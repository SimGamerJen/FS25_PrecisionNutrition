-- FS25_PrecisionNutrition / scripts / PN_Debug.lua
-- Console helpers for on-demand inspection (FS25-style addConsoleCommand).

PN_Debug = PN_Debug or {}

-- =========================================================
-- Small utilities (safe string, simple helpers)
-- =========================================================
-- ---------- steer / castration inference (no file IO) ----------
local function _cGender(c)
    if not c then return nil end
    if c.isMale ~= nil and type(c.isMale)=="function" then
        local ok, b = pcall(c.isMale, c); if ok then return b and "male" or "female" end
    end
    if c.getGender ~= nil and type(c.getGender)=="function" then
        local ok, g = pcall(c.getGender, c); if ok and type(g)=="string" then return g:lower() end
    end
    if c.gender ~= nil then return tostring(c.gender):lower() end
    return nil
end

local function _cCastrated(c)
    -- RL puts it right on the cluster table in your build
    if c.isCastrated ~= nil then
        return c.isCastrated == true
    end
    -- Fallbacks if RL moves it or your scan cached it elsewhere
    if c.extra and c.extra.isCastrated ~= nil then
        return c.extra.isCastrated == true
    end
    if PN_HusbandryScan and PN_HusbandryScan.getAnimalFlags then
        local flags = PN_HusbandryScan.getAnimalFlags(c) -- whatever your API returns for this cluster
        if flags and flags.isCastrated ~= nil then
            return flags.isCastrated == true
        end
    end
    return false
end

-- Some maps/mods (incl. RL) label cluster subType/typeName with "steer"
local function _cLooksLikeSteer(c)
    local s = tostring(c.subType or c.typeName or c.breed or ""):lower()
    return (s:find("steer", 1, true) ~= nil)
end

local function _safe(n)
    if n == nil then return "?" end
    n = tostring(n)
    if n == "" then return "?" end
    return n
end

--- ---------- Cluster getters (robust) ----------
local function _cNum(c)
    if not c then return 0 end
    if c.getNumAnimals ~= nil then local ok, n = pcall(c.getNumAnimals, c); if ok and type(n)=="number" then return n end end
    if c.numAnimals ~= nil then return tonumber(c.numAnimals) or 0 end
    if c.count      ~= nil then return tonumber(c.count)      or 0 end
    if c.n          ~= nil then return tonumber(c.n)          or 0 end
    return 1 -- worst-case: treat as a single animal
end

local function _cAvgWeightKg(c)
    if not c then return 0 end
    if c.getAverageWeight ~= nil then local ok, w = pcall(c.getAverageWeight, c); if ok and type(w)=="number" then return w end end
    if c.getWeight        ~= nil then local ok, w = pcall(c.getWeight,        c); if ok and type(w)=="number" then return w end end
    if c.avgWeight        ~= nil then return tonumber(c.avgWeight)        or 0 end
    if c.averageWeight    ~= nil then return tonumber(c.averageWeight)    or 0 end
    if c.weight           ~= nil then return tonumber(c.weight)           or 0 end
    return 0
end

local function _cLactating(c)
    if not c then return false end
    for _,k in ipairs({"isLactating","getIsLactating","isMilking"}) do
        local f = c[k]
        if type(f)=="function" then local ok, v = pcall(f, c); if ok and v == true then return true end
        elseif f ~= nil and f == true then return true end
    end
    if (c.milkLitersPerDay or 0) > 0 then return true end
    return false
end

local function _cAgeMonths(c)
    if not c then return 0 end
    -- Prefer explicit months if available
    for _,k in ipairs({"getAgeMonths","ageMonths","ageM","age_months","months","monthAge","ageInMonths"}) do
        local v = c[k]
        if type(v)=="function" then local ok, n = pcall(v, c); if ok and type(n)=="number" then return n end
        elseif v ~= nil then local n=tonumber(v); if n then return n end end
    end
    -- Fallbacks likely in DAYS; heuristic: big values (>100) are days
    for _,k in ipairs({"getAge","ageDays","ageInDays","age"}) do
        local v = c[k]
        if type(v)=="function" then local ok, n = pcall(v, c); if ok and type(n)=="number" then return (n > 100 and (n/30.4167) or n) end
        elseif v ~= nil then local n=tonumber(v); if n then return (n > 100 and (n/30.4167) or n) end end
    end
    return 0
end

-- ---------- Stage helpers (uses PN_Core or PN_Settings) ----------
local function _dbgNormSpecies(s)
    s = tostring(s or ""):upper()
    if s == "CATTLE" then return "COW" end
    if s == "HEN"    then return "CHICKEN" end
    return s ~= "" and s or "ANIMAL"
end

local _DBG_STAGE_ORDER = {
  COW     = { CALF=1, HEIFER=2, LACT=3, DRY=4, YEARLING=5, STEER=6, BULL=7, OVERAGE=8, DEFAULT=99 },
  SHEEP   = { LAMB=1, EWE_LACT=2, EWE_DRY=3, RAM_GROW=4, RAM_ADULT=5, DEFAULT=99 },
  PIG     = { PIGLET=1, GILT=2, SOW_LACT=3, SOW_GEST=4, BARROW=5, BOAR=6, DEFAULT=99 },
  GOAT    = { KID=1, DOE_LACT=2, DOE_DRY=3, BUCK_GROW=4, BUCK_ADULT=5, DEFAULT=99 },
  CHICKEN = { CHICK=1, BROILER_F=2, LAYER=3, BROILER_M=4, ROOSTER=5, DEFAULT=99 },
  ANIMAL  = { DEFAULT=1 },
}

local _DBG_BANDS_CACHE = {}
local function _dbgGetBands(species)
    species = tostring(species or "ANIMAL"):upper()
    if _DBG_BANDS_CACHE[species] then return _DBG_BANDS_CACHE[species] end
    local bands = nil
    if PN_Core and PN_Core.stages and PN_Core.stages[species] then
        bands = PN_Core.stages[species]
    elseif PN_Settings and PN_Settings.load then
        local ok, cfg = pcall(PN_Settings.load)
        if ok and type(cfg)=="table" and cfg.stages and cfg.stages[species] then
            bands = cfg.stages[species]
        end
    end
    _DBG_BANDS_CACHE[species] = bands
    return bands
end

-- Prefer live RL flags; enforce COW priority before bands
local function _dbgResolveStage(species, gender, ageM, flags)
    species = tostring(species or "ANIMAL"):upper()
    gender  = (gender == "male" or gender == "female") and gender or nil
    flags   = flags or {}
    local isCast = flags.castrated == true
    local isLact = flags.lactating == true
    ageM    = tonumber(ageM or 0) or 0

    -- 1) COW priority rules (win before bands)
    if species == "COW" then
        if gender == "male" then
            if isCast then
                if ageM >= 25 then return "OVERAGE" end     -- castrated, 25m+ => OVERAGE
                if ageM >= 18 then return "STEER"   end     -- castrated, 18–24.999m => STEER
                -- <18m: let bands handle CALF/YEARLING, etc.
            else
                if ageM >= 18 then return "BULL"    end     -- intact male, 18m+ => BULL
                -- <18m: let bands handle CALF/YEARLING, etc.
            end
        elseif gender == "female" then
            if isLact then return "LACT" end                -- lactating takes precedence
            -- (non-lactating female: bands will pick HEIFER / DRY by age)
        end
    end

    -- 2) If PN_Core has a resolver, let it try (may include more nuanced logic)
    if PN_Core and PN_Core.resolveStage then
        local ok, st = pcall(PN_Core.resolveStage, PN_Core, species, gender or "", ageM, flags)
        if ok and type(st) == "string" and st ~= "" then
            return st
        end
    end

    -- 3) Fallback: PN_Settings bands
    local bands = _dbgGetBands(species)
    if type(bands) == "table" then
        for _, b in ipairs(bands) do
            if type(b) == "table" and b.name then
                if (not b.gender) or (gender and b.gender == gender) then
                    local minA = tonumber(b.minAgeM or 0) or 0
                    local maxA = tonumber(b.maxAgeM or math.huge) or math.huge
                    if ageM >= minA and ageM < maxA then
                        if b.name == "LACT" or b.name == "DRY" then
                            if b.name == "LACT" and isLact      then return "LACT" end
                            if b.name == "DRY"  and not isLact  then return "DRY"  end
                        else
                            return tostring(b.name)
                        end
                    end
                end
            end
        end
    end

    -- 4) Very last resort (keeps things sensible if bands are missing)
    if species == "COW" then
        if gender == "female" then return isLact and "LACT" or "DRY" end
        if gender == "male"   then return isCast and "STEER" or "BULL" end
    end
    return "DEFAULT"
end

-- All barns: pnStagesAll  (calls pnStages for each index)
function PN_Debug:cmdStagesAll()
    local list = (PN_HusbandryScan and PN_HusbandryScan.getAll and PN_HusbandryScan.getAll()) or {}
    if type(list) ~= "table" or #list == 0 then
        Logging.info("[PN] pnStagesAll: no entries")
        return
    end
    for i=1,#list do
        self:cmdStages(tostring(i))
    end
end

function PN_Debug:cmdRLCounts()
    local rl = _dbgLoadRLSteerMap() or {}
    Logging.info("[PN] RL (savegame) male castrated counts by placeable file:")
    local n=0
    for k,v in pairs(rl) do Logging.info("[PN]   %s => %d", k, v); n=n+v end
    Logging.info("[PN]   TOTAL = %d", n)
end

-- =========================================================
-- Diagnostics & self-heal
-- =========================================================
-- Prints which PN modules/methods are actually loaded and ready
function PN_Debug:cmdDiag()
    local ok = function(x) return x and "yes" or "no" end
    local has = function(t, k) return (t and t[k]) and "yes" or "no" end

    Logging.info("---- PN Diag ----")
    Logging.info("PN_Settings loaded: " .. ok(PN_Settings))
    Logging.info("PN_Logger  loaded: " .. ok(PN_Logger) .. (PN_Logger and (" level="..(PN_Logger.levelName or "?")) or ""))

    Logging.info("PN_HusbandryScan loaded: " .. ok(PN_HusbandryScan))
    if PN_HusbandryScan and PN_HusbandryScan.entries then
        Logging.info(("  entries: %d"):format(#PN_HusbandryScan.entries))
    end

    Logging.info("PN_FeedMatrix loaded: " .. ok(PN_FeedMatrix))
    Logging.info("PN_Core      loaded: " .. ok(PN_Core) ..
                 "  computeNutritionAndADG: " .. has(PN_Core, "computeNutritionAndADG"))

    Logging.info("PN_Events    loaded: " .. ok(PN_Events) ..
                 "  heartbeat: " .. has(PN_Events, "heartbeat") ..
                 "  simDays: " .. has(PN_Events, "simDays"))

    Logging.info("---- End PN Diag ----")
end

function PN_Debug:cmdFixEvents()
    if not PN_Events then PN_Events = {} end
    PN_Events.__index = PN_Events
    -- Reattach methods if missing (pull from globals the installer stashed)
    PN_Events.heartbeat = PN_Events.heartbeat or _G.__pn_events_heartbeat_impl
    PN_Events.simDays   = PN_Events.simDays   or _G.__pn_events_simdays_impl
    if PN_Events.heartbeat and PN_Events.simDays then
        Logging.info("[PN] Events restored (heartbeat/simDays).")
    else
        Logging.info("[PN] Could not restore Events (impls missing).")
    end
end

-- =========================================================
-- Listing / exporting husbandries
-- =========================================================
function PN_Debug:cmdDumpHusbandries()
    if PN_HusbandryScan == nil or PN_HusbandryScan.getAll == nil then
        Logging.info("[PN] pnDumpHusbandries: scanner not available")
        return
    end
    local list = PN_HusbandryScan.getAll()
    Logging.info("[PN] ---- PN Husbandries ---- count=%d", #list)
    for i, e in ipairs(list) do
        local name   = _safe(e.name)
        local farmId = _safe(e.farmId)
        local kind   = _safe(e.type)
        local hasCS  = (e.clusterSystem ~= nil) and "yes" or "no"
        Logging.info("[PN] %03d | farm=%s | type=%s | cluster=%s | %s", i, farmId, kind, hasCS, name)
    end
    Logging.info("[PN] ------------------------")
end

function PN_Debug:cmdDumpHusbandriesCSV()
    if PN_HusbandryScan == nil or PN_HusbandryScan.getAll == nil then
        Logging.info("[PN] pnDumpHusbandriesCSV: scanner not available")
        return
    end
    local list = PN_HusbandryScan.getAll()
    local dir  = g_currentModSettingsDirectory or ""
    local file = dir .. "/PN_Husbandries.csv"
    local fh = io.open(file, "w")
    if fh == nil then
        Logging.info("[PN] Could not open %s for writing", file)
        return
    end
    fh:write("index,farmId,type,cluster,name\n")
    for i, e in ipairs(list) do
        local name   = '"' .. tostring(_safe(e.name)):gsub('"', '""') .. '"'
        local farmId = _safe(e.farmId)
        local kind   = _safe(e.type)
        local hasCS  = (e.clusterSystem ~= nil) and "yes" or "no"
        fh:write(string.format("%d,%s,%s,%s,%s\n", i, farmId, kind, hasCS, name))
    end
    fh:close()
    Logging.info("[PN] Wrote %d entries to %s", #list, file)
end

-- =========================================================
-- Inspectors (husbandry, clusters, trough, food spec)
-- =========================================================
-- Summarise animals by stage for one entry: pnStages <index>
function PN_Debug:cmdStages(idxStr)
    local idx = tonumber(idxStr or "")
    if idx == nil then
        Logging.info("[PN] Usage: pnStages <index>  (see pnDumpHusbandries)")
        return
    end
    local list = (PN_HusbandryScan and PN_HusbandryScan.getAll and PN_HusbandryScan.getAll()) or {}
    local e = list[idx]
    if not e or not e.clusterSystem then
        Logging.info("[PN] pnStages: no entry/cluster at index %s", tostring(idx))
        return
    end

    -- Species + barn nutrition
    local species = _dbgNormSpecies(e.type or (e.__pn_last and e.__pn_last.species) or "ANIMAL")
    local barnNut = 0
    if e.__pn_last and e.__pn_last.nutRatio ~= nil then
        barnNut = tonumber(e.__pn_last.nutRatio) or 0
    elseif PN_Core and PN_Core.getTotals then
        local okT, totals = pcall(PN_Core.getTotals, e)
        if okT and type(totals)=="table" then barnNut = tonumber(totals.nut or 0) or 0 end
    end
    if barnNut < 0 then barnNut = 0 elseif barnNut > 1 then barnNut = 1 end

    -- Clusters
    local okC, clusters = pcall(e.clusterSystem.getClusters, e.clusterSystem)
    if not okC or type(clusters) ~= "table" then
        Logging.info("[PN] pnStages: getClusters() failed")
        return
    end

    -- Aggregate stages
    local agg = {} -- stage -> { head, weightTotal, ageSum, ageMin, ageMax }
    local totalHead = 0
    for _, c in pairs(clusters) do
        if type(c)=="table" and not c.isDead then
			local head       = _cNum(c)
			local ageM       = _cAgeMonths(c)
			local looksSteer = _cLooksLikeSteer(c)
			local isCast     = _cCastrated(c) or looksSteer       -- live RL + subtype hint
			local gender     = _cGender(c)
			local flags      = { lactating=_cLactating(c), castrated=isCast }
			local stage      = _dbgResolveStage(species, gender, ageM, flags)
			local avgW       = _cAvgWeightKg(c)

            local t = agg[stage]
            if not t then t = { head=0, weightTotal=0, ageSum=0, ageMin=9999, ageMax=0 }; agg[stage]=t end
            t.head        = t.head + head
            t.weightTotal = t.weightTotal + (avgW * head)
            t.ageSum      = t.ageSum + (ageM * head)
            if head > 0 then
                if ageM < t.ageMin then t.ageMin = ageM end
                if ageM > t.ageMax then t.ageMax = ageM end
            end
            totalHead = totalHead + head
        end
    end

    -- Sort and print
    local order = _DBG_STAGE_ORDER[species] or _DBG_STAGE_ORDER.ANIMAL
    local keys = {}
    for st,_ in pairs(agg) do table.insert(keys, st) end
    table.sort(keys, function(a,b)
        local oa = order[a] or order.DEFAULT or 99
        local ob = order[b] or order.DEFAULT or 99
        if oa == ob then return a < b end
        return oa < ob
    end)

    Logging.info("[PN] ---- Stage breakdown for #%d '%s' [%s] ----", idx, tostring(e.name or "?"), species)
    Logging.info("[PN] Barn Nut=%d%%, animals=%d", math.floor(barnNut*100+0.5), totalHead)
    for _, st in ipairs(keys) do
        local t = agg[st]
        local avgW = (t.head > 0) and (t.weightTotal / t.head) or 0
        local avgM = (t.head > 0) and (t.ageSum / t.head) or 0
        Logging.info("[PN]   stage=%-8s | head=%3d | avgW=%7.2f kg | age=avg %.1f m (min %.1f, max %.1f)",
            tostring(st), t.head, avgW, avgM, t.ageMin, t.ageMax)
    end
    Logging.info("[PN] -----------------------------------------------")
end

-- Explain per-cluster steer detection and stage: pnStagesWhy <index>
function PN_Debug:cmdStagesWhy(idxStr)
    local idx = tonumber(idxStr or "")
    if idx == nil then
        Logging.info("[PN] Usage: pnStagesWhy <index>  (see pnDumpHusbandries)")
        return
    end
    local list = (PN_HusbandryScan and PN_HusbandryScan.getAll and PN_HusbandryScan.getAll()) or {}
    local e = list[idx]
    if not e or not e.clusterSystem then
        Logging.info("[PN] pnStagesWhy: no entry/cluster at index %s", tostring(idx))
        return
    end

    local species = _dbgNormSpecies(e.type or (e.__pn_last and e.__pn_last.species) or "ANIMAL")
    local okC, clusters = pcall(e.clusterSystem.getClusters, e.clusterSystem)
    if not okC or type(clusters) ~= "table" then
        Logging.info("[PN] pnStagesWhy: getClusters() failed")
        return
    end

    Logging.info("[PN] ---- WHY for #%d '%s' [%s] ----", idx, tostring(e.name or "?"), species)
    for _, c in pairs(clusters) do
        if type(c)=="table" and not c.isDead then
            local head    = _cNum(c)
            local gender  = _cGender(c) or "?"
            local ageM    = _cAgeMonths(c) or 0
            local hasFlag = _cCastrated(c)
            local byType  = _cLooksLikeSteer and _cLooksLikeSteer(c) or false
            local isCast  = hasFlag or byType
            local flags   = { lactating=_cLactating(c), castrated=isCast }
            local stage   = _dbgResolveStage(species, gender, ageM, flags)
            local reason  = hasFlag and "[flag]" or (byType and "[subType]") or ""
            Logging.info("[PN]   head=%3d | gender=%-6s | age=%5.1fm | cast=%5s %-9s | stage=%-8s | subType='%s'",
                head, gender, ageM, tostring(isCast), reason, tostring(stage), tostring(c.subType or c.typeName or ""))
        end
    end
    Logging.info("[PN] --------------------------------")
end

-- Dump non-function fields for each cluster: pnClusterKeys <index>
function PN_Debug:cmdClusterKeys(idxStr)
    local idx = tonumber(idxStr or "")
    if idx == nil then
        Logging.info("[PN] Usage: pnClusterKeys <index>  (see pnDumpHusbandries)")
        return
    end
    local list = (PN_HusbandryScan and PN_HusbandryScan.getAll and PN_HusbandryScan.getAll()) or {}
    local e = list[idx]
    if not e or not e.clusterSystem then
        Logging.info("[PN] pnClusterKeys: no entry/cluster at index %s", tostring(idx))
        return
    end
    local okC, clusters = pcall(e.clusterSystem.getClusters, e.clusterSystem)
    if not okC or type(clusters) ~= "table" then
        Logging.info("[PN] pnClusterKeys: getClusters() failed")
        return
    end

    Logging.info("[PN] ---- Cluster fields for #%d '%s' ----", idx, tostring(e.name or "?"))
    local ci = 0
    for _, c in pairs(clusters) do
        if type(c)=="table" and not c.isDead then
            ci = ci + 1
            Logging.info("[PN] [C%d] gender=%s ageM=%.1f head=%d subType='%s'",
                ci, tostring(_cGender(c) or "?"), _cAgeMonths(c) or 0, _cNum(c) or 0, tostring(c.subType or c.typeName or ""))
            for k,v in pairs(c) do
                local t = type(v)
                if t ~= "function" then
                    if t == "table" then
                        -- try a short summary
                        local n = 0; for _ in pairs(v) do n = n + 1; if n>5 then break end end
                        Logging.info("[PN]   - %-20s : table (%d keys)", tostring(k), n)
                    else
                        Logging.info("[PN]   - %-20s : %s = %s", tostring(k), t, tostring(v))
                    end
                end
            end
        end
    end
    Logging.info("[PN] --------------------------------")
end

-- Hunt for castration-like fields on clusters: pnFindCastration <index>
function PN_Debug:cmdFindCastration(idxStr)
    local idx = tonumber(idxStr or "")
    if idx == nil then
        Logging.info("[PN] Usage: pnFindCastration <index>  (see pnDumpHusbandries)")
        return
    end
    local list = (PN_HusbandryScan and PN_HusbandryScan.getAll and PN_HusbandryScan.getAll()) or {}
    local e = list[idx]
    if not e or not e.clusterSystem then
        Logging.info("[PN] pnFindCastration: no entry/cluster at index %s", tostring(idx))
        return
    end
    local okC, clusters = pcall(e.clusterSystem.getClusters, e.clusterSystem)
    if not okC or type(clusters) ~= "table" then
        Logging.info("[PN] pnFindCastration: getClusters() failed")
        return
    end

    Logging.info("[PN] ---- Find castration flags for #%d '%s' ----", idx, tostring(e.name or "?"))
    local ci = 0
    for _, c in pairs(clusters) do
        if type(c)=="table" and not c.isDead then
            ci = ci + 1
            local hints = {}
            for k,v in pairs(c) do
                if type(k)=="string" and k:lower():find("cast", 1, true) then
                    table.insert(hints, string.format("%s=%s", k, tostring(v)))
                end
            end
            local gender  = _cGender(c) or "?"
            local ageM    = _cAgeMonths(c) or 0
            local byType  = _cLooksLikeSteer and _cLooksLikeSteer(c) or false
            local hasFlag = _cCastrated(c)
            Logging.info("[PN] [C%d] head=%d gender=%s age=%.1fm subType='%s' | hasFlag=%s byType=%s | matches={%s}",
                ci, _cNum(c) or 0, gender, ageM, tostring(c.subType or c.typeName or ""), tostring(hasFlag), tostring(byType),
                table.concat(hints, ", "))
        end
    end
    Logging.info("[PN] --------------------------------")
end

function PN_Debug:cmdInspectHusbandry(idxStr)
    local idx = tonumber(idxStr or "")
    if idx == nil then
        Logging.info("[PN] Usage: pnInspect <index>  (see pnDumpHusbandries)")
        return
    end
    local list = (PN_HusbandryScan and PN_HusbandryScan.getAll and PN_HusbandryScan.getAll()) or {}
    local e = list[idx]
    if not e then
        Logging.info("[PN] pnInspect: no entry at index %s", tostring(idx))
        return
    end
    Logging.info("[PN] Inspect #%d: name=%s farm=%s type=%s cluster=%s",
        idx, tostring(e.name), tostring(e.farmId), tostring(e.type), tostring(e.clusterSystem ~= nil))

    local function dumpTable(label, t, max)
        Logging.info("[PN]  %s = %s", label, tostring(t))
        local n = 0
        for k, v in pairs(t or {}) do
            Logging.info("[PN]   - %s : %s", tostring(k), tostring(v))
            n = n + 1; if n >= (max or 20) then break end
        end
    end

    dumpTable("placeable", e.placeable, 25)
    if e.placeable and e.placeable.spec_husbandryAnimals then
        dumpTable("spec_husbandryAnimals", e.placeable.spec_husbandryAnimals, 50)
    end
    if e.clusterSystem then
        dumpTable("clusterSystem", e.clusterSystem, 50)
        if e.clusterSystem.getClusters then
            local ok, clusters = pcall(e.clusterSystem.getClusters, e.clusterSystem)
            Logging.info("[PN]  getClusters() ok=%s, result=%s", tostring(ok), tostring(clusters))
        end
        if e.clusterSystem.getNumOfAnimals then
            local ok, n = pcall(e.clusterSystem.getNumOfAnimals, e.clusterSystem)
            Logging.info("[PN]  getNumOfAnimals() ok=%s, n=%s", tostring(ok), tostring(n))
        end
    end
end

function PN_Debug:cmdInspectClusters(idxStr)
    local idx = tonumber(idxStr or "")
    if idx == nil then
        Logging.info("[PN] Usage: pnInspectClusters <index>  (see pnDumpHusbandries)")
        return
    end
    local list = (PN_HusbandryScan and PN_HusbandryScan.getAll and PN_HusbandryScan.getAll()) or {}
    local e = list[idx]
    if not e or not e.clusterSystem then
        Logging.info("[PN] pnInspectClusters: no entry/cluster at index %s", tostring(idx))
        return
    end

    local ok, clusters = pcall(e.clusterSystem.getClusters, e.clusterSystem)
    if not ok or type(clusters) ~= "table" then
        Logging.info("[PN] pnInspectClusters: getClusters() failed or not a table")
        return
    end

    local count = 0
    for k, c in pairs(clusters) do
        count = count + 1
        Logging.info("[PN]  Cluster key=%s  value=%s", tostring(k), tostring(c))
        local n = 0
        for ck, cv in pairs(c or {}) do
            Logging.info("[PN]    - %s : %s", tostring(ck), tostring(cv))
            n = n + 1; if n >= 20 then break end
        end
    end
    Logging.info("[PN]  total clusters=%d", count)
end

-- ---- fillType name helper (v2, intentionally later to override v1)
local function _ftName(idx)
    if g_fillTypeManager and g_fillTypeManager.getFillTypeNameByIndex then
        local n = g_fillTypeManager:getFillTypeNameByIndex(idx)
        if n and n ~= "" then return n end
    end
    return tostring(idx)
end

local function _hasFillUnit(p)
    return p and p.spec_fillUnit and p.spec_fillUnit.fillUnits and #p.spec_fillUnit.fillUnits > 0
end

-- v2: also show husbandryFood if present (some maps separate specs)
function PN_Debug:cmdInspectTrough(idxStr)
    local idx = tonumber(idxStr or "")
    if not idx then
        Logging.info("[PN] Usage: pnInspectTrough <index> (see pnDumpHusbandries)")
        return
    end
    local list = (PN_HusbandryScan and PN_HusbandryScan.getAll and PN_HusbandryScan.getAll()) or {}
    local e = list[idx]
    if not e or not e.placeable then
        Logging.info("[PN] pnInspectTrough: no entry/placeable at %s", tostring(idx))
        return
    end
    local p = e.placeable

    if _hasFillUnit(p) then
        local fus = p.spec_fillUnit.fillUnits
        Logging.info("[PN] Placeable '%s' has %d fillUnits:", tostring(e.name), #fus)
        for u, fu in ipairs(fus) do
            local lvl  = tonumber(fu.fillLevel or 0) or 0
            local lft  = fu.lastFillType or fu.fillType
            Logging.info("[PN]  unit %d: level=%.3f, fillType=%s", u, lvl, _ftName(lft))
            if fu.supportedFillTypes then
                local names = {}
                for ftIndex, allowed in pairs(fu.supportedFillTypes) do
                    if allowed then table.insert(names, _ftName(ftIndex)) end
                end
                table.sort(names)
                if #names > 0 then
                    Logging.info("[PN]   supported: %s", table.concat(names, ", "))
                end
            end
            if fu.fillLevels then
                local count = 0
                for ftIndex, v in pairs(fu.fillLevels) do
                    if count < 16 then
                        Logging.info("[PN]   level[%s]=%.3f", _ftName(ftIndex), tonumber(v or 0) or 0)
                    end
                    count = count + 1
                end
                if count > 16 then Logging.info("[PN]   ... (%d total entries)", count) end
            end
        end
        return
    end

    -- No fillUnit on this placeable. Some maps carry a husbandryFood spec with fillTypes listed:
    if p.spec_husbandryFood and p.spec_husbandryFood.fillTypes then
        local names = {}
        for ftIndex, allowed in pairs(p.spec_husbandryFood.fillTypes) do
            if allowed then table.insert(names, _ftName(ftIndex)) end
        end
        table.sort(names)
        Logging.info("[PN] '%s' has spec_husbandryFood; accepted: %s", tostring(e.name), table.concat(names, ", "))
    else
        Logging.info("[PN] '%s' has no fillUnit and no spec_husbandryFood", tostring(e.name))
    end
    Logging.info("[PN] Tip: try pnFindFeeder %d to locate a nearby feeder placeable.", idx)
end

function PN_Debug:cmdInspectFoodSpec(idxStr)
  local idx = tonumber(idxStr or "")
  if not idx then
    Logging.info("[PN] Usage: pnInspectFoodSpec <index>")
    return
  end
  local list = PN_HusbandryScan and PN_HusbandryScan.getAll and PN_HusbandryScan.getAll() or {}
  local e = list[idx]
  local p = e and e.placeable
  if not (p and p.spec_husbandryFood) then
    Logging.info("[PN] pnInspectFoodSpec: no spec_husbandryFood on entry %s", tostring(idx))
    return
  end
  local lv = p.spec_husbandryFood.fillLevels
  if type(lv) ~= "table" then
    Logging.info("[PN] pnInspectFoodSpec: no fillLevels table")
    return
  end
  local n = 0
  for ftIndex, v in pairs(lv) do
    Logging.info("[PN] food level[%s] = %.3f", _ftName(ftIndex), tonumber(v or 0) or 0)
    n = n + 1
  end
  if n == 0 then Logging.info("[PN] pnInspectFoodSpec: empty") end
end

-- =========================================================
-- Finder
-- =========================================================
function PN_Debug:cmdFindFeeder(idxStr, radiusStr)
    local idx = tonumber(idxStr or "")
    local radius = tonumber(radiusStr or "35") or 35  -- meters
    if not idx then
        Logging.info("[PN] Usage: pnFindFeeder <index> [radiusMeters]")
        return
    end
    local list = (PN_HusbandryScan and PN_HusbandryScan.getAll and PN_HusbandryScan.getAll()) or {}
    local e = list[idx]
    if not e or not e.placeable or not e.placeable.rootNode then
        Logging.info("[PN] pnFindFeeder: no entry/rootNode at %s", tostring(idx))
        return
    end
    local ex, ey, ez = getWorldTranslation(e.placeable.rootNode)
    local myFarm = e.farmId

    local candidates = {}
    -- Walk all known placeables (via PlaceableSystem or our scanner cache if exposed)
    local ps = g_placeableSystem or g_placeableManager or {}
    local function try(pl)
        if pl and pl ~= e.placeable and _hasFillUnit(pl) then
            -- same farm (when available)
            local pfarm = (pl.owningPlaceable and pl.owningPlaceable.farmId) or pl.farmId or pl.ownerFarmId
            if (myFarm == nil) or (pfarm == nil) or (pfarm == myFarm) then
                local rx = pl.rootNode or pl.nodeId or pl.node
                if rx then
                    local x, y, z = getWorldTranslation(rx)
                    local dx, dz = (x - ex), (z - ez)
                    local dist2 = dx*dx + dz*dz
                    table.insert(candidates, { pl=pl, dist2=dist2 })
                end
            end
        end
    end

    -- collect from PlaceableSystem / Manager
    if ps.placeables then
      for _, pl in ipairs(ps.placeables) do try(pl) end
    end
    if type(ps.getPlaceables) == "function" then
      local ok, arr = pcall(ps.getPlaceables, ps)
      if ok and type(arr) == "table" then
        for _, pl in ipairs(arr) do try(pl) end
      end
    end

    table.sort(candidates, function(a,b) return a.dist2 < b.dist2 end)

    local shown = 0
    for _, c in ipairs(candidates) do
        local dist = math.sqrt(c.dist2)
        if dist <= radius then
            shown = shown + 1
            local pl = c.pl
            Logging.info("[PN] Feeder candidate @ %.1fm: %s", dist, tostring(pl.typeName or pl.customEnvironment or pl))
            local fus = pl.spec_fillUnit.fillUnits
            for u, fu in ipairs(fus) do
                local lvl  = tonumber(fu.fillLevel or 0) or 0
                local lft  = fu.lastFillType or fu.fillType
                Logging.info("[PN]   unit %d: level=%.3f, currentFT=%s", u, lvl, _ftName(lft))
                if fu.supportedFillTypes then
                    local names = {}
                    for ftIndex, allowed in pairs(fu.supportedFillTypes) do
                        if allowed then table.insert(names, _ftName(ftIndex)) end
                    end
                    table.sort(names)
                    if #names > 0 then
                        Logging.info("[PN]    supported: %s", table.concat(names, ", "))
                    end
                end
            end
        end
        if shown >= 5 then break end -- avoid spam
    end

    if shown == 0 then
        Logging.info("[PN] No feeder placeable with fillUnits found within %.0fm of '%s'", radius, tostring(e.name))
    end
end

-- =========================================================
-- Mix override (set/clear/show)
-- =========================================================
function PN_Debug:cmdSetMix(idxStr, specStr)
    local idx = tonumber(idxStr)
    local list = (PN_HusbandryScan and PN_HusbandryScan.entries) or (PN_Core and PN_Core.entries)
    if not idx or not list or not list[idx] then
        Logging.info('[PN] Usage: pnSetMix <index> "TYPE=frac,TYPE=frac,..."')
        return
    end
    local mix, err = _parseMixSpec(specStr)
    if not mix then
        Logging.info("[PN] pnSetMix error: "..tostring(err))
        return
    end
    local e = list[idx]
    e.__pn_mixOverride = mix
    _printMix(string.format("[PN] Mix override set on %s: ", _entryLabel(e, idx)), mix)
end

function PN_Debug:cmdClearMix(idxStr)
    local idx = tonumber(idxStr)
    local list = (PN_HusbandryScan and PN_HusbandryScan.entries) or (PN_Core and PN_Core.entries)
    if not idx or not list or not list[idx] then
        Logging.info("[PN] Usage: pnClearMix <index>")
        return
    end
    local e = list[idx]
    e.__pn_mixOverride = nil
    Logging.info(string.format("[PN] Mix override cleared on %s", _entryLabel(e, idx)))
end

function PN_Debug:cmdShowMix(idxStr)
    local idx = tonumber(idxStr)
    local list = (PN_HusbandryScan and PN_HusbandryScan.entries) or (PN_Core and PN_Core.entries)
    if not idx or not list or not list[idx] then
        Logging.info("[PN] Usage: pnShowMix <index>")
        return
    end
    local e = list[idx]
    if e.__pn_mixOverride then
        _printMix(string.format("[PN] %s override: ", _entryLabel(e, idx)), e.__pn_mixOverride)
        return
    end
    -- Estimate from trough levels if possible
    local plc = e.placeable or e.feeder or e
    if plc and _isFeeder(plc) and plc.spec_husbandryFood and plc.spec_husbandryFood.fillLevels then
        local lvl = plc.spec_husbandryFood.fillLevels
        local total = 0
        for _,v in pairs(lvl) do total = total + (v or 0) end
        if total > 0 then
            local est = {}
            for id,v in pairs(lvl) do
                if (v or 0) > 0 then est[id] = (v or 0) / total end
            end
            _printMix(string.format("[PN] %s trough-estimated: ", _entryLabel(e, idx)), est)
            return
        end
    end
    Logging.info(string.format("[PN] %s has no override and trough composition not visible.", _entryLabel(e, idx)))
end

-- =========================================================
-- One-shot / simulation / feed manipulation / credit
-- =========================================================
function PN_Debug:cmdBeat(idxStr)
    if PN_HusbandryScan == nil or PN_HusbandryScan.getAll == nil or PN_Core == nil or PN_Core.updateHusbandry == nil then
        Logging.info("[PN] pnBeat: PN not ready")
        return
    end
    local idx = tonumber(idxStr or "")
    if idx == nil then
        Logging.info("[PN] Usage: pnBeat <index> (see pnDumpHusbandries)")
        return
    end
    local list = PN_HusbandryScan.getAll()
    local e = list[idx]
    if not e or not e.clusterSystem then
        Logging.info("[PN] pnBeat: no entry/cluster at index %s", tostring(idx))
        return
    end

    -- Refresh PN snapshot so nut/totals are current
    pcall(PN_Core.updateHusbandry, PN_Core, e, e.clusterSystem, 33, { forceBeat = true })

    -- Species inference (same as elsewhere)
    local function inferSpecies(entry)
        local function norm(s)
            s = tostring(s or ""):upper()
            if s == "CATTLE" then return "COW" end
            if s == "HEN"    then return "CHICKEN" end
            return s
        end
        if entry and entry.type and entry.type ~= "ANIMAL" then return norm(entry.type) end
        local cs = entry and entry.clusterSystem
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

    local species = inferSpecies(e)
    local name    = tostring(e.name or "?")

    -- Barn-level Nut ratio (0..1)
    local barnNut = 0
    if e.__pn_last and e.__pn_last.nutRatio ~= nil then
        barnNut = tonumber(e.__pn_last.nutRatio) or 0
    elseif PN_Core and PN_Core.getTotals then
        local okT, totals = pcall(PN_Core.getTotals, e)
        if okT and type(totals) == "table" then
            barnNut = tonumber(totals.nut or 0) or 0
        end
    end
    if barnNut < 0 then barnNut = 0 elseif barnNut > 1 then barnNut = 1 end

    -- Collect clusters → aggregate by resolved stage
    local okC, clusters = pcall(e.clusterSystem.getClusters, e.clusterSystem)
    if not okC or type(clusters) ~= "table" then
        Logging.info("[PN] pnBeat: getClusters() failed")
        return
    end

    local agg = {} -- stage -> { head, wSum }
    local totalHead = 0
    for _, c in pairs(clusters) do
        if type(c)=="table" and not c.isDead then
            local head       = _cNum(c)
            local ageM       = _cAgeMonths(c)
            local gender     = _cGender(c)
            local looksSteer = _cLooksLikeSteer and _cLooksLikeSteer(c) or false
            local isCast     = (_cCastrated and _cCastrated(c)) or looksSteer
            local flags      = { lactating=_cLactating(c), castrated=isCast }
            local stage      = (_dbgResolveStage and _dbgResolveStage(species, gender, ageM, flags)) or "DEFAULT"
            local avgW       = _cAvgWeightKg(c)

            local t = agg[stage]
            if not t then t = { head=0, wSum=0 } ; agg[stage]=t end
            t.head = t.head + head
            t.wSum = t.wSum + (avgW * head)
            totalHead = totalHead + head
        end
    end

    -- DM available (kg) in trough
    local function _barnAvailableDmKg(entry)
        local p = entry and entry.placeable
        if not p then return 0 end
        local total = 0
        -- Preferred: spec_fillUnit per-unit levels
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
                            local nameU = tostring((g_fillTypeManager and g_fillTypeManager.getFillTypeNameByIndex and g_fillTypeManager:getFillTypeNameByIndex(ftIndex)) or ftIndex):upper()
                            if PN_Core and PN_Core.feedAliases and PN_Core.feedAliases[nameU] then
                                nameU = tostring(PN_Core.feedAliases[nameU]):upper()
                            end
                            local fmRow = PN_Core and PN_Core.feedMatrix and PN_Core.feedMatrix[nameU] or nil
                            local dmFrac = (fmRow and fmRow.dm) and tonumber(fmRow.dm) or 0
                            total = total + (liters * mpl * dmFrac)
                        end
                    end
                end
            end
        end
        -- Fallback: spec_husbandryFood aggregate
        if total == 0 and p.spec_husbandryFood and p.spec_husbandryFood.fillLevels then
            for ftIndex, L in pairs(p.spec_husbandryFood.fillLevels) do
                local liters = tonumber(L or 0) or 0
                if liters > 0 then
                    local mpl = 1.0
                    if g_fillTypeManager and g_fillTypeManager.fillTypes and g_fillTypeManager.fillTypes[ftIndex] then
                        mpl = tonumber(g_fillTypeManager.fillTypes[ftIndex].massPerLiter or 1.0) or 1.0
                    end
                    local nameU = tostring((g_fillTypeManager and g_fillTypeManager.getFillTypeNameByIndex and g_fillTypeManager:getFillTypeNameByIndex(ftIndex)) or ftIndex):upper()
                    if PN_Core and PN_Core.feedAliases and PN_Core.feedAliases[nameU] then
                        nameU = tostring(PN_Core.feedAliases[nameU]):upper()
                    end
                    local fmRow = PN_Core and PN_Core.feedMatrix and PN_Core.feedMatrix[nameU] or nil
                    local dmFrac = (fmRow and fmRow.dm) and tonumber(fmRow.dm) or 0
                    total = total + (liters * mpl * dmFrac)
                end
            end
        end
        return total
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

    -- Supply factor (0..1) from live DM vs required DM by stages
    local supplyF = 1.0
    do
        local avail = _barnAvailableDmKg(e)
        local req = 0
        for st, t in pairs(agg) do
            req = req + (_dmDemandKgHd(species, st) * (t.head or 0))
        end
        if req > 0 then
            supplyF = math.max(0, math.min(1, avail / req))
        end
    end

    -- Sort stages in species-aware order (same order as overlay)
    local order = {
        COW     = { CALF=1, HEIFER=2, LACT=3, DRY=4, YEARLING=5, STEER=6, BULL=7, OVERAGE=8, DEFAULT=99 },
        SHEEP   = { LAMB=1, EWE_LACT=2, EWE_DRY=3, RAM_GROW=4, RAM_ADULT=5, DEFAULT=99 },
        PIG     = { PIGLET=1, GILT=2, SOW_LACT=3, SOW_GEST=4, BARROW=5, BOAR=6, DEFAULT=99 },
        GOAT    = { KID=1, DOE_LACT=2, DOE_DRY=3, BUCK_GROW=4, BUCK_ADULT=5, DEFAULT=99 },
        CHICKEN = { CHICK=1, BROILER_F=2, LAYER=3, BROILER_M=4, ROOSTER=5, DEFAULT=99 },
        ANIMAL  = { DEFAULT=1 }
    }
    local ord = order[(tostring(species or "ANIMAL")):upper()] or order.ANIMAL
    local keys = {}
    for st,_ in pairs(agg) do table.insert(keys, st) end
    table.sort(keys, function(a,b)
        local oa = ord[a] or ord.DEFAULT or 99
        local ob = ord[b] or ord.DEFAULT or 99
        if oa == ob then return a < b end
        return oa < ob
    end)

    -- Print one line per stage with ADG adjusted by maturity + supply
    local nutPct = math.floor(barnNut*100 + 0.5)
    for _, st in ipairs(keys) do
        local t = agg[st]
        local avgW = (t.head > 0) and (t.wSum / t.head) or 0

        -- Base ADG from PN_Core
        local adg = 0.10 * barnNut
        if PN_Core and PN_Core.adgFor then
            local okG, g = pcall(PN_Core.adgFor, PN_Core, species, st, avgW, barnNut)
            if okG and type(g)=="number" then adg = g end
        end

        -- Maturity taper (matches PN_Core.updateHusbandry)
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

        -- Apply barn supply factor (live trough)
        adg = adg * (supplyF or 1.0)

        -- Optional negative ADG (starvation) per PN_Settings
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

        Logging.info("[PN] %s [%s/%s] | head=%d | avgW=%.2fkg | Nut=%d%% | ADG=%.3f kg/d",
            name, species, tostring(st), t.head or 0, avgW, nutPct, adg)
    end
end

function PN_Debug:cmdSim(idxStr, spanStr)
    if PN_HusbandryScan == nil or PN_HusbandryScan.getAll == nil or PN_Core == nil or PN_Core.updateHusbandry == nil then
        Logging.info("[PN] pnSim: PN not ready")
        return
    end
    local idx = tonumber(idxStr or "")
    if idx == nil then
        Logging.info("[PN] Usage: pnSim <index> <hours|e.g. 6 or 0.5d for days>  (see pnDumpHusbandries)")
        return
    end
    local list = PN_HusbandryScan.getAll()
    local e = list[idx]
    if not e or not e.clusterSystem then
        Logging.info("[PN] pnSim: no entry/cluster at index %s", tostring(idx))
        return
    end

    local hours = tonumber(spanStr or "")
    if not hours then
        -- allow suffix 'd' for days
        local s = tostring(spanStr or ""):lower()
        local num = tonumber(s:match("^([%d%.]+)d$") or "")
        if num then hours = num * 24 end
    end
    if not hours or hours <= 0 then
        Logging.info("[PN] pnSim: please provide a positive number of hours (e.g. 6) or days (e.g. 0.5d)")
        return
    end

    local dtMs = math.floor(hours * 60 * 60 * 1000)  -- ms in the simulated window
    pcall(PN_Core.updateHusbandry, PN_Core, e, e.clusterSystem, dtMs, { forceBeat = true })

    -- Show the result immediately
    local name    = tostring(e.name or "?")
    local last    = e.__pn_last or {}
    local nutPct  = math.floor((last.nutRatio or 1) * 100 + 0.5)
    local adg     = last.effADG or 0
    local t       = e.__pn_totals or {}
    Logging.info("[PN] SIM '%s' %s | dT=%sh | Nut=%d%% | ADG=%.2f kg/d | head=%d avgW=%.2f kg",
    name, (last.species or "?"), tostring(hours), nutPct, adg, (t.animals or 0), (t.avgWeight or 0))

end

function PN_Debug:cmdClearFeed(idxStr, pctStr)
  if PN_HusbandryScan == nil or PN_HusbandryScan.getAll == nil then
    Logging.info("[PN] pnClearFeed: PN not ready"); return
  end
  local idx = tonumber(idxStr or "")
  if idx == nil then
    Logging.info("[PN] Usage: pnClearFeed <index> [percent 0..100]  (see pnDumpHusbandries)"); return
  end
  local pct = tonumber(pctStr or "100") or 100
  if pct < 0 then pct = 0 elseif pct > 100 then pct = 100 end
  local list = PN_HusbandryScan.getAll()
  local e = list and list[idx]
  if not e then Logging.info("[PN] pnClearFeed: no entry at index %s", tostring(idx)); return end

  local p = (e.placeable or e)
  local removedL = 0

  local function _massPerL(ftIndex)
    if g_fillTypeManager and g_fillTypeManager.fillTypes and g_fillTypeManager.fillTypes[ftIndex] then
      return tonumber(g_fillTypeManager.fillTypes[ftIndex].massPerLiter or 1.0) or 1.0
    end
    return 1.0
  end

  -- Try API first (preferred), otherwise fall back to raw table edits
  local canAPI = (p.addFillUnitFillLevel ~= nil)

  -- 1) spec_fillUnit per-unit levels
  if p.spec_fillUnit and p.spec_fillUnit.fillUnits then
    for unitIndex, fu in ipairs(p.spec_fillUnit.fillUnits) do
      local levels = fu and fu.fillLevels
      if type(levels) == "table" then
        for ftIndex, liters in pairs(levels) do
          local L = tonumber(liters or 0) or 0
          if L > 0 then
            local take = L * (pct/100)
            if canAPI then
              p:addFillUnitFillLevel(nil, unitIndex, -take, ftIndex, ToolType.UNDEFINED)
            else
              levels[ftIndex] = L - take
            end
            removedL = removedL + take
          end
        end
      end
    end
  end

  -- 2) spec_husbandryFood aggregate levels (fallback)
  if p.spec_husbandryFood and p.spec_husbandryFood.fillLevels then
    for ftIndex, liters in pairs(p.spec_husbandryFood.fillLevels) do
      local L = tonumber(liters or 0) or 0
      if L > 0 then
        local take = L * (pct/100)
        p.spec_husbandryFood.fillLevels[ftIndex] = L - take
        removedL = removedL + take
      end
    end
  end

  -- Refresh PN snapshot so overlay updates right away
  if PN_Core and PN_Core.updateHusbandry and e and e.clusterSystem then
    pcall(PN_Core.updateHusbandry, PN_Core, e, e.clusterSystem, 33, { source="pnClearFeed" })
  end

  Logging.info("[PN] Cleared %.0f%% feed in '%s' (%.0f L total; ~%.0f kg)", pct, tostring(e.name or "?"),
    removedL, removedL * _massPerL(1))
end

-- pnCredit <index> <FILLTYPE_NAME> <kg>
function PN_Debug:cmdCredit(idxStr, ftName, kgStr)
  local idx = tonumber(idxStr or "")
  local kg  = tonumber(kgStr or "")
  if not idx or not ftName or not kg or kg <= 0 then
    Logging.info("[PN] Usage: pnCredit <index> <FILLTYPE_NAME> <kg>")
    return
  end
  local list = PN_HusbandryScan.getAll()
  local e = list[idx]
  if not e or not e.clusterSystem then
    Logging.info("[PN] pnCredit: no entry/cluster at %s", tostring(idx))
    return
  end
  if not g_fillTypeManager or not g_fillTypeManager.getFillTypeIndexByName then
    Logging.info("[PN] pnCredit: fillTypeManager not available")
    return
  end
  local ftIndex = g_fillTypeManager:getFillTypeIndexByName(ftName)
  if not ftIndex then
    Logging.info("[PN] pnCredit: unknown fill type '%s'", tostring(ftName))
    return
  end
  -- one-shot heartbeat with injected intake
  local ctx = { injectIntake = { [ftIndex] = kg } }
  pcall(PN_Core.updateHusbandry, PN_Core, e, e.clusterSystem, 33, ctx)
  if PN_Core.formatBeatLine then
    Logging.info("[PN] %s", PN_Core.formatBeatLine(e))
  end
end

-- =========================================================
-- UI / toggles / settings
-- =========================================================
-- Set heartbeat period or disable it: pnHeartbeat <ms|off>
function PN_Debug:cmdHeartbeat(periodStr)
    if periodStr == nil or periodStr == "" then
        Logging.info("[PN] pnHeartbeat usage: pnHeartbeat <milliseconds|off>. Current=%s",
            tostring(PN_HEARTBEAT_MS))
        return
    end
    if tostring(periodStr):lower() == "off" then
        PN_HEARTBEAT_MS = math.huge  -- effectively disables periodic logging
        Logging.info("[PN] Heartbeat disabled (pnBeat still works).")
        return
    end
    local ms = tonumber(periodStr)
    if not ms or ms < 100 then
        Logging.info("[PN] pnHeartbeat: please provide milliseconds >= 100 or 'off'")
        return
    end
    PN_HEARTBEAT_MS = ms
    Logging.info("[PN] Heartbeat set to every %d ms.", ms)
end

function PN_Debug:cmdHeartbeatTick(args)
    return self:cmdBeat(args)
end

function PN_Debug:cmdOverlayMine(state)
    if PN_UI == nil then
        Logging.info("[PN] pnOverlayMine: PN_UI not available")
        return
    end
    local s = tostring(state or ""):lower()
    if s == "on" or s == "true" or s == "1" then
        PN_UI.onlyMyFarm = true
    elseif s == "off" or s == "false" or s == "0" or s == "all" then
        PN_UI.onlyMyFarm = false
    else
        -- toggle if no/unknown arg
        PN_UI.onlyMyFarm = not (PN_UI.onlyMyFarm == true)
    end
    local mode = (PN_UI.onlyMyFarm and "My Farm Only" or "All Farms")
    Logging.info("[PN] Overlay ownership filter now: %s", mode)
end

-- Toggle overlay from console
function PN_Debug:cmdOverlay()
    if PN_UI and PN_UI.toggle then PN_UI.toggle() end
end

-- Show next barn in single-barn overlay (wraps around; turns on if off)
function PN_Debug:cmdOverlayNext()
    if not PN_UI then Logging.info("[PN] pnOverlayNext: PN_UI not available"); return end
    -- If UI exposes single-barn helpers, use them
    if PN_UI.buildBarnList and PN_UI._selectBarn then
        PN_UI.enabled = true
        PN_UI.mode    = "single"
        local list = PN_UI.buildBarnList() or {}
        if #list == 0 then Logging.info("[PN] pnOverlayNext: no barns to show"); return end
        local idx = (PN_UI._barnIdx or 0) + 1
        if idx > #list then idx = 1 end
        PN_UI._selectBarn(idx)
		PN_UI._nextRefreshAt = 0
        local e = list[idx]
        Logging.info("[PN] Overlay: showing #%d/%d '%s'", idx, #list, tostring(e and e.name or "?"))
        return
    end
    -- Fallback: just cycle once
    if PN_UI.cycleBarnOverlay then PN_UI.cycleBarnOverlay() end
end

-- Show previous barn in single-barn overlay (wraps around; turns on if off)
function PN_Debug:cmdOverlayPrev()
    if not PN_UI then Logging.info("[PN] pnOverlayPrev: PN_UI not available"); return end
    if PN_UI.buildBarnList and PN_UI._selectBarn then
        PN_UI.enabled = true
        PN_UI.mode    = "single"
        local list = PN_UI.buildBarnList() or {}
        if #list == 0 then Logging.info("[PN] pnOverlayPrev: no barns to show"); return end
        local idx = (PN_UI._barnIdx or 1) - 1
        if idx < 1 then idx = #list end
        PN_UI._selectBarn(idx)
		PN_UI._nextRefreshAt = 0
        local e = list[idx]
        Logging.info("[PN] Overlay: showing #%d/%d '%s'", idx, #list, tostring(e and e.name or "?"))
        return
    end
    -- Fallback: two cycles to simulate "prev" (not perfect, but safe)
    if PN_UI.cycleBarnOverlay then PN_UI.cycleBarnOverlay(); PN_UI.cycleBarnOverlay() end
end

function PN_Debug:cmdPNReload()
    if not PN_Settings or not PN_Settings.load or not PN_Core or not PN_Core.init then
        Logging.info("[PN] pnPNReload: PN not ready"); return
    end
    local cfg = PN_Settings.load()
    PN_Core.init(cfg)
    Logging.info("[PN] Reloaded PN settings (including external XML packs).")
end

function PN_Debug:cmdIntakeDebug(state)
    local s = tostring(state or ""):lower()
    if s == "on" or s == "true" or s == "1" then
        _G.PN_INTAKE_DEBUG = true
    elseif s == "off" or s == "false" or s == "0" then
        _G.PN_INTAKE_DEBUG = false
    else
        _G.PN_INTAKE_DEBUG = not (_G.PN_INTAKE_DEBUG == true)
    end
    Logging.info("[PN] Intake debug is %s", (_G.PN_INTAKE_DEBUG and "ON" or "OFF"))
end

-- Set PN_Logger level from console (TRACE|DEBUG|INFO|WARN|ERROR)
function PN_Debug:cmdSetLogLevel(level)
    if PN_Logger and PN_Logger.setLevel then
        PN_Logger:setLevel(level)
    else
        Logging.info("[PN] Logger not available; level not changed.")
    end
end

-- =========================================================
-- Extra debug conveniences
-- =========================================================
function PN_Debug:cmdListMods()
    local mm = g_modManager
    if not mm or not mm.mods then
        Logging.info("[PN] No mod manager or mods list.")
        return
    end
    Logging.info("[PN] Active mods:")
    for _,m in ipairs(mm.mods) do
        local dir = m.modDir or "?"
        local title = m.title or m.name or "?"
        Logging.info(string.format("  - %s  (%s)", dir, title))
    end
end

function PN_Debug:cmdDumpFillTypes()
    local fm = g_fillTypeManager
    if not fm then Logging.info("[PN] No fillTypeManager"); return end
    local names = {
        "GRASS","HAY","SILAGE","STRAW","MAIZE","CORN","WHEAT","BARLEY","OAT",
        "SORGHUM","SOYBEAN","PEA","PEAS","CHICKPEA","CHICKPEAS","CANOLA","FLAX",
        "RYE","TRITICALE","ALFALFA","ALFALFA_HAY","ALFALFA_SILAGE"
    }
    Logging.info("[PN] FillType presence:")
    for _,n in ipairs(names) do
        local idx = fm:getFillTypeByName(n)
        if idx then
            local title = fm.getFillTypeTitleByIndex and (fm:getFillTypeTitleByIndex(idx) or "")
            Logging.info(string.format("  %s -> id %d %s", n, idx, title ~= "" and ("(title="..title..")") or ""))
        else
            Logging.info(string.format("  %s -> MISSING", n))
        end
    end
end

-- Aliases to clarify meaning
-- (cmdBeat = one-shot tick; cmdHeartbeat = set heartbeat period)
PN_Debug.cmdHeartbeatTick = PN_Debug.cmdBeat
PN_Debug.cmdHeartbeatSet  = PN_Debug.cmdHeartbeat

-- =====================
-- Console registration
-- =====================
if addConsoleCommand ~= nil then
    -- Lists / CSV exports
    addConsoleCommand("pnDumpHusbandries",    "List PN-scanned husbandries",                  "cmdDumpHusbandries",    PN_Debug)
    addConsoleCommand("pnDumpHusbandriesCSV", "Export PN-scanned husbandries to CSV",         "cmdDumpHusbandriesCSV", PN_Debug)

    -- Inspectors
    addConsoleCommand("pnInspect",            "Inspect PN entry (alias of pnInspectHusbandry)","cmdInspectHusbandry",  PN_Debug)
    addConsoleCommand("pnInspectHusbandry",   "Inspect PN entry (by index)",                   "cmdInspectHusbandry",  PN_Debug)
    addConsoleCommand("pnInspectClusters",    "Inspect clusters for a PN entry",               "cmdInspectClusters",   PN_Debug)
    addConsoleCommand("pnInspectTrough",      "Inspect trough fillUnits/levels",               "cmdInspectTrough",     PN_Debug)
    addConsoleCommand("pnInspectFoodSpec",    "Dump spec_husbandryFood levels",                "cmdInspectFoodSpec",   PN_Debug)

    -- Feeder finder
    addConsoleCommand("pnFindFeeder",         "Find a nearby feeder (fillUnit) for the entry", "cmdFindFeeder",        PN_Debug)

    -- One-shot nutrition tick / simulation
    addConsoleCommand("pnBeat",               "Trigger one PN heartbeat for an entry",         "cmdHeartbeatTick",     PN_Debug)
    addConsoleCommand("pnSim",                "Simulate PN for an entry over hours/days",      "cmdSim",               PN_Debug)

    -- Feed + nutrition controls
    addConsoleCommand("pnClearFeed",          "Clear/Reduce trough feed % for an entry",       "cmdClearFeed",         PN_Debug)
    addConsoleCommand("pnNut",                "Set/view barn nutrition ratio (0..1)",          "cmdNut",               PN_Debug)
    addConsoleCommand("pnCredit",             "Credit intake to a barn (kg)",                  "cmdCredit",            PN_Debug)
    addConsoleCommand("pnAutoConsume",        "Toggle PN auto consumption (on/off)",           "cmdAutoConsume",       PN_Debug)
    addConsoleCommand("pnIntakeDebug",        "Toggle PN intake debug (on/off)",               "cmdIntakeDebug",       PN_Debug)

    -- UI / reload / heartbeat period / logging
    addConsoleCommand("pnOverlay",            "Toggle PN overlay",                              "cmdOverlay",           PN_Debug)
    addConsoleCommand("pnOverlayMine",        "Filter overlay to my farm only (on/off|all)",    "cmdOverlayMine",       PN_Debug)
	addConsoleCommand("pnOverlayNext", "Overlay: show next barn (single mode)",     "cmdOverlayNext", PN_Debug)
	addConsoleCommand("pnOverlayPrev", "Overlay: show previous barn (single mode)", "cmdOverlayPrev", PN_Debug)
    addConsoleCommand("pnPNReload",           "Reload PN settings/XML packs",                   "cmdPNReload",          PN_Debug)
    addConsoleCommand("pnHeartbeat",          "Set heartbeat period ms (or 'off')",             "cmdHeartbeatSet",      PN_Debug)
    addConsoleCommand("pnSetLogLevel",        "Set PN log level (TRACE|DEBUG|INFO|WARN|ERROR)", "cmdSetLogLevel",       PN_Debug)

    -- Diagnostics & fixers
    addConsoleCommand("pnDiag",               "Print PN module readiness",                      "cmdDiag",              PN_Debug)
    addConsoleCommand("pnFixEvents",          "Restore PN_Events methods if clobbered",         "cmdFixEvents",         PN_Debug)
	
    addConsoleCommand("pnStages",             "Breakdown animals by stage for an entry",        "cmdStages",            PN_Debug)
    addConsoleCommand("pnStagesAll",          "Breakdown animals by stage for all entries",     "cmdStagesAll",         PN_Debug)
	addConsoleCommand("pnStagesWhy", 		  "Explain steer detection & stage per cluster", 	"cmdStagesWhy", 		PN_Debug)

	addConsoleCommand("pnClusterKeys",   "List non-function fields for clusters",       "cmdClusterKeys",   PN_Debug)
	addConsoleCommand("pnFindCastration","Search cluster fields for castration hints",  "cmdFindCastration",PN_Debug)

    Logging.info("[PN] Console commands registered (debug).")
else
    Logging.info("[PN] Console: addConsoleCommand not available at load")
end



-- Helper: print warning if any steer is overage in a barn entry
local function PN_Debug_warnOverage(entry, stageLabel)
    if stageLabel == "OVERAGE" then
        Logging.warning("[PN] %s | steer OVERAGE: age %s mo. Consider selling.",
            tostring(entry.name or entry.barnName or "husbandry"),
            tostring(entry.ageMonths or "?"))
    end
end

