-- PN_Load.lua — bootstraps PN with a hard RL dependency + auto-bind + day ticks

PN_MODDIR  = g_currentModDirectory
PN_MODNAME = g_currentModName

-- Always load RL compat first
source(Utils.getFilename("scripts/PN_Compat_RL.lua", g_currentModDirectory))
CompatRL:init()

-- If RL is missing, disable PN and expose a tiny help message
if not CompatRL.hasRL then
  if addConsoleCommand then
    addConsoleCommand("pnHelp", "PrecisionNutrition help", function()
      print("[PN] Disabled: Realistic Livestock is required. Install/enable RL to use PrecisionNutrition.")
    end)
  end
  Logging.warning("[PN] PrecisionNutrition aborted: RealisticLivestock not found.")
  return
end

-- With RL present, load the rest of PN
source(Utils.getFilename("scripts/PN_Config.lua",           g_currentModDirectory))
source(Utils.getFilename("scripts/PN_Settings.lua",         g_currentModDirectory))
source(Utils.getFilename("scripts/PN_HusbandryScan.lua",    g_currentModDirectory))
source(Utils.getFilename("scripts/PN_FeedMatrix.lua",       g_currentModDirectory))
source(Utils.getFilename("scripts/PN_Core.lua",             g_currentModDirectory))
source(Utils.getFilename("scripts/PN_Sales.lua",            g_currentModDirectory))
source(Utils.getFilename("scripts/PN_HusbandryPatch.lua",   g_currentModDirectory))
source(Utils.getFilename("scripts/PN_UI.lua",               g_currentModDirectory))
source(Utils.getFilename("scripts/PN_Events.lua",           g_currentModDirectory))
source(Utils.getFilename("scripts/PN_Effects.lua",          g_currentModDirectory))
source(Utils.getFilename("scripts/PN_GrazingFeeder.lua", g_currentModDirectory))

local PN_VERBOSE_TICKS = false

-- ============================================================================
-- Auto-bind + day scheduler (no console needed for players)
-- ============================================================================
PN_Boot = {
  initialized = false,
  reboundDueAtMs = 0,
  lastDayIndex = nil,
  didInitialBind = false,        -- NEW
  lastBarnCount  = 0,            -- NEW
}

function PN_Boot:_scheduleRebind(seconds)
  local ms = math.max(0, (seconds or 0.25)) * 1000
  self.reboundDueAtMs = g_time + ms
end

function PN_Boot:_doRebind()
  if not (CompatRL and CompatRL.hasRL) then return end
  local list = PN_HusbandryScan and PN_HusbandryScan.getAll and PN_HusbandryScan.getAll() or {}
  if #list > 0 then
    local n = CompatRL:bindBarnHandles(list)
    Logging.info(string.format("[PN] Auto-bind RL handles: %d/%d", n, #list))
  end
end

function PN_Boot:initAfterMap()
  if self.initialized then return end

  -- If RL disappeared somehow, disable PN_Effects
  if not (CompatRL and CompatRL.hasRL) then
    if PN_Effects then PN_Effects.enabled = false end
    Logging.warning("[PN] PN_Effects disabled (RealisticLivestock not found).")
    self.initialized = true
    return
  end

  -- Ensure an initial scan, then schedule a quick rebind
  if PN_HusbandryScan and PN_HusbandryScan.scan then PN_HusbandryScan:scan() end
  self:_scheduleRebind(1.0)

  -- Subscribe to day change if available
  if g_messageCenter and MessageType and MessageType.DAY_CHANGED then
    g_messageCenter:subscribe(MessageType.DAY_CHANGED, function()
      if PN_Effects and PN_Effects.onDayTick then PN_Effects:onDayTick(1.0) end
    end, self)
    Logging.info("[PN] Subscribed to DAY_CHANGED for PN_Effects daily ticks.")
  end

  -- Optional: rebind when placeables change (if these messages exist)
  if g_messageCenter and MessageType then
    if MessageType.PLACEABLE_BUYED then
      g_messageCenter:subscribe(MessageType.PLACEABLE_BUYED, function(_)
        self:_scheduleRebind(0.50)
      end, self)
    end
    if MessageType.PLACEABLE_REMOVED then
      g_messageCenter:subscribe(MessageType.PLACEABLE_REMOVED, function(_)
        self:_scheduleRebind(0.50)
      end, self)
    end
  end

  self.initialized = true
end

function PN_Boot:update(dt)
  -- 1) Delayed rebinds
  if self.reboundDueAtMs > 0 and g_time >= self.reboundDueAtMs then
    self.reboundDueAtMs = 0
    self:_doRebind()
    self.didInitialBind = true
  end

  -- 2) Bind immediately once the scan is ready, even if (1) never fired
  if not self.didInitialBind and (CompatRL and CompatRL.hasRL) then
    if PN_HusbandryScan and PN_HusbandryScan.isReady and PN_HusbandryScan:isReady() then
      local list = PN_HusbandryScan.getAll and PN_HusbandryScan.getAll() or {}
      if #list > 0 then
        self:_doRebind()
        self.didInitialBind = true
      end
    end
  end

  -- 3) Rebind if the barn count changes (buy/sell) and we missed an event
  do
    local list = PN_HusbandryScan and PN_HusbandryScan.getAll and PN_HusbandryScan.getAll() or {}
    local n = #list
    if n ~= self.lastBarnCount then
      self.lastBarnCount = n
      -- debounce a little to let RL create clusters
      self:_scheduleRebind(0.5)
    end
  end

  -- 4) Fallback day tick if we don't get DAY_CHANGED events
  if not (g_messageCenter and MessageType and MessageType.DAY_CHANGED) then
    local env = g_currentMission and g_currentMission.environment
    if env then
      local curDay = env.currentDay
      if curDay ~= nil and curDay ~= self.lastDayIndex then
        self.lastDayIndex = curDay
        if PN_Effects and PN_Effects.onDayTick and CompatRL and CompatRL.hasRL then
          PN_Effects:onDayTick(1.0)
        end
      end
    end
  end
end

-- Register PN_Boot for update() callbacks
addModEventListener(PN_Boot)

-- ============================================================================
-- Mission hooks
-- ============================================================================
Mission00.loadMission00Finished = Utils.prependedFunction(Mission00.loadMission00Finished, function()
  local cfg = PN_Settings and PN_Settings.load and PN_Settings.load() or nil

  if PN_Core and PN_Core.init then
    PN_Core.init(cfg)
  end

  if PN_Effects and PN_Effects.registerConsole then
    PN_Effects:registerConsole()
  end

  if PN_HusbandryScan and PN_HusbandryScan.rescan then
    local n = PN_HusbandryScan.rescan()
    Logging.info("[PN] Bootstrap scan found %d animal-capable placeables (PS+PM).", n or -1)
  end

  if PN_HusbandryPatch and PN_HusbandryPatch.install then
    PN_HusbandryPatch.install()
  end

  if PN_Sales and PN_Sales.initHook then
    PN_Sales.initHook()
  end

  if PN_Config and PN_Config.loadUI then
    local ok, _, p = PN_Config:loadUI('config')
    if ok then
      Logging.info('[PN] Loaded PN overlay config: %s', tostring(p))
    else
      Logging.info('[PN] No PN config found (will use defaults).')
    end
  end

  -- Kick the auto-binder/day scheduler after map is ready
  PN_Boot:initAfterMap()

    Logging.info("[PN] Precision Nutrition ready.")
end)

Mission00.update = Utils.appendedFunction(Mission00.update, function(self, dt)
  if PN_VERBOSE_TICKS then Logging.info("[PN] Update hook tick") end
  if PN_Boot and PN_Boot.update then PN_Boot:update(dt) end

  if PN_HusbandryScan and PN_HusbandryScan.tick then PN_HusbandryScan.tick(dt) end
  if PN_UI and PN_UI.onUpdate then PN_UI.onUpdate(dt) end
  if PN_HusbandryPatch and PN_HusbandryPatch.tick then PN_HusbandryPatch.tick(dt) end

  if PN_Core and PN_Core.hourEdgeGraze then PN_Core.hourEdgeGraze() end
  if PN_HusbandryScan and PN_HusbandryScan.isReady and PN_HusbandryScan:isReady()
     and PN_Core and PN_Core.updateHusbandry then
    local list = PN_HusbandryScan.getAll()
    for _, e in ipairs(list) do
      local cs = e.clusterSystem
      if cs ~= nil then
        pcall(PN_Core.updateHusbandry, PN_Core, e, cs, dt, {})
      end
    end
  end
end)

Mission00.draw = Utils.appendedFunction(Mission00.draw, function(self)
  if PN_VERBOSE_TICKS then Logging.info("[PN] Draw hook tick") end
  if PN_UI and PN_UI.onDraw then PN_UI.onDraw() end
end)

Mission00.keyEvent = Utils.appendedFunction(Mission00.keyEvent, function(self, unicode, sym, modifier, isDown, isUp, isRepeat)
  if PN_UI and PN_UI.onKeyEvent then
    PN_UI.onKeyEvent(unicode, sym, modifier, isDown, isUp, isRepeat)
  end
end)
