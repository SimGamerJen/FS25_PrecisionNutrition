-- scripts/PN_GrazingFeeder.lua
-- FS25_PrecisionNutrition: Pasture graze → buffer → trough (FS22-style)

PN_GrazingFeeder = PN_GrazingFeeder or {}

-- === Tuning (defaults) =====================================================
local CFG = {
  enabled           = true,
  outputFillType    = "GRASS_WINDROW",  -- what we add into the trough
  harvestChunkL     = 1500,             -- liters per harvest pass
  harvestMaxPerDayL = 15000,            -- daily cap per barn
  dripBootstrapPct  = 0.25,             -- jump to 25% if very low
  dripCeilPct       = 0.85,             -- never fill above this from grazing
  dripLph           = 1200,             -- liters per hour
  minTroughLowPct   = 0.05,             -- consider "low" below 5%
  safeFarmOnly      = true,             -- only operate on player's farm
  debug             = false
}

-- Merge overrides from PN_Settings (optional)
local function _mergeCfgFromSettings()
  if PN_Settings and PN_Settings.load then
    local ok, cfg = pcall(PN_Settings.load)
    if ok and type(cfg) == "table" and type(cfg.grazingFeeder) == "table" then
      for k, v in pairs(cfg.grazingFeeder) do
        if CFG[k] ~= nil then CFG[k] = v end
      end
    end
  end
end
_mergeCfgFromSettings()

-- === State per-barn ========================================================
local function _state(e)
  e.__pn_graze = e.__pn_graze or { bufferL=0, grazedToday=false, lastDay=nil, dailyHarvestedL=0 }
  return e.__pn_graze
end

-- === Helpers ===============================================================
local function _ftIndexByName(name)
  if g_fillTypeManager and g_fillTypeManager.getFillTypeIndexByName then
    return g_fillTypeManager:getFillTypeIndexByName(name)
  end; return nil
end

local function _farmIdOf(e)
  if e and e.farmId then return e.farmId end
  local p = e and e.placeable
  if p then
    if p.ownerFarmId then return p.ownerFarmId end
    if p.getOwnerFarmId then local ok,id=pcall(p.getOwnerFarmId,p); if ok then return id end end
  end
  return nil
end

local function _myFarmId()
  if g_currentMission and g_currentMission.player and g_currentMission.player.farmId then
    return g_currentMission.player.farmId
  end
  if g_farmManager and g_farmManager.getActiveFarmId then
    local ok,id = pcall(g_farmManager.getActiveFarmId,g_farmManager); if ok then return id end
  end
  return 1
end

local function _dayNumber()
  local env = g_currentMission and g_currentMission.environment
  local d = env and env.currentDay
  if type(d)=="number" then return d end
  return math.floor((os.time() or 0) / 86400)
end

-- Meadow liters across common specs (returns liters, specRef, grassIdx)
local function _meadowLitersAndSpec(p)
  if not p then return 0,nil,nil end
  local grassIdx = _ftIndexByName("GRASS_WINDROW") or _ftIndexByName("GRASS")
  local spec = p.spec_husbandryMeadow or p.spec_meadow or p.spec_husbandryPasture or p.spec_pasture
  if spec and grassIdx then
    if type(spec.fillLevels)=="table" then
      return (tonumber(spec.fillLevels[grassIdx] or 0) or 0), spec, grassIdx
    end
    if spec.fillTypeIndex==grassIdx and spec.fillLevel then
      return (tonumber(spec.fillLevel or 0) or 0), spec, grassIdx
    end
    if type(spec.getFillLevel)=="function" then
      local ok,L = pcall(spec.getFillLevel, spec, grassIdx)
      return (ok and (tonumber(L or 0) or 0) or 0), spec, grassIdx
    end
  end
  -- fallback: scan fillUnits
  local fu = p.spec_fillUnit
  if fu and type(fu.fillUnits)=="table" and grassIdx then
    local sum = 0
    for _,u in ipairs(fu.fillUnits) do
      local L = u.fillLevels and (tonumber(u.fillLevels[grassIdx] or 0) or 0) or 0
      sum = sum + L
    end
    if sum>0 then return sum, fu, grassIdx end
  end
  return 0, nil, grassIdx
end

-- Consume meadow liters if possible (best-effort). Returns liters actually taken.
local function _consumeMeadow(p, deltaL)
  if (deltaL or 0) <= 0 then return 0 end
  local L, spec, grassIdx = _meadowLitersAndSpec(p)
  if L <= 0 then return 0 end
  local take = math.min(L, deltaL)
  if spec and type(spec.fillLevels)=="table" then
    spec.fillLevels[grassIdx] = (tonumber(spec.fillLevels[grassIdx] or 0) or 0) - take
    return take
  end
  if spec and spec.fillTypeIndex==grassIdx and spec.fillLevel then
    spec.fillLevel = (tonumber(spec.fillLevel or 0) or 0) - take
    return take
  end
  local fu = p.spec_fillUnit
  if fu and type(fu.fillUnits)=="table" then
    local left = take
    for _,u in ipairs(fu.fillUnits) do
      if u.fillLevels and u.fillLevels[grassIdx] then
        local have = tonumber(u.fillLevels[grassIdx] or 0) or 0
        local d = math.min(have, left)
        u.fillLevels[grassIdx] = have - d
        left = left - d
        if left <= 0 then break end
      end
    end
    return take - math.max(0, left)
  end
  return 0
end

-- Trough totals for a fillType (liters, capacity, percent)
local function _getTroughInfo(p, fillTypeIdx)
  if not p then return 0,0,0 end
  local fu = p.spec_fillUnit
  local capSum, Lsum = 0, 0
  if fu and type(fu.fillUnits)=="table" then
    for _,u in ipairs(fu.fillUnits) do
      local allows = true
      if u.supportedFillTypes then allows = (u.supportedFillTypes[fillTypeIdx] == true) end
      if allows then
        local cap = tonumber(u.capacity or 0) or 0
        local L = (u.fillLevels and (tonumber(u.fillLevels[fillTypeIdx] or 0) or 0)) or 0
        capSum = capSum + cap
        Lsum  = Lsum + L
      end
    end
  end
  if capSum > 0 then return Lsum, capSum, (capSum>0 and (Lsum/capSum) or 0) end
  local hf = p.spec_husbandryFood
  if hf and type(hf.fillLevels)=="table" then
    local L = tonumber(hf.fillLevels[fillTypeIdx] or 0) or 0
    return L, 10000, (L / 10000)
  end
  return 0,0,0
end

-- Add liters to trough for a fillType (returns liters actually added)
local function _addToTrough(p, fillTypeIdx, liters)
  if (liters or 0) <= 0 then return 0 end
  local fu = p.spec_fillUnit
  local left = liters
  if fu and type(fu.fillUnits)=="table" then
    for _,u in ipairs(fu.fillUnits) do
      local allows = true
      if u.supportedFillTypes then allows = (u.supportedFillTypes[fillTypeIdx] == true) end
      if allows then
        local cap   = tonumber(u.capacity or 0) or 0
        local have  = (u.fillLevels and (tonumber(u.fillLevels[fillTypeIdx] or 0) or 0)) or 0
        local room  = math.max(0, cap - have)
        local add   = math.min(left, room)
        if add > 0 then
          u.fillLevels = u.fillLevels or {}
          u.fillLevels[fillTypeIdx] = have + add
          left = left - add
          if left <= 0 then break end
        end
      end
    end
    return liters - left
  end
  local hf = p.spec_husbandryFood
  if hf and type(hf.fillLevels)=="table" then
    hf.fillLevels[fillTypeIdx] = (tonumber(hf.fillLevels[fillTypeIdx] or 0) or 0) + liters
    return liters
  end
  return 0
end

-- One step for a barn (call hourly)
local function _stepBarn(e)
  if not CFG.enabled then return end
  local p = e and e.placeable; if not p then return end
  if CFG.safeFarmOnly then
    local fid = _farmIdOf(e)
    if fid ~= nil and fid ~= _myFarmId() then return end
  end

  local st = _state(e)
  local ftIdx = _ftIndexByName(CFG.outputFillType) or _ftIndexByName("GRASS_WINDROW")
  if not ftIdx then return end

  -- day reset
  local day = _dayNumber()
  if st.lastDay ~= day then
    st.lastDay, st.grazedToday, st.dailyHarvestedL = day, false, 0
    if CFG.debug then Logging.info("[PN:GrazingFeeder] day reset %s", tostring(e.name or "?")) end
  end

  local L, cap, pct = _getTroughInfo(p, ftIdx)
  if (pct >= CFG.dripCeilPct) and (st.bufferL <= 0) then return end

  -- harvest if low and not yet grazed today (or buffer empty)
  if (pct <= CFG.minTroughLowPct or st.bufferL <= 0) and (not st.grazedToday) then
    local meadowL = _meadowLitersAndSpec(p)
    meadowL = tonumber(meadowL or 0) or 0
    if meadowL > 0 and st.dailyHarvestedL < CFG.harvestMaxPerDayL then
      local need = math.min(CFG.harvestChunkL, CFG.harvestMaxPerDayL - st.dailyHarvestedL)
      local took = _consumeMeadow(p, need)
      if took > 0 then
        st.bufferL = st.bufferL + took
        st.dailyHarvestedL = st.dailyHarvestedL + took
        st.grazedToday = true
        if CFG.debug then Logging.info("[PN:GrazingFeeder] harvested %d L → buffer (%s)", took, tostring(e.name or "?")) end
      end
    end
  end

  if st.bufferL <= 0 then return end

  
  -- drip: replace fixed LPH with "make-up last hour's consumption"
  local add = 0
  local Lnow, C, P = _getTroughInfo(p, ftIdx)

  -- Track last trough liters to estimate consumption over the past hour
  st.lastTroughL = st.lastTroughL or Lnow
  local consumedLastHour = 0
  if st.lastTroughL and Lnow and (st.lastTroughL > Lnow) then
    consumedLastHour = st.lastTroughL - Lnow
  end

  -- Base plan: only add what was consumed last hour (prevents runaway increases)
  add = math.min(st.bufferL, consumedLastHour)

  -- If we're very low, allow a bootstrap up to target
  if P < CFG.dripBootstrapPct then
    local wantL = math.max(0, (CFG.dripBootstrapPct - P) * (C > 0 and C or 0))
    add = math.max(add, math.min(st.bufferL, wantL))
  end


  local roomToCeil = math.max(0, (CFG.dripCeilPct * (C>0 and C or 0)) - Lnow)
  add = math.min(add, roomToCeil)

  if add > 0 then
    local added = _addToTrough(p, ftIdx, add)
    st.bufferL = st.bufferL - added
    if CFG.debug then Logging.info("[PN:GrazingFeeder] +%d L → trough (%s); buffer=%d L", added, tostring(e.name or "?"), st.bufferL) end
  end
  -- Update lastTroughL at the end of step
  do
    local La,_,_ = _getTroughInfo(p, ftIdx)
    st.lastTroughL = La
  end

end

-- === Public API =============================================================
function PN_GrazingFeeder.onHourChanged()
  if not PN_HusbandryScan or not PN_HusbandryScan.getAll then return end
  if not CFG.enabled then return end
  for _, e in ipairs(PN_HusbandryScan.getAll() or {}) do _stepBarn(e) end
end

function PN_GrazingFeeder:cmdGraze(args, ...)
  local sub = tostring(args or "status"):lower()
  if sub=="on"  then CFG.enabled=true;  Logging.info("[PN:GrazingFeeder] enabled")
  elseif sub=="off" then CFG.enabled=false; Logging.info("[PN:GrazingFeeder] disabled")
  elseif sub=="debug" then
    local v = tostring(select(1, ...) or "")
    CFG.debug = (v=="1" or v=="true" or v=="on")
    Logging.info("[PN:GrazingFeeder] debug=%s", tostring(CFG.debug))
  elseif sub=="status" then
    if not PN_HusbandryScan or not PN_HusbandryScan.getAll then return end
    for _, e in ipairs(PN_HusbandryScan.getAll() or {}) do
      local st = _state(e)
      Logging.info("[PN:GrazingFeeder] %s: buffer=%d L, dailyHarvested=%d L, grazedToday=%s",
        tostring(e.name or "?"), st.bufferL, st.dailyHarvestedL, tostring(st.grazedToday))
    end
  else
    Logging.info("[PN:GrazingFeeder] Usage: pnGraze on|off|debug <0|1>|status")
  end
end



-- Expose a copy of the merged runtime configuration
function PN_GrazingFeeder.getCfg()
  local t = {}
  for k,v in pairs(CFG) do t[k]=v end
  return t
end

return PN_GrazingFeeder