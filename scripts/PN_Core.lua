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

-- === PN live per-husbandry update (safe) ===
function PN_Core:updateHusbandry(entry, clusterSystem, dtMs, ctx)
    if clusterSystem == nil or clusterSystem.getClusters == nil then return end

    local ok, clusters = pcall(clusterSystem.getClusters, clusterSystem)
    if not ok or type(clusters) ~= "table" then return end

    -- Aggregate simple stats (gender, pregnancy, weight)
    local totals = {
        animals = 0, bulls = 0, cows = 0, pregnant = 0,
        weightSum = 0, bySubType = {}
    }

    for _, c in pairs(clusters) do
        if type(c) == "table" and not c.isDead then
            totals.animals = totals.animals + 1
            local g = tostring(c.gender or ""):lower()
            if g == "male" then totals.bulls = totals.bulls + 1 end
            if g == "female" then
                totals.cows = totals.cows + 1
                if c.isPregnant then totals.pregnant = totals.pregnant + 1 end
            end
            local w = tonumber(c.weight or 0) or 0
            totals.weightSum = totals.weightSum + w

            local st = tostring(c.subType or "?")
            totals.bySubType[st] = (totals.bySubType[st] or 0) + 1
        end
    end
    totals.avgWeight = (totals.animals > 0) and (totals.weightSum / totals.animals) or 0

    -- TODO: when intake math is wired, compute consumedByFillType and call your calcTick(...)
    -- Example placeholder:
    -- local consumed = ctx and ctx.consumedByFillType or {}
    -- local ageMonths = ctx and ctx.avgAgeM or 18
    -- local res = PN_Core.calcTick and PN_Core.calcTick("COW", ageMonths, consumed, totals.animals, dtMs) or nil
    -- entry.__pn_last = res

    -- Temporary heartbeat so you see something in the log:
    if totals.animals > 0 and (g_time % 3000) < (dtMs or 0) then
        Logging.info("[PN] %s | head=%d (♂%d / ♀%d, preg=%d) avgW=%.1fkg",
            tostring(entry.name), totals.animals, totals.bulls, totals.cows, totals.pregnant, totals.avgWeight)
    end

    entry.__pn_totals = totals
end

return PN_Core
