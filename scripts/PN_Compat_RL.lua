PN_Compat_RL = PN_Compat_RL or { installed=false, enabled=false }

function PN_Compat_RL.install()
    if PN_Compat_RL.installed then
        PN_Compat_RL.enabled = true
        return true
    end
    PN_Compat_RL.installed = true

    local loaded = g_modIsLoaded ~= nil and g_modIsLoaded.FS25_RealisticLivestockRM == true
    if not loaded or Animal == nil or Animal.updateHealth == nil then
        PN_Log.error("Realistic Livestock RM was not available; Precision Nutrition is disabled")
        PN_Compat_RL.enabled = false
        return false
    end

    Animal.updateHealth = Utils.overwrittenFunction(Animal.updateHealth, function(superFunc, animal, foodFactor)
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

    PN_Compat_RL.enabled = true
    PN_Log.info("Connected to Realistic Livestock RM through Animal.updateHealth")
    return true
end

function PN_Compat_RL.disable()
    PN_Compat_RL.enabled = false
end

return PN_Compat_RL
