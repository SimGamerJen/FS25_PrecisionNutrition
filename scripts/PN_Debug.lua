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
    -- dtMs ~ 33ms to emulate a frame
	pcall(PN_Core.updateHusbandry, PN_Core, e, e.clusterSystem, 33, { forceBeat = true })
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

-- Toggle overlay from console
function PN_Debug:cmdOverlay()
    if PN_UI and PN_UI.toggle then PN_UI.toggle() end
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
