-- FS25_PrecisionNutrition / scripts / PN_HusbandryScan.lua
-- Minimal safe fix v6: passive scan, clusterSystem present, and species inference restored.

PN_HusbandryScan = {}

local PN_TAG   = "[PN]"
local PN_DEBUG = false

-- State
local _isReady         = false
local _entries         = {}
local _byFarmIndex     = {}
local _elapsedMs       = 0
local _rescanElapsedMs = 0
local _bootRescanned   = false

-- Tunables
local INITIAL_DELAY_MS = 2000   -- wait ~2s after mission start
local RESCAN_EVERY_MS  = 10000  -- refresh every ~10s

-- ---------- utils ----------
local function log(fmt, ...)
    if PN_DEBUG and Logging and Logging.info then
        Logging.info(PN_TAG .. " " .. string.format(fmt, ...))
    elseif PN_DEBUG then
        print(PN_TAG .. " " .. string.format(fmt, ...))
    end
end

local function safeLower(s) return (type(s)=="string" and string.lower(s)) or "" end

local function isFarmhouseLike(plc)
    if plc == nil then return false end
    local name = safeLower(plc.typeName)
    local cfg  = safeLower(plc.configFileName)
    if name:find("farmhouse", 1, true) or cfg:find("farmhouse", 1, true) then return true end
    if plc.spec_sleeping ~= nil or plc.spec_sleepTrigger ~= nil or plc.spec_farmhouse ~= nil or plc.spec_sleep ~= nil then
        return true
    end
    return false
end

local function isAnimalHusbandry(plc)
    if plc == nil then return false end
    if plc.spec_husbandryAnimals ~= nil then return true end
    if plc.spec_animalHusbandry   ~= nil then return true end
    if plc.animalSystem           ~= nil then return true end
    local t = safeLower(plc.typeName or "")
    return t:find("husbandry", 1, true) ~= nil
end

local function getOwnerFarmId(plc)
    if plc == nil then return 0 end
    if plc.getOwnerFarmId ~= nil then
        local ok, v = pcall(function() return plc:getOwnerFarmId() end)
        if ok and v then return v end
    end
    if plc.ownerFarmId ~= nil then return plc.ownerFarmId end
    return 0
end

local function getAnimalCount(plc)
    local spec = plc and (plc.spec_husbandryAnimals or plc.spec_animalHusbandry)
    if spec and spec.getNumOfAnimals ~= nil then
        local ok, n = pcall(function() return spec:getNumOfAnimals() end)
        if ok and type(n)=="number" then return n end
    end
    if plc and plc.getNumOfAnimals ~= nil then
        local ok, n = pcall(function() return plc:getNumOfAnimals() end)
        if ok and type(n)=="number" then return n end
    end
    return 0
end

local function getClustersCount(clusterSystem)
    if clusterSystem == nil then return 0 end
    if clusterSystem.getClusters ~= nil then
        local ok, list = pcall(function() return clusterSystem:getClusters() end)
        if ok and type(list) == "table" then return #list end
    end
    if clusterSystem.clusters ~= nil and type(clusterSystem.clusters)=="table" then
        return #clusterSystem.clusters
    end
    if clusterSystem.getNumClusters ~= nil then
        local ok, n = pcall(function() return clusterSystem:getNumClusters() end)
        if ok and type(n)=="number" then return n end
    end
    return 0
end

local function prettyName(plc)
    if plc == nil then return "UNKNOWN" end
    if plc.getName ~= nil then
        local n = plc:getName()
        if n and n ~= "" then return n end
    end
    if plc.configFileName ~= nil then
        local s = tostring(plc.configFileName)
        if s ~= "" then return s end
    end
    return "Placeable"
end

local function inferSpecies(plc, spec)
    -- Prefer explicit husbandry name
    local hname = safeLower(spec and spec.husbandryName or "")
    if hname:find("cow", 1, true)   then return "COW" end
    if hname:find("sheep", 1, true) then return "SHEEP" end
    if hname:find("pig", 1, true)   then return "PIG" end
    if hname:find("goat", 1, true)  then return "GOAT" end
    if hname:find("chick",1, true) or hname:find("hen",1,true) then return "CHICKEN" end

    -- Fallback: typeName/config filename hints
    local t   = safeLower(plc and plc.typeName or "")
    local cfg = safeLower(plc and plc.configFileName or "")
    if t:find("cow",1,true) or cfg:find("cow",1,true) then return "COW" end
    if t:find("sheep",1,true) or cfg:find("sheep",1,true) then return "SHEEP" end
    if t:find("pig",1,true) or cfg:find("pig",1,true) then return "PIG" end
    if t:find("goat",1,true) or cfg:find("goat",1,true) then return "GOAT" end
    if t:find("chicken",1,true) or cfg:find("chicken",1,true) or cfg:find("hen",1,true) then return "CHICKEN" end

    return "ANIMAL"
end

local function addEntry(entry)
    table.insert(_entries, entry)
    local f = entry.farmId or 0
    if _byFarmIndex[f] == nil then _byFarmIndex[f] = {} end
    table.insert(_byFarmIndex[f], entry)
end

local function classify(plc, via)
    if plc == nil or isFarmhouseLike(plc) then return end
    if not isAnimalHusbandry(plc) then return end

    local spec = plc.spec_husbandryAnimals or plc.spec_animalHusbandry
    local clusterSystem = nil
    if spec ~= nil then
        clusterSystem = spec.clusterSystem or spec.clusterHusbandry or nil
    end

    local entry = {
        placeable      = plc,
        farmId         = getOwnerFarmId(plc),
        type           = inferSpecies(plc, spec),  -- <- RESTORED species category
        clusterSystem  = clusterSystem,
        clustersCount  = getClustersCount(clusterSystem),
        name           = prettyName(plc),
        animalCount    = getAnimalCount(plc),
        typeName       = plc.typeName,
        file           = plc.configFileName
    }
    addEntry(entry)
    log("%s HIT: %s | farm=%d | species=%s | animals=%d | clusters=%d",
        tostring(via), entry.name, entry.farmId, entry.type, entry.animalCount or -1, entry.clustersCount or -1)
end

local function clearIndex()
    _entries     = {}
    _byFarmIndex = {}
end

function PN_HusbandryScan:doScan(tag)
    clearIndex()
    local ps  = g_currentMission and g_currentMission.placeableSystem or nil
    local arr = ps and ps.placeables or nil
    if arr ~= nil then
        for _, plc in ipairs(arr) do
            classify(plc, tag or "Scan")
        end
    end
    _isReady = true
    log("Scan complete: %d entries.", #_entries)
end

-- ---------- public API (unchanged) ----------
function PN_HusbandryScan.isReady()
    return _isReady
end

function PN_HusbandryScan.getAll()
    return _entries
end

function PN_HusbandryScan.getByFarmId(farmId)
    return _byFarmIndex[farmId or 0] or {}
end

function PN_HusbandryScan:onMissionStarted()
    _elapsedMs       = 0
    _rescanElapsedMs = 0
    _bootRescanned   = false
    _isReady         = false
    PN_HusbandryScan:doScan("Boot")
end

function PN_HusbandryScan:update(dt)
    if type(dt) ~= "number" then return end
    if not _bootRescanned then
        _elapsedMs = _elapsedMs + dt
        if _elapsedMs >= INITIAL_DELAY_MS then
            PN_HusbandryScan:doScan("Delayed")
            _bootRescanned = true
            _rescanElapsedMs = 0
            return
        end
    else
        _rescanElapsedMs = _rescanElapsedMs + dt
        if _rescanElapsedMs >= RESCAN_EVERY_MS then
            PN_HusbandryScan:doScan("Refresh")
            _rescanElapsedMs = 0
        end
    end
end

function PN_HusbandryScan.tick(dt)
    PN_HusbandryScan:update(dt)
end

addModEventListener(PN_HusbandryScan)
