PN_Core = {}

-- === PN multi-species support (Option A stage lookup) ===
local cfg = cfg or nil

function PN_Core.init(settings)
    cfg = settings
end

local function normSpecies(s)
    s = tostring(s or ""):upper()
    if s == "COW" or s == "CATTLE" then return "COW" end
    if s == "SHEEP" then return "SHEEP" end
    if s == "PIG" or s == "SWINE" then return "PIG" end
    if s == "GOAT" then return "GOAT" end
    if s == "CHICKEN" or s == "HEN" then return "CHICKEN" end
    return "COW"
end

local function inferSpecies(entry, clusterSystem)
    if entry and entry.type and entry.type ~= "ANIMAL" then
        return normSpecies(entry.type)
    end
    if clusterSystem and clusterSystem.getClusters then
        local ok, clusters = pcall(clusterSystem.getClusters, clusterSystem)
        if ok and type(clusters) == "table" then
            for _, c in pairs(clusters) do
                local st = tostring(c and c.subType or ""):upper()
                if st:find("COW", 1, true) or st:find("BULL", 1, true) then return "COW" end
                if st:find("SHEEP", 1, true) then return "SHEEP" end
                if st:find("PIG", 1, true) then return "PIG" end
                if st:find("GOAT", 1, true) then return "GOAT" end
                if st:find("CHICK", 1, true) or st:find("HEN", 1, true) then return "CHICKEN" end
            end
        end
    end
    return "COW"
end

local function getStage(species, ageM)
    species = normSpecies(species)
    local stages = cfg and cfg.stages and cfg.stages[species]
    if type(stages) == "table" then
        for _, s in ipairs(stages) do
            if ageM >= (s.minAgeM or 0) and ageM < (s.maxAgeM or math.huge) then
                return s
            end
        end
        if stages.default then return stages.default end
    end
    return { name="DEFAULT", baseADG=0, minAgeM=0, maxAgeM=math.huge }
end


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

function PN_Core.calcTick(species, ageMonths, consumedByFillType, headcount, dtMs)

    if not cfg or not cfg.stages or not cfg.intakes or not cfg.targets then return nil end
    species = normSpecies(species)
    local S = getStage(species, ageMonths or 0)
    local stageName = S.name
    local speciesIntakes = cfg.intakes[species]
    local speciesTargets = cfg.targets[species]
    if not speciesIntakes or not speciesTargets then return nil end
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
    local species = inferSpecies(entry, clusterSystem)
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

	-- === Heartbeat (server-only), dt-accumulated ===
	PN_HEARTBEAT_MS = PN_HEARTBEAT_MS or 3000
	local isMp  = g_currentMission and g_currentMission.missionDynamicInfo and g_currentMission.missionDynamicInfo.isMultiplayer
	local force = (ctx and ctx.forceBeat) == true

	-- Only log from server (avoid client spam in MP)
	if not (isMp and not g_server) then
		-- accumulate dt and log on threshold
		entry.__pn_lastBeat = entry.__pn_lastBeat or 0  -- keep for reference
		entry.__pn_accum    = (entry.__pn_accum or 0) + (dtMs or 0)

		local firstPrint = (entry.__pn_lastBeat == 0)
		local due        = entry.__pn_accum >= (PN_HEARTBEAT_MS or 3000)

		if force or firstPrint or due then
			Logging.info("[PN] %s [%s] | head=%d (M:%d / F:%d, preg=%d) avgW=%.1fkg",
				tostring(entry.name), species, totals.animals, totals.bulls, totals.cows, totals.pregnant, totals.avgWeight)
			entry.__pn_lastBeat = g_time or 0
			entry.__pn_accum    = 0
		end
	end

    entry.__pn_totals = totals
end

return PN_Core
