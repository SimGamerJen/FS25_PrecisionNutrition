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
  preferLiveRows = true,
}
-- Single-barn overlay cycling state
PN_UI.mode       = PN_UI.mode or "list"   -- "list" (current: all barns) or "single" (one barn)
PN_UI._barnList  = PN_UI._barnList or nil -- cached, filtered barn list
PN_UI._barnIdx   = PN_UI._barnIdx or 0    -- 1-based index into _barnList

-- Let PN_Settings override defaults if present

-- === Overlay appearance & palette ===========================================
PN_UI.palette = PN_UI.palette or {
  bg      = {0, 0, 0, 0.40},       -- semi-opaque panel
  text    = {0.95, 0.98, 1.0, 1.0},
  header  = {1.00, 1.00, 1.00, 1.0},
  warn    = {1.00, 0.75, 0.20, 1.0},
  feed    = {0.35, 0.85, 0.45, 1.0},
  female1 = {1.00, 0.88, 0.95, 1.0},  -- female-open
  female2 = {1.00, 0.55, 0.80, 1.0},  -- female-preg
  male    = {0.20, 0.60, 0.95, 1.0},  -- male blue
  calf    = {1.00, 0.85, 0.10, 1.0},  -- calf yellow (reserved)
}

PN_UI.ov = PN_UI.ov or {
  anchor   = "tl",     -- tl | tr | bl | br
  alpha    = 0.60,
  fontSize = 0.014,
  rowH     = 0.018,
  padX     = 0.010,
  padY     = 0.010,
  maxRows  = nil,		-- optional max row clamp
  marginX  = 0.020,    -- your chosen defaults
  marginY  = 0.030,
  fixedW   = 0.55,      -- optional fixed width (screen units, 0..1) or nil for auto
  minW     = nil,      -- optional min width clamp
  maxW     = nil,      -- optional max width clamp
}

-- Measure width from header + rows (approx chars → screen units)
local function _pn_measureWidth(header, rows)
  local maxChars = math.max(#tostring(header or ""), 24)
  for _, r in ipairs(rows or {}) do
    local t = tostring(r.text or "")
    if #t > maxChars then maxChars = #t end
  end
  local approxCharW = 0.0075  -- tuned for FS font
  return maxChars * approxCharW + 0.06
end
-- ============================================================================
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

local function drawLine(x, y, s, fs)
  if renderText ~= nil then
    local size = fs or (PN_UI and PN_UI.ov and PN_UI.ov.fontSize) or 0.014
    renderText(x, y, size, _ascii(s))
  end
end

local function nfmt(v, d)
  return string.format("%."..tostring(d or 0).."f", tonumber(v or 0) or 0)
end

-- ---- overlay toggle & key polling (Alt+N open/close; Alt+B prev, Alt+M next) ----
function PN_UI.toggle()
  PN_UI.enabled = not PN_UI.enabled
  Logging.info("[PN] Overlay %s", PN_UI.enabled and "ON" or "OFF")
end

function PN_UI.nextBarn()
  if not PN_UI.enabled then return end
  PN_UI.mode = "single"
  local list = PN_UI._barnList or PN_UI.buildBarnList()
  if #list == 0 then return end
  local idx = (PN_UI._barnIdx or 0) + 1
  if idx > #list then idx = 1 end
  PN_UI._selectBarn(idx)
end

function PN_UI.prevBarn()
  if not PN_UI.enabled then return end
  PN_UI.mode = "single"
  local list = PN_UI._barnList or PN_UI.buildBarnList()
  if #list == 0 then return end
  local idx = (PN_UI._barnIdx or 2) - 1
  if idx < 1 then idx = #list end
  PN_UI._selectBarn(idx)
end

local function pollOverlayKeys(dt)
  PN_UI._debounce = math.max(0, (PN_UI._debounce or 0) - (dt or 0))
  if PN_UI._debounce > 0 then return end
  if not (Input and Input.isKeyPressed) then return end

  local alt = Input.isKeyPressed(Input.KEY_lalt) or Input.isKeyPressed(Input.KEY_ralt)
  if not alt then return end

  -- Alt+N: toggle overlay on/off
  if Input.isKeyPressed(Input.KEY_n) then
    PN_UI._debounce = 250
    PN_UI.toggle()
    return
  end

  -- While overlay is ON: Alt+M -> next, Alt+B -> prev
  if not PN_UI.enabled then return end

  if Input.isKeyPressed(Input.KEY_m) then
    PN_UI._debounce = 150
    PN_UI.nextBarn()
    return
  end

  if Input.isKeyPressed(Input.KEY_b) then
    PN_UI._debounce = 150
    PN_UI.prevBarn()
    return
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

  if e and e.type and e.type ~= "ANIMAL" then
    return norm(e.type)
  end

  local cs = e and e.clusterSystem
  if cs and cs.getClusters then
    local ok, clusters = pcall(cs.getClusters, cs)
    if ok and type(clusters) == "table" then
      for _, c in pairs(clusters) do
        local st = tostring(c and (c.subType or c.typeName or c.role) or ""):upper()
        -- CATTLE
        if st:find("COW",1,true) or st:find("BULL",1,true) or st:find("HEIFER",1,true) or st:find("STEER",1,true) then
          return "COW"
        end
        -- SHEEP
        if st:find("SHEEP",1,true) or st:find("EWE",1,true) or st:find("RAM",1,true) or st:find("LAMB",1,true) then
          return "SHEEP"
        end
        -- PIGS
        if st:find("PIG",1,true) or st:find("HOG",1,true) or st:find("SOW",1,true) or st:find("GILT",1,true)
           or st:find("BOAR",1,true) or st:find("BARROW",1,true) then
          return "PIG"
        end
        -- GOATS
        if st:find("GOAT",1,true) or st:find("DOE",1,true) or st:find("BUCK",1,true) or st:find("KID",1,true) then
          return "GOAT"
        end
        -- CHICKENS
        if st:find("CHICK",1,true) or st:find("HEN",1,true) or st:find("ROOSTER",1,true)
           or st:find("LAYER",1,true) or st:find("BROILER",1,true) then
          return "CHICKEN"
        end
      end
    end
  end

  return "ANIMAL"
end

-- Infer gender from RL-style subtype tokens when explicit gender is missing
local function inferGenderFromSubtype(species, subTL)
  species = tostring(species or "ANIMAL"):upper()
  subTL   = tostring(subTL or ""):lower()

  if species == "COW" then
    if subTL:find("bull",   1, true) or subTL:find("steer", 1, true) then return "male"   end
    if subTL:find("cow",    1, true) or subTL:find("heifer",1, true)   then return "female" end

  elseif species == "SHEEP" then
    if subTL:find("ram",    1, true) then return "male"   end
    if subTL:find("ewe",    1, true) then return "female" end

  elseif species == "PIG" then
    -- 'barrow' is a castrated male
    if subTL:find("boar",   1, true) or subTL:find("barrow", 1, true) then return "male"   end
    if subTL:find("gilt",   1, true) or subTL:find("sow",    1, true) then return "female" end

  elseif species == "GOAT" then
    if subTL:find("buck",   1, true) then return "male"   end
    if subTL:find("doe",    1, true) then return "female" end

  elseif species == "CHICKEN" then
    if subTL:find("rooster",1, true) or subTL:find("broiler_m",1,true) then return "male"   end
    if subTL:find("hen",    1, true) or subTL:find("layer",   1,true)
       or subTL:find("broiler_f",1,true) then return "female" end
  end
  return nil
end

-- ---------- stage helpers (display-only; no overlay settings changed) ----------
PN_UI.stageOrder = PN_UI.stageOrder or {
  COW     = { CALF=1, HEIFER=2, LACT=3, DRY=4, YEARLING=5, STEER=6, BULL=7, OVERAGE=8, DEFAULT=99 },
  SHEEP   = { LAMB=1, WEANER=2, EWE_LACT=3, EWE_DRY=4, RAM_GROW=5, WETHER_FINISH=6, RAM_ADULT=7, DEFAULT=99 },
  PIG 	  = { PIGLET=1, WEANER=2, GROWER=3, GILT=4, SOW_LACT=5, SOW_DRY=6, SOW_GEST=7, FINISHER=8, BARROW=9, BOAR=10, DEFAULT=99 },
  GOAT    = { KID=1, DOE_LACT=2, DOE_DRY=3, BUCK_GROW=4, BUCK_ADULT=5, DEFAULT=99 },
  CHICKEN = { CHICK=1, BROILER_F=2, LAYER=3, BROILER_M=4, ROOSTER=5, DEFAULT=99 },
  ANIMAL  = { DEFAULT=1 }
}

-- small cache for stage bands
PN_UI._stagesCache = PN_UI._stagesCache or {}
local function _ageMonths(c)
  if not c then return nil end

  -- 1) Explicit months
  local m = tonumber(
    c.ageMonths or c.ageInMonths or c.monthsOld or c.age_mo or
    c.ageM or c.months or c.age_months
  )
  if m then return m end

  -- 2) Ambiguous 'age' (RL): prefer MONTHS; treat as days only if clearly too large to be months
  local a = tonumber(c.age)
  if a then
    if a <= 120 then return a else return a / 30.0 end
  end

  -- 3) Known day fields
  local d = tonumber(
    c.ageDays or c.age_in_days or c.daysOld or c.age_d or c.ageDaysOld or c.days
  )
  if d then return d / 30.0 end

  -- 4) Hours
  local h = tonumber(c.ageHours or c.age_in_hours or c.hoursOld or c.age_h)
  if h then return h / (24.0 * 30.0) end

  return nil
end


local function _getStagesForSpecies(species)
  species = tostring(species or "ANIMAL"):upper()
  if PN_UI._stagesCache[species] then return PN_UI._stagesCache[species] end
  if PN_Core and PN_Core.stages and PN_Core.stages[species] then
    PN_UI._stagesCache[species] = PN_Core.stages[species]
    return PN_UI._stagesCache[species]
  end
  if PN_Settings and PN_Settings.load then
    local ok, cfg = pcall(PN_Settings.load)
    if ok and type(cfg)=="table" and cfg.stages and cfg.stages[species] then
      PN_UI._stagesCache[species] = cfg.stages[species]
      return PN_UI._stagesCache[species]
    end
  end
  return nil
end

-- Resolve stage with preference for PN_Core, otherwise PN_Settings bands (+ cow overage rule)
local function _resolveStage(species, gender, ageM, flags)
  species = tostring(species or "ANIMAL"):upper()
  gender  = (gender=="male" or gender=="female") and gender or nil
  flags   = flags or {}
  local isLact = flags.lactating == true
  local isCast = flags.castrated == true

  if PN_Core and PN_Core.resolveStage then
    local ok, st = pcall(PN_Core.resolveStage, PN_Core, species, gender or "", ageM or 0, flags)
    if ok and type(st)=="string" and st~="" then return st end
  end

  local bands = _getStagesForSpecies(species)
  if type(bands)=="table" then
    if species=="COW" and gender=="male" and isCast and (ageM or 0) >= 25 then
      return "OVERAGE"
    end
    for _, b in ipairs(bands) do
      if type(b)=="table" and b.name then
        if (not b.gender) or (gender and b.gender==gender) then
          local minA = tonumber(b.minAgeM or 0) or 0
          local maxA = tonumber(b.maxAgeM or 1e9) or 1e9
          local okAge = (ageM==nil) or ((ageM >= minA) and (ageM < maxA))
          if okAge then
            if b.name=="LACT" or b.name=="DRY" then
              if b.name=="LACT" and isLact then return "LACT" end
              if b.name=="DRY"  and not isLact then return "DRY" end
            else
              return tostring(b.name)
            end
          end
        end
      end
    end
  end

  -- very generic fallback
  if species=="COW" then
    if gender=="female" then return isLact and "LACT" or "DRY" end
    if gender=="male" then return isCast and "STEER" or "BULL" end
  end
  return "DEFAULT"
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
--  • total DM (Dry Matter) in trough
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

  table.insert(lines, string.format("   Dry Matter in trough: %s kg  (≈ %s d @ current demand)",
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

-- Build per-stage rows (one row per stage present in the barn)
-- Build stage-based rows (one row per animal stage present in the barn)
local function makeStageRows(e)
  local rows = {}
  if not e then return rows end

  local name    = tostring(e.name or "?")
  local species = inferSpecies(e)

  -- Aggregate animals by stage (prefer PN_Core snapshot), fallback to raw clusters
  local agg = {}   -- stage -> { head, wSum }

  -- 1) Prefer processed snapshot from PN_Core.updateHusbandry (matches console / pnBeat)
  local usedAnimals = false
  if e.__pn_last and type(e.__pn_last.animals) == "table" and #e.__pn_last.animals > 0 then
    for _, a in ipairs(e.__pn_last.animals) do
      if type(a) == "table" then
        local gender = (a.gender or a.sex)
        if gender then gender = tostring(gender):lower() end
        if gender ~= "male" and gender ~= "female" then gender = nil end

        local ageM = tonumber(a.ageM or a.ageMonths or a.age_mo)
        if ageM == nil then
          -- last resort: reuse our generic age resolver over the snapshot table
          ageM = _ageMonths(a) or 0
        end

        local flags = a.flags or {
          lactating = (a.lactating == true) or (a.isLactating == true),
          castrated = (a.castrated == true) or (a.isCastrated == true)
        }

        local stage = tostring(a.stage or "")
        if stage == "" then
          stage = _resolveStage(species, gender, ageM, flags)
        end
		
		-- Normalize to sheep labels if the barn species is SHEEP
		if tostring(species):upper() == "SHEEP" then
		  local U = tostring(stage):upper()
		  if     U == "CALF"   then stage = "LAMB"
		  elseif U == "LACT"   then stage = "EWE_LACT"
		  elseif U == "DRY"    then stage = "EWE_DRY"
		  elseif U == "STEER"  then stage = "WETHER_FINISH"
		  elseif U == "BULL"   then stage = "RAM_ADULT"
		  elseif U == "HEIFER" then stage = "EWE_DRY"      -- safest ewe fallback
		  end
		end

		-- Pig label normalisation (overlay-friendly names)
		if tostring(species):upper() == "PIG" then
		  local U = tostring(stage):upper()

		  -- If any generic cattle-ish label ever leaks in, coerce to piggy terms
		  if U == "CALF" then
			stage = "PIGLET"
			U = "PIGLET"
		  end

		  -- Keep existing pig labels as-is, but tolerate either schema:
		  -- (schema A) PIGLET, GILT, SOW_GEST, SOW_LACT, BARROW, BOAR
		  -- (schema B) PIGLET, WEANER, GROWER, FINISHER, SOW_DRY, SOW_LACT, BOAR

		  -- Nothing to convert here beyond CALF→PIGLET; both schemas already use pig-native names per PN_Settings.
		end

        local head = tonumber(a.head or a.n or a.count or 1) or 1
        local avgW = tonumber(a.avgW or a.avgWeight or a.weight or 0) or 0

		local t = agg[stage]
		if not t then t = { head=0, wSum=0, male=0, female=0, wSumM=0, wSumF=0 }; agg[stage] = t end
		t.head = t.head + head
		t.wSum = t.wSum + (avgW * head)
		if gender == "male" then
		  t.male  = t.male + head
		  t.wSumM = t.wSumM + (avgW * head)
		elseif gender == "female" then
		  t.female  = t.female + head
		  t.wSumF   = t.wSumF + (avgW * head)
		end

      end
    end
    usedAnimals = (next(agg) ~= nil)
  end

  -- 2) Fallback to raw RL clusters only if snapshot was unavailable/empty
  if not usedAnimals then
    local cs = e and e.clusterSystem
    if cs and cs.getClusters then
      local ok, clusters = pcall(cs.getClusters, cs)
      if ok and type(clusters)=="table" then
        for _, c in pairs(clusters) do
          if type(c)=="table" and not c.isDead then
            -- Normalize inputs (+ infer gender from subtype if missing)
            local gender = tostring(c.gender or ""):lower()
            local subTL  = tostring(c.subType or c.typeName or ""):lower()
            if gender ~= "male" and gender ~= "female" then
              gender = inferGenderFromSubtype(species, subTL)
            end

            local flags = {
              lactating = (c.isLactating == true) or (c.isMilking == true) or ((c.milkLitersPerDay or 0) > 0),
              castrated = (c.isCastrated == true) or (c.castrated == true) or (c.isCast == true)
                          or (subTL:find("steer", 1, true) ~= nil),
            }

            -- Head & avg weight first (needed for weight-based stage fallback)
            local head = tonumber(c.numAnimals or c.n or c.count or c.head or c.size or c.num or 1) or 1
            local avgW = tonumber(c.avgWeight  or c.weight or 0) or 0

            local ageM  = _ageMonths(c)
            local stage = _resolveStage(species, gender, ageM or 0, flags)
			
            -- If age is missing/zero and stage couldn't be resolved well, use a weight-based heuristic
            if (not ageM or ageM <= 0) or stage == "DEFAULT" or stage == "" then
              local U  = tostring(species or "COW"):upper()
              local mk = nil
              if PN_Core and PN_Core.meta and PN_Core.meta[U] then
                mk = tonumber(PN_Core.meta[U].matureKg) or nil
              end
              local m = mk or 650  -- sensible fallback mature mass for cattle

              if gender == "female" then
                if flags.lactating then
                  stage = "LACT"
                elseif avgW < 240 then
                  stage = "CALF"
                elseif avgW < 500 then
                  stage = "HEIFER"
                else
                  stage = "DRY"
                end
              else -- male or unknown
                if flags.castrated then
                  stage = (avgW >= 0.8*m) and "STEER" or "YEARLING"
                else
                  if avgW >= 0.9*m then      stage = "BULL"
                  elseif avgW >= 280 then    stage = "YEARLING"
                  else                       stage = "CALF"
                  end
                end
              end
            end

			if tostring(species):upper() == "SHEEP" then
			  local U = tostring(stage):upper()
			  if     U == "CALF"   then stage = "LAMB"
			  elseif U == "LACT"   then stage = "EWE_LACT"
			  elseif U == "DRY"    then stage = "EWE_DRY"
			  elseif U == "STEER"  then stage = "WETHER_FINISH"
			  elseif U == "BULL"   then stage = "RAM_ADULT"
			  elseif U == "HEIFER" then stage = "EWE_DRY"
			  end
			end

            if tostring(species):upper() == "PIG" then
              local U = tostring(stage):upper()
              if U == "CALF" then stage = "PIGLET" end
            end

			local t = agg[stage]
			if not t then t = { head=0, wSum=0, male=0, female=0, wSumM=0, wSumF=0 }; agg[stage] = t end
			t.head = t.head + head
			t.wSum = t.wSum + (avgW * head)
			if gender == "male" then
			  t.male  = t.male + head
			  t.wSumM = t.wSumM + (avgW * head)
			elseif gender == "female" then
			  t.female  = t.female + head
			  t.wSumF   = t.wSumF + (avgW * head)
			end

          end
        end
      end
    end
  end

  if not PN_UI.__probeOnce then
    PN_UI.__probeOnce = true
    local keys = {}
    for st,_ in pairs(agg) do table.insert(keys, st) end
    table.sort(keys)
    Logging.info("[PN:Overlay] Aggregation via %s; stages=%s",
      (e.__pn_last and type(e.__pn_last.animals)=="table" and #e.__pn_last.animals>0) and "snapshot" or "raw-clusters",
      table.concat(keys, ","))
  end

  -- Barn nutrition factor (0..1)
  local barnNut = 0
  if e and e.__pn_last and e.__pn_last.nutRatio ~= nil then
    barnNut = tonumber(e.__pn_last.nutRatio) or 0
  elseif PN_Core and PN_Core.getTotals then
    local okT, totals = pcall(PN_Core.getTotals, e)
    if okT and type(totals)=="table" then
      barnNut = tonumber(totals.nut or 0) or 0
    end
  end
  if barnNut < 0 then barnNut = 0 elseif barnNut > 1 then barnNut = 1 end

  -- Live supply factor from trough: available DM vs required DM across stages
  local avail = _barnAvailableDmKg(e)
  local req = 0
  for st, t in pairs(agg) do
    req = req + (_dmDemandKgHd(species, st) * (t.head or 0))
  end
  local supplyF = (req > 0) and math.max(0, math.min(1, avail / req)) or 1.0
  if not PN_UI.cfg.useSupplyFactor then supplyF = 1.0 end

  -- Stage ordering per species (matches console pnBeat)
  -- Stage ordering per species (use global PN_UI.stageOrder for single source of truth)
  local SU  = (tostring(species or "ANIMAL")):upper()
  local ord = (PN_UI.stageOrder and PN_UI.stageOrder[SU])
           or (PN_UI.stageOrder and PN_UI.stageOrder.ANIMAL)
           or { DEFAULT = 99 }

  local keys = {}
  for st,_ in pairs(agg) do table.insert(keys, st) end
  table.sort(keys, function(a,b)
    local oa = ord[a] or ord.DEFAULT or 99
    local ob = ord[b] or ord.DEFAULT or 99
    if oa == ob then return a < b end
    return oa < ob
  end)

  -- Emit one overlay row per stage (with your palette tags)
  local nutPct = math.floor(barnNut*100 + 0.5)
  for _, st in ipairs(keys) do
    local t    = agg[st]
    local avgW = (t.head > 0) and (t.wSum / t.head) or 0

    -- Base ADG from PN_Core (already accounts for stage/species)
    local adg = 0.10 * barnNut
    if PN_Core and PN_Core.adgFor then
      local okG, g = pcall(PN_Core.adgFor, PN_Core, species, st, avgW, barnNut)
      if okG and type(g)=="number" then adg = g end
    end

    -- Maturity reserve
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

    -- Apply live supply factor (if enabled)
    adg = adg * (supplyF or 1.0)

    -- Optional starvation penalty per PN_Settings
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

    -- Tag → your palette (species-aware; colors match cows)
	-- Tag/emit → species-aware; YEARLING (sheep) by sex (split if mixed)
	local tag
	local SU = tostring(species or "ANIMAL"):upper()
	local U  = tostring(st):upper()

	if SU == "SHEEP" and U == "YEARLING" and (t.male > 0 or t.female > 0) then
	  -- mixed or single sex yearlings → emit 1–2 rows with proper colours
	  if t.female > 0 then
		local nf   = t.female
		local avgF = (t.wSumF > 0) and (t.wSumF / math.max(1, nf)) or 0
		table.insert(rows, {
		  gender = "femaleOpen",
		  text   = string.format("%s [%s/%s] | head=%d | avgW=%.2fkg | Nut=%d%% | ADG=%.3f kg/d",
					name, species, st, nf, avgF, nutPct, adg)
		})
	  end
	  if t.male > 0 then
		local nm   = t.male
		local avgM = (t.wSumM > 0) and (t.wSumM / math.max(1, nm)) or 0
		table.insert(rows, {
		  gender = "male",
		  text   = string.format("%s [%s/%s] | head=%d | avgW=%.2fkg | Nut=%d%% | ADG=%.3f kg/d",
					name, species, st, nm, avgM, nutPct, adg)
		})
	  end
	  
	elseif SU == "PIG" and U == "FINISHER" and (t.male > 0 or t.female > 0) then
	  -- PIG/FINISHER → split into female & male rows so colour matches sex
	  if t.female > 0 then
		local nf   = t.female
		local avgF = (t.wSumF > 0) and (t.wSumF / math.max(1, nf)) or 0
		table.insert(rows, {
		  gender = "femaleOpen",
		  text   = string.format("%s [%s/%s] | head=%d | avgW=%.2fkg | Nut=%d%% | ADG=%.3f kg/d",
					name, species, st, nf, avgF, nutPct, adg)
		})
	  end
	  if t.male > 0 then
		local nm   = t.male
		local avgM = (t.wSumM > 0) and (t.wSumM / math.max(1, nm)) or 0
		table.insert(rows, {
		  gender = "male",
		  text   = string.format("%s [%s/%s] | head=%d | avgW=%.2fkg | Nut=%d%% | ADG=%.3f kg/d",
					name, species, st, nm, avgM, nutPct, adg)
		})
	  end
else
  -- Normal single-row path (incl. all other sheep/cow/pig stages)
  if SU == "SHEEP" then
    -- lamb/weaner = calf yellow
    if U == "LAMB" or U == "WEANER" then
      tag = "calf"
    -- ewes: lact = stronger pink, dry = softer pink
    elseif U == "EWE_LACT" then
      tag = "femalepreg"
    elseif U == "EWE_DRY" then
      tag = "femaleOpen"
    elseif U == "YEARLING" then
      -- if YEARLING but no sex breakdown, assume female (your barn is all-female)
      tag = (t.male > 0 and t.female == 0) and "male" or "femaleOpen"
    -- castrated & rams → male blue
    elseif U == "WETHER" or U == "WETHER_FINISH" or U == "RAM" or U == "RAM_GROW" or U == "RAM_ADULT" then
      tag = "male"
    else
      -- heuristic fallback for unknown sheep labels
      if U:find("EWE",1,true) then
        tag = "femaleOpen"
      elseif U:find("LAMB",1,true) or U:find("WEAN",1,true) then
        tag = "calf"
      else
        tag = "male"
      end
    end

  elseif SU == "PIG" then
    -- Early growth → calf yellow
    if U == "PIGLET" or U == "WEANER" or U == "GROWER" then
      tag = "calf"

    -- Lactating → strong pink
    elseif U == "SOW_LACT" then
      tag = "femalepreg"

    -- Dry/gestating females + gilt → soft pink
    elseif U == "SOW_DRY" or U == "SOW_GEST" or U == "GILT" then
      tag = "femaleOpen"

    -- Finishers & all males → blue
    elseif U == "FINISHER" then
	  -- If only one sex present, colour by sex; mixed is handled by the split block above
	  if t.male > 0 and t.female == 0 then tag = "male"
	  elseif t.female > 0 and t.male == 0 then tag = "femaleOpen"
	  else tag = "male" end

	elseif U == "BARROW" or U == "BOAR" then
	  tag = "male"

    else
      -- Fallback: if it contains 'SOW' or 'GILT' treat as female; else male
      if U:find("SOW",1,true) or U:find("GILT",1,true) then
        tag = "femaleOpen"
      else
        tag = "male"
      end
    end  -- <— closes pig-stage inner if/elseif/else

  else
    -- cattle/default as before
    if U == "CALF" then
      tag = "calf"
    elseif U == "HEIFER" or U == "DRY" then
      tag = "femaleOpen"
    elseif U == "LACT" or U == "GEST" then
      tag = "femalepreg"
    else
      tag = "male"
    end
  end  -- <— closes species switch (SHEEP / PIG / else)

	  table.insert(rows, {
		gender = tag,
		text   = string.format("%s [%s/%s] | head=%d | avgW=%.2fkg | Nut=%d%% | ADG=%.3f kg/d",
				  name, species, tostring(st), tonumber(t.head or 0), tonumber(avgW or 0), nutPct, adg)
	  })
	end
  end

  return rows
end

local function _visibleBarns()
  local barns = {}
  if not PN_HusbandryScan or not PN_HusbandryScan.getAll then return barns end
  local list = PN_HusbandryScan.getAll() or {}

  local myId = _getMyFarmId()
  for _, e in ipairs(list) do
    local keep = true
    if PN_UI.onlyMyFarm then
      local farmId = _getEntryFarmId(e)
      if (farmId ~= nil) and (myId ~= nil) and (farmId ~= myId) then
        keep = false
      end
    end
    if keep then table.insert(barns, e) end
  end
  return barns
end

-- Count animals known for a husbandry entry (from last snapshot or live clusters)
local function _headCount(e)
  if not e then return 0 end
  -- Prefer our last snapshot (fast)
  local last = e.__pn_last
  if last and type(last.animals) == "table" then
    local sum = 0
    for _, a in ipairs(last.animals) do
      sum = sum + (tonumber(a.head or 0) or 0)
    end
    if sum > 0 then return sum end
  end

  -- Fallback to live cluster system (slower, but safe)
  local cs = e.clusterSystem
  if cs and cs.getClusters then
    local ok, clusters = pcall(cs.getClusters, cs)
    if ok and type(clusters) == "table" then
      local sum = 0
      for _, c in pairs(clusters) do
        if type(c) == "table" and not c.isDead then
          sum = sum + (tonumber(c.numAnimals or c.n or c.count or c.head or 1) or 1)
        end
      end
      return sum
    end
  end
  return 0
end

function PN_UI.buildBarnList()
  local all = _visibleBarns()                -- farm filter stays the same
  local keep = {}
  for _, e in ipairs(all) do
    if _headCount(e) > 0 then
      table.insert(keep, e)
    end
  end
  -- Stable-ish order by display name so cycling is predictable
  table.sort(keep, function(a,b)
    return tostring(a.name or ""):lower() < tostring(b.name or ""):lower()
  end)
  PN_UI._barnList = keep
  return PN_UI._barnList
end

local function _clampIndex(i, n)
  if n <= 0 then return 0 end
  if i < 1 then return 1 end
  if i > n then return n end
  return i
end

function PN_UI._selectBarn(i)
  local list = PN_UI._barnList or PN_UI.buildBarnList()
  PN_UI._barnIdx = _clampIndex(i or 1, #list)
  PN_UI._nextRefreshAt = 0 -- force a redraw update tick
  return list[PN_UI._barnIdx], PN_UI._barnIdx, #list
end

function PN_UI.cycleBarnOverlay()
  if not PN_UI.enabled then
    PN_UI.enabled = true
    PN_UI.mode = "single"
    PN_UI.buildBarnList()
    PN_UI._selectBarn(1)
    return
  end

  if PN_UI.mode ~= "single" then
    PN_UI.mode = "single"
    PN_UI.buildBarnList()
    PN_UI._selectBarn(1)
    return
  end

  -- mode == "single": advance or turn off at the end
  local list = PN_UI._barnList or PN_UI.buildBarnList()
  if #list == 0 then
    PN_UI.enabled = false
    return
  end

  local nextIdx = PN_UI._barnIdx + 1
  if nextIdx > #list then
    PN_UI.enabled = false
    PN_UI.mode = "list"
  else
    PN_UI._selectBarn(nextIdx)
  end
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
  if not PN_UI._rescanOnce and PN_HusbandryScan.rescan then
    PN_UI._rescanOnce = true
    pcall(PN_HusbandryScan.rescan, PN_HusbandryScan)
    list = getAll() or {}
  else
    return rows
  end
end

-- Decide which barns to draw
local toDraw = {}
if PN_UI.mode == "single" then
  -- keep cached filtered list in sync with live list
  PN_UI.buildBarnList()
  local e, idx, total = PN_UI._selectBarn(PN_UI._barnIdx > 0 and PN_UI._barnIdx or 1)
  if e then table.insert(toDraw, e) end
else
  -- draw them all (current behavior)
  toDraw = _visibleBarns()
end

for _, e in ipairs(toDraw) do
  -- LIVE refresh snapshot (match pnBeat) — throttled
  if PN_Core and PN_Core.updateHusbandry and e and e.clusterSystem ~= nil then
    pcall(PN_Core.updateHusbandry, PN_Core, e, e.clusterSystem, 33, { source = "overlay" })
  end

  -- Per-stage rows (one row per stage present)
  local stageRows = makeStageRows(e)
  for _, r in ipairs(stageRows) do table.insert(rows, r) end

  -- FEED summary after animals (as you set it)
  local feedLines = PN_UI._feedSummaryLines(e)
  for _, s in ipairs(feedLines) do table.insert(rows, { gender = "feed", text = s }) end

  table.insert(rows, { gender = "feed", text = " " })
end

  return rows
end

-- ---- hooks from PN_Load ----
function PN_UI.onUpdate(dt) pollOverlayKeys(dt) end

function PN_UI.onDraw()
  if not PN_UI.enabled then return end

  -- Build header and rows (reuse existing logic)
  local mode = (PN_UI.onlyMyFarm and "My Farm Only" or "All Farms")
  local ac   = (PN_Core and PN_Core.autoConsume) and "AC:ON" or "AC:OFF"
	local header
	if PN_UI.mode == "single" then
	  local list = PN_UI._barnList or {}
	  local idx  = PN_UI._barnIdx or 0
	  local e    = list[idx]
	  local title = e and tostring(e.name or "?") or "Barn"
	  header = string.format("[PN] %s (%d/%d) – %s  [%s]", title, idx, #list, mode, ac, "(ALT+N to cycle barns)")
	else
	  header = string.format("[PN] Precision Nutrition Overlay (Alt+N) – %s  [%s]", mode, ac)
	end

  -- Collect rows we will draw (strings + gender)
  local rows = {}

  -- Always build LIVE per-stage rows first (matches pnBeat)
  local built = buildFallbackRows()
  for _, r in ipairs(built) do table.insert(rows, r) end

  -- Optionally append any pushed rows (only if you disable preferLiveRows)
  if PN_UI.cfg.preferLiveRows ~= true then
    for _, v in pairs(PN_UI.barns) do
      table.insert(rows, { text = string.format(
        "%s [%s] | Head=%d | Stage=%s | ADG=%s kg/d | Intake=%s /hd/d | Balance=%s | Forage=%s%%",
        tostring(v.name or "?"),
        tostring(v.species or "ANIMAL"),
        tonumber(v.n or 0),
        tostring(v.stage or "?"),
        nfmt(v.adg, 2), nfmt(v.intake, 1), nfmt(v.balance, 2), nfmt((v.forage or 0)*100, 0)
      )})
    end
  end

  if #rows == 0 then
    rows = { { text = "(no animal barns detected for this filter)", gender = "warn" } }
  end

  -- Dimensions
  local fs = PN_UI.ov.fontSize
  local totalW = _pn_measureWidth(header, rows)
  do
    local ov = PN_UI.ov
    if ov.fixedW ~= nil then
      totalW = ov.fixedW
    else
      if ov.minW then totalW = math.max(totalW, ov.minW) end
      if ov.maxW then totalW = math.min(totalW, ov.maxW) end
    end
  end
  local maxRows = tonumber(PN_UI.ov.maxRows or 0) or 0
  local n = #rows
  if maxRows > 0 then n = math.min(#rows, maxRows) end

  local totalH = PN_UI.ov.padY*2 + (PN_UI.ov.rowH * (n + 1))

  -- Anchor/margins → x,y
  local x, y
  if PN_UI.ov.anchor == "tr" then
    x = 1.0 - totalW - PN_UI.ov.marginX
    y = 1.0 - PN_UI.ov.marginY
  elseif PN_UI.ov.anchor == "tl" then
    x = PN_UI.ov.marginX
    y = 1.0 - PN_UI.ov.marginY
  elseif PN_UI.ov.anchor == "bl" then
    x = PN_UI.ov.marginX
    y = totalH + PN_UI.ov.marginY
  else -- "br"
    x = 1.0 - totalW - PN_UI.ov.marginX
    y = totalH + PN_UI.ov.marginY
  end

  -- Background panel
  if drawFilledRect then
    local c = PN_UI.palette.bg
    drawFilledRect(x - PN_UI.ov.padX, y - totalH, totalW + PN_UI.ov.padX*2, totalH + PN_UI.ov.padY, c[1], c[2], c[3], PN_UI.ov.alpha or c[4] or 0.40)
  end

  -- Header
  if setTextBold then setTextBold(true) end
  if setTextColor then
    local h = PN_UI.palette.header
    setTextColor(h[1], h[2], h[3], h[4])
  end
  if setTextAlignment then setTextAlignment(RenderText.ALIGN_LEFT) end
  drawLine(x, y - fs*0.2, header, fs)
  if setTextBold then setTextBold(false) end

  -- Rows
  local yLine = y - fs - PN_UI.ov.padY*0.2
  for i = 1, n do
    local r = rows[i]
    if setTextColor then
      local g = tostring(r.gender or ""):lower()
      if g == "femaleopen" then local c=PN_UI.palette.female1; setTextColor(c[1],c[2],c[3],1.0)
      elseif g == "femalepreg" then local c=PN_UI.palette.female2; setTextColor(c[1],c[2],c[3],1.0)
      elseif g == "male" then local c=PN_UI.palette.male; setTextColor(c[1],c[2],c[3],1.0)
	  elseif g == "calf" then local c=PN_UI.palette.calf; setTextColor(c[1],c[2],c[3],1.0)
      elseif g == "feed" then local c=PN_UI.palette.feed; setTextColor(c[1],c[2],c[3],1.0)
      elseif g == "warn" then local c=PN_UI.palette.warn; setTextColor(c[1],c[2],c[3],1.0)
      else local t=PN_UI.palette.text; setTextColor(t[1],t[2],t[3],t[4]) end
    end
    drawLine(x, yLine, tostring(r.text or ""), fs)
    yLine = yLine - PN_UI.ov.rowH
    if yLine < 0.05 then break end
  end
end



-- === Console commands: overlay =============================================
if not PN_UI.__overlayRegistered then
  function PN_UI:cmdOverlay(args, ...)
    local a = {}
    if type(args) == "table" then a = args else
      if args ~= nil then table.insert(a, tostring(args)) end
      local n = select('#', ...); for i=1,n do table.insert(a, tostring(select(i, ...))) end
    end
    local sub = (a[1] or "toggle"):lower()
    if sub == "on" then PN_UI.enabled = true; PN_UI._nextRefreshAt = 0
    elseif sub == "off" then PN_UI.enabled = false
    elseif sub == "toggle" then 
	  PN_UI.enabled = not PN_UI.enabled
	  if PN_UI.enabled then PN_UI._nextRefreshAt = 0 end
    elseif sub == "alpha" then
      local v = tonumber(a[2]); if v then PN_UI.ov.alpha = math.max(0, math.min(1, v)) end
    elseif sub == "anchor" then
      local v = (a[2] or PN_UI.ov.anchor):lower()
      if v=="tl" or v=="tr" or v=="bl" or v=="br" then PN_UI.ov.anchor = v end
	elseif sub == "rows" then
	  local v = (a[2] or ""):lower()
	  if v == "" or v == "auto" or v == "0" then
		PN_UI.ov.maxRows = nil  -- auto (no cap)
	  else
		local n = tonumber(v)
		if n then PN_UI.ov.maxRows = math.max(1, math.floor(n)) end
	  end
    elseif sub == "margin" then
      local mx = tonumber(a[2]); local my = tonumber(a[3])
      if mx then PN_UI.ov.marginX = math.max(0, math.min(0.5, mx)) end
      if my then PN_UI.ov.marginY = math.max(0, math.min(0.5, my)) end
    elseif sub == "fontsize" then
      local v = tonumber(a[2]); if v then PN_UI.ov.fontSize = math.max(0.008, math.min(0.040, v)) end
    elseif sub == "rowh" or sub == "rowH" then
      local v = tonumber(a[2]); if v then PN_UI.ov.rowH = math.max(0.010, math.min(0.060, v)) end
    elseif sub == "padding" or sub == "pad" then
      local px = tonumber(a[2]); local py = tonumber(a[3])
      if px then PN_UI.ov.padX = math.max(0.000, math.min(0.050, px)) end
      if py then PN_UI.ov.padY = math.max(0.000, math.min(0.050, py)) end
    elseif sub == "width" then
      local v1 = (a[2] or "auto"):lower()
      if v1 == "auto" then
        PN_UI.ov.fixedW = nil
      elseif v1 == "min" then
        local w = tonumber(a[3]); if w then PN_UI.ov.minW = math.max(0.10, math.min(1.00, w)) end
      elseif v1 == "max" then
        local w = tonumber(a[3]); if w then PN_UI.ov.maxW = math.max(0.10, math.min(1.00, w)) end
      elseif v1 == "clamp" then
        local mn = tonumber(a[3]); local mx = tonumber(a[4])
        if mn and mx then PN_UI.ov.minW = math.min(mn, mx); PN_UI.ov.maxW = math.max(mn, mx) end
      else
        local w = tonumber(a[2]); if w then PN_UI.ov.fixedW = math.max(0.10, math.min(1.00, w)) end
      end
    elseif sub == "reset" then
      PN_UI.enabled = true
      PN_UI.ov.anchor  = "tr"
      PN_UI.ov.alpha   = 0.40
      PN_UI.ov.maxRows = 14
      PN_UI.ov.marginX = 0.500
      PN_UI.ov.marginY = 0.030
      PN_UI.ov.fontSize= 0.016
      PN_UI.ov.rowH    = 0.018
      PN_UI.ov.padX    = 0.010
      PN_UI.ov.padY    = 0.010
      PN_UI.ov.fixedW  = nil
      PN_UI.ov.minW    = nil
      PN_UI.ov.maxW    = nil
    elseif sub == "status" then
      local rows = buildFallbackRows() or {}
      local fw = (PN_UI.ov.fixedW ~= nil) and PN_UI.ov.fixedW or -1
      local mn = (PN_UI.ov.minW  ~= nil) and PN_UI.ov.minW  or -1
      local mx = (PN_UI.ov.maxW  ~= nil) and PN_UI.ov.maxW  or -1

      local rowsVal = tonumber(PN_UI.ov.maxRows or 0) or 0
      Logging.info("[PN:Overlay] enabled=%s alpha=%.2f anchor=%s rows=%d margin=(%.3f, %.3f) fs=%.3f rowH=%.3f pad=(%.3f,%.3f) width(fixed=%.3f,min=%.3f,max=%.3f) rowsCount=%d",
        tostring(PN_UI.enabled),
        tonumber(PN_UI.ov.alpha   or 0) or 0,
        tostring(PN_UI.ov.anchor  or "tl"),
        rowsVal,
        tonumber(PN_UI.ov.marginX or 0) or 0,
        tonumber(PN_UI.ov.marginY or 0) or 0,
        tonumber(PN_UI.ov.fontSize or 0) or 0,
        tonumber(PN_UI.ov.rowH     or 0) or 0,
        tonumber(PN_UI.ov.padX     or 0) or 0,
        tonumber(PN_UI.ov.padY     or 0) or 0,
        fw, mn, mx, #rows)
      return
    elseif sub == "probe" then
	  local v = (a[2] or ""):lower()
	  if v == "reset" then
		PN_UI.__probeOnce = nil
		Logging.info("[PN:Overlay] probe reset")
	  else
		Logging.info("[PN:Overlay] probe usage: pnOverlay probe reset")
	  end
	else
      Logging.info("[PN:Overlay] Usage: pnOverlay on|off|toggle | alpha <0..1> | anchor tl|tr|bl|br | margin <x y> | rows <N> | fontsize <v> | rowH <v> | padding <x y> | width auto|<v>|min <v>|max <v>|clamp <min> <max> | reset | status")
    end
    Logging.info("[PN:Overlay] enabled=%s alpha=%.2f anchor=%s rows=%d margin=(%.3f, %.3f)",
      tostring(PN_UI.enabled),
      tonumber(PN_UI.ov.alpha   or 0) or 0,
      tostring(PN_UI.ov.anchor  or "tl"),
      tonumber(PN_UI.ov.maxRows or 0) or 0,
      tonumber(PN_UI.ov.marginX or 0) or 0,
      tonumber(PN_UI.ov.marginY or 0) or 0)
  end
  if addConsoleCommand then
    addConsoleCommand("pnOverlay", "Overlay controls", "cmdOverlay", PN_UI)
  end
  PN_UI.__overlayRegistered = true
end
-- ============================================================================
return PN_UI
