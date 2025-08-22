-- Example zone trigger file demonstrating pattern/action pairs
return {
    { "An unstable rift appears", "/p Rift spawned!;sound:rift.wav" },
    { "The air crackles with energy", "sound:factorio.wav" },
    { "You sense a powerful presence", "/echo Boss incoming!;sound:alert.wav" },
}
