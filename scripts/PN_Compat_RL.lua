-- PN_Compat_RL.lua — single source of truth for RL detection + safe calls
CompatRL = {
  -- persistent registries so bindings survive fresh PN lists
  handlesByPid = {},
  handlesByHid = {},
  hasRL = false,
  caps  = {
    addWeightKg=false, addWeightForDay=false, addHealthDelta=false,
    setReproductionRateFactor=false, setProductionFactor=false
  },
  rl    = nil
}

local function _getModByName(name)
  if g_modManager and g_modManager.getModByName then
    local ok, mod = pcall(g_modManager.getModByName, g_modManager, name)
    if ok and mod ~= nil then return mod end
  end
  return nil
end

function CompatRL:init()
  -- detect by global handle and/or mod folder names
  local byGlobal = rawget(_G, "RealisticLivestock")
  local byName   = _getModByName("FS25_RealisticLivestock")
                 or _getModByName("RealisticLivestock")
                 or _getModByName("RL")

  self.hasRL = (byGlobal ~= nil) or (byName ~= nil)
  self.rl    = byGlobal

  if self.hasRL then
    Logging.info("[PN] Realistic Livestock detected. PN enabled.")
  else
    Logging.error("[PN] Realistic Livestock NOT found. PrecisionNutrition will be disabled.")
  end
end

-- ===== Binding & indexing =====================================================

-- Extract ids from an RL handle (cluster husbandry)
function CompatRL:_extractIdsFromHandle(h)
  if type(h) ~= "table" then return nil, nil end
  local hid = rawget(h, "husbandryId") or rawget(h, "id")
  local pid = rawget(h, "placeableId") or rawget(h, "owningPlaceableId")
  local pl  = rawget(h, "placeable") or rawget(h, "husbandryPlaceable")
  if pid == nil and type(pl)=="table" then
    pid = rawget(pl, "id") or rawget(pl, "owningPlaceableId")
  end
  return hid, pid
end

-- Build fast lookup maps from RL husbandrySystem
function CompatRL:_indexRLClusters()
  local hs = g_currentMission and g_currentMission.husbandrySystem
  local map = { byHid = {}, byPid = {} }
  if not hs then return map end

  local function addEntry(hid, pid, handle)
    if hid ~= nil then map.byHid[hid] = handle end
    if pid ~= nil then map.byPid[pid] = handle end
  end

  local function tryCluster(handle)
    if type(handle) ~= "table" then return end
    local hid, pid = self:_extractIdsFromHandle(handle)
    addEntry(hid, pid, handle)
  end

  -- Common buckets to scan
  for _, key in ipairs({"clusterHusbandries", "clusters", "husbandries", "byId", "byPlaceableId"}) do
    local t = rawget(hs, key)
    if type(t) == "table" then
      for _, v in pairs(t) do
        tryCluster(v)
        if type(v) == "table" then
          for _, v2 in pairs(v) do
            tryCluster(v2)
          end
        end
      end
    end
  end
  return map
end

-- Bind RL handles (ClusterHusbandry) onto each PN barn entry
function CompatRL:bindBarnHandles(barnList)
  if not self.hasRL or barnList == nil then return 0 end
  local hs = g_currentMission and g_currentMission.husbandrySystem
  if hs == nil then
    Logging.error("[PN] RL bind: g_currentMission.husbandrySystem missing")
    return 0
  end
  local getById = hs.getClusterHusbandryById
  local index = self:_indexRLClusters()

  local function tryBind(barn)
    -- Try explicit ids first
    local hid = barn and (barn.husbandryId or barn.id) or nil
    if getById and type(getById)=="function" and hid ~= nil then
      local ok, res = pcall(getById, hs, hid)
      if ok and res ~= nil then return res end
    end
    -- Try our index by husbandryId
    if hid ~= nil and index.byHid[hid] then return index.byHid[hid] end

    -- Try by placeable id
    local pid = nil
    if barn and barn.placeable then pid = barn.placeable.id or barn.placeable.owningPlaceableId end
    if pid ~= nil then
      if index.byPid[pid] then return index.byPid[pid] end
      -- As a last resort, scan again looking for matching placeable pointer
      for _, h in pairs(index.byPid) do
        local pl = rawget(h, "placeable") or rawget(h, "husbandryPlaceable")
        if pl and (pl == barn.placeable) then return h end
      end
    end

    -- Fallback: some placeables expose getClusterHusbandry()
    if barn and barn.placeable and type(barn.placeable.getClusterHusbandry)=="function" then
      local ok, res = pcall(barn.placeable.getClusterHusbandry, barn.placeable)
      if ok and res ~= nil then return res end
    end

    return nil
  end

  local bound, total = 0, #barnList
  for _, barn in ipairs(barnList) do
    if barn.rl ~= nil then
      bound = bound + 1
    else
      local h = tryBind(barn)
      if h ~= nil then
        barn.rl = h
        local hid, pid = self:_extractIdsFromHandle(h)
        if pid ~= nil then self.handlesByPid[pid] = h end
        if hid ~= nil then self.handlesByHid[hid] = h end
        bound = bound + 1
      else
        local name = barn and (barn.title or barn.name) or "?"
        Logging.info(string.format("[PN] RL bind: no handle for %s (id=%s hid=%s pid=%s)",
          tostring(name), tostring(barn and barn.id or "nil"),
          tostring(barn and barn.husbandryId or "nil"),
          tostring(barn and barn.placeable and (barn.placeable.id or barn.placeable.owningPlaceableId) or "nil")))
      end
    end
  end
  Logging.info(string.format("[PN] CompatRL bound RL handles for %d/%d barns.", bound, total))
  return bound
end

-- Return an RL handle for a PN barn (checks cache + registries)
function CompatRL:getHandleForBarn(barn)
  if not barn then return nil end
  if barn.rl ~= nil then return barn.rl end
  local pid = barn.placeable and (barn.placeable.id or barn.placeable.owningPlaceableId)
  if pid and self.handlesByPid[pid] then return self.handlesByPid[pid] end
  local hid = barn.husbandryId or barn.id
  if hid and self.handlesByHid[hid] then return self.handlesByHid[hid] end
  return nil
end

-- ===== Capability detection & wrappers =======================================

-- Resolve capabilities from a specific RL handle (cluster husbandry) and cache minimal caps
function CompatRL:_resolveCapsFromHandle(h)
  if type(h) ~= "table" then return end
  -- Include metatable __index lookups
  local mt = getmetatable(h)
  local idx = mt and mt.__index or nil
  local function has(name)
    local v = h[name]
    if v == nil and type(idx)=="table" then v = idx[name] end
    return type(v)=="function"
  end
  self.caps.addWeightKg = self.caps.addWeightKg or has("addWeightKg")
  self.caps.addWeightForDay = self.caps.addWeightForDay or has("addWeightForDay") or has("setDailyGainFactor")
  self.caps.addHealthDelta = self.caps.addHealthDelta or has("addHealthDelta") or has("addHealth") or has("setHealthDelta")
  self.caps.setReproductionRateFactor = self.caps.setReproductionRateFactor or has("setReproductionRateFactor") or has("setFertilityFactor")
  self.caps.setProductionFactor = self.caps.setProductionFactor or has("setProductionFactor") or has("setMilkFactor") or has("setYieldFactor")
end

-- Helper to choose a handle (prefer bound barn.rl, else registry, else global)
local function _pickHandle(self, barn)
  local h = (barn and (barn.rl or self:getHandleForBarn(barn))) or self.rl
  if h then CompatRL:_resolveCapsFromHandle(h) end
  return h
end

function CompatRL:addHealth(barn, dH)
  if not self.hasRL or not dH then return false end
  local h = _pickHandle(self, barn);  -- keep capability detection
  -- try handle methods first (if any were found)
  local mt = h and getmetatable(h); local idx = mt and mt.__index or nil
  local f = h and (h.addHealthDelta or (type(idx)=="table" and idx.addHealthDelta))
  if type(f)=="function" then f(h, dH); return true end
  f = h and (h.addHealth or (type(idx)=="table" and idx.addHealth))
  if type(f)=="function" then f(h, dH); return true end
  f = h and (h.setHealthDelta or (type(idx)=="table" and idx.setHealthDelta))
  if type(f)=="function" then f(h, dH); return true end
  -- fallback: edit animal health directly
  return self:_animalAddHealth(barn, dH)
end

function CompatRL:setReproFactor(barn, f)
  if not self.hasRL or not f then return false end
  local h = _pickHandle(self, barn)
  local mt = h and getmetatable(h); local idx = mt and mt.__index or nil
  local fn = h and (h.setReproductionRateFactor or (type(idx)=="table" and idx.setReproductionRateFactor))
  if type(fn)=="function" then fn(h, f); return true end
  fn = h and (h.setFertilityFactor or (type(idx)=="table" and idx.setFertilityFactor))
  if type(fn)=="function" then fn(h, f); return true end
  -- fallback: nudge per-animal reproduction gauge
  return self:_animalSetReproFactor(barn, f)
end

function CompatRL:addWeight(barn, valueOrFactor)
  if not self.hasRL then return false end
  local h = _pickHandle(self, barn)
  local mt = h and getmetatable(h); local idx = mt and mt.__index or nil
  local f = h and (h.addWeightForDay or (type(idx)=="table" and idx.addWeightForDay))
  if type(f)=="function" then f(h, valueOrFactor); return true end
  f = h and (h.setDailyGainFactor or (type(idx)=="table" and idx.setDailyGainFactor))
  if type(f)=="function" then f(h, valueOrFactor); return true end
  f = h and (h.addWeightKg or (type(idx)=="table" and idx.addWeightKg))
  if type(f)=="function" then f(h, valueOrFactor); return true end
  -- fallback: tiny direct weight nudge
  return self:_animalAddWeight(barn, valueOrFactor)
end

function CompatRL:setProductionFactor(barn, f)
  if not self.hasRL or not f then return false end
  local h = _pickHandle(self, barn); if not h then return false end
  local mt = getmetatable(h); local idx = mt and mt.__index or nil
  local fn = h["setProductionFactor"]; if fn == nil and type(idx)=="table" then fn = idx["setProductionFactor"] end
  if type(fn)=="function" then fn(h, f); return true end
  fn = h["setMilkFactor"]; if fn == nil and type(idx)=="table" then fn = idx["setMilkFactor"] end
  if type(fn)=="function" then fn(h, f); return true end
  fn = h["setYieldFactor"]; if fn == nil and type(idx)=="table" then fn = idx["setYieldFactor"] end
  if type(fn)=="function" then fn(h, f); return true end
  return false
end

-- Walk animals for a PN barn. Returns number visited.
function CompatRL:_forEachAnimal(barn, fn)
  local h = self:getHandleForBarn(barn)
  if not h then return 0 end

  local visited = 0

  -- Common RL layouts we saw in your build:
  --  • h.animalIdToCluster[husbandryId][animalId] = Animal
  --  • h.clusters[...] = { animals = { Animal, ... } }   (some maps store arrays)
  local function visitAnimal(a)
    if type(a) == "table" then
      local mt = getmetatable(a)
      if mt ~= nil then visited = visited + 1; fn(a) end
    end
  end

  -- 1) animalIdToCluster: { [hid] = { [animalId] = Animal } }
  local a2c = rawget(h, "animalIdToCluster")
  if type(a2c) == "table" then
    for _, animals in pairs(a2c) do
      if type(animals) == "table" then
        for _, animal in pairs(animals) do visitAnimal(animal) end
      end
    end
  end

  -- 2) clusters[...] -> animals array
  local clusters = rawget(h, "clusters") or rawget(h, "nextUpdateClusters")
  if type(clusters) == "table" then
    for _, c in pairs(clusters) do
      local arr = type(c)=="table" and (rawget(c, "animals") or rawget(c, "list") or rawget(c, "entries"))
      if type(arr) == "table" then
        for _, animal in pairs(arr) do visitAnimal(animal) end
      end
    end
  end

  return visited
end

-- Fallbacks if no handle methods exist:
function CompatRL:_animalAddHealth(barn, dH)
  if not dH or dH == 0 then return false end
  local changed = 0
  self:_forEachAnimal(barn, function(a)
    -- health is 0..100 in RL Animal; we saw updateHealth applying a delta internally.
    local hval = rawget(a, "health")
    if type(hval) == "number" then
      local newH = math.max(0, math.min(100, math.floor(hval + dH)))
      rawset(a, "health", newH)
      changed = changed + 1
    end
  end)
  return changed > 0
end

function CompatRL:_animalSetReproFactor(barn, f)
  if not f then return false end
  -- Map factor (0.5..1.25) to a small per-day delta in RL’s 0..100 reproduction gauge.
  -- A gentle mapping: delta = (f-1.0)*2 (i.e., ±2 points/day at ±0.5 swing).
  local delta = math.floor((f - 1.0) * 2.0 + 0.5)
  if delta == 0 then return false end
  local changed = 0
  self:_forEachAnimal(barn, function(a)
    -- Prefer Animal:changeReproduction(delta) if present (method may live on metatable).
    local fn = a.changeReproduction
    if not fn then
      local mt = getmetatable(a); local idx = mt and mt.__index
      if type(idx) == "table" then fn = idx.changeReproduction end
    end
    if type(fn) == "function" then
      fn(a, delta)
      changed = changed + 1
    else
      -- Direct edit as a last resort
      local r = rawget(a, "reproduction")
      if type(r) == "number" then
        local newR = math.max(0, math.min(100, math.floor(r + delta)))
        rawset(a, "reproduction", newR)
        changed = changed + 1
      end
    end
  end)
  return changed > 0
end

function CompatRL:_animalAddWeight(barn, factor)
  if not factor or factor == 1 then return false end
  -- Translate FG (e.g., 1.10) into a gentle kg delta: +/−0.2% of current weight.
  local changed = 0
  self:_forEachAnimal(barn, function(a)
    local cur = rawget(a, "weight")
    if type(cur) == "number" then
      local kg = cur * (factor - 1.0) * 0.002
      if kg ~= 0 then
        rawset(a, "weight", math.max(0, cur + kg))
        changed = changed + 1
      end
    end
  end)
  return changed > 0
end

return CompatRL
