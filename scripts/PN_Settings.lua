-- FS25_PrecisionNutrition / scripts / PN_Settings.lua
PN_Settings = PN_Settings or {}

function PN_Settings.load()
    local cfg = {
        stages = {
            COW = {
                { name="CALF",   minAgeM=0,  maxAgeM=6,   baseADG=0.7 },
                { name="HEIFER", minAgeM=6,  maxAgeM=15,  baseADG=0.9 },
                { name="LACT",   minAgeM=15, maxAgeM=120, baseADG=0.2 },
                { name="DRY",    minAgeM=15, maxAgeM=120, baseADG=0.0 },
                default = { name="DEFAULT", minAgeM=0, maxAgeM=1e9, baseADG=0.2 },
            },
            SHEEP = {
                { name="LAMB",     minAgeM=0,  maxAgeM=6,   baseADG=0.25 },
                { name="EWE_LACT", minAgeM=6,  maxAgeM=120, baseADG=0.05 },
                { name="EWE_DRY",  minAgeM=6,  maxAgeM=120, baseADG=0.00 },
                default = { name="DEFAULT", minAgeM=0, maxAgeM=1e9, baseADG=0.05 },
            },
            PIG = {
                { name="PIGLET",  minAgeM=0,  maxAgeM=2,   baseADG=0.35 },
                { name="GROWER",  minAgeM=2,  maxAgeM=5,   baseADG=0.65 },
                { name="FINISH",  minAgeM=5,  maxAgeM=12,  baseADG=0.80 },
                { name="SOW_GEST",minAgeM=8,  maxAgeM=120, baseADG=0.20 },
                { name="SOW_LACT",minAgeM=8,  maxAgeM=120, baseADG=0.10 },
                default = { name="DEFAULT", minAgeM=0, maxAgeM=1e9, baseADG=0.40 },
            },
            GOAT = {
                { name="KID",      minAgeM=0,  maxAgeM=6,   baseADG=0.20 },
                { name="DOE_LACT", minAgeM=6,  maxAgeM=120, baseADG=0.05 },
                { name="DOE_DRY",  minAgeM=6,  maxAgeM=120, baseADG=0.00 },
                default = { name="DEFAULT", minAgeM=0, maxAgeM=1e9, baseADG=0.05 },
            },
            CHICKEN = {
                { name="CHICK",   minAgeM=0,  maxAgeM=1,   baseADG=0.05 },
                { name="BROILER", minAgeM=1,  maxAgeM=6,   baseADG=0.08 },
                { name="LAYER",   minAgeM=5,  maxAgeM=60,  baseADG=0.02 },
                default = { name="DEFAULT", minAgeM=0, maxAgeM=1e9, baseADG=0.03 },
            },
        },
        targets = {
            COW = {
                CALF={DMI=2.0,DM=0.88,CP=0.18,NDF=0.30,Starch=0.25,Sugar=0.08,Fat=0.04,Ash=0.08},
                HEIFER={DMI=7.0,DM=0.88,CP=0.16,NDF=0.35,Starch=0.18,Sugar=0.06,Fat=0.04,Ash=0.07},
                LACT={DMI=20.0,DM=0.88,CP=0.17,NDF=0.32,Starch=0.22,Sugar=0.06,Fat=0.05,Ash=0.08},
                DRY={DMI=12.0,DM=0.88,CP=0.13,NDF=0.40,Starch=0.15,Sugar=0.05,Fat=0.03,Ash=0.08},
                DEFAULT={DMI=12.0,DM=0.88,CP=0.15,NDF=0.35,Starch=0.20,Sugar=0.06,Fat=0.04,Ash=0.08},
            },
            SHEEP = {
                LAMB={DMI=1.0,DM=0.88,CP=0.16,NDF=0.35,Starch=0.18,Sugar=0.06,Fat=0.04,Ash=0.08},
                EWE_LACT={DMI=2.5,DM=0.88,CP=0.17,NDF=0.35,Starch=0.20,Sugar=0.07,Fat=0.04,Ash=0.08},
                EWE_DRY={DMI=1.8,DM=0.88,CP=0.12,NDF=0.40,Starch=0.15,Sugar=0.05,Fat=0.03,Ash=0.08},
                DEFAULT={DMI=2.0,DM=0.88,CP=0.14,NDF=0.37,Starch=0.18,Sugar=0.06,Fat=0.03,Ash=0.08},
            },
            PIG = {
                PIGLET={DMI=0.6,DM=0.90,CP=0.20,NDF=0.15,Starch=0.35,Sugar=0.08,Fat=0.05,Ash=0.07},
                GROWER={DMI=1.6,DM=0.90,CP=0.18,NDF=0.15,Starch=0.38,Sugar=0.08,Fat=0.05,Ash=0.06},
                FINISH={DMI=2.4,DM=0.90,CP=0.16,NDF=0.15,Starch=0.40,Sugar=0.07,Fat=0.05,Ash=0.06},
                SOW_GEST={DMI=2.2,DM=0.90,CP=0.15,NDF=0.20,Starch=0.30,Sugar=0.08,Fat=0.05,Ash=0.07},
                SOW_LACT={DMI=5.0,DM=0.90,CP=0.18,NDF=0.20,Starch=0.35,Sugar=0.08,Fat=0.06,Ash=0.06},
                DEFAULT={DMI=2.0,DM=0.90,CP=0.17,NDF=0.18,Starch=0.36,Sugar=0.08,Fat=0.05,Ash=0.06},
            },
            GOAT = {
                KID={DMI=0.8,DM=0.88,CP=0.18,NDF=0.35,Starch=0.18,Sugar=0.06,Fat=0.04,Ash=0.08},
                DOE_LACT={DMI=2.2,DM=0.88,CP=0.16,NDF=0.35,Starch=0.20,Sugar=0.07,Fat=0.04,Ash=0.08},
                DOE_DRY={DMI=1.6,DM=0.88,CP=0.12,NDF=0.40,Starch=0.15,Sugar=0.05,Fat=0.03,Ash=0.08},
                DEFAULT={DMI=1.8,DM=0.88,CP=0.14,NDF=0.37,Starch=0.18,Sugar=0.06,Fat=0.03,Ash=0.08},
            },
            CHICKEN = {
                CHICK={DMI=0.05,DM=0.90,CP=0.20,NDF=0.10,Starch=0.40,Sugar=0.05,Fat=0.05,Ash=0.07},
                BROILER={DMI=0.12,DM=0.90,CP=0.19,NDF=0.10,Starch=0.42,Sugar=0.05,Fat=0.05,Ash=0.06},
                LAYER={DMI=0.11,DM=0.90,CP=0.17,NDF=0.12,Starch=0.38,Sugar=0.06,Fat=0.05,Ash=0.09},
                DEFAULT={DMI=0.10,DM=0.90,CP=0.18,NDF=0.11,Starch=0.40,Sugar=0.05,Fat=0.05,Ash=0.07},
            },
        },
        intakes = {
            COW={DEFAULT={}}, SHEEP={DEFAULT={}}, PIG={DEFAULT={}}, GOAT={DEFAULT={}}, CHICKEN={DEFAULT={}},
        },
    }
    local function ensureSpecies(s)
        cfg.stages[s]  = cfg.stages[s]  or { default={ name="DEFAULT", minAgeM=0, maxAgeM=1e9, baseADG=0 } }
        cfg.intakes[s] = cfg.intakes[s] or { DEFAULT={} }
        cfg.targets[s] = cfg.targets[s] or { DEFAULT={} }
        cfg.stages[s].default = cfg.stages[s].default or { name="DEFAULT", minAgeM=0, maxAgeM=1e9, baseADG=0 }
        cfg.intakes[s].DEFAULT = cfg.intakes[s].DEFAULT or {}
        cfg.targets[s].DEFAULT = cfg.targets[s].DEFAULT or {}
    end
    for _, sp in ipairs({"COW","SHEEP","PIG","GOAT","CHICKEN"}) do ensureSpecies(sp) end

    return cfg
end

return PN_Settings
