-- FS25_PrecisionNutrition / scripts / PN_HusbandryScan.lua
-- Live discovery of animal-capable placeables via PlaceableSystem hooks.

PN_HusbandryScan = {}

local PN_TAG   = "[PN]"
local PN_DEBUG = true

local _isReady     = false
local _entries     = {}
local _byFarmIndex = {}

-- ---------- utils ----------
local function log(fmt, ...)
    if PN_DEBUG then
        Logging.info(PN_TAG .. " " .. fmt, ...)
    end
end

local function safeFarmId(placeable)
    if placeable ~= nil then
        if placeable.getOwnerFarmId ~= nil then
            return placeable:getOwnerFarmId() or 0
        end
        if placeable.owningFarmId ~= nil then
            return placeable.owningFarmId or 0
        end
    end
    return 0
end

local function prettyName(placeable)
    if placeable == nil then return "UNKNOWN" end
    if placeable.getName ~= nil then
        local n = placeable:getName()
        if n ~= nil and n ~= "" then return n end
    end
    if placeable.configFileName ~= nil then
        local s = tostring(placeable.configFileName)
        if s ~= "" then return s end
    end
    return "Placeable"
end

local function isAnimalHusbandry(placeable)
    return placeable ~= nil and placeable.spec_husbandryAnimals ~= nil
end

local function isLivestockTrailer(placeable)
    return placeable ~= nil and placeable.spec_livestockTrailer ~= nil
end

local function inferTypeFromSpec(placeable)
    if isAnimalHusbandry(placeable) then
        local spec = placeable.spec_husbandryAnimals
        local hname = (spec and spec.husbandryName) or ""
        local N = string.upper(hname)
        if string.find(N, "COW")    then return "COW" end
        if string.find(N, "SHEEP")  then return "SHEEP" end
        if string.find(N, "PIG")    then return "PIG" end
        if string.find(N, "GOAT")   then return "GOAT" end
        if string.find(N, "CHICK") or string.find(N, "HEN") then return "CHICKEN" end
        return "ANIMAL"
    elseif isLivestockTrailer(placeable) then
        return "TRAILER"
    end
    return "OTHER"
end

local function addEntry(entry)
    table.insert(_entries, entry)
    local f = entry.farmId or 0
    if _byFarmIndex[f] == nil then _byFarmIndex[f] = {} end
    table.insert(_byFarmIndex[f], entry)
end

-- ---------- classify one placeable ----------
local function _classify(placeable, via)
    if placeable == nil then return end
    local hasHus = isAnimalHusbandry(placeable)
    local hasTrl = isLivestockTrailer(placeable)
    if not hasHus and not hasTrl then return end

    local clusterSystem = nil
    if hasHus and placeable.spec_husbandryAnimals ~= nil then
        clusterSystem = placeable.spec_husbandryAnimals.clusterSystem
    elseif hasTrl and placeable.spec_livestockTrailer ~= nil then
        clusterSystem = placeable.spec_livestockTrailer.clusterHusbandry
    end

    local entry = {
        placeable     = placeable,
        farmId        = safeFarmId(placeable),
        type          = inferTypeFromSpec(placeable),
        clusterSystem = clusterSystem,
        name          = prettyName(placeable),
    }
    addEntry(entry)
    log("%s HIT: %s | farm=%d | type=%s | cluster=%s",
        tostring(via), entry.name, entry.farmId, entry.type, tostring(entry.clusterSystem ~= nil))
end

-- ---------- GLOBAL (class) hooks: install ASAP at file load ----------
local function hookPlaceableSystemGlobals()
    if PlaceableSystem == nil then return end
    if PlaceableSystem.__pn_globalHooked then return end

    -- after original: get the actual instance that was added
    if PlaceableSystem.addPlaceable ~= nil then
        PlaceableSystem.addPlaceable = Utils.appendedFunction(PlaceableSystem.addPlaceable, function(self, placeable, ...)
            _classify(placeable, "AddPlaceable")
        end)
    end

    -- load functions: actual classification occurs when addPlaceable runs
    if PlaceableSystem.loadPlaceable ~= nil then
        PlaceableSystem.loadPlaceable = Utils.appendedFunction(PlaceableSystem.loadPlaceable, function(self, xmlFile, ...)
            -- no-op
        end)
    end
    if PlaceableSystem.loadPlaceableFromXML ~= nil then
        PlaceableSystem.loadPlaceableFromXML = Utils.appendedFunction(PlaceableSystem.loadPlaceableFromXML, function(self, xmlFilename, ...)
            -- no-op
        end)
    end

    PlaceableSystem.__pn_globalHooked = true
    Logging.info("[PN] Global PlaceableSystem hooks installed")
end

-- Install immediately
hookPlaceableSystemGlobals()

-- ---------- snapshot scan (fallback) ----------
local function doScan()
    _entries     = {}
    _byFarmIndex = {}

    local ps  = g_currentMission and g_currentMission.placeableSystem or nil
    local arr = ps and ps.placeables or nil

    if arr ~= nil then
        for _, placeable in ipairs(arr) do
            _classify(placeable, "Scan")
        end
    end
    log("Scan complete: %d (animal-capable) entries now tracked.", #_entries)
    return #_entries
end

-- ---------- public API ----------
function PN_HusbandryScan.isReady()
    return _isReady
end

function PN_HusbandryScan.getAll()
    return _entries
end

function PN_HusbandryScan.getByFarm(farmId)
    return _byFarmIndex[farmId or 0] or {}
end

function PN_HusbandryScan.getFirstByType(wantedType)
    local t = string.upper(wantedType or "")
    for _, e in ipairs(_entries) do
        if e.type == t then return e end
    end
    return nil
end

-- ---------- lifecycle ----------
function PN_HusbandryScan:onMissionStarted()
    hookPlaceableSystemGlobals()  -- in case class wasn’t ready at file load
    doScan()
    _isReady = true
    log("PN_HusbandryScan ready.")
end

-- delayed one-shot rescan (guarded)
PN_HusbandryScan._bootElapsed = 0
PN_HusbandryScan._rescanned   = false
function PN_HusbandryScan.tick(dt)
    hookPlaceableSystemGlobals()
    if type(dt) ~= "number" then return end
    if not _isReady then return end
    if PN_HusbandryScan._rescanned then return end

    PN_HusbandryScan._bootElapsed = PN_HusbandryScan._bootElapsed + dt
    if PN_HusbandryScan._bootElapsed >= 2000 then
        local n = doScan()
        log("Delayed rescan; entries=%d", n or -1)
        PN_HusbandryScan._rescanned = true
    end
end

addModEventListener(PN_HusbandryScan)
