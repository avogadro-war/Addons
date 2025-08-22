--[[
    trigger_schema.lua
    Utility for validating trigger file structure and types.
    Usage: local schema = require('utils.trigger_schema'); schema.validate(trigger_table, 'job'|'boss'|'zone', log)
]]

local T = T or function(t) return t end

local schema = {}

local function is_table(t) return type(t) == 'table' end
local function is_string(s) return type(s) == 'string' end

function schema.validate(trigger, trigger_type, log)
    if not is_table(trigger) then
        log.error('Trigger file did not return a table.')
        return false
    end
    if trigger_type == 'job' then
        if trigger.chat_triggers and not is_table(trigger.chat_triggers) then
            log.error('chat_triggers must be a table.')
            return false
        end
        if trigger.buffgain_alerts and not is_table(trigger.buffgain_alerts) then
            log.error('buffgain_alerts must be a table.')
            return false
        end
        if trigger.bufflose_alerts and not is_table(trigger.bufflose_alerts) then
            log.error('bufflose_alerts must be a table.')
            return false
        end
        if trigger.debuffexpire_alerts and not is_table(trigger.debuffexpire_alerts) then
            log.error('debuffexpire_alerts must be a table.')
            return false
        end
        if trigger.cooldown_alerts and not is_table(trigger.cooldown_alerts) then
            log.error('cooldown_alerts must be a table.')
            return false
        end
        -- Ensure chat_triggers is T{}
        if trigger.chat_triggers and getmetatable(trigger.chat_triggers) ~= getmetatable(T{}) then
            log.warn('chat_triggers should be wrapped in T{} for Ashita compatibility.')
        end
    elseif trigger_type == 'boss' then
        if trigger.chat_triggers and not is_table(trigger.chat_triggers) then
            log.error('chat_triggers must be a table.')
            return false
        end
        if trigger.packet_triggers and not is_table(trigger.packet_triggers) then
            log.error('packet_triggers must be a table.')
            return false
        end
        if trigger.chat_triggers and getmetatable(trigger.chat_triggers) ~= getmetatable(T{}) then
            log.warn('chat_triggers should be wrapped in T{} for Ashita compatibility.')
        end
    elseif trigger_type == 'zone' then
        if not is_table(trigger) then
            log.error('Zone trigger file must return a table.')
            return false
        end
        -- Each entry should be a table {pattern, action}
        for i, entry in ipairs(trigger) do
            if not is_table(entry) or not is_string(entry[1]) or not is_string(entry[2]) then
                log.warn('Zone trigger entry #'..i..' should be {pattern, action} (both strings).')
            end
        end
    end
    return true
end

return schema
