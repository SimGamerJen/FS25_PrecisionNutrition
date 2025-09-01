-- FS25_PrecisionNutrition / scripts / PN_Debug.lua
-- Console helpers for on-demand inspection (FS25-style addConsoleCommand).

PN_Debug = PN_Debug or {}

-- ---------- small utils ----------
local function _safe(n)
    if n == nil then return "?" end
    n = tostring(n)
    if n == "" then return "?" end
    return n
end

-- ---------- dump list ----------
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

-- ---------- dump CSV ----------
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

-- ---------- inspect one entry ----------
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

-- ---------- inspect clusters for one entry ----------
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

-- ---------- force a heartbeat once ----------
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

    -- Light refresh so PN snapshots are current
    pcall(PN_Core.updateHusbandry, PN_Core, e, e.clusterSystem, 33, { forceBeat = true })

    -- Species inference (local, no PN_Core dependency)
    local function inferSpecies(entry)
        local function norm(s)
            s = tostring(s or ""):upper()
            if s == "CATTLE" then return "COW" end
            if s == "HEN" then return "CHICKEN" end
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

    -- Split counts from live clusters
    local counts = { femaleOpen=0, femalePreg=0, male=0 }
    local wsum   = { femaleOpen=0, femalePreg=0, male=0 }

    local okC, clusters = pcall(e.clusterSystem.getClusters, e.clusterSystem)
    if okC and type(clusters) == "table" then
        for _, c in pairs(clusters) do
            if type(c) == "table" and not c.isDead then
                local gsex = tostring(c.gender or ""):lower()
                local w    = tonumber(c.weight or 0) or 0
                if gsex == "female" then
                    if c.isPregnant then
                        counts.femalePreg = counts.femalePreg + 1
                        wsum.femalePreg   = wsum.femalePreg + w
                    else
                        counts.femaleOpen = counts.femaleOpen + 1
                        wsum.femaleOpen   = wsum.femaleOpen + w
                    end
                elseif gsex == "male" then
                    counts.male = counts.male + 1
                    wsum.male   = wsum.male + w
                end
            end
        end
    end

    local avgW = {
        femaleOpen = (counts.femaleOpen>0) and (wsum.femaleOpen / counts.femaleOpen) or 0,
        femalePreg = (counts.femalePreg>0) and (wsum.femalePreg / counts.femalePreg) or 0,
        male       = (counts.male>0)       and (wsum.male       / counts.male)       or 0,
    }

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

    -- Stage mapping for ADG model (uses PN_Core.stageLabel if available)
    local function stageFor(key)
        local sex  = (key == "male") and "male" or "female"
        local isPr = (key == "femalePreg")
        if PN_Core and PN_Core.stageLabel then
            local okS, lbl = pcall(PN_Core.stageLabel, PN_Core, species, sex, isPr)
            if okS and type(lbl) == "string" and lbl ~= "" then return lbl end
        end
        if species == "COW" then
            if sex == "male" then return "BULL" end
            return isPr and "GEST" or "LACT"
        end
        if sex == "male" then return "MALE" end
        return isPr and "PREG" or "FEMALE"
    end

    local function adgFor(stage, w)
        if PN_Core and PN_Core.adgFor then
            local okG, g = pcall(PN_Core.adgFor, PN_Core, species, stage, w or 0, barnNut)
            if okG and type(g) == "number" then return g end
        end
        return 0.10 * barnNut -- baseline fallback
    end

    local rows = {
        { key="female-open", n=counts.femaleOpen, avgW=avgW.femaleOpen, stage=stageFor("femaleOpen"), preg=0 },
        { key="female-preg", n=counts.femalePreg, avgW=avgW.femalePreg, stage=stageFor("femalePreg"), preg=counts.femalePreg },
        { key="male",        n=counts.male,       avgW=avgW.male,       stage=stageFor("male"),       preg=0 },
    }

    for _, r in ipairs(rows) do
        if (r.n or 0) > 0 then
            local g = adgFor(r.stage, r.avgW)
            if r.key ~= "male" then
                Logging.info("[PN] %s [%s/%s] | stage=%s | head=%d preg=%d | avgW=%.2fkg | Nut=%d%% | ADG=%.3f kg/d",
                    name, species, r.key, r.stage, r.n, (r.preg or 0), r.avgW, math.floor(barnNut*100 + 0.5), g)
            else
                Logging.info("[PN] %s [%s/%s] | stage=%s | head=%d | avgW=%.2fkg | Nut=%d%% | ADG=%.3f kg/d",
                    name, species, r.key, r.stage, r.n, r.avgW, math.floor(barnNut*100 + 0.5), g)
            end
        end
    end
end

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

if addConsoleCommand ~= nil then
    addConsoleCommand("pnOverlayMine", "Filter overlay to my farm only (on/off|all)", "cmdOverlayMine", PN_Debug)
end

-- Set/view barn nutrition ratio (0..1): pnNut <index> <ratio>
function PN_Debug:cmdNut(idxStr, ratioStr)
    if PN_HusbandryScan == nil or PN_HusbandryScan.getAll == nil then
        Logging.info("[PN] pnNut: scanner not available")
        return
    end
    local idx = tonumber(idxStr or "")
    if idx == nil then
        Logging.info("[PN] Usage: pnNut <index> <ratio 0..1>  (see pnDumpHusbandries)")
        return
    end
    local list = PN_HusbandryScan.getAll()
    local e = list[idx]
    if not e then
        Logging.info("[PN] pnNut: no entry at index %s", tostring(idx))
        return
    end
    if ratioStr == nil or ratioStr == "" then
        -- just show current
        local r = (PN_Core and PN_Core._nutBarns and PN_Core._nutBarns[e]) or 1.0
        Logging.info("[PN] Barn '%s' nutrition ratio = %.0f%%", tostring(e.name), (r or 1)*100)
        return
    end
    local r = tonumber(ratioStr)
    if not r then
        Logging.info("[PN] pnNut: ratio must be a number from 0..1")
        return
    end
    if PN_Core and PN_Core.setBarnNutrition then
        PN_Core.setBarnNutrition(e, r)
        Logging.info("[PN] Barn '%s' nutrition ratio set to %.0f%%", tostring(e.name), math.max(0, math.min(1, r))*100)
    else
        Logging.info("[PN] pnNut: PN_Core not ready")
    end
end

if addConsoleCommand ~= nil then
    addConsoleCommand("pnNut", "Set/view PN nutrition ratio for one entry (0..1)", "cmdNut", PN_Debug)
end

-- Simulate nutrition over a time window: pnSim <index> <hours|e.g. 6>  (or add 'd' suffix for days, e.g. 0.5d)
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

if addConsoleCommand ~= nil then
    addConsoleCommand("pnSim", "Simulate PN over time: pnSim <index> <hours|e.g. 6 or 0.5d>", "cmdSim", PN_Debug)
end

function PN_Debug:cmdNutOverride(idxStr, ratioStr)
  local list = PN_HusbandryScan.getAll(); local e = list[tonumber(idxStr or "") or -1]
  if not (e and PN_Core) then Logging.info("[PN] pnNutOverride: entry/core missing"); return end
  if PN_Core._nutOverride == nil then PN_Core._nutOverride = {} end
  if ratioStr == nil or ratioStr == "" then
    PN_Core._nutOverride[e] = nil
    Logging.info("[PN] Cleared manual Nut%% override for '%s'", tostring(e.name)); return
  end
  local r = math.max(0, math.min(1, tonumber(ratioStr) or 1))
  PN_Core._nutOverride[e] = r
  Logging.info("[PN] Manual Nut%% override for '%s' = %d%%", tostring(e.name), math.floor(r*100+0.5))
end

if addConsoleCommand ~= nil then
  addConsoleCommand("pnNutOverride", "Set/clear manual Nut%% override: pnNutOverride <index> <0..1 | (empty to clear)>", "cmdNutOverride", PN_Debug)
end

-- Toggle overlay from console
function PN_Debug:cmdOverlay()
    if PN_UI and PN_UI.toggle then PN_UI.toggle() end
end

function PN_Debug:cmdPNReload()
    if not PN_Settings or not PN_Settings.load or not PN_Core or not PN_Core.init then
        Logging.info("[PN] pnPNReload: PN not ready"); return
    end
    local cfg = PN_Settings.load()
    PN_Core.init(cfg)
    Logging.info("[PN] Reloaded PN settings (including external XML packs).")
end

if addConsoleCommand ~= nil then
    addConsoleCommand("pnPNReload", "Reload PN settings from modSettings/PrecisionNutrition/*.xml", "cmdPNReload", PN_Debug)
end

-- ---- fillType name helper
local function _ftName(idx)
    if g_fillTypeManager and g_fillTypeManager.getFillTypeNameByIndex then
        return g_fillTypeManager:getFillTypeNameByIndex(idx) or tostring(idx)
    end
    return tostring(idx)
end

-- ---- inspect trough/fillUnits for one barn index
function PN_Debug:cmdInspectTrough(idxStr)
    local idx = tonumber(idxStr or "")
    if not idx then
        Logging.info("[PN] Usage: pnInspectTrough <index> (see pnDumpHusbandries)")
        return
    end
    local list = (PN_HusbandryScan and PN_HusbandryScan.getAll and PN_HusbandryScan.getAll()) or {}
    local e = list[idx]
    if not e or not e.placeable or not e.placeable.spec_fillUnit then
        Logging.info("[PN] pnInspectTrough: no placeable/fillUnit at index %s", tostring(idx))
        return
    end

    local fus = e.placeable.spec_fillUnit.fillUnits or {}
    Logging.info("[PN] Trough of '%s' has %d fillUnits", tostring(e.name), #fus)

    for u, fu in ipairs(fus) do
        local lvl  = fu.fillLevel
        local lft  = fu.lastFillType or fu.fillType
        Logging.info("[PN]  unit %d: level=%.3f, fillType=%s", u, tonumber(lvl or 0) or 0, _ftName(lft))

        -- supported fill types (if provided)
        if fu.supportedFillTypes then
            local names = {}
            for ftIndex, allowed in pairs(fu.supportedFillTypes) do
                if allowed then table.insert(names, _ftName(ftIndex)) end
            end
            table.sort(names)
            Logging.info("[PN]   supported: %s", table.concat(names, ", "))
        end

        -- per-FT levels (precise mode)
        if fu.fillLevels then
            local n = 0
            for ftIndex, v in pairs(fu.fillLevels) do
                if n < 16 then
                    Logging.info("[PN]   level[%s]=%.3f", _ftName(ftIndex), tonumber(v or 0) or 0)
                end
                n = n + 1
            end
            if n > 16 then Logging.info("[PN]   ... (%d total entries)", n) end
        end
    end
end

if addConsoleCommand ~= nil then
    addConsoleCommand("pnInspectTrough", "Inspect trough fillUnits/levels for one PN entry", "cmdInspectTrough", PN_Debug)
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

if addConsoleCommand ~= nil then
    addConsoleCommand("pnIntakeDebug", "Toggle PN intake debug (on/off)", "cmdIntakeDebug", PN_Debug)
end

-- ---- fillType name helper
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

-- Search for a nearby placeable (same farm) that HAS a fillUnit (the feeder)
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

addConsoleCommand("pnFindFeeder", "Find a nearby feeder (fillUnit) for the PN entry", "cmdFindFeeder", PN_Debug)

local function _ftName(idx)
  if g_fillTypeManager and g_fillTypeManager.getFillTypeNameByIndex then
    return g_fillTypeManager:getFillTypeNameByIndex(idx) or tostring(idx)
  end
  return tostring(idx)
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

if addConsoleCommand ~= nil then
  addConsoleCommand("pnInspectFoodSpec","Inspect spec_husbandryFood.fillLevels for a PN entry","cmdInspectFoodSpec",PN_Debug)
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

if addConsoleCommand ~= nil then
   addConsoleCommand("pnCredit", "Credit intake for a barn (kg)", "cmdCredit", PN_Debug)
end

function PN_Debug:cmdAutoConsume(state)
    local s = tostring(state or ""):lower()
    if s == "on" or s == "true" or s == "1" then
        PN_Core.autoConsume = true
    elseif s == "off" or s == "false" or s == "0" then
        PN_Core.autoConsume = false
    else
        PN_Core.autoConsume = not PN_Core.autoConsume
    end
    Logging.info("[PN] Auto-consume is now %s", PN_Core.autoConsume and "ON" or "OFF")
end

if addConsoleCommand ~= nil then
    addConsoleCommand("pnAutoConsume", "Toggle PN auto consumption (on/off)", "cmdAutoConsume", PN_Debug)
end

-- ---------- register everything (guarded) ----------
if addConsoleCommand ~= nil then
    -- NOTE: arg3 = *method name string*, arg4 = target table
    addConsoleCommand("pnDumpHusbandries",
        "Print PN-detected husbandries/trailers to the log",
        "cmdDumpHusbandries", PN_Debug)

    addConsoleCommand("pnDumpHusbandriesCSV",
        "Write PN-detected husbandries/trailers to PN_Husbandries.csv",
        "cmdDumpHusbandriesCSV", PN_Debug)

    addConsoleCommand("pnInspect",
        "Inspect one PN entry by index",
        "cmdInspectHusbandry", PN_Debug)

    addConsoleCommand("pnInspectClusters",
        "Inspect cluster objects for one PN entry",
        "cmdInspectClusters", PN_Debug)

    addConsoleCommand("pnBeat",
        "Force a PN heartbeat for one entry by index",
        "cmdBeat", PN_Debug)
		
    addConsoleCommand("pnOverlay",
		"Toggle PN overlay on/off",
		"cmdOverlay", PN_Debug)
		
    addConsoleCommand("pnHeartbeat",
        "Set PN heartbeat period in ms, or 'off' to disable",
        "cmdHeartbeat", PN_Debug)

    Logging.info("[PN] Console commands: pnDumpHusbandries, pnDumpHusbandriesCSV, pnInspect, pnInspectClusters, pnBeat, pnOverlay, pnHeartbeat")
else
    Logging.info("[PN] Console: addConsoleCommand not available at load")
end
