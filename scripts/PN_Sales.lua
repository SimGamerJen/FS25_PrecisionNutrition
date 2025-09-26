-- scripts/PN_Sales.lua
PN_Sales = PN_Sales or {}

--------------------------------------------------------------------------------
-- Settings helpers
--------------------------------------------------------------------------------
local DEFAULT_SALE = { overagePenaltyPerMonth = 0, overagePenaltyFloor = 1.0 }

local function _getMeta(species)
  local m = PN_Settings and PN_Settings.meta and PN_Settings.meta[species]
  if not m then
    return { overageM = 1e9, overageSnr = 1e9, sale = DEFAULT_SALE }
  end
  m.sale = m.sale or DEFAULT_SALE
  m.sale.overagePenaltyPerMonth = tonumber(m.sale.overagePenaltyPerMonth or 0) or 0
  m.sale.overagePenaltyFloor    = tonumber(m.sale.overagePenaltyFloor    or 1) or 1
  m.overageM   = tonumber(m.overageM   or 1e9) or 1e9
  m.overageSnr = tonumber(m.overageSnr or 1e9) or 1e9
  return m
end

local function _priceFactorForAnimal(species, gender, isCast, ageM)
  local meta  = _getMeta(species)
  local per   = meta.sale.overagePenaltyPerMonth
  local floor = meta.sale.overagePenaltyFloor
  local overM = meta.overageM
  local snrM  = meta.overageSnr
  local a     = tonumber(ageM or 0) or 0

  local monthsOver = 0
  if gender == "male" and isCast then
    monthsOver = math.max(0, a - overM)
  elseif gender == "female" then
    monthsOver = math.max(0, a - snrM)
  else
    return 1.0
  end

  if monthsOver <= 0 or per <= 0 then return 1.0 end
  local f = 1.0 - per * monthsOver
  if floor then f = math.max(f, floor) end
  return f
end

--------------------------------------------------------------------------------
-- Snapshot building (on-demand, inside the money hook)
--------------------------------------------------------------------------------
local function _barnId(entry)
  return entry and (entry.id or entry.uniqueId or entry.name or tostring(entry))
end

local function _summarizeEntry(entry)
  -- Summarize by species using the latest __pn_last.animals
  local out = {}
  local animals = entry and entry.__pn_last and entry.__pn_last.animals or {}
  if type(animals) ~= "table" then return out end

  local speciesOfEntry = tostring(entry.species or "ANIMAL"):upper()
  for _, a in ipairs(animals) do
    local sp = tostring(a.species or speciesOfEntry):upper()
    local row = out[sp] or { head=0, maleCast=0, female=0, maleCastOver=0, femaleOver=0 }
    local meta = _getMeta(sp)
    local overM, snrM = meta.overageM, meta.overageSnr

    local head   = tonumber(a.head or a.count or 0) or 0
    local g      = tostring(a.gender or ""):lower()
    local flags  = a.flags or a
    local isCast = (flags and (flags.castrated or flags.isCast)) and true or false
    local age    = tonumber(a.ageM or a.ageMonths or 0) or 0

    row.head = row.head + head
    if g == "female" then
      row.female = row.female + head
      if age >= snrM then row.femaleOver = row.femaleOver + head end
    elseif g == "male" and isCast then
      row.maleCast = row.maleCast + head
      if age >= overM then row.maleCastOver = row.maleCastOver + head end
    end

    out[sp] = row
  end
  return out
end

local function _buildSnapshot()
  local byBarn = {}
  if not PN_HusbandryScan or not PN_HusbandryScan.getAll then return byBarn end
  local list = PN_HusbandryScan.getAll()
  for _, e in ipairs(list) do
    local cs = e.clusterSystem
    if PN_Core and PN_Core.updateHusbandry and cs ~= nil then
      -- Ensure __pn_last is fresh *right now*
      pcall(PN_Core.updateHusbandry, PN_Core, e, cs, 0, {})
    end
    local bid = _barnId(e)
    if bid then
      byBarn[bid] = _summarizeEntry(e)
    end
  end
  return byBarn
end

--------------------------------------------------------------------------------
-- Sale detection + factor
--------------------------------------------------------------------------------
local function _findLikelySale(pre, post, species)
  -- returns (barnId, soldHead, fracMaleCastOver, fracFemaleOver) or nil
  local best, bestDrop = nil, 0
  for barnId, specA in pairs(pre or {}) do
    local a = specA[species]
    local b = post and post[barnId] and post[barnId][species]
    if a and b then
      local drop = (a.head or 0) - (b.head or 0)
      if drop > bestDrop then best, bestDrop = barnId, drop end
    end
  end
  if not best or bestDrop <= 0 then return nil end
  local a = pre[best][species]
  local b = post[best][species]
  local sold = (a.head or 0) - (b.head or 0)
  if sold <= 0 then return nil end

  local fOver = (a.femaleOver or 0);     local fAll = (a.female or 0)
  local mOver = (a.maleCastOver or 0);   local mAll = (a.maleCast or 0)
  local fracFOver = (fAll > 0) and (fOver / fAll) or 0
  local fracMOver = (mAll > 0) and (mOver / mAll) or 0
  return best, sold, fracMOver, fracFOver
end

local function _computeRowFactor(species, fracMOver, fracFOver)
  -- Safe approximation: use the species' overage floors for the over-age fractions.
  local fFinish = _priceFactorForAnimal(species, "male",   true,  1e9)  -- → floor
  local fSenior = _priceFactorForAnimal(species, "female", false, 1e9)  -- → floor
  local factor  = (1 - fracMOver) * 1.0 + fracMOver * fFinish
  factor        = factor * ((1 - fracFOver) * 1.0 + fracFOver * fSenior)
  return factor
end

--------------------------------------------------------------------------------
-- Hook g_currentMission.addMoney (no RL edits required)
--------------------------------------------------------------------------------
local _origAddMoney

function PN_Sales.initHook()
  if _origAddMoney ~= nil then return end
  local mission = g_currentMission
  if not mission or not mission.addMoney then return end

  _origAddMoney = mission.addMoney
  mission.addMoney = function(mis, amount, farmId, moneyType, silent, noEventSend)
    -- Only consider positive animal-sale payouts
    local isAnimalSale = (moneyType == (MoneyType and MoneyType.ANIMAL_SALES or moneyType))
    if isAnimalSale and amount and amount > 0 then
      -- Build a fresh "pre" snapshot, call the original, then "post" snapshot
      local pre  = _buildSnapshot()
      local res  = _origAddMoney(mis, amount, farmId, moneyType, silent, noEventSend)
      local post = _buildSnapshot()

      -- Try each species; adjust once on the first clear drop we find
      local speciesList = { "COW","SHEEP","PIG","GOAT","CHICKEN","HORSE" }
      for _, sp in ipairs(speciesList) do
        local barnId, sold, fracM, fracF = _findLikelySale(pre, post, sp)
        if barnId and sold and sold > 0 then
          local rlSubtotal = math.max(0, math.floor(amount))
          local factor     = _computeRowFactor(sp, fracM, fracF)
          if factor and factor ~= 1 then
            local target = math.floor(rlSubtotal * factor + 0.5)
            local delta  = target - rlSubtotal
            if delta ~= 0 then
              _origAddMoney(mis, delta, farmId, moneyType, false, noEventSend)
              if PN_Settings and PN_Settings.debug and PN_Settings.debug.saleAdjust then
                Logging.info("[PN] Sale adjust: barn=%s species=%s sold≈%d rl=%d factor=%.3f delta=%+d",
                  tostring(barnId), sp, sold, rlSubtotal, factor, delta)
              end
            end
          end
          break
        end
      end
      return res
    else
      return _origAddMoney(mis, amount, farmId, moneyType, silent, noEventSend)
    end
  end

  if PN_Settings and PN_Settings.debug then
    Logging.info("[PN] PN_Sales: addMoney hook installed (ANIMAL_SALES).")
  end
end

return PN_Sales
