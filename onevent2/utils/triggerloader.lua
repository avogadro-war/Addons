--[[
    triggerloader.lua
    Generic loader/merger for job, boss, and zone triggers.
    Usage: local triggerloader = require('utils.triggerloader')
]]

local log = require('utils.log')

local triggerloader = {}

-- Generic loader for triggers (job, boss, zone)
function triggerloader.load_trigger(setname, trigger_type, addon_path, resolve_cooldown_alerts)
    local path = string.format('%striggers/%s/%s.lua', addon_path, trigger_type, setname)
    local ok, triggerfile = pcall(dofile, path)
    if not ok then
        log.error('Failed to load ' .. trigger_type .. ' trigger set: ' .. setname .. ' (' .. tostring(triggerfile) .. ')')
        return nil
    elseif type(triggerfile) ~= 'table' then
        log.error('Trigger file ' .. setname .. ' did not return a table.')
        return nil
    end
    if trigger_type == 'jobs' then
        if (triggerfile.chat_triggers and type(triggerfile.chat_triggers) ~= 'table') or
           (triggerfile.bufflose_alerts and type(triggerfile.bufflose_alerts) ~= 'table') or
           (triggerfile.buffgain_alerts and type(triggerfile.buffgain_alerts) ~= 'table') then
            log.error('Malformed trigger file: ' .. setname)
            return nil
        end
        triggerfile.cooldown_alerts = resolve_cooldown_alerts and resolve_cooldown_alerts(triggerfile.cooldown_alerts) or {}
    end
    return triggerfile
end

function triggerloader.merge_triggers(target, source)
    for k, v in pairs(source) do
        if type(v) == 'table' and type(target[k]) == 'table' then
            for k2, v2 in pairs(v) do
                target[k][k2] = v2
            end
        else
            target[k] = v
        end
    end
end

return triggerloader
