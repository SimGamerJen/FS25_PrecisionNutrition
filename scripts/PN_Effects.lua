-- PN_Effects.lua — Nut → outcomes, routed through CompatRL; inert if RL missing
PN_Effects = {
  enabled = true,
  windowDays = 3,
  barnNut = {}, -- barnId -> {samples={}, sum=0, idx=1, n=0}
  cfg = {
    growthMin=0.25, growthMax=1.20,
    healthUnderSlope=6, healthRecSlope=3, minNut=0.70, recNut=0.95,
    reproBase=0.50, reproK=0.75, reproMin=0.50, reproMax=1.25,
    prodBase=0.40, prodK=0.60, prodMin=0.40, prodMax=1.10
  },
}

-- Rolling average of Nut over a small window to smooth spikes
local function rollingAvg(self, barnId, nutSample, maxSamples)
  local t = self.barnNut[barnId]
  if t == nil then t = {samples={}, sum=0, idx=1, n=0}; self.barnNut[barnId]=t end
  if maxSamples <= 0 then return nutSample end
  if t.n < maxSamples then
    t.samples[t.idx] = nutSample; t.sum = t.sum + nutSample; t.idx = t.idx + 1; t.n = t.n + 1
  else
    local old = t.samples[t.idx] or 0
    t.samples[t.idx] = nutSample
    t.sum = t.sum - old + nutSample
    t.idx = (t.idx % maxSamples) + 1
  end
  return t.sum / t.n
end

-- Map nutrition → growth factor
local function mapGrowth(cfg, N)
  N = math.min(math.max(N, 0.0), 1.2)
  if N <= 0.60 then
    return math.max(cfg.growthMin, 0.25 + 1.25*(N/0.60))
  elseif N < 1.00 then
    return 0.75 + 0.625*((N-0.60)/0.40)
  else
    return math.min(cfg.growthMax, 1.00 + 0.20*((math.min(N,1.20)-1.00)/0.20))
  end
end

-- Map nutrition → daily health delta
local function mapHealthDelta(cfg, N)
  if N < cfg.minNut then
    return - (cfg.minNut - N) * cfg.healthUnderSlope  -- health/day
  elseif N > cfg.recNut then
    return   (N - cfg.recNut) * cfg.healthRecSlope
  end
  return 0
end

-- Map nutrition → reproduction factor
local function mapRepro(cfg, N)
  local f = cfg.reproBase + cfg.reproK * N
  return math.max(cfg.reproMin, math.min(cfg.reproMax, f))
end

-- Map nutrition → production factor (kept conservative)
local function mapProduction(cfg, N)
  local f = cfg.prodBase + cfg.prodK * N
  return math.max(cfg.prodMin, math.min(cfg.prodMax, f))
end

-- Called once per in-game day (wired from PN_Load)
function PN_Effects:onDayTick(dayDt)
  if not self.enabled then return end
  if not (rawget(_G, "CompatRL") and CompatRL.hasRL) then return end

  local list = PN_Core and PN_Core.husbandries or (PN_HusbandryScan and PN_HusbandryScan.getAll and PN_HusbandryScan.getAll()) or {}
  for barnId, barn in pairs(list) do
    local id = barnId
    if type(barnId) ~= "number" and barn and (barn.id or barn.husbandryId) then id = barn.id or barn.husbandryId end
    local N = PN_Metrics and PN_Metrics.getNutForBarn and PN_Metrics:getNutForBarn(id) or 0.6
    local Nbar = rollingAvg(self, id, N, self.windowDays)

    local FG = mapGrowth(self.cfg, Nbar)
    local dH = mapHealthDelta(self.cfg, Nbar)
    local FR = mapRepro(self.cfg, Nbar)
    local FP = mapProduction(self.cfg, Nbar)

    self:applyEffects(barn, FG, dH, FR, FP, dayDt)
  end
end

-- Apply the mapped effects via RL (with gentle guards)
function PN_Effects:applyEffects(barn, FG, dH, FR, FP, dayDt)
  local clamp = function(x,min,max) return math.max(min, math.min(max, x)) end
  FG = clamp(FG or 1.0, 0.60, 1.50)
  dH = clamp(dH or 0.0, -5.0, 5.0)
  FR = clamp(FR or 1.0, 0.50, 1.25)
  FP = clamp(FP or 1.0, 0.40, 1.10)

  if FG and FG ~= 1.0 then CompatRL:addWeight(barn, FG) end
  if dH and dH ~= 0   then CompatRL:addHealth(barn, dH) end
  if FR and FR ~= 1.0 then CompatRL:setReproFactor(barn, FR) end
  -- NOTE: Production is routed only if RL exposes a safe knob; CompatRL will no-op otherwise.
  if FP and FP ~= 1.0 then CompatRL:setProductionFactor(barn, FP) end
end

-- === Console helpers (dev/debug) ============================================
function PN_Effects:_computePreview(barnId)
  local N = PN_Metrics and PN_Metrics.getNutForBarn and PN_Metrics:getNutForBarn(barnId) or 0.6
  local Nbar = N
  local t = self.barnNut[barnId]
  if t and t.n and t.n > 0 then Nbar = t.sum / t.n end
  local FG = mapGrowth(self.cfg, Nbar)
  local dH = mapHealthDelta(self.cfg, Nbar)
  local FR = mapRepro(self.cfg, Nbar)
  local FP = mapProduction(self.cfg, Nbar)
  return N, Nbar, FG, dH, FR, FP
end

function PN_Effects:printInfo()
  -- Pre-resolve caps from any bound handle so header reflects reality
  local listPeek = PN_HusbandryScan and PN_HusbandryScan.getAll and PN_HusbandryScan.getAll() or {}
  for _, b in ipairs(listPeek) do
    local h = (CompatRL and CompatRL.getHandleForBarn and CompatRL:getHandleForBarn(b))
    if h and CompatRL and CompatRL._resolveCapsFromHandle then
      CompatRL:_resolveCapsFromHandle(h)
      break
    end
  end

  local caps = CompatRL and CompatRL.caps or {}

  -- Detect if fallbacks are armed (animals reachable)
  local fallback = { weight=false, health=false, repro=false, prod=false }
  local tryList = PN_HusbandryScan and PN_HusbandryScan.getAll and PN_HusbandryScan.getAll() or {}
  for _, b in ipairs(tryList) do
    if CompatRL and CompatRL._forEachAnimal then
      local seen = CompatRL:_forEachAnimal(b, function() end)
      if seen and seen > 0 then
        fallback.weight = true
        fallback.health = true
        fallback.repro  = true
        break
      end
    end
  end

  print(("[PN] Effects info — RL hooks  growthKg:%s  growthDay:%s  health:%s  repro:%s  prod:%s  |  fallbacks  W:%s H:%s R:%s P:%s")
    :format(tostring(caps.addWeightKg), tostring(caps.addWeightForDay),
            tostring(caps.addHealthDelta), tostring(caps.setReproductionRateFactor),
            tostring(caps.setProductionFactor),
            fallback.weight and "yes" or "no",
            fallback.health and "yes" or "no",
            fallback.repro  and "yes" or "no",
            fallback.prod   and "yes" or "no"))

  local list = PN_HusbandryScan and PN_HusbandryScan.getAll and PN_HusbandryScan.getAll() or {}
  for _, barn in ipairs(list) do
    local barnId = barn.id or barn.husbandryId or "unknown"
    local title = barn.title or barn.name or ("Barn#" .. tostring(barnId))
    local rlBound = (CompatRL and CompatRL.getHandleForBarn and CompatRL:getHandleForBarn(barn)) ~= nil
    local N, Nbar, FG, dH, FR, FP = self:_computePreview(barnId)
    local pid = barn.placeable and (barn.placeable.id or barn.placeable.owningPlaceableId) or "p?"
    print(("[PN] %-24s | id:%s pid:%s rl:%s | N:%.2f  Nbar:%.2f  FG:%.2f  dH:%+.2f  FR:%.2f  FP:%.2f")
      :format(title, tostring(barnId), tostring(pid), rlBound and "yes" or "no", N, Nbar, FG, dH, FR, FP))
  end
end

-- Dump first N animals' stats for a barn
function PN_Effects:_peekBarn(barn, limit)
  limit = math.max(1, tonumber(limit or 5) or 5)
  if not (CompatRL and CompatRL._forEachAnimal) then
    print("[PN] No animal iterator available."); return
  end
  local shown, total = 0, 0
  total = CompatRL:_forEachAnimal(barn, function(_) end)

  CompatRL:_forEachAnimal(barn, function(a)
    if shown < limit then
      local w = rawget(a, "weight")
      local h = rawget(a, "health")
      local r = rawget(a, "reproduction") or rawget(a, "fertility") or rawget(a, "fertilityLevel")
      print(string.format("    #%02d  weight:%s  health:%s  repro:%s",
        shown+1, tostring(w or "?"), tostring(h or "?"), tostring(r or "?")))
      shown = shown + 1
    end
  end)
  print(string.format("    (showing %d of ~%d animals)", shown, total))
end

-- Apply current PN effects to a barn once (optionally scaled up for visibility)
function PN_Effects:_applyOnce(barn, scale)
  scale = tonumber(scale or 1) or 1
  local barnId = barn.id or barn.husbandryId
  local N, Nbar, FG, dH, FR, FP = self:_computePreview(barnId)

  -- Scale for testing (kept within guards)
  local clamp = function(x,min,max) return math.max(min, math.min(max, x)) end
  FG = clamp(1.0 + (FG - 1.0) * scale, 0.60, 1.50)
  dH = clamp((dH or 0) * scale,       -5.0, 5.0)
  FR = clamp(1.0 + (FR - 1.0) * scale, 0.50, 1.25)
  FP = clamp(1.0 + (FP - 1.0) * scale, 0.40, 1.10)

  self:applyEffects(barn, FG, dH, FR, FP, 1.0)
  print(string.format("[PN] applyOnce(x%.1f) → FG=%.2f  dH=%+.2f  FR=%.2f  FP=%.2f", scale, FG, dH, FR, FP))
end

function PN_Effects:consoleCommand(arg1, ...)
  local sub = tostring(arg1 or ""):match("^%s*(%S*)$")

  if sub == "" or sub == "info" then
    if self.printInfo then self:printInfo() end
    return ""

  elseif sub == "bind" then
    local list = PN_HusbandryScan and PN_HusbandryScan.getAll and PN_HusbandryScan.getAll() or {}
    if CompatRL and CompatRL.hasRL then
      local n = CompatRL:bindBarnHandles(list)
      print("[PN] bindBarnHandles(): bound "..tostring(n).." barns")
    else
      print("[PN] RL not detected; cannot bind.")
    end
    if self.printInfo then self:printInfo() end
    return ""

  elseif sub == "dumpHS" then
    local hs = g_currentMission and g_currentMission.husbandrySystem
    if not hs then print("[PN] No husbandrySystem"); return "" end
    print("[PN] husbandrySystem keys:")
    for k,v in pairs(hs) do print("  -", k, type(v)) end
    return ""

  elseif sub == "probe" then
    local function has(h, name)
      if not h then return false end
      local mt = getmetatable(h); local idx = mt and mt.__index or nil
      local v = h[name]
      if v == nil and type(idx)=="table" then v = idx[name] end
      return type(v)=="function"
    end
    local candidates = {
      "addWeightForDay","setDailyGainFactor","addWeightKg",
      "addHealthDelta","addHealth","setHealthDelta",
      "setReproductionRateFactor","setFertilityFactor",
      "setProductionFactor","setMilkFactor","setYieldFactor"
    }
    local list = PN_HusbandryScan and PN_HusbandryScan.getAll and PN_HusbandryScan.getAll() or {}
    for _, barn in ipairs(list) do
      local title = barn.title or barn.name or tostring(barn.id or barn.husbandryId or "?")
      local h = (CompatRL and CompatRL.getHandleForBarn and CompatRL:getHandleForBarn(barn))
      print(("[PN] Probe %s — rl:%s"):format(title, h and "yes" or "no"))
      -- Count animals reachable via CompatRL helper (for sanity check)
      local seen = 0
      if CompatRL and CompatRL._forEachAnimal then
        seen = CompatRL:_forEachAnimal(barn, function(_) end)
      end
      print(("    animals seen: %d"):format(seen))
      if h then
        local shown = 0
        for _, cname in ipairs(candidates) do
          if has(h, cname) then print("    ✓", cname); shown = shown + 1 end
        end
        if shown == 0 then
          local mt = getmetatable(h); local idx = mt and mt.__index or nil
          if type(idx)=="table" then
            local n=0; print("    __index keys:")
            for k,v in pairs(idx) do
              if type(v)=="function" then
                print("      fn:", k); n=n+1; if n>40 then print("      ..."); break end
              end
            end
            if n==0 then print("    (no functions on __index)") end
          else
            print("    (no callable methods exposed; __index not a table)")
          end
        end
      end
    end
    return ""

	elseif sub == "peek" then
	  local list = PN_HusbandryScan and PN_HusbandryScan.getAll and PN_HusbandryScan.getAll() or {}
	  local idx = tonumber(select(1, ...))
	  local n   = select(2, ...)
	  if not idx or not list[idx] then
		print("[PN] Usage: pnEffects peek <barnIndex> [n]"); return ""
	  end

	  local barn = list[idx]
	  local h = (CompatRL and CompatRL.getHandleForBarn and CompatRL:getHandleForBarn(barn))
	  if not h and PN_Boot and PN_Boot._doRebind then
		-- try a quick bind once so peek works without manual steps
		PN_Boot:_doRebind()
		h = (CompatRL and CompatRL.getHandleForBarn and CompatRL:getHandleForBarn(barn))
	  end

	  local title = barn.title or barn.name or tostring(barn.id or barn.husbandryId or "?")
	  local seen = (CompatRL and CompatRL._forEachAnimal and CompatRL:_forEachAnimal(barn, function() end)) or 0
	  print(string.format("[PN] Peek %s — animals seen: %d", title, seen))
	  self:_peekBarn(barn, n)
	  return ""

  elseif sub == "applyOnce" then
    -- pnEffects applyOnce <barnIndex> [scale]
    local list = PN_HusbandryScan and PN_HusbandryScan.getAll and PN_HusbandryScan.getAll() or {}
    local idx   = tonumber(select(1, ...))
    local scale = select(2, ...)
    if not idx or not list[idx] then
      print("[PN] Usage: pnEffects applyOnce <barnIndex> [scale]")
      return ""
    end
    local barn = list[idx]
    local title = barn.title or barn.name or tostring(barn.id or barn.husbandryId or "?")
    print(string.format("[PN] Applying current PN effects to %s ...", title))
    self:_applyOnce(barn, scale)
    return ""

  else
    print("[PN] Usage: pnEffects info | pnEffects probe | pnEffects bind | pnEffects dumpHS | pnEffects peek <i> [n] | pnEffects applyOnce <i> [scale]")
    return ""
  end
end

function PN_Effects:registerConsole()
  if addConsoleCommand then
    addConsoleCommand("pnEffects", "PN effects tools: use 'pnEffects info'", "consoleCommand", PN_Effects)
  end
end

return PN_Effects
