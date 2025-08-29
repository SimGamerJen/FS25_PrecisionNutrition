PN_Core = {}

local Feed = PN_FeedMatrix
local cfg  = nil

local MS_PER_DAY = 24*60*60*1000

function PN_Core.init(settings) cfg = settings end

local function mixVectors(consumed)
  local tot, v = 0, {energy=0,protein=0,fibre=0,starch=0}
  for ft, amt in pairs(consumed) do
    local m = Feed[ft]
    if m and amt > 0 then
      v.energy  = v.energy  + m.energy  * amt
      v.protein = v.protein + m.protein * amt
      v.fibre   = v.fibre   + m.fibre   * amt
      v.starch  = v.starch  + m.starch  * amt
      tot = tot + amt
    end
  end
  if tot > 0 then
    v.energy, v.protein, v.fibre, v.starch =
      v.energy/tot, v.protein/tot, v.fibre/tot, v.starch/tot
  end
  return v, tot
end

local function cosine(a,b)
  local dot = a.energy*b.energy + a.protein*b.protein + a.fibre*b.fibre + a.starch*b.starch
  local na  = math.sqrt(a.energy^2 + a.protein^2 + a.fibre^2 + a.starch^2)
  local nb  = math.sqrt(b.energy^2 + b.protein^2 + b.fibre^2 + b.starch^2)
  if na == 0 or nb == 0 then return 0 end
  return math.max(0, math.min(1, dot/(na*nb)))
end

local function getStage(ageM)
  for _, s in ipairs(cfg.stages.COW) do
    if ageM >= s.minAgeM and ageM < s.maxAgeM then return s.name end
  end
  return "grower"
end

local function intakeScore(stage, intakePH)
  local I = cfg.intakes.COW[stage]
  if intakePH <= I.min then return 0.5 * (intakePH / math.max(I.min, 0.01)) end
  if intakePH >= I.max then return 1 end
  return 0.5 + 0.5 * ((intakePH - I.min) / (I.max - I.min))
end

function PN_Core.calcTick(animalType, ageMonths, consumedByFillType, nAnimals, dtMs)
  if animalType ~= "COW" or nAnimals < 1 then return nil end

  local stage  = getStage(ageMonths)
  local vec, total = mixVectors(consumedByFillType)
  local target = cfg.targets.COW[stage]
  local bal    = cosine(vec, target) ^ cfg.params.dietPenaltyK
  local starchPenalty = (vec.starch > cfg.params.starchUpper)
        and math.max(0.6, 0.9 - (vec.starch - cfg.params.starchUpper)*1.5) or 1.0

  local intakePH = (total / nAnimals) / (dtMs / MS_PER_DAY)
  local iscore   = intakeScore(stage, intakePH)

  local baseADG  = cfg.stages.COW[stage].baseADG
  local adg      = math.min(cfg.params.adgCap, math.max(0, baseADG * bal * iscore * starchPenalty))

  local forageConsumed = (
    (consumedByFillType.GRASS_WINDROW or 0) +
    (consumedByFillType.ALFALFA_WINDROW or 0) +
    (consumedByFillType.CLOVER_WINDROW or 0) +
    (consumedByFillType.DRYGRASS_WINDROW or 0) +
    (consumedByFillType.DRYALFALFA_WINDROW or 0) +
    (consumedByFillType.DRYCLOVER_WINDROW or 0) +
    (consumedByFillType.SILAGE or 0)
  )
  local forageShare = (total > 0) and (forageConsumed / total) or 0

  return { adg=adg, stage=stage, intakePH=intakePH, forageShare=forageShare, balance=bal }
end

return PN_Core
