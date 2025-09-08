-- ============================================================================
-- KEYRING ADDON - KEY ITEM COOLDOWN TRACKER
-- ============================================================================
-- Tracks cooldowns and availability of key items in Final Fantasy XI
-- Automatically detects item acquisition, usage, and cooldown states via packet analysis
-- Provides real-time GUI display and notifications for key item management
--
-- Author: Avogadro, with assistance from Thorny and Will
-- Version: 0.4.3
-- ============================================================================

addon.author   = 'Avogadro, assistance from Thorny and Will'
addon.name     = 'Keyring'
addon.version  = '0.4.3'

-- ============================================================================
-- MODULE IMPORTS
-- ============================================================================
require('common')
local chat = require('chat')
local trackedData = require('tracked_key_items')
local key_items = trackedData.key_items
local trackedKeyItems = trackedData.tracked
local packet_tracker = require('keyring_packet_handler')
local gui = require('keyring_gui')
local itemManagementGui = require('item_management_gui')
local persistence = require('keyring_persistence')

-- ============================================================================
-- MODULE INITIALIZATION AND SETUP
-- ============================================================================
-- Inject persistence functions into tracked items module for data persistence
trackedData.set_persistence_functions(
    function(key, data) return persistence.save_data(key, data) end,
    function(key) return persistence.load_data(key) end
)



-- ============================================================================
-- STATE VARIABLES AND CALLBACKS
-- ============================================================================
-- Local storage for canteen state, updated via callback from packet handler
local storage_canteens = 0

-- Set up canteen count callback to keep local state synchronized
packet_tracker.set_currency_callback(function(canteens)
    storage_canteens = canteens
end)

-- Set up GUI update callback to refresh display when persistence data is loaded
packet_tracker.set_gui_update_callback(function()
    -- Force GUI refresh by toggling visibility (this triggers a redraw)
    local was_visible = gui.is_visible()
    if was_visible then
        gui.set_visible(false)
        gui.set_visible(true)
    end
end)

-- ============================================================================
-- CONFIGURATION AND FLAGS
-- ============================================================================
-- Debug and notification system configuration
local debug_mode = false  -- Disable debug mode for normal operation
local notification_enabled = true

-- Player ID detection throttling to prevent spam
local last_player_id_message = 0
local player_id_message_interval = 5  -- Only show message every 5 seconds

-- Note: Storage update throttling is now handled by custom timer system in packet handler

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================
-- Debug output function - only prints when debug mode is enabled
local function debug_print(message)
    if debug_mode then
        print(chat.header('Keyring Debug'):append(chat.message(message)))
    end
end

-- Memory usage monitoring function for debugging and performance tracking
local function get_memory_usage()
    local info = collectgarbage('count')
    return math.floor(info / 1024 * 100) / 100 -- Convert to MB with 2 decimal places
end

-- Synchronize debug mode setting with packet handler module
local function update_debug_mode()
    if packet_tracker.set_debug_mode then
        packet_tracker.set_debug_mode(debug_mode)
    end
end

-- ============================================================================
-- ITEM AVAILABILITY LOGIC
-- ============================================================================
-- Check if a specific item is available for pickup
-- Handles special cases like canteens (storage-based) vs cooldown-based items
local function is_item_available(id)
    if id == 3137 then
        -- Canteen availability: must have storage canteens AND not have one in inventory
        local canteenCount = packet_tracker.get_storage_info().count
        local hasCanteen = packet_tracker.has_key_item(3137)
        return canteenCount > 0 and not hasCanteen
    else
        -- Standard cooldown-based items - check if cooldown is complete
        return packet_tracker.is_available(id)
    end
end

-- ============================================================================
-- ZONE CHANGE NOTIFICATION SYSTEM
-- ============================================================================
-- Set up zone change callback to notify player of available key items
-- Triggers when player zones and checks for items ready for pickup
packet_tracker.set_zone_change_callback(function(current_zone, previous_zone)
    -- Check for available key items after zoning (if notifications are enabled)
    if notification_enabled then
        -- Only show notifications for specific items: Moglophone, Shiny Rakaznarian plate, and Mystical Canteen
        local notification_items = {3212, 3300, 3137}  -- Moglophone, Shiny Rakaznarian plate, Mystical Canteen
        
        for _, id in ipairs(notification_items) do
            local data = trackedKeyItems[id]
            if data then
                local hasItem = packet_tracker.has_key_item(id)
                local itemName = key_items.idToName[id] or ('ID ' .. tostring(id))
                local available = is_item_available(id)
                
                -- Notify if item is available and player doesn't have it
                -- This handles both cooldown-based items and storage-based items (canteens)
                if available and not hasItem then
                    print(chat.header('Keyring'):append(chat.message(string.format('%s is ready for pickup', itemName))))
                end
            end
        end
    end
end)

-- ============================================================================
-- ITEM AVAILABILITY CHECKING
-- ============================================================================
-- Get a list of all key items currently available for pickup
-- Returns item names for items that are ready and not currently owned
local function get_available_items()
    local availableItems = {}
    -- Only check specific items: Moglophone, Shiny Rakaznarian plate, and Mystical Canteen
    local notification_items = {3212, 3300, 3137}  -- Moglophone, Shiny Rakaznarian plate, Mystical Canteen
    
    for _, id in ipairs(notification_items) do
        local data = trackedKeyItems[id]
        if data then
            local hasItem = packet_tracker.has_key_item(id)
            local available = is_item_available(id)
            
            -- Only show if item is available and player doesn't have it
            -- This handles both cooldown-based items and storage-based items (canteens)
            if available and not hasItem then
                local itemName = key_items.idToName[id] or ('ID ' .. tostring(id))
                table.insert(availableItems, itemName)
            end
        end
    end
    return availableItems
end

-- ============================================================================
-- COMMAND HANDLER SYSTEM
-- ============================================================================
-- Main command handler for all /keyring commands
-- Processes user input and executes appropriate addon functions
ashita.events.register('command', 'command_cb', function(e)
    local args = e.command:lower():split(' ')
    if args[1] ~= '/keyring' then return false end

    -- ============================================================================
    -- GUI TOGGLE COMMAND
    -- ============================================================================
    -- Toggle the GUI if no extra args or 'gui'
    if args[2] == nil or args[2] == '' or args[2] == 'gui' then
        local isVisible = gui.toggle()
        print(chat.header('Keyring'):append(chat.message('GUI ' .. (isVisible and 'toggled on.' or 'toggled off.'))))
        
        -- Request fresh currency data (Imprimaturs and canteens) when GUI is opened
        if isVisible then
            packet_tracker.request_currency_data()
        end
        
        return true
    end

    -- ============================================================================
    -- HELP COMMAND
    -- ============================================================================
    -- Display comprehensive help information about the addon and its features
    if args[2] == 'help' then
        print(chat.header('Keyring'):append(chat.message('Keyring Addon v0.4.4 - Key Item Cooldown Tracker')))
        print(chat.message(''))
        print(chat.message('== TRACKED KEY ITEMS =='))
        print(chat.message('  • Moglophone (20h cooldown) - Acquired when obtained'))
        print(chat.message('  • Mystical Canteen (20h generation cycle) - Storage-based tracking'))
        print(chat.message('  • Shiny Ra\'Kaznarian Plate (20h cooldown) - Cooldown starts when used for teleport'))
        print(chat.message('  • Dynamis [D] Entry (60h cooldown) - Auto-detected on zone entry'))
        print(chat.message('  • Empty Hourglass - Time value tracked via NPC interactions'))
        print(chat.message('  • Ruspix Plate - Real-time time tracking with dynamic "Ready" status'))
        print(chat.message('  • Other key items - Ownership tracking (no cooldowns)'))
        print(chat.message(''))
        print(chat.message('== NOTIFICATION ITEMS =='))
        print(chat.message('  • Notifications are limited to: Moglophone, Shiny Ra\'Kaznarian Plate, and Mystical Canteen'))
        print(chat.message('  • Other tracked items are displayed in GUI but do not generate notifications'))
        print(chat.message(''))
        print(chat.message('== BASIC COMMANDS =='))
        print(chat.message('  /keyring [gui] - Toggle the GUI window'))
        print(chat.message('  /keyring check - Check for available key items'))
        print(chat.message('  /keyring status - Show addon status and cooldown information'))
        print(chat.message('  /keyring notify - Toggle zone change notifications (default: on)'))
        print(chat.message('  /keyring manage - Open item management GUI'))
        print(chat.message('  /keyring additem - Open item management GUI with Add Item dialog'))
        print(chat.message(''))
        print(chat.message('== UTILITY COMMANDS =='))
        print(chat.message('  /keyring fix <item> - Manually trigger acquisition for missed packets'))
        print(chat.message('    Available items: moglophone, canteen, plate'))
        print(chat.message('  /keyring hourglass <seconds> - Manually set hourglass time'))
        print(chat.message('  /keyring reset_hourglass - Reset hourglass time to 0'))
        print(chat.message('  /keyring force_hourglass <seconds> - Force hourglass time (bypasses validation)'))
        print(chat.message(''))
        print(chat.message('== DEBUG COMMANDS =='))
        print(chat.message('  /keyring debug - Toggle debug messages in chat'))
        print(chat.message('  /keyring memory - Show current memory usage'))
        print(chat.message('  /keyring debug_item <item> - Debug specific item state'))
        print(chat.message('  /keyring debug_canteen - Show detailed canteen cooldown state'))
        print(chat.message(''))
        print(chat.message('== NOTIFICATIONS =='))
        print(chat.message('  • Individual item acquisition alerts for: Moglophone, Shiny Ra\'Kaznarian Plate, Mystical Canteen'))
        print(chat.message('  • Individual "ready for pickup" alerts on zone change for the same three items'))
        print(chat.message('  • Toggle zone notifications with /keyring notify'))
        print(chat.message(''))
        print(chat.message('== FEATURES =='))
        print(chat.message('  • Automatic packet-based detection of key item events'))
        print(chat.message('  • Real-time GUI with countdown timers'))
        print(chat.message('  • Persistent state across character sessions'))
        print(chat.message('  • Manual acquisition fix for missed packets'))
        print(chat.message('  • Smart cooldown handling per item type'))
        print(chat.message('  • Zone-based automatic Dynamis [D] and Ra\'Kaznar detection'))
        print(chat.message('  • Empty Hourglass time tracking and status display'))
        print(chat.message('  • Enhanced packet handling for improved accuracy'))
        print(chat.message('  • Dynamic Ruspix Plate "Ready" status based on Shiny Plate cooldown'))
        return true
    end

    -- ============================================================================
    -- DEBUG COMMANDS
    -- ============================================================================
    -- Toggle debug mode on/off for troubleshooting and development
    if args[2] == 'debug' then
        debug_mode = not debug_mode
        update_debug_mode()
        print(chat.header('Keyring'):append(chat.message('Debug mode ' .. (debug_mode and 'enabled.' or 'disabled.'))))
        if debug_mode then
            print(chat.header('Keyring'):append(chat.message('Debug messages will now be shown in chat.')))
        end
        return true
    end

    -- ============================================================================
    -- SYSTEM MONITORING COMMANDS
    -- ============================================================================
    -- Display current memory usage for performance monitoring
    if args[2] == 'memory' then
        local memory_mb = get_memory_usage()
        print(chat.header('Keyring'):append(chat.message('Current memory usage: ' .. memory_mb .. ' MB')))
        return true
    end

    -- ============================================================================
    -- NOTIFICATION SYSTEM COMMANDS
    -- ============================================================================
    -- Toggle zone change notifications on/off
    if args[2] == 'notify' then
        notification_enabled = not notification_enabled
        print(chat.header('Keyring'):append(chat.message('Notifications ' .. (notification_enabled and 'enabled.' or 'disabled.'))))
        return true
    end

    -- ============================================================================
    -- ITEM STATUS COMMANDS
    -- ============================================================================
    -- Check current availability of all tracked key items
    if args[2] == 'check' then
        local availableItems = get_available_items()
        
        if #availableItems > 0 then
            -- Show individual callouts for each available item
            for _, itemName in ipairs(availableItems) do
                print(chat.header('Keyring'):append(chat.message(string.format('%s is ready for pickup', itemName))))
            end
        else
            print(chat.header('Keyring'):append(chat.message('No key items are currently available for pickup.')))
        end
        
        -- Debug mode: show detailed availability info
        if debug_mode then
            print(chat.header('Keyring Debug'):append(chat.message('Detailed availability check:')))
            for id, data in pairs(trackedKeyItems) do
                -- Skip items without cooldowns (cooldown = 0 or nil)
                if data.cooldown and data.cooldown > 0 then
                    local timestamp = packet_tracker.get_timestamp(id) or 0
                    local remaining = packet_tracker.get_remaining(id) or 0
                    local hasItem = packet_tracker.has_key_item(id)
                    local itemName = key_items.idToName[id] or ('ID ' .. tostring(id))
                    
                    local status = 'Not available'
                    if timestamp > 0 and remaining <= 0 and not hasItem then
                        status = 'AVAILABLE for pickup'
                    elseif timestamp <= 0 then
                        status = 'No timestamp (Unknown status)'
                    elseif remaining > 0 then
                        local hours = math.floor(remaining / 3600)
                        local minutes = math.floor((remaining % 3600) / 60)
                        status = string.format('On cooldown (%02d:%02d remaining)', hours, minutes)
                    elseif hasItem then
                        status = 'Already owned'
                    end
                    
                    print(chat.message(string.format('  %s: %s (TS:%d, Rem:%d, Own:%s)', 
                        itemName, status, timestamp, remaining, tostring(hasItem))))
                end
            end
        end
        return true
    end

    -- ============================================================================
    -- MANUAL ACQUISITION COMMANDS
    -- ============================================================================
    -- Manually trigger acquisition for missed packets or fix timestamp issues
    if args[2] == 'fix' then
        if not args[3] or args[3] == '' then
            print(chat.header('Keyring'):append(chat.message('Usage: /keyring fix <item>')))
            print(chat.message('Available items: Moglophone, Mystical Canteen, Shiny Ra\'Kaznarian Plate'))
            return true
        end
        
        -- Convert item name to proper case and find ID
        local itemName = args[3]:lower()
        local itemId = nil
        
        -- Create case-insensitive lookup
        for id, name in pairs(key_items.idToName) do
            if name:lower():find(itemName, 1, true) then
                itemId = id
                itemName = name  -- Use the proper name
                break
            end
        end
        
        if not itemId then
            print(chat.header('Keyring'):append(chat.message('Unknown item: ' .. args[3])))
            print(chat.message('Available items: Moglophone, Mystical Canteen, Shiny Ra\'Kaznarian Plate'))
            return true
        end
        
        -- Check if item is already owned
        local hasItem = packet_tracker.has_key_item(itemId)
        local currentTimestamp = packet_tracker.get_timestamp(itemId)
        
        if hasItem and currentTimestamp > 0 then
            print(chat.header('Keyring'):append(chat.message(string.format('%s is already in your inventory with timestamp %d', itemName, currentTimestamp))))
            return true
        end
        
        -- If item is owned but no timestamp, force set the timestamp
        if hasItem and currentTimestamp == 0 then
            print(chat.header('Keyring'):append(chat.message(string.format('%s is owned but missing timestamp - forcing timestamp update', itemName))))
        end
        
        -- Trigger manual acquisition
        local now = os.time()
        local success = packet_tracker.set_timestamp(itemId, now)
        
        if success then
            print(chat.header('Keyring'):append(chat.message(string.format('Manual acquisition triggered for %s - cooldown started', itemName))))
        else
            print(chat.header('Keyring'):append(chat.message('Failed to set timestamp for ' .. itemName)))
        end
        
        return true
    end

    -- ============================================================================
    -- SYSTEM STATUS COMMANDS
    -- ============================================================================
    -- Display comprehensive addon status and system information
    if args[2] == 'status' then
        local dynamis_remaining = packet_tracker.get_dynamis_d_cooldown_remaining()
        local dynamis_available = packet_tracker.is_dynamis_d_available()
        local dynamis_entry_time = packet_tracker.get_dynamis_d_entry_time()
        local is_initialized = packet_tracker.is_initialized()
        
        print(chat.header('Keyring'):append(chat.message('Addon Status:')))
        print(chat.message('  • Persistence: Settings Library'))
        print(chat.message('  • Initialized: ' .. (is_initialized and 'Yes' or 'No')))
        print(chat.message('  • Debug Mode: ' .. (debug_mode and 'Enabled' or 'Disabled')))
        print(chat.message('  • Notifications: ' .. (notification_enabled and 'Enabled' or 'Disabled')))
        print(chat.message('  • Dynamis [D] Status: ' .. (dynamis_available and 'Available' or 'On Cooldown')))
        
        if dynamis_entry_time > 0 then
            local entry_date = os.date('%Y-%m-%d %H:%M:%S', dynamis_entry_time)
            print(chat.message('  • Dynamis [D] Last Entry: ' .. entry_date))
        else
            print(chat.message('  • Dynamis [D] Last Entry: None recorded'))
        end
        
        if dynamis_remaining and dynamis_remaining > 0 then
            local hours = math.floor(dynamis_remaining / 3600)
            local minutes = math.floor((dynamis_remaining % 3600) / 60)
            print(chat.message('  • Dynamis [D] Time Remaining: ' .. string.format('%02d:%02d', hours, minutes)))
        end
        
        return true
    end

    -- ============================================================================
    -- HOURGLASS TIME MANAGEMENT COMMANDS
    -- ============================================================================
    -- Manually set hourglass time for missed packets or testing purposes
    if args[2] == 'hourglass' then
        if not args[3] or args[3] == '' then
            print(chat.header('Keyring'):append(chat.message('Usage: /keyring hourglass <time_in_seconds>')))
            print(chat.message('Example: /keyring hourglass 7200 (for 2 hours)'))
            return true
        end
        
        local hourglass_time = tonumber(args[3])
        if not hourglass_time or hourglass_time < 0 then
            print(chat.header('Keyring'):append(chat.message('Invalid time value. Please provide time in seconds.')))
            return true
        end
        
        local current_state = packet_tracker.get_state()
        local now = os.time()
        
        -- Set hourglass time manually
        current_state.hourglass_time = hourglass_time
        current_state.hourglass_packet_timestamp = now

        packet_tracker.save_state()
        
        local hours = math.floor(hourglass_time / 3600)
        local minutes = math.floor((hourglass_time % 3600) / 60)
        local seconds = hourglass_time % 60
        print(chat.header('Keyring'):append(chat.message(string.format('Manual hourglass time set: %02dh:%02dm:%02ds (%d seconds)', hours, minutes, seconds, hourglass_time))))
        print(chat.header('Keyring'):append(chat.message('Time will be consumed automatically when entering Dynamis [D] with cooldown')))
        
        return true
    end

    -- Reset hourglass time to 0 (clears any stored time value)
    if args[2] == 'reset_hourglass' then
        local success = packet_tracker.reset_hourglass_time()
        if success then
            print(chat.header('Keyring'):append(chat.message('Hourglass time has been reset to 0')))
        else
            print(chat.header('Keyring'):append(chat.message('Failed to reset hourglass time')))
        end
        return true
    end

    -- Force hourglass time to specific value (bypasses packet validation)
    -- Use this for testing or when packet data is corrupted
    if args[2] == 'force_hourglass' then
        if not args[3] or args[3] == '' then
            print(chat.header('Keyring'):append(chat.message('Usage: /keyring force_hourglass <time_in_seconds>')))
            print(chat.message('Example: /keyring force_hourglass 147939'))
            return true
        end
        
        local hourglass_time = tonumber(args[3])
        if not hourglass_time or hourglass_time < 0 then
            print(chat.header('Keyring'):append(chat.message('Invalid time value. Please provide time in seconds.')))
            return true
        end
        
        local success = packet_tracker.force_hourglass_time(hourglass_time)
        if success then
            local hours = math.floor(hourglass_time / 3600)
            local minutes = math.floor((hourglass_time % 3600) / 60)
            local seconds = hourglass_time % 60
            print(chat.header('Keyring'):append(chat.message(string.format('Hourglass time forced to: %02dh:%02dm:%02ds (%d seconds)', hours, minutes, seconds, hourglass_time))))
        else
            print(chat.header('Keyring'):append(chat.message('Failed to force hourglass time')))
        end
        return true
    end

    -- ============================================================================
    -- DYNAMIS [D] MANAGEMENT COMMANDS
    -- ============================================================================
    -- Manually set Dynamis [D] entry timestamp for missed packets or testing
    if args[2] == 'set_dynamis' then
        if not args[3] or args[3] == '' then
            print(chat.header('Keyring'):append(chat.message('Usage: /keyring set_dynamis <timestamp>')))
            print(chat.message('Example: /keyring set_dynamis 1754961008'))
            print(chat.message('Use 0 to clear the timestamp'))
            return true
        end
        
        local timestamp = tonumber(args[3])
        if not timestamp then
            print(chat.header('Keyring'):append(chat.message('Invalid timestamp. Please provide a number.')))
            return true
        end
        
        local current_state = packet_tracker.get_state()
        current_state.dynamis_d_entry_time = timestamp
        packet_tracker.save_state()
        
        if timestamp == 0 then
            print(chat.header('Keyring'):append(chat.message('Dynamis [D] entry timestamp cleared')))
        else
            local date = os.date('%Y-%m-%d %H:%M:%S', timestamp)
            print(chat.header('Keyring'):append(chat.message('Dynamis [D] entry timestamp set to: ' .. date .. ' (' .. timestamp .. ')')))
        end
        
        print(chat.header('Keyring'):append(chat.message('Use /keyring status to see the cooldown')))
        return true
    end





    -- ============================================================================
    -- DEBUG ITEM COMMANDS
    -- ============================================================================
    -- Display detailed debug information for a specific item
    if args[2] == 'debug_item' then
        if not args[3] or args[3] == '' then
            print(chat.header('Keyring'):append(chat.message('Usage: /keyring debug_item <item>')))
            print(chat.message('Example: /keyring debug_item moglophone'))
            return true
        end
        
        -- Convert item name to proper case and find ID
        local itemName = args[3]:lower()
        local itemId = nil
        
        -- Create case-insensitive lookup
        for id, name in pairs(key_items.idToName) do
            if name:lower():find(itemName, 1, true) then
                itemId = id
                itemName = name  -- Use the proper name
                break
            end
        end
        
        if not itemId then
            print(chat.header('Keyring'):append(chat.message('Unknown item: ' .. args[3])))
            return true
        end
        
        local hasItem = packet_tracker.has_key_item(itemId)
        local timestamp = packet_tracker.get_timestamp(itemId)
        local remaining = packet_tracker.get_remaining(itemId)
        
        print(chat.header('Keyring'):append(chat.message('Debug info for ' .. itemName .. ':')))
        print(chat.message('  • Item ID: ' .. itemId))
        print(chat.message('  • Owned: ' .. tostring(hasItem)))
        print(chat.message('  • Timestamp: ' .. timestamp))
        print(chat.message('  • Remaining time: ' .. (remaining or 'N/A')))
        
        if timestamp > 0 then
            local date = os.date('%Y-%m-%d %H:%M:%S', timestamp)
            print(chat.message('  • Acquisition date: ' .. date))
        end
        
        return true
    end

    -- ============================================================================
    -- GUI MANAGEMENT COMMANDS
    -- ============================================================================
    -- Open item management GUI for adding, editing, or removing tracked items
    if args[2] == 'manage' then
        print(chat.header('Keyring'):append(chat.message('Opening item management GUI. Use the GUI to add, edit, or remove tracked items.')))
        itemManagementGui.toggle()
        return true
    end
    
    -- Open item management GUI with Add Item dialog pre-selected
    if args[2] == 'additem' then
        print(chat.header('Keyring'):append(chat.message('Opening item management GUI with Add Item dialog.')))
        itemManagementGui.show_add_item_dialog()
        return true
    end



    -- ============================================================================
    -- ERROR HANDLING
    -- ============================================================================
    -- Unknown command - provide helpful error message
    print(chat.header('Keyring'):append(chat.message('Unknown command. Type /keyring help for available commands.')))
    return true
end)

-- ============================================================================
-- ASHITA EVENT HANDLERS
-- ============================================================================
-- Addon load event - called when the addon is loaded or reloaded
ashita.events.register('load', 'load_cb', function()
    print(chat.header('Keyring'):append(chat.message('Keyring v0.4.2 loaded. Key item state will be initialized when ready.')))
end)

-- ============================================================================
-- MAIN RENDER LOOP
-- ============================================================================
-- Main render loop - called every frame for GUI updates and system maintenance
ashita.events.register('d3d_present', 'render', function()
    -- Wrap everything in pcall to prevent crashes and ensure stability
    local success, err = pcall(function()
        -- Check for player ID and initialize packet tracking system if needed
        if not packet_tracker.is_initialized() then
            local mem = AshitaCore:GetMemoryManager()
            if mem then
                local party = mem:GetParty()
                if party then
                    local player_id = party:GetMemberServerId(0)
                    if player_id and player_id > 0 then
                        -- Throttle the player ID detection message to prevent spam
                        local current_time = os.time()
                        if current_time - last_player_id_message >= player_id_message_interval then
                            print(chat.header('Keyring'):append(chat.message('Player ID detected: ' .. player_id .. ' - Initializing...')))
                            last_player_id_message = current_time
                        end
                        packet_tracker.initialize_player(player_id)
                    end
                end
            end
            -- Render GUI during initialization with empty data (shows loading state)
            local keyItemStatuses = {}
            gui.render(keyItemStatuses, trackedKeyItems, 0, packet_tracker)
            return
        end
    end)
    
    if not success then
        print(chat.header('Keyring'):append(chat.message('Error in render loop: ' .. tostring(err))))
        return
    end
    
    -- Continue with normal operation if initialization is complete
    if packet_tracker.is_initialized() then
        -- Use our custom timer system instead of manual time checks
        -- This handles all cooldown and generation timers automatically
        packet_tracker.check_all_timers()
        
        -- Update storage canteens from the timer system
        -- This keeps our local state synchronized with the packet handler
        storage_canteens = packet_tracker.get_storage_info().count
        
        -- Update Imprimatur count in GUI
        local imprimatur_count = packet_tracker.get_imprimatur_count()
        gui.set_imprimatur_count(imprimatur_count)

        -- Render the main GUI using the modularized GUI system
        -- Pass all necessary data for proper display
        local keyItemStatuses = packet_tracker.get_key_item_statuses()
        gui.render(keyItemStatuses, trackedKeyItems, storage_canteens, packet_tracker)
        
        -- Render the item management GUI (if it's open)
        itemManagementGui.render()
    end
end)