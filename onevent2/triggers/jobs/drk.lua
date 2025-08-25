return {
    chat_triggers = T{
        { "Mortal Ray", "/echo Turn!;sound:tf2.wav" },
        { "Danse Macabre", "/ma \"Stun\" <t>,sound:tf2.wav" },
    },
    buffgain_alerts = {
        [15] = "doom.wav", -- Doom (self only)
        [6] = "debuff.wav", -- Silence (self only)
        ["Paralyze"] = "debuff.wav", -- Paralyze (self only, by name)
        [16] = "debuff.wav", -- Amnesia (self only)
        [177] = "debuff.wav", -- Encumbrance (self only)
    },
    bufflose_alerts = {
        [330] = "wompwomp.wav", -- Soul Enslavement
        ["Haste"] = { self = "doorcat.wav" }, -- Haste
        [88] = 'agh.wav',  -- HP Boost
        [353] = 'factorio.wav',  -- Hasso
        [354] = 'factorio.wav',  -- Seigan'
    },
    debuffexpire_alerts = {
    },
    cooldown_alerts = {
        [35] = "mgsitem.wav", -- Last Resort
    }
}