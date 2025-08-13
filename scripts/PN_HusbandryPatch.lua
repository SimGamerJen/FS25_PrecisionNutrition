PN_HusbandryPatch = {}

local function replace(owner, name, wrap)
  if owner and owner[name] and owner["__pn_"..name] == nil then
    owner["__pn_"..name] = owner[name]
    owner[name] = wrap(owner["__pn_"..name])
  end
end

local function fillTypeExists(name)
  local ft = g_fillTypeManager and g_fillTypeManager.nameToIndex[name]
  return ft ~= nil
end

function PN_HusbandryPatch.install()
  local HMA = HusbandryModuleFeeding or HusbandryModuleAnimal or HusbandryAnimals

  -- Fallback: scan globals for a husbandry module with updateFeeding
  if (not HMA) or (not HMA.updateFeeding) then
    for k,v in pairs(_G) do
      if type(v)=="table" and k:match("^HusbandryModule") and v.updateFeeding then
        HMA = v
        break
      end
    end
  end
  if not HMA then Logging.warning("[PN] Husbandry module not found"); return end

  replace(HMA, "updateFeeding", function(orig)
    return function(self, dt)
      orig(self, dt)

      if self.typeName ~= "COW" then return end
      if (g_currentMission.missionDynamicInfo.isMultiplayer and not g_server) then return end
      local group = (self.getAnimals and self:getAnimals()) or nil
      if not group or (group.getNumOfAnimals and group:getNumOfAnimals() or 0) < 1 then return end

      self.__pn_prev = self.__pn_prev or {}
      local consumed = {}

      local rawList = {
        "GRASS_WINDROW","ALFALFA_WINDROW","CLOVER_WINDROW",
        "DRYGRASS_WINDROW","DRYALFALFA_WINDROW","DRYCLOVER_WINDROW",
        "SILAGE","STRAW","SOYBEANSTRAW","CORN_STALKS",
        "MAIZE","WHEAT","BARLEY","RYE","TRITICALE","OAT","SORGHUM",
        "SOYBEAN","CANOLA","SUNFLOWER","LENTILS","DRYPEAS","PEA","BEANS","CHICKPEAS",
        "FORAGE","MINERAL_FEED"
      }
      local toCheck = {}
      for _, ft in ipairs(rawList) do if fillTypeExists(ft) then table.insert(toCheck, ft) end end

      -- Placeholder accessor: try getFeedingTroughLevel(ft) if present; else sample a generic storage method if available
      for _, ft in ipairs(toCheck) do
        local cur = (self.getFeedingTroughLevel and self:getFeedingTroughLevel(ft)) or 0
        local prev = self.__pn_prev[ft] or cur
        local delta = prev - cur
        if delta > 0 then consumed[ft] = delta end
        self.__pn_prev[ft] = cur
      end

      if next(consumed) == nil then return end

      local n = group.getNumOfAnimals and group:getNumOfAnimals() or 0
      local ageMonths = group.getAgeInMonths and group:getAgeInMonths() or 18

      if PN_Core and PN_Core.calcTick then
        local res = PN_Core.calcTick("COW", ageMonths, consumed, n, dt)
        if res then
          local dayFrac = dt / (24*60*60*1000)
          local dW = res.adg * dayFrac
          group.liveWeight = (group.liveWeight or 250) + dW
          group.bcs        = math.max(1, math.min(9, (group.bcs or 5) + dW*0.01))
          group.__pn_grassDays = (group.__pn_grassDays or 0) + ((res.forageShare >= (PN_Settings.params.grassFedFlag.minGrassShare or 0.80)) and dayFrac or 0)
          if PN_UI and PN_UI.pushBarnStat then PN_UI.pushBarnStat(self, self.placeable and self.placeable.name, {adg=res.adg, intakePH=res.intakePH, balance=res.balance, forageShare=res.forageShare, stage=res.stage, n=n}) end
        end
      end
    end
  end)
end

return PN_HusbandryPatch
