local event         = require('utils.event')
local packet_dedupe = require('utils.packet_dedupe')
local struct        = require('struct')
local chat          = require('chat')
local buff_state_manager = require('utils.buff_state_manager')

local packethandler = {
    buffGain = event:new(),
    buffLoss = event:new(),
    debuffExpire = event:new(),
    onZoneChange = event:new(),
    get_debug = nil,
}

local function debug_log(msg)
    if packethandler.get_debug and packethandler.get_debug() then
        print(chat.header('onevent2'):append(chat.message(msg)))
    end
end

function packethandler.start()
    ashita.events.register('packet_in', 'packet_in_handlers', function(e)
        packet_dedupe.record_packets(e)

        -- Zone change packet
        if e.id == 0x00A then
            local zoneId = struct.unpack('H', e.data, 0x10+1)
            packethandler.onZoneChange:trigger(zoneId)
            debug_log(('Zone change detected: %d'):format(zoneId))
            buff_state_manager.reset_all()

        -- Action Message Packet
        elseif e.id == 0x29 then
            if packet_dedupe.check_duplicates(e) then return end

            local message_id = struct.unpack('H', e.data, 0x18+1)
            local actor_id   = struct.unpack('I', e.data, 0x08+1)
            local buff_id    = struct.unpack('I', e.data, 0x0C+1)

            local expire_messages = T{ 64, 204, 205, 206, 321, 322, 350, 351 }

            if message_id == 206 and buff_id then
                packethandler.buffLoss:trigger(buff_id, actor_id)
                buff_state_manager.lose_buff(buff_id, actor_id)
                debug_log(('Buff %d lost by actor %d'):format(buff_id, actor_id))

            elseif expire_messages:contains(message_id) and buff_id then
                packethandler.debuffExpire:trigger(buff_id, actor_id, message_id)
                buff_state_manager.lose_buff(buff_id, actor_id)
                debug_log(('Debuff %d expired on actor %d; message_id %d'):format(buff_id, actor_id, message_id))
            end

        -- Buff Sync Packet (0x028)
        elseif e.id == 0x028 then
            -- Action Packet: print debug info for mob abilities (category 7)
            local actor_id = struct.unpack('I', e.data, 0x04+1)
            local category = struct.unpack('B', e.data, 0x0A+1)
            local param = struct.unpack('H', e.data, 0x0C+1)
            if category == 7 then
                local resMgr = AshitaCore:GetResourceManager()
                local ability = resMgr:GetAbilityByTimerId(param) or resMgr:GetAbilityById(param)
                local ability_name = ability and ability.Name[1] or 'Unknown'
                local entityMgr = AshitaCore:GetMemoryManager():GetEntity()
                local actor_name = 'Unknown'
                for i = 0, 2303 do
                    if entityMgr:GetServerId(i) == actor_id then
                        actor_name = entityMgr:GetName(i)
                        break
                    end
                end
                print(string.format('[DEBUG] Mob Ability: %s (ID: %d) used by %s (ID: %d)', ability_name, param, actor_name, actor_id))

                -- Boss packet_triggers integration
                local onevent = require('onevent2')
                for _, trigger in ipairs(onevent.boss_packet_triggers or {}) do
                    if trigger.ability_id == param then
                        local actions = {}
                        if type(trigger.action) == 'string' then
                            actions = {trigger.action}
                        elseif type(trigger.action) == 'table' then
                            actions = trigger.action
                        end
                        for _, act in ipairs(actions) do
                            act = act:match('^%s*(.-)%s*$')
                            if act:lower():startswith('sound:') then
                                local soundPath = addon.path .. 'sounds\\' .. act:sub(7):trim()
                                local ok, f = pcall(io.open, soundPath, "r")
                                if ok and f then f:close(); ashita.misc.play_sound(soundPath) end
                            else
                                if AshitaCore and AshitaCore:GetChatManager() then
                                    AshitaCore:GetChatManager():QueueCommand(1, act)
                                end
                            end
                        end
                    end
                end
            end

        -- Buff Sync Packet (0x063)
        elseif e.id == 0x063 then
            if packet_dedupe.check_duplicates(e) then return end

            local type = ashita.bits.unpack_be(e.data_raw, 32, 8)
            if type ~= 0x09 then return end

            local new_buffs = {}
            for i = 1, 32 do
                local buff = struct.unpack('<H', e.data, 0x07 + 2 * i)
                if buff ~= 0 and buff ~= 255 then
                    new_buffs[buff] = true
                end
            end

            -- No just_zoned logic needed; per-actor alert suppression handles duplicate alerts

            -- Trigger buff gain
            -- NOTE: Buff Sync packets do not provide actor_id, so assume 'self' for now
            local self_id = AshitaCore and AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0)
            for buff_id, _ in pairs(new_buffs) do
                if buff_state_manager.gain_buff(buff_id, self_id) then
                    packethandler.buffGain:trigger(buff_id, self_id)
                    debug_log(('Gained buff %d for actor %d'):format(buff_id, self_id))
                    buff_state_manager.mark_alerted(buff_id, self_id)
                end
            end

            -- Trigger buff loss
            for buff_id, actors in pairs(buff_state_manager.current_buffs) do
                if not new_buffs[buff_id] then
                    -- Remove for self only
                    packethandler.buffLoss:trigger(buff_id, self_id)
                    debug_log(('Lost buff %d for actor %d'):format(buff_id, self_id))
                    buff_state_manager.lose_buff(buff_id, self_id)
                end
            end
        end
    end)
end

return packethandler