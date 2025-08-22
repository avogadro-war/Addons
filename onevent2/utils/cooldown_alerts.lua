-- Handles polling for ability and spell cooldown ready alerts
local previous_ability_recasts = {}
local previous_spell_recasts = {}

return function(sounds_path, file_exists, debug_log, get_cooldown_alerts)
    return function()
        local mmRecast = AshitaCore:GetMemoryManager():GetRecast()
        local cooldown_alerts = get_cooldown_alerts()
        -- Abilities
        for x = 0, 31 do
            local timer_id = mmRecast:GetAbilityTimerId(x)
            local timer = mmRecast:GetAbilityTimer(x)
            local entry = cooldown_alerts[timer_id]
            if entry and not entry.is_spell then
                local prev = previous_ability_recasts[timer_id] or 0
                if prev > 0 and timer == 0 then
                    local soundPath = sounds_path .. entry.sound
                    if file_exists(soundPath) then
                        ashita.misc.play_sound(soundPath)
                        debug_log(('Ability %d is ready: playing %s'):format(timer_id, entry.sound))
                    end
                end
                previous_ability_recasts[timer_id] = timer
            end
        end
        -- Spells
        for id, entry in pairs(cooldown_alerts) do
            if entry.is_spell then
                local timer = mmRecast:GetSpellTimer(id)
                local prev = previous_spell_recasts[id] or 0
                if prev > 0 and timer == 0 then
                    local soundPath = sounds_path .. entry.sound
                    if file_exists(soundPath) then
                        ashita.misc.play_sound(soundPath)
                        debug_log(('Spell %d is ready: playing %s'):format(id, entry.sound))
                    end
                end
                previous_spell_recasts[id] = timer
            end
        end
    end
end
