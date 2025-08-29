-- Bootstraps the mod after mission load.
source(Utils.getFilename("scripts/PN_Compat_RL.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/PN_Settings.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/PN_HusbandryScan.lua", g_currentModDirectory))
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

  -- Explicit bootstrap scan so we don't rely on onMissionStarted timing
  if PN_HusbandryScan and PN_HusbandryScan.rescan then
    local n = PN_HusbandryScan.rescan()
    Logging.info("[PN] Bootstrap scan found %d animal-capable placeables (PS+PM).", n or -1)
  end

  -- Defer scanning to Mission00.update to avoid early-load nils
  PN_ScanResults = PN_ScanResults or {}
  PN_HusbandryPatch.install()
  Logging.info("[PN] Precision Nutrition ready.")
end)

-- Hook update/draw for overlay
Mission00.update = Utils.appendedFunction(Mission00.update, function(self, dt)
  Logging.info("[PN] Update hook tick")
  if PN_HusbandryScan and PN_HusbandryScan.tick then PN_HusbandryScan.tick(dt) end
  if PN_UI and PN_UI.onUpdate then PN_UI.onUpdate(dt) end
  if PN_HusbandryPatch and PN_HusbandryPatch.tick then PN_HusbandryPatch.tick(dt) end
end)

Mission00.draw = Utils.appendedFunction(Mission00.draw, function(self)
  Logging.info("[PN] Draw hook tick")
  if PN_UI and PN_UI.onDraw then PN_UI.onDraw() end
end)

-- In PN_Load.lua update hook, after existing lines
if PN_HusbandryScan and PN_HusbandryScan.isReady and PN_HusbandryScan:isReady() then
    local list = PN_HusbandryScan.getAll()
    for _, e in ipairs(list) do
        local cs = e.clusterSystem
        if cs and cs.getNumOfAnimals then
            local ok, n = pcall(cs.getNumOfAnimals, cs)
            if ok and (n or 0) > 0 then
                -- TODO: call into PN_Core with (e, cs, n) to compute nutrition
                -- Example: PN_Core.updateHusbandry(e, cs, dt)
            end
        end
    end
end
