PN_Settings = PN_Settings or {}

local function upper(value)
    return tostring(value or ""):upper()
end

local function numberOr(value, fallback)
    value = tonumber(value)
    return value == nil and fallback or value
end

local function defaults()
    return {
        feedMatrix = {
            PASTURE_SPRING = { dm=0.18, energyMJ=3.4, proteinKg=0.050 },
            PASTURE_SUMMER = { dm=0.22, energyMJ=3.2, proteinKg=0.040 },
            PASTURE_AUTUMN = { dm=0.25, energyMJ=3.1, proteinKg=0.035 },
            PASTURE_WINTER = { dm=0.16, energyMJ=3.0, proteinKg=0.030 },
            GRASS_WINDROW  = { dm=0.30, energyMJ=3.2, proteinKg=0.036 },
            HAY            = { dm=0.85, energyMJ=5.2, proteinKg=0.100 },
            SILAGE         = { dm=0.35, energyMJ=3.8, proteinKg=0.035 },
            TMR            = { dm=0.60, energyMJ=6.6, proteinKg=0.084 },
            WHEAT          = { dm=0.86, energyMJ=6.7, proteinKg=0.105 },
            BARLEY         = { dm=0.86, energyMJ=6.5, proteinKg=0.100 },
            OAT            = { dm=0.86, energyMJ=6.2, proteinKg=0.105 },
            MAIZE          = { dm=0.86, energyMJ=7.8, proteinKg=0.075 },
            SORGHUM        = { dm=0.86, energyMJ=7.4, proteinKg=0.095 },
            RYE            = { dm=0.86, energyMJ=6.6, proteinKg=0.110 },
            TRITICALE      = { dm=0.86, energyMJ=6.8, proteinKg=0.115 },
            POTATO         = { dm=0.25, energyMJ=3.5, proteinKg=0.020 },
            SUGARBEET      = { dm=0.23, energyMJ=3.3, proteinKg=0.010 },
            PEA            = { dm=0.88, energyMJ=6.7, proteinKg=0.210 },
            PIG_FEED       = { dm=0.90, energyMJ=8.5, proteinKg=0.180 },
            CHICKEN_FEED   = { dm=0.90, energyMJ=7.1, proteinKg=0.160 },
            MINERAL        = { dm=1.00, energyMJ=0.0, proteinKg=0.000 }
        },
        feedAliases = {
            DRYGRASS_WINDROW="HAY", DRY_GRASS_WINDROW="HAY", WINDROW_DRYGRASS="HAY",
            WINDROW_HAY="HAY", DRYGRASS="HAY", DRY_GRASS="HAY", LUCERNE_HAY="HAY",
            CUT_GRASS="GRASS_WINDROW", CUTGRASS="GRASS_WINDROW", FRESH_GRASS="GRASS_WINDROW",
            FRESHGRASS="GRASS_WINDROW", GRASS="GRASS_WINDROW", GRASS_WET="GRASS_WINDROW",
            WETGRASS_WINDROW="GRASS_WINDROW", FORAGE="TMR", FORAGE_MIXING="TMR",
            FORAGE_MIXER="TMR", HAY_PELLETS="HAY", GRASS_PELLETS="HAY", PIGFOOD="PIG_FEED",
            MINERAL_FEED="MINERAL", CHAFF="SILAGE", MAIZE_CHAFF="SILAGE",
            SORGHUM_CHAFF="SILAGE", MAIZE_WHOLEPLANT="SILAGE"
        },
        targets = {
            COW={ default={ energyMJ=120, proteinKg=1.90, dmiKg=14.0 } },
            SHEEP={ default={ energyMJ=8, proteinKg=0.20, dmiKg=1.2 } },
            PIG={ default={ energyMJ=28, proteinKg=0.45, dmiKg=2.5 } },
            GOAT={ default={ energyMJ=9, proteinKg=0.18, dmiKg=1.2 } },
            CHICKEN={ default={ energyMJ=0.70, proteinKg=0.03, dmiKg=0.08 } },
            HORSE={ default={ energyMJ=68, proteinKg=0.80, dmiKg=8.0 } },
            DEFAULT={ default={ energyMJ=20, proteinKg=0.30, dmiKg=2.0 } }
        },
        stages = {}
    }
end

local function settingsDirectory()
    local root = getUserProfileAppPath ~= nil and getUserProfileAppPath() or ""
    if root == "" then return nil end
    local modSettings = root .. "modSettings/"
    local directory = modSettings .. "FS25_PrecisionNutrition/"
    if createFolder ~= nil then
        createFolder(modSettings)
        createFolder(directory)
    end
    return directory
end

local function loadFeeds(config, path)
    if fileExists == nil or not fileExists(path) then return end
    local xml = XMLFile.load("pnFeeds", path, "precisionNutrition")
    if xml == nil then PN_Log.warning("Unable to read %s", path); return end
    local i, count = 0, 0
    while xml:hasProperty(string.format("precisionNutrition.feedMatrix.feed(%d)", i)) do
        local key = string.format("precisionNutrition.feedMatrix.feed(%d)", i)
        local name = upper(xml:getString(key .. "#name"))
        if name ~= "" then
            config.feedMatrix[name] = {
                dm=math.clamp(numberOr(xml:getFloat(key .. "#dm"), 1), 0, 1),
                energyMJ=math.max(numberOr(xml:getFloat(key .. "#energyMJ"), 0), 0),
                proteinKg=math.max(numberOr(xml:getFloat(key .. "#proteinKg"), 0), 0)
            }
            count = count + 1
        end
        i = i + 1
    end
    i = 0
    while xml:hasProperty(string.format("precisionNutrition.feedAliases.alias(%d)", i)) do
        local key = string.format("precisionNutrition.feedAliases.alias(%d)", i)
        local from, to = upper(xml:getString(key .. "#from")), upper(xml:getString(key .. "#to"))
        if from ~= "" and to ~= "" then config.feedAliases[from] = to end
        i = i + 1
    end
    xml:delete()
    PN_Log.info("Loaded %d custom feeds from %s", count, path)
end

local function loadTargets(config, path)
    if fileExists == nil or not fileExists(path) then return end
    local xml = XMLFile.load("pnTargets", path, "precisionNutrition")
    if xml == nil then PN_Log.warning("Unable to read %s", path); return end
    local i, count = 0, 0
    while xml:hasProperty(string.format("precisionNutrition.targets(%d)", i)) do
        local key = string.format("precisionNutrition.targets(%d)", i)
        local species = upper(xml:getString(key .. "#species"))
        local stage = upper(xml:getString(key .. "#stage"))
        if stage == "" or stage == "DEFAULT" then stage = "default" end
        if species ~= "" then
            config.targets[species] = config.targets[species] or {}
            local fallback = config.targets[species].default or config.targets.DEFAULT.default
            config.targets[species][stage] = {
                energyMJ=math.max(numberOr(xml:getFloat(key .. "#energyMJ"), fallback.energyMJ), 0.001),
                proteinKg=math.max(numberOr(xml:getFloat(key .. "#proteinKg"), fallback.proteinKg), 0.001),
                dmiKg=math.max(numberOr(xml:getFloat(key .. "#dmiKg"), fallback.dmiKg), 0.001)
            }
            count = count + 1
        end
        i = i + 1
    end
    xml:delete()
    PN_Log.info("Loaded %d custom nutrition targets from %s", count, path)
end

local function loadStages(config, path)
    if fileExists == nil or not fileExists(path) then return end
    local xml = XMLFile.load("pnStages", path, "precisionNutrition")
    if xml == nil then PN_Log.warning("Unable to read %s", path); return end
    local i, speciesCount = 0, 0
    while xml:hasProperty(string.format("precisionNutrition.stages(%d)", i)) do
        local root = string.format("precisionNutrition.stages(%d)", i)
        local species = upper(xml:getString(root .. "#species"))
        local bands, j = {}, 0
        while xml:hasProperty(string.format("%s.band(%d)", root, j)) do
            local key = string.format("%s.band(%d)", root, j)
            local gender = tostring(xml:getString(key .. "#gender") or ""):lower()
            if gender ~= "male" and gender ~= "female" then gender = nil end
            local function optionalBool(attribute)
                local path = key .. "#" .. attribute
                return xml:hasProperty(path) and xml:getBool(path) or nil
            end
            table.insert(bands, {
                name=upper(xml:getString(key .. "#name")), gender=gender,
                minAgeM=numberOr(xml:getFloat(key .. "#minAgeM"), 0),
                maxAgeM=numberOr(xml:getFloat(key .. "#maxAgeM"), 100000),
                lactating=optionalBool("lactating"), pregnant=optionalBool("pregnant"),
                castrated=optionalBool("castrated")
            })
            j = j + 1
        end
        if species ~= "" and #bands > 0 then config.stages[species] = bands; speciesCount = speciesCount + 1 end
        i = i + 1
    end
    xml:delete()
    PN_Log.info("Loaded custom stage bands for %d species from %s", speciesCount, path)
end

function PN_Settings.load(force)
    if PN_Settings.config ~= nil and not force then return PN_Settings.config end
    local config = defaults()
    local directory = settingsDirectory()
    if directory ~= nil then
        loadFeeds(config, directory .. "feeds.xml")
        loadTargets(config, directory .. "targets.xml")
        loadStages(config, directory .. "stages.xml")
    end
    PN_Settings.config = config
    return config
end

function PN_Settings.reload()
    return PN_Settings.load(true)
end

return PN_Settings
