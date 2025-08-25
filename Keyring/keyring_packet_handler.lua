-- Keyring Packet Handler Module
-- Handles all packet processing and state management for the keyring addon

-- Import required modules
local persistence = require('keyring_persistence')
require('common')
local struct = require('struct')
local trackedData = require('tracked_key_items')
local key_items = trackedData.key_items
local trackedKeyItems = trackedData.tracked
local chat = require('chat')

-- Debug flag - set to true to enable debug output
local debugMode = false  -- Debug mode disabled

-- Debug throttling to prevent spam
local last_debug_messages = {}
local debug_throttle = 5.0  -- Only show same debug message every 5 seconds

-- Simple debug function with throttling
local function debug_print(message)
    if debugMode then
        -- Create a hash for the message to throttle duplicates
        local message_hash = tostring(message)
        local now = os.clock()
        
        -- Check if we should show this message
        if not last_debug_messages[message_hash] or (now - last_debug_messages[message_hash]) >= debug_throttle then
            last_debug_messages[message_hash] = now
            print('[Keyring Debug] ' .. tostring(message))
        end
    end
end

-- Initial state
local state = {
    dynamis_d_entry_time = 0,
    dynamis_projected_ready_time = 0,
    hourglass_packet_timestamp = 0,
    hourglass_time = -1,  -- -1 represents "Unknown" until packet value is received
    key_items = {},
    packet_ruspix_time = 0,  -- Ruspix Plate timer from packet data
    storage_canteens = 0,
    timestamps = {},
    -- Smart cooldown management
    canteen_cooldown_state = 'idle', -- 'idle', 'running', 'ready'
    canteen_cooldown_start_time = 0,
    -- Batch state updates
    is_dirty = false,
    last_save_time = 0,
}

-- Initialization tracking
local player_ID = nil
local is_initialized = false

-- Zone tracking variables
local current_zone = nil
local previous_zone = nil

-- Handler table for API functions
local handler = {}

-- Zone change callback
local zone_callback = nil

-- Currency callback
local currency_callback = nil

-- GUI update callback
local gui_update_callback = nil

-- GUI update throttling (now handled by handler.throttled_gui_update)

-- Throttled GUI update function (now uses handler.throttled_gui_update)
local function throttled_gui_update()
    handler.throttled_gui_update()
end

-- Flag to track if we've already requested canteen data after login/reload
local canteen_requested = false

-- Flag to track if we've done the post-0x0A key item check
local post_zone_check_done = false

-- Flag to track if we've sent a 0x05B packet requesting Shiny Ra'Kaznarian Plate cooldown
local shiny_plate_05b_sent = false

-- Flag to track if we've sent a 0x05B packet requesting Ruspix Plate time
local ruspix_plate_05b_sent = false

-- Get current state (defined early for use by other functions)
local function get_state()
    return state
end

-- Notification cooldown removed - no longer needed after fixing duplicate zone handlers

-- Smart cooldown management function
local function handle_canteen_cooldown(previous_count, new_count)
    local current_state = get_state()
    if not current_state then return end
    
    debug_print('Smart cooldown: previous=' .. previous_count .. ', new=' .. new_count .. ', current_state=' .. current_state.canteen_cooldown_state)
    
    if previous_count == 3 and new_count == 2 then
        -- Storage decreased from 3 to 2 - start cooldown if not already running
        if current_state.canteen_cooldown_state == 'idle' then
            current_state.canteen_cooldown_state = 'running'
            current_state.canteen_cooldown_start_time = os.time()
            
            local canteen_cooldown = trackedKeyItems and trackedKeyItems[3137] and trackedKeyItems[3137].cooldown or 72000
            local hours = math.floor(canteen_cooldown / 3600)
            print(chat.header('Keyring'):append(chat.message('Canteen cooldown started - next canteen in ' .. hours .. ' hours')))
            debug_print('Smart cooldown: Started cooldown from 3→2')
        else
            debug_print('Smart cooldown: Cooldown already running, not starting new one')
        end
    elseif new_count == 3 then
        -- Storage is full - stop cooldown
        if current_state.canteen_cooldown_state == 'running' then
            current_state.canteen_cooldown_state = 'idle'
            current_state.canteen_cooldown_start_time = 0
            debug_print('Smart cooldown: Stopped cooldown - storage full')
        end
    elseif new_count == 0 then
        -- Storage empty - mark as ready for generation
        if current_state.canteen_cooldown_state == 'running' then
            current_state.canteen_cooldown_state = 'ready'
            debug_print('Smart cooldown: Marked as ready for generation')
        end
    end
end

-- Request Storage Slip Canteen info (outgoing packet 0x115)
local function request_currency_data()
    local packet = struct.pack('bbbb', 0x15, 0x03, 0x00, 0x00):totable()
    AshitaCore:GetPacketManager():AddOutgoingPacket(0x115, packet)
    debug_print('Sent 0x115 currency request packet')
end

-- Simple state saving (no dirty state system)

-- Load state from persistence
local function load_state()
    local loaded_state = persistence.load_state(debug_print)
    
    -- Create a deep copy to avoid reference issues with settings library
    if type(loaded_state) == 'table' then
        local new_state = {
            dynamis_d_entry_time = tonumber(loaded_state.dynamis_d_entry_time) or 0,
            dynamis_projected_ready_time = tonumber(loaded_state.dynamis_projected_ready_time) or 0,
            hourglass_packet_timestamp = tonumber(loaded_state.hourglass_packet_timestamp) or 0,
            hourglass_time = tonumber(loaded_state.hourglass_time) or -1,  -- -1 represents "Unknown" until packet value is received
            key_items = {},
            packet_ruspix_time = tonumber(loaded_state.packet_ruspix_time) or 0,
            storage_canteens = tonumber(loaded_state.storage_canteens) or 0,
            timestamps = {},
            -- Smart cooldown management
            canteen_cooldown_state = loaded_state.canteen_cooldown_state or 'idle',
            canteen_cooldown_start_time = tonumber(loaded_state.canteen_cooldown_start_time) or 0,
        }
        
        -- Deep copy key_items
        if loaded_state.key_items then
            for id, owned in pairs(loaded_state.key_items) do
                new_state.key_items[tonumber(id)] = owned == true
            end
        end
        
        -- Deep copy timestamps
        if loaded_state.timestamps then
            for id, ts in pairs(loaded_state.timestamps) do
                new_state.timestamps[tonumber(id)] = tonumber(ts) or 0
            end
        end
        
        return new_state
    end
    
    return loaded_state
end

-- Get current state (already defined above)

-- Legacy accumulated time functions removed - accrual is now calculated on-the-fly

-- Save state to persistence
local function save_state()
    -- Hourglass and Ruspix Plate accrual are now calculated on-the-fly, no need to update before saving
    return persistence.save_state(state, debug_print)
end

-- API: Get current state (for external access)
function handler.get_state()
    return get_state()
end

-- Set current state
local function set_state(new_state)
    if type(new_state) == 'table' then
        state = new_state
    end
end

-- No manual HasKeyItem checks needed - 0x55 packets handle this automatically

-- API: Check if addon is initialized
function handler.is_initialized()
    return is_initialized
end

-- API: Debug mode control
function handler.enable_debug()
    debugMode = true
    debug_print('Debug mode enabled')
end

function handler.disable_debug()
    debugMode = false
    debug_print('Debug mode disabled')
end

function handler.is_debug_enabled()
    return debugMode
end

-- API: Initialize player (no manual HasKeyItem checks needed)
function handler.initialize_player(server_id)
    if is_initialized then
        debug_print('Already initialized for player ID: ' .. tostring(player_ID))
        return
    end
    
    debug_print('Initializing player ID: ' .. server_id)
    player_ID = server_id
    
    -- 1. Load persistence file
    debug_print('Loading persistence file...')
    local loaded_state = load_state()
    if type(loaded_state) == 'table' then
        set_state(loaded_state)
        debug_print('Persistence loaded successfully')
        

        
        -- Trigger throttled GUI update callback to refresh display with loaded data
        throttled_gui_update()
    else
        debug_print('No persistence file found, starting fresh')
    end
    
    -- 2. Mark as initialized - 0x55 packets will handle key item detection
    is_initialized = true
    
    -- Reset canteen request flags for new session
    canteen_requested = false
    post_zone_check_done = false
    
    -- Request canteen data immediately after initialization
    debug_print('Requesting canteen data after initialization')
    request_currency_data()
    canteen_requested = true
    
    -- Try to get current zone from memory manager if available
    local mem = AshitaCore:GetMemoryManager()
    if mem then
        local player = mem:GetPlayer()
        if player then
            local success, zone_id = pcall(function() return player:GetZoneId() end)
            if success and zone_id and zone_id > 0 then
                current_zone = zone_id
                debug_print('Initial zone set from memory manager: ' .. current_zone)
            else
                debug_print('Could not get zone ID from memory manager (zone_id=' .. tostring(zone_id) .. ')')
            end
        else
            debug_print('Player object not available from memory manager during initialization')
        end
    else
        debug_print('Memory manager not available during initialization')
    end
    
    debug_print('Initialization complete - waiting for 0x55 packet for key item data')
end

-- API: Force initialization (for debugging/testing)
function handler.force_initialization()
    if is_initialized then
        debug_print('Already initialized - no action needed')
        return
    end
    
    debug_print('Force initializing addon...')
    
    -- Set a default player ID if none exists
    if not player_ID then
        local mem = AshitaCore:GetMemoryManager()
        if mem then
            local party = mem:GetParty()
            if party then
                player_ID = party:GetMemberServerId(0) or 0
            end
        end
        if not player_ID or player_ID == 0 then
            player_ID = 999999  -- Fallback ID
        end
    end
    
    -- Load persistence file
    local loaded_state = load_state()
    if type(loaded_state) == 'table' then
        set_state(loaded_state)
        debug_print('Persistence loaded successfully')
        
        -- Trigger throttled GUI update callback to refresh display with loaded data
        throttled_gui_update()
    else
        debug_print('No persistence file found, starting fresh')
    end
    
    -- Force initialization
    is_initialized = true
    
    -- Reset canteen request flags for new session
    canteen_requested = false
    post_zone_check_done = false
    
    -- Request canteen data immediately after force initialization
    debug_print('Requesting canteen data after force initialization')
    request_currency_data()
    canteen_requested = true
    
    -- Try to get current zone from memory manager if available
    local mem = AshitaCore:GetMemoryManager()
    if mem then
        local player = mem:GetPlayer()
        if player then
            local success, zone_id = pcall(function() return player:GetZoneId() end)
            if success and zone_id and zone_id > 0 then
                current_zone = zone_id
                debug_print('Initial zone set from memory manager: ' .. current_zone)
            else
                debug_print('Could not get zone ID from memory manager (zone_id=' .. tostring(zone_id) .. ')')
            end
        else
            debug_print('Player object not available from memory manager during initialization')
        end
    else
        debug_print('Memory manager not available during initialization')
    end
    
    debug_print('Force initialization complete')
end

-- API: Clear persistence data (for fixing incorrect data)
function handler.clear_persistence_data()
    debug_print('Clearing persistence data...')
    
    -- Reset state to empty
    state = {
        dynamis_d_entry_time = 0,
        dynamis_projected_ready_time = 0,
        hourglass_packet_timestamp = 0,
        hourglass_time = -1,  -- -1 represents "Unknown" until packet value is received
        key_items = {
            [3212] = false,  -- moglophone
            [3137] = false,  -- mystical canteen
            [3300] = false,  -- shiny Ra'Kaznarian plate
            [3052] = false,  -- Ambuscade Primer Vol. 1
            [3053] = false,  -- Ambuscade Primer Vol. 2
        },
        packet_ruspix_time = 0,
        storage_canteens = 0,
        timestamps = {
            [3212] = 0,  -- moglophone
            [3137] = 0,  -- mystical canteen
            [3300] = 0,  -- shiny Ra'Kaznarian plate
            [3052] = 0,  -- Ambuscade Primer Vol. 1
            [3053] = 0,  -- Ambuscade Primer Vol. 2
        },
        -- Smart cooldown management
        canteen_cooldown_state = 'idle',
        canteen_cooldown_start_time = 0,
    }
    
    -- Save empty state to overwrite persistence file
            save_state()
    
    -- Reset initialization flag
    is_initialized = false
    player_ID = nil
    
    -- Reset runtime-only flags
    -- is_ruspix = false -- Removed as per edit hint
    
    debug_print('Persistence data cleared')
end

-- API: Force clear persistence file (for fixing persistent incorrect data)
function handler.force_clear_persistence_file()
    debug_print('Force clearing persistence file...')
    
    -- Reset state to empty
    state = {
        dynamis_d_entry_time = 0,
        dynamis_projected_ready_time = 0,
        hourglass_packet_timestamp = 0,
        hourglass_time = -1,  -- -1 represents "Unknown" until packet value is received
        key_items = {
            [3212] = false,  -- moglophone
            [3137] = false,  -- mystical canteen
            [3300] = false,  -- shiny Ra'Kaznarian plate
            [3052] = false,  -- Ambuscade Primer Vol. 1
            [3053] = false,  -- Ambuscade Primer Vol. 2
        },
        packet_ruspix_time = 0,
        storage_canteens = 0,
        timestamps = {
            [3212] = 0,  -- moglophone
            [3137] = 0,  -- mystical canteen
            [3300] = 0,  -- shiny Ra'Kaznarian plate
            [3052] = 0,  -- Ambuscade Primer Vol. 1
            [3053] = 0,  -- Ambuscade Primer Vol. 2
        },
        -- Smart cooldown management
        canteen_cooldown_state = 'idle',
        canteen_cooldown_start_time = 0,
    }
    
    -- Force save empty state multiple times to ensure file is overwritten
    for i = 1, 3 do
        save_state()
        debug_print('Force save attempt ' .. i .. ' completed')
    end
    
    -- Reset initialization flag
    is_initialized = false
    player_ID = nil
    
    -- Reset runtime-only flags
    -- is_ruspix = false -- Removed as per edit hint
    
    debug_print('Persistence file force cleared')
end

-- API: Nuclear clear - clear all persistence data
function handler.nuclear_clear_persistence()
    debug_print('Nuclear clearing persistence data...')
    
    -- Clear internal state
    state = {
        dynamis_d_entry_time = 0,
        dynamis_projected_ready_time = 0,
        hourglass_packet_timestamp = 0,
        hourglass_time = -1,  -- -1 represents "Unknown" until packet value is received
        key_items = {
            [3212] = false,  -- moglophone
            [3137] = false,  -- mystical canteen
            [3300] = false,  -- shiny Ra'Kaznarian plate
            [3052] = false,  -- Ambuscade Primer Vol. 1
            [3053] = false,  -- Ambuscade Primer Vol. 2
        },
        packet_ruspix_time = 0,
        storage_canteens = 0,
        timestamps = {
            [3212] = 0,  -- moglophone
            [3137] = 0,  -- mystical canteen
            [3300] = 0,  -- shiny Ra'Kaznarian plate
            [3052] = 0,  -- Ambuscade Primer Vol. 1
            [3053] = 0,  -- Ambuscade Primer Vol. 2
        },
        -- Smart cooldown management
        canteen_cooldown_state = 'idle',
        canteen_cooldown_start_time = 0,
    }
    
    -- Clear persistence data using the settings library
    local success = persistence.clear_all_data(debug_print)
    if success then
        print(chat.header('Keyring'):append(chat.message('Successfully cleared all persistence data!')))
    else
        print(chat.header('Keyring'):append(chat.message('Failed to clear persistence data')))
    end
    
    -- Reset runtime-only flags
    -- is_ruspix = false -- Removed as per edit hint
    
    debug_print('Nuclear clear completed')
end

-- API: Debug persistence structure
function handler.debug_persistence_structure()
    debug_print('Debugging persistence structure...')
    
    -- Show current state structure
    local current_state = get_state()
    print(chat.header('Keyring'):append(chat.message('Current state structure:')))
    
    if current_state then
        print(chat.message('  State type: ' .. type(current_state)))
        
        if current_state.key_items then
            print(chat.message('  Key items table type: ' .. type(current_state.key_items)))
            print(chat.message('  Key items table keys:'))
            for key, value in pairs(current_state.key_items) do
                local item_name = key_items.idToName[tonumber(key)] or ('ID ' .. tostring(key))
                print(chat.message('    [' .. tostring(key) .. '] = ' .. tostring(value) .. ' (' .. item_name .. ')'))
            end
        else
            print(chat.message('  Key items table: nil or missing'))
        end
        
        if current_state.timestamps then
            print(chat.message('  Timestamps table type: ' .. type(current_state.timestamps)))
            print(chat.message('  Timestamps table keys:'))
            for key, value in pairs(current_state.timestamps) do
                local item_name = key_items.idToName[tonumber(key)] or ('ID ' .. tostring(key))
                print(chat.message('    [' .. tostring(key) .. '] = ' .. tostring(value) .. ' (' .. item_name .. ')'))
            end
        else
            print(chat.message('  Timestamps table: nil or missing'))
        end
    else
        print(chat.message('  Current state: nil'))
    end
    
    -- Show what get_key_item_statuses returns
    print(chat.header('Keyring'):append(chat.message('get_key_item_statuses() output:')))
    local statuses = handler.get_key_item_statuses()
    for i, status in ipairs(statuses) do
        print(chat.message('  Item ' .. i .. ': ' .. status.name .. ' (ID ' .. status.id .. ') - owned=' .. tostring(status.owned) .. ', timestamp=' .. tostring(status.timestamp)))
    end
end

-- API: Check current state
function handler.check_current_state()
    debug_print('Checking current state...')
    
    -- Show current state
    local current_state = get_state()
    print(chat.header('Keyring'):append(chat.message('Current state:')))
    
    if current_state and current_state.key_items then
        for id, owned in pairs(current_state.key_items) do
            local item_name = key_items.idToName[id] or ('ID ' .. tostring(id))
            print(chat.message('  ' .. item_name .. ': ' .. tostring(owned)))
        end
    else
        print(chat.message('  No key_items data available'))
    end
    
    -- Check if we're initialized
    print(chat.header('Keyring'):append(chat.message('Initialization status:')))
    print(chat.message('  Initialized: ' .. tostring(is_initialized)))
    print(chat.message('  Player ID: ' .. tostring(player_ID)))
    
    -- Check memory manager
    local mem = AshitaCore:GetMemoryManager()
    if mem then
        local party = mem:GetParty()
        if party then
            local current_player_id = party:GetMemberServerId(0)
            print(chat.message('  Current player ID from memory: ' .. tostring(current_player_id)))
            
            -- Check actual key item ownership via memory
            print(chat.header('Keyring'):append(chat.message('Memory manager key item checks:')))
            local player = mem:GetPlayer()
            if player then
                for id, _ in pairs(trackedKeyItems) do
                    local has_item = player:HasKeyItem(id)
                    local item_name = key_items.idToName[id] or ('ID ' .. tostring(id))
                    print(chat.message('  ' .. item_name .. ': ' .. tostring(has_item)))
                end
            else
                print(chat.message('  Player object not available'))
            end
        else
            print(chat.message('  Party object not available'))
        end
    else
        print(chat.message('  Memory manager not available'))
    end
end

-- Helper function to get player server ID
local function get_player_server_id()
    local mem = AshitaCore:GetMemoryManager()
    if not mem then return nil end
    local party = mem:GetParty()
    if not party then return nil end
    local player_server_id = party:GetMemberServerId(0)
    if player_server_id and player_server_id > 0 then return player_server_id end
    return nil
end

-- API: Debug persistence location and content
function handler.debug_persistence_location()
    debug_print('Debugging persistence system...')
    
    -- Show current state
    local current_state = get_state()
    print(chat.header('Keyring'):append(chat.message('Current state in memory:')))
    if current_state and current_state.key_items then
        for item_id, owned in pairs(current_state.key_items) do
            local item_name = key_items.idToName[item_id] or ('ID ' .. tostring(item_id))
            print(chat.message('  • ' .. item_name .. ': ' .. tostring(owned)))
        end
    else
        print(chat.message('  No key_items data in memory'))
    end
    
    -- Try to load fresh from persistence
    print(chat.header('Keyring'):append(chat.message('Loading fresh from persistence...')))
    local fresh_state = load_state()
    if fresh_state and fresh_state.key_items then
        print(chat.message('  Fresh persistence data:'))
        for item_id, owned in pairs(fresh_state.key_items) do
            local item_name = key_items.idToName[item_id] or ('ID ' .. tostring(item_id))
            print(chat.message('  • ' .. item_name .. ': ' .. tostring(owned)))
        end
    else
        print(chat.message('  No data in persistence file'))
    end
    
    -- Show file paths
    print(chat.header('Keyring'):append(chat.message('Persistence file paths:')))
    local settings_file = persistence.get_settings_path(debug_print)
    print(chat.message('  Settings file: ' .. settings_file))
end

-- No reset function needed - initialization happens immediately

-- Get key item statuses for GUI (reads from persistence)
function handler.get_key_item_statuses()
    local result = {}
    local current_state = get_state()
    local grouped_items = {}
    
    -- Ensure tables exist
    if not current_state.timestamps then current_state.timestamps = {} end
    if not current_state.key_items then current_state.key_items = {} end
    
    for id, data in pairs(trackedKeyItems) do
        if data.group == "moglophone_ii" then
            -- Group Moglophone II variants together
            if not grouped_items["Moglophone II"] then
                grouped_items["Moglophone II"] = {
                    id = "moglophone_ii_group",
                    name = "Moglophone II",
                    remaining = nil,
                    timestamp = 0,
                    owned = false,
                    group = "moglophone_ii",
                    variant_count = 0
                }
            end
            -- Count variants as owned
            if current_state.key_items[id] == true then
                grouped_items["Moglophone II"].variant_count = grouped_items["Moglophone II"].variant_count + 1
                grouped_items["Moglophone II"].owned = true
                debug_print('Moglophone II variant ' .. id .. ' is owned, total count: ' .. grouped_items["Moglophone II"].variant_count)
            end
        else
            -- Regular items
            local timestamp = current_state.timestamps[id] or 0
            local remaining = nil
            
            -- Only calculate remaining time for items with cooldowns
            if data.cooldown > 0 and timestamp > 0 then
                remaining = (timestamp + data.cooldown) - os.time()
            end
            
            local name = key_items.idToName[id] or ('Unknown ID: ' .. tostring(id))
            local owned = current_state.key_items[id] == true
            
            table.insert(result, {
                id = id,
                name = name,
                remaining = remaining,
                timestamp = timestamp,
                owned = owned,
            })
        end
    end
    
    -- Add grouped items
    for _, grouped_item in pairs(grouped_items) do
        table.insert(result, grouped_item)
    end
    
    return result
end

-- PACKET HANDLERS

-- Duplicate zone change handler removed to prevent duplicate "ready for pickup" messages

-- Handle 0x55 packets (key item list)
if ashita.events then
    ashita.events.register('packet_in', 'Keyring_PacketHandler', function(e)
    -- Basic debug: log all incoming packets
    if debugMode then
        debug_print('Packet received: 0x' .. string.format('%02X', e.id) .. ' (size: ' .. #e.data .. ')')
    end
    
    -- Special debug for Ruspix-related packets
    if e.id == 0x034 or e.id == 0x05C then
        debug_print('*** RUSPIX PACKET: 0x' .. string.format('%02X', e.id) .. ' (size: ' .. #e.data .. ') ***')
    end
    
    if e.id == 0x00D then
        -- Logout counter packet - reset canteen request flags when logout is imminent
        local param = struct.unpack('I', e.data, 0x04 + 1)
        if param and param <= 5 then
            debug_print('Logout detected (0x053 param=' .. param .. '), resetting canteen request flags')
            canteen_requested = false
            post_zone_check_done = false
        end
    elseif e.id == 0x55 then
        -- Only process if initialized
        if not is_initialized then
            return
        end
        
        local current_state = get_state()
        if not current_state.key_items then
            return
        end

        local offset = struct.unpack('B', e.data, 0x84 + 1) * 512
        
        -- Debug: Log all 0x55 packets to see what ranges we're getting
        debug_print('0x55: Received packet with offset=' .. offset .. ' (covers items ' .. offset .. '-' .. (offset + 511) .. ')')

        for ki, _ in pairs(trackedKeyItems) do
            if (ki >= offset) and (ki <= offset + 511) then
                local hasKeyItem = (ashita.bits.unpack_be(e.data_raw, 0x04, ki - offset, 1) == 1)
                local wasOwned = current_state.key_items[ki] == true
                local item_name = key_items.idToName[ki] or ('ID ' .. tostring(ki))
                
                -- Debug output for Shiny Rakaznar Plate specifically
                if ki == 3300 then
                    debug_print('0x55: Processing Shiny Rakaznar Plate - offset=' .. offset .. ', hasKeyItem=' .. tostring(hasKeyItem) .. ', wasOwned=' .. tostring(wasOwned) .. ', item_name=' .. (key_items.idToName[ki] or 'unknown'))
                end
                
                -- Debug output for Mystical Canteen specifically
                if ki == 3137 then
                    debug_print('0x55: Processing Mystical Canteen - offset=' .. offset .. ', hasKeyItem=' .. tostring(hasKeyItem) .. ', wasOwned=' .. tostring(wasOwned) .. ', item_name=' .. (key_items.idToName[ki] or 'unknown'))
                end
                
                if hasKeyItem ~= wasOwned then
                    -- Key item state changed - update persistence
                    current_state.key_items[ki] = hasKeyItem
                    
                    -- If Mystical Canteen is newly acquired, decrease storage count and check for cooldown
                    if ki == 3137 and hasKeyItem and not wasOwned then
                        local previous_count = current_state.storage_canteens or 0
                        current_state.storage_canteens = math.max(0, previous_count - 1)
                        
                        debug_print('0x55: Mystical Canteen newly acquired - decreasing storage from ' .. previous_count .. ' to ' .. current_state.storage_canteens)
                        
                        -- Use smart cooldown management
                        handle_canteen_cooldown(previous_count, current_state.storage_canteens)
                        
                        -- Save state immediately
                        save_state()
                        
                        -- Request storage update to verify
                        request_currency_data()
                    elseif ki == 3137 then
                        debug_print('0x55: Mystical Canteen state changed - hasKeyItem: ' .. tostring(hasKeyItem) .. ', wasOwned: ' .. tostring(wasOwned))
                    end
                    
                    -- If Shiny Rakaznarian Plate is acquired while on cooldown, reset Ruspix Plate timer
                    if ki == 3300 and hasKeyItem then
                        -- Check if Shiny Rakaznarian Plate is currently on cooldown
                        local shiny_plate_timestamp = current_state.timestamps[3300] or 0
                        local shiny_plate_cooldown = trackedKeyItems[3300] and trackedKeyItems[3300].cooldown or 0
                        local now = os.time()
                        
                        -- Calculate if Shiny Rakaznarian Plate is on cooldown
                        local shiny_plate_on_cooldown = false
                        if shiny_plate_cooldown > 0 then
                            local time_since_acquisition = now - shiny_plate_timestamp
                            if time_since_acquisition < shiny_plate_cooldown then
                                shiny_plate_on_cooldown = true
                            end
                        end
                        
                        -- Only reset if Shiny Rakaznarian Plate is acquired while on cooldown
                        if shiny_plate_on_cooldown then
                            debug_print('0x55: Shiny Rakaznarian Plate acquired while on cooldown - resetting Ruspix Plate timer')
                            current_state.packet_ruspix_time = 0
                        else
                            debug_print('0x55: Shiny Rakaznarian Plate acquired while off cooldown - not resetting Ruspix Plate timer')
                        end
                    end
                    
                    -- Set timestamp for new acquisitions (except Shiny Rakaznar Plate and Mystical Canteen)
                    if hasKeyItem and ki ~= 3300 and ki ~= 3137 then
                        local cooldown = trackedKeyItems[ki] and trackedKeyItems[ki].cooldown
                        if cooldown and cooldown > 0 then
                            current_state.timestamps[ki] = os.time()
                        end
                    end
                    
                    -- Show acquisition notifications for specific items: Moglophone, Shiny Rakaznarian plate, and Mystical Canteen
                    -- Only show when item ownership changes from "Don't Have" to "Have" (wasOwned = false, hasKeyItem = true)
                    if hasKeyItem and not wasOwned then
                        local notification_items = {3212, 3300, 3137}  -- Moglophone, Shiny Rakaznarian plate, Mystical Canteen
                        for _, notification_id in ipairs(notification_items) do
                            if ki == notification_id then
                                -- Customize message based on item type
                                if ki == 3300 then
                                    -- Shiny Ra'Kaznarian Plate - no cooldown on acquisition
                                    print(chat.header('Keyring'):append(chat.message(string.format('Acquired %s - cooldown starts when used for teleport', item_name))))
                                else
                                    -- Moglophone and Mystical Canteen - cooldown starts on acquisition
                                    print(chat.header('Keyring'):append(chat.message(string.format('Acquired %s - cooldown started', item_name))))
                                end
                                debug_print('0x55: Notification shown for item ' .. ki .. ' (' .. item_name .. ')')
                                break
                            end
                        end
                    end
                    
                    local save_result = save_state()
                    
                    -- Trigger throttled GUI update callback to refresh display
                    throttled_gui_update()
                end
            else
                -- Debug output for items not in current packet range
                if ki == 3300 then
                    debug_print('0x55: Shiny Rakaznar Plate not in current packet range - offset=' .. offset .. ', item_id=' .. ki .. ', packet_size=' .. #e.data)
                end
                
                -- Debug output for Mystical Canteen not in current packet range
                if ki == 3137 then
                    debug_print('0x55: Mystical Canteen not in current packet range - offset=' .. offset .. ', item_id=' .. ki .. ', packet_size=' .. #e.data)
                end
            end
        end
        
    elseif e.id == 0x034 then
        -- NPC Interaction Packet - used for Ruspix validation
        debug_print('0x034: Received packet, size: ' .. #e.data)
        if #e.data < 0x34 then
            debug_print('0x034: Packet too short, expected at least 52 bytes, got ' .. #e.data)
            return
        end
        
        -- Extract NPC ID from offset 0x04-0x07 (corrected offset)
        local npc_id = struct.unpack('I', e.data, 0x04+1)
        debug_print('0x034: NPC ID: ' .. npc_id)
        
        -- Debug: Show hex dump of first 16 bytes to verify data
        local hex_dump = ''
        for i = 1, math.min(16, #e.data) do
            hex_dump = hex_dump .. string.format('%02X ', e.data:byte(i))
        end
        debug_print('0x034: First 16 bytes: ' .. hex_dump)
        
        -- Check if this is Ruspix (ID 17928266)
        if npc_id == 17928266 then
            debug_print('0x034: Ruspix detected')
        else
            debug_print('0x034: Not Ruspix (ID: ' .. npc_id .. ')')
        end
        
        -- Note: is_ruspix flag removed - packet field validation is sufficient
        debug_print('0x034: Packet processed')
        
    elseif e.id == 0x05C then
        -- Ruspix response (0x05C) - could be Shiny Ra'Kaznarian Plate cooldown or Ruspix Plate time
        local current_state = get_state()
        
        -- Check if packet data is long enough for the expected offset
        if #e.data < 0x0A then  -- Need at least 10 bytes for offset 0x08-0x09 (16-bit)
            debug_print('0x05C: Packet too short, expected at least 10 bytes, got ' .. #e.data)
            return
        end
        
        -- Process Shiny Ra'Kaznarian Plate cooldown response
        if shiny_plate_05b_sent then
            debug_print('0x05C: Validated Shiny Ra\'Kaznarian Plate cooldown response, processing...')
            
            -- Check status at offset 0x04+1: 1=ready, 2=can upgrade, 3=on cooldown
            local status = struct.unpack('B', e.data, 0x04+1)
            debug_print('0x05C: Status received: ' .. status .. ' (1=ready, 2=can upgrade, 3=on cooldown)')
            
            if status == 2 then
                -- Status 2: Can upgrade - set cooldown as "0" (item is Ready)
                debug_print('0x05C: Status 2 - Shiny Ra\'Kaznarian Plate is Ready (cooldown = 0)')
                -- Note: We could update a timestamp here if needed, but currently just logging
            elseif status == 3 then
                -- Status 3: On cooldown - extract time value from 0x08+1 offset
                local shiny_plate_remaining = struct.unpack('H', e.data, 0x08+1)
                debug_print('0x05C: Status 3 - Shiny Ra\'Kaznarian Plate remaining cooldown: ' .. shiny_plate_remaining .. ' seconds')
                
                -- Calculate when the cooldown started using the fresh server data
                local current_time = os.time()
                local total_cooldown = trackedKeyItems and trackedKeyItems[3300] and trackedKeyItems[3300].cooldown or 72000
                local cooldown_start = current_time - (total_cooldown - shiny_plate_remaining)
                
                -- Update the Shiny Plate cooldown start timestamp (same field used by 0x55 handler)
                current_state.timestamps[3300] = cooldown_start
                save_state()
                
                debug_print('0x05C: Shiny Plate cooldown start updated to: ' .. cooldown_start .. ' (remaining: ' .. shiny_plate_remaining .. ' seconds)')
            else
                -- Status 1: Junk - already have a Shiny Ra'Kaznarian Plate
                debug_print('0x05C: Status 1 - Already have Shiny Ra\'Kaznarian Plate (junk data)')
            end
            
            -- Note: We don't update packet_ruspix_time here - that field is only for Ruspix Plate time responses
            -- This response is about Shiny Ra'Kaznarian Plate cooldown, not Ruspix Plate accumulation
            
            -- Reset the validation flag after successful processing
            shiny_plate_05b_sent = false
            
            -- Trigger throttled GUI update callback to refresh display
            throttled_gui_update()
            
            return
        end
        
        -- Process Ruspix Plate time response
        if ruspix_plate_05b_sent then
            debug_print('0x05C: Validated Ruspix Plate time response, processing...')
            
            -- Check status at offset 0x04+1: 1=ready, 2=can upgrade, 3=on cooldown
            local status = struct.unpack('B', e.data, 0x04+1)
            debug_print('0x05C: Status received: ' .. status .. ' (1=ready, 2=can upgrade, 3=on cooldown)')
            
            if status == 3 then
                -- Status 3: On cooldown - extract time value from 0x08+1 offset
                local ruspix_plate_remaining = struct.unpack('H', e.data, 0x08+1)
                debug_print('0x05C: Status 3 - Ruspix Plate remaining cooldown: ' .. ruspix_plate_remaining .. ' seconds')
                
                -- Get Shiny Ra'Kaznarian Plate's current remaining cooldown
                local shiny_plate_remaining = handler.get_remaining(3300)  -- 3300 = Shiny Ra'Kaznarian Plate ID
                
                -- Calculate Ruspix Plate time: Shiny Plate remaining cooldown - 0x05C value
                local calculated_ruspix_time = shiny_plate_remaining - ruspix_plate_remaining
                
                debug_print('0x05C: Shiny Plate remaining: ' .. shiny_plate_remaining .. ' seconds, 0x05C value: ' .. ruspix_plate_remaining .. ' seconds')
                debug_print('0x05C: Calculated Ruspix Plate time: ' .. calculated_ruspix_time .. ' seconds (Shiny Plate remaining: ' .. shiny_plate_remaining .. ' - 0x05C value: ' .. ruspix_plate_remaining .. ')')
                
                -- Cap Ruspix Plate time at Shiny Plate cooldown value
                local max_ruspix_time = trackedKeyItems and trackedKeyItems[3300] and trackedKeyItems[3300].cooldown or 72000
                local capped_ruspix_time = math.min(calculated_ruspix_time, max_ruspix_time)
                
                -- Update the Ruspix Plate time in our state
                current_state.packet_ruspix_time = capped_ruspix_time
                
                -- Save the state
                save_state()
                
                if calculated_ruspix_time > max_ruspix_time then
                    debug_print('0x05C: Ruspix Plate time capped at ' .. math.floor(max_ruspix_time/3600) .. ' hours: ' .. capped_ruspix_time .. ' seconds (was ' .. calculated_ruspix_time .. ' seconds)')
                else
                    debug_print('0x05C: Ruspix Plate time updated to: ' .. capped_ruspix_time .. ' seconds (calculated from remaining cooldown)')
                end
            else
                -- Status 1 or 2: Don't update Ruspix Plate time value
                debug_print('0x05C: Status ' .. status .. ' - not updating Ruspix Plate time value')
            end
            
            -- Note: We don't update packet_ruspix_time here - that field is only for Ruspix Plate time responses
            -- This response is about Ruspix Plate cooldown, not Ruspix Plate accumulation
            
            -- Reset the validation flag after successful processing
            ruspix_plate_05b_sent = false
            
            -- Trigger throttled GUI update callback to refresh display
            throttled_gui_update()
            
            return
        end
        
        -- If we get here, we received a 0x05C without a prior 0x05B request
        debug_print('0x05C: Received without prior 0x05B request, ignoring')
        
    elseif e.id == 0x00A then
        -- Zone change detection using proper 0x00A packet structure
        local zoneId = struct.unpack('H', e.data, 0x30+1)  -- Zone field at offset 0x30
        
        -- Track zone transitions
        if current_zone ~= nil then
            previous_zone = current_zone
        end
        current_zone = zoneId
        
        -- Process if this is the first zone OR if zone actually changed
        if previous_zone == nil or previous_zone ~= current_zone then
                            debug_print('Zone changed from ' .. (previous_zone or 'unknown') .. ' to ' .. (current_zone or 'unknown'))
            
            -- Trigger zone change callback if registered
            if zone_callback then
                zone_callback(current_zone, previous_zone)
            end
            
            -- Skip post-zone check - rely on 0x55 packets for accurate ownership data
            if not post_zone_check_done then
                debug_print('First zone complete')
                post_zone_check_done = true
            end
        end
        
        -- Handle Dynamis [D] zone transitions with cooldown consumption
        local dynamis_zone_transitions = {
            [230] = 294,  -- southern_san_doria => Dynamis-San_Doria_[D]
            [234] = 295,  -- Bastok_Mines => Dynamis-Bastok_[D]
            [239] = 296,  -- Windurst_Walls => Dynamis-Windurst_[D]
            [243] = 297   -- RuLude_Gardens => Dynamis-Jeuno_[D]
        }
        
        local current_state = get_state()
        
        for pre_zone_id, dynamis_zone_id in pairs(dynamis_zone_transitions) do
            if zoneId == dynamis_zone_id then
                local now = os.time()
                
                -- Check if there was an existing Dynamis [D] cooldown
                local existing_cooldown_remaining = 0
                if current_state.dynamis_d_entry_time and current_state.dynamis_d_entry_time > 0 then
                    local time_since_entry = now - current_state.dynamis_d_entry_time
                    local cooldown_duration = 216000  -- 60 hours = 216000 seconds
                    existing_cooldown_remaining = math.max(0, cooldown_duration - time_since_entry)
                end
                
                -- If there was a cooldown remaining, consume hourglass time
                if existing_cooldown_remaining > 0 then
                    local total_hourglass_time = handler.get_hourglass_time() -- Base + any accrual time
                    if total_hourglass_time > 0 then
                        -- Consume hourglass time equal to remaining cooldown from total (base + accrual)
                        local consumed_time = math.min(total_hourglass_time, existing_cooldown_remaining)
                        local remaining_time = total_hourglass_time - consumed_time
                        
                        -- Set the remaining time as the new base hourglass time (no more accrual since Dynamis will be on cooldown)
                        current_state.hourglass_time = remaining_time
                        current_state.hourglass_packet_timestamp = now  -- Reset timestamp since we're setting new base time
                        current_state.hourglass_last_save_timestamp = now
                        
                        print(chat.header('Keyring'):append(chat.message(string.format('Entered Dynamis [D] with cooldown - consumed %d:%02d hourglass time', 
                            math.floor(consumed_time / 3600), math.floor((consumed_time % 3600) / 60)))))
                        
                        if remaining_time <= 0 then
                            print(chat.header('Keyring'):append(chat.message('Warning: Empty Hourglass time depleted')))
                        end
                    else
                        print(chat.header('Keyring'):append(chat.message('Entered Dynamis [D] with cooldown - no hourglass time to consume')))
                    end
                else
                    -- Dynamis [D] is off cooldown - no hourglass time should be consumed
                    -- The accumulated time will be preserved automatically since we update it before saving
                    print(chat.header('Keyring'):append(chat.message('Entered Dynamis [D] - no cooldown to bypass')))
                end
                
                -- Record new entry time (starts fresh 60-hour cooldown)
                current_state.dynamis_d_entry_time = now
                -- Calculate and store projected ready time (entry time + 60 hours)
                current_state.dynamis_projected_ready_time = now + 216000  -- 60 hours = 216000 seconds
                save_state()
                
                print(chat.header('Keyring'):append(chat.message(string.format('Dynamis [D] zone (ID: %d) - new 60-hour cooldown started', dynamis_zone_id))))
                break
            end
        end
        
        -- Handle Ra'Kaznar zone transitions (Shiny Rakaznar Plate usage detection)
        local rakaznar_zone_transitions = {
            [267] = {275, 133, 189}  -- Kamihr Drifts => Outer Ra'Kaznar [U1], [U2], [U3]
        }
        
        for pre_zone_id, target_zones in pairs(rakaznar_zone_transitions) do
            for _, target_zone_id in ipairs(target_zones) do
                if zoneId == target_zone_id then
                    debug_print('Ra\'Kaznar zone transition detected: zoneId=' .. zoneId .. ', previous_zone=' .. (previous_zone or 'unknown'))
                    local plate_id = 3300  -- Shiny Rakaznar Plate ID
                    if current_state.key_items and current_state.key_items[plate_id] == true then
                        local now = os.time()
                        current_state.key_items[plate_id] = false
                        current_state.timestamps[plate_id] = now
                        save_state()
                        print(chat.header('Keyring'):append(chat.message('Shiny Rakaznar Plate used - 20-hour cooldown started')))
                    else
                        debug_print('Shiny Rakaznar Plate not owned or already used - plate_id=' .. plate_id .. ', owned=' .. tostring(current_state.key_items and current_state.key_items[plate_id]))
                    end
                    break
                end
            end
        end
        
    elseif e.id == 0x02A then
        -- 0x02A packet handler with zone-based separation
        -- This packet contains both Hourglass and Ruspix Plate data, separated by zone context
        
        -- Define zone groups for processing logic
        local pre_dynamis_zones = {230, 234, 239, 243}  -- Southern San Doria, Bastok Mines, Windurst Walls, Ru'Lude Gardens
        local outer_rakaznar_zones = {275, 133, 189}    -- Outer Ra'Kaznar [U1], [U2], [U3]
        
        local is_in_pre_dynamis = false
        local is_in_outer_rakaznar = false
        
        -- Check current zone for processing logic
        for _, zone_id in ipairs(pre_dynamis_zones) do
            if current_zone == zone_id then
                is_in_pre_dynamis = true
                break
            end
        end
        
        for _, zone_id in ipairs(outer_rakaznar_zones) do
            if current_zone == zone_id then
                is_in_outer_rakaznar = true
                break
            end
        end
        
        -- Process Hourglass data only in pre-Dynamis zones
        if is_in_pre_dynamis then
            local messageId = struct.unpack('H', e.data, 0x1A+1)
            local actor_ID = struct.unpack('I', e.data, 0x04+1)
            local byte1 = e.data:byte(0x0C+1)
            local byte2 = e.data:byte(0x0D+1)
            local byte3 = e.data:byte(0x0E+1)
            local hourglass_time = byte1 + (byte2 * 256) + (byte3 * 65536)
            
            local hourglass_validation = {
                [17772867] = 48733,
                [17720029] = 49344,
                [17756500] = 43686,
                [17736063] = 49463
            }
            
            local expected_message_id = hourglass_validation[actor_ID]
            if expected_message_id and messageId == expected_message_id then
                local current_state = get_state()
                local now = os.time()
                
                -- Get the current base hourglass time (without accrual)
                local current_base = current_state.hourglass_time or -1
                
                -- Always update with the new packet value if it's different or if current_base is -1 (Unknown)
                -- This ensures we get the latest hourglass time from the server
                if hourglass_time ~= current_base or current_base == -1 then
                    -- Cap hourglass time at 60 hours (216000 seconds)
                    local max_hourglass_time = 216000
                    local capped_hourglass_time = math.min(hourglass_time, max_hourglass_time)
                    
                    -- Store the new hourglass time value as the base hourglass time
                    current_state.hourglass_time = capped_hourglass_time
                    current_state.hourglass_packet_timestamp = now  -- Store timestamp when packet was received
                    
                    if current_base == -1 then
                        if hourglass_time > max_hourglass_time then
                            print(chat.header('Keyring'):append(chat.message('Empty Hourglass time received from server: ' .. capped_hourglass_time .. ' seconds (capped at 60 hours)')))
                        else
                            print(chat.header('Keyring'):append(chat.message('Empty Hourglass time received from server: ' .. capped_hourglass_time .. ' seconds')))
                        end
                    elseif hourglass_time > max_hourglass_time then
                        print(chat.header('Keyring'):append(chat.message('Empty Hourglass time capped at 60 hours: ' .. capped_hourglass_time .. ' seconds (was ' .. current_base .. ' seconds)')))
                    else
                        print(chat.header('Keyring'):append(chat.message('Empty Hourglass time updated: ' .. capped_hourglass_time .. ' seconds (was ' .. current_base .. ' seconds)')))
                    end
                    
                    -- Save state after hourglass update
                    save_state()
                end
                
                debug_print('0x02A: Hourglass time processed in pre-Dynamis zone ' .. (current_zone or 'unknown'))
            end
        end
        
        -- Process Ruspix Plate data only in Outer Ra'Kaznar zones
        if is_in_outer_rakaznar and #e.data >= 0x1C then  -- Need at least 28 bytes for offset 0x1A (message ID)
            -- Validate this is a genuine Ruspix Plate response by checking message ID
            -- Message ID is at offset 0x1A as unsigned short (16-bit)
            local messageId = struct.unpack('H', e.data, 0x1A+1)
            debug_print('0x02A: Outer Ra\'Kaznar zone packet - message ID: ' .. messageId .. ' (expected: 70)')
            
            -- Note: struct.unpack('H') automatically handles unsigned short bounds (0-65535)
            
            if messageId ~= 70 then
                debug_print('0x02A: Ignoring packet in Outer Ra\'Kaznar zone - invalid message ID: ' .. messageId .. ' (expected: 70)')
                return
            end
            
            -- Process valid Ruspix Plate packet
            -- Extract Ruspix Plate time from offset 0x10-0x13 (32-bit value)
            local ruspix_plate_time = struct.unpack('I', e.data, 0x10+1)
            
            -- Additional validation: ensure the time value is reasonable
            if ruspix_plate_time < 0 or ruspix_plate_time > 1000000 then  -- Sanity check: 0 to ~11.5 days
                debug_print('0x02A: Ignoring Ruspix Plate packet - invalid time value: ' .. ruspix_plate_time .. ' seconds')
                return
            end
            
            local current_state = get_state()
            
            debug_print('0x02A: Validated Ruspix Plate response - message ID: ' .. messageId .. ', time: ' .. ruspix_plate_time .. ' seconds')
            
            -- Cap Ruspix Plate time at Shiny Plate cooldown value
            local max_ruspix_time = trackedKeyItems and trackedKeyItems[3300] and trackedKeyItems[3300].cooldown or 72000
            local capped_ruspix_time = math.min(ruspix_plate_time, max_ruspix_time)
            
            -- Update the packet time (same variable used by 0x05C)
            current_state.packet_ruspix_time = capped_ruspix_time
            
            if ruspix_plate_time > max_ruspix_time then
                debug_print('0x02A: Ruspix Plate time capped at ' .. math.floor(max_ruspix_time/3600) .. ' hours: ' .. capped_ruspix_time .. ' seconds (was ' .. ruspix_plate_time .. ' seconds)')
            else
                debug_print('0x02A: Ruspix Plate time updated from packet: ' .. capped_ruspix_time .. ' seconds')
            end
            
            -- Save state after Ruspix Plate update
            save_state()
            
            -- Trigger throttled GUI update callback to refresh display
            throttled_gui_update()
            
            debug_print('0x02A: Ruspix Plate time processed in Outer Ra\'Kaznar zone ' .. (current_zone or 'unknown'))
        end
        
        -- Debug output for zones where neither processing applies
        if not is_in_pre_dynamis and not is_in_outer_rakaznar then
            debug_print('0x02A: Packet received in zone ' .. (current_zone or 'unknown') .. ' - no processing needed for this zone')
        end
        
    elseif e.id == 0x118 then
        -- Canteen storage response (0x118)
        local current_state = get_state()
        
        local canteenCount = e.data:byte(12) or 0 
        canteenCount = math.min(canteenCount, 3)
        
        local previousCount = current_state.storage_canteens or 0
        
        -- Prevent processing duplicate packets with the same count
        if canteenCount == previousCount then
            debug_print('0x118: Ignoring duplicate packet - count unchanged: ' .. canteenCount)
            return
        end
        
        debug_print('0x118: Canteen storage update - previous: ' .. previousCount .. ', new: ' .. canteenCount .. ', change: ' .. (canteenCount - previousCount))
        
        -- Use smart cooldown management for all count changes
        handle_canteen_cooldown(previousCount, canteenCount)
        
        -- Check if canteens increased (indicating new generation)
        if canteenCount > previousCount then
            
            -- This could be due to our generation logic or external factors
            -- Don't modify the generation timer here - let update_storage_canteens handle it
            
            -- Update canteen timestamp for Mystical Canteen (ID 3137) if not already tracked
            local canteenId = 3137
            if not current_state.timestamps or not current_state.timestamps[canteenId] or current_state.timestamps[canteenId] == 0 then
                
                -- Don't set a timestamp - let the user acquire it manually for accuracy
                if not current_state.key_items then current_state.key_items = {} end
                current_state.key_items[canteenId] = true
                
                -- Show informative message
                print(chat.header('Keyring'):append(chat.message('Canteen storage increased but exact acquisition time unknown.')))
                print(chat.header('Keyring'):append(chat.message('Please acquire a canteen manually to start accurate tracking.')))
            end
        else
            -- Normal case: just update the count (no change detected)
        end

        -- Check if storage count actually changed
        if canteenCount ~= previousCount then
            debug_print('0x118: Storage count changed from ' .. previousCount .. ' to ' .. canteenCount .. ' - saving state')
            save_state()
        else
            debug_print('0x118: Storage count unchanged at ' .. canteenCount .. ' - no save needed')
        end
        
        -- Check for any discrepancy between packet and what we expected
        if canteenCount ~= previousCount then
            debug_print('0x118: Count change detected - packet shows ' .. canteenCount .. ', previous state was ' .. previousCount .. ' - using packet as authoritative')
        end
        
        current_state.storage_canteens = canteenCount

        -- Trigger currency callback if registered
        if currency_callback then
            currency_callback(canteenCount)
        end
    end
end)

-- Register packet handlers
ashita.events.register('packet_out', 'Keyring_Outgoing', function(e)
    if e.id == 0x05B then
        -- Check if this is a Ruspix request
        -- Target, Option Index, Target Index, Zone, Menu ID
        local target = struct.unpack('I', e.data, 0x04+1)  -- Target ID at offset 0x04
        local option_index = struct.unpack('H', e.data, 0x08+1)  -- Option Index at offset 0x08
        local target_index = struct.unpack('H', e.data, 0x0C+1)  -- Target Index at offset 0x0C
        local zone = struct.unpack('H', e.data, 0x10+1)  -- Zone at offset 0x10
        local menu_id = struct.unpack('H', e.data, 0x12+1)  -- Menu ID at offset 0x12
        
        debug_print('0x05B: Target=' .. target .. ', Option=' .. option_index .. ', TargetIndex=' .. target_index .. ', Zone=' .. zone .. ', Menu=' .. menu_id)
        
        -- Check if this looks like a Shiny Ra'Kaznarian Plate cooldown request
        -- Target=0x0111904A, Option=0x0004, Menu=0x0047
        if target == 0x0111904A and option_index == 0x0004 and menu_id == 0x0047 then
            shiny_plate_05b_sent = true
            debug_print('0x05B: Shiny Ra\'Kaznarian Plate cooldown request detected, setting validation flag')
        end
        
        -- Check if this looks like a Ruspix Plate time request
        -- Target=0x0111904A, Option=0x0005, Menu=0x0047
        if target == 0x0111904A and option_index == 0x0005 and menu_id == 0x0047 then
            ruspix_plate_05b_sent = true
            debug_print('0x05B: Ruspix Plate time request detected, setting validation flag')
        end
    end
end)
end

-- API functions for other modules
function handler.has_key_item(id)
    local current_state = get_state()
    return current_state.key_items and current_state.key_items[id] == true
end

function handler.get_timestamp(id)
    local current_state = get_state()
    return current_state.timestamps and current_state.timestamps[id] or 0
end

function handler.get_timestamps()
    local current_state = get_state()
    return current_state.timestamps or {}
end

function handler.set_timestamp(id, timestamp)
    local current_state = get_state()
    if not current_state.timestamps then current_state.timestamps = {} end
    if not current_state.key_items then current_state.key_items = {} end
    
    current_state.timestamps[id] = timestamp
    current_state.key_items[id] = true
    save_state()
    return true
end

function handler.get_remaining(id)
    local cooldown = trackedKeyItems[id] and trackedKeyItems[id].cooldown
    local ts = handler.get_timestamp(id)
    if not cooldown or not ts or ts <= 0 then 
        return 0 
    end
    return math.max(0, (ts + cooldown) - os.time())
end

function handler.is_available(id)
    local cooldown = trackedKeyItems[id] and trackedKeyItems[id].cooldown
    if not cooldown or cooldown == 0 then
        return not handler.has_key_item(id)
    end
    
    local ts = handler.get_timestamp(id)
    if not ts or ts <= 0 then 
        return false 
    end
    
    return os.time() >= (ts + cooldown)
end

function handler.get_storage_info()
    local current_state = get_state()
    return {
        count = current_state.storage_canteens or 0,
        last_storage = 0
    }
end

-- Legacy function removed - use get_canteen_generation_remaining() instead

function handler.update_storage_canteens()
    local current_state = get_state()
    local currentTime = os.time()
    
    -- Use smart cooldown state instead of legacy timer
    if current_state.canteen_cooldown_state == 'running' and current_state.storage_canteens and current_state.storage_canteens < 3 then
        local timeSinceTimerStart = currentTime - current_state.canteen_cooldown_start_time
        
        -- If the timer is more than 24 hours old, it's probably stale - reset it
        if timeSinceTimerStart > 86400 then  -- 24 hours
            print(chat.header('Keyring'):append(chat.message('Canteen generation timer is stale, resetting')))
            current_state.canteen_cooldown_state = 'idle'
            current_state.canteen_cooldown_start_time = 0
            save_state()
            return current_state.storage_canteens or 0
        end
        
        -- Check if canteen generation time has passed since timer started
        local canteen_cooldown = trackedKeyItems and trackedKeyItems[3137] and trackedKeyItems[3137].cooldown or 72000
        if timeSinceTimerStart >= canteen_cooldown then
            -- Generate one canteen
            current_state.storage_canteens = current_state.storage_canteens + 1
            
            -- If we haven't reached max capacity, continue the timer for next generation
            if current_state.storage_canteens < 3 then
                -- Reset timer to current time for next generation cycle
                current_state.canteen_cooldown_start_time = currentTime
                local hours = math.floor(canteen_cooldown / 3600)
                print(chat.header('Keyring'):append(chat.message('Canteen generated: ' .. current_state.storage_canteens .. '/3 - next canteen in ' .. hours .. ' hours')))
            else
                -- Storage is full, stop the timer
                current_state.canteen_cooldown_state = 'idle'
                current_state.canteen_cooldown_start_time = 0
                print(chat.header('Keyring'):append(chat.message('Canteen generated: ' .. current_state.storage_canteens .. '/3 - storage full')))
            end
            
            -- Save state immediately
            save_state()
        end
    end
    
    return current_state.storage_canteens or 0
end

function handler.get_canteen_generation_remaining()
    local current_state = get_state()
    
    -- If storage is full, no generation is happening
    if current_state.storage_canteens and current_state.storage_canteens >= 3 then
        return nil
    end
    
    -- Use smart cooldown state instead of legacy timer
    if current_state.canteen_cooldown_state ~= 'running' then
        return nil
    end
    
    local currentTime = os.time()
    local timeSinceTimerStart = currentTime - current_state.canteen_cooldown_start_time
    
    -- If the timer is more than 24 hours old, it's stale
    if timeSinceTimerStart > 86400 then
        return nil
    end
    
    -- Calculate remaining time until next generation
    local canteen_cooldown = trackedKeyItems and trackedKeyItems[3137] and trackedKeyItems[3137].cooldown or 72000
    local remaining = canteen_cooldown - timeSinceTimerStart
    return math.max(0, remaining)
end

function handler.get_dynamis_d_cooldown_remaining()
    local current_state = get_state()
    
    -- If no entry time recorded, no cooldown
    if not current_state.dynamis_d_entry_time or current_state.dynamis_d_entry_time <= 0 then
        return nil
    end
    
    local current_time = os.time()
    
    -- Use stored projected ready time if available; otherwise, fall back to entry_time + 60h
    local projected_ready_time = current_state.dynamis_projected_ready_time
    if not projected_ready_time or projected_ready_time <= 0 then
        projected_ready_time = (current_state.dynamis_d_entry_time or 0) + 216000 -- 60 hours
    end
    
    -- Calculate remaining time until ready
    local remaining = projected_ready_time - current_time
    
    return math.max(0, remaining)
end

function handler.get_dynamis_d_entry_time()
    local current_state = get_state()
    return current_state.dynamis_d_entry_time or 0
end

function handler.get_hourglass_time()
    local current_state = get_state()
    if not current_state then
        debug_print('get_hourglass_time: No current state')
        return -1
    end
    
    local base_hourglass_time = current_state.hourglass_time or -1
    
    -- If hourglass_time is -1 (Unknown), return -1
    if base_hourglass_time == -1 then
        return -1
    end
    
    local dynamis_d_entry_time = current_state.dynamis_d_entry_time or 0
    local current_time = os.time()
    
    debug_print('get_hourglass_time: base=' .. base_hourglass_time .. ', dynamis_d_entry_time=' .. dynamis_d_entry_time)
    
    -- Check if we're past the 60-hour mark from Dynamis [D] entry
    if dynamis_d_entry_time > 0 then
        local accrual_start_time = dynamis_d_entry_time + 216000  -- 60 hours = 216000 seconds
        if current_time > accrual_start_time then
            -- Past 60 hours - calculate accrual
            local time_since_accrual_start = current_time - accrual_start_time
            local accrued_time = math.floor(time_since_accrual_start / 5)  -- 1:5 ratio
            
            -- Apply cap: min(base_hourglass_time + accrued_time, 216000) - 60 hour max (Dynamis [D] cooldown)
            local total_time = math.min(base_hourglass_time + accrued_time, 216000)
            
            debug_print('get_hourglass_time: Past 60 hours, accrued_time=' .. accrued_time .. ', total=' .. total_time)
            return total_time
        else
            debug_print('get_hourglass_time: Within 60 hours, no accrual, returning base=' .. base_hourglass_time)
        end
    end
    
    -- No accrual - return base time only
    debug_print('get_hourglass_time: No dynamis entry time, returning base=' .. base_hourglass_time)
    return base_hourglass_time
end

function handler.get_hourglass_time_remaining()
    local hourglass_time = handler.get_hourglass_time()
    if hourglass_time == -1 then
        return -1  -- Unknown (no packet value received yet)
    elseif hourglass_time == 0 then
        return nil  -- No hourglass use recorded
    end
    
    -- Return the hourglass time value directly (this is a duration, not a cooldown)
    return hourglass_time
end

function handler.get_hourglass_packet_timestamp()
    local current_state = get_state()
    return current_state.hourglass_packet_timestamp or 0
end

-- Legacy function removed - use get_hourglass_time() instead

-- Helper function to format hourglass time for display
function handler.format_hourglass_time(hourglass_time)
    if hourglass_time == -1 then
        return "Unknown"
    elseif hourglass_time == 0 then
        return "0:00:00"
    else
        local hours = math.floor(hourglass_time / 3600)
        local minutes = math.floor((hourglass_time % 3600) / 60)
        local seconds = hourglass_time % 60
        return string.format("%d:%02d:%02d", hours, minutes, seconds)
    end
end

function handler.reset_hourglass_time()
    local current_state = get_state()
    current_state.hourglass_time = -1  -- Reset to "Unknown" until packet value is received
    current_state.hourglass_packet_timestamp = 0
    save_state()
    return true
end

function handler.force_hourglass_time(time_value)
    local current_state = get_state()
    current_state.hourglass_time = time_value
    current_state.hourglass_packet_timestamp = os.time()
    save_state()
    return true
end

-- Ruspix Plate Timer Functions

function handler.get_ruspix_time()
    local current_state = get_state()
    if not current_state then
        debug_print('get_ruspix_time: No current state')
        return 0
    end
    
    local packet_time = current_state.packet_ruspix_time or 0
    local shiny_plate_timestamp = current_state.timestamps and current_state.timestamps[3300] or 0
    local current_time = os.time()
    
    debug_print('get_ruspix_time: packet_time=' .. packet_time .. ', shiny_plate_timestamp=' .. shiny_plate_timestamp)
    
    -- Check if Shiny Plate is off cooldown
    if shiny_plate_timestamp > 0 then
        local shiny_plate_cooldown = trackedKeyItems and trackedKeyItems[3300] and trackedKeyItems[3300].cooldown or 72000
        local cooldown_end_time = shiny_plate_timestamp + shiny_plate_cooldown
        if current_time > cooldown_end_time then
            -- Shiny Plate is off cooldown - calculate accrual
            local time_since_cooldown_end = current_time - cooldown_end_time
            local accrued_time = math.floor(time_since_cooldown_end / 5)  -- 1:5 ratio
            
            -- Apply cap: min(packet_time + accrued_time, shiny_plate_cooldown)
            local total_time = math.min(packet_time + accrued_time, shiny_plate_cooldown)
            
            debug_print('get_ruspix_time: Shiny plate off cooldown, accrued_time=' .. accrued_time .. ', total=' .. total_time)
            return total_time
        else
            debug_print('get_ruspix_time: Shiny plate on cooldown, no accrual, returning packet_time=' .. packet_time)
        end
    end
    
    -- No accrual - return packet time only
    debug_print('get_ruspix_time: No shiny plate timestamp, returning packet_time=' .. packet_time)
    return packet_time
end

-- Legacy function removed - use get_ruspix_time() instead

function handler.get_ruspix_packet_time()
    local current_state = get_state()
    if not current_state then
        return 0
    end
    return current_state.packet_ruspix_time or 0
end

function handler.reset_ruspix_time()
    local current_state = get_state()
    if not current_state then
        return false
    end
    
    current_state.packet_ruspix_time = 0
    save_state()
    return true
end

function handler.force_ruspix_time(time_value)
    local current_state = get_state()
    if not current_state then
        return false
    end
    
    if type(time_value) ~= 'number' then
        return false
    end
    
    current_state.packet_ruspix_time = time_value
    save_state()
    return true
end

function handler.is_dynamis_d_available()
    local remaining = handler.get_dynamis_d_cooldown_remaining()
    return remaining == nil or remaining <= 0
end

function handler.save_state()
    save_state()
end

function handler.get_state()
    return get_state()
end

function handler.get_player_id()
    return player_ID
end

-- API: Register callback for zone change
function handler.set_zone_change_callback(cb)
    zone_callback = cb
end

-- API: Register callback for storage canteen updates
function handler.set_currency_callback(cb)
    currency_callback = cb
end

-- API: Register callback for GUI updates
function handler.set_gui_update_callback(cb)
    gui_update_callback = cb
end

-- Custom GUI update throttling using os.time (standard Lua)
local last_gui_update_time = 0
local gui_update_throttle = 5  -- 5 seconds

-- Throttled GUI update function
function handler.throttled_gui_update()
    local current_time = os.time()
    if current_time - last_gui_update_time >= gui_update_throttle then
        if gui_update_callback then
            gui_update_callback()
        end
        last_gui_update_time = current_time
    end
end

-- API: Get current zone ID
function handler.get_current_zone()
    return current_zone
end

-- API: Get previous zone ID
function handler.get_previous_zone()
    return previous_zone
end

-- No manual HasKeyItem checks needed - 0x55 packets handle this automatically

-- API: Set debug mode
function handler.set_debug_mode(enabled)
    debugMode = enabled
    debug_print("Debug mode " .. (enabled and "enabled" or "disabled") .. " in packet handler")
end

-- API: Clear debug throttle cache (simplified - no longer needed)
function handler.clear_debug_throttle()
    debug_print("Debug throttle cache cleared (no longer needed)")
end

-- API: Set debug throttle intervals (simplified - no longer needed)
function handler.set_debug_throttle_intervals(default_interval, render_interval)
    debug_print("Debug throttle intervals no longer used (simplified debug system)")
end

-- API: Manually request currency data (for testing/debugging)
function handler.request_currency_data()
    debug_print('Manual currency request triggered')
    request_currency_data()
    return true
end

-- API: Reset canteen request flags (for testing/debugging)
function handler.reset_canteen_flags()
    debug_print('Resetting canteen request flags')
    canteen_requested = false
    post_zone_check_done = false
    return true
end

-- Simple timer system using os.time (standard Lua)
local last_periodic_save_time = 0
local periodic_save_interval = 5  -- 5 seconds

-- Periodic save check (called from main addon loop)
function handler.check_periodic_save()
    local current_time = os.time()
    if current_time - last_periodic_save_time >= periodic_save_interval then
        save_state()
        last_periodic_save_time = current_time
    end
end

-- Main timer check function - call this from the main addon loop
function handler.check_all_timers()
    -- Check periodic save
    handler.check_periodic_save()
    
    -- Check canteen generation
    handler.update_storage_canteens()
end

-- Save state on unload
if ashita.events then
    ashita.events.register('unload', 'Keyring_Unload_Save', function()
        pcall(function()
            -- Force save any dirty state before unloading
            local current_state = get_state()
            if current_state and current_state.is_dirty then
                debug_print('Unloading with dirty state - forcing save')
                save_state()
            end
        end)
    end)
else
    debug_print('Warning: ashita.events not available - unload save disabled')
end

-- Notification cooldown API removed - no longer needed

return handler
