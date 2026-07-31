PN_MOD_DIRECTORY = g_currentModDirectory
PN_MOD_NAME = g_currentModName

source(Utils.getFilename("scripts/PN_Logger.lua", PN_MOD_DIRECTORY))
source(Utils.getFilename("scripts/PN_Settings.lua", PN_MOD_DIRECTORY))
source(Utils.getFilename("scripts/PN_Husbandry.lua", PN_MOD_DIRECTORY))
source(Utils.getFilename("scripts/PN_Core.lua", PN_MOD_DIRECTORY))
source(Utils.getFilename("scripts/PN_Events.lua", PN_MOD_DIRECTORY))
source(Utils.getFilename("scripts/PN_Compat_RL.lua", PN_MOD_DIRECTORY))
source(Utils.getFilename("scripts/PN_UI.lua", PN_MOD_DIRECTORY))
source(Utils.getFilename("scripts/PN_Debug.lua", PN_MOD_DIRECTORY))

PN_Boot = {
    enabled=false,
    scanTimer=0,
    broadcastTimer=0
}

function PN_Boot:loadMap()
    PN_Husbandry.reset()
    PN_Core.reset()
    PN_Settings.load(false)
    PN_Husbandry.scan()
    self.enabled = PN_Compat_RL.install()
    if self.enabled and g_server ~= nil then PN_Core.refreshAllMetrics(true) end
    self.scanTimer = 0
    self.broadcastTimer = 0
    PN_Debug.register()
    if self.enabled then PN_Log.info("0.5.0.4-alpha ready (server-authoritative RLRM integration)") end
end

function PN_Boot:onMissionStarted()
    if not self.enabled then return end
    PN_Husbandry.scan()
    if g_server ~= nil then PN_Core.refreshAllMetrics(true) end
end

function PN_Boot:update(dt)
    if not self.enabled then return end
    self.scanTimer = self.scanTimer + (tonumber(dt) or 0)
    if self.scanTimer >= 10000 then
        self.scanTimer = self.scanTimer - 10000
        PN_Husbandry.scan()
        if g_server ~= nil then PN_Core.refreshAllMetrics(false) end
    end
    if g_server ~= nil then
        self.broadcastTimer = self.broadcastTimer + (tonumber(dt) or 0)
        if self.broadcastTimer >= 5000 then
            self.broadcastTimer = self.broadcastTimer - 5000
            PN_Events.broadcastSnapshot()
        end
    end
end

function PN_Boot:draw()
    PN_UI.draw()
end

function PN_Boot:deleteMap()
    self.enabled = false
    PN_Compat_RL.disable()
    PN_Debug.unregister()
    PN_Husbandry.reset()
    PN_Core.reset()
end

addModEventListener(PN_Boot)
