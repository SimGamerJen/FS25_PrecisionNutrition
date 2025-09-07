-- PN_CoreCompat.lua (v3)
-- Compatibility shims for PN_Test and tooling without editing PN_Core.lua directly.
-- Load this AFTER PN_Core.lua in modDesc.xml.

PN_Core = PN_Core or {}

local function _u(s) return tostring(s or ""):upper() end
local function _lb(v)
    if v == nil then return false end
    local t = type(v)
    if t == "boolean" then return v end
    if t == "number" then return v ~= 0 end
    local s = tostring(v):lower()
    return (s == "1" or s == "true" or s == "yes" or s == "y")
end

-- Embedded fallback stages (COW only) if PN_Settings.stages is not initialized yet
local _fallbackStages = {
    COW = {
        -- FEMALE
        { name="CALF",     gender="female", minAgeM=0,   maxAgeM=8,   baseADG=0.80 },
        { name="HEIFER",   gender="female", minAgeM=8,   maxAgeM=15,  baseADG=1.00 },
        { name="LACT",     gender="female", minAgeM=15,  maxAgeM=120, baseADG=0.20 },
        { name="DRY",      gender="female", minAgeM=15,  maxAgeM=120, baseADG=0.10 },

        -- MALE
        { name="CALF",     gender="male",   minAgeM=0,   maxAgeM=8,   baseADG=0.80 },
        { name="YEARLING", gender="male",   minAgeM=8,   maxAgeM=18,  baseADG=0.90 },

        -- Castrated vs intact at 18 months
        { name="STEER",    gender="male",   minAgeM=18,  maxAgeM=24,  requireCastrated=true, baseADG=1.30 },
        { name="OVERAGE",  gender="male",   minAgeM=25,  maxAgeM=120, requireCastrated=true, baseADG=0.15, salePenalty="overage" },
        { name="BULL",     gender="male",   minAgeM=18,  maxAgeM=120, requireIntact=true,    baseADG=0.70 },
    }
}

-- Expose fallback so tests can read it if needed
PN_Core._fallbackStages = _fallbackStages

local function _stagesFor(speciesKey)
    local S = (PN_Settings and PN_Settings.stages and PN_Settings.stages[_u(speciesKey)])
    if S and #S > 0 then return S end
    return _fallbackStages[_u(speciesKey)] or {}
end

-- Generic stage resolver using tables (with gating flags).
local function _resolveFromTables(speciesKey, gender, ageM, isLact, rl)
    local S = _stagesFor(speciesKey)
    local g = tostring(gender or ""):lower()
    local m = tonumber(ageM) or 0
    local cas = (rl and rl.isCastrated ~= nil) and (rl.isCastrated and true or false) or nil

    for _, row in ipairs(S) do
        if type(row)=="table" and row.name and row.minAgeM and row.maxAgeM then
            local rg = (row.gender ~= nil) and tostring(row.gender):lower() or nil
            if (rg == nil or rg == g) and m >= (row.minAgeM or 0) and m < (row.maxAgeM or 1e9) then
                local ok = true
                if row.requireCastrated and not cas then ok = false end
                if row.requireIntact and cas == true then ok = false end
                if ok then
                    return row.name
                end
            end
        end
    end
    return "UNKNOWN"
end

-- Expose: resolveStage (and RL alias) if not already present
if type(PN_Core.resolveStage) ~= "function" then
function PN_Core:resolveStage(speciesKey, gender, ageM, isLact, rl)
    speciesKey = _u(speciesKey)
    if speciesKey == "COW" and type(self.resolveCowStage) == "function" then
        local entry = {
            gender      = (tostring(gender or ""):lower()=="male") and "male" or "female",
            ageMonths   = tonumber(ageM) or 0,
            isLactating = _lb(isLact),
        }
        if rl and rl.isCastrated ~= nil then
            entry.isCastrated = _lb(rl.isCastrated)
            entry.isIntact    = not _lb(rl.isCastrated)
        end
        return self:resolveCowStage(entry)
    end
    -- Generic tables path
    return _resolveFromTables(speciesKey, gender, ageM, isLact, rl)
end
end

if type(PN_Core.resolveStageRL) ~= "function" then
function PN_Core:resolveStageRL(speciesKey, gender, ageM, isLact, rl)
    return self:resolveStage(speciesKey, gender, ageM, isLact, rl)
end
end

-- Expose: adgFor (species-aware), using species-specific functions when present; otherwise baseADG*nut
if type(PN_Core.adgFor) ~= "function" then
function PN_Core:adgFor(speciesKey, stageLabel, avgW, nut, ageM)
    speciesKey = _u(speciesKey)
    if speciesKey == "COW" and type(self.adgForCow) == "function" then
        return self:adgForCow(stageLabel, avgW, nut)
    end
    local base = 0.10
    local S = _stagesFor(speciesKey)
    for _, row in ipairs(S) do
        if row.name == stageLabel and row.baseADG then base = row.baseADG; break end
    end
    local adg = (base or 0) * (tonumber(nut) or 0)
    if adg < 0 then adg = 0 end
    return adg
end
end

-- Expose: valueMultiplierFor (species-aware)
if type(PN_Core.valueMultiplierFor) ~= "function" then
function PN_Core:valueMultiplierFor(speciesKey, stageLabel, ageM)
    speciesKey = _u(speciesKey)
    if speciesKey == "COW" and type(self.valueFactorForCow) == "function" then
        return self:valueFactorForCow({ ageMonths = tonumber(ageM) or 0 }, stageLabel) or 1.0
    end
    return 1.0
end
end

-- Mark that wrappers are active
PN_Core.__pn_resolvePatch = true
