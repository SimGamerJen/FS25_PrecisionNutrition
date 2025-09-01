-- FS25_PrecisionNutrition / scripts / PN_Core.lua
-- Core nutrition logic: intake accounting, fulfillment, and weight gain.

PN_Core = PN_Core or {}

-- -----------------------
-- Internal state
-- -----------------------
PN_Core.cfg          = PN_Core.cfg or nil
PN_Core._lastTrough  = PN_Core._lastTrough or setmetatable({}, { __mode = "k" }) -- per-entry cache
PN_Core._nutOverride = PN_Core._nutOverride or setmetatable({}, { __mode = "k" }) -- per-entry Nut lock [0..1]
PN_Core._simBoost    = PN_Core._simBoost or setmetatable({}, { __mode = "k" }) -- per-entry sim weight kg to add once

-- -----------------------
-- Utils
-- -----------------------
local function _u(s) return tostring(s or ""):upper() end

local function _ftNameByIndex(ftIndex)
    if g_fillTypeManager and g_fillTypeManager.getFillTypeNameByIndex then
        local n = g_fillTypeManager:getFillTypeNameByIndex(ftIndex)
        if n and n ~= "" then return n end
    end
    return tostring(ftIndex)
end

-- kg (as-fed) from liters using engine massPerLiter when available; fallback 1:1
local function _kgFromFill(ftIndex, liters)
    if liters == nil then return 0 end
    local kg = tonumber(liters) or 0
    if g_fillTypeManager and g_fillTypeManager.fillTypes and g_fillTypeManager.fillTypes[ftIndex] then
        local d = g_fillTypeManager.fillTypes[ftIndex].massPerLiter
        if d and d > 0 then kg = liters * d end
    end
    return kg
end

local function _nfmt(x, p)
    x = tonumber(x or 0) or 0
    local m = 10 ^ (p or 1)
    return math.floor(x * m + 0.5) / m
end

-- -----------------------
-- Config access
-- -----------------------
function PN_Core.init(cfg)
    PN_Core.cfg = cfg or {}
    PN_Core.feedMatrix  = PN_Core.cfg.feedMatrix  or {}
    PN_Core.feedAliases = PN_Core.cfg.feedAliases or {}
    PN_Core.targets     = PN_Core.cfg.targets     or {}
    PN_Core.stages      = PN_Core.cfg.stages      or {}
    PN_Core.meta        = PN_Core.cfg.meta        or {}
    PN_Core.autoConsume = (PN_Core.cfg.autoConsume == true)  -- optional toggle
end

local function _aliasFeed(token)
    token = _u(token)
    local a = PN_Core.feedAliases[token]
    if a then return _u(a) end
    return token
end

-- Option A (gender-aware): pick first row where gender matches (or is nil),
-- and minAgeM <= months < maxAgeM. Allows gender-specific defaults: default_male/default_female.
local function _getStage(speciesKey, months, gender)
    local S = PN_Core.stages[_u(speciesKey or "DEFAULT")] or {}
    local g = tostring(gender or ""):lower()
    local list = {}
    for _, row in ipairs(S) do
        if type(row) == "table" and row.name and row.minAgeM and row.maxAgeM then
            if row.gender == nil or tostring(row.gender):lower() == g then
                table.insert(list, row)
            end
        end
    end
    table.sort(list, function(a, b) return a.minAgeM < b.minAgeM end)
    for _, r in ipairs(list) do
        if months >= r.minAgeM and months < r.maxAgeM then return r end
    end
    -- fallbacks: gendered default first, then generic default
    local dGender = S["default_" .. (g ~= "" and g or "any")]
    if dGender then return dGender end
    return S.default or { name = "DEFAULT", minAgeM = 0, maxAgeM = 1e9, baseADG = 0.2 }
end

local function _getTargets(speciesKey, stageName)
    local T = PN_Core.targets[_u(speciesKey or "DEFAULT")] or PN_Core.targets.DEFAULT or {}
    local row = (T[stageName or "default"] or T.default or { energyMJ = 20, proteinKg = 0.3, dmiKg = 2 })
    return row.energyMJ or 0, row.proteinKg or 0, row.dmiKg or 0
end

-- Species best-effort (kept simple; UI may set entry.__pn_species)
local function _getSpeciesFromEntry(entry)
    if entry and entry.__pn_species then return entry.__pn_species end
    return "COW"
end

-- -----------------------
-- FEED RESOLUTION / TROUGH LEVELS (levels-based path)
-- -----------------------
local function _resolveFeed(ftIndex)
    local token = _u(_ftNameByIndex(ftIndex))
    token = _aliasFeed(token)
    local row = PN_Core.feedMatrix[token]
    return token, row
end

-- Read placeable.spec_husbandryFood.fillLevels as { [ftIndex]=liters, ... }
local function _readHusbandryFoodLevels(entry)
    local p = entry and entry.placeable
    local spec = p and p.spec_husbandryFood
    local levels = {}
    if spec and type(spec.fillLevels) == "table" then
        for ftIndex, liters in pairs(spec.fillLevels) do
            levels[ftIndex] = tonumber(liters or 0) or 0
        end
    end
    return levels, spec
end

-- Sum DM kg available from current levels: sum( asFedKg(ft) * row.dm )
local function _availableDmKgFromLevels(levelsByIndex)
    local total = 0
    for ftIndex, liters in pairs(levelsByIndex or {}) do
        local asFedKg = _kgFromFill(ftIndex, liters)
        local _, row = _resolveFeed(ftIndex)
        if row and asFedKg > 0 then
            total = total + asFedKg * (row.dm or 1)
        end
    end
    return total
end

-- Consume DM from levels proportionally to each FT's DM contribution.
-- dmBarnKg: total DM kg to remove across all feeds (this frame)
local function _consumeDmFromLevels(entry, levelsByIndex, dmBarnKg, specHF)
    if (dmBarnKg or 0) <= 0 then return end
    local totalDm = 0
    local perFtDm = {}
    for ftIndex, liters in pairs(levelsByIndex or {}) do
        local asFedKg = _kgFromFill(ftIndex, liters)
        local _, row = _resolveFeed(ftIndex)
        if row and asFedKg > 0 then
            local dmKg = asFedKg * (row.dm or 1)
            perFtDm[ftIndex] = dmKg
            totalDm = totalDm + dmKg
        end
    end
    if totalDm <= 1e-6 then return end

    -- Draw liters proportional to DM share
    if not (specHF and specHF.fillLevels) then return end
    for ftIndex, dmKg in pairs(perFtDm) do
        local share = math.min(dmKg / totalDm, 1)
        local drawDm = share * dmBarnKg
        local liters = levelsByIndex[ftIndex] or 0
        if liters > 0 and drawDm > 0 then
            local asFedKg = _kgFromFill(ftIndex, liters)
            local _, row = _resolveFeed(ftIndex)
            local dmPerLiter = 0
            if asFedKg > 0 and liters > 0 and row and row.dm then
                local kgPerLiter = asFedKg / liters
                dmPerLiter = kgPerLiter * (row.dm or 1)
            end
            if dmPerLiter > 0 then
                local drawLiters = drawDm / dmPerLiter
                local newL = math.max(0, liters - drawLiters)
                specHF.fillLevels[ftIndex] = newL
                levelsByIndex[ftIndex] = newL
            end
        end
    end
end

-- -----------------------
-- Trough consumption scanner (delta-based path)
-- Reads both spec_fillUnit and spec_husbandryFood.fillLevels
-- Returns map: [fillTypeIndex] = kgConsumedThisTick (as-fed)
-- -----------------------
local function _scanTroughConsumption(entry, placeable)
    local consumedKg = {}
    if not placeable then return consumedKg end

    local last = PN_Core._lastTrough[entry]
    if last == nil then last = {}; PN_Core._lastTrough[entry] = last end

    local function addDelta(ftIndex, deltaLiters)
        if not ftIndex or not deltaLiters or deltaLiters <= 0 then return end
        local kg = _kgFromFill(ftIndex, deltaLiters)
        if kg > 0 then
            consumedKg[ftIndex] = (consumedKg[ftIndex] or 0) + kg
        end
    end

    -- PATH 1: fillUnits
    local fuSpec = placeable.spec_fillUnit
    if fuSpec and fuSpec.fillUnits then
        for u, fu in ipairs(fuSpec.fillUnits) do
            local level = fu and fu.fillLevel
            if level ~= nil then
                local unitKey  = ("FU:%d:%s"):format(u, tostring(fu))
                local unitPrev = last[unitKey]
                local unitCur  = level

                if fu.fillLevels and type(fu.fillLevels) == "table" then
                    for ftIndex, cur in pairs(fu.fillLevels) do
                        local key  = ("FULVL:%d:%s"):format(u, tostring(ftIndex))
                        local prev = last[key] or cur
                        local deltaL = (prev - cur)
                        if deltaL > 0 then addDelta(ftIndex, deltaL) end
                        last[key] = cur
                    end
                elseif fu.supportedFillTypes then
                    if unitPrev == nil then unitPrev = unitCur end
                    local deltaL = (unitPrev - unitCur)
                    if deltaL > 0 then
                        local ftIndex = fu.lastFillType or fu.fillType
                        if not ftIndex then
                            for ftIdx, allowed in pairs(fu.supportedFillTypes) do
                                if allowed then ftIndex = ftIdx; break end
                            end
                        end
                        if ftIndex then addDelta(ftIndex, deltaL) end
                    end
                else
                    local ftIndex = fu.lastFillType or fu.fillType
                    if unitPrev == nil then unitPrev = unitCur end
                    local deltaL = (unitPrev - unitCur)
                    if deltaL > 0 and ftIndex ~= nil then addDelta(ftIndex, deltaL) end
                end
                last[unitKey] = unitCur
            end
        end
    end

    -- PATH 2: husbandryFood.fillLevels
    local foodSpec = placeable.spec_husbandryFood
    if foodSpec and type(foodSpec.fillLevels) == "table" then
        for ftIndex, cur in pairs(foodSpec.fillLevels) do
            local key  = ("HF:%s"):format(tostring(ftIndex))
            local prev = last[key]
            if prev == nil then
                last[key] = cur
            else
                local deltaL = (prev - cur)
                if deltaL > 0 then addDelta(ftIndex, deltaL) end
                last[key] = cur
            end
        end
    end

    return consumedKg
end

-- -----------------------
-- Nutrition accounting (delta path → nutrients)
-- -----------------------
local function _accumulateNutrients(consumedKgByFT)
    local N = { dm = 0, energyMJ = 0, proteinKg = 0, asFedKg = 0 }
    for ftIndex, kg in pairs(consumedKgByFT or {}) do
        local token, row = _resolveFeed(ftIndex)
        if row then
            local asFed = kg
            local dmKg  = asFed * (row.dm or 1)
            N.asFedKg   = N.asFedKg + asFed
            N.dm        = N.dm + dmKg
            N.energyMJ  = N.energyMJ + (asFed * (row.energyMJ or 0))
            N.proteinKg = N.proteinKg + (asFed * (row.proteinKg or 0))
        end
    end
    return N
end

-- -----------------------
-- Group snapshot (overlay assist, legacy)
-- -----------------------
local function _computeGroupSnapshots(entry, totals)
    local cs = entry and entry.clusterSystem
    if not (cs and cs.getClusters) then
        entry.__pn_groups = nil
        return
    end

    local groups = {
        female = { head = 0, weightSum = 0, avgW = 0, nut = 0, adg = 0 },
        male   = { head = 0, weightSum = 0, avgW = 0, nut = 0, adg = 0 },
    }

    local ok, clusters = pcall(cs.getClusters, cs)
    if not ok or type(clusters) ~= "table" then
        entry.__pn_groups = nil
        return
    end

    for _, c in pairs(clusters) do
        if type(c) == "table" and not c.isDead then
            local g = tostring(c.gender or ""):lower()
            local w = tonumber(c.weight or 0) or 0
            if g == "female" then
                groups.female.head      = groups.female.head + 1
                groups.female.weightSum = groups.female.weightSum + w
            elseif g == "male" then
                groups.male.head      = groups.male.head + 1
                groups.male.weightSum = groups.male.weightSum + w
            end
        end
    end

    groups.female.avgW = (groups.female.head > 0) and (groups.female.weightSum / groups.female.head) or 0
    groups.male.avgW   = (groups.male.head   > 0) and (groups.male.weightSum   / groups.male.head)   or 0

    local barnNut  = 0
    local barnADG  = 0
    if entry.__pn_last then
        barnNut = tonumber(entry.__pn_last.nutRatio or 0) or 0
        barnADG = tonumber(entry.__pn_last.effADG or 0) or 0
    elseif totals then
        barnNut = tonumber(totals.nut or 0) or 0
        barnADG = tonumber(totals.adg or totals.effADG or 0) or 0
    end

    local function stageADGFor(species, sex, avgW)
        if PN_Core and type(PN_Core.stageADG) == "function" then
            local ok2, base = pcall(PN_Core.stageADG, species, sex, avgW)
            if ok2 and type(base) == "number" then return base end
        end
        if PN_Core and type(PN_Core._stageADG) == "function" then
            local ok3, base = pcall(PN_Core._stageADG, species, sex)
            if ok3 and type(base) == "number" then return base end
        end
        return barnADG / math.max(barnNut, 1e-6)
    end

    local species = (entry.__pn_totals and entry.__pn_totals.species) or "COW"

    if groups.female.head > 0 then
        local base = stageADGFor(species, "female", groups.female.avgW)
        groups.female.nut = barnNut
        groups.female.adg = base * barnNut
    end
    if groups.male.head > 0 then
        local base = stageADGFor(species, "male", groups.male.avgW)
        groups.male.nut = barnNut
        groups.male.adg = base * barnNut
    end

    entry.__pn_groups = groups
end

-- -----------------------
-- Public helpers used by PN_Debug
-- -----------------------
function PN_Core.setBarnNutrition(entry, ratio) -- 0..1
    PN_Core._nutOverride[entry] = nil
    entry.__pn_nutRatio = math.max(0, math.min(1, tonumber(ratio or 0) or 0))
end

function PN_Core.setBarnNutritionOverride(entry, ratio) -- 0..1 ; nil clears
    if ratio == nil then
        PN_Core._nutOverride[entry] = nil
        return
    end
    PN_Core._nutOverride[entry] = math.max(0, math.min(1, tonumber(ratio) or 0))
end

-- Sim: apply an immediate per-head average weight change equivalent to Δt with current ADG
function PN_Core.simAdvance(entry, hours)
    if not entry then return end
    hours = tonumber(hours or 0) or 0
    if hours <= 0 then return end
    local t = entry.__pn_totals or {}
    local adg = t.adg or 0 -- kg/day
    local head = math.max(1, t.animals or 1)
    local deltaAvg = (adg / 24) * hours
    local addKg = deltaAvg * head
    PN_Core._simBoost[entry] = (PN_Core._simBoost[entry] or 0) + addKg
end

-- -----------------------
-- (NEW) Public API suggested: nutritionForStage / adgFor
-- -----------------------
-- Returns nutrition ratio 0..1 for a (species, stage, entry)
function PN_Core:nutritionForStage(species, stageLabel, entry)
    -- If you later differentiate by stage targets, compare barn mix against stage needs here.
    -- For now, fallback to barn-level ratio captured in updateHusbandry:
    return (entry and entry.__pn_last and entry.__pn_last.nutRatio) or 0
end

-- Returns ADG (kg/day) for a (species, stage, avgWeightKg, nutRatio)
function PN_Core:adgFor(species, stageLabel, avgW, nut)
    -- Baseline model; override in settings if needed.
    local sp  = _u(species or "COW")
    local st  = _u(stageLabel or "DEFAULT")
    local n   = tonumber(nut or 0) or 0
    local base = 0.10
    if sp == "COW" then
        if st == "LACT" then base = 0.12 end
        if st == "GEST" then base = 0.10 end
        if st == "BULL" then base = 0.09 end
    elseif sp == "SHEEP" then
        base = 0.04
    elseif sp == "PIG" then
        base = 0.30
    end
    return base * n
end

-- -----------------------
-- Gender split helper (uses same Nut/taper rules)
-- -----------------------
local function _calcGenderLine(genderKey, gHead, gWeightSum, gMonths, speciesKey, nutRatio)
    local g = { head = gHead or 0, avgW = 0, stage = "DEFAULT", adg = 0 }
    if g.head > 0 then
        g.avgW = (gWeightSum or 0) / g.head
        local st = _getStage(speciesKey, gMonths or 0, genderKey)
        g.stage = st.name or "DEFAULT"
        local base = tonumber(st.baseADG or 0) or 0
        local a = base * (nutRatio or 0)

        -- taper as animals approach mature weight (same rule as barn-level)
        local meta = PN_Core.meta and PN_Core.meta[(speciesKey or "COW"):upper()] or nil
        local mk = meta and tonumber(meta.matureKg) or nil
        if mk and mk > 0 and g.avgW > 0 then
            local frac = math.max(0, math.min(1, g.avgW / mk))
            local reserve = math.max(0.10, 1.0 - (frac ^ 1.6))
            a = a * reserve
        end
        g.adg = a
    end
    return g
end

-- -----------------------
-- Heartbeat core update (called each frame from Mission00.update)
-- ctx.injectIntake = { [ftIndex]=kg, ... }  -- optional testing credit
-- -----------------------
function PN_Core.updateHusbandry(self, entry, clusterSystem, dtMs, ctx)
    if not entry or not clusterSystem then return end
    local dtH = (tonumber(dtMs or 0) or 0) / (1000 * 60 * 60)
    if dtH <= 0 then return end

    -- 1) Gather cluster info (head count, sexes, weight sum, rough age proxy)
    local head, bulls, cows, preg, weightSum = 0, 0, 0, 0, 0
    local maleWeightSum, femaleWeightSum = 0, 0
    local avgMonths = 24
    local ok, clusters = pcall(clusterSystem.getClusters, clusterSystem)
    if ok and type(clusters) == "table" then
        for _, c in pairs(clusters) do
            if type(c) == "table" and not c.isDead then
                head = head + 1
                local g = tostring(c.gender or ""):lower()
                if g == "male" then
                    bulls = bulls + 1
                    maleWeightSum = maleWeightSum + (tonumber(c.weight or 0) or 0)
                elseif g == "female" then
                    cows = cows + 1
                    femaleWeightSum = femaleWeightSum + (tonumber(c.weight or 0) or 0)
                    if c.isPregnant then preg = preg + 1 end
                end
                weightSum = weightSum + (tonumber(c.weight or 0) or 0)
                if c.monthsSinceLastBirth ~= nil then
                    avgMonths = math.max(avgMonths, tonumber(c.monthsSinceLastBirth) or avgMonths)
                end
            end
        end
    end
    local avgW = (head > 0) and (weightSum / head) or 0

    -- choose a dominant gender for the barn (used for stage selection)
    local barnGender = "female"
    if bulls > cows then barnGender = "male" end

    -- 2) Determine species & stage → targets and baseADG
    local species = entry.__pn_species or _getSpeciesFromEntry(entry)
    local stage   = _getStage(species, avgMonths, barnGender)
    local E_tgt, P_tgt, DMI_tgt = _getTargets(species, stage.name)

    -- 3) Intake since last tick (delta-based)
    local consumedKgByFT = _scanTroughConsumption(entry, entry.placeable)
    if ctx and type(ctx.injectIntake) == "table" then
        for ftIndex, kg in pairs(ctx.injectIntake) do
            if kg and kg > 0 then
                consumedKgByFT[ftIndex] = (consumedKgByFT[ftIndex] or 0) + kg
            end
        end
    end
    local N = _accumulateNutrients(consumedKgByFT)

    -- 4) Compute demand (per-barn) and availability (levels-based)
    local levels, specHF = _readHusbandryFoodLevels(entry)
    local availDm = _availableDmKgFromLevels(levels)          -- kg DM currently in trough

    -- per-sex stage for demand share (simple: same stage row but we could refine)
    local stageF = _getStage(species, avgMonths, "female")
    local stageM = _getStage(species, avgMonths, "male")
    local _, _, DMI_tgtF = _getTargets(species, stageF.name)
    local _, _, DMI_tgtM = _getTargets(species, stageM.name)

    local dayFrac = math.max(0, dtH / 24.0)
    local reqDmF = (cows  > 0 and DMI_tgtF > 0) and (DMI_tgtF * cows  * dayFrac) or 0
    local reqDmM = (bulls > 0 and DMI_tgtM > 0) and (DMI_tgtM * bulls * dayFrac) or 0
    local reqDmBarn = reqDmF + reqDmM

    -- 5) Fulfillment: prefer delta-based nutrients if present; otherwise use levels/demand
    local eRat, pRat, dRat, nut
    if (N.dm or 0) > 0 then
        -- scale to 24h equivalent
        local scale = (dtH > 0) and (24 / dtH) or 0
        local E_day = N.energyMJ  * scale
        local P_day = N.proteinKg * scale
        local D_day = N.dm        * scale
        eRat = (E_tgt  > 0) and (E_day / (E_tgt  * math.max(1, head))) or 0 -- assume targets per head
        pRat = (P_tgt  > 0) and (P_day / (P_tgt  * math.max(1, head))) or 0
        dRat = (DMI_tgt> 0) and (D_day / (DMI_tgt* math.max(1, head))) or 0
        nut  = math.max(0, math.min(1, math.min(eRat, math.min(pRat, dRat))))
    else
        -- availability path: how much of the current trough could satisfy this frame's demand?
        if reqDmBarn > 0 then
            dRat = math.min(1, (availDm / reqDmBarn))
            nut  = dRat
        else
            dRat, nut = 0, 0
        end
        eRat, pRat = 0, 0
    end

    -- 6) Apply override if set, else persist auto calc for pnBeat/overlay
    local ovr = PN_Core._nutOverride[entry]
    if ovr ~= nil then nut = ovr end
    entry.__pn_nutRatio = nut

    -- 7) Compute ADG = baseADG * Nut, with taper by mature weight
    local baseADG = tonumber(stage.baseADG or 0) or 0
    local adg = baseADG * nut
    if adg < 0 then adg = 0 end

    do
        local meta = PN_Core.meta and PN_Core.meta[(species or "COW"):upper()] or nil
        local matureKg = meta and tonumber(meta.matureKg) or nil
        if matureKg and matureKg > 0 and avgW > 0 then
            local frac = math.max(0, math.min(1, avgW / matureKg))
            local reserve = math.max(0.10, 1.0 - (frac ^ 1.6))
            adg = adg * reserve
        end
    end

    -- 8) Advance average weight
    local deltaAvg = (adg / 24) * dtH

    local addKg = PN_Core._simBoost[entry]
    if addKg and addKg ~= 0 then
        deltaAvg = deltaAvg + (addKg / math.max(1, head))
        PN_Core._simBoost[entry] = 0
    end

    if head > 0 and deltaAvg ~= 0 then
        local newAvg = avgW + deltaAvg
        if ok and type(clusters) == "table" then
            local factor = (newAvg / (avgW ~= 0 and avgW or newAvg))
            for _, c in pairs(clusters) do
                if type(c) == "table" and not c.isDead then
                    local w = tonumber(c.weight or 0) or 0
                    c.weight = w * factor
                end
            end
            avgW = newAvg
        end
    end

    -- 9) Per-gender summaries using same Nut/taper rules (for pnBeat split)
    local gFemale = _calcGenderLine("female", cows,  femaleWeightSum, avgMonths, species, nut)
    local gMale   = _calcGenderLine("male",   bulls, maleWeightSum,   avgMonths, species, nut)

    -- 10) Persist totals for UI/debug
    entry.__pn_totals = {
        animals   = head,
        bulls     = bulls,
        cows      = cows,
        pregnant  = preg,
        weightSum = weightSum,
        avgWeight = avgW,
        nut       = nut,
        adg       = adg,          -- kg/day
        E = (N.energyMJ or 0), P = (N.proteinKg or 0), DMI = (N.dm or 0),
        Et = E_tgt, Pt = P_tgt, DMIt = DMI_tgt,
        species   = species,
        stage     = stage.name,
        gender    = barnGender,
        split     = { female = gFemale, male = gMale },
    }

    -- Also store what overlay expects
    entry.__pn_last = entry.__pn_last or {}
    entry.__pn_last.nutRatio = nut
    entry.__pn_last.effADG   = adg

    --------------------------------------------------------------------------
    -- 11) === GROUP AGGREGATION (female-open / female-preg / male) ===
    --------------------------------------------------------------------------
    -- tiny helpers (scoped here)
    local function _safeLower(s) return tostring(s or ""):lower() end
    local function _safeUpper(s) return tostring(s or ""):upper() end
    local function _nz(x) return tonumber(x or 0) or 0 end

    -- Resolve a readable stage per animal, using settings where possible.
    local function resolveStage(speciesKey, genderKey, isPregnant)
        local sp = _safeUpper(speciesKey)
        local g  = _safeLower(genderKey)

        if PN_Settings and PN_Settings.stageName then
            local key
            if g == "male" then
                key = string.format("%s_M", sp)
            else
                key = string.format("%s_F_%s", sp, isPregnant and "PREG" or "OPEN")
            end
            local name = PN_Settings:stageName(key)
            if name and name ~= "" then return name end
        end

        if g == "male" then
            if sp == "COW" then return "BULL"
            elseif sp == "SHEEP" then return "RAM"
            elseif sp == "GOAT" then return "BUCK"
            elseif sp == "PIG" then return "BOAR"
            elseif sp == "CHICKEN" then return "ROOSTER"
            else return "MALE" end
        else
            if isPregnant then
                if sp == "COW" then return "GEST" else return "PREG" end
            else
                if sp == "COW" then return "LACT" else return "FEMALE" end
            end
        end
    end

    local function inferSpeciesFromEntry(entryObj, csObj)
        if entryObj and entryObj.type and entryObj.type ~= "ANIMAL" then
            return _u(entryObj.type)
        end
        local cs = csObj
        if cs and cs.getClusters then
            local okc, cl = pcall(cs.getClusters, cs)
            if okc and type(cl) == "table" then
                for _, c in pairs(cl) do
                    local st = _u(c and c.subType or "")
                    if st:find("COW",1,true) or st:find("BULL",1,true) then return "COW" end
                    if st:find("SHEEP",1,true) then return "SHEEP" end
                    if st:find("PIG",1,true) then return "PIG" end
                    if st:find("GOAT",1,true) then return "GOAT" end
                    if st:find("CHICK",1,true) or st:find("HEN",1,true) then return "CHICKEN" end
                end
            end
        end
        return "ANIMAL"
    end

    local speciesResolved = inferSpeciesFromEntry(entry, clusterSystem)

    local G = {
        femaleOpen = { n=0, wSum=0, nut=0, adg=0, stage=resolveStage(speciesResolved, "female", false) },
        femalePreg = { n=0, wSum=0, nut=0, adg=0, stage=resolveStage(speciesResolved, "female", true)  },
        male       = { n=0, wSum=0, nut=0, adg=0, stage=resolveStage(speciesResolved, "male",  false) },
    }

    local okC, clustersC = pcall(clusterSystem.getClusters, clusterSystem)
    if okC and type(clustersC) == "table" then
        for _, c in pairs(clustersC) do
            if type(c) == "table" and not c.isDead then
                local g  = _safeLower(c.gender)
                local w  = _nz(c.weight)
                local dst
                if g == "female" then
                    dst = (c.isPregnant and G.femalePreg or G.femaleOpen)
                elseif g == "male" then
                    dst = G.male
                end
                if dst then
                    dst.n    = dst.n + 1
                    dst.wSum = dst.wSum + w
                end
            end
        end
    end

    for _, dst in pairs(G) do
        dst.avgW = (dst.n > 0) and (dst.wSum / dst.n) or 0
    end

    local function groupNutritionRatioFor(stageLabel)
        if PN_Core and PN_Core.nutritionForStage then
            local okN, r = pcall(PN_Core.nutritionForStage, PN_Core, speciesResolved, stageLabel, entry)
            if okN and type(r) == "number" then return math.max(0, math.min(1, r)) end
        end
        local barnNut = (entry.__pn_last and entry.__pn_last.nutRatio) or 0
        return math.max(0, math.min(1, barnNut))
    end

    G.femaleOpen.nut = groupNutritionRatioFor(G.femaleOpen.stage)
    G.femalePreg.nut = groupNutritionRatioFor(G.femalePreg.stage)
    G.male.nut       = groupNutritionRatioFor(G.male.stage)

    local function groupADG(dst)
        local f = PN_Core and PN_Core.adgFor
        if f then
            local okA, v = pcall(f, PN_Core, speciesResolved, dst.stage, dst.avgW, dst.nut)
            if okA and type(v)=="number" then return v end
        end
        local st = _getStage(speciesResolved, avgMonths, (dst == G.male) and "male" or "female")
        local a  = tonumber(st.baseADG or 0) or 0
        a = a * (dst.nut or 0)
        local meta = PN_Core.meta and PN_Core.meta[(speciesResolved or "COW"):upper()] or nil
        local mk = meta and tonumber(meta.matureKg) or nil
        if mk and mk > 0 and (dst.avgW or 0) > 0 then
            local frac = math.max(0, math.min(1, (dst.avgW or 0) / mk))
            local reserve = math.max(0.10, 1.0 - (frac ^ 1.6))
            a = a * reserve
        end
        return a
    end

    G.femaleOpen.adg = groupADG(G.femaleOpen)
    G.femalePreg.adg = groupADG(G.femalePreg)
    G.male.adg       = groupADG(G.male)

    entry.__pn_groups = {
        female = { -- alias of open
            n    = G.femaleOpen.n,
            avgW = G.femaleOpen.avgW,
            nut  = G.femaleOpen.nut,
            adg  = G.femaleOpen.adg,
            stage= G.femaleOpen.stage,
            preg = 0
        },
        femaleOpen = {
            n    = G.femaleOpen.n,
            avgW = G.femaleOpen.avgW,
            nut  = G.femaleOpen.nut,
            adg  = G.femaleOpen.adg,
            stage= G.femaleOpen.stage,
            preg = 0
        },
        femalePreg = {
            n    = G.femalePreg.n,
            avgW = G.femalePreg.avgW,
            nut  = G.femalePreg.nut,
            adg  = G.femalePreg.adg,
            stage= G.femalePreg.stage,
            preg = G.femalePreg.n
        },
        male = {
            n    = G.male.n,
            avgW = G.male.avgW,
            nut  = G.male.nut,
            adg  = G.male.adg,
            stage= G.male.stage,
            preg = 0
        }
    }

    -- 12) Optional: consume from trough levels (availability path)
    if PN_Core.autoConsume == true and reqDmBarn > 0 then
        local dmEaten
        if (N.dm or 0) > 0 then
            local scale = (dtH > 0) and (24 / dtH) or 0
            local dDay = N.dm * scale
            dmEaten = math.min(dDay * dayFrac, availDm)
        else
            dmEaten = math.min(nut * reqDmBarn, availDm)
        end
        if dmEaten and dmEaten > 0 then
            _consumeDmFromLevels(entry, levels, dmEaten, specHF)
        end
    end

    -- 13) Keep legacy snapshot (safe no-op if not used)
    pcall(_computeGroupSnapshots, entry, entry.__pn_totals)
end

-- -----------------------
-- Pretty line for pnBeat logging (single-line)
-- -----------------------
function PN_Core.formatBeatLine(entry)
    local t = entry and entry.__pn_totals or {}
    local name    = tostring(entry and entry.name or "?")
    local species = tostring(t.species or "COW"):upper()
    local head    = tonumber(t.animals or 0) or 0
    local bulls   = tonumber(t.bulls or 0) or 0
    local cows    = tonumber(t.cows or 0) or 0
    local preg    = tonumber(t.pregnant or 0) or 0
    local avgW    = _nfmt(t.avgWeight or 0, 2)
    local nutPct  = _nfmt((t.nut or 0) * 100, 1)
    local adg     = _nfmt(t.adg or 0, 3)
    local stage   = tostring(t.stage or "?")
    local gtxt    = tostring(t.gender or "?")
    return string.format("%s [%s/%s] | stage=%s | head=%d (M:%d / F:%d, preg=%d) avgW=%.2fkg | Nut=%.1f%% | ADG=%.3f kg/d",
        name, species, gtxt, stage, head, bulls, cows, preg, avgW, nutPct, adg)
end

-- -----------------------
-- Split lines for pnBeat (female/male) when present
-- -----------------------
function PN_Core.formatBeatLinesSplit(entry)
    local t = entry and entry.__pn_totals or {}
    local name    = tostring(entry and entry.name or "?")
    local species = tostring(t.species or "COW"):upper()
    local s = t.split or {}
    local F, M = s.female or {}, s.male or {}

    local function rounded(x, p)
        x = tonumber(x or 0) or 0
        local m = 10 ^ (p or 1)
        return math.floor(x * m + 0.5) / m
    end

    local function mkLine(label, G)
        if (G.head or 0) <= 0 then return nil end
        local avgW   = rounded(G.avgW or 0, 2)
        local nutPct = rounded((t.nut or 0) * 100, 1)
        local adg    = rounded(G.adg or 0, 3)
        local stage  = tostring(G.stage or "?")
        return string.format(
            "%s [%s/%s] | stage=%s | head=%d avgW=%.2fkg | Nut=%.1f%% | ADG=%.3f kg/d",
            name, species, label, stage, tonumber(G.head or 0), avgW, nutPct, adg
        )
    end

    local fLine = mkLine("female", F)
    local mLine = mkLine("male",   M)
    return fLine, mLine
end

-- -----------------------
-- Optional public: get last totals (for UI)
-- -----------------------
function PN_Core.getTotals(entry)
    return entry and entry.__pn_totals or {}
end

return PN_Core
