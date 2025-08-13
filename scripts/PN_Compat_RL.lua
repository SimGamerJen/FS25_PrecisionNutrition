PN_Compat_RL = { active=false, weightMul=1.10, baseAdgMul=0.90 }

function PN_Compat_RL.detect()
  if g_modManager and g_modManager.getActiveMods then
    for _, m in ipairs(g_modManager:getActiveMods()) do
      local name = (m.modFileName or ""):lower() .. " " .. (m.title or ""):lower()
      if name:find("realistic") and name:find("livestock") then
        PN_Compat_RL.active = true
        Logging.info("[PN] Realistic Livestock detected: applying compatibility multipliers.")
        break
      end
    end
  end
end

function PN_Compat_RL.applyToSettings(cfg)
  if not PN_Compat_RL.active then return cfg end
  for _, st in ipairs(cfg.stages.COW) do st.baseADG = st.baseADG * PN_Compat_RL.baseAdgMul end
  cfg.params.adgCap = cfg.params.adgCap * PN_Compat_RL.baseAdgMul
  return cfg
end

return PN_Compat_RL
