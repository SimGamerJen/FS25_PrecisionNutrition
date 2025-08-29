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

Mission00.loadMission00Finished = Utils.prependedFunction(Mission00.loadMission00Finished, function()
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

  -- >>> Nutrition tick (safe: only if scan ready and clusterSystem exposes data)
  if PN_HusbandryScan and PN_HusbandryScan.isReady and PN_HusbandryScan:isReady()
     and PN_Core and PN_Core.updateHusbandry then
    local list = PN_HusbandryScan.getAll()
    for _, e in ipairs(list) do
      local cs = e.clusterSystem
      if cs and cs.getClusters then
        local ok, clusters = pcall(cs.getClusters, cs)
        if ok and type(clusters) == "table" then
          -- Example: count animals (works even before we know exact keys)
          local total = 0
          for _, c in pairs(clusters) do
            local n = nil
            if type(c) == "table" then
              -- Candidates often seen: numAnimals, count, size
              n = c.numAnimals or c.count or c.size
              if n == nil and c.getNumAnimals then
                local ok2, vn = pcall(c.getNumAnimals, c)
                if ok2 then n = vn end
              end
            end
            if type(n) == "number" then total = total + n end
          end

          -- Hand off to PN core (pass dt each frame)
          pcall(PN_Core.updateHusbandry, PN_Core, e, cs, dt, { totalAnimals = total })
        end
      end
    end
  end
  -- <<< end nutrition tick
end)

Mission00.draw = Utils.appendedFunction(Mission00.draw, function(self)
  if PN_VERBOSE_TICKS then Logging.info("[PN] Draw hook tick") end
  if PN_UI and PN_UI.onDraw then PN_UI.onDraw() end
end)
