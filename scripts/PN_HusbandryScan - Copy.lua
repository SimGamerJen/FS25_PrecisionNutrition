-- FS25_PrecisionNutrition / scripts / PN_HusbandryScan.lua
-- RL-style live discovery of animal-capable placeables with global (class) hooks.

PN_HusbandryScan = {}

local PN_TAG   = "[PN]"
local PN_DEBUG = true

local _isReady     = false
local _entries     = {}
local _byFarmIndex = {}

-- ---------- utils ----------
-- after the local state tables near the top:
PN_HusbandryScan._printedSummary = false
PN_HusbandryScan._bootElapsed = 0

-- in PN_HusbandryScan.tick(dt), after existing code that arms hooks:
if type(dt) == "number" then
    PN_HusbandryScan._bootElapsed = PN_HusbandryScan._bootElapsed + dt
    if not PN_HusbandryScan._printedSummary and PN_HusbandryScan._bootElapsed >= 3000 then
        Logging.info("[PN] Scan complete: %d (animal-capable) entries now tracked.", #PN_HusbandryScan.getAll())
        PN_HusbandryScan._printedSummary = true
    end
end

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

-- classify a single placeable now (idempotent enough for our needs)
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
    log("%s HIT: %s | farm=%d | type=%s | cluster=%s", tostring(via), entry.name, entry.farmId, entry.type, tostring(entry.clusterSystem ~= nil))
end

-- ---------- GLOBAL (class) hooks: install ASAP at file load ----------
local function hookPlaceableSystemGlobals()
    if PlaceableSystem == nil then return end
    if PlaceableSystem.__pn_globalHooked then return end

    -- After original: we want the instance that’s actually being registered
    if PlaceableSystem.addPlaceable ~= nil then
        PlaceableSystem.addPlaceable = Utils.appendedFunction(PlaceableSystem.addPlaceable, function(self, placeable, ...)
            _classify(placeable, "AddPlaceable")
        end)
    end

    -- These load funcs create/prepare the instance; actual registration still goes through addPlaceable
    if PlaceableSystem.loadPlaceable ~= nil then
        PlaceableSystem.loadPlaceable = Utils.appendedFunction(PlaceableSystem.loadPlaceable, function(self, xmlFile, ...)
            -- classification happens when the instance is added
        end)
    end
    if PlaceableSystem.loadPlaceableFromXML ~= nil then
        PlaceableSystem.loadPlaceableFromXML = Utils.appendedFunction(PlaceableSystem.loadPlaceableFromXML, function(self, xmlFilename, ...)
            -- classification happens when the instance is added
        end)
    end

    PlaceableSystem.__pn_globalHooked = true
    Logging.info("[PN] Global PlaceableSystem hooks installed")
end

-- Install global hooks immediately (as soon as this file is loaded)
hookPlaceableSystemGlobals()

-- ---------- snapshot scan as a fallback ----------
local function doScan()
    _entries     = {}
    _byFarmIndex = {}

    local ps  = g_currentMission and g_currentMission.placeableSystem or nil
    local arr = ps and ps.placeables or nil
    local count = 0

    if arr ~= nil then
        for _, placeable in ipairs(arr) do
            _classify(placeable, "Scan")
            count = count + 1  -- counts animal-capable ones only (via _classify’s early return)
        end
    end
    -- note: _classify logs each hit; we just summarize here
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
    -- just in case the class object wasn’t available at file-load time:
    hookPlaceableSystemGlobals()
    doScan()
    _isReady = true
    log("PN_HusbandryScan ready.")
end

-- delayed one-shot rescan (guarded)
PN_HusbandryScan._bootElapsed = 0
PN_HusbandryScan._rescanned   = false
function PN_HusbandryScan.tick(dt)
    hookPlaceableSystemGlobals() -- keep it armed no matter the load order
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
