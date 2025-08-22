-- Example boss trigger file demonstrating chat and packet triggers
return {
    chat_triggers = T{
        { "The boss is readying.*Ultimate Ability", "/p Ultimate incoming!;sound:alert.wav" },
        { "The boss gains Enrage", "/p Enrage! Kite!;sound:enrage.wav" },
        { "The boss uses Death", "/p Death!;sound:doom.wav" },
    },
    packet_triggers = {
        {
            ability_id = 1234, -- Mob ability ID
            action = { "/echo Mob uses special!;sound:tf2.wav" }
        },
        {
            ability_id = 5678,
            action = "sound:doorcat.wav"
        }
    }
}
