-- scripts/PN_FeedMatrix.lua
-- Nutrient vectors on a 0..1 scale per macro; ballpark values.
PN_FeedMatrix = {
  -- Forages / roughage
  GRASS_WINDROW      = {energy=0.30, protein=0.12, fibre=0.48, starch=0.10},
  ALFALFA_WINDROW    = {energy=0.36, protein=0.20, fibre=0.38, starch=0.06},
  CLOVER_WINDROW     = {energy=0.33, protein=0.17, fibre=0.42, starch=0.08},
  DRYGRASS_WINDROW   = {energy=0.32, protein=0.14, fibre=0.46, starch=0.08},
  DRYALFALFA_WINDROW = {energy=0.37, protein=0.20, fibre=0.39, starch=0.04},
  DRYCLOVER_WINDROW  = {energy=0.34, protein=0.17, fibre=0.41, starch=0.08},
  SILAGE             = {energy=0.38, protein=0.15, fibre=0.40, starch=0.07},
  STRAW              = {energy=0.15, protein=0.04, fibre=0.78, starch=0.03},
  SOYBEANSTRAW       = {energy=0.16, protein=0.05, fibre=0.76, starch=0.03},
  CORN_STALKS        = {energy=0.17, protein=0.05, fibre=0.75, starch=0.03},

  -- Energy grains
  MAIZE     = {energy=0.55, protein=0.09, fibre=0.06, starch=0.30},
  WHEAT     = {energy=0.48, protein=0.12, fibre=0.11, starch=0.29},
  BARLEY    = {energy=0.49, protein=0.11, fibre=0.11, starch=0.29},
  RYE       = {energy=0.47, protein=0.12, fibre=0.12, starch=0.29},
  TRITICALE = {energy=0.49, protein=0.13, fibre=0.10, starch=0.28},
  OAT       = {energy=0.45, protein=0.11, fibre=0.17, starch=0.27},
  SORGHUM   = {energy=0.48, protein=0.11, fibre=0.12, starch=0.29},

  -- Protein grains / pulses / oilseeds
  PEA       = {energy=0.41, protein=0.24, fibre=0.21, starch=0.14}, -- base peas
  DRYPEAS   = {energy=0.42, protein=0.25, fibre=0.20, starch=0.13}, -- fodder peas
  BEANS     = {energy=0.41, protein=0.26, fibre=0.20, starch=0.13}, -- pinto beans
  LENTILS   = {energy=0.40, protein=0.24, fibre=0.21, starch=0.15},
  CHICKPEAS = {energy=0.41, protein=0.23, fibre=0.21, starch=0.15},
  SOYBEAN   = {energy=0.41, protein=0.28, fibre=0.19, starch=0.12},
  CANOLA    = {energy=0.46, protein=0.23, fibre=0.20, starch=0.11},
  SUNFLOWER = {energy=0.43, protein=0.21, fibre=0.23, starch=0.13},

  -- Premix & fallback for TMR (FORAGE)
  MINERAL_FEED = {energy=0.00, protein=0.00, fibre=0.00, starch=0.00},
  FORAGE       = {energy=0.36, protein=0.17, fibre=0.36, starch=0.11}, -- recipe fallback
}
