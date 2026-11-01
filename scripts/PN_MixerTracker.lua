-- Diagnostic-only mixer ingredient ledger for FS25_CustomAnimalFoodRecipes.
-- No nutrition, husbandry, fill level, or animal behaviour is changed here.
PN_MixerTracker = PN_MixerTracker or {
    installed = false, enabled = false, tracing = false,
    vehicles = setmetatable({}, {__mode = "k"})
}

local MOD_NAME = "FS25_CustomAnimalFoodRecipes"
local UNKNOWN = "__UNTRACKED__"
local EPSILON = 0.1

local function fillName(index)
    if index == nil then return UNKNOWN end
    if g_fillTypeManager ~= nil and g_fillTypeManager.getFillTypeNameByIndex ~= nil then
        local name = g_fillTypeManager:getFillTypeNameByIndex(index)
        if name ~= nil and name ~= "" then return tostring(name):upper() end
    end
    return UNKNOWN
end

local function wagonName(vehicle)
    if vehicle ~= nil and vehicle.getName ~= nil then
        local ok, name = pcall(vehicle.getName, vehicle)
        if ok and name ~= nil and name ~= "" then return tostring(name) end
    end
    return "Mixer wagon"
end

local function measuredLevel(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_mixerWagon or nil
    if spec == nil or spec.fillUnitIndex == nil or vehicle.getFillUnitFillLevel == nil then return 0 end
    return math.max(tonumber(vehicle:getFillUnitFillLevel(spec.fillUnitIndex)) or 0, 0)
end

local function totalIngredients(state)
    local sum = 0
    for _, litres in pairs(state.ingredients or {}) do sum = sum + (tonumber(litres) or 0) end
    return sum
end

local function scaleIngredients(state, target)
    local before = totalIngredients(state)
    if before <= EPSILON then
        state.ingredients = {}
    else
        for name, litres in pairs(state.ingredients) do
            local adjusted = litres * math.max(target, 0) / before
            state.ingredients[name] = adjusted > EPSILON and adjusted or nil
        end
    end
end

local function addIngredient(state, name, litres)
    if litres <= EPSILON then return end
    state.ingredients[name] = (state.ingredients[name] or 0) + litres
    if name == UNKNOWN then state.quality = "incomplete" end
end

local function reconstructedState(vehicle)
    local state = {ingredients = {}, quality = "observed"}
    local actual = measuredLevel(vehicle)
    if actual <= EPSILON then return state end

    local spec = vehicle.spec_mixerWagon
    local rows = spec ~= nil and spec.mixerWagonFillTypes or nil
    local recovered = 0
    if type(rows) == "table" then
        for _, row in ipairs(rows) do
            local litres = math.max(tonumber(row.fillLevel) or 0, 0)
            if litres > EPSILON then
                local uniqueIndex, count = nil, 0
                for index, supported in pairs(row.fillTypes or {}) do
                    if supported then uniqueIndex, count = index, count + 1 end
                end
                local name = count == 1 and fillName(uniqueIndex) or UNKNOWN
                addIngredient(state, name, litres)
                recovered = recovered + litres
            end
        end
    end

    if recovered <= EPSILON then
        state.ingredients = {[UNKNOWN] = actual}
    else
        scaleIngredients(state, actual)
    end
    state.quality = state.ingredients[UNKNOWN] and "incomplete" or "reconstructed"
    return state
end

local function reconcile(vehicle, state, actual)
    local recorded = totalIngredients(state)
    if math.abs(actual - recorded) <= EPSILON then return end
    if actual <= EPSILON then
        state.ingredients = {}
        state.quality = "observed"
    elseif recorded <= EPSILON then
        state.ingredients[UNKNOWN] = actual
        state.quality = "incomplete"
    elseif actual < recorded then
        -- If another mod changed the volume, preserve the known ingredient proportions.
        scaleIngredients(state, actual)
        if PN_MixerTracker.tracing then
            PN_Log.info("[Mixer] reconciled unobserved removal on %s: %.1f L", wagonName(vehicle), recorded - actual)
        end
    else
        addIngredient(state, UNKNOWN, actual - recorded)
        if PN_MixerTracker.tracing then
            PN_Log.warning("[Mixer] unobserved addition on %s: %.1f L", wagonName(vehicle), actual - recorded)
        end
    end
end

function PN_MixerTracker.track(vehicle)
    if not PN_MixerTracker.enabled or vehicle == nil or vehicle.spec_mixerWagon == nil then return end
    local state = PN_MixerTracker.vehicles[vehicle]
    if state == nil then
        state = vehicle.pnMixerIngredientLedger or reconstructedState(vehicle)
        PN_MixerTracker.vehicles[vehicle] = state
        vehicle.pnMixerIngredientLedger = state
        PN_Log.info("[Mixer] tracking %s (initial %.1f L, source=%s)",
            wagonName(vehicle), totalIngredients(state), state.quality)
    end
    if vehicle.pnMixerInstrumented ~= true then
        local previous = vehicle.addFillUnitFillLevel
        if type(previous) == "function" then
            vehicle.addFillUnitFillLevel = function(target, farmId, fillUnitIndex, delta, fillTypeIndex, toolType, fillPositionData)
                local spec = target.spec_mixerWagon
                local isMixer = spec ~= nil and fillUnitIndex == spec.fillUnitIndex
                local before = isMixer and measuredLevel(target) or 0
                -- Always call the complete existing chain, including CustomAnimalFoodRecipes.
                local result = previous(target, farmId, fillUnitIndex, delta, fillTypeIndex, toolType, fillPositionData)
                if isMixer and PN_MixerTracker.enabled and g_server ~= nil then
                    local after = measuredLevel(target)
                    local ok, err = pcall(PN_MixerTracker.recordChange, target, fillTypeIndex, before, after)
                    if not ok then PN_Log.warning("[Mixer] recorder failed: %s", tostring(err)) end
                end
                return result
            end
            vehicle.pnMixerInstrumented = true
        end
    end
    reconcile(vehicle, state, measuredLevel(vehicle))
end

function PN_MixerTracker.recordChange(vehicle, fillTypeIndex, before, after)
    local state = PN_MixerTracker.vehicles[vehicle]
    if state == nil then return end
    reconcile(vehicle, state, before)
    local delta = after - before
    if math.abs(delta) <= EPSILON then return end

    if delta > 0 then
        local spec = vehicle.spec_mixerWagon
        local accepted = spec ~= nil and spec.fillTypeToMixerWagonFillType ~= nil
            and spec.fillTypeToMixerWagonFillType[fillTypeIndex] ~= nil
        local name = accepted and fillName(fillTypeIndex) or UNKNOWN
        addIngredient(state, name, delta)
        if PN_MixerTracker.tracing then
            PN_Log.info("[Mixer] %s +%.1f L %s (incoming=%s)",
                wagonName(vehicle), delta, name, fillName(fillTypeIndex))
        end
    else
        scaleIngredients(state, after)
        if PN_MixerTracker.tracing then
            PN_Log.info("[Mixer] %s %.1f L removed; remaining=%.1f L",
                wagonName(vehicle), -delta, after)
        end
    end
end

function PN_MixerTracker.scan()
    if not PN_MixerTracker.enabled or g_server == nil then return end
    local system = g_currentMission ~= nil and g_currentMission.vehicleSystem or nil
    for _, vehicle in pairs(system ~= nil and system.vehicles or {}) do
        if vehicle ~= nil and vehicle.spec_mixerWagon ~= nil then
            PN_MixerTracker.track(vehicle)
        end
    end
end

function PN_MixerTracker.dump()
    if not PN_MixerTracker.enabled then
        print("[PN][Mixer] Custom Animal Food Recipes is not loaded; diagnostics inactive")
        return
    end
    PN_MixerTracker.scan()
    local count = 0
    for vehicle, state in pairs(PN_MixerTracker.vehicles) do
        if vehicle ~= nil then
            count = count + 1
            local spec = vehicle.spec_mixerWagon
            local output = spec ~= nil and spec.customAnimalFoodOutputFillType or nil
            print(string.format("[PN][Mixer] %s | output=%s | measured=%.1f L | ledger=%.1f L | source=%s",
                wagonName(vehicle), fillName(output), measuredLevel(vehicle),
                totalIngredients(state), tostring(state.quality)))
            local keys = {}
            for name, _ in pairs(state.ingredients) do table.insert(keys, name) end
            table.sort(keys)
            for _, name in ipairs(keys) do
                print(string.format("[PN][Mixer]   %-24s %.1f L", name, state.ingredients[name]))
            end
        end
    end
    print(string.format("[PN][Mixer] tracked wagons=%d; trace=%s", count, tostring(PN_MixerTracker.tracing)))
end

function PN_MixerTracker.toggleTrace()
    PN_MixerTracker.tracing = not PN_MixerTracker.tracing
    print("[PN][Mixer] input/removal trace=" .. tostring(PN_MixerTracker.tracing))
end

function PN_MixerTracker.install()
    if PN_MixerTracker.installed then
        PN_MixerTracker.enabled = g_modIsLoaded ~= nil and g_modIsLoaded[MOD_NAME] == true
        return PN_MixerTracker.enabled
    end
    local loaded = g_modIsLoaded ~= nil and g_modIsLoaded[MOD_NAME] == true
    if not loaded then
        PN_Log.info("[Mixer] optional %s not loaded; tracker inactive", MOD_NAME)
        return false
    end
    if MixerWagon == nil or MixerWagon.onPostLoad == nil or MixerWagon.saveToXMLFile == nil
            or Vehicle == nil or Utils == nil or Utils.appendedFunction == nil
            or Vehicle.xmlSchemaSavegame == nil
            or XMLValueType == nil then
        PN_Log.warning("[Mixer] game save hooks unavailable; tracker inactive")
        return false
    end

    local schema = Vehicle.xmlSchemaSavegame
    schema:register(XMLValueType.STRING, "vehicles.vehicle(?).mixerWagon.precisionNutrition#quality",
        "PN mixer ingredient ledger provenance")
    schema:register(XMLValueType.STRING, "vehicles.vehicle(?).mixerWagon.precisionNutrition.ingredient(?)#name",
        "PN actual ingredient fill type")
    schema:register(XMLValueType.FLOAT, "vehicles.vehicle(?).mixerWagon.precisionNutrition.ingredient(?)#litres",
        "PN actual ingredient quantity", 0)

    MixerWagon.saveToXMLFile = Utils.appendedFunction(MixerWagon.saveToXMLFile,
        function(vehicle, xmlFile, key)
            if g_server == nil then return end
            local state = PN_MixerTracker.vehicles[vehicle] or vehicle.pnMixerIngredientLedger
            if state == nil then return end
            reconcile(vehicle, state, measuredLevel(vehicle))
            local root = key .. ".precisionNutrition"
            xmlFile:setValue(root .. "#quality", state.quality or "incomplete")
            local keys = {}
            for name, litres in pairs(state.ingredients) do
                if litres > EPSILON then table.insert(keys, name) end
            end
            table.sort(keys)
            for i, name in ipairs(keys) do
                local item = string.format("%s.ingredient(%d)", root, i - 1)
                xmlFile:setValue(item .. "#name", name)
                xmlFile:setValue(item .. "#litres", state.ingredients[name])
            end
        end)

    MixerWagon.onPostLoad = Utils.appendedFunction(MixerWagon.onPostLoad,
        function(vehicle, savegame)
            if g_server == nil or savegame == nil or savegame.xmlFile == nil or savegame.key == nil then return end
            local root = savegame.key .. ".mixerWagon.precisionNutrition"
            local quality = savegame.xmlFile:getValue(root .. "#quality")
            if quality == nil then return end
            local state = {quality = quality, ingredients = {}}
            local i = 0
            while i < 100 do
                local item = string.format("%s.ingredient(%d)", root, i)
                local name = savegame.xmlFile:getValue(item .. "#name")
                if name == nil then break end
                local litres = tonumber(savegame.xmlFile:getValue(item .. "#litres", 0)) or 0
                if litres > EPSILON then addIngredient(state, name, litres) end
                i = i + 1
            end
            vehicle.pnMixerIngredientLedger = state
            PN_MixerTracker.vehicles[vehicle] = state
            PN_Log.info("[Mixer] restored %s: %.1f L (%s)", wagonName(vehicle),
                totalIngredients(state), state.quality)
        end)

    PN_MixerTracker.installed = true
    PN_MixerTracker.enabled = true
    PN_Log.info("[Mixer] diagnostic tracker active with %s (server only)", MOD_NAME)
    return true
end

function PN_MixerTracker.reset()
    PN_MixerTracker.enabled = false
    PN_MixerTracker.tracing = false
    PN_MixerTracker.vehicles = setmetatable({}, {__mode = "k"})
end

return PN_MixerTracker
