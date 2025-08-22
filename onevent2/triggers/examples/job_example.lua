-- Example job trigger file demonstrating all supported features
return {
    chat_triggers = T{
        { "readies Dark Thorn", "/echo Spikes!;sound:mgs.wav" },
        { "Mortal Ray", "/echo Turn!;sound:tf2.wav" },
        { "uses Benediction", "/p Benediction used!;sound:doorcat.wav" },
    },
    buffgain_alerts = {
        [15] = "doom.wav", -- Doom (self only)
        [6] = "debuff.wav", -- Silence (self only)
        [16] = "debuff.wav", -- Amnesia (self only)
        [177] = "debuff.wav", -- Encumbrance (self only)
        [116] = { self = "doorcat.wav", party = "factorio.wav" }, -- Phalanx
    },
    bufflose_alerts = {
        [432] = "doorcat.wav", -- Temper
        [419] = "doorcat.wav", -- Composure
        [48] = "wompwomp.wav", -- Chainspell
        [43] = { self = "doorcat.wav", party = "factorio.wav", other = "agh.wav" }, -- Refresh
        [33] = { self = "doorcat.wav", party = "factorio.wav", other = "wompwomp.wav" }, -- Haste
    },
    debuffexpire_alerts = {
        [15] = "bweep.wav", -- Doom wears off
        [12] = "stop.wav", -- Gravity wears off
    },
    cooldown_alerts = {
        ["Convert"] = "mgsitem.wav", -- Ability name
        [123] = "codec.wav",         -- Ability recast timer ID
        ["Cure IV"] = "rupee.wav",   -- Spell name
        [47] = "rupee.wav",          -- Spell ID
    }
}
