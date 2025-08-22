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

-- Simple debug function
local function debug_print(message)
    if debugMode then
        print('[Keyring Debug] ' .. tostring(message))
    end
end

-- Simple state management
local state = {
    key_items = {
        [3212] = false,  -- moglophone
        [3137] = false,  -- mystical canteen
        [3300] = false,  -- shiny Ra'Kaznarian plate
        [3052] = false,  -- Ambuscade Primer Vol. 1
        [3053] = false,  -- Ambuscade Primer Vol. 2
    },
    timestamps = {
        [3212] = 0,  -- moglophone
        [3137] = 0,  -- mystical canteen
        [3300] = 0,  -- shiny Ra'Kaznarian plate
        [3052] = 0,  -- Ambuscade Primer Vol. 1
        [3053] = 0,  -- Ambuscade Primer Vol. 2
    },
    storage_canteens = 0,
    last_canteen_time = 0,
    hourglass_time = 0,
    hourglass_packet_timestamp = 0,
    hourglass_accumulated_time = 0,
    hourglass_last_save_timestamp = 0,
    dynamis_d_entry_time = 0,
    dynamis_projected_ready_time = 0,
    packet_ruspix_time = 0,  -- Ruspix Plate timer from packet data
    ruspix_accumulated_time = 0,  -- Accumulated time for Ruspix Plate accrual
    ruspix_last_save_timestamp = 0,  -- Timestamp when Ruspix accumulated time was last saved
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

-- Flag to track if we've already requested canteen data after login/reload
local canteen_requested = false

-- Flag to track if we've done the post-0x0A key item check
local post_zone_check_done = false

-- Flag to track if currently targeting Ruspix (runtime only, not persisted)
local is_ruspix = false

-- Request Storage Slip Canteen info (outgoing packet 0x115)
local function request_currency_data()
    local packet = struct.pack('bbbb', 0x15, 0x03, 0x00, 0x00):totable()
    AshitaCore:GetPacketManager():AddOutgoingPacket(0x115, packet)
    debug_print('Sent 0x115 currency request packet')
end

-- Load state from persistence
local function load_state()
    local loaded_state = persistence.load_state(debug_print)
    
    -- Create a deep copy to avoid reference issues with settings library
    if type(loaded_state) == 'table' then
        local new_state = {
            key_items = {},
            timestamps = {},
            storage_canteens = tonumber(loaded_state.storage_canteens) or 0,
            last_canteen_time = tonumber(loaded_state.last_canteen_time) or 0,
            hourglass_time = tonumber(loaded_state.hourglass_time) or 0,
            hourglass_packet_timestamp = tonumber(loaded_state.hourglass_packet_timestamp) or 0,
            hourglass_accumulated_time = tonumber(loaded_state.hourglass_accumulated_time) or 0,
            hourglass_last_save_timestamp = tonumber(loaded_state.hourglass_last_save_timestamp) or 0,
            dynamis_d_entry_time = tonumber(loaded_state.dynamis_d_entry_time) or 0,
            dynamis_projected_ready_time = tonumber(loaded_state.dynamis_projected_ready_time) or 0,
            packet_ruspix_time = tonumber(loaded_state.packet_ruspix_time) or 0,
            ruspix_accumulated_time = tonumber(loaded_state.ruspix_accumulated_time) or 0,
            ruspix_last_save_timestamp = tonumber(loaded_state.ruspix_last_save_timestamp) or 0
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

-- Get current state
local function get_state()
    return state
end

-- Calculate and update accumulated hourglass time
local function update_accumulated_hourglass_time()
    local current_state = get_state()
    local now = os.time()
    
    -- Only calculate if we have a valid packet timestamp
    if current_state.hourglass_packet_timestamp and current_state.hourglass_packet_timestamp > 0 then
        -- Check if Dynamis [D] is off cooldown (only accumulate when off cooldown)
        local dynamis_off_cooldown = true
        if current_state.dynamis_d_entry_time and current_state.dynamis_d_entry_time > 0 then
            local time_since_entry = now - current_state.dynamis_d_entry_time
            local cooldown_duration = 216000  -- 60 hours = 216000 seconds
            if time_since_entry < cooldown_duration then
                dynamis_off_cooldown = false
            end
        end
        
        if dynamis_off_cooldown then
            local time_since_packet = now - current_state.hourglass_packet_timestamp
            
            -- Hourglass time increments by 1 second for every 5 seconds elapsed
            local new_accumulated = math.floor(time_since_packet / 5)
            
            -- Update the accumulated time
            current_state.hourglass_accumulated_time = new_accumulated
            current_state.hourglass_last_save_timestamp = now
            
            debug_print('Updated accumulated hourglass time: ' .. new_accumulated .. ' seconds (time since packet: ' .. time_since_packet .. ' seconds)')
        else
            debug_print('Dynamis [D] on cooldown - not accumulating hourglass time')
        end
    end
end

-- Calculate and update accumulated Ruspix Plate time
local function update_accumulated_ruspix_time()
    local current_state = get_state()
    if not current_state then
        return
    end
    
    local now = os.time()
    
    -- Check if Shiny Rakaznarian Plate is off cooldown (regardless of ownership)
    local shiny_plate_timestamp = current_state.timestamps and current_state.timestamps[3300] or 0
    local shiny_plate_cooldown = trackedKeyItems and trackedKeyItems[3300] and trackedKeyItems[3300].cooldown or 0
    
    -- Calculate if Shiny Rakaznarian Plate is off cooldown
    local shiny_plate_off_cooldown = false
    if shiny_plate_cooldown > 0 then
        local time_since_acquisition = now - shiny_plate_timestamp
        if time_since_acquisition >= shiny_plate_cooldown then
            shiny_plate_off_cooldown = true
        end
    end
    
    -- Only accumulate when Shiny Rakaznarian Plate is off cooldown (regardless of ownership)
    if shiny_plate_off_cooldown then
        -- Only calculate if we have a valid last save timestamp
        if current_state.ruspix_last_save_timestamp and current_state.ruspix_last_save_timestamp > 0 then
            local time_since_last_save = now - current_state.ruspix_last_save_timestamp
            
            -- Ruspix Plate time increments by 1 second for every 5 seconds elapsed
            local new_accumulated = math.floor(time_since_last_save / 5)
            
            -- Get Shiny Rakaznarian Plate cooldown for maximum accumulation
            local shiny_plate_cooldown = trackedKeyItems and trackedKeyItems[3300] and trackedKeyItems[3300].cooldown or 72000
            new_accumulated = math.min(shiny_plate_cooldown, new_accumulated)
            
            -- Update the accumulated time
            current_state.ruspix_accumulated_time = new_accumulated
            current_state.ruspix_last_save_timestamp = now
            
            debug_print('Updated accumulated Ruspix Plate time: ' .. new_accumulated .. ' seconds (time since last save: ' .. time_since_last_save .. ' seconds)')
        end
    else
        debug_print('Shiny Rakaznarian Plate on cooldown - not accumulating Ruspix Plate time')
    end
end

-- Save state to persistence
local function save_state()
    -- Update accumulated hourglass time before saving
    update_accumulated_hourglass_time()
    -- Update accumulated Ruspix Plate time before saving
    update_accumulated_ruspix_time()
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
        

        
        -- Trigger GUI update callback to refresh display with loaded data
        if gui_update_callback then
            pcall(gui_update_callback)
        end
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
        
        -- Trigger GUI update callback to refresh display with loaded data
        if gui_update_callback then
            pcall(gui_update_callback)
        end
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
    
    debug_print('Force initialization complete')
end

-- API: Clear persistence data (for fixing incorrect data)
function handler.clear_persistence_data()
    debug_print('Clearing persistence data...')
    
    -- Reset state to empty
    state = {
        key_items = {
            [3212] = false,  -- moglophone
            [3137] = false,  -- mystical canteen
            [3300] = false,  -- shiny Ra'Kaznarian plate
            [3052] = false,  -- Ambuscade Primer Vol. 1
            [3053] = false,  -- Ambuscade Primer Vol. 2
        },
        timestamps = {
            [3212] = 0,  -- moglophone
            [3137] = 0,  -- mystical canteen
            [3300] = 0,  -- shiny Ra'Kaznarian plate
            [3052] = 0,  -- Ambuscade Primer Vol. 1
            [3053] = 0,  -- Ambuscade Primer Vol. 2
        },
        storage_canteens = 0,
        last_canteen_time = 0,
        dynamis_d_entry_time = 0,
        dynamis_projected_ready_time = 0,
        hourglass_time = 0,
        hourglass_packet_timestamp = 0,
        hourglass_accumulated_time = 0,
        hourglass_last_save_timestamp = 0,
        packet_ruspix_time = 0,
        ruspix_accumulated_time = 0,
        ruspix_last_save_timestamp = 0
    }
    
    -- Save empty state to overwrite persistence file
            save_state()
    
    -- Reset initialization flag
    is_initialized = false
    player_ID = nil
    
    -- Reset runtime-only flags
    is_ruspix = false
    
    debug_print('Persistence data cleared')
end

-- API: Force clear persistence file (for fixing persistent incorrect data)
function handler.force_clear_persistence_file()
    debug_print('Force clearing persistence file...')
    
    -- Reset state to empty
    state = {
        key_items = {
            [3212] = false,  -- moglophone
            [3137] = false,  -- mystical canteen
            [3300] = false,  -- shiny Ra'Kaznarian plate
            [3052] = false,  -- Ambuscade Primer Vol. 1
            [3053] = false,  -- Ambuscade Primer Vol. 2
        },
        timestamps = {
            [3212] = 0,  -- moglophone
            [3137] = 0,  -- mystical canteen
            [3300] = 0,  -- shiny Ra'Kaznarian plate
            [3052] = 0,  -- Ambuscade Primer Vol. 1
            [3053] = 0,  -- Ambuscade Primer Vol. 2
        },
        storage_canteens = 0,
        last_canteen_time = 0,
        dynamis_d_entry_time = 0,
        dynamis_projected_ready_time = 0,
        hourglass_time = 0,
        hourglass_packet_timestamp = 0,
        hourglass_accumulated_time = 0,
        hourglass_last_save_timestamp = 0,
        packet_ruspix_time = 0,
        ruspix_accumulated_time = 0,
        ruspix_last_save_timestamp = 0
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
    is_ruspix = false
    
    debug_print('Persistence file force cleared')
end

-- API: Nuclear clear - clear all persistence data
function handler.nuclear_clear_persistence()
    debug_print('Nuclear clearing persistence data...')
    
    -- Clear internal state
    state = {
        key_items = {
            [3212] = false,  -- moglophone
            [3137] = false,  -- mystical canteen
            [3300] = false,  -- shiny Ra'Kaznarian plate
            [3052] = false,  -- Ambuscade Primer Vol. 1
            [3053] = false,  -- Ambuscade Primer Vol. 2
        },
        timestamps = {
            [3212] = 0,  -- moglophone
            [3137] = 0,  -- mystical canteen
            [3300] = 0,  -- shiny Ra'Kaznarian plate
            [3052] = 0,  -- Ambuscade Primer Vol. 1
            [3053] = 0,  -- Ambuscade Primer Vol. 2
        },
        storage_canteens = 0,
        last_canteen_time = 0,
        dynamis_d_entry_time = 0,
        dynamis_projected_ready_time = 0,
        hourglass_time = 0,
        hourglass_packet_timestamp = 0,
        hourglass_accumulated_time = 0,
        hourglass_last_save_timestamp = 0,
        packet_ruspix_time = 0,
        ruspix_accumulated_time = 0,
        ruspix_last_save_timestamp = 0,
    }
    
    -- Clear persistence data using the settings library
    local success = persistence.clear_all_data(debug_print)
    if success then
        print(chat.header('Keyring'):append(chat.message('Successfully cleared all persistence data!')))
    else
        print(chat.header('Keyring'):append(chat.message('Failed to clear persistence data')))
    end
    
    -- Reset runtime-only flags
    is_ruspix = false
    
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
    

    
    -- Ensure tables exist
    if not current_state.timestamps then current_state.timestamps = {} end
    if not current_state.key_items then current_state.key_items = {} end
    
    for id, data in pairs(trackedKeyItems) do
        local timestamp = current_state.timestamps[id] or 0
        local remaining = nil
        
        if timestamp > 0 then
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
    
    return result
end

-- PACKET HANDLERS

-- Handle 0x55 packets (key item list)
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
                    
                    -- If Mystical Canteen ownership changed, request storage count update
                    if ki == 3137 then
                        debug_print('0x55: Mystical Canteen ownership changed to ' .. tostring(hasKeyItem) .. ' - requesting storage count update')
                        request_currency_data()
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
                            current_state.ruspix_accumulated_time = 0
                            current_state.ruspix_last_save_timestamp = os.time()
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
                            break
                        end
                    end
                    
                    local save_result = save_state()
                    
                    -- Trigger GUI update callback to refresh display
                    if gui_update_callback then
                        pcall(gui_update_callback)
                    end
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
            is_ruspix = true
            debug_print('0x034: Ruspix detected, setting is_ruspix to true')
        else
            is_ruspix = false
            debug_print('0x034: Not Ruspix (ID: ' .. npc_id .. '), setting is_ruspix to false')
        end
        
        -- No need to save state for runtime-only flag
        debug_print('0x034: is_ruspix flag updated to: ' .. tostring(is_ruspix))
        
    elseif e.id == 0x05C then
        -- Ruspix Plate Timer Packet
        debug_print('0x05C: Received packet, size: ' .. #e.data)
        
        -- Check if packet data is long enough for the expected offset
        if #e.data < 0x0C then  -- Need at least 12 bytes for offset 0x08-0x0B
            debug_print('0x05C: Packet too short, expected at least 12 bytes, got ' .. #e.data)
            return
        end
        
        -- Check if we're currently targeting Ruspix
        debug_print('0x05C: Current is_ruspix flag: ' .. tostring(is_ruspix))
        if not is_ruspix then
            debug_print('0x05C: Not targeting Ruspix, skipping packet')
            return
        end
        
        -- Extract Ruspix Plate timer value from offset 0x08-0x0B
        local ruspix_cooldown = struct.unpack('I', e.data, 0x08+1)
        
        debug_print('0x05C: Ruspix Plate timer received: ' .. ruspix_cooldown .. ' seconds')
        
        -- Get current state for updates
        local current_state = get_state()
        
        -- Get Shiny Rakaznarian Plate remaining cooldown
        local shiny_plate_remaining = 0
        local has_valid_cooldown = false
        
        if trackedKeyItems and trackedKeyItems[3300] then
            local shiny_plate_timestamp = current_state.timestamps and current_state.timestamps[3300] or 0
            local shiny_plate_cooldown = trackedKeyItems[3300].cooldown or 72000
            local now = os.time()
            
            -- Safety check: Only process if there's actually a valid cooldown
            if shiny_plate_cooldown and shiny_plate_cooldown > 0 then
                has_valid_cooldown = true
                
                if shiny_plate_timestamp > 0 then
                    local time_since_acquisition = now - shiny_plate_timestamp
                    if time_since_acquisition < shiny_plate_cooldown then
                        shiny_plate_remaining = shiny_plate_cooldown - time_since_acquisition
                    end
                end
            else
                debug_print('0x05C: Shiny Rakaznarian Plate cooldown is 0 or nil, skipping timestamp update')
                return
            end
        else
            debug_print('0x05C: Shiny Rakaznarian Plate not tracked, skipping timestamp update')
            return
        end
        
        -- Only proceed if we have a valid cooldown to work with
        if not has_valid_cooldown then
            debug_print('0x05C: No valid cooldown found, skipping timestamp update')
            return
        end
        
        -- Calculate packet_ruspix_time: Shiny Rakaznarian Plate remaining cooldown - 0x05C value
        local calculated_ruspix_time = shiny_plate_remaining - ruspix_cooldown
        
        -- Cap Ruspix Plate time at 20 hours (72000 seconds)
        local max_ruspix_time = 72000
        local capped_ruspix_time = math.min(calculated_ruspix_time, max_ruspix_time)
        
        current_state.packet_ruspix_time = capped_ruspix_time
        current_state.ruspix_accumulated_time = 0  -- Reset accrual since this is new packet data
        current_state.ruspix_last_save_timestamp = os.time()  -- Update timestamp for accrual tracking
        
        -- Save the state
        save_state()
        
        if calculated_ruspix_time > max_ruspix_time then
            debug_print('0x05C: packet_ruspix_time capped at 20 hours: ' .. capped_ruspix_time .. ' seconds (was ' .. calculated_ruspix_time .. ' seconds), accrual reset to 0')
        else
            debug_print('0x05C: packet_ruspix_time set to: ' .. capped_ruspix_time .. ' seconds, accrual reset to 0')
        end
        
        -- Trigger GUI update callback to refresh display
        if gui_update_callback then
            pcall(gui_update_callback)
        end
        
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
            debug_print('Zone changed from ' .. (previous_zone or 'unknown') .. ' to ' .. current_zone)
            
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
                        current_state.hourglass_accumulated_time = 0  -- Reset accumulated time since we consumed it
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
        -- Hourglass usage detection with accrual logic
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
            local current_base = current_state.hourglass_time or 0
            
            -- Always update with the new packet value if it's different
            -- This ensures we get the latest hourglass time from the server
            if hourglass_time ~= current_base then
                -- Cap hourglass time at 60 hours (216000 seconds)
                local max_hourglass_time = 216000
                local capped_hourglass_time = math.min(hourglass_time, max_hourglass_time)
                
                -- Store the new hourglass time value as the base hourglass time
                current_state.hourglass_time = capped_hourglass_time
                current_state.hourglass_packet_timestamp = now  -- Store timestamp when packet was received
                
                -- Reset accumulated time since the new packet value includes any accumulated time
                current_state.hourglass_accumulated_time = 0
                current_state.hourglass_last_save_timestamp = now
                
                if hourglass_time > max_hourglass_time then
                    print(chat.header('Keyring'):append(chat.message('Empty Hourglass time capped at 60 hours: ' .. capped_hourglass_time .. ' seconds')))
                else
                    print(chat.header('Keyring'):append(chat.message('Empty Hourglass time updated: ' .. capped_hourglass_time .. ' seconds')))
                end
            else
                -- Time matches current base - no update needed
            end
            
            -- Empty Hourglass time is tracked but not actively consumed here
            -- Consumption happens automatically when entering Dynamis while on cooldown
            
            save_state()
        end
        
        -- Ruspix Plate time extraction from 0x02A packet
        if #e.data >= 0x1C then  -- Need at least 28 bytes for offset 0x18-0x1B
            local ruspix_time = struct.unpack('I', e.data, 0x18+1)  -- 32-bit at offset 0x18-0x1B
            
            -- Only update if we're in an Outer Rakaznar zone
            local outer_rakaznar_zones = {275, 133, 189}  -- Outer Ra'Kaznar [U1], [U2], [U3]
            local is_in_outer_rakaznar = false
            
            for _, zone_id in ipairs(outer_rakaznar_zones) do
                if current_zone == zone_id then
                    is_in_outer_rakaznar = true
                    break
                end
            end
            
            if is_in_outer_rakaznar then
                local current_state = get_state()
                
                -- Cap Ruspix Plate time at 20 hours (72000 seconds)
                local max_ruspix_time = 72000
                local capped_ruspix_time = math.min(ruspix_time, max_ruspix_time)
                
                -- Update the packet time (same variable used by 0x05C)
                current_state.packet_ruspix_time = capped_ruspix_time
                current_state.ruspix_accumulated_time = 0  -- Reset accrual since this is new packet data
                current_state.ruspix_last_save_timestamp = os.time()  -- Update timestamp for accrual tracking
                
                if ruspix_time > max_ruspix_time then
                    debug_print('0x02A: Ruspix Plate time capped at 20 hours: ' .. capped_ruspix_time .. ' seconds (was ' .. ruspix_time .. ' seconds), accrual reset to 0')
                else
                    debug_print('0x02A: Ruspix Plate time updated from packet: ' .. capped_ruspix_time .. ' seconds, accrual reset to 0')
                end
                
                save_state()
                
                -- Trigger GUI update callback to refresh display
                if gui_update_callback then
                    pcall(gui_update_callback)
                end
            end
        end
        
    elseif e.id == 0x118 then
        -- Canteen storage response (0x118)
        local current_state = get_state()

        local canteenCount = e.data:byte(12) or 0 
        canteenCount = math.min(canteenCount, 3)
        
        local previousCount = current_state.storage_canteens or 0
        
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
        elseif canteenCount < previousCount then
            -- Canteen was used (count decreased)
            
            -- Start the generation timer when storage decreases from 3 to 2
            if previousCount == 3 and canteenCount == 2 then
                current_state.last_canteen_time = os.time()
                print(chat.header('Keyring'):append(chat.message('Canteen cooldown started - next canteen in 20 hours')))
            end
        else
            -- Normal case: just update the count (no change detected)
        end

        current_state.storage_canteens = canteenCount

        -- Trigger currency callback if registered
        if currency_callback then
            currency_callback(canteenCount)
        end

        -- Save state after canteen data changes
        save_state()
    end
end)

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

function handler.get_canteen_timestamp()
    local current_state = get_state()
    return current_state.last_canteen_time or 0
end

function handler.update_storage_canteens()
    local current_state = get_state()
    local currentTime = os.time()
    
    -- Only process if we have a valid generation timer and storage is not full
    if current_state.last_canteen_time and current_state.last_canteen_time > 0 and current_state.storage_canteens and current_state.storage_canteens < 3 then
        local timeSinceTimerStart = currentTime - current_state.last_canteen_time
        
        -- If the timer is more than 24 hours old, it's probably stale - reset it
        if timeSinceTimerStart > 86400 then  -- 24 hours
            print(chat.header('Keyring'):append(chat.message('Canteen generation timer is stale, resetting')))
            current_state.last_canteen_time = 0
            save_state()
            return current_state.storage_canteens or 0
        end
        
        -- Check if 20 hours have passed since timer started
        if timeSinceTimerStart >= 72000 then  -- 20 hours = 72000 seconds
            -- Generate one canteen
            current_state.storage_canteens = current_state.storage_canteens + 1
            
            -- If we haven't reached max capacity, continue the timer for next generation
            if current_state.storage_canteens < 3 then
                -- Reset timer to current time for next generation cycle
                current_state.last_canteen_time = currentTime
                print(chat.header('Keyring'):append(chat.message('Canteen generated: ' .. current_state.storage_canteens .. '/3 - next canteen in 20 hours')))
            else
                -- Storage is full, stop the timer
                current_state.last_canteen_time = 0
                print(chat.header('Keyring'):append(chat.message('Canteen generated: ' .. current_state.storage_canteens .. '/3 - storage full')))
            end
            
            -- Save state after updating
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
    
    -- If no timer is active, no generation is happening
    if not current_state.last_canteen_time or current_state.last_canteen_time <= 0 then
        return nil
    end
    
    local currentTime = os.time()
    local timeSinceTimerStart = currentTime - current_state.last_canteen_time
    
    -- If the timer is more than 24 hours old, it's stale
    if timeSinceTimerStart > 86400 then
        return nil
    end
    
    -- Calculate remaining time until next generation (20 hours = 72000 seconds)
    local remaining = 72000 - timeSinceTimerStart
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
    local base_hourglass_time = current_state.hourglass_time or 0
    local accumulated_time = current_state.hourglass_accumulated_time or 0
    local last_save_timestamp = current_state.hourglass_last_save_timestamp or 0
    
    -- If no Dynamis D entry time recorded, return base hourglass time plus accumulated
    if not current_state.dynamis_d_entry_time or current_state.dynamis_d_entry_time <= 0 then
        -- Calculate any additional time since last save
        local now = os.time()
        local time_since_last_save = now - last_save_timestamp
        local additional_accumulated = math.floor(time_since_last_save / 5)
        
        return base_hourglass_time + accumulated_time + additional_accumulated
    end
    
    local current_time = os.time()
    local dynamis_entry_time = current_state.dynamis_d_entry_time
    local dynamis_ready_time = dynamis_entry_time + 216000 -- 60 hours (216000 seconds)
    
    -- Only start accrual after Dynamis D entry time + 60 hours
    if current_time <= dynamis_ready_time then
        return base_hourglass_time + accumulated_time
    end
    
    -- Calculate time elapsed since Dynamis D entry time + 60 hours
    local time_elapsed = current_time - dynamis_ready_time
    
    -- Hourglass time increments by 1 second for every 5 seconds elapsed
    local accrual_time = math.floor(time_elapsed / 5)
    
    -- Return base hourglass time plus accumulated time plus accrual time
    return base_hourglass_time + accumulated_time + accrual_time
end

function handler.get_hourglass_time_remaining()
    local hourglass_time = handler.get_hourglass_time()
    if hourglass_time == 0 then
        return nil  -- No hourglass use recorded
    end
    
    -- Return the hourglass time value directly (this is a duration, not a cooldown)
    return hourglass_time
end

function handler.get_hourglass_packet_timestamp()
    local current_state = get_state()
    return current_state.hourglass_packet_timestamp or 0
end

function handler.get_hourglass_accumulated_time()
    local current_state = get_state()
    local accumulated_time = current_state.hourglass_accumulated_time or 0
    local last_save_timestamp = current_state.hourglass_last_save_timestamp or 0
    
    -- Calculate any additional time since last save
    local now = os.time()
    local time_since_last_save = now - last_save_timestamp
    local additional_accumulated = math.floor(time_since_last_save / 5)
    
    return accumulated_time + additional_accumulated
end

function handler.get_hourglass_last_save_timestamp()
    local current_state = get_state()
    return current_state.hourglass_last_save_timestamp or 0
end

function handler.reset_hourglass_time()
    local current_state = get_state()
    current_state.hourglass_time = 0
    current_state.hourglass_packet_timestamp = 0
    current_state.hourglass_accumulated_time = 0
    current_state.hourglass_last_save_timestamp = 0
    save_state()
    return true
end

function handler.force_hourglass_time(time_value)
    local current_state = get_state()
    current_state.hourglass_time = time_value
    current_state.hourglass_packet_timestamp = os.time()
    current_state.hourglass_accumulated_time = 0
    current_state.hourglass_last_save_timestamp = os.time()
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
    
    local base_ruspix_time = current_state.packet_ruspix_time or 0
    local accumulated_time = current_state.ruspix_accumulated_time or 0
    local last_save_timestamp = current_state.ruspix_last_save_timestamp or 0
    
    debug_print('get_ruspix_time: base=' .. base_ruspix_time .. ', accumulated=' .. accumulated_time .. ', last_save=' .. last_save_timestamp)
    
    -- Check if Shiny Rakaznarian Plate is off cooldown (regardless of ownership)
    local shiny_plate_timestamp = current_state.timestamps and current_state.timestamps[3300] or 0
    local shiny_plate_cooldown = trackedKeyItems and trackedKeyItems[3300] and trackedKeyItems[3300].cooldown or 0
    
    -- Calculate if Shiny Rakaznarian Plate is off cooldown
    local shiny_plate_off_cooldown = false
    if shiny_plate_cooldown > 0 then
        local now = os.time()
        local time_since_acquisition = now - shiny_plate_timestamp
        if time_since_acquisition >= shiny_plate_cooldown then
            shiny_plate_off_cooldown = true
        end
    end
    
    -- If Shiny Rakaznarian Plate is off cooldown, calculate additional accrual
    if shiny_plate_off_cooldown then
        -- Calculate any additional time since last save
        local now = os.time()
        local time_since_last_save = now - last_save_timestamp
        local additional_accumulated = math.floor(time_since_last_save / 5)  -- 1 second per 5 seconds
        
        -- Get Shiny Rakaznarian Plate cooldown for maximum total
        local shiny_plate_cooldown = trackedKeyItems and trackedKeyItems[3300] and trackedKeyItems[3300].cooldown or 72000
        local total = math.min(shiny_plate_cooldown, base_ruspix_time + accumulated_time + additional_accumulated)
        debug_print('get_ruspix_time: Shiny plate off cooldown, additional=' .. additional_accumulated .. ', total=' .. total)
        return total
    end
    
    -- If Shiny Rakaznarian Plate is on cooldown, return base time plus accumulated (no further accrual)
    local total = base_ruspix_time + accumulated_time
    debug_print('get_ruspix_time: Shiny plate on cooldown, total=' .. total)
    return total
end

function handler.get_ruspix_accumulated_time()
    local current_state = get_state()
    if not current_state then
        return 0
    end
    
    local accumulated_time = current_state.ruspix_accumulated_time or 0
    local last_save_timestamp = current_state.ruspix_last_save_timestamp or 0
    
    -- Check if Shiny Rakaznarian Plate is off cooldown (regardless of ownership)
    local shiny_plate_timestamp = current_state.timestamps and current_state.timestamps[3300] or 0
    local shiny_plate_cooldown = trackedKeyItems and trackedKeyItems[3300] and trackedKeyItems[3300].cooldown or 0
    
    -- Calculate if Shiny Rakaznarian Plate is off cooldown
    local shiny_plate_off_cooldown = false
    if shiny_plate_cooldown > 0 then
        local now = os.time()
        local time_since_acquisition = now - shiny_plate_timestamp
        if time_since_acquisition >= shiny_plate_cooldown then
            shiny_plate_off_cooldown = true
        end
    end
    
    -- If Shiny Rakaznarian Plate is on cooldown, no further accrual
    if not shiny_plate_off_cooldown then
        return accumulated_time
    end
    
    -- Calculate any additional time since last save
    local now = os.time()
    local time_since_last_save = now - last_save_timestamp
    local additional_accumulated = math.floor(time_since_last_save / 5)  -- 1 second per 5 seconds
    
            -- Get Shiny Rakaznarian Plate cooldown for maximum accumulated
        local shiny_plate_cooldown = trackedKeyItems and trackedKeyItems[3300] and trackedKeyItems[3300].cooldown or 72000
        return math.min(shiny_plate_cooldown, accumulated_time + additional_accumulated)
end

function handler.get_ruspix_last_save_timestamp()
    local current_state = get_state()
    if not current_state then
        return 0
    end
    return current_state.ruspix_last_save_timestamp or 0
end

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
    current_state.ruspix_accumulated_time = 0
    current_state.ruspix_last_save_timestamp = os.time()
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
    current_state.ruspix_accumulated_time = 0
    current_state.ruspix_last_save_timestamp = os.time()
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

-- Save state on unload
ashita.events.register('unload', 'Keyring_Unload_Save', function()
    pcall(function()
        save_state()
    end)
end)

return handler
