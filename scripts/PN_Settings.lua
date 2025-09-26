-- FS25_PrecisionNutrition / scripts / PN_Settings.lua
-- UI / overlay knobs
PN_Settings = PN_Settings or {}
PN = PN or {}   -- ensure global PN table exists before we populate PN.tuning

PN_Settings.debug = PN_Settings.debug or { saleAdjust = true }  -- log PN deltas so you can verify
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
PN_Settings.adg.starvationPenaltyKg = 0.05    -- max extra loss at 100% shortage (kg/d)

PN_Settings.debug = PN_Settings.debug or { saleAdjust = true }  -- log PN deltas so you can verify

-- ===== PN Tuning (Alpha) =====
-- These are intentionally conservative to avoid balance shock.
PN.tuning = PN.tuning or {
    -- ADG scaling around nutrition quality (Nut in 0..1)
    -- Piecewise curve: ~0.2x at Nut=0, ~0.8x at Nut=0.5, up to (1+adgMaxBoost)x at Nut=1
    adgMaxBoost = 0.20,           -- 1.20x at Nut = 1.00
    adgMinFactorAtZero = 0.20,    -- 0.20x at Nut = 0.00
    adgFactorAtHalf = 0.80,       -- 0.80x at Nut = 0.50

    -- Slow “condition” drift to reward good long-term feeding
    conditionDriftPerHr = 0.001,  -- +/- 0.001 per hour when Nut > 0.9 or Nut < 0.6
    conditionMin = 0.50,          -- clamp range (alpha safety)
    conditionMax = 1.00,

    -- Optional milk responsiveness (only applied if a husbandry is milking-enabled)
    milkBoostMax = 0.30,          -- +30% at Nut = 1.00 → 1.30x max (clamped)
    milkBoostClamp = 1.20,        -- clamp milk at 1.20x max in alpha (safer)
}

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
        grazingFeeder = {
            enabled           = true,
            outputFillType    = "GRASS_WINDROW",
            harvestChunkL     = 1500,
            harvestMaxPerDayL = 15000,
            dripBootstrapPct  = 0.25,
            dripCeilPct       = 0.85,
            dripLph           = 1200,
            minTroughLowPct   = 0.05,
            safeFarmOnly      = true,
        },

        -- species meta
		meta = {
		  COW = {
			matureKg   = 650,
			matureAgeM = 24,
			overageSnr = 60,
			overageM   = 26,
			sale = { overagePenaltyPerMonth = 0.03, overagePenaltyFloor = 0.80 },
		  },

		  -- 👇 peer to COW, not nested
		  SHEEP = {
			matureKg   = 75,
			matureAgeM = 12,
			overageSnr = 60,  -- ewes: senior line
			overageM   = 18,  -- wethers: finish window end
			sale = { overagePenaltyPerMonth = 0.04, overagePenaltyFloor = 0.70 },
		  },
		  
		  PIG = {
			  matureKg   = 120,  -- keep your existing value
			  matureAgeM = 8,    -- boar/sow “adult” threshold you noted
			  overageSnr = 48,   -- sows ≥48 m: senior taper (ADG + price haircut)
			  overageM   = 10,   -- barrows ≥10 m: past optimal finish → taper + haircut
			  sale = {
				overagePenaltyPerMonth = 0.05, -- slightly steeper than sheep/cattle
				overagePenaltyFloor    = 0.65, -- don’t drop below 65% of base price
			  },
			},
		  GOAT = {
			  matureKg   = 65,
			  matureAgeM = 12,
			  overageSnr = 72,   -- does ~6y: senior taper later (for when you enable overage math)
			  overageM   = 18,   -- wethers past finish window
			  sale = {
				overagePenaltyPerMonth = 0.04,
				overagePenaltyFloor    = 0.70,
			  },
			},
		  CHICKEN = {
			  matureKg   = 3,
			  matureAgeM = 5,
			  overageSnr = 30,  -- hens ~2.5y for later price/ADG taper (optional)
			  overageM   = 0,   -- not used; kept for structural parity
			  sale = {
				overagePenaltyPerMonth = 0.05,
				overagePenaltyFloor    = 0.60,
			  },
			},
			HORSE = {
				matureKg   = 500,  -- avg riding horse
				matureAgeM = 36,   -- adult reference (♂ fertility 36m; ♀ handled by stages)
				overageSnr = 144,  -- ~12 years: senior taper for mares/stallions
				overageM   = 96,   -- ~8 years: gelding “post-prime” taper (keeps parity with other species)
				sale = {
					overagePenaltyPerMonth = 0.015, -- slow monthly haircut; horses hold value longer
					overagePenaltyFloor    = 0.55,  -- don’t drop below 55% of base price
				},
			},
		},

        -- Option A: stage bands (gender-aware) — defaults (override via stages.xml)
        stages = {
			COW = {
				-- Unsexed / shared
				{ name="CALF",   minAgeM=0,  maxAgeM=5,   baseADG=0.85 },   -- typical pre-wean ADG ~0.7–1.2

				-- Females
				{ name="HEIFER", gender="female", minAgeM=6,  maxAgeM=17,  baseADG=0.70 },  -- replacement target ~0.6–0.9
				{ name="COW_DRY",    gender="female", minAgeM=18, maxAgeM=120, baseADG=0.30 },  -- rebuilding BCS pre-calving
				{ name="COW_LACT",   gender="female", minAgeM=14, maxAgeM=120, baseADG=0.12 },  -- can be 0 to slight loss; use 0.15 baseline | At 14 months, HEIFERS will be exposed to the bull and may be impregnated

				-- Males
				{ name="YEARLING", gender="male", minAgeM=6,  maxAgeM=17,  baseADG=1.00 },  -- intact/steer growth 0.9–1.3 typical
				{ name="STEER_FINISH",    gender="male", minAgeM=18, maxAgeM=24,  baseADG=0.95 },  -- finishing (pasture/feedlot mix)
				{ name="BULL",     gender="male", minAgeM=18, maxAgeM=120, baseADG=0.40 },  -- 18–30m ~0.6, mature settles ~0.3–0.4

				-- Fallbacks
				default_female = { name="DEFAULT_F", minAgeM=0, maxAgeM=1e9, baseADG=0.25, gender="female" },
				default_male   = { name="DEFAULT_M", minAgeM=0, maxAgeM=1e9, baseADG=0.45, gender="male"   },
				default        = { name="DEFAULT",   minAgeM=0, maxAgeM=1e9, baseADG=0.25 },
			},
			
			SHEEP = {
				-- Unsexed / shared
				{ name="LAMB",           minAgeM=0,  maxAgeM=4,                   baseADG=0.25 },

				-- Adult females (status-driven)
				{ name="GROWER",     gender="female", minAgeM=5,  maxAgeM=7,  baseADG=0.25 },
				{ name="EWE_DRY",        gender="female", minAgeM=8, maxAgeM=120, baseADG=0.15 }, -- not lactating
				{ name="EWE_LACT",       gender="female", minAgeM=8, maxAgeM=120, baseADG=0.10 }, -- post-lambing

				-- Adult males
				{ name="WETHER_FINISH",  gender="male",   minAgeM=3,  maxAgeM=18,  baseADG=0.30 }, -- castrated finish lane
				{ name="RAM",      		 gender="male",   minAgeM=5, maxAgeM=120, baseADG=0.25 }, -- intact adult
				{ name="RAM_ADULT",      gender="male",   minAgeM=8, maxAgeM=120, baseADG=0.20 }, -- intact adult

				-- Fallbacks (keep format identical to COW)
				default_female = { name="DEFAULT_F", minAgeM=0, maxAgeM=1e9, baseADG=0.15, gender="female" },
				default_male   = { name="DEFAULT_M", minAgeM=0, maxAgeM=1e9, baseADG=0.18, gender="male"   },
				default        = { name="DEFAULT",   minAgeM=0, maxAgeM=1e9, baseADG=0.15 },
			},

			PIG = {	  
				  -- Unsexed / shared
				  { name="PIGLET", minAgeM=0,  maxAgeM=5,   baseADG=0.45 },

--				  { name="WEANER", minAgeM=2,  maxAgeM=5,   baseADG=0.65 },
--				  { name="GROWER", minAgeM=4,  maxAgeM=5,   baseADG=0.80 },

				  -- Females
				  { name="GILT",      gender="female", minAgeM=6,  maxAgeM=7,   baseADG=0.70 }, -- fertile window pre-1st service
--				  { name="SOW_GEST",  gender="female", minAgeM=8,  maxAgeM=120, baseADG=0.15 }, -- pregnant
				  { name="SOW_DRY",   gender="female", minAgeM=8,  maxAgeM=120, baseADG=0.25 }, -- open/non-lactating adult
				  { name="SOW_LACT",  gender="female", minAgeM=8,  maxAgeM=120, baseADG=0.05 }, -- lactating (maint./slight loss)


				  -- Males
				  { name="BARROW_FINISH", gender="male", minAgeM=6,  maxAgeM=10,  baseADG=0.95 }, -- castrated finish lane
				  { name="BOAR",    gender="male", minAgeM=6,  maxAgeM=7, baseADG=0.35 }, -- intact adult
				  { name="BOAR_ADULT",    gender="male", minAgeM=8,  maxAgeM=120, baseADG=0.30 }, -- intact adult

				  -- Fallbacks
				  default_female = { name="DEFAULT_F", minAgeM=0, maxAgeM=1e9, baseADG=0.20, gender="female" },
				  default_male   = { name="DEFAULT_M", minAgeM=0, maxAgeM=1e9, baseADG=0.40, gender="male"   },
				  default        = { name="DEFAULT",   minAgeM=0, maxAgeM=1e9, baseADG=0.20 },
			},

			GOAT = {
				-- Unsexed / shared
				{ name="KID",           minAgeM=0,  maxAgeM=4,                   baseADG=0.20 },

				-- Adult females (status-driven)
				{ name="GROWER",     	 gender="female", minAgeM=5,  maxAgeM=7,  baseADG=0.20 },
				{ name="DOE_DRY",        gender="female", minAgeM=8, maxAgeM=120, baseADG=0.12 }, -- not lactating
				{ name="DOE_LACT",       gender="female", minAgeM=8, maxAgeM=120, baseADG=0.08 }, -- post-lambing

				-- Adult males
				{ name="WETHER_FINISH",  gender="male",   minAgeM=3,  maxAgeM=18,  baseADG=0.25 }, -- castrated finish lane
				{ name="BUCK",           gender="male",   minAgeM=5, maxAgeM=120, baseADG=0.20 }, -- intact adult
				{ name="BUCK_ADULT",     gender="male",   minAgeM=8, maxAgeM=120, baseADG=0.15 }, -- intact adult

				-- Fallbacks (keep format identical to COW)
				default_female = { name="DEFAULT_F", minAgeM=0, maxAgeM=1e9, baseADG=0.15, gender="female" },
				default_male   = { name="DEFAULT_M", minAgeM=0, maxAgeM=1e9, baseADG=0.18, gender="male"   },
				default        = { name="DEFAULT",   minAgeM=0, maxAgeM=1e9, baseADG=0.15 },
			},

			CHICKEN = {
				  -- Unsexed / shared
				  { name="CHICK",  minAgeM=0,   maxAgeM=5,   baseADG=0.025 },
--				  { name="GROWER", minAgeM=3,   maxAgeM=5,   baseADG=0.035 }, -- pullet/cockerel age

				  -- Adult females / males
				  { name="LAYER",   gender="female", minAgeM=6, maxAgeM=120, baseADG=0.005 }, -- maintenance
				  { name="ROOSTER", gender="male",   minAgeM=6, maxAgeM=120, baseADG=0.010 },

				  -- Optional meat lanes (kept simple; remove if not using broilers)
--				  { name="BROILER_F", gender="female", minAgeM=1, maxAgeM=4, baseADG=0.050 },
--				  { name="BROILER_M", gender="male",   minAgeM=1, maxAgeM=4, baseADG=0.060 },

				  -- Fallbacks
				  default_female = { name="DEFAULT_F", minAgeM=0, maxAgeM=1e9, baseADG=0.01, gender="female" },
				  default_male   = { name="DEFAULT_M", minAgeM=0, maxAgeM=1e9, baseADG=0.015, gender="male"   },
				  default        = { name="DEFAULT",   minAgeM=0, maxAgeM=1e9, baseADG=0.01 },
			},

			-- Option A: stage bands (gender-aware) — add this block under stages =
			HORSE = {
			  -- Unsexed / shared
			  { name="FOAL",     minAgeM=0,  maxAgeM=5,   baseADG=0.70 },
			  { name="WEANLING", minAgeM=6,  maxAgeM=11,  baseADG=0.60 },
			  { name="YEARLING", minAgeM=12, maxAgeM=21,  baseADG=0.45 },  -- stops where ♀ fertility begins

			  -- Females (22m+)
			  { name="MARE_DRY",  gender="female", minAgeM=22, maxAgeM=120, baseADG=0.20 }, -- list DRY before LACT
			  { name="MARE_LACT", gender="female", minAgeM=22, maxAgeM=120, baseADG=0.05 },

			  -- Males
			  { name="COLT",         gender="male",   minAgeM=12, maxAgeM=35,  baseADG=0.40 },
			  { name="STALLION",     gender="male",   minAgeM=36, maxAgeM=120, baseADG=0.18 },
			  { name="GELDING",      gender="male",   minAgeM=12, maxAgeM=120, baseADG=0.25 },

			  -- Fallbacks
			  default_female = { name="DEFAULT_F", minAgeM=0, maxAgeM=1e9, baseADG=0.18, gender="female" },
			  default_male   = { name="DEFAULT_M", minAgeM=0, maxAgeM=1e9, baseADG=0.25, gender="male"   },
			  default        = { name="DEFAULT",   minAgeM=0, maxAgeM=1e9, baseADG=0.18 },
			}
        },

        -- daily nutrition targets (defaults; override via targets.xml)
		targets = {
		  -- Daily targets per head (as-fed intake converted in PN via DM); tuned so TMR @ target DMI ≈ 1.0 Nut
		  COW     = { default = { energyMJ = 120, proteinKg = 1.90, dmiKg = 14.0 } },
		  SHEEP   = { default = { energyMJ =   8, proteinKg = 0.20, dmiKg =  1.2 } },
		  PIG     = { default = { energyMJ =  28, proteinKg = 0.45, dmiKg =  2.5 } },
		  GOAT    = { default = { energyMJ =   9, proteinKg = 0.18, dmiKg =  1.2 } },
		  CHICKEN = { default = { energyMJ = 0.70, proteinKg = 0.03, dmiKg = 0.08 } },
		  DEFAULT = { default = { energyMJ =  20, proteinKg = 0.30, dmiKg =  2.0 } },
		},

        -- feed matrix (per kg as-fed) — base-game friendly defaults
		feedMatrix = {
          -- Seasonal pasture (as-fed; ballpark values)
          PASTURE_SPRING = { dm = 0.18, energyMJ = 3.4, proteinKg = 0.050 },
          PASTURE_SUMMER = { dm = 0.22, energyMJ = 3.2, proteinKg = 0.040 },
          PASTURE_AUTUMN = { dm = 0.25, energyMJ = 3.1, proteinKg = 0.035 },
          PASTURE_WINTER = { dm = 0.16, energyMJ = 3.0, proteinKg = 0.030 },

		  -- Ruminant forages (as-fed)
		  GRASS_WINDROW = { dm = 0.30, energyMJ = 3.2, proteinKg = 0.036 },
		  HAY           = { dm = 0.85, energyMJ = 5.2, proteinKg = 0.100 },
		  SILAGE        = { dm = 0.35, energyMJ = 3.8, proteinKg = 0.035 },
		  TMR           = { dm = 0.60, energyMJ = 6.6, proteinKg = 0.084 },

		  -- Grains (as-fed)
		  WHEAT         = { dm = 0.86, energyMJ = 6.7, proteinKg = 0.105 },
		  BARLEY        = { dm = 0.86, energyMJ = 6.5, proteinKg = 0.100 },
		  OAT           = { dm = 0.86, energyMJ = 6.2, proteinKg = 0.105 },
		  MAIZE         = { dm = 0.86, energyMJ = 7.8, proteinKg = 0.075 },
		  SORGHUM       = { dm = 0.86, energyMJ = 7.4, proteinKg = 0.095 },
		  RYE           = { dm = 0.86, energyMJ = 6.6, proteinKg = 0.110 },
		  TRITICALE     = { dm = 0.86, energyMJ = 6.8, proteinKg = 0.115 },

		  -- Roots (as-fed)
		  POTATO        = { dm = 0.25, energyMJ = 3.5, proteinKg = 0.020 },
		  SUGARBEET     = { dm = 0.23, energyMJ = 3.3, proteinKg = 0.010 },

		  -- Pulses / protein (as-fed)
		  PEA           = { dm = 0.88, energyMJ = 6.7, proteinKg = 0.210 },
		  -- If you use others (e.g., LENTILS/CHICKPEAS) add them here or leave to feeds.xml

		  -- Compounds / species mixes (as-fed)
		  PIG_FEED      = { dm = 0.90, energyMJ = 8.5, proteinKg = 0.180 },
		  CHICKEN_FEED  = { dm = 0.90, energyMJ = 7.1, proteinKg = 0.160 },

		  -- Non-nutritive (as-fed)
		  MINERAL       = { dm = 1.00, energyMJ = 0.0, proteinKg = 0.000 },
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
-- Cached loader: logs only on first real read; use PN_Settings.load(true) to force reload.
function PN_Settings.load(forceReload)
    if PN_Settings._cache and not forceReload then
        return PN_Settings._cache
    end

    local cfg = baseConfig()

    local dir = _extBaseDir()
    if dir == "" then
        Logging.info("[PN] Settings: no user profile dir; using built-in defaults only.")
        PN_Settings._cache = cfg
        return cfg
    end

    -- Explicit individual files (nice for users)
    loadFeedsXml(cfg,   dir .. "/feeds.xml")
    loadTargetsXml(cfg, dir .. "/targets.xml")
    loadStagesXml(cfg,  dir .. "/stages.xml")

    -- Any other *.xml packs in the folder (optional)
    mergeAnyXmlPacks(cfg, dir)

    PN_Settings._cache = cfg
    return cfg
end

function PN_Settings.invalidateCache()
    PN_Settings._cache = nil
end

return PN_Settings
