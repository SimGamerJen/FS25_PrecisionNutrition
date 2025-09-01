-- FS25_PrecisionNutrition / scripts / PN_UI.lua
-- Overlay: Alt+N toggle + "My Farm Only" filter, split female/male rows,
-- pregnancy counts, and live trough summary (DM & days left).

PN_UI = {
  enabled     = false,   -- OFF by default; Alt+N toggles
  barns       = {},      -- optional push buffer (kept for future nutrition UI)
  onlyMyFarm  = true,    -- default: show only barns I own
  _debounce   = 0,
  _rescanOnce = false,   -- trigger one rescan if list is empty
}

-- --- farm helpers ---
local function _getMyFarmId()
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
-- Replace Unicode glyphs that aren't in the FS texture font
local function _ascii(s)
  s = tostring(s or "")
  s = s:gsub("•", "-")
  s = s:gsub("≈", "~")
  return s
end

local function drawLine(x, y, s)
  if renderText ~= nil then renderText(x, y, 0.014, _ascii(s)) end
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

-- ---------- feed display helpers ----------
local function _ftNameByIndex(idx)
  if g_fillTypeManager and g_fillTypeManager.getFillTypeNameByIndex then
    local n = g_fillTypeManager:getFillTypeNameByIndex(idx)
    if n and n ~= "" then return n end
  end
  return tostring(idx)
end

local function _massPerLiter(idx)
  if g_fillTypeManager and g_fillTypeManager.fillTypes and g_fillTypeManager.fillTypes[idx] then
    return g_fillTypeManager.fillTypes[idx].massPerLiter or 1
  end
  return 1
end

local function _u(s) return tostring(s or ""):upper() end

local function _nfmt(x, p)
  x = tonumber(x or 0) or 0
  local m = 10 ^ (p or 0)
  return math.floor(x * m + 0.5) / m
end

-- Build per-barn feed summary lines:
--  • total DM in trough
--  • ≈ days of feed left at current demand
--  • top 3 feed lines by DM contribution (name, liters, ~DM kg)
function PN_UI._feedSummaryLines(entry)
  local lines = {}
  local p = entry and entry.placeable
  local spec = p and p.spec_husbandryFood
  if not (spec and type(spec.fillLevels) == "table") then
    return lines
  end

  -- Collect items
  local items = {}
  local totalDmKg = 0
  for ftIndex, liters in pairs(spec.fillLevels) do
    local L = tonumber(liters or 0) or 0
    if L > 0 then
      local name = _ftNameByIndex(ftIndex)
      local kgAsFed = L * _massPerLiter(ftIndex)

      -- Map to PN feed token to get DM fraction (and aliases)
      local token = _u(name)
      if PN_Core and PN_Core.feedAliases and PN_Core.feedAliases[token] then
        token = _u(PN_Core.feedAliases[token])
      end
      local fmRow = PN_Core and PN_Core.feedMatrix and PN_Core.feedMatrix[token] or nil
      local dmFrac = (fmRow and fmRow.dm) and tonumber(fmRow.dm) or 0
      local dmKg = kgAsFed * dmFrac

      totalDmKg = totalDmKg + dmKg
      table.insert(items, { name = name, liters = L, dmKg = dmKg })
    end
  end

  -- Sort by DM contribution desc
  table.sort(items, function(a,b) return (a.dmKg or 0) > (b.dmKg or 0) end)

  -- Days of feed left at current demand (use PN totals snapshot)
  local t = entry.__pn_totals or {}
  local head = tonumber(t.animals or 0) or 0
  local DMIperHead = tonumber(t.DMIt or 0) or 0   -- per-head daily DM target captured by PN_Core
  local reqPerDay = DMIperHead * head
  local daysLeft = (reqPerDay > 0) and (totalDmKg / reqPerDay) or 0

  table.insert(lines, string.format("   DM in trough: %s kg  (≈ %s d @ current demand)",
      _nfmt(totalDmKg, 0), _nfmt(daysLeft, 2)))

  local show = 0
  for _, it in ipairs(items) do
    if it.liters > 0 and show < 3 then
      table.insert(lines, string.format("   • %s: %s L  (~%s kg DM)",
          tostring(it.name), _nfmt(it.liters, 0), _nfmt(it.dmKg, 0)))
      show = show + 1
    end
  end

  return lines
end

-- Build three lines (female-open, female-preg, male) using per-group snapshot when available.
local function makeSplitRows(e)
  local rows = {}
  local name    = tostring(e.name or "?")
  local species = inferSpecies(e)

  -- Prefer PN_Core per-group snapshot if present
  local g = e.__pn_groups or {}

  -- If the core hasn’t populated yet, derive counts from clusters
  local derived = {
    femaleOpen = { n=0, preg=0, avgW=0 },
    femalePreg = { n=0, preg=0, avgW=0 },
    male       = { n=0, preg=0, avgW=0 },
  }
  do
    local cs = e and e.clusterSystem
    if cs and cs.getClusters then
      local ok, clusters = pcall(cs.getClusters, cs)
      if ok and type(clusters) == "table" then
        local wSum = { femaleOpen=0, femalePreg=0, male=0 }
        for _, c in pairs(clusters) do
          if type(c) == "table" and not c.isDead then
            local gsex = tostring(c.gender or ""):lower()
            local w    = tonumber(c.weight or 0) or 0
            if gsex == "female" then
              if c.isPregnant then
                derived.femalePreg.n  = derived.femalePreg.n + 1
                derived.femalePreg.preg = derived.femalePreg.preg + 1
                wSum.femalePreg = wSum.femalePreg + w
              else
                derived.femaleOpen.n  = derived.femaleOpen.n + 1
                wSum.femaleOpen = wSum.femaleOpen + w
              end
            elseif gsex == "male" then
              derived.male.n = derived.male.n + 1
              wSum.male = wSum.male + w
            end
          end
        end
        if derived.femaleOpen.n > 0 then derived.femaleOpen.avgW = wSum.femaleOpen / derived.femaleOpen.n end
        if derived.femalePreg.n > 0 then derived.femalePreg.avgW = wSum.femalePreg / derived.femalePreg.n end
        if derived.male.n       > 0 then derived.male.avgW       = wSum.male       / derived.male.n       end
      end
    end
  end

  -- Helper to extract a live group snapshot or fallback
  local function snap(key, fallbackStage)
    local s = g[key]
    if s then
      return {
        n    = tonumber(s.n or 0) or 0,
        preg = tonumber(s.preg or 0) or 0,
        avgW = tonumber(s.avgW or 0) or 0,
        nut  = tonumber(s.nut or 0) or 0,
        adg  = tonumber(s.adg or 0) or 0,
        stage= tostring(s.stage or fallbackStage or "?"),
      }
    else
      local d = derived[key] or { n=0, preg=0, avgW=0 }
      return {
        n=d.n, preg=d.preg, avgW=d.avgW, nut=0, adg=0,
        stage=fallbackStage or "?"
      }
    end
  end

  local femaleOpen = snap("femaleOpen", (PN_Core and PN_Core.stageLabel and PN_Core:stageLabel(species,"female",false)) or "OPEN")
  local femalePreg = snap("femalePreg", (PN_Core and PN_Core.stageLabel and PN_Core:stageLabel(species,"female",true )) or "PREG")
  local male       = snap("male",       (PN_Core and PN_Core.stageLabel and PN_Core:stageLabel(species,"male",  false)) or "MALE")

  -- Compose lines
  if femaleOpen.n > 0 then
    table.insert(rows, { gender="femaleOpen",
      text = string.format("%s [%s/female-open] | stage=%s | head=%d preg=%d | avgW=%.2fkg | Nut=%d%% | ADG=%.3f kg/d",
        name, species, femaleOpen.stage, femaleOpen.n, femaleOpen.preg, femaleOpen.avgW,
        math.floor(femaleOpen.nut*100 + 0.5), femaleOpen.adg)
    })
  end

  if femalePreg.n > 0 then
    table.insert(rows, { gender="femalePreg",
      text = string.format("%s [%s/female-preg] | stage=%s | head=%d preg=%d | avgW=%.2fkg | Nut=%d%% | ADG=%.3f kg/d",
        name, species, femalePreg.stage, femalePreg.n, femalePreg.preg, femalePreg.avgW,
        math.floor(femalePreg.nut*100 + 0.5), femalePreg.adg)
    })
  end

  if male.n > 0 then
    table.insert(rows, { gender="male",
      text = string.format("%s [%s/male] | stage=%s | head=%d | avgW=%.2fkg | Nut=%d%% | ADG=%.3f kg/d",
        name, species, male.stage, male.n, male.avgW,
        math.floor(male.nut*100 + 0.5), male.adg)
    })
  end

  if #rows == 0 then
    -- empty pen line (kept)
    table.insert(rows, { gender="any",
      text = string.format("%s [%s] | head=0 preg=0 | avgW=0.00kg | Nut=0%% | ADG=0.000 kg/d",
                           name, species)
    })
  end

  -- Feed summary (unchanged)
  local feedLines = PN_UI._feedSummaryLines(e)
  for _, L in ipairs(feedLines) do
    table.insert(rows, { gender="feed", text=L })
  end

  return rows
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
      -- Only filter out when BOTH ids are known and different
      if (farmId ~= nil) and (myId ~= nil) and (farmId ~= myId) then
        filteredOut = true
      end
    end

    if not filteredOut then
      local splitRows = makeSplitRows(e)
      for _, r in ipairs(splitRows) do
        table.insert(rows, r) -- keep gender tag for coloring later
      end
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
  local ac   = (PN_Core and PN_Core.autoConsume) and "AC:ON" or "AC:OFF"

  setTextBold(true)
  setTextColor(1,1,0.6,1)
  drawLine(x, y, string.format("[PN] Precision Nutrition Overlay (Alt+N) – %s  [%s]", mode, ac))
  setTextBold(false)
  y = y - 0.022

  local showedAny = false
  -- First, any pushed stats (unchanged)
  for _, v in pairs(PN_UI.barns) do
    setTextColor(1,1,1,1)
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
    if #rows == 0 then
      setTextColor(0.8, 0.6, 0.6, 1)
      drawLine(x, y, "(no animal barns detected for this filter)")
      return
    end
    for _, r in ipairs(rows) do
      -- Color coding: female = soft pink, male = soft blue, feed = soft green, any = white
		if r.gender == "femaleOpen" then
		  setTextColor(1.00, 0.88, 0.95, 1)   -- pale pink
		elseif r.gender == "femalePreg" then
		  setTextColor(1.00, 0.75, 0.90, 1)   -- stronger pink for pregnant
		elseif r.gender == "male" then
		  setTextColor(0.85, 0.90, 1.00, 1)   -- soft blue
		elseif r.gender == "feed" then
		  setTextColor(0.80, 1.00, 0.80, 1)   -- soft green
		else
		  setTextColor(1, 1, 1, 1)
		end
      drawLine(x, y, r.text)
      y = y - 0.018
      if y < 0.05 then break end
    end
  end
end

return PN_UI
