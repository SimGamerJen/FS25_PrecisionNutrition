-- FS25_PrecisionNutrition / scripts / PN_UI.lua
-- Clean, robust overlay: Alt+N toggle + live fallback from PN_HusbandryScan.

PN_UI = {
  enabled   = false,   -- OFF by default; Alt+N toggles
  barns     = {},      -- optional push buffer (kept for future nutrition UI)
  onlyMyFarm = true,  -- default: show only barns I own
  _debounce = 0,
  _rescanOnce = false, -- trigger one rescan if list is empty
}

-- --- farm helpers ---
local function _getMyFarmId()
  -- Try common places to read the local player's farm id
  if g_currentMission ~= nil then
    if g_currentMission.player ~= nil and g_currentMission.player.farmId ~= nil then
      return g_currentMission.player.farmId
    end
    if g_currentMission.getFarmId ~= nil then
      local ok, id = pcall(g_currentMission.getFarmId, g_currentMission)
      if ok and id ~= nil then return id end
    end
  end
  if g_farmManager ~= nil and g_farmManager.getActiveFarmId ~= nil then
    local ok, id = pcall(g_farmManager.getActiveFarmId, g_farmManager)
    if ok and id ~= nil then return id end
  end
  return 1 -- sensible fallback for SP
end

local function _getEntryFarmId(e)
  if e == nil then return nil end
  if e.farmId ~= nil then return e.farmId end
  if e.placeable ~= nil then
    if e.placeable.ownerFarmId ~= nil then return e.placeable.ownerFarmId end
    if e.placeable.getOwnerFarmId ~= nil then
      local ok, id = pcall(e.placeable.getOwnerFarmId, e.placeable)
      if ok then return id end
    end
  end
  return nil
end

-- ---- tiny helpers ----
local function drawLine(x, y, s)
  if renderText ~= nil then renderText(x, y, 0.014, s) end
end

local function nfmt(v, d)
  return string.format("%."..tostring(d or 0).."f", tonumber(v or 0) or 0)
end

-- ---- toggle & key polling (Alt+N) ----
function PN_UI.toggle()
  PN_UI.enabled = not PN_UI.enabled
  Logging.info("[PN] Overlay %s", PN_UI.enabled and "ON" or "OFF")
end

local function pollToggleKey(dt)
  PN_UI._debounce = math.max(0, (PN_UI._debounce or 0) - (dt or 0))
  if PN_UI._debounce > 0 then return end
  if Input and Input.isKeyPressed then
    local alt = Input.isKeyPressed(Input.KEY_lalt) or Input.isKeyPressed(Input.KEY_ralt)
    local n   = Input.isKeyPressed(Input.KEY_n)
    if alt and n then
      PN_UI._debounce = 300 -- ms
      PN_UI.toggle()
    end
  end
end

-- ---- optional: external push API (kept) ----
function PN_UI.pushBarnStat(owner, name, stats)
  local id = tostring(owner or "barn")
  PN_UI.barns[id] = {
    name    = name or ("Barn@"..id),
    adg     = stats.adg or 0,
    intake  = stats.intakePH or 0,
    balance = stats.balance or 0,
    forage  = stats.forageShare or 0,
    stage   = stats.stage or "?",
    n       = stats.n or 0,
    species = stats.species or "ANIMAL"
  }
end

-- ---- local species inference (no PN_Core dependency) ----
local function inferSpecies(e)
  local function norm(s)
    s = tostring(s or ""):upper()
    if s == "CATTLE" then return "COW" end
    if s == "HEN" then return "CHICKEN" end
    return s
  end
  if e and e.type and e.type ~= "ANIMAL" then return norm(e.type) end
  local cs = e and e.clusterSystem
  if cs and cs.getClusters then
    local ok, clusters = pcall(cs.getClusters, cs)
    if ok and type(clusters) == "table" then
      for _, c in pairs(clusters) do
        local st = tostring(c and c.subType or ""):upper()
        if st:find("COW",1,true) or st:find("BULL",1,true) then return "COW" end
        if st:find("SHEEP",1,true) then return "SHEEP" end
        if st:find("PIG",1,true) then return "PIG" end
        if st:find("GOAT",1,true) then return "GOAT" end
        if st:find("CHICK",1,true) or st:find("HEN",1,true) then return "CHICKEN" end
      end
    end
  end
  return "ANIMAL"
end

-- ---- live fallback rows (scan + cluster data; no strict isReady gating) ----
local function buildFallbackRows()
  local rows = {}
  if not PN_HusbandryScan then return rows end

  local getAll = PN_HusbandryScan.getAll
  if type(getAll) ~= "function" then return rows end

  local list = getAll()
  if type(list) ~= "table" or next(list) == nil then
    -- Try one rescan the first time we discover empty list (prevents spam)
    if not PN_UI._rescanOnce and PN_HusbandryScan.rescan then
      PN_UI._rescanOnce = true
      pcall(PN_HusbandryScan.rescan, PN_HusbandryScan)
      list = getAll() or {}
    else
      return rows
    end
  end

  for _, e in ipairs(list) do
    local filteredOut = false
    if PN_UI.onlyMyFarm then
      local myId   = _getMyFarmId()
      local farmId = _getEntryFarmId(e)
      if (farmId ~= nil) and (myId ~= nil) and (farmId ~= myId) then
        filteredOut = true
      end
    end

    if not filteredOut then
      local name    = tostring(e.name or "?")
      local species = inferSpecies(e)

      -- Prefer totals from core if present
      local t = e.__pn_totals
      if not t then
        t = { animals=0, bulls=0, cows=0, pregnant=0, weightSum=0, avgWeight=0 }
        local cs = e.clusterSystem
        if cs and cs.getClusters then
          local ok, clusters = pcall(cs.getClusters, cs)
          if ok and type(clusters) == "table" then
            for _, c in pairs(clusters) do
              if type(c) == "table" and not c.isDead then
                t.animals = t.animals + 1
                local g = tostring(c.gender or ""):lower()
                if g == "male" then t.bulls = t.bulls + 1 end
                if g == "female" then
                  t.cows = t.cows + 1
                  if c.isPregnant then t.pregnant = t.pregnant + 1 end
                end
                t.weightSum = (t.weightSum or 0) + (tonumber(c.weight or 0) or 0)
              end
            end
            if t.animals > 0 and (t.weightSum or 0) > 0 then
              t.avgWeight = t.weightSum / t.animals
            end
          end
        end
      end

      table.insert(rows, string.format(
        "%s [%s] | head=%d (M:%d/F:%d, preg=%d) avgW=%skg",
        name, species, t.animals or 0, t.bulls or 0, t.cows or 0, t.pregnant or 0, nfmt(t.avgWeight, 1)
      ))
    end
  end

  return rows
end

-- ---- hooks from PN_Load ----
function PN_UI.onUpdate(dt) pollToggleKey(dt) end

function PN_UI.onDraw()
  if not PN_UI.enabled then return end
  local x, y = 0.02, 0.95
  local mode = (PN_UI.onlyMyFarm and "My Farm Only" or "All Farms")
  drawLine(x, y, string.format("[PN] Precision Nutrition Overlay (Alt+N) – %s", mode))
  y = y - 0.02

  local showedAny = false
  for _, v in pairs(PN_UI.barns) do
    local line = string.format(
      "%s [%s] | Head=%d | Stage=%s | ADG=%s kg/d | Intake=%s /hd/d | Balance=%s | Forage=%s%%",
      tostring(v.name or "?"),
      tostring(v.species or "ANIMAL"),
      tonumber(v.n or 0),
      tostring(v.stage or "?"),
      nfmt(v.adg, 2), nfmt(v.intake, 1), nfmt(v.balance, 2), nfmt((v.forage or 0)*100, 0)
    )
    drawLine(x, y, line); y = y - 0.018
    showedAny = true
    if y < 0.05 then break end
  end

  if not showedAny then
    local rows = buildFallbackRows()
    for _, line in ipairs(rows) do
      drawLine(x, y, line); y = y - 0.018
      if y < 0.05 then break end
    end
  end
end

return PN_UI
