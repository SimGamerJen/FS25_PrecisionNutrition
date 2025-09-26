-- scripts/PN_Logger.lua
PN_Logger = PN_Logger or {}
PN_Logger.__index = PN_Logger

local LMAP = { TRACE=10, DEBUG=20, INFO=30, WARN=40, ERROR=50 }
PN_Logger.levelName = "INFO"
PN_Logger.level = LMAP[PN_Logger.levelName]

local function _normLevel(name)
    if not name then return nil end
    local up = tostring(name):upper()
    return LMAP[up] and up or nil
end

function PN_Logger:setLevel(name)
    local up = _normLevel(name)
    if not up then
        Logging.info("[PN] Logger: unknown level '%s' (use TRACE|DEBUG|INFO|WARN|ERROR)", tostring(name))
        return
    end
    self.levelName = up
    self.level = LMAP[up]
    Logging.info(string.format("[PN] Logger: level set to %s", up))
    -- Optional: remember in settings so it persists this session
    PN_Settings = PN_Settings or {}
    PN_Settings.logLevel = up
end

function PN_Logger:isEnabled(name)
    local up = _normLevel(name) or "INFO"
    return (LMAP[up] >= (self.level or LMAP.INFO))
end

local function _fmt(msg, ...)
    if select("#", ...) > 0 then
        return string.format(msg, ...)
    end
    return tostring(msg)
end

local function _emit(tag, msg)
    -- You can swap Logging.info for print if needed
    Logging.info(string.format("[PN][%s] %s", tag, msg))
end

function PN_Logger:log(level, msg, ...)
    if self:isEnabled(level) then _emit(level, _fmt(msg, ...)) end
end

function PN_Logger:trace(msg, ...) self:log("TRACE", msg, ...) end
function PN_Logger:debug(msg, ...) self:log("DEBUG", msg, ...) end
function PN_Logger:info (msg, ...) self:log("INFO" , msg, ...) end
function PN_Logger:warn (msg, ...) self:log("WARN" , msg, ...) end
function PN_Logger:error(msg, ...) self:log("ERROR", msg, ...) end

-- Optional helper so other modules can do PN_log("DEBUG", "Hello %d", 42)
function PN_log(level, msg, ...)
    if PN_Logger and PN_Logger.log then
        PN_Logger:log(level, msg, ...)
    else
        Logging.info(string.format("[PN][%s] %s", tostring(level), _fmt(msg, ...)))
    end
end

-- Initialize from prior PN_Settings if present
if PN_Settings and PN_Settings.logLevel then
    PN_Logger:setLevel(PN_Settings.logLevel)
end
