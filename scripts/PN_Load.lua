-- Bootstraps the mod after mission load.
source(Utils.getFilename("scripts/PN_Compat_RL.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/PN_Settings.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/PN_HusbandryScan.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/PN_FeedMatrix.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/PN_Core.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/PN_HusbandryPatch.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/PN_UI.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/PN_Events.lua", g_currentModDirectory))

PN_MODDIR  = g_currentModDirectory
PN_MODNAME = g_currentModName

local PN_VERBOSE_TICKS = false

-- PN depends on Realistic Livestock (extension, not standalone)
local function PN_requireRL()
  local mm  = g_modManager
  local has = mm and (mm:getModByName("FS25_RealisticLivestock") or mm:getModByName("RealisticLivestock"))
  if not has then
    Logging.error("[PN] Realistic Livestock is required. Disabling PN features.")
    PN_Core = PN_Core or {}; PN_Core.enabled = false
    return false
  end
  PN_Core = PN_Core or {}; PN_Core.enabled = true
  return true
end

Mission00.loadMission00Finished = Utils.prependedFunction(Mission00.loadMission00Finished, function()
  if not PN_requireRL() then
    return
  end

  local cfg = PN_Settings.load()
  if PN_Core and PN_Core.init then
    PN_Core.init(cfg)
  else
    Logging.info("[PN] PN_Core not ready at load; continuing without init.")
  end

  -- Explicit bootstrap scan so we don't rely on onMissionStarted timing
  if PN_HusbandryScan and PN_HusbandryScan.rescan then
    local n = PN_HusbandryScan.rescan()
    Logging.info("[PN] Bootstrap scan found %d animal-capable placeables (PS+PM).", n or -1)
  end

  PN_ScanResults = PN_ScanResults or {}
  if PN_HusbandryPatch and PN_HusbandryPatch.install then
    PN_HusbandryPatch.install()
  end
  Logging.info("[PN] Precision Nutrition ready.")
end)

-- Hook update/draw for overlay + nutrition pass
Mission00.update = Utils.appendedFunction(Mission00.update, function(self, dt)
  if PN_VERBOSE_TICKS then Logging.info("[PN] Update hook tick") end

  -- existing ticks
  if PN_HusbandryScan and PN_HusbandryScan.tick then PN_HusbandryScan.tick(dt) end
  if PN_UI and PN_UI.onUpdate then PN_UI.onUpdate(dt) end
  if PN_HusbandryPatch and PN_HusbandryPatch.tick then PN_HusbandryPatch.tick(dt) end

 -- >>> Nutrition tick (lightweight — PN_Core does the cluster work)
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

  -- <<< end nutrition tick
end)

Mission00.draw = Utils.appendedFunction(Mission00.draw, function(self)
  if PN_VERBOSE_TICKS then Logging.info("[PN] Draw hook tick") end
  if PN_UI and PN_UI.onDraw then PN_UI.onDraw() end
end)

-- Forward key events so Alt+N works even without modDesc bindings
Mission00.keyEvent = Utils.appendedFunction(Mission00.keyEvent, function(self, unicode, sym, modifier, isDown, isUp, isRepeat)
    if PN_UI and PN_UI.onKeyEvent then
        PN_UI.onKeyEvent(unicode, sym, modifier, isDown, isUp, isRepeat)
    end
end)
