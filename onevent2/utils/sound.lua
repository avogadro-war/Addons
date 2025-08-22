--[[
    sound.lua
    Sound playback utility: sound.play(addon_path, sound_name)
    Usage: local sound = require('utils.sound')
]]

local file = require('utils.file')

local sound = {}

function sound.play(addon_path, sound_name)
    local soundPath = addon_path .. 'sounds/' .. sound_name
    if file.exists(soundPath) then
        ashita.misc.play_sound(soundPath)
        return true, soundPath
    end
    return false, soundPath
end

return sound
