PN_Log = {}

local PN_TAG   = "[PN]"
local PN_DEBUG = true

function PN_Log.d(fmt, ...)
    if not PN_DEBUG then return end
    if select("#", ...) > 0 then
        print(("%s " .. fmt):format(PN_TAG, ...))
    else
        print(("%s %s"):format(PN_TAG, fmt))
    end
end