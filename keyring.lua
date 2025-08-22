addon.author   = 'Avogadro, assistance from Thorny and Will'
addon.name     = 'Keyring'
addon.version  = '0.4.1'

require('common')
local chat = require('chat')
local trackedData = require('tracked_key_items')
local key_items = trackedData.key_items
local trackedKeyItems = trackedData.tracked
local packet_tracker = require('keyring_packet_handler')
local gui = require('keyring_gui')
local itemManagementGui = require('item_management_gui')
local persistence = require('keyring_persistence')

-- Inject persistence functions into tracked items module
trackedData.set_persistence_functions(
    function(key, data) return persistence.save_data(key, data) end,
    function(key) return persistence.load_data(key) end
)

-- Local copies of canteen state, updated via callback
local storage_canteens = 0

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

-- Zone tracking (now handled by packet handler)

-- Debug and notification flags
local debug_mode = false  -- Disable debug mode for normal operation
local notification_enabled = true

-- Player ID detection throttling
local last_player_id_message = 0
local player_id_message_interval = 5  -- Only show message every 5 seconds

-- Storage update throttling
local last_storage_update = 0

-- Debug helper function
local function debug_print(message)
    if debug_mode then
        print(chat.header('Keyring Debug'):append(chat.message(message)))
    end
end

-- Memory monitoring function (for debugging)
local function get_memory_usage()
    local info = collectgarbage('count')
    return math.floor(info / 1024 * 100) / 100 -- Convert to MB with 2 decimal places
end

-- Set debug mode in packet handler
local function update_debug_mode()
    if packet_tracker.set_debug_mode then
        packet_tracker.set_debug_mode(debug_mode)
    end
end

-- Helper function to check if item is available
local function is_item_available(id)
    if id == 3137 then
        -- Canteen availability: must have storage canteens AND not have one in inventory
        local canteenCount = packet_tracker.get_storage_info().count
        local hasCanteen = packet_tracker.has_key_item(3137)
        return canteenCount > 0 and not hasCanteen
    else
        return packet_tracker.is_available(id)
    end
end

-- Set up zone change callback
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

-- Helper function to get available items for pickup
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

-- Command handler
ashita.events.register('command', 'command_cb', function(e)
    local args = e.command:lower():split(' ')
    if args[1] ~= '/keyring' then return false end

    -- Toggle the GUI if no extra args or 'gui'
    if args[2] == nil or args[2] == '' or args[2] == 'gui' then
        local isVisible = gui.toggle()
        print(chat.header('Keyring'):append(chat.message('GUI ' .. (isVisible and 'toggled on.' or 'toggled off.'))))
        return true
    end

    -- Help command
    if args[2] == 'help' then
        print(chat.header('Keyring'):append(chat.message('Keyring Addon v0.4.1 - Key Item Cooldown Tracker')))
        print(chat.message(''))
        print(chat.message('== TRACKED KEY ITEMS =='))
        print(chat.message('  • Moglophone (20h cooldown) - Acquired when obtained'))
        print(chat.message('  • Mystical Canteen (20h generation cycle) - Storage-based tracking'))
        print(chat.message('  • Shiny Ra\'Kaznarian Plate (20h cooldown) - Cooldown starts when used for teleport'))
        print(chat.message('  • Dynamis [D] Entry (60h cooldown) - Auto-detected on zone entry'))
        print(chat.message('  • Empty Hourglass - Time value tracked via NPC interactions'))
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
        return true
    end

    -- Debug toggle
    if args[2] == 'debug' then
        debug_mode = not debug_mode
        update_debug_mode()
        print(chat.header('Keyring'):append(chat.message('Debug mode ' .. (debug_mode and 'enabled.' or 'disabled.'))))
        if debug_mode then
            print(chat.header('Keyring'):append(chat.message('Debug messages will now be shown in chat.')))
        end
        return true
    end

    -- Memory usage command
    if args[2] == 'memory' then
        local memory_mb = get_memory_usage()
        print(chat.header('Keyring'):append(chat.message('Current memory usage: ' .. memory_mb .. ' MB')))
        return true
    end

    -- Notification toggle
    if args[2] == 'notify' then
        notification_enabled = not notification_enabled
        print(chat.header('Keyring'):append(chat.message('Notifications ' .. (notification_enabled and 'enabled.' or 'disabled.'))))
        return true
    end

    -- Check command
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

    -- Fix command - manually trigger acquisition for missed packets
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

    -- Status command
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

    -- Manual hourglass command - set hourglass time for missed packets
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

    -- Reset hourglass time command
    if args[2] == 'reset_hourglass' then
        local success = packet_tracker.reset_hourglass_time()
        if success then
            print(chat.header('Keyring'):append(chat.message('Hourglass time has been reset to 0')))
        else
            print(chat.header('Keyring'):append(chat.message('Failed to reset hourglass time')))
        end
        return true
    end

    -- Force update hourglass time command (bypasses packet validation)
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

    -- Set Dynamis [D] entry timestamp manually
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





    -- Debug item state command
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

    -- Manage command - open item management GUI
    if args[2] == 'manage' then
        print(chat.header('Keyring'):append(chat.message('Opening item management GUI. Use the GUI to add, edit, or remove tracked items.')))
        itemManagementGui.toggle()
        return true
    end
    
    -- Add Item command - open item management GUI with add item dialog
    if args[2] == 'additem' then
        print(chat.header('Keyring'):append(chat.message('Opening item management GUI with Add Item dialog.')))
        itemManagementGui.show_add_item_dialog()
        return true
    end

    -- Unknown command
    print(chat.header('Keyring'):append(chat.message('Unknown command. Type /keyring help for available commands.')))
    return true
end)

-- Load event
ashita.events.register('load', 'load_cb', function()
    print(chat.header('Keyring'):append(chat.message('Keyring v0.4.1 loaded. Key item state will be initialized when ready.')))
end)

-- Main render loop
ashita.events.register('d3d_present', 'render', function()
    -- Wrap everything in pcall to prevent crashes
    local success, err = pcall(function()
        -- Check for player ID and initialize if needed
        if not packet_tracker.is_initialized() then
            local mem = AshitaCore:GetMemoryManager()
            if mem then
                local party = mem:GetParty()
                if party then
                    local player_id = party:GetMemberServerId(0)
                    if player_id and player_id > 0 then
                        -- Throttle the player ID detection message
                        local current_time = os.time()
                        if current_time - last_player_id_message >= player_id_message_interval then
                            print(chat.header('Keyring'):append(chat.message('Player ID detected: ' .. player_id .. ' - Initializing...')))
                            last_player_id_message = current_time
                        end
                        packet_tracker.initialize_player(player_id)
                    end
                end
            end
            -- Still render GUI even during initialization (but with empty data)
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
        -- Update storage canteens every 5 seconds
        local current_time_seconds = os.time()
        if current_time_seconds - (last_storage_update or 0) > 5 then
            storage_canteens = packet_tracker.update_storage_canteens()
            last_storage_update = current_time_seconds
        end

        -- Render the GUI using the modularized GUI system
        local keyItemStatuses = packet_tracker.get_key_item_statuses()
        gui.render(keyItemStatuses, trackedKeyItems, storage_canteens, packet_tracker)
        
        -- Render the item management GUI
        itemManagementGui.render()
    end
end)