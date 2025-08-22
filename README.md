# Keyring - Final Fantasy XI Key Item Cooldown Tracker

A Final Fantasy XI addon for Ashita4 that tracks key items with cooldown timers, providing real-time status updates and individual item notifications.

## Features

- **Automatic Detection**: Automatically detects when key items are acquired via packet interception
- **Real-time Tracking**: Live countdown timers for key item cooldowns
- **Individual Notifications**: Each item gets specific callouts instead of general messages
- **Zone Change Alerts**: Individual "ready for pickup" notifications when zoning
- **Special Canteen Tracking**: Advanced tracking for Mystical Canteen with storage system (1/3, 2/3, 3/3)
- **Dynamis [D] Tracking**: Automatic detection of Dynamis [D] zone entries with 60-hour cooldown tracking
- **Empty Hourglass Tracking**: Automatic detection via NPC interactions with time value tracking and status display
- **Manual Fix Command**: Recover from missed packets with manual acquisition triggers
- **Persistent State**: Remembers timestamps across game sessions
- **Modern GUI**: Clean, responsive interface with dynamic sizing
- **Toggleable Notifications**: Full control over zone change notifications
- **Item Management**: Add, edit, or remove tracked items through an intuitive GUI

## Tracked Items

The addon currently tracks these items with their respective cooldowns:

### Key Items with Cooldowns
- **Moglophone** (20h cooldown) - Cooldown starts when acquired
- **Mystical Canteen** (20h generation cycle) - Storage-based tracking (up to 3 canteens)
- **Shiny Ra'Kaznarian Plate** (20h cooldown) - Cooldown starts when used for teleport

### Special Cooldowns
- **Dynamis [D] Entry** (60h cooldown) - Auto-detected when entering Dynamis [D] zones:
  - Southern San d'Oria (230) → Dynamis-San d'Oria [D] (294)
  - Bastok Mines (234) → Dynamis-Bastok [D] (295)
  - Windurst Walls (239) → Dynamis-Windurst [D] (296)
  - Ru'Lude Gardens (243) → Dynamis-Jeuno [D] (297)
- **Empty Hourglass** - Time value tracked via NPC interactions with status display

### Items Without Cooldowns
- **Ambuscade Primer Vol. 1 & 2** - Ownership tracking only
- **Other key items** - Can be added via the management GUI

## Notification System

### Notification Items
**Notifications are limited to these three items:**
- **Moglophone** - Acquisition and ready-for-pickup notifications
- **Shiny Rakaznarian plate** - Usage and ready-for-pickup notifications  
- **Mystical Canteen** - Acquisition and ready-for-pickup notifications

### Other Tracked Items
All other tracked items are displayed in the GUI with their status and cooldown information, but do not generate chat notifications. This includes:
- Ambuscade Primer Vol. 1 & 2
- Dynamis [D] Entry status
- Empty Hourglass time
- Any additional items added via the management GUI

## Installation

1. Download the addon files
2. Place the `Keyring` folder in your Ashita4 `addons` directory:
   ```
   Ashita4/addons/Keyring/
   ```
3. Load the addon in-game with:
   ```
   /addon load keyring
   ```

## Commands

### Basic Commands
| Command | Description |
|---------|-------------|
| `/keyring` or `/keyring gui` | Toggle the GUI window |
| `/keyring check` | Check for available key items |
| `/keyring status` | Show addon status and cooldown information |
| `/keyring notify` | Toggle zone change notifications (default: on) |
| `/keyring manage` | Open item management GUI |
| `/keyring additem` | Open item management GUI with Add Item dialog |

### Utility Commands
| Command | Description |
|---------|-------------|
| `/keyring fix <item>` | Manually trigger acquisition for missed packets |
| `/keyring hourglass <seconds>` | Manually set hourglass time |
| `/keyring reset_hourglass` | Reset hourglass time to 0 |
| `/keyring force_hourglass <seconds>` | Force hourglass time (bypasses validation) |
| `/keyring set_dynamis <timestamp>` | Manually set Dynamis [D] entry timestamp |

### Fix Command Examples
- `/keyring fix moglophone` or `/keyring fix mog`
- `/keyring fix canteen` or `/keyring fix mystical`
- `/keyring fix plate` or `/keyring fix rakaznar`



### Debug Commands
| Command | Description |
|---------|-------------|
| `/keyring debug` | Toggle debug messages in chat |
| `/keyring memory` | Show current memory usage |
| `/keyring debug_item <item>` | Debug specific item state |

## GUI Interface

The addon provides a clean, responsive GUI with several main sections:

### Key Items Section
- **Key Item**: Name of the tracked item
- **Have?**: Whether you currently possess the item (Yes/No)
- **Time Remaining**: Current status with countdown timer

### Dynamis [D] Section
- **Status**: Whether Dynamis [D] entry is available or on cooldown
- **Time Remaining**: Countdown timer for the 60-hour cooldown
- **Last Entry**: Timestamp of the last Dynamis [D] entry

### Empty Hourglass Section
- **Status**: "Ready" (green) when hourglass time ≥ remaining Dynamis cooldown, "Not enough time" (red) otherwise
- **Time Display**: Shows the current hourglass time value in hh:mm:ss format

### Item Management GUI
- **Add Item**: Add new key items to track with custom cooldowns
- **Edit Item**: Modify existing item properties
- **Remove Item**: Remove items from tracking


### Status Colors

- **Gray**: "Unknown" - No acquisition time recorded yet
- **Green**: "Available" - Item is off cooldown and can be acquired
- **Red**: Countdown timer - Shows remaining time until available
- **White**: Canteen storage count (e.g., "Available (2/3)")
- **Yellow**: Dynamis [D] section header
- **Green/Red**: Dynamis [D] availability status
- **Green/Red**: Empty Hourglass status ("Ready" / "Not enough time")
- **Green/Gray**: Items without cooldowns ("Owned" / "Not Owned")

## How It Works

### Automatic Detection
The addon intercepts network packets to detect when key items are acquired, automatically recording timestamps for accurate cooldown tracking.

### Individual Notifications System
The addon provides specific, individual notifications for the three primary key items:

#### Acquisition Notifications (Always On)
- "Moglophone acquired - 20-hour cooldown started"
- "Acquired Mystical Canteen - cooldown started"
- "Shiny Rakaznarian Plate acquired - cooldown starts when used for teleport"

#### Zone Change Notifications (Toggleable)
When you zone into a new area, individual "ready for pickup" alerts for the three notification items:
- "Moglophone is ready for pickup"
- "Mystical Canteen is ready for pickup"
- "Shiny Ra'Kaznarian Plate is ready for pickup"

**Note**: Other tracked items (Ambuscade Primers, Dynamis [D] status, etc.) are displayed in the GUI but do not generate chat notifications.

### Special Canteen Handling
The Mystical Canteen has a unique storage system where you can hold up to 3 canteens. The addon tracks this storage count and displays it alongside the availability status.

### Dynamis [D] Tracking
The addon automatically detects when you enter a Dynamis [D] zone by monitoring zone transitions from specific pre-Dynamis areas. When a valid transition is detected, it records the entry time and starts the 60-hour cooldown timer.

### Empty Hourglass Tracking
The addon tracks the time value stored in the Empty Hourglass by intercepting 0x02A packets when interacting with the Enigmatic Footprints NPC. The hourglass time is displayed in the GUI with a status indicator showing whether it's sufficient to bypass the current Dynamis [D] cooldown.

### Items Without Cooldowns
The addon can track key items that don't have cooldowns by setting their cooldown value to 0 in the configuration. These items are tracked for ownership status only - showing whether the player currently has them in their inventory or not.

### Persistent Storage
The addon uses Ashita's settings library for character-aware persistence.

- Storage location: `AshitaCore/config/addons/Keyring/<CharacterName_ServerId>/settings.lua`
- Automatic character switching: handled by the library on login/logout/zone events


## File Structure

```
Keyring/
├── keyring.lua                    # Main addon file with command handling
├── keyring_packet_handler.lua     # Packet interception and state management
├── keyring_gui.lua               # GUI rendering module
├── item_management_gui.lua       # Item management interface
├── tracked_key_items.lua         # Configuration of tracked items
├── key_items_reference.lua       # Full key item reference
├── keyring_persistence.lua       # Persistence system
├── data/                         # Data directory for settings
└── README.md                     # This file
```

### Module Overview

- **`keyring.lua`**: Main addon entry point, command handling, and event registration
- **`keyring_packet_handler.lua`**: Network packet interception and state management
- **`keyring_gui.lua`**: ImGui rendering logic and window management
- **`item_management_gui.lua`**: Interface for managing tracked items
- **`tracked_key_items.lua`**: Configuration of tracked items with names, cooldowns, and optimized mappings
- **`key_items_reference.lua`**: Complete key item ID to name mappings
- **`keyring_persistence.lua`**: Wrapper around Ashita settings library with legacy migration support

## Requirements

- Final Fantasy XI
- Ashita4 client
- Windows operating system

## Troubleshooting

### Settings Module Error
If you encounter a settings module error on first load, the addon will automatically fall back to internal storage. This is normal for fresh installations.

### Debug Mode
Enable debug mode with `/keyring debug` to see detailed packet information and troubleshooting messages.

### Manual State Reset
If tracking becomes inaccurate, you can:

#### Fix Individual Items
Use the fix command to manually trigger acquisition for missed packets:
- `/keyring fix moglophone` - If the addon missed your Moglophone acquisition
- `/keyring fix canteen` - If canteen tracking is out of sync
- `/keyring fix plate` - If Rakaznar Plate cooldown wasn't detected

#### Complete Reset
For complete reset:
1. Unload the addon: `/addon unload keyring`
2. Delete the character-specific settings file:
   `config/addons/Keyring/<CharacterName_ServerId>/settings.lua`
3. Reload the addon: `/addon load keyring`

**Note**: Each character has their own settings file, so you can reset tracking for one character without affecting others.

## Contributing

Feel free to submit issues, feature requests, or pull requests to improve the addon.

## Credits

- **Author**: Avogadro
- **Assistance**: Thorny and Will
- **Special Thanks**: To the Ashita4 community for packet analysis and technical support

## License

This addon is provided as-is for the Final Fantasy XI community. Use at your own discretion.

## Performance & Optimization

The addon has been optimized for performance and maintainability:

- **Memory Efficiency**: Uses optimized key item mappings that only load tracked items
- **Caching**: Implements intelligent caching for storage calculations to reduce redundant computations
- **Modular Design**: Separated concerns into dedicated modules for better maintainability
- **Error Handling**: Comprehensive input validation and error handling throughout
- **Settings Management**: Unified Lua-based settings system
- **Clean Code**: Removed outdated debug commands and streamlined functionality

## Version History

- **v0.4.1**: Fixed false acquisition messages when items are lost
  - **Corrected notification logic**: Acquisition messages now only show when items are actually gained (ownership changes from "Don't Have" to "Have")
  - **Eliminated false positives**: No more "Acquired [Item]" messages when items are being lost or consumed
  - **Better user experience**: Notifications now accurately reflect actual item acquisition events
  - **Fixed Mystical Canteen bug**: Resolved issue where losing a canteen would show acquisition message

- **v0.4.0**: Restructured 0x02A packet handler with zone-based separation
  - **Zone-based processing**: 0x02A packets now only process Hourglass data in pre-Dynamis zones (Southern San Doria, Bastok Mines, Windurst Walls, Ru'Lude Gardens)
  - **Eliminated unnecessary processing**: Ruspix Plate data only processed in Outer Ra'Kaznar zones (U1, U2, U3)
  - **Improved efficiency**: No more processing irrelevant data based on location
  - **Better structure**: Clear separation of concerns with zone validation before processing
  - **Enhanced debugging**: Added zone-specific debug messages for better troubleshooting

- **v0.3.9**: Fixed Shiny Ra'Kaznarian Plate acquisition message
  - **Corrected acquisition notification**: Changed "Acquired Shiny Ra'Kaznarian Plate - cooldown started" to "Acquired Shiny Ra'Kaznarian Plate - cooldown starts when used for teleport"
  - **Accurate item behavior**: Now correctly reflects that the plate doesn't start a cooldown when acquired, only when used for teleportation
  - **Smart messaging**: Different messages for items that start cooldowns on acquisition (Moglophone, Canteen) vs. items that don't (Shiny Plate)
  - **Better user understanding**: No more confusion about when cooldowns actually start

- **v0.3.8**: Improved naming consistency and message accuracy
  - **Standardized item names**: Updated all references to use consistent "Shiny Ra'Kaznarian Plate" naming
  - **Fixed acquisition message**: Changed "Shiny Rakaznarian Plate used - 20-hour cooldown started" to "Shiny Ra'Kaznarian Plate acquired - cooldown starts when used for teleport"
  - **Better user clarity**: Help text and documentation now accurately reflect that the plate cooldown starts on teleport usage, not acquisition
  - **Consistent terminology**: Unified naming across help menu, commands, and documentation

- **v0.3.7**: Enhanced Ruspix Plate safety checks
  - **Prevented false timestamps**: Added safety check to prevent 0x05C packets from setting timestamps when Shiny Rakaznarian Plate cooldown is 0 or nil
  - **Better error handling**: Improved debug messages for edge cases
  - **Enhanced stability**: Prevents potential false cooldown starts when plate isn't on cooldown
  - **Smart packet processing**: Only processes Ruspix Plate packets when there's a valid cooldown to work with

- **v0.3.6**: Removed non-functional backup system
  - **Cleaned up help menu**: Removed backup commands that were never implemented
  - **Removed backup handlers**: Eliminated command handlers for non-existent backup functions
  - **Updated documentation**: Removed all backup-related references from README
  - **Streamlined commands**: Help menu now only shows functional commands
  - **Better user experience**: No more confusion about non-working backup features

- **v0.3.5**: Final cleanup and optimization
  - **Fixed missing variable**: Added proper declaration for `last_storage_update` variable
  - **Removed duplicate code**: Eliminated duplicate hex dump code in packet handler
  - **Simplified debug system**: Streamlined debug throttling system for better performance
  - **Removed unused variables**: Cleaned up unused variables and test messages
  - **Code optimization**: Reduced complexity and improved maintainability
  - **Enhanced stability**: All potential variable scope issues resolved

- **v0.3.4**: Critical bug fix and code cleanup
  - **Fixed critical crash**: Resolved `current_state` scope issue in packet handler that was causing addon to crash and unload
  - **Code cleanup**: Removed outdated debug and test commands that were no longer needed
  - **Improved help system**: Better organized command categories and descriptions
  - **Streamlined code**: Removed unnecessary fallback timers and debug functions
  - **Enhanced documentation**: Updated README with cleaner organization and current feature set
  - **Better user experience**: Cleaner, more focused command set with logical grouping
  - **Stability improvement**: Addon now runs without critical errors

- **v0.3.3**: Code cleanup and improved organization
  - **Removed outdated commands**: Cleaned up debug and test commands that were no longer needed
  - **Improved help system**: Better organized command categories and descriptions
  - **Streamlined code**: Removed unnecessary fallback timers and debug functions
  - **Enhanced documentation**: Updated README with cleaner organization and current feature set
  - **Better user experience**: Cleaner, more focused command set with logical grouping

- **v0.3.2**: Empty Hourglass tracking and items without cooldowns
  - **Empty Hourglass tracking**: Added automatic detection of hourglass time via 0x02A packet parsing
  - **Status display**: Shows "Ready" (green) when hourglass time ≥ remaining Dynamis cooldown, "Not enough time" (red) otherwise
  - **Manual hourglass commands**: Added `/keyring hourglass`, `/keyring reset_hourglass`, and `/keyring force_hourglass` commands
  - **Packet parsing fix**: Corrected 0x02A packet offset for accurate hourglass time reading
  - **GUI integration**: Added Empty Hourglass section to the GUI with time display and status indicators
  - **Items without cooldowns**: Added support for tracking key items that don't have cooldowns (ownership only)
  - **Debug cleanup**: Removed superfluous debug output for cleaner chat experience

- **v0.3.1**: Individual notifications and manual fix functionality
  - **Individual item notifications**: Replaced general "One or more items available" with specific per-item callouts
  - **Zone change individual alerts**: Each available item now gets its own "ready for pickup" notification
  - **Manual fix command**: Added `/keyring fix <item>` to manually trigger acquisition for missed packets
  - **Enhanced help system**: Comprehensive help with organized sections for commands, notifications, and features
  - **Improved notification control**: Cleaner distinction between always-on acquisition alerts and toggleable zone notifications
  - **Better user experience**: No more grouped notifications - each item gets specific, actionable feedback
  - **Flexible item name matching**: Fix command accepts partial names (e.g., "mog", "canteen", "plate")
  - **Enhanced command documentation**: Updated README and help with detailed examples and usage instructions

- **v0.3.0**: Enhanced Shiny Ra'Kaznarian Plate tracking and improved detection systems
  - **Fixed Shiny Ra'Kaznarian Plate cooldown logic**: Cooldown now starts when the plate is used/lost, not when acquired
  - **Dual detection system**: Both zone transition detection (0x0A packets) and key item loss detection (0x55 packets) for Shiny Ra'Kaznarian Plate
  - **Improved zone transition detection**: More reliable detection of Ra'Kaznar zone transitions from Kamihr Drifts to Outer Ra'Kaznar zones
  - **Enhanced packet handling**: Better handling of key item acquisition and loss events
  - **Redundant safety systems**: Multiple detection methods ensure accurate cooldown tracking even if one method fails
  - **Updated persistence system**: Improved state management for accurate timestamp tracking
  - **Character-specific persistence**: Each character now has their own settings file, preventing data conflicts between characters
  - **Better user feedback**: Clear messages when Shiny Ra'Kaznarian Plate is acquired, used, or lost
  - **Dynamis [D] tracking system**: Automatic detection of Dynamis [D] zone entries with 60-hour cooldown tracking
  - **Zone transition monitoring**: Monitors transitions from pre-Dynamis zones to Dynamis [D] zones for accurate entry detection

- **v0.2.0**: Performance and code organization improvements
  - Modular architecture with separated GUI and settings management
  - Memory optimization with targeted key item mappings
  - Caching system for storage calculations
  - Enhanced error handling and input validation
  - Centralized constants and configuration
  - Improved documentation and code structure

- **v0.1.0**: Initial release with core tracking functionality
  - Basic key item cooldown tracking
  - GUI interface
  - Packet-based detection
  - Zone change notifications
  - Special canteen handling
  - Persistent state storage 