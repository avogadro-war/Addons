local log = {}

local debug_enabled = false
local addon_name = 'onevent2'

function log.set_debug(enabled)
    debug_enabled = enabled
end

function log.debug(msg)
    if debug_enabled then
        print(('[%s][DEBUG] %s'):format(addon_name, msg))
    end
end

function log.warn(msg)
    print(('[%s][WARN] %s'):format(addon_name, msg))
end

function log.error(msg)
    print(('[%s][ERROR] %s'):format(addon_name, msg))
end

function log.info(msg)
    print(('[%s] %s'):format(addon_name, msg))
end

return log
