--[[
    PN_TestHarness.lua (standalone, resilient, varargs-safe)
    Self-contained stage test tools for Precision Nutrition (FS25).

    Enable for dev:
      1) Place this file at: scripts/PN_TestHarness.lua
      2) In modDesc.xml <extraSourceFiles>, ensure it is AFTER PN_Settings.lua:
           <sourceFile filename="scripts/PN_Settings.lua" />
           <sourceFile filename="scripts/PN_TestHarness.lua" />
      3) Console commands:
           pnTestInit
           pnTestSource
           pnTestCow <ageM> <gender male|female> <castrated 0|1|true|false>
           pnTestCowGrid <castrated 0|1|true|false> [minAge=0] [maxAge=36] [step=1]
]]

PN_TestHarness = PN_TestHarness or {}
local H = PN_TestHarness
H._usingFallback = false

-- --- Embedded fallback (used if PN_Settings.stages is not available) ---------
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

-- --- Utilities ---------------------------------------------------------------
local function _toBool(v)
    if v == nil then return false end
    local t = type(v)
    if t == "boolean" then return v end
    if t == "number" then return v ~= 0 end
    local s = tostring(v):lower()
    return (s == "1" or s == "true" or s == "yes" or s == "y")
end

local function _argsFromVarargs(...)
    local n = select('#', ...)
    if n > 1 then
        local t = {}
        for i=1,n do t[i] = select(i, ...) end
        return t
    end
    local only = select(1, ...)
    if type(only) == "table" then return only end
    -- string or single number -> split
    local t = {}
    for w in string.gmatch(tostring(only or ""), "%S+") do t[#t+1] = w end
    return t
end

local function _ensureStagesLoaded()
    H._usingFallback = false
    -- Use PN_Settings.stages if present
    if PN_Settings and PN_Settings.stages and PN_Settings.stages.COW and #PN_Settings.stages.COW > 0 then
        return true
    end
    -- Try to build from PN_Settings.baseConfig() if available
    if PN_Settings and type(PN_Settings.baseConfig) == "function" then
        local ok, cfg = pcall(PN_Settings.baseConfig, PN_Settings)
        if ok and type(cfg) == "table" and type(cfg.stages) == "table" then
            PN_Settings.stages = cfg.stages
        end
    end
    -- Re-check
    if PN_Settings and PN_Settings.stages and PN_Settings.stages.COW and #PN_Settings.stages.COW > 0 then
        return true
    end
    -- Fallback to embedded
    H._usingFallback = true
    return false
end

local function _cowStages()
    if PN_Settings and PN_Settings.stages and PN_Settings.stages.COW and #PN_Settings.stages.COW > 0 then
        return PN_Settings.stages.COW
    end
    return _fallbackStages.COW
end

-- Resolve stage using active stages with gating for requireCastrated/requireIntact
local function _resolveStageForCow(ageM, gender, isCastrated)
    local stages = _cowStages()
    local g = tostring(gender or ""):lower()
    local months = tonumber(ageM) or 0
    local cas = _toBool(isCastrated)

    for _, s in ipairs(stages) do
        if type(s) == "table" and s.name and s.minAgeM and s.maxAgeM then
            local sg = (s.gender ~= nil) and tostring(s.gender):lower() or nil
            if (sg == nil or sg == g)
               and months >= (s.minAgeM or 0)
               and months <  (s.maxAgeM or 1e9)
            then
                local ok = true
                if s.requireCastrated and not cas then ok = false end
                if s.requireIntact    and cas then ok = false end
                if ok then
                    return s.name
                end
            end
        end
    end
    return "UNKNOWN"
end

-- Commands --------------------------------------------------------------------

-- pnTestInit : attempt to load PN_Settings.stages (or fall back)
function H:cmdTestInit(...)
    local ok = _ensureStagesLoaded()
    local n = #_cowStages()
    local log = Logging and Logging.info or function(fmt, ...) print(string.format(fmt, ...)) end
    log("[PN:Test] Init: stages loaded = %s (rows=%d)%s",
        ok and "true" or "false",
        n,
        H._usingFallback and " [USING FALLBACK]" or "")
end

-- pnTestSource : show where stages are coming from
function H:cmdTestSource(...)
    local src = H._usingFallback and "FALLBACK (embedded)" or "PN_Settings.stages"
    local n = #_cowStages()
    local log = Logging and Logging.info or function(fmt, ...) print(string.format(fmt, ...)) end
    log("[PN:Test] Stage source: %s (rows=%d)", src, n)
end

-- pnTestCow <ageM> <gender male|female> <castrated 0|1|true|false>
function H:cmdTestCow(...)
    local a = _argsFromVarargs(...)
    _ensureStagesLoaded()
    local ageM   = tonumber(a[1] or 0) or 0
    local gender = tostring(a[2] or "male")
    local castr  = a[3] or "0"
    local stage  = _resolveStageForCow(ageM, gender, castr)

    local log = Logging and Logging.info or function(fmt, ...) print(string.format(fmt, ...)) end
    log("[PN:Test] (stages loaded: %d rows)%s", #_cowStages(), H._usingFallback and " [FALLBACK]" or "")
    log("[PN:Test] age=%.1f mo | gender=%s | castrated=%s => stage=%s",
        ageM, gender, _toBool(castr) and "true" or "false", tostring(stage))
end

-- pnTestCowGrid <castrated 0|1|true|false> [minAge=0] [maxAge=36] [step=1]
function H:cmdTestCowGrid(...)
    local a = _argsFromVarargs(...)
    _ensureStagesLoaded()

    local castr  = a[1] or "0"
    local minA   = tonumber(a[2] or 0) or 0
    local maxA   = tonumber(a[3] or 36) or 36
    local step   = tonumber(a[4] or 1) or 1

    local function row(gender)
        local out = {}
        for m = minA, maxA, step do
            out[#out+1] = _resolveStageForCow(m, gender, castr)
        end
        return table.concat(out, ",")
    end

    local ages = {}
    for m = minA, maxA, step do ages[#ages+1] = m end
    local agesStr = table.concat(ages, ",")

    local log = Logging and Logging.info or function(fmt, ...) print(string.format(fmt, ...)) end
    log("[PN:Test] (stages loaded: %d rows)%s", #_cowStages(), H._usingFallback and " [FALLBACK]" or "")
    log("[PN:Test] Grid castrated=%s | range=%g..%g step %g", _toBool(castr) and "true" or "false", minA, maxA, step)
    log("[PN:Test] Ages:   %s", agesStr)
    log("[PN:Test] Female: %s", row("female"))
    log("[PN:Test] Male:   %s", row("male"))
end

-- Console registration
if addConsoleCommand ~= nil then
    addConsoleCommand("pnTestInit",     "Initialize PN test harness (prefers PN_Settings.stages, else fallback)", "cmdTestInit", H)
    addConsoleCommand("pnTestSource",   "Show which stage source is active", "cmdTestSource", H)
    addConsoleCommand("pnTestCow",      "Test cow stage: pnTestCow <ageM> <gender male|female> <castrated 0|1|true|false>", "cmdTestCow", H)
    addConsoleCommand("pnTestCowGrid",  "Grid cow stages: pnTestCowGrid <castrated 0|1|true|false> [minAge] [maxAge] [step]", "cmdTestCowGrid", H)
end
