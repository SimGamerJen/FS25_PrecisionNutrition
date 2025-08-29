PN_Core = PN_Core or {}

-- === Config wiring (single source of truth) ===
local cfg = nil
function PN_Core.init(settings)
    cfg = settings
end

-- === Nutrition ratio per barn (0..1), default 1.0 ===
PN_Core._nutBarns = PN_Core._nutBarns or {}   -- key by entry table (stable per session)
local function _getKey(entry) return entry end
function PN_Core.setBarnNutrition(entry, ratio)
    ratio = math.max(0, math.min(1, tonumber(ratio) or 1))
    PN_Core._nutBarns[_getKey(entry)] = ratio
end
local function _getBarnNutrition(entry)
    local r = PN_Core._nutBarns[_getKey(entry)]
    if r == nil then r = 1.0 end
    return r
end

-- === Species + stage helpers (multi-species, Option A) ===
local function normSpecies(s)
    s = tostring(s or ""):upper()
    if s == "CATTLE" then return "COW" end
    if s == "HEN"    then return "CHICKEN" end
    if s == "COW" or s == "SHEEP" or s == "PIG" or s == "GOAT" or s == "CHICKEN" then return s end
    return "COW"
end

local function inferSpecies(entry, clusterSystem)
    if entry and entry.type and entry.type ~= "ANIMAL" then
        return normSpecies(entry.type)
    end
    if clusterSystem and clusterSystem.getClusters then
        local ok, clusters = pcall(clusterSystem.getClusters, clusterSystem)
        if ok and type(clusters) == "table" then
            for _, c in pairs(clusters) do
                local st = tostring(c and c.subType or ""):upper()
                if st:find("COW",1,true) or st:find("BULL",1,true) then return "COW" end
                if st:find("SHEEP",1,true) then return "SHEEP" end
                if st:find("PIG",1,true)   then return "PIG" end
                if st:find("GOAT",1,true)  then return "GOAT" end
                if st:find("CHICK",1,true) or st:find("HEN",1,true) then return "CHICKEN" end
            end
        end
    end
    return "COW"
end

local function getStage(species, ageM)
    species = normSpecies(species)
    local stages = cfg and cfg.stages and cfg.stages[species]
    if type(stages) == "table" then
        for _, s in ipairs(stages) do
            if (ageM or 0) >= (s.minAgeM or 0) and (ageM or 0) < (s.maxAgeM or math.huge) then
                return s
            end
        end
        if stages.default then return stages.default end
    end
    return { name="DEFAULT", baseADG=0, minAgeM=0, maxAgeM=math.huge }
end

-- === Weight application (Phase 1 live effect) ===
local function _applyWeightDeltaToCluster(c, dKg)
    if type(dKg) ~= "number" or dKg == 0 then return false end
    if type(c) == "table" then
        if type(c.setWeight) == "function" then
            local ok = pcall(c.setWeight, c, (tonumber(c.weight or 0) or 0) + dKg)
            if ok then return true end
        end
        if type(c.addWeight) == "function" then
            local ok = pcall(c.addWeight, c, dKg)
            if ok then return true end
        end
        if c.weight ~= nil then
            local w = tonumber(c.weight) or 0
            c.weight = w + dKg
            return true
        end
    end
    return false
end

-- Fallback species meta if PN_Settings doesn't define it
local _SPECIES_META = {
    COW     = { matureKg = 650, matureAgeM = 24 },
    SHEEP   = { matureKg = 75,  matureAgeM = 12 },
    PIG     = { matureKg = 120, matureAgeM = 8  },
    GOAT    = { matureKg = 65,  matureAgeM = 12 },
    CHICKEN = { matureKg = 3,   matureAgeM = 5  },
}

local function _getSpeciesMeta(species)
    species = species or "COW"
    -- If you later add cfg.meta[species] in PN_Settings, this will use it:
    local m = (cfg and cfg.meta and cfg.meta[species]) or _SPECIES_META[species] or _SPECIES_META.COW
    return { matureKg = tonumber(m.matureKg) or 650, matureAgeM = tonumber(m.matureAgeM) or 24 }
end

-- Try to infer average age (months) from clusters; fall back to weight-based estimate
local function _inferAverageAgeMonths(species, clusters)
    if type(clusters) ~= "table" then return 0 end

    local n, ageSum, wSum = 0, 0, 0
    local foundExplicit = false

    for _, c in pairs(clusters) do
        if type(c) == "table" and not c.isDead then
            -- 1) explicit age fields we might encounter
            local a = rawget(c, "ageMonths") or rawget(c, "age") or rawget(c, "months") or rawget(c, "ageInMonths")
            if type(a) == "number" and a >= 0 then
                ageSum = ageSum + a
                foundExplicit = true
            end
            -- 2) collect weight for fallback
            local w = tonumber(c.weight or 0) or 0
            wSum = wSum + w
            n = n + 1
        end
    end

    if n == 0 then return 0 end
    if foundExplicit and ageSum > 0 then
        return ageSum / n
    end

    -- Fallback: infer from average weight
    local avgW = (wSum > 0) and (wSum / n) or 0
    local meta = _getSpeciesMeta(species)
    local frac = 0
    if meta.matureKg > 0 then frac = math.min(1.0, math.max(0.0, avgW / meta.matureKg)) end
    -- assume roughly linear growth to maturity
    local estAge = frac * meta.matureAgeM
    return estAge
end

-- Returns effective ADG (kg/d) actually applied (per head)
local function _tickWeight(entry, clusterSystem, species, dtMs)
    if not (g_server and clusterSystem and clusterSystem.getClusters) then return 0 end

    local ok, clusters = pcall(clusterSystem.getClusters, clusterSystem)
    if not ok or type(clusters) ~= "table" then return 0 end

    -- Infer average age (months) and select stage accordingly
    local ageM    = _inferAverageAgeMonths(species, clusters)
    local stage   = getStage(species, ageM)
    local baseADG = stage.baseADG or 0

    local nut    = _getBarnNutrition(entry) -- 0..1
    local effADG = baseADG * nut            -- kg/d per head

    -- Nothing to do if paused/zero timestep or zero ADG
    local ms = tonumber(dtMs) or 0
    if effADG == 0 or ms <= 0 then return effADG end

    -- Convert day rate → per-tick delta
    local dDays       = ms / 86400000.0
    local dKgPerHead  = effADG * dDays

    for _, c in pairs(clusters) do
        if type(c) == "table" and not c.isDead then
            _applyWeightDeltaToCluster(c, dKgPerHead)
        end
    end
    return effADG
end


-- === Safe stub for future diet math (returns nil until wired) ===
function PN_Core.calcTick(species, ageMonths, consumedByFillType, headcount, dtMs)
    -- Keep signature stable; return a small record if/when needed.
    if not cfg then return nil end
    species = normSpecies(species)
    local S = getStage(species, ageMonths or 0)
    return {
        species = species,
        stage   = S.name,
        head    = tonumber(headcount or 0) or 0,
        baseADG = S.baseADG or 0
    }
end

-- === Per-husbandry update (called by PN_Debug:pnBeat and/or periodic) ===
function PN_Core:updateHusbandry(entry, clusterSystem, dtMs, ctx)
    local species = inferSpecies(entry, clusterSystem)
    if clusterSystem == nil or clusterSystem.getClusters == nil then return end

    local ok, clusters = pcall(clusterSystem.getClusters, clusterSystem)
    if not ok or type(clusters) ~= "table" then return end

    -- Aggregate simple stats
    local totals = { animals=0, bulls=0, cows=0, pregnant=0, weightSum=0, bySubType={} }
    for _, c in pairs(clusters) do
        if type(c) == "table" and not c.isDead then
            totals.animals = totals.animals + 1
            local g = tostring(c.gender or ""):lower()
            if g == "male" then totals.bulls = totals.bulls + 1 end
            if g == "female" then
                totals.cows = totals.cows + 1
                if c.isPregnant then totals.pregnant = totals.pregnant + 1 end
            end
            totals.weightSum = totals.weightSum + (tonumber(c.weight or 0) or 0)
            local st = tostring(c.subType or "?")
            totals.bySubType[st] = (totals.bySubType[st] or 0) + 1
        end
    end
    totals.avgWeight = (totals.animals > 0) and (totals.weightSum / totals.animals) or 0

    -- Phase 1: apply nutrition → weight
    local effADG = _tickWeight(entry, clusterSystem, species, dtMs)

    -- Snapshot for overlay
    entry.__pn_last = entry.__pn_last or {}
    entry.__pn_last.effADG   = effADG or 0
    entry.__pn_last.nutRatio = _getBarnNutrition(entry)
    entry.__pn_last.species  = species

    -- Heartbeat logging (server-only)
    PN_HEARTBEAT_MS = PN_HEARTBEAT_MS or 3000
    local isMp  = g_currentMission and g_currentMission.missionDynamicInfo and g_currentMission.missionDynamicInfo.isMultiplayer
    local force = (ctx and ctx.forceBeat) == true
    if not (isMp and not g_server) then
        entry.__pn_lastBeat = entry.__pn_lastBeat or 0
        entry.__pn_accum    = (entry.__pn_accum or 0) + (dtMs or 0)
        local firstPrint = (entry.__pn_lastBeat == 0)
        local due        = entry.__pn_accum >= (PN_HEARTBEAT_MS or 3000)
        if force or firstPrint or due then
			local nutPct = math.floor((entry.__pn_last and entry.__pn_last.nutRatio or _getBarnNutrition(entry)) * 100 + 0.5)
			local adg    = (entry.__pn_last and entry.__pn_last.effADG) or 0
			Logging.info("[PN] %s [%s] | head=%d (M:%d / F:%d, preg=%d) avgW=%.2fkg | Nut=%d%% | ADG=%.3f kg/d",
			tostring(entry.name), species,
			totals.animals, totals.bulls, totals.cows, totals.pregnant, totals.avgWeight,
			nutPct, adg)

            entry.__pn_lastBeat = g_time or 0
            entry.__pn_accum    = 0
        end
    end

    entry.__pn_totals = totals
end

return PN_Core
