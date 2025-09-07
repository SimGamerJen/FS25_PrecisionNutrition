-- PN_Test.lua (v3, varargs-safe)
-- Precision Nutrition - Lightweight test harness for STEER/OVERAGE logic
-- Registers console commands: pnTestRL, pnTestResolve, pnTestOverageRange, pnTestStatus
-- Load AFTER PN_Core.lua and PN_CoreCompat.lua

local PN_Test = {}

local function _u(s) return tostring(s or ""):upper() end
local function _b(v, def)
    if v==nil then return def end
    if type(v)=="boolean" then return v end
    if type(v)=="number" then return v ~= 0 end
    local s = tostring(v):lower()
    return (s=="1" or s=="true" or s=="yes" or s=="y")
end
local function _n(v, def) v=tonumber(v); if v==nil then return def end return v end

local function _argsFromVarargs(...)
    local n = select('#', ...)
    if n > 1 then
        local t = {}
        for i=1,n do t[i] = select(i, ...) end
        return t
    end
    local only = select(1, ...)
    if type(only) == "table" then return only end
    local t = {}
    for w in string.gmatch(tostring(only or ""), "%S+") do t[#t+1] = w end
    return t
end

-- Print helper
local function _log(fmt, ...)
    if Logging and Logging.info then
        Logging.info(fmt, ...)
    else
        print(string.format(fmt, ...))
    end
end

-- Toggle or set the Realistic Livestock capability flag
function PN_Test:cmdTestRL(...)
    local args = _argsFromVarargs(...)
    if not PN_Core then _log("[PN][TEST] PN_Core not ready."); return end
    local prev = PN_Core.hasRealisticLivestock and true or false
    local onoff = args[1]
    if onoff == nil then
        PN_Core.hasRealisticLivestock = not prev
        _log("[PN][TEST] RL flag toggled: %s (was %s)", tostring(PN_Core.hasRealisticLivestock), tostring(prev))
        _log("[PN][TEST] Tip: you can also try 'pnTestRL on' or 'pnTestRL off'")
        return
    end
    local want = _u(onoff) == "ON" or _u(onoff) == "TRUE" or onoff == "1"
    PN_Core.hasRealisticLivestock = want
    _log("[PN][TEST] RL flag set to: %s", tostring(PN_Core.hasRealisticLivestock))
end

-- Resolve stage & show ADG / value multiplier without touching game data
-- Usage A: pnTestResolve male 26 0 1 1.0 600
-- Usage B: pnTestResolve 26 0 1 1.0 600      (assumes male)
function PN_Test:cmdTestResolve(...)
    if not PN_Core then _log("[PN][TEST] PN_Core not ready."); return end
    if not PN_Core.resolveStage and not PN_Core.resolveStageRL then
        _log("[PN][TEST] No resolver (resolveStage). Ensure PN_CoreCompat.lua is loaded.")
        return
    end

    local a = _argsFromVarargs(...)
    local gender, ageM, isLact, isCastrated, nut, avgWkg

    if a[1] and tostring(a[1]):match("^%d") then
        -- numeric-first
        gender, ageM, isLact, isCastrated, nut, avgWkg = "male", a[1], a[2], a[3], a[4], a[5]
    else
        -- gender-first
        gender, ageM, isLact, isCastrated, nut, avgWkg = a[1] or "male", a[2], a[3], a[4], a[5], a[6]
    end

    gender = (gender and tostring(gender):lower()) or "male"
    local age = _n(ageM, 20)
    local lact = _b(isLact, false)
    local cas = _b(isCastrated, false)
    local rl = { isCastrated = cas }

    local nr = _n(nut, 1.0); if nr < 0 then nr = 0 elseif nr > 1 then nr = 1 end
    local w  = _n(avgWkg, 550)

    local stage = (PN_Core.resolveStageRL or PN_Core.resolveStage)(PN_Core, "COW", gender, age, lact, rl)

    -- Compute ADG purely from tables (no weight scaling) for clarity
    local base = 0.10
    local S = (PN_Settings and PN_Settings.stages and PN_Settings.stages.COW) or (PN_Core._fallbackStages and PN_Core._fallbackStages.COW) or {}
    for _, row in ipairs(S) do if row.name == stage and row.baseADG then base = row.baseADG; break end end
    local adg = base * nr
    if stage == "OVERAGE" then adg = adg * 0.6 end

    local mult = (PN_Core.valueMultiplierFor and PN_Core:valueMultiplierFor("COW", stage, age)) or 1.0

    _log("[PN][TEST] gender=%s age=%.1fm lact=%s castrated=%s nut=%.2f avgW=%.1fkg => stage=%s, ADG=%.3f kg/d, Price×=%.3f",
         gender, age, tostring(lact), tostring(cas), nr, w, tostring(stage), adg, mult)
end

-- Sweep ages and show multiplier decay for OVERAGE
-- Usage: pnTestOverageRange [startM=24] [endM=36] [nut=1.0] [avgWkg=600]
function PN_Test:cmdTestOverageRange(...)
    local a = _argsFromVarargs(...)
    local sM = _n(a[1], 24); local eM = _n(a[2], 36)
    local nr = _n(a[3], 1.0);   local w  = _n(a[4], 600)
    if sM > eM then sM, eM = eM, sM end
    _log("[PN][TEST] OVERAGE sweep (castrated male): %dm..%dm", sM, eM)
    for m = sM, eM do
        local stage = (m >= 25) and "OVERAGE" or ((m >= 18) and "STEER" or "YEARLING")
        local base = (stage=="OVERAGE" and 0.15) or (stage=="STEER" and 1.30) or (stage=="YEARLING" and 0.90) or 0.10
        local adg  = base * nr * ((stage=="OVERAGE") and 0.6 or 1.0)
        local mult = (PN_Core.valueMultiplierFor and PN_Core:valueMultiplierFor("COW", stage, m)) or 1.0
        _log("  age=%2dm -> stage=%s, ADG=%.3f kg/d, Price×=%.3f", m, stage, adg, mult)
    end
end

function PN_Test:cmdTestStatus(...)
    local rl = PN_Core and PN_Core.hasRealisticLivestock
    local patch = PN_Core and PN_Core.__pn_resolvePatch
    local hasResolver = PN_Core and (type(PN_Core.resolveStage) == "function")
    local hasAlias    = PN_Core and (type(PN_Core.resolveStageRL) == "function")
    _log("[PN][TEST] RL flag: %s", tostring(rl))
    _log("[PN][TEST] Compat patch active: %s", tostring(patch))
    _log("[PN][TEST] resolveStage present: %s", tostring(hasResolver))
    _log("[PN][TEST] resolveStageRL present: %s", tostring(hasAlias))
end

-- Register console commands when script loads
local function _register()
    if addConsoleCommand == nil then return end
    addConsoleCommand("pnTestRL",
        "Toggle or set RL flag (usage: pnTestRL [on|off]; no arg toggles)",
        "cmdTestRL", PN_Test)
    addConsoleCommand("pnTestResolve",
        "Resolve stage & show ADG/Price (usage: pnTestResolve <gender> <ageM> [isLact=0/1] [castrated=0/1] [nut] [avgWkg] | pnTestResolve <ageM> <isLact> <castrated> [nut] [avgWkg])",
        "cmdTestResolve", PN_Test)
    addConsoleCommand("pnTestOverageRange",
        "Sweep overage ages and show ADG/Price decay (usage: pnTestOverageRange [startM] [endM] [nut] [avgWkg])",
        "cmdTestOverageRange", PN_Test)
    addConsoleCommand("pnTestStatus",
        "Show RL flag and whether compat resolver patch is active",
        "cmdTestStatus", PN_Test)
end

_register()

return PN_Test
