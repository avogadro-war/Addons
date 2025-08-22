# 📦 onevent2 – Ashita4 Addon

Reacts to events defined by trigger files that evaluate and play audio alerts in response to:

- Chat events
- Status Gain and Status Loss (self and party)
- Events in zone
- Boss specific events  
    
Supports auto-loading triggers by job, boss, and zone.

---

## 📂 Directory Structure
```
onevent2/
├── onevent2.lua ← Main addon
├── utils/
│   ├── strings.lua ← String helpers
│   ├── file.lua ← File helpers
│   ├── sound.lua ← Sound helpers
│   ├── log.lua ← Logging helpers
│   ├── triggerloader.lua ← Trigger loading/merging
│   ├── trigger_schema.lua ← Trigger file schema validation
│   └── ...
├── config/
│   └── known.lua ← Tables of known bosses, jobs, zones
├── triggers/
│   ├── jobs/
│   │   ├── sam.lua
│   │   ├── rdm.lua
│   │   ���── ...
│   ├── bosses/
│   │   ├── ody_boss1.lua
│   │   └── ...
│   ├── zones/
│   │   ├── walk_of_echoes.lua
│   │   └── ...
│   └── examples/
│       ├── job_example.lua
│       ├── boss_example.lua
│       └── zone_example.lua
├── sounds/
│   ├── stop.wav
│   └── tf2.wav
│   └── ...
└── ...
```
## ⚙ How it works

Auto-loads triggers based on:

- Your main job  
- Your current zone  
- The current target (if it matches a known boss)

Reacts to:

- Chat messages  
- Buff gain / buff loss (with actor detection)

Executes:

- In-game commands (via `/command`)  
- Plays sound files (WAV)

Uses a deduplication system to avoid reacting multiple times to repeated packets.

---

## 🧩 Components

| File                  | Purpose                                                 |
|-----------------------|---------------------------------------------------------|
| `onevent2.lua`        | Main addon logic, command handler, trigger loading, event hooks |
| `utils/`              | Utility modules for strings, file, sound, logging, trigger loading |
| `config/known.lua`    | Tables of known bosses, zones, jobs (by name or zoneId) |
| `triggers/`           | Contains your custom trigger sets (by job, boss, or zone) |
| `sounds/`             | Sound files to be played when triggers fire             |

---

## ▶️ Usage

**Load addon:**

```bash
/addon load onevent2
```
| Command                          | Description                         |
|---------------------------------|-----------------------------------|
| `/onevent debug`                 | Toggle debug logging               |
| `/onevent pause`                 | Temporarily stop reacting          |
| `/onevent unpause`               | Resume reacting                   |
| `/onevent auto on/off`           | Enable or disable auto-loading of triggers |
| `/onevent add <trigger> \| <action>` | Add a trigger                  |
| `/onevent remove <trigger>`      | Remove a trigger                  |
| `/onevent removeall`             | Remove all triggers               |
| `/onevent removebossall`         | Remove boss triggers              |
| `/onevent removejoball`          | Remove job triggers               |
| `/onevent removezoneall`         | Remove zone triggers              |
| `/onevent list`                  | List currently loaded triggers    |
| `/onevent loadjob <setname>`     | Load job triggers manually        |
| `/onevent loadboss <setname>`    | Load boss triggers manually       |
| `/onevent loadzone <setname>`    | Load zone triggers manually       |

🎵 **Trigger files**

Trigger files are Lua files that return a table. See `triggers/examples/` for full-featured examples.

**Jobs**

- Path: `triggers/jobs/<job>.lua`
- Example: See `triggers/examples/job_example.lua`

**Bosses**

- Path: triggers/bosses/<boss>.lua
- Example: See `triggers/examples/boss_example.lua`

**Zones**

- Path: triggers/zones/<zone>.lua
- Example: See `triggers/examples/zone_example.lua`

✏ **How to add triggers**

- Boss / zone names must be in config/known.lua to auto-load
- Add entries like:
```
known.bosses = {
    ['odin'] = 'odin.lua',
    ['dynamis lord'] = 'dynamis_lord.lua',
}

known.zones = {
    [295] = 'walk_of_echoes' 
}
```
- Trigger files must return a table in the correct format (see examples above).
- Sound files should be in the /sounds folder, named to match what you reference.

🐛 **Debugging tips**

- Use `/onevent debug` to toggle detailed logs.
- Check Ashita console if a sound or command fails.
- Verify your trigger file returns a valid table; syntax errors will prevent loading.
- The addon will warn if your trigger file is missing required keys or has the wrong structure.

📜 **License / Credits**

    Original by atom0s

    Buff tracking, audio alert functionality by Avogadro
    
    Dedupe inspired by Thorny/Simplelog
    
    Buff events / zone change pattern inspired by Will

❤️ Contribute

Have ideas or triggers? Feel free to submit a pull request or share your custom triggers!
