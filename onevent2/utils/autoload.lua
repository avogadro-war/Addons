require('common')

local autoload = {
    auto_load    = true,
    last_check   = os.clock(),
    last_job     = nil,
    last_boss    = nil,
    last_zoneid  = nil,

    load_job_triggers = nil,
    unload_job_triggers = nil,
    load_boss_triggers = nil,
    load_zone_triggers = nil,
}

local packethandler = require('utils.packethandler')
local known_zones   = require('config.known').zones
------------------------------------------------------------
-- Debug log (only if debug enabled in main addon)
local function debug_log(msg, addon_name)
    if _G.onevent and _G.onevent.debug and _G.chat and type(print) == 'function' then
        addon_name = addon_name or 'onevent2'
        print(_G.chat.header(addon_name):append(_G.chat.message(msg)))
    end
end

------------------------------------------------------------
-- Zone auto-load
------------------------------------------------------------
packethandler.onZoneChange:register(function(zoneId)
    if zoneId == autoload.last_zoneid then return end
    autoload.last_zoneid = zoneId
    if known_zones and known_zones[zoneId] then
        local zoneName = known_zones[zoneId]
        local fname = zoneName:lower():gsub(' ', '_')
        if autoload.load_zone_triggers then
            autoload.load_zone_triggers(fname)
            debug_log(('Loaded zone triggers: %s'):format(fname))
        else
            debug_log('Warning: load_zone_triggers function not set in autoload.lua')
        end
    else
        debug_log(('Zone %d entered; no known triggers configured'):format(zoneId))
    end
end)
------------------------------------------------------------
-- Main periodic check: job + boss auto-load
------------------------------------------------------------
function autoload.check_and_load(
    playerMgr, targetMgr, partyMgr, jobNames, known_bosses,
    debug_log_loaded
)
    if not autoload.auto_load then return end

    local now = os.clock()
    if now - autoload.last_check < 2 then return end
    autoload.last_check = now

    -- Job auto-load
    local jobId = playerMgr and playerMgr:GetMainJob()
    local job   = jobId and jobNames[jobId]
    if job and job ~= autoload.last_job then
        local fname = job:lower()
        if autoload.unload_job_triggers then
            autoload.unload_job_triggers()
        end
        if autoload.load_job_triggers then
            autoload.load_job_triggers(fname)
            autoload.last_job = job
            if debug_log_loaded then debug_log_loaded('job', job) end
        end
    end


    -- Boss auto-load
    if targetMgr and known_bosses then
        local targetIndex = targetMgr:GetTargetIndex(0)
        if targetIndex and targetIndex > 0 then
            local entityMgr = AshitaCore and AshitaCore:GetMemoryManager():GetEntity()
            if entityMgr then
                local name = entityMgr:GetName(targetIndex)
                if name then
                    local lname = name:lower()
                    if known_bosses[lname] and lname ~= autoload.last_boss then
                        if autoload.load_boss_triggers then
                            autoload.load_boss_triggers(known_bosses[lname])
                            autoload.last_boss = lname
                            if debug_log_loaded then debug_log_loaded('boss', name) end
                        else
                            debug_log('Warning: load_boss_triggers function not set in autoload.lua')
                        end
                    end
                end
            end
        end
    end
end

------------------------------------------------------------
-- Setter to injecttrigger loader from main addon
------------------------------------------------------------
function autoload.set_job_trigger_loader(func)
    autoload.load_job_triggers = func
end

function autoload.set_job_trigger_unloader(func)
    autoload.unload_job_triggers = func
end

function autoload.set_boss_trigger_loader(func)
    autoload.load_boss_triggers = func
end

function autoload.set_zone_trigger_loader(func)
    autoload.load_zone_triggers = func
end

return autoload