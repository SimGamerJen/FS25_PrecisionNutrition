-- PN_CoreValuePatch.lua
-- Safe, optional patch to add valueFactorForCow() without editing PN_Core.lua.
-- Load after PN_Core.lua (and CoreCompat) in modDesc.xml.

PN_Core = PN_Core or {}

if type(PN_Core.valueFactorForCow) ~= "function" then
    function PN_Core:valueFactorForCow(entry, stageLabel)
        local ageM = (entry and entry.ageMonths) or 0
        local mult = 1.0

        -- Defaults if PN_Settings.meta isn't initialized
        local sale = (((PN_Settings or {}).meta or {}).COW or {}).sale or {}
        local perMonth = tonumber(sale.overagePenaltyPerMonth) or 0.05   -- 5% per month
        local floor    = tonumber(sale.overagePenaltyFloor)  or 0.60     -- don't go below 60%

        if stageLabel == "OVERAGE" then
            local over = math.max(0, ageM - 24)           -- months beyond 24
            mult = math.max(floor, 1.0 - perMonth * over)
        end
        return mult
    end
end
