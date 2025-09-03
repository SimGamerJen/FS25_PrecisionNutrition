-- FS25_PrecisionNutrition / scripts / PN_Husbandry.lua
-- Compatibility shim so legacy PN code that expects "PN_Husbandry" keeps working.
-- It delegates to PN_HusbandryScan (the real implementation).

PN_Husbandry = {}

local function _scanReady()
    return PN_HusbandryScan ~= nil and PN_HusbandryScan.isReady ~= nil and PN_HusbandryScan:isReady()
end

function PN_Husbandry:isReady()
    return _scanReady()
end

function PN_Husbandry:getAll()
    if PN_HusbandryScan ~= nil and PN_HusbandryScan.getAll ~= nil then
        return PN_HusbandryScan:getAll()
    end
    return {}
end

function PN_Husbandry:getByFarm(farmId)
    if PN_HusbandryScan ~= nil and PN_HusbandryScan.getByFarm ~= nil then
        return PN_HusbandryScan:getByFarm(farmId)
    end
    return {}
end

function PN_Husbandry:getFirstByType(wantedType)
    if PN_HusbandryScan ~= nil and PN_HusbandryScan.getFirstByType ~= nil then
        return PN_HusbandryScan:getFirstByType(wantedType)
    end
    return nil
end

-- Optional: small log once scan becomes ready (safe + quiet otherwise)
function PN_Husbandry:onMissionStarted()
    if PN_HusbandryScan ~= nil then
        -- Let the scanner run its own discovery; nothing to do here.
    end
end

addModEventListener(PN_Husbandry)
