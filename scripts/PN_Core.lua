PN_Core = PN_Core or {}
PN_Core.metricsByKey = PN_Core.metricsByKey or {}
PN_Core.unknownFeeds = PN_Core.unknownFeeds or {}

local function upper(value)
    return tostring(value or ""):upper()
end

local function clamp01(value)
    return math.clamp(tonumber(value) or 0, 0, 1)
end

local function speciesFromAnimal(animal)
    local subType = upper(animal ~= nil and animal.subType or "")
    if subType:find("GOAT", 1, true) ~= nil then return "GOAT" end
    local typeIndex = animal ~= nil and animal.animalTypeIndex or nil
    if AnimalType ~= nil then
        if typeIndex == AnimalType.COW then return "COW" end
        if typeIndex == AnimalType.SHEEP then return "SHEEP" end
        if typeIndex == AnimalType.PIG then return "PIG" end
        if typeIndex == AnimalType.CHICKEN then return "CHICKEN" end
        if typeIndex == AnimalType.HORSE then return "HORSE" end
    end
    if subType:find("COW", 1, true) or subType:find("BULL", 1, true) then return "COW" end
    if subType:find("SHEEP", 1, true) or subType:find("RAM", 1, true) then return "SHEEP" end
    if subType:find("PIG", 1, true) then return "PIG" end
    if subType:find("CHICKEN", 1, true) or subType:find("ROOSTER", 1, true) then return "CHICKEN" end
    if subType:find("HORSE", 1, true) then return "HORSE" end
    return "DEFAULT"
end

local function builtInStage(animal, species)
    local age = tonumber(animal.age) or 0
    local gender = tostring(animal.gender or "female"):lower()
    local female = gender == "female"
    local lactating = animal.isLactating == true
    local pregnant = animal.isPregnant == true
    local castrated = animal.isCastrated == true

    if species == "COW" then
        if age < 6 then return "CALF" end
        if female then
            if age < 18 then return "HEIFER" end
            return lactating and "COW_LACT" or (pregnant and "COW_GEST" or "COW_DRY")
        end
        if age < 18 then return "YEARLING" end
        return castrated and "STEER_FINISH" or "BULL"
    elseif species == "SHEEP" then
        if age < 5 then return "LAMB" end
        if female then
            if age < 8 then return "GROWER" end
            return lactating and "EWE_LACT" or (pregnant and "EWE_GEST" or "EWE_DRY")
        end
        return castrated and "WETHER_FINISH" or (age < 8 and "RAM" or "RAM_ADULT")
    elseif species == "GOAT" then
        if age < 5 then return "KID" end
        if female then
            if age < 8 then return "GROWER" end
            return lactating and "DOE_LACT" or (pregnant and "DOE_GEST" or "DOE_DRY")
        end
        return castrated and "WETHER_FINISH" or (age < 8 and "BUCK" or "BUCK_ADULT")
    elseif species == "PIG" then
        if age < 6 then return "PIGLET" end
        if female then
            if age < 8 then return "GILT" end
            return lactating and "SOW_LACT" or (pregnant and "SOW_GEST" or "SOW_DRY")
        end
        return castrated and "BARROW_FINISH" or (age < 8 and "BOAR" or "BOAR_ADULT")
    elseif species == "CHICKEN" then
        if age < 6 then return "CHICK" end
        return female and "LAYER" or "ROOSTER"
    elseif species == "HORSE" then
        if age < 6 then return "FOAL" end
        if age < 12 then return "WEANLING" end
        if female then
            if age < 22 then return "YEARLING" end
            return lactating and "MARE_LACT" or (pregnant and "MARE_GEST" or "MARE_DRY")
        end
        if castrated then return "GELDING" end
        return age < 36 and "COLT" or "STALLION"
    end
    return "DEFAULT"
end

local function configuredStage(animal, species, config)
    local bands = config.stages[species]
    if bands == nil then return nil end
    local age = tonumber(animal.age) or 0
    local gender = tostring(animal.gender or ""):lower()
    local function statusMatches(band)
        local name = band.name or ""
        local lactating = animal.isLactating == true
        local pregnant = animal.isPregnant == true
        local castrated = animal.isCastrated == true
        if band.lactating ~= nil and band.lactating ~= lactating then return false end
        if band.pregnant ~= nil and band.pregnant ~= pregnant then return false end
        if band.castrated ~= nil and band.castrated ~= castrated then return false end
        if band.lactating == nil and name:find("LACT", 1, true) and not lactating then return false end
        if band.pregnant == nil and name:find("GEST", 1, true) and not pregnant then return false end
        if name:find("DRY", 1, true) and (lactating or pregnant) then return false end
        local castratedName = name:find("STEER", 1, true) or name:find("WETHER", 1, true)
            or name:find("BARROW", 1, true) or name:find("GELDING", 1, true)
        if band.castrated == nil and castratedName and not castrated then return false end
        local intactName = name == "BULL" or name == "RAM" or name == "RAM_ADULT" or name == "BUCK"
            or name == "BUCK_ADULT" or name == "BOAR" or name == "BOAR_ADULT" or name == "STALLION"
        if band.castrated == nil and intactName and castrated then return false end
        return true
    end
    local selected = nil
    for _, band in ipairs(bands) do
        if (band.gender == nil or band.gender == gender) and age >= band.minAgeM and age < band.maxAgeM
                and statusMatches(band) and (selected == nil or band.minAgeM > selected.minAgeM) then
            selected = band
        end
    end
    return selected ~= nil and selected.name or nil
end

function PN_Core.getStage(animal, species)
    local config = PN_Settings.load(false)
    return configuredStage(animal, species, config) or builtInStage(animal, species)
end

local function nutritionTarget(config, species, stage)
    local speciesTargets = config.targets[species] or config.targets.DEFAULT
    return speciesTargets[stage] or speciesTargets.default or speciesTargets.DEFAULT or config.targets.DEFAULT.default
end

local function fillTypeName(index)
    if g_fillTypeManager ~= nil and g_fillTypeManager.getFillTypeNameByIndex ~= nil then
        return upper(g_fillTypeManager:getFillTypeNameByIndex(index))
    end
    local fillType = g_fillTypeManager ~= nil and g_fillTypeManager.fillTypes ~= nil and g_fillTypeManager.fillTypes[index] or nil
    return upper(fillType ~= nil and fillType.name or index)
end

local function kilograms(index, litres)
    local fillType = g_fillTypeManager ~= nil and g_fillTypeManager.fillTypes ~= nil and g_fillTypeManager.fillTypes[index] or nil
    local massPerLitre = fillType ~= nil and tonumber(fillType.massPerLiter) or nil
    local kgPerLitre = massPerLitre ~= nil and massPerLitre > 0 and massPerLitre * 1000 or 1
    return math.max(tonumber(litres) or 0, 0) * kgPerLitre
end

local currentStamp

local function ration(entry, config)
    local stamp = currentStamp()
    if entry.rationCache ~= nil and entry.rationCache.stamp == stamp then return entry.rationCache end
    local food = entry.placeable ~= nil and entry.placeable.spec_husbandryFood or nil
    local totalKg, dryMatterKg, energyMJ, proteinKg, unknownKg = 0, 0, 0, 0, 0
    local signatureParts = {}
    for fillTypeIndex, litres in pairs(food ~= nil and food.fillLevels or {}) do
        local kg = kilograms(fillTypeIndex, litres)
        if kg > 0.0001 then
            local rawName = fillTypeName(fillTypeIndex)
            local token = config.feedAliases[rawName] or rawName
            local feed = config.feedMatrix[token]
            totalKg = totalKg + kg
            table.insert(signatureParts, string.format("%s=%.1f", token, kg))
            if feed ~= nil then
                dryMatterKg = dryMatterKg + kg * feed.dm
                energyMJ = energyMJ + kg * feed.energyMJ
                proteinKg = proteinKg + kg * feed.proteinKg
            else
                dryMatterKg = dryMatterKg + kg
                unknownKg = unknownKg + kg
                if not PN_Core.unknownFeeds[rawName] then
                    PN_Core.unknownFeeds[rawName] = true
                    PN_Log.warning("Unknown feed '%s'; it contributes dry matter but no energy or protein", rawName)
                end
            end
        end
    end
    table.sort(signatureParts)
    local result = {
        totalKg=totalKg, dryMatterKg=dryMatterKg, energyMJ=energyMJ, proteinKg=proteinKg,
        unknownKg=unknownKg, signature=table.concat(signatureParts, "|"), stamp=stamp
    }
    entry.rationCache = result
    return result
end

currentStamp = function()
    local environment = g_currentMission ~= nil and g_currentMission.environment or nil
    if environment == nil then return "0" end
    return string.format("%s:%s:%s:%s", tostring(environment.currentYear or 0),
        tostring(environment.currentPeriod or 0), tostring(environment.currentDayInPeriod or 0),
        tostring(environment.currentHour or math.floor((environment.dayTime or 0) / 3600000)))
end

local function metricFor(entry, animal, baseFoodFactor)
    local config = PN_Settings.load(false)
    local species = speciesFromAnimal(animal)
    local stage = PN_Core.getStage(animal, species)
    local target = nutritionTarget(config, species, stage)
    local mix = ration(entry, config)
    local actualEnergyDensity = mix.dryMatterKg > 0 and mix.energyMJ / mix.dryMatterKg or 0
    local actualProteinDensity = mix.dryMatterKg > 0 and mix.proteinKg / mix.dryMatterKg or 0
    local targetEnergyDensity = target.energyMJ / target.dmiKg
    local targetProteinDensity = target.proteinKg / target.dmiKg
    local energyRatio = clamp01(actualEnergyDensity / targetEnergyDensity)
    local proteinRatio = clamp01(actualProteinDensity / targetProteinDensity)
    local quality = math.min(energyRatio, proteinRatio)
    local effective = clamp01(clamp01(baseFoodFactor) * quality)
    return species, stage, mix, energyRatio, proteinRatio, quality, effective
end

local function addSummary(entry, animal, baseFoodFactor, species, stage, mix, energyRatio, proteinRatio, quality, effective, isPreview)
    local stamp = currentStamp()
    local summary = PN_Core.metricsByKey[entry.key]
    if summary == nil or summary.stamp ~= stamp then
        summary = {
            key=entry.key, name=entry.name, farmId=entry.farmId, species=species, stamp=stamp,
            head=0, samples=0, baseTotal=0, effectiveTotal=0, energyTotal=0,
            proteinTotal=0, qualityTotal=0, stages={}, dryMatterKg=mix.dryMatterKg,
            unknownKg=mix.unknownKg, rationSignature=mix.signature, sampledIds={},
            individuals={}, preview=isPreview == true
        }
        PN_Core.metricsByKey[entry.key] = summary
    end
    local animalId = tostring(animal.uniqueId or animal)
    if summary.sampledIds[animalId] then return end
    summary.sampledIds[animalId] = true
    local head = math.max(tonumber(animal.numAnimals) or 1, 1)
    summary.name, summary.farmId, summary.species = entry.name, entry.farmId, species
    summary.head = summary.head + head
    summary.samples = summary.samples + head
    summary.baseTotal = summary.baseTotal + clamp01(baseFoodFactor) * head
    summary.effectiveTotal = summary.effectiveTotal + effective * head
    summary.energyTotal = summary.energyTotal + energyRatio * head
    summary.proteinTotal = summary.proteinTotal + proteinRatio * head
    summary.qualityTotal = summary.qualityTotal + quality * head
    summary.stages[stage] = (summary.stages[stage] or 0) + head
    summary.dryMatterKg, summary.unknownKg, summary.rationSignature = mix.dryMatterKg, mix.unknownKg, mix.signature

    local animalName = tostring(animal.name or "")
    if animalName == "" and animal.getName ~= nil then
        local ok, name = pcall(animal.getName, animal)
        if ok then animalName = tostring(name or "") end
    end
    if animalName == "" then animalName = "#" .. tostring(animal.uniqueId or "?") end
    table.insert(summary.individuals, {
        id=tostring(animal.uniqueId or animalId), name=animalName, head=head,
        species=species, stage=stage, gender=tostring(animal.gender or ""),
        age=tonumber(animal.age) or 0, weight=tonumber(animal.weight) or 0,
        targetWeight=tonumber(animal.targetWeight) or 0, health=tonumber(animal.health) or 0,
        pregnant=animal.isPregnant == true, lactating=animal.isLactating == true,
        castrated=animal.isCastrated == true, energy=energyRatio, protein=proteinRatio,
        quality=quality, baseFood=clamp01(baseFoodFactor), effectiveFood=effective
    })
end

function PN_Core.adjustFoodFactor(animal, baseFoodFactor)
    local entry = PN_Husbandry.getFromAnimal(animal)
    if entry == nil then return baseFoodFactor end
    local existing = PN_Core.metricsByKey[entry.key]
    if existing ~= nil and existing.preview == true then PN_Core.metricsByKey[entry.key] = nil end
    local species, stage, mix, energyRatio, proteinRatio, quality, effective = metricFor(entry, animal, baseFoodFactor)
    addSummary(entry, animal, baseFoodFactor, species, stage, mix, energyRatio, proteinRatio, quality, effective, false)
    return effective
end

local function currentFoodFactor(entry)
    local placeable = entry ~= nil and entry.placeable or nil
    if placeable ~= nil and placeable.getFoodInfos ~= nil then
        local ok, infos = pcall(placeable.getFoodInfos, placeable)
        if ok and type(infos) == "table" then
            local value, capacity = 0, 0
            for _, info in ipairs(infos) do
                if not info.ignoreCapacity then
                    value = value + math.max(tonumber(info.value) or 0, 0)
                    capacity = math.max(capacity, tonumber(info.capacity) or 0)
                end
            end
            if capacity > 0 then return clamp01(value / capacity) end
        end
    end

    local food = placeable ~= nil and placeable.spec_husbandryFood or nil
    for _, litres in pairs(food ~= nil and food.fillLevels or {}) do
        if (tonumber(litres) or 0) > 0 then return 1 end
    end
    return 0
end

function PN_Core.refreshEntry(entry, force)
    if entry == nil or entry.clusterSystem == nil then return false end
    local existing = PN_Core.metricsByKey[entry.key]
    if not force and existing ~= nil and existing.stamp == currentStamp() and existing.preview ~= true then return true end

    local clusters = nil
    if entry.clusterSystem.getClusters ~= nil then
        local ok, result = pcall(entry.clusterSystem.getClusters, entry.clusterSystem)
        if ok and type(result) == "table" then clusters = result end
    end
    clusters = clusters or entry.clusterSystem.animals
    if type(clusters) ~= "table" or next(clusters) == nil then
        PN_Core.metricsByKey[entry.key] = nil
        return false
    end

    PN_Core.metricsByKey[entry.key] = nil
    local baseFoodFactor = currentFoodFactor(entry)
    for _, animal in pairs(clusters) do
        if animal ~= nil and animal.isDead ~= true and (tonumber(animal.numAnimals) or 1) > 0 then
            local species, stage, mix, energyRatio, proteinRatio, quality, effective = metricFor(entry, animal, baseFoodFactor)
            addSummary(entry, animal, baseFoodFactor, species, stage, mix, energyRatio, proteinRatio, quality, effective, true)
        end
    end
    return PN_Core.metricsByKey[entry.key] ~= nil
end

function PN_Core.refreshAllMetrics(force)
    for _, entry in ipairs(PN_Husbandry.entries or {}) do PN_Core.refreshEntry(entry, force) end
end

local function averaged(summary)
    local divisor = math.max(summary.samples or 0, 1)
    local stages = {}
    for name, count in pairs(summary.stages or {}) do table.insert(stages, { name=name, count=count }) end
    table.sort(stages, function(a, b) return a.name < b.name end)
    local stageParts = {}
    for _, item in ipairs(stages) do table.insert(stageParts, string.format("%s %d", item.name, item.count)) end
    local stagesText = summary.remoteStages or table.concat(stageParts, ", ")
    local individuals = {}
    for _, animal in ipairs(summary.individuals or {}) do table.insert(individuals, animal) end
    table.sort(individuals, function(a, b)
        if tostring(a.stage) ~= tostring(b.stage) then return tostring(a.stage) < tostring(b.stage) end
        if (a.age or 0) ~= (b.age or 0) then return (a.age or 0) < (b.age or 0) end
        return tostring(a.name) < tostring(b.name)
    end)
    return {
        key=summary.key, name=summary.name, farmId=summary.farmId, species=summary.species,
        head=summary.head or 0, baseFood=summary.baseTotal / divisor,
        effectiveFood=summary.effectiveTotal / divisor, energy=summary.energyTotal / divisor,
        protein=summary.proteinTotal / divisor, quality=summary.qualityTotal / divisor,
        dryMatterKg=summary.dryMatterKg or 0, unknownKg=summary.unknownKg or 0,
        stages=stagesText, stamp=summary.stamp or "", individuals=individuals,
        individualTotal=summary.individualTotal or #individuals
    }
end

function PN_Core.getMetrics(farmId)
    local rows = {}
    for _, summary in pairs(PN_Core.metricsByKey) do
        if farmId == nil or farmId == 0 or summary.farmId == farmId then table.insert(rows, averaged(summary)) end
    end
    table.sort(rows, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return rows
end

function PN_Core.applyRemoteMetric(metric)
    PN_Core.metricsByKey[metric.key] = {
        key=metric.key, name=metric.name, farmId=metric.farmId, species=metric.species,
        head=metric.head, samples=1, baseTotal=metric.baseFood, effectiveTotal=metric.effectiveFood,
        energyTotal=metric.energy, proteinTotal=metric.protein, qualityTotal=metric.quality,
        dryMatterKg=metric.dryMatterKg, unknownKg=metric.unknownKg,
        stages={ [metric.stages ~= "" and metric.stages or "Awaiting stage data"] = 1 }, stamp=metric.stamp,
        remoteStages=metric.stages, individuals=metric.individuals or {},
        individualTotal=metric.individualTotal or #(metric.individuals or {})
    }
end

function PN_Core.reset()
    PN_Core.metricsByKey = {}
    PN_Core.unknownFeeds = {}
    for _, entry in ipairs(PN_Husbandry ~= nil and PN_Husbandry.entries or {}) do entry.rationCache = nil end
end

return PN_Core
