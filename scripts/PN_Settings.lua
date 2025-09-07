-- FS25_PrecisionNutrition / scripts / PN_Settings.lua
-- UI / overlay knobs
PN_Settings = PN_Settings or {}
PN_Settings.ui = PN_Settings.ui or {
  overlayRefreshMs = 1000,   -- throttle snapshot refresh; set 0 to refresh every frame
  addSpacerBetweenBarns = true,
}

-- ADG knobs
PN_Settings.adg = PN_Settings.adg or {
  useSupplyFactor = true,     -- turn supply sensitivity on/off globally
}

PN_Settings.adg = PN_Settings.adg or {}
PN_Settings.adg.allowNegative = true          -- default false
PN_Settings.adg.starvationPenaltyKg = 0.05    -- max extra loss at 100% shortage (kg/d)And for a 

-- ---------- small utils ----------
local function _u(s) return tostring(s or ""):upper() end
local function _n(v, d) v = tonumber(v); if v == nil then return d end; return v end

local function ensureDir(path)
    if createFolder ~= nil then createFolder(path) end
end

-- Fixed external base dir:
local function _extBaseDir()
    local base = (getUserProfileAppPath and getUserProfileAppPath()) or ""
    if base == "" then return "" end
    local modRoot = base .. "modSettings/"
    local dir = modRoot .. "FS25_PrecisionNutrition"
    ensureDir(modRoot)
    ensureDir(dir)
    return dir
end

-- ---------- BASE CONFIG (defaults) ----------
local function baseConfig()
    return {
        -- species meta
        meta = {
            COW     = {
        matureKg   = 650,
        matureAgeM = 24,
        overageM   = 25,
        sale = {
            overagePenaltyPerMonth = 0.03,
            overagePenaltyFloor    = 0.80,
        }
    },
            SHEEP   = { matureKg = 75,  matureAgeM = 12 },
            PIG     = { matureKg = 120, matureAgeM = 8  },
            GOAT    = { matureKg = 65,  matureAgeM = 12 },
            CHICKEN = { matureKg = 3,   matureAgeM = 5  },
        },

        -- Option A: stage bands (gender-aware) — defaults (override via stages.xml)
        stages = {
			COW = {
				-- Unsexed / shared
				{ name="CALF",   minAgeM=0,  maxAgeM=8,   baseADG=0.90 },   -- typical pre-wean ADG ~0.7–1.2

				-- Females
				{ name="HEIFER", gender="female", minAgeM=8,  maxAgeM=15,  baseADG=0.75 },  -- replacement target ~0.6–0.9
				{ name="LACT",   gender="female", minAgeM=15, maxAgeM=120, baseADG=0.15 },  -- can be 0 to slight loss; use 0.15 baseline
				{ name="DRY",    gender="female", minAgeM=15, maxAgeM=120, baseADG=0.35 },  -- rebuilding BCS pre-calving

				-- Males
				{ name="YEARLING", gender="male", minAgeM=8,  maxAgeM=18,  baseADG=1.10 },  -- intact/steer growth 0.9–1.3 typical
				{ name="STEER",    gender="male", minAgeM=18, maxAgeM=24,  baseADG=1.25 },  -- finishing (pasture/feedlot mix) 1.0–1.5
				{ name="BULL",     gender="male", minAgeM=18, maxAgeM=120, baseADG=0.45 },  -- 18–30m ~0.6, mature settles ~0.3–0.4

				-- Fallbacks
				default_female = { name="DEFAULT_F", minAgeM=0, maxAgeM=1e9, baseADG=0.25, gender="female" },
				default_male   = { name="DEFAULT_M", minAgeM=0, maxAgeM=1e9, baseADG=0.45, gender="male"   },
				default        = { name="DEFAULT",   minAgeM=0, maxAgeM=1e9, baseADG=0.25 },
			},
			
			SHEEP = {
			  -- Species meta
			  matureKg    = 80,    -- UI/economy cap; keep rams sensible in menus
			  matureAgeM  = 12,    -- functional maturity for most systems

			  -- Shared early growth
			  { name="LAMB",         minAgeM=0,  maxAgeM=4,  baseADG=0.28 },  -- ♂ & ♀
			  { name="WEANER",       minAgeM=4,  maxAgeM=8,  baseADG=0.22 },  -- ♂ & ♀

			  -- Females
			  { name="YEARLING",     gender="female", minAgeM=8,  maxAgeM=12, baseADG=0.12 },
			  { name="EWE_LACT",     gender="female", minAgeM=12, maxAgeM=240, baseADG=0.05 },
			  { name="EWE_DRY",      gender="female", minAgeM=12, maxAgeM=240, baseADG=0.10 },

			  -- Males
			  { name="YEARLING",     gender="male",   minAgeM=8,  maxAgeM=12, baseADG=0.12 }, -- ram lamb/yearling
			  { name="WETHER_FINISH",gender="male",   minAgeM=6,  maxAgeM=10, baseADG=0.30 }, -- finishing window for castrated males
			  { name="RAM",          gender="male",   minAgeM=12, maxAgeM=240, baseADG=0.08 },

			  -- Fallbacks
			  default_female = { name="DEFAULT_F", minAgeM=0, maxAgeM=1e9, baseADG=0.08, gender="female" },
			  default_male   = { name="DEFAULT_M", minAgeM=0, maxAgeM=1e9, baseADG=0.10, gender="male"   },
			  default        = { name="DEFAULT",   minAgeM=0, maxAgeM=1e9, baseADG=0.08 },
			},
			PIG = {
			  -- Species meta
			  matureKg    = 300,   -- UI/economy cap for sows/boars
			  matureAgeM  = 10,    -- functional maturity
			  
			  -- Shared early growth
			  { name="PIGLET",  minAgeM=0,  maxAgeM=2, baseADG=0.30 },  -- 1–20 kg
			  { name="WEANER",  minAgeM=2,  maxAgeM=4, baseADG=0.55 },  -- 20–60 kg
			  { name="GROWER",  minAgeM=4,  maxAgeM=6, baseADG=0.70 },  -- 60–100 kg
			  
			  -- Slaughter finishers
			  { name="BARROW", 	 gender="male",   minAgeM=6, maxAgeM=8, baseADG=0.80 }, -- barrows
			  { name="GILT", 	 gender="female", minAgeM=6, maxAgeM=8, baseADG=0.80 }, -- gilts
			  
			  -- Breeding stock
			  { name="SOW_LACT", gender="female", minAgeM=8, maxAgeM=120, baseADG=0.15 },
			  { name="SOW_DRY",  gender="female", minAgeM=8, maxAgeM=120, baseADG=0.25 },
			  { name="BOAR",     gender="male",   minAgeM=8, maxAgeM=120, baseADG=0.20 },
			  
			  -- Fallbacks
			  default_female = { name="DEFAULT_F", minAgeM=0, maxAgeM=1e9, baseADG=0.25, gender="female" },
			  default_male   = { name="DEFAULT_M", minAgeM=0, maxAgeM=1e9, baseADG=0.25, gender="male"   },
			  default        = { name="DEFAULT",   minAgeM=0, maxAgeM=1e9, baseADG=0.25 },
			},
			GOAT = {
			  -- Species meta
			  matureKg    = 80,     -- UI/economy cap
			  matureAgeM  = 12,     -- functional maturity

			  -- Shared early growth
			  { name="KID",           minAgeM=0,  maxAgeM=4,  baseADG=0.22 },  -- ♂ & ♀
			  { name="WEANER",        minAgeM=4,  maxAgeM=8,  baseADG=0.18 },  -- ♂ & ♀
			  { name="YEARLING",      minAgeM=8,  maxAgeM=12, baseADG=0.10 },  -- ♂ & ♀

			  -- Females
			  { name="DOE_LACT",      gender="female", minAgeM=12, maxAgeM=240, baseADG=0.04 },
			  { name="DOE_DRY",       gender="female", minAgeM=12, maxAgeM=240, baseADG=0.08 },

			  -- Males
			  { name="WETHER_FINISH", gender="male",   minAgeM=6,  maxAgeM=10,  baseADG=0.25 }, -- castrated finish window
			  { name="BUCK",          gender="male",   minAgeM=12, maxAgeM=240, baseADG=0.07 },

			  -- Fallbacks
			  default_female = { name="DEFAULT_F", minAgeM=0, maxAgeM=1e9, baseADG=0.08, gender="female" },
			  default_male   = { name="DEFAULT_M", minAgeM=0, maxAgeM=1e9, baseADG=0.10, gender="male"   },
			  default        = { name="DEFAULT",   minAgeM=0, maxAgeM=1e9, baseADG=0.08 },
			},
			CHICKEN = {
			  -- Species meta
			  matureKg    = 3.0,   -- UI/economy cap
			  matureAgeM  = 6,     -- functional maturity (layers start laying ~20–24 wks)

			  -- Shared early growth
			  { name="CHICK",          minAgeM=0,  maxAgeM=1, baseADG=0.02 }, -- 40–200 g
			  { name="GROWER",         minAgeM=1,  maxAgeM=4, baseADG=0.04 }, -- 200 g–1.5 kg

			  -- Broiler meat birds
			  { name="BROILER_FINISH", minAgeM=2,  maxAgeM=3, baseADG=0.06 }, -- 2–3 kg finish window

			  -- Layers
			  { name="PULLET",   gender="female", minAgeM=4, maxAgeM=6,   baseADG=0.03 },
			  { name="HEN_LAY",  gender="female", minAgeM=6, maxAgeM=120, baseADG=0.01 },

			  -- Roosters
			  { name="ROOSTER",  gender="male",   minAgeM=6, maxAgeM=120, baseADG=0.015 },

			  -- Fallbacks
			  default_female = { name="DEFAULT_F", minAgeM=0, maxAgeM=1e9, baseADG=0.01, gender="female" },
			  default_male   = { name="DEFAULT_M", minAgeM=0, maxAgeM=1e9, baseADG=0.015, gender="male" },
			  default        = { name="DEFAULT",   minAgeM=0, maxAgeM=1e9, baseADG=0.01 },
			},
        },

        -- daily nutrition targets (defaults; override via targets.xml)
        targets = {
            COW     = { default = { energyMJ = 100, proteinKg = 1.8,  dmiKg = 14  } },
            SHEEP   = { default = { energyMJ =  12, proteinKg = 0.22, dmiKg = 1.3 } },
            PIG     = { default = { energyMJ =  40, proteinKg = 0.55, dmiKg = 2.5 } },
            GOAT    = { default = { energyMJ =  11, proteinKg = 0.20, dmiKg = 1.2 } },
            CHICKEN = { default = { energyMJ = 1.6, proteinKg = 0.04, dmiKg = 0.13 } },
            DEFAULT = { default = { energyMJ =  20, proteinKg = 0.30, dmiKg = 2.0 } },
        },

        -- feed matrix (per kg as-fed) — base-game friendly defaults
        feedMatrix = {
            -- ruminant forages
            GRASS_WINDROW = { dm = 0.30, energyMJ = 6.0,  proteinKg = 0.12 },
            HAY           = { dm = 0.85, energyMJ = 7.5,  proteinKg = 0.14 },
            SILAGE        = { dm = 0.35, energyMJ = 6.5,  proteinKg = 0.10 },
            TMR           = { dm = 0.60, energyMJ = 7.2,  proteinKg = 0.14 },

            -- grains
            WHEAT         = { dm = 0.86, energyMJ = 6.8,  proteinKg = 0.12 },
            BARLEY        = { dm = 0.86, energyMJ = 6.6,  proteinKg = 0.11 },
            OAT           = { dm = 0.86, energyMJ = 6.3,  proteinKg = 0.11 },
            MAIZE         = { dm = 0.86, energyMJ = 7.8,  proteinKg = 0.09 },
            SORGHUM       = { dm = 0.86, energyMJ = 7.2,  proteinKg = 0.11 },

            -- roots
            POTATO        = { dm = 0.25, energyMJ = 3.5,  proteinKg = 0.02 },
            SUGARBEET     = { dm = 0.23, energyMJ = 3.3,  proteinKg = 0.01 },

            -- pulses / protein
            PEA           = { dm = 0.88, energyMJ = 6.8,  proteinKg = 0.24 },

            -- compounds
            PIG_FEED      = { dm = 0.90, energyMJ = 9.0,  proteinKg = 0.20 },
            CHICKEN_FEED  = { dm = 0.90, energyMJ = 7.5,  proteinKg = 0.17 },
			MINERAL       = { dm = 0.0, energyMJ = 0.0, proteinKg = 0.0 }
        },

        -- aliases (map many names → one feed)
        feedAliases = {
            -- grass forms
			DRYGRASS_WINDROW = "HAY",
			DRY_GRASS_WINDROW = "HAY",
			WINDROW_DRYGRASS = "HAY",
			WINDROW_HAY	     = "HAY",
            DRYGRASS         = "HAY",
            DRY_GRASS        = "HAY",
			LUCERNE_HAY      = "HAY",     -- some EU maps use "lucerne" for alfalfa
            CUT_GRASS        = "GRASS_WINDROW",
            CUTGRASS         = "GRASS_WINDROW",
            FRESH_GRASS      = "GRASS_WINDROW",
            FRESHGRASS       = "GRASS_WINDROW",
            GRASS            = "GRASS_WINDROW",
            GRASS_WET        = "GRASS_WINDROW",
            WETGRASS_WINDROW = "GRASS_WINDROW",

            -- heap “forage” → treat as TMR so dynamic food planes work
            FORAGE           = "TMR",
            FORAGE_MIXING    = "TMR",
            FORAGE_MIXER     = "TMR",

            -- pellets / variants
            HAY_PELLETS      = "HAY",
			GRASS_PELLETS    = "HAY",     -- treat as “dry forage” unless you have a separate token

            -- compound
            PIGFOOD          = "PIG_FEED",
			MINERAL_FEED     = "MINERAL",

            -- optional chaff mapping (uncomment if used by your map)
            CHAFF          = "SILAGE",
            MAIZE_CHAFF    = "SILAGE",
            SORGHUM_CHAFF  = "SILAGE",
			MAIZE_WHOLEPLANT    = "SILAGE",  -- some maps export this name
        },
    }
end

-- ---------- XML loaders (feeds / targets / stages) ----------
local function loadFeedsXml(cfg, path)
    if not (fileExists and fileExists(path)) then
        Logging.info("[PN] Settings: no feeds.xml found at %s", path)
        return
    end
    local xml = XMLFile.load("pnFeeds", path, "precisionNutrition")
    if not xml then
        Logging.info("[PN] Settings: could not open %s", path); return
    end
    local addedFeeds, addedAliases = 0, 0

    if xml:hasProperty("precisionNutrition.feedMatrix") then
        local i = 0
        while true do
            local key = string.format("precisionNutrition.feedMatrix.feed(%d)", i)
            if not xml:hasProperty(key) then break end
            local name = _u(xml:getString(key .. "#name"))
            if name ~= "" then
                local dm  = _n(xml:getFloat(key .. "#dm"), 1.0)
                local emj = _n(xml:getFloat(key .. "#energyMJ"), 0.0)
                local pk  = _n(xml:getFloat(key .. "#proteinKg"), 0.0)
                cfg.feedMatrix[name] = { dm = dm, energyMJ = emj, proteinKg = pk }
                addedFeeds = addedFeeds + 1
            end
            i = i + 1
        end
    end

    if xml:hasProperty("precisionNutrition.feedAliases") then
        local i = 0
        while true do
            local key = string.format("precisionNutrition.feedAliases.alias(%d)", i)
            if not xml:hasProperty(key) then break end
            local from = _u(xml:getString(key .. "#from"))
            local to   = _u(xml:getString(key .. "#to"))
            if from ~= "" and to ~= "" then
                cfg.feedAliases[from] = to
                addedAliases = addedAliases + 1
            end
            i = i + 1
        end
    end

    xml:delete()
    Logging.info("[PN] Settings: loaded %s (+%d feeds, +%d aliases)", path, addedFeeds, addedAliases)
end

local function loadTargetsXml(cfg, path)
    if not (fileExists and fileExists(path)) then
        Logging.info("[PN] Settings: no targets.xml found at %s", path)
        return
    end
    local xml = XMLFile.load("pnTargets", path, "precisionNutrition")
    if not xml then
        Logging.info("[PN] Settings: could not open %s", path); return
    end
    local changed = 0
    local i = 0
    while true do
        local key = string.format("precisionNutrition.targets(%d)", i)
        if not xml:hasProperty(key) then break end
        local species = _u(xml:getString(key .. "#species"))
        local stage   = _u(xml:getString(key .. "#stage"))
        local emj     = xml:getFloat(key .. "#energyMJ")
        local pk      = xml:getFloat(key .. "#proteinKg")
        local dmi     = xml:getFloat(key .. "#dmiKg")
        if species ~= "" then
            cfg.targets[species] = cfg.targets[species] or {}
            local stageKey = (stage == "" and "default" or stage)
            cfg.targets[species][stageKey] = {
                energyMJ  = _n(emj, (cfg.targets[species].default or {}).energyMJ or 0),
                proteinKg = _n(pk,  (cfg.targets[species].default or {}).proteinKg or 0),
                dmiKg     = _n(dmi, (cfg.targets[species].default or {}).dmiKg or 0),
            }
            changed = changed + 1
        end
        i = i + 1
    end
    xml:delete()
    Logging.info("[PN] Settings: loaded %s (+%d targets)", path, changed)
end

local function loadStagesXml(cfg, path)
    if not (fileExists and fileExists(path)) then
        Logging.info("[PN] Settings: no stages.xml found at %s", path)
        return
    end
    local xml = XMLFile.load("pnStages", path, "precisionNutrition")
    if not xml then
        Logging.info("[PN] Settings: could not open %s", path); return
    end
    local replaced = 0
    local i = 0
    while true do
        local root = string.format("precisionNutrition.stages(%d)", i)
        if not xml:hasProperty(root) then break end

        local species = _u(xml:getString(root .. "#species"))
        if species ~= "" then
            cfg.stages[species] = cfg.stages[species] or {}
            local dst = { }

            -- bands
            local j = 0
            while true do
                local key = string.format("%s.band(%d)", root, j)
                if not xml:hasProperty(key) then break end
                local band = {
                    name    = _u(xml:getString(key .. "#name")),
                    gender  = (function ()
                        local g = xml:getString(key .. "#gender") or ""
                        g = g:lower()
                        if g == "male" or g == "female" then return g end
                        return nil
                    end)(),
                    minAgeM = _n(xml:getFloat(key .. "#minAgeM"), 0),
                    maxAgeM = _n(xml:getFloat(key .. "#maxAgeM"), 1e9),
                    baseADG = _n(xml:getFloat(key .. "#baseADG"), 0.0),
                }
                table.insert(dst, band)
                j = j + 1
            end

            -- defaults (optional)
            local function readDef(node, g)
                if xml:hasProperty(node) then
                    return {
                        name    = _u(xml:getString(node .. "#name")),
                        minAgeM = _n(xml:getFloat(node .. "#minAgeM"), 0),
                        maxAgeM = _n(xml:getFloat(node .. "#maxAgeM"), 1e9),
                        baseADG = _n(xml:getFloat(node .. "#baseADG"), 0.0),
                        gender  = g,
                    }
                end
                return nil
            end
            local df  = readDef(root .. ".default(0)", nil)
            local dff = readDef(root .. ".defaultFemale(0)", "female")
            local dfm = readDef(root .. ".defaultMale(0)",   "male")

            if df  then dst.default        = df  end
            if dff then dst.default_female = dff end
            if dfm then dst.default_male   = dfm end

            cfg.stages[species] = dst
            replaced = replaced + 1
        end

        i = i + 1
    end
    xml:delete()
    Logging.info("[PN] Settings: loaded %s (replaced %d species stages)", path, replaced)
end

-- Generic pack merger (optional *.xml files besides the big three)
local function mergeAnyXmlPacks(cfg, dir)
    local files = {}
    if listFiles ~= nil then
        files = listFiles(dir, "*.xml", false, false) or {}
    end
    for _, path in ipairs(files) do
        local pU = path:upper()
        if pU:find("FEEDS.XML", 1, true) or pU:find("TARGETS.XML", 1, true) or pU:find("STAGES.XML", 1, true) then
            -- handled explicitly below
        else
            -- Treat like a combined pack: feedMatrix, feedAliases, targets
            local xml = XMLFile.load("pnPack", path, "precisionNutrition")
            if xml then
                local addedFeeds, addedAliases, changedTargets = 0, 0, 0

                if xml:hasProperty("precisionNutrition.feedMatrix") then
                    local i = 0
                    while true do
                        local key = string.format("precisionNutrition.feedMatrix.feed(%d)", i)
                        if not xml:hasProperty(key) then break end
                        local name = _u(xml:getString(key .. "#name"))
                        if name ~= "" then
                            local dm  = _n(xml:getFloat(key .. "#dm"), 1.0)
                            local emj = _n(xml:getFloat(key .. "#energyMJ"), 0.0)
                            local pk  = _n(xml:getFloat(key .. "#proteinKg"), 0.0)
                            cfg.feedMatrix[name] = { dm = dm, energyMJ = emj, proteinKg = pk }
                            addedFeeds = addedFeeds + 1
                        end
                        i = i + 1
                    end
                end

                if xml:hasProperty("precisionNutrition.feedAliases") then
                    local i = 0
                    while true do
                        local key = string.format("precisionNutrition.feedAliases.alias(%d)", i)
                        if not xml:hasProperty(key) then break end
                        local from = _u(xml:getString(key .. "#from"))
                        local to   = _u(xml:getString(key .. "#to"))
                        if from ~= "" and to ~= "" then
                            cfg.feedAliases[from] = to
                            addedAliases = addedAliases + 1
                        end
                        i = i + 1
                    end
                end

                local i = 0
                while true do
                    local key = string.format("precisionNutrition.targets(%d)", i)
                    if not xml:hasProperty(key) then break end
                    local species = _u(xml:getString(key .. "#species"))
                    local stage   = _u(xml:getString(key .. "#stage"))
                    local emj     = xml:getFloat(key .. "#energyMJ")
                    local pk      = xml:getFloat(key .. "#proteinKg")
                    local dmi     = xml:getFloat(key .. "#dmiKg")
                    if species ~= "" then
                        cfg.targets[species] = cfg.targets[species] or {}
                        local stageKey = (stage == "" and "default" or stage)
                        cfg.targets[species][stageKey] = {
                            energyMJ  = _n(emj, (cfg.targets[species].default or {}).energyMJ or 0),
                            proteinKg = _n(pk,  (cfg.targets[species].default or {}).proteinKg or 0),
                            dmiKg     = _n(dmi, (cfg.targets[species].default or {}).dmiKg or 0),
                        }
                        changedTargets = changedTargets + 1
                    end
                    i = i + 1
                end

                xml:delete()
                Logging.info("[PN] Settings: loaded %s (+%d feeds, +%d aliases, +%d targets)", path, addedFeeds, addedAliases, changedTargets)
            end
        end
    end
end

-- ---------- PUBLIC ----------
function PN_Settings.load()
    local cfg = baseConfig()

    local dir = _extBaseDir()
    if dir == "" then
        Logging.info("[PN] Settings: no user profile dir; using built-in defaults only.")
        return cfg
    end

    -- Explicit individual files (nice for users)
    loadFeedsXml(cfg,   dir .. "/feeds.xml")
    loadTargetsXml(cfg, dir .. "/targets.xml")
    loadStagesXml(cfg,  dir .. "/stages.xml")

    -- Any other *.xml packs in the folder (optional)
    mergeAnyXmlPacks(cfg, dir)

    return cfg
end

return PN_Settings
