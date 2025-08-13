-- Bootstraps the mod after mission load.
source(Utils.getFilename("scripts/PN_Compat_RL.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/PN_Settings.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/PN_FeedMatrix.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/PN_Core.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/PN_HusbandryPatch.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/PN_UI.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/PN_Events.lua", g_currentModDirectory))

PN_MODDIR = g_currentModDirectory
PN_MODNAME = g_currentModName
Mission00.loadMission00Finished = Utils.prependedFunction(Mission00.loadMission00Finished, function()
  local cfg = PN_Settings.load()
  PN_Core.init(cfg)
  PN_HusbandryPatch.install()
  Logging.info("[PN] Precision Nutrition ready.")
end)


-- Hook update/draw for overlay
Mission00.update = Utils.appendedFunction(Mission00.update, function(self, dt)
  if PN_UI and PN_UI.onUpdate then PN_UI.onUpdate(dt) end
end)

Mission00.draw = Utils.appendedFunction(Mission00.draw, function(self)
  if PN_UI and PN_UI.onDraw then PN_UI.onDraw() end
end)
