--[[
* Onevent2 Addon - Auto-load by job, boss, zone; reacts to chat & buffs with commands & sounds.
* Author: atom0s + extended by Avogadro + library code by Will
--]]

addon.name    = 'onevent2';
addon.author  = 'original: atom0s | extended: Avogadro | events/buffChange/zoneChange code: Will';
addon.version = '1.0';
addon.desc    = 'Reacts to chat, buffs, auto-loads triggers by job/boss/zone.';
--------------------------------------------------------------------------------
-- Dependencies
--------------------------------------------------------------------------------
require('common')
local known         = require('config.known')
local chat          = require('chat')
local autoload      = require('utils.autoload')
local packethandler = require('utils.packethandler')
local packet_dedupe = require('utils.packet_dedupe')
local statusIDs     = require('utils.statusIDs')
local strings       = require('utils.strings')
local fileutil      = require('utils.file')
local soundutil     = require('utils.sound')
local log           = require('utils.log')
local triggerloader = require('utils.triggerloader')
--------------------------------------------------------------------------------
-- Managers
--------------------------------------------------------------------------------
local memMgr    = AshitaCore and AshitaCore:GetMemoryManager()
local targetMgr = memMgr and memMgr:GetTarget()
local entityMgr = memMgr and memMgr:GetEntity()
local partyMgr  = memMgr and memMgr:GetParty()
local playerMgr = memMgr and memMgr:GetPlayer()
local chatManager = AshitaCore and AshitaCore:GetChatManager()
--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------
local onevent = {
    job_triggers        = T{},
    boss_triggers       = T{},
    zone_triggers       = T{},
    bufflose_alerts     = {},
    buffgain_alerts     = {},
    debuffexpire_alerts = {},
    cooldown_alerts     = {},
    boss_packet_triggers = {},
    paused              = false,
    debug               = false,
    status_id_to_names  = {},
    current_buffs       = T{}  -- keys = buff IDs, values = true
}
--------------------------------------------------------------------------------
-- Config
--------------------------------------------------------------------------------
local known_bosses = known.bosses
local known_zones  = known.zones
local jobNames     = known.jobs
local sounds_path  = addon.path .. 'sounds/'
--------------------------------------------------------------------------------
-- Debug Helpers
--------------------------------------------------------------------------------
packethandler.get_debug = function()
    return onevent.debug
end
log.set_debug(onevent.debug)
local function debug_log(msg)
    if onevent.debug then
        log.debug(msg)
    end
end
local function debug_log_loaded(type, name)
    debug_log(('Auto-loaded %s triggers: %s'):fmt(type, name))
end
--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local startswith = strings.startswith
local trim = strings.trim
local split = strings.split
local file_exists = fileutil.exists
local function classify_actor(actor_id)
    if not partyMgr then return 'other' end
    local my_id = partyMgr:GetMemberServerId(0)
    if actor_id == my_id then
        return 'self'
    end
    for i = 1, 5 do
        local member_id = partyMgr:GetMemberServerId(i)
        if member_id > 0 and member_id == actor_id then
            return 'party'
        end
    end
    return 'other'
end

local statusID_to_names = {}
for name, id in pairs(statusIDs) do
    statusID_to_names[id] = statusID_to_names[id] or {}
    table.insert(statusID_to_names[id], name)
end

local function normalize_trigger_table(trigger_table, table_name)
    local normalized = {}
    for key, value in pairs(trigger_table or {}) do
        local id = tonumber(key)
        if not id then
            -- key is string: lookup by lowercased name
            local lookup = statusIDs[key:lower()]
            if lookup then
                id = lookup
            else
                log.error(('Unknown buff/debuff name in %s: "%s"'):format(table_name, tostring(key)))
            end
        end
        if id then
            normalized[id] = value
        end
    end
    return normalized
end

local function handle_buff_or_debuff_event(buff_id, actor_id, alert_table, event_type)
    if onevent.paused then return end

    local scope = classify_actor(actor_id)  -- 'self', 'party', or 'other'
    local alert = alert_table[buff_id]
    local soundFile = nil

    if type(alert) == 'string' then
        if scope == 'self' then soundFile = alert end
    elseif type(alert) == 'table' then
        soundFile = alert[scope]  -- Only use the exact tag, do not fall back
    end

    if soundFile then
        local ok, soundPath = soundutil.play(addon.path, soundFile)
        if ok then
            debug_log(('%s %d on %s: playing %s'):format(event_type, buff_id, scope, soundFile))
        else
            debug_log('Missing sound file: ' .. soundFile)
        end
    else
        debug_log(('%s %d on %s but no alert configured'):format(event_type, buff_id, scope))
    end
end
--------------------------------------------------------------------------------
-- Process triggers
--------------------------------------------------------------------------------
local function process_triggers(triggers, e)
    for _, v in ipairs(triggers) do
        if string.find(e.message_modified, v[1], 1, true) then
            local actions = split(v[2], ';')
            for _, act in ipairs(actions) do
                act = trim(act)
                if act:lower():startswith('sound:') then
                    local ok, soundPath = soundutil.play(addon.path, trim(act:sub(7)))
                    if ok then
                        debug_log('Playing sound: ' .. soundPath)
                    else
                        debug_log('Missing sound file: ' .. soundPath)
                    end
                else
                    if chatManager then chatManager:QueueCommand(1, act)
                    else debug_log('ChatManager unavailable; could not run: ' .. act)
                    end
                end
            end
        end
    end
end
--------------------------------------------------------------------------------
-- Buff gain/loss
--------------------------------------------------------------------------------

local buff_state_manager = require('utils.buff_state_manager')

packethandler.buffGain:register(function(buff_id, actor_id)
    if onevent.paused then return end

    -- Only trigger sound if this buff hasn't been alerted already (centralized, actor-specific)
    if buff_state_manager.should_alert(buff_id, actor_id) then
        buff_state_manager.mark_alerted(buff_id, actor_id)

        local alert = onevent.buffgain_alerts[buff_id]
        if alert then
            local ok, soundPath = soundutil.play(addon.path, alert)
            if ok then
                debug_log(('Buff gained [%d] for actor %d: playing "%s"'):format(buff_id, actor_id, alert))
            else
                debug_log(('Buff gained [%d] for actor %d but sound file missing: "%s"'):format(buff_id, actor_id, alert))
            end
        else
            debug_log(('Buff gained [%d] for actor %d but no alert configured.'):format(buff_id, actor_id))
        end
    end
end)

packethandler.buffLoss:register(function(buff_id, actor_id)
    -- Clear alert so future gains will re-trigger sound (centralized, actor-specific)
    buff_state_manager.lose_buff(buff_id, actor_id)

    handle_buff_or_debuff_event(buff_id, actor_id, onevent.bufflose_alerts, 'BuffLost')
end)

packethandler.debuffExpire:register(function(buff_id, actor_id, message_id)
    local scope = classify_actor(actor_id)
    debug_log(('Debuff expired [%d] from actor %d (scope: %s)'):format(buff_id, actor_id, scope))

    handle_buff_or_debuff_event(buff_id, actor_id, onevent.debuffexpire_alerts, 'DebuffExpired')
end)

--------------------------------------------------------------------------------
-- Loaders with validation (now using triggerloader)
--------------------------------------------------------------------------------
local function resolve_cooldown_alerts(alerts)
    local resolved = {}
    local resMgr = AshitaCore:GetResourceManager()
    for k, v in pairs(alerts or {}) do
        local id = tonumber(k)
        local is_spell = false
        if not id then
            -- Try to resolve as ability first
            local ability = resMgr:GetAbilityByName(k, 2)
            if ability then
                id = ability.RecastTimerId
            else
                -- Try to resolve as spell
                local spell = resMgr:GetSpellByName(k, 2)
                if spell then
                    id = spell.Id
                    is_spell = true
                end
            end
        else
            -- If numeric, check if it's a spell ID
            local spell = resMgr:GetSpellById(id)
            if spell then
                is_spell = true
            end
        end
        if id then
            resolved[id] = { sound = v, is_spell = is_spell }
        end
    end
    return resolved
end

local function load_triggers(setname, type)
    local triggerfile = triggerloader.load_trigger(setname, type, addon.path, resolve_cooldown_alerts)
    if not triggerfile then return end
    if type == 'jobs' then
        onevent.job_triggers = T(triggerfile.chat_triggers or {})
        onevent.bufflose_alerts = triggerfile.bufflose_alerts or {}
        onevent.buffgain_alerts = triggerfile.buffgain_alerts or {}
        onevent.debuffexpire_alerts = triggerfile.debuffexpire_alerts or {}
        onevent.cooldown_alerts = triggerfile.cooldown_alerts or {}
        log.info(('Loaded job triggers: %s'):format(setname))
    elseif type == 'bosses' then
        onevent.boss_triggers = T(triggerfile.chat_triggers or triggerfile)
        onevent.boss_packet_triggers = triggerfile.packet_triggers or {}
        log.info(('Loaded boss triggers: %s'):format(setname))
    elseif type == 'zones' then
        onevent.zone_triggers = T(triggerfile)
        log.info(('Loaded zone triggers: %s'):format(setname))
    end
end

local function unload_job_triggers()
    onevent.job_triggers = T{}
    onevent.bufflose_alerts = {}
    onevent.buffgain_alerts = {}
    onevent.debuffexpire_alerts = {}
    log.info('Unloaded old job triggers')
end

--------------------------------------------------------------------------------
-- Table-driven command handler
--------------------------------------------------------------------------------
local commands = {
    add = function(args, raw)
        local s = raw:sub(#args[1]+#args[2]+3)
        local parts = split(s, '|')
        if not parts or #parts < 2 then
            log.error('Usage: /onevent add <trigger>|<action> (found: '..s..')')
            return
        end
        local trigger = trim(parts[1])
        local action = trim(parts[2])
        for _,v in ipairs(onevent.boss_triggers) do
            if v[1]==trigger then
                v[2]=action
                log.info('Updated boss trigger: '..trigger)
                return
            end
        end
        table.insert(onevent.boss_triggers, {trigger, action})
        log.info('Added boss trigger: '..trigger)
    end,
    remove = function(args, raw)
        local t = trim(raw:sub(#args[1]+#args[2]+3))
        for i,v in ipairs(onevent.boss_triggers) do
            if v[1]==t then table.remove(onevent.boss_triggers,i); log.info('Removed boss trigger: '..t); return end
        end
        log.info('No boss trigger found: '..t)
    end,
    removeall = function()
        local b,j,z = #onevent.boss_triggers,#onevent.job_triggers,#onevent.zone_triggers
        onevent.boss_triggers,onevent.job_triggers,onevent.zone_triggers=T{},T{},T{}
        log.info(('Removed all triggers (boss:%d, job:%d, zone:%d)'):fmt(b,j,z))
    end,
    removebossall = function() local n=#onevent.boss_triggers; onevent.boss_triggers=T{}; log.info(('Removed %d boss triggers'):fmt(n)) end,
    removejoball = function() local n=#onevent.job_triggers; onevent.job_triggers=T{}; log.info(('Removed %d job triggers'):fmt(n)) end,
    removezoneall = function() local n=#onevent.zone_triggers; onevent.zone_triggers=T{}; log.info(('Removed %d zone triggers'):fmt(n)) end,
    list = function()
        print('--- Job Triggers ---'); for _,v in ipairs(onevent.job_triggers) do print(v[1]..' => '..v[2]) end
        print('--- Boss Triggers ---'); for _,v in ipairs(onevent.boss_triggers) do print(v[1]..' => '..v[2]) end
        print('--- Zone Triggers ---'); for _,v in ipairs(onevent.zone_triggers) do print(v[1]..' => '..v[2]) end
    end,
    loadjob = function(args) if args[3] then load_triggers(args[3], 'jobs') end end,
    loadboss= function(args) if args[3] then load_triggers(args[3], 'bosses') end end,
    loadzone= function(args) if args[3] then load_triggers(args[3], 'zones') end end,
    auto = function(args) if args[3]=='on' then autoload.auto_load=true log.info('Auto-load on')
        elseif args[3]=='off' then autoload.auto_load=false log.info('Auto-load off')
        else log.info('Usage: /onevent auto on|off') end end,
    debug = function() onevent.debug=not onevent.debug; log.info('Debug: '..tostring(onevent.debug)); log.set_debug(onevent.debug) end,
    pause = function() onevent.paused=true; log.info('Paused.') end,
    unpause = function() onevent.paused=false; log.info('Unpaused.') end,
    help = function() print('Use /onevent help: add, remove, removeall, list, loadjob, loadboss, loadzone, auto, debug, pause, unpause') end,
}

ashita.events.register('command','onevent_cmd',function(e)
    local args=e.command:args()
    if #args>=2 and (args[1]:ieq('/onevent') or args[1]:ieq('/oe')) then
        e.blocked=true
        local cmd=args[2]:lower()
        if commands[cmd] then commands[cmd](args,e.command) else commands.help() end
    end
end)
--------------------------------------------------------------------------------
-- Text_in
--------------------------------------------------------------------------------
ashita.events.register('text_in','react',function(e)
    if not onevent.paused then
        process_triggers(onevent.job_triggers,e)
        process_triggers(onevent.boss_triggers,e)
        process_triggers(onevent.zone_triggers,e)
    end
end)
--------------------------------------------------------------------------------
-- Packet Handling
--------------------------------------------------------------------------------
packethandler.start()
--------------------------------------------------------------------------------
-- Auto-Load
--------------------------------------------------------------------------------
autoload.set_job_trigger_loader(function(setname) load_triggers(setname, 'jobs') end)
autoload.set_job_trigger_unloader(unload_job_triggers)
autoload.set_boss_trigger_loader(function(setname) load_triggers(setname, 'bosses') end)
autoload.set_zone_trigger_loader(function(setname) load_triggers(setname, 'zones') end)

local cooldown_alerts_factory = require('utils.cooldown_alerts')
local cooldown_alerts = cooldown_alerts_factory(
    sounds_path,
    file_exists,
    debug_log,
    function() return onevent.cooldown_alerts end
)
ashita.events.register('d3d_present', 'cooldown_alerts', cooldown_alerts)

ashita.events.register('d3d_present', 'auto', function()
    autoload.check_and_load(
        playerMgr, targetMgr, partyMgr, jobNames, known_bosses,
        debug_log_loaded
    )
end)
