PN_Settings = { stages={}, targets={}, intakes={}, params={} }

local function parseNumber(v, d) return v and tonumber(v) or d end

function PN_Settings.load()
  local cfg = {
    stages = { COW = {} },
    targets = { COW = {} },
    intakes = { COW = {} },
    params = {}
  }

  local path = Utils.getFilename("config/feedTargets.xml", PN_MODDIR or g_currentModDirectory)
  local xml = loadXMLFile("pnFeedTargets", path)
  if xml == nil then
    Logging.error("[PN] Could not open %s", tostring(path))
    PN_Settings.params = {dietPenaltyK=0.85, starchUpper=0.25, adgCap=1.6, grassFedFlag={minGrassShare=0.80, minDays=120}}
    return {stages={COW={}}, targets={COW={}}, intakes={COW={}}, params=PN_Settings.params}
  end

  local function readStages()
    local i=0
    while true do
      local key = string.format("precisionNutrition.stages(0).stage(%d)", i)
      if not hasXMLProperty(xml, key) then break end
      table.insert(cfg.stages.COW, {
        name = getXMLString(xml, key.."#name"),
        minAgeM = getXMLInt(xml, key.."#minAgeM") or 0,
        maxAgeM = getXMLInt(xml, key.."#maxAgeM") or 999,
        baseADG = getXMLFloat(xml, key.."#baseADG") or 0.9
      })
      i=i+1
    end
  end

  local function readTargets()
    local tkey = "precisionNutrition.targets(0)"
    local i=0
    while true do
      local key = string.format("%s.target(%d)", tkey, i)
      if not hasXMLProperty(xml, key) then break end
      local stage = getXMLString(xml, key.."#stage")
      cfg.targets.COW[stage] = {
        energy = getXMLFloat(xml, key.."#energy") or 0.35,
        protein= getXMLFloat(xml, key.."#protein") or 0.20,
        fibre  = getXMLFloat(xml, key.."#fibre") or 0.30,
        starch = getXMLFloat(xml, key.."#starch") or 0.15
      }
      i=i+1
    end
  end

  local function readIntakes()
    local ikey = "precisionNutrition.intakes(0)"
    local i=0
    while true do
      local key = string.format("%s.intake(%d)", ikey, i)
      if not hasXMLProperty(xml, key) then break end
      local stage = getXMLString(xml, key.."#stage")
      cfg.intakes.COW[stage] = {
        min = getXMLFloat(xml, key.."#min") or 8,
        max = getXMLFloat(xml, key.."#max") or 16
      }
      i=i+1
    end
  end

  local function readParams()
    local p = "precisionNutrition.params(0)"
    cfg.params.dietPenaltyK = getXMLFloat(xml, p..".dietPenaltyK#value") or 0.85
    cfg.params.starchUpper  = getXMLFloat(xml, p..".starchUpper#value") or 0.25
    cfg.params.adgCap       = getXMLFloat(xml, p..".adgCap#value") or 1.6
    cfg.params.grassFedFlag = {
      minGrassShare = getXMLFloat(xml, p..".grassFedFlag#minGrassShare") or 0.80,
      minDays       = getXMLFloat(xml, p..".grassFedFlag#minDays") or 120
    }
  end

  readStages(); readTargets(); readIntakes(); readParams(); if xml ~= nil then delete(xml) end

  if PN_Compat_RL and PN_Compat_RL.detect then
    PN_Compat_RL.detect()
    if PN_Compat_RL.applyToSettings then
      cfg = PN_Compat_RL.applyToSettings(cfg)
    end
  end

  PN_Settings.params = cfg.params
  return cfg
end

return PN_Settings
