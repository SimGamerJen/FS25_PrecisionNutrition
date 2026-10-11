PN_Compat_RL = PN_Compat_RL or { installed=false, enabled=false }

local RLRM_MOD_NAME = "FS25_RealisticLivestockRM"

local function resolveRLRMAnimalClass()
    -- FS25 runs each mod in its own environment. RLRM's replacement Animal
    -- class therefore lives in the RLRM environment, not PN's `Animal` global.
    local metatable = getmetatable(_G)
    local realGlobal = metatable ~= nil and metatable.__index or nil
    local rlEnvironment = nil

    if type(realGlobal) == "table" then
        rlEnvironment = rawget(realGlobal, RLRM_MOD_NAME)
    end
    if rlEnvironment == nil then
        rlEnvironment = rawget(_G, RLRM_MOD_NAME)
    end

    if type(rlEnvironment) ~= "table" then
        return nil, "mod environment was not published"
    end

    local animalClass = rawget(rlEnvironment, "Animal")
    if type(animalClass) ~= "table" then
        return nil, "RLRM Animal class was not found"
    end
    if type(animalClass.updateHealth) ~= "function" then
        return nil, "RLRM Animal.updateHealth was not found"
    end

    return animalClass, nil
end

function PN_Compat_RL.install()
    if PN_Compat_RL.installed then
        PN_Compat_RL.enabled = true
        return true
    end

    local loaded = g_modIsLoaded ~= nil and g_modIsLoaded[RLRM_MOD_NAME] == true
    if not loaded then
        PN_Log.error("Realistic Livestock RM is not loaded; Precision Nutrition is disabled")
        PN_Compat_RL.enabled = false
        return false
    end

    local animalClass, resolveError = resolveRLRMAnimalClass()
    if animalClass == nil then
        PN_Log.error("Realistic Livestock RM is loaded but its integration point is unavailable (%s); Precision Nutrition is disabled", tostring(resolveError))
        PN_Compat_RL.enabled = false
        return false
    end

    animalClass.updateHealth = Utils.overwrittenFunction(animalClass.updateHealth, function(animal, superFunc, foodFactor)
        if PN_Compat_RL.enabled and g_server ~= nil and animal ~= nil then
            local ok, adjusted = pcall(PN_Core.adjustFoodFactor, animal, foodFactor)
            if ok then
                foodFactor = adjusted
            else
                PN_Log.error("Nutrition calculation failed for animal %s: %s", tostring(animal.uniqueId), tostring(adjusted))
            end
        end
        return superFunc(animal, foodFactor)
    end)

    PN_Compat_RL.installed = true
    PN_Compat_RL.enabled = true
    PN_Log.info("Connected to Realistic Livestock RM through its mod-environment Animal.updateHealth")
    return true
end

function PN_Compat_RL.disable()
    PN_Compat_RL.enabled = false
end

return PN_Compat_RL
