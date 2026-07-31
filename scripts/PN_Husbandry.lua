PN_Husbandry = PN_Husbandry or {}
PN_Husbandry.entriesByKey = PN_Husbandry.entriesByKey or {}
PN_Husbandry.entries = PN_Husbandry.entries or {}

local function lower(value)
    return tostring(value or ""):lower()
end

local function ownerFarmId(placeable)
    if placeable == nil then return 0 end
    if placeable.getOwnerFarmId ~= nil then
        local ok, farmId = pcall(placeable.getOwnerFarmId, placeable)
        if ok and farmId ~= nil then return farmId end
    end
    return placeable.ownerFarmId or 0
end

local function objectId(placeable)
    if NetworkUtil ~= nil and NetworkUtil.getObjectId ~= nil then
        local ok, id = pcall(NetworkUtil.getObjectId, placeable)
        if ok and id ~= nil and id ~= 0 then return id end
    end
    return placeable.id or placeable.rootNode or tostring(placeable)
end

local function displayName(placeable)
    if placeable ~= nil and placeable.getName ~= nil then
        local ok, name = pcall(placeable.getName, placeable)
        if ok and name ~= nil and name ~= "" then return name end
    end
    return "Animal husbandry"
end

local function isHusbandry(placeable)
    return placeable ~= nil and placeable.spec_husbandryAnimals ~= nil
end

local function clusterSystem(placeable)
    local spec = placeable ~= nil and placeable.spec_husbandryAnimals or nil
    return spec ~= nil and spec.clusterSystem or nil
end

function PN_Husbandry.getKey(placeable)
    return string.format("%s:%s", tostring(ownerFarmId(placeable)), tostring(objectId(placeable)))
end

function PN_Husbandry.getOrCreate(placeable)
    if not isHusbandry(placeable) then return nil end
    local key = PN_Husbandry.getKey(placeable)
    local entry = PN_Husbandry.entriesByKey[key]
    if entry == nil then
        entry = { key=key }
        PN_Husbandry.entriesByKey[key] = entry
        table.insert(PN_Husbandry.entries, entry)
    end
    entry.placeable = placeable
    entry.clusterSystem = clusterSystem(placeable)
    entry.farmId = ownerFarmId(placeable)
    entry.name = displayName(placeable)
    entry.seen = true
    return entry
end

function PN_Husbandry.getFromAnimal(animal)
    local system = animal ~= nil and animal.clusterSystem or nil
    return PN_Husbandry.getOrCreate(system ~= nil and system.owner or nil)
end

function PN_Husbandry.scan()
    for _, entry in ipairs(PN_Husbandry.entries) do entry.seen = false end
    local placeableSystem = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    for _, placeable in ipairs(placeableSystem ~= nil and placeableSystem.placeables or {}) do
        PN_Husbandry.getOrCreate(placeable)
    end
    for i = #PN_Husbandry.entries, 1, -1 do
        local entry = PN_Husbandry.entries[i]
        if not entry.seen then
            PN_Husbandry.entriesByKey[entry.key] = nil
            if PN_Core ~= nil then PN_Core.metricsByKey[entry.key] = nil end
            table.remove(PN_Husbandry.entries, i)
        end
    end
end

function PN_Husbandry.reset()
    PN_Husbandry.entriesByKey = {}
    PN_Husbandry.entries = {}
end

return PN_Husbandry
