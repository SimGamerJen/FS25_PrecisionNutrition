-- Precision Nutrition - Conflict Probe (enhanced)
-- Goals:
--  - Catch more write paths: addFillUnitFillLevel, setFillUnitFillLevel,
--    Husbandry food add/remove, and husbandry update ticks.
--  - Provide per-barn high-frequency trace (1 Hz) to see “levels stuck”.
--  - Safe on builds without debug.getinfo().

PN_ConflictProbe = PN_ConflictProbe or {}
PN_ConflictProbe.__index = PN_ConflictProbe

local Logging = Logging or { info=print, warning=print, error=print }

-- ===== Config =====
local RING_MAX      = 600     -- event buffer size
local REPORT_SEC    = 1800    -- default probe report window
local TRACE_HZ      = 1       -- samples per second for pnProbeTrace
local TRACE_MAX_S   = 900     -- safety cap for traces (seconds)
local STALL_HRS     = 2       -- “no consumption” window for pnProbeBarns

-- ===== State =====
PN_ConflictProbe.enabled     = PN_ConflictProbe.enabled or false
PN_ConflictProbe.events      = PN_ConflictProbe.events  or {}
PN_ConflictProbe.head        = PN_ConflictProbe.head    or 0
PN_ConflictProbe._installed  = PN_ConflictProbe._installed or false
PN_ConflictProbe._hourMarks  = PN_ConflictProbe._hourMarks or {}
PN_ConflictProbe._lastHour   = PN_ConflictProbe._lastHour or nil
PN_ConflictProbe._hooks      = PN_ConflictProbe._hooks or {}

-- Per-barn traces: { [index] = { active=true, tEndMs=..., nextTickMs=..., samples={ {t,L}, ... } } }
PN_ConflictProbe._traces     = PN_ConflictProbe._traces or {}

-- ===== Safe clock helpers =====
local function nowMs() return (g_time or 0) end
local function nowHour()
    local m = g_currentMission
    local env = m and m.environment
    if not env or not env.dayTime then return nil end
    return math.floor(env.dayTime / (60*60*1000))
end

-- ===== Debug-safe source capture =====
local HAS_DEBUG = (type(debug) == "table") and (type(debug.getinfo) == "function")
local function srcFromStack(depth)
    if not HAS_DEBUG then return "<no-debuglib>" end
    local start = (tonumber(depth) or 3)
    for d = start, start + 6 do
        local ok, info = pcall(debug.getinfo, d, "S")
        if ok and info and info.source then
            local s = tostring(info.source)
            if s ~= "=[C]" and not s:match("%[C%]") then
                return s
            end
        end
    end
    return "<unknown>"
end

-- ===== FillType helper =====
local function ftName(idx)
    local fm = g_fillTypeManager
    if fm and fm.getFillTypeNameByIndex then
        return fm:getFillTypeNameByIndex(idx) or tostring(idx)
    end
    return tostring(idx)
end

-- ===== PN list & liters =====
local function husbandryList()
    if PN_HusbandryScan and PN_HusbandryScan.getAll then
        return PN_HusbandryScan.getAll()
    end
    return {}
end

local function totalTroughLiters(p)
    local tot = 0
    if p and p.spec_fillUnit and p.spec_fillUnit.fillUnits then
        for _, fu in ipairs(p.spec_fillUnit.fillUnits) do
            if type(fu.fillLevels) == "table" then
                for _, L in pairs(fu.fillLevels) do tot = tot + (tonumber(L or 0) or 0) end
            else
                tot = tot + (tonumber(fu.fillLevel or 0) or 0)
            end
        end
    end
    if tot == 0 and p and p.spec_husbandryFood and p.spec_husbandryFood.fillLevels then
        for _, L in pairs(p.spec_husbandryFood.fillLevels) do
            tot = tot + (tonumber(L or 0) or 0)
        end
    end
    return tot
end

-- ===== Event ring =====
local function recordEvent(kind, placeable, deltaL, ftIndex, note)
    if not PN_ConflictProbe.enabled then return end
    PN_ConflictProbe.head = (PN_ConflictProbe.head % RING_MAX) + 1
    PN_ConflictProbe.events[PN_ConflictProbe.head] = {
        t     = nowMs(),
        kind  = kind,    -- "ADD_FILL", "SET_FILL", "DISCHARGE", "FOOD_ADD", "FOOD_REM", "FEED_TICK"
        place = placeable,
        delta = deltaL or 0,
        ft    = ftIndex,
        src   = srcFromStack(4),
        note  = note
    }
end

-- ===== Hourly checkpoints (for pnProbeBarns) =====
local function hourlyTick()
    local h = nowHour()
    if h == nil then return end
    if PN_ConflictProbe._lastHour == nil then PN_ConflictProbe._lastHour = h end
    if h == PN_ConflictProbe._lastHour then return end
    PN_ConflictProbe._lastHour = h

    for i, e in ipairs(husbandryList()) do
        local p = e.placeable or e
        if p then
            local L = totalTroughLiters(p)
            local rec = PN_ConflictProbe._hourMarks[i] or { hours = {}, head = 0 }
            rec.head = (rec.head % (STALL_HRS+1)) + 1
            rec.hours[rec.head] = L
            PN_ConflictProbe._hourMarks[i] = rec
        end
    end
end

-- ===== Per-barn 1 Hz trace =====
local function tickTraces()
    local tNow = nowMs()
    local list = husbandryList()
    for idx, tr in pairs(PN_ConflictProbe._traces) do
        if tr.active then
            if tNow >= tr.tEndMs then
                tr.active = false
                Logging.info("[PN] ProbeTrace #%d: finished (%ds, %d samples).", idx, math.floor((tr.tEndMs - tr.tStartMs)/1000), #(tr.samples or {}))
            elseif tNow >= tr.nextTickMs then
                tr.nextTickMs = tNow + math.floor(1000 / TRACE_HZ)
                local e = list[idx]
                if e then
                    local L = totalTroughLiters(e.placeable or e)
                    table.insert(tr.samples, { t=tNow, L=L })
                end
            end
        end
    end
end

local function traceReport(idx)
    local tr = PN_ConflictProbe._traces[idx]
    if not tr or not tr.samples or #tr.samples == 0 then
        Logging.info("[PN] ProbeTrace #%d: no samples.", idx); return
    end
    Logging.info("[PN] ---- ProbeTrace for #%d (%d samples) ----", idx, #tr.samples)
    local baseT = tr.samples[1].t
    local lastL = tr.samples[1].L
    Logging.info("[PN]   %6.1fs  L=%.1f", 0.0, lastL)
    for i=2,#tr.samples do
        local dtS = (tr.samples[i].t - baseT)/1000.0
        local L   = tr.samples[i].L
        local dL  = L - lastL
        if math.abs(dL) > 0.05 then
            Logging.info("[PN]   %6.1fs  L=%.1f  Δ=%.1f", dtS, L, dL)
        end
        lastL = L
    end
    Logging.info("[PN] -----------------------------------")
end

-- ===== Wrappers (defensive) =====
local function hookOnce(tag, ok)
    PN_ConflictProbe._hooks[tag] = ok and "yes" or "no"
end

local function installWrappers()
    if PN_ConflictProbe._installed then return end

    -- 1) Dischargeable.setDischargeState (start/stop unloading)
    do
        local ok = false
        if Dischargeable and Dischargeable.setDischargeState then
            local raw = Dischargeable.setDischargeState
            Dischargeable.setDischargeState = function(self, state, ...)
                local before = self.getDischargeState and self:getDischargeState() or 0
                local ret = raw(self, state, ...)
                local after  = self.getDischargeState and self:getDischargeState() or 0
                if PN_ConflictProbe.enabled and before ~= after then
                    local active = (after ~= (Dischargeable.DISCHARGE_STATE_OFF or 0))
                    recordEvent("DISCHARGE", self, 0, nil, active and "start" or "stop")
                end
                return ret
            end
            ok = true
        end
        hookOnce("Dischargeable.setDischargeState", ok)
    end

    -- 2) FillUnit.addFillUnitFillLevel (common)
    do
        local ok = false
        if FillUnit and FillUnit.addFillUnitFillLevel then
            local raw = FillUnit.addFillUnitFillLevel
            FillUnit.addFillUnitFillLevel = function(self, farmId, unitIndex, delta, fillTypeIndex, toolType, ...)
                if PN_ConflictProbe.enabled and delta and delta ~= 0 then
                    local place = (self and self.owningPlaceable) or (self and self.parent) or self
                    recordEvent("ADD_FILL", place, delta, fillTypeIndex, "addFillUnitFillLevel")
                end
                return raw(self, farmId, unitIndex, delta, fillTypeIndex, toolType, ...)
            end
            ok = true
        end
        hookOnce("FillUnit.addFillUnitFillLevel", ok)
    end

    -- 3) FillUnit.setFillUnitFillLevel (many mods use this)
    do
        local ok = false
        if FillUnit and FillUnit.setFillUnitFillLevel then
            local raw = FillUnit.setFillUnitFillLevel
            FillUnit.setFillUnitFillLevel = function(self, unitIndex, level, fillTypeIndex, force, ...)
                if PN_ConflictProbe.enabled then
                    local place = (self and self.owningPlaceable) or (self and self.parent) or self
                    recordEvent("SET_FILL", place, tonumber(level or 0) or 0, fillTypeIndex, "setFillUnitFillLevel")
                end
                return raw(self, unitIndex, level, fillTypeIndex, force, ...)
            end
            ok = true
        end
        hookOnce("FillUnit.setFillUnitFillLevel", ok)
    end

    -- 4) Husbandry food add/remove (names differ across builds; try a few)
    local foodTargets = {
        { name="HusbandryModuleFood", add="addFillType", remove="removeFillType" },
        { name="HusbandryFood",       add="addFood",     remove="removeFood"     },
    }
    for _, t in ipairs(foodTargets) do
        local T = rawget(_G, t.name)
        if T then
            if T[t.add] then
                local raw = T[t.add]
                T[t.add] = function(self, fillTypeIndex, liters, ...)
                    if PN_ConflictProbe.enabled then
                        local place = (self and self.placeable) or (self and self.parent) or self
                        recordEvent("FOOD_ADD", place, tonumber(liters or 0) or 0, fillTypeIndex, t.name.."."..t.add)
                    end
                    return raw(self, fillTypeIndex, liters, ...)
                end
                hookOnce(t.name.."."..t.add, true)
            else
                hookOnce(t.name.."."..t.add, false)
            end
            if T[t.remove] then
                local raw = T[t.remove]
                T[t.remove] = function(self, fillTypeIndex, liters, ...)
                    if PN_ConflictProbe.enabled then
                        local place = (self and self.placeable) or (self and self.parent) or self
                        recordEvent("FOOD_REM", place, tonumber(liters or 0) or 0, fillTypeIndex, t.name.."."..t.remove)
                    end
                    return raw(self, fillTypeIndex, liters, ...)
                end
                hookOnce(t.name.."."..t.remove, true)
            else
                hookOnce(t.name.."."..t.remove, false)
            end
        else
            hookOnce(t.name, false)
        end
    end

    -- 5) Husbandry update tick (to see if feeding ever runs)
    local tickTargets = {
        { name="AnimalHusbandry", fn="updateFeeding" },
        { name="AnimalHusbandry", fn="update"        },
        { name="HusbandryModuleFood", fn="update"    },
        { name="HusbandryFood",    fn="update"       },
    }
    for _, t in ipairs(tickTargets) do
        local T = rawget(_G, t.name)
        if T and T[t.fn] and not T["_pn_probe_wrapped_"..t.fn] then
            local raw = T[t.fn]
            T[t.fn] = function(self, ...)
                if PN_ConflictProbe.enabled then
                    local place = (self and self.placeable) or (self and self.parent) or self
                    recordEvent("FEED_TICK", place, 0, nil, t.name.."."..t.fn)
                end
                return raw(self, ...)
            end
            T["_pn_probe_wrapped_"..t.fn] = true
            hookOnce(t.name.."."..t.fn, true)
        elseif T then
            hookOnce(t.name.."."..t.fn, T[t.fn] ~= nil)
        else
            hookOnce(t.name, false)
        end
    end

    -- Mission update for hourly checkpoints & traces
    if Utils and Mission00 then
        Mission00.update = Utils.appendedFunction(Mission00.update, function(_, dt)
            if PN_ConflictProbe.enabled then
                hourlyTick()
                tickTraces()
            end
        end)
        hookOnce("Mission00.update", true)
    else
        hookOnce("Mission00.update", false)
    end

    PN_ConflictProbe._installed = true
    Logging.info("[PN] ConflictProbe: wrappers installed.")
end

-- ===== Public controls =====
function PN_ConflictProbe:enable()
    self.enabled = true
    installWrappers()
    Logging.info(string.format("[PN] ConflictProbe: enabled. debug.getinfo=%s",
        HAS_DEBUG and "yes" or "no"))
end

function PN_ConflictProbe:disable()
    self.enabled = false
    Logging.info("[PN] ConflictProbe: disabled.")
end

function PN_ConflictProbe:report(idx, seconds)
    local list = husbandryList()
    local e = list[tonumber(idx or 0)]
    if not e then Logging.info("[PN] Probe: no entry at index %s", tostring(idx)); return end
    local p = e.placeable or e
    local cutoff = nowMs() - 1000 * (tonumber(seconds or REPORT_SEC) or REPORT_SEC)

    Logging.info("[PN] ---- Probe report for #%d '%s' (last %ds) ----",
        idx, tostring(e.name or "?"), (tonumber(seconds or REPORT_SEC) or REPORT_SEC))
    local count = 0
    for n = 0, RING_MAX-1 do
        local i = ((PN_ConflictProbe.head - n - 1) % RING_MAX) + 1
        local ev = PN_ConflictProbe.events[i]
        if not ev then break end
        if ev.t < cutoff then break end
        local same =
            (ev.place == p) or
            (ev.place and p and ev.place.rootNode and ev.place.rootNode == p.rootNode)
        if same then
            count = count + 1
            local sign = (ev.delta or 0)
            local ft = ev.ft and ftName(ev.ft) or "-"
            Logging.info("[PN] %6.1fs %-10s ΔL=%8.1f  ft=%-12s  src=%s  note=%s",
                (nowMs()-ev.t)/1000.0, ev.kind or "-", sign, ft, tostring(ev.src), tostring(ev.note or "-"))
        end
    end
    if count == 0 then
        Logging.info("[PN] (no events recorded for this barn in window)")
    end
    Logging.info("[PN] ----------------------------------------------")
end

function PN_ConflictProbe:listStalled(windowHours)
    local wh = tonumber(windowHours or STALL_HRS) or STALL_HRS
    Logging.info("[PN] ---- Probe: barns with no consumption over %d in-game hour(s) ----", wh)
    local list = husbandryList()
    local flagged = 0
    for i, e in ipairs(list) do
        local rec = PN_ConflictProbe._hourMarks[i]
        if rec and rec.hours then
            local vals = {}
            for k=1, wh do
                local slot = ((rec.head - (k-1) - 1) % (STALL_HRS+1)) + 1
                local v = rec.hours[slot]
                if v ~= nil then table.insert(vals, 1, v) end
            end
            if #vals >= 2 then
                local first, last = vals[1], vals[#vals]
                if last >= first - 0.01 then
                    flagged = flagged + 1
                    Logging.info("[PN]  #%d '%s' farm=%s  totalL: %.1f → %.1f  (no drop)",
                        i, tostring(e.name or "?"), tostring(e.farmId or "?"), first, last)
                end
            end
        end
    end
    if flagged == 0 then Logging.info("[PN] (none)") end
end

-- Start or stop a 1 Hz trace for one barn
function PN_ConflictProbe:trace(idx, seconds)
    local list = husbandryList()
    local i = tonumber(idx or 0)
    if not list[i] then Logging.info("[PN] ProbeTrace: no entry at %s", tostring(idx)); return end
    local s = tonumber(seconds or 300) or 300
    if s < 5 then s = 5 elseif s > TRACE_MAX_S then s = TRACE_MAX_S end
    local tNow = nowMs()
    PN_ConflictProbe._traces[i] = {
        active    = true,
        tStartMs  = tNow,
        tEndMs    = tNow + s*1000,
        nextTickMs= tNow,
        samples   = {}
    }
    Logging.info("[PN] ProbeTrace #%d: started for %ds (%.0f Hz).", i, s, TRACE_HZ)
end

function PN_ConflictProbe:traceStop(idx)
    local i = tonumber(idx or 0)
    local tr = PN_ConflictProbe._traces[i]
    if tr and tr.active then
        tr.active = false
        Logging.info("[PN] ProbeTrace #%d: stopped.", i)
        traceReport(i)
    else
        Logging.info("[PN] ProbeTrace #%d: not active.", i)
    end
end

function PN_ConflictProbe:traceReport(idx)
    traceReport(tonumber(idx or 0))
end

function PN_ConflictProbe:hookList()
    Logging.info("[PN] ---- Probe hooks ----")
    for k,v in pairs(PN_ConflictProbe._hooks) do
        Logging.info("[PN]  %-36s : %s", k, tostring(v))
    end
end

-- ===== Console bindings =====
if addConsoleCommand then
    addConsoleCommand("pnProbeOn",       "Enable PN conflict probe logging",                                  "enable",       PN_ConflictProbe)
    addConsoleCommand("pnProbeOff",      "Disable PN conflict probe logging",                                 "disable",      PN_ConflictProbe)
    addConsoleCommand("pnProbeReport",   "Report recent events for a barn: pnProbeReport <index> [seconds]",  "report",       PN_ConflictProbe)
    addConsoleCommand("pnProbeBarns",    "List barns with no consumption over last N hours",                  "listStalled",  PN_ConflictProbe)
    addConsoleCommand("pnProbeTrace",    "Start 1 Hz level trace: pnProbeTrace <index> [seconds]",            "trace",        PN_ConflictProbe)
    addConsoleCommand("pnProbeTraceStop","Stop trace and print summary: pnProbeTraceStop <index>",            "traceStop",    PN_ConflictProbe)
    addConsoleCommand("pnProbeTraceRpt", "Print trace summary: pnProbeTraceRpt <index>",                      "traceReport",  PN_ConflictProbe)
    addConsoleCommand("pnProbeHooks",    "Print which hooks were installed",                                  "hookList",     PN_ConflictProbe)
end

-- Install immediately (safe to call multiple times)
local ok, err = pcall(installWrappers)
if not ok then Logging.info("[PN] ConflictProbe: install error: %s", tostring(err)) end

return PN_ConflictProbe
