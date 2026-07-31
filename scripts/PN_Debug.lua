PN_Debug = PN_Debug or { registered=false }

local function printStatus()
    local rows = PN_Core.getMetrics(nil)
    print(string.format("[PN] enabled=%s RLRM=%s husbandries=%d metrics=%d",
        tostring(PN_Boot ~= nil and PN_Boot.enabled), tostring(PN_Compat_RL.enabled),
        #(PN_Husbandry.entries or {}), #rows))
    for _, row in ipairs(rows) do
        print(string.format("[PN] %s: %s head=%d quality=%.3f base=%.3f effective=%.3f stages=%s",
            row.name, row.species, row.head, row.quality, row.baseFood, row.effectiveFood, row.stages))
    end
end

local function reloadSettings()
    PN_Settings.reload()
    PN_Core.reset()
    print("[PN] feeds.xml, targets.xml, and stages.xml reloaded; metrics will repopulate on the next RLRM update")
end

function PN_Debug.register()
    if PN_Debug.registered or addConsoleCommand == nil then return end
    addConsoleCommand("pnStatus", g_i18n:getText("pn_console_status"), "pnStatus", PN_Debug)
    addConsoleCommand("pnReload", g_i18n:getText("pn_console_reload"), "pnReload", PN_Debug)
    PN_Debug.registered = true
end

function PN_Debug.unregister()
    if not PN_Debug.registered or removeConsoleCommand == nil then return end
    removeConsoleCommand("pnStatus")
    removeConsoleCommand("pnReload")
    PN_Debug.registered = false
end

function PN_Debug:pnStatus()
    printStatus()
end

function PN_Debug:pnReload()
    reloadSettings()
end


return PN_Debug
