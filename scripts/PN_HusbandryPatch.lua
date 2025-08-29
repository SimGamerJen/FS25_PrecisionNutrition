-- FS25_PrecisionNutrition / scripts / PN_HusbandryPatch.lua
-- Scan-only mode: disable husbandry module hook (not required for PN scanning/logic).

PN_HusbandryPatch = {}

function PN_HusbandryPatch.install()
    Logging.info("[PN] Husbandry hook disabled (scan-only mode).")
end

function PN_HusbandryPatch.tick(dt)
    -- no-op
end

return PN_HusbandryPatch
