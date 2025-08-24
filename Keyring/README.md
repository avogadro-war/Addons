# Keyring Addon

A Final Fantasy XI addon for Ashita4 that tracks key item cooldowns and provides real-time monitoring of important game items.

## Features

- **Automatic Key Item Detection**: Monitors key item acquisition and loss via packet analysis
- **Real-time Cooldown Tracking**: Tracks cooldowns for items like Moglophone, Shiny Ra'Kaznarian Plate, and Mystical Canteen
- **Dynamic Hourglass Tracking**: Monitors Empty Hourglass time with automatic accrual calculations
- **Ruspix Plate Integration**: Tracks Ruspix Plate time with real-time packet data and dynamic "Ready" status
- **Dynamis [D] Monitoring**: Automatic detection of Dynamis [D] entries with cooldown tracking
- **Interactive GUI**: Real-time display with countdown timers and status indicators
- **Persistent State**: Maintains tracking data across game sessions
- **Smart Notifications**: Zone-change alerts for available key items

## Tracked Items

### Primary Cooldown Items
- **Moglophone** (ID: 3212) - 20-hour cooldown
- **Shiny Ra'Kaznarian Plate** (ID: 3300) - 20-hour cooldown (starts when used for teleport)
- **Mystical Canteen** (ID: 3137) - 20-hour generation cycle

### Special Tracking
- **Empty Hourglass** - Time value with automatic accrual (1 second per 5 seconds elapsed)
- **Dynamis [D] Entry** - 60-hour cooldown with automatic detection
- **Ruspix Plate** - Real-time time tracking with dynamic "Ready" status based on Shiny Plate cooldown

### Other Key Items
- **Ownership tracking** for all tracked key items (no cooldowns)
- **Automatic state updates** via packet analysis

## Commands

### Basic Commands
- `/keyring [gui]` - Toggle the GUI window
- `/keyring check` - Check for available key items
- `/keyring status` - Show addon status and cooldown information
- `/keyring notify` - Toggle zone change notifications

### Utility Commands
- `/keyring manage` - Open item management GUI
- `/keyring additem` - Open item management GUI with Add Item dialog
- `/keyring fix <item>` - Manually trigger acquisition for missed packets
- `/keyring hourglass <seconds>` - Manually set hourglass time
- `/keyring reset_hourglass` - Reset hourglass time to 0

### Debug Commands
- `/keyring debug` - Toggle debug messages in chat
- `/keyring memory` - Show current memory usage
- `/keyring debug_item <item>` - Debug specific item state

## Installation

1. **Download** the Keyring addon folder
2. **Place** it in your Ashita4 `addons/` directory
3. **Load** the addon in-game with `/addon load keyring`
4. **Access** the GUI with `/keyring gui`

## How It Works

### Packet Analysis
- **0x55 packets**: Key item ownership changes
- **0x0A packets**: Zone change detection
- **0x02A packets**: Hourglass and Ruspix Plate time data (improved offset handling)
- **0x05B/0x05C packets**: Ruspix Plate queries and responses
- **0x118 packets**: Canteen storage updates

### State Management
- **Automatic persistence** across game sessions
- **Real-time updates** via packet monitoring
- **Smart cooldown calculations** with accrual tracking and real-time server data updates
- **Zone-based processing** for different packet types

### GUI Features
- **Real-time countdown timers**
- **Color-coded status indicators**
- **Hover tooltips** with detailed information
- **Automatic refresh** on state changes

## Technical Details

### Dependencies
- **Ashita4 Framework**
- **ImGui** for GUI rendering
- **Lua 5.1+** compatibility

### Architecture
- **Packet Handler**: Processes all incoming/outgoing packets
- **Persistence Layer**: Manages state saving/loading
- **GUI System**: Real-time display and user interaction
- **State Management**: Centralized data handling

### Performance
- **Efficient packet processing** with minimal overhead
- **Smart update throttling** to prevent spam
- **Memory-conscious** state management
- **Optimized GUI rendering**

## Version History

- **v0.4.4** - Fixed Ruspix Plate time calculations, improved 0x02A packet handling, enhanced GUI "Ready" logic
- **v0.4.3** - Fixed duplicate zone change handlers, improved packet processing
- **v0.4.2** - Enhanced Ruspix Plate integration, improved cooldown tracking
- **v0.4.1** - Added notification system, improved GUI
- **v0.4.0** - Major rewrite with new architecture
- **v0.3.x** - Legacy versions

## Support

For issues, questions, or contributions:
- **Repository**: [Keyring Addon](https://github.com/avogadro-war/Keyring)
- **FFXINA**: [FFXINA Project](https://github.com/FFXINA)

## License

This addon is provided under the MIT License. See LICENSE file for details.

---

**Note**: This addon automatically detects and tracks key item events. No manual configuration is required for basic functionality. 