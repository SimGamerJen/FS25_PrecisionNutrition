PN_Log = PN_Log or {}

local PREFIX = "[Precision Nutrition] "

function PN_Log.info(message, ...)
    Logging.info(PREFIX .. tostring(message), ...)
end

function PN_Log.warning(message, ...)
    Logging.warning(PREFIX .. tostring(message), ...)
end

function PN_Log.error(message, ...)
    Logging.error(PREFIX .. tostring(message), ...)
end

return PN_Log
