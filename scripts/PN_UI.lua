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

PN_UI = PN_UI or {}
PN_UI.cfg = PN_UI.cfg or {
  useSupplyFactor = true,
  refreshThrottleMs = 1000,     -- 0 = no throttle (refresh every frame)
  addSpacerBetweenBarns = true,
}

-- Let PN_Settings override defaults if present
if PN_Settings and PN_Settings.ui then
  if PN_Settings.ui.overlayRefreshMs ~= nil then
    PN_UI.cfg.refreshThrottleMs = tonumber(PN_Settings.ui.overlayRefreshMs) or PN_UI.cfg.refreshThrottleMs
  end
  if PN_Settings.ui.addSpacerBetweenBarns ~= nil then
    PN_UI.cfg.addSpacerBetweenBarns = (PN_Settings.ui.addSpacerBetweenBarns == true)
  end
end
if PN_Settings and PN_Settings.adg and PN_Settings.adg.useSupplyFactor ~= nil then
  PN_UI.cfg.useSupplyFactor = (PN_Settings.adg.useSupplyFactor == true)
end

local function _nowMs()
  if g_currentMission and g_currentMission.time then return g_currentMission.time end
  if getTimeMs then return getTimeMs() end
  return (os.time() or 0) * 1000
end

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
  local subj = (entry and entry.placeable) or entry
  local t = (subj and subj.__pn_totals) or entry.__pn_totals or {}
  if (not t or next(t) == nil) and PN_Core and PN_Core.getTotals and subj then
    local okT, tt = pcall(PN_Core.getTotals, subj)
    if okT and type(tt) == "table" then t = tt end
  end
  local head = tonumber(t.animals or t.head or 0) or 0
  local DMIperHead = tonumber(t.DMIt or t.intakeKgHd or 0) or 0
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



local function _dmDemandKgHd(species, stage)
  if PN_Core and PN_Core.nutritionForStage then
    local okN, row = pcall(PN_Core.nutritionForStage, PN_Core, species, stage)
    if okN and type(row)=="table" then
      local v = tonumber(row.dmDemandKgHd or row.intakeKgHd or 0)
      if v and v > 0 then return v end
    end
  end
  return 0
end

local function _barnAvailableDmKg(entry)
  local p = entry and entry.placeable
  if not p then return 0 end
  local total = 0

  -- Prefer spec_fillUnit if present (per-unit per-fillType levels)
  if p.spec_fillUnit and p.spec_fillUnit.fillUnits then
    for _, fu in ipairs(p.spec_fillUnit.fillUnits) do
      local levels = fu and fu.fillLevels
      if type(levels) == "table" then
        for ftIndex, L in pairs(levels) do
          local liters = tonumber(L or 0) or 0
          if liters > 0 then
            local mpl = 1.0
            if g_fillTypeManager and g_fillTypeManager.fillTypes and g_fillTypeManager.fillTypes[ftIndex] then
              mpl = tonumber(g_fillTypeManager.fillTypes[ftIndex].massPerLiter or 1.0) or 1.0
            end
            local name = _ftNameByIndex(ftIndex)
            local token = _u(name)
            if PN_Core and PN_Core.feedAliases and PN_Core.feedAliases[token] then
              token = _u(PN_Core.feedAliases[token])
            end
            local fmRow = PN_Core and PN_Core.feedMatrix and PN_Core.feedMatrix[token] or nil
            local dmFrac = (fmRow and fmRow.dm) and tonumber(fmRow.dm) or 0
            total = total + (liters * mpl * dmFrac)
          end
        end
      end
    end
  end

  -- Fallback: spec_husbandryFood.fillLevels (aggregate liters by FT)
  if total == 0 and p.spec_husbandryFood and p.spec_husbandryFood.fillLevels then
    for ftIndex, L in pairs(p.spec_husbandryFood.fillLevels) do
      local liters = tonumber(L or 0) or 0
      if liters > 0 then
        local mpl = 1.0
        if g_fillTypeManager and g_fillTypeManager.fillTypes and g_fillTypeManager.fillTypes[ftIndex] then
          mpl = tonumber(g_fillTypeManager.fillTypes[ftIndex].massPerLiter or 1.0) or 1.0
        end
        local name = _ftNameByIndex(ftIndex)
        local token = _u(name)
        if PN_Core and PN_Core.feedAliases and PN_Core.feedAliases[token] then
          token = _u(PN_Core.feedAliases[token])
        end
        local fmRow = PN_Core and PN_Core.feedMatrix and PN_Core.feedMatrix[token] or nil
        local dmFrac = (fmRow and fmRow.dm) and tonumber(fmRow.dm) or 0
        total = total + (liters * mpl * dmFrac)
      end
    end
  end

  return total
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

  -- Compute live supply factor from trough: available DM vs today's requirement (0..1)
  local supplyF = 1.0
  if PN_UI.cfg.useSupplyFactor then
    supplyF = (function()
      local avail = _barnAvailableDmKg(e)
      local req = 0
      req = req + _dmDemandKgHd(species, "LACT") * (derived.femaleOpen.n or 0)
      req = req + _dmDemandKgHd(species, "GEST") * (derived.femalePreg.n or 0)
      req = req + _dmDemandKgHd(species, "BULL") * (derived.male.n       or 0)
      if req <= 0 then return 1.0 end
      local f = avail / req
      if f < 0 then f = 0 elseif f > 1 then f = 1 end
      return f
    end)()
  end

  -- Helper to extract a live group snapshot or fallback
  local function snap(key, fallbackStage)
    local gtbl = e.__pn_groups or {}
    local s = gtbl[key]                          -- snapshot (may exist but n==0)
    local d = derived[key] or { n=0, preg=0, avgW=0 }  -- live derived

	-- Barn-level Nut ratio (0..1): prefer WRAPPER snapshot, then totals (on wrapper)
	local barnNut = 0
	if e and e.__pn_last and e.__pn_last.nutRatio ~= nil then
		barnNut = tonumber(e.__pn_last.nutRatio) or 0
	elseif PN_Core and PN_Core.getTotals then
		local okT, totals = pcall(PN_Core.getTotals, e)
		if okT and type(totals) == "table" then
			barnNut = tonumber(totals.nut or 0) or 0
		end
	end
if barnNut < 0 then barnNut = 0 elseif barnNut > 1 then barnNut = 1 end
-- Logging.info("[PN] UI Nut check: barnNut=%.3f (e=%s)", barnNut, tostring(e and e.name))

    -- Stage (normalize to model’s expectations)
    local sex    = (key == "male") and "male" or "female"
    local isPreg = (key == "femalePreg")
    local stage  = fallbackStage or "?"
    if PN_Core and PN_Core.stageLabel then
      local okS, lbl = pcall(PN_Core.stageLabel, PN_Core, species, sex, isPreg)
      if okS and type(lbl) == "string" and lbl ~= "" then stage = lbl end
    end
    -- Normalize for cows; generic for others
    if (tostring(species or ""):upper() == "COW") then
      if key == "femaleOpen" then stage = "LACT"
      elseif key == "femalePreg" then stage = "GEST"
      elseif key == "male" then stage = "BULL" end
    else
      if key == "male" then stage = "MALE"
      elseif key == "femalePreg" then stage = "PREG"
      else stage = "FEMALE" end
    end

    -- Choose the source of headcount & avgW:
    -- If snapshot exists AND has n>0, use it; otherwise prefer live derived
    local n, preg, avgW = 0, 0, 0
    if s and ((tonumber(s.n or 0) or 0) > 0) then
      n    = tonumber(s.n or 0) or 0
      preg = tonumber(s.preg or 0) or 0
      avgW = tonumber(s.avgW or 0) or 0
    else
      n    = tonumber(d.n or 0) or 0
      preg = tonumber(d.preg or 0) or 0
      avgW = tonumber(d.avgW or 0) or 0
    end

    -- Base ADG from model (base × nut)
    local adg = 0.10 * barnNut
    if PN_Core and PN_Core.adgFor then
      local okG, g = pcall(PN_Core.adgFor, PN_Core, species, stage, avgW, barnNut)
      if okG and type(g) == "number" then adg = g end
    end

    -- Maturity taper (same as in PN_Core.updateHusbandry)
    do
      local mk
      if PN_Core and PN_Core.meta then
        local m = PN_Core.meta[(tostring(species or "COW")):upper()]
        mk = m and tonumber(m.matureKg)
      end
      if mk and mk > 0 and avgW > 0 then
        local frac    = math.max(0, math.min(1, avgW / mk))
        local reserve = math.max(0.10, 1.0 - (frac ^ 1.6))
        adg = adg * reserve
      end
    end

    -- Apply live supply factor for the barn (computed once per barn above)
	adg = adg * (supplyF or 1.0)

	-- Optional negative ADG when supply is short
	local allowNeg = (PN_Settings and PN_Settings.adg and PN_Settings.adg.allowNegative == true)
	if allowNeg then
	  local deficit = 1 - (supplyF or 1.0)
	  if deficit > 0 then
		local penalty = ((PN_Settings.adg.starvationPenaltyKg or 0.05) * deficit)
		adg = adg - penalty
	  end
	else
	  if adg < 0 then adg = 0 end
	end

    return { n = n, preg = preg, avgW = avgW, nut = barnNut, adg = adg, stage = stage }
  end

  -- Compose lines
  local femaleOpen = snap("femaleOpen", (PN_Core and PN_Core.stageLabel and PN_Core:stageLabel(species,"female",false)) or "OPEN")
  local femalePreg = snap("femalePreg", (PN_Core and PN_Core.stageLabel and PN_Core:stageLabel(species,"female",true )) or "PREG")
  local male       = snap("male",       (PN_Core and PN_Core.stageLabel and PN_Core:stageLabel(species,"male",  false)) or "MALE")

  if femaleOpen and (tonumber(femaleOpen.n) or 0) > 0 then
    table.insert(rows, { gender="femaleOpen",
      text = string.format("%s [%s/female-open] | stage=%s | head=%d preg=%d | avgW=%.2fkg | Nut=%d%% | ADG=%.3f kg/d",
        name, species, tostring(femaleOpen.stage or "?"),
        tonumber(femaleOpen.n or 0), tonumber(femaleOpen.preg or 0),
        tonumber(femaleOpen.avgW or 0),
        math.floor((tonumber(femaleOpen.nut or 0) * 100) + 0.5),
        tonumber(femaleOpen.adg or 0))
    })
  end

  if femalePreg and (tonumber(femalePreg.n) or 0) > 0 then
    table.insert(rows, { gender="femalePreg",
      text = string.format("%s [%s/female-preg] | stage=%s | head=%d preg=%d | avgW=%.2fkg | Nut=%d%% | ADG=%.3f kg/d",
        name, species, tostring(femalePreg.stage or "?"),
        tonumber(femalePreg.n or 0), tonumber(femalePreg.preg or 0),
        tonumber(femalePreg.avgW or 0),
        math.floor((tonumber(femalePreg.nut or 0) * 100) + 0.5),
        tonumber(femalePreg.adg or 0))
    })
  end

  if male and (tonumber(male.n) or 0) > 0 then
    table.insert(rows, { gender="male",
      text = string.format("%s [%s/male] | stage=%s | head=%d | avgW=%.2fkg | Nut=%d%% | ADG=%.3f kg/d",
        name, species, tostring(male.stage or "?"),
        tonumber(male.n or 0), tonumber(male.avgW or 0),
        math.floor((tonumber(male.nut or 0) * 100) + 0.5),
        tonumber(male.adg or 0))
    })
  end

  return rows
end

-- ---- live fallback rows (scan + cluster data; no strict isReady gating) ----
local function buildFallbackRows()
  local nowMs = _nowMs()
  local refreshMs = tonumber(PN_UI.cfg.refreshThrottleMs or 0) or 0
  local doRefresh = (refreshMs <= 0) or (nowMs >= (PN_UI._nextRefreshAt or 0))
  if doRefresh and refreshMs > 0 then
    PN_UI._nextRefreshAt = nowMs + refreshMs
  end

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
      -- LIVE refresh snapshot (match pnBeat) — throttled
      if doRefresh and PN_Core and PN_Core.updateHusbandry and e and e.clusterSystem ~= nil then
        pcall(PN_Core.updateHusbandry, PN_Core, e, e.clusterSystem, 33, { source = "overlay" })
      end

	  -- ANIMAL split rows first (keep your existing order)
	  local splitRows = makeSplitRows(e)
	  for _, r in ipairs(splitRows) do
		table.insert(rows, r)
	  end

	  -- FEED summary after animals (as you set it)
	  local feedLines = PN_UI._feedSummaryLines(e)
	  for _, s in ipairs(feedLines) do
		table.insert(rows, { gender = "feed", text = s })
	  end
	  
	  table.insert(rows, { gender = "feed", text = " " })
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
