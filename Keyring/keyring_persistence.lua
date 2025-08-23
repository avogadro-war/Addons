-- Keyring Persistence Module (pure settings library)

require('common')
local chat = require('chat')
local settingslib = require('settings')

local persistence = {}

local SETTINGS_ALIAS = 'settings'

-- Simplified defaults - direct key_items table
local DEFAULTS = T{
    key_items = T{
        [3212] = false,  -- moglophone
        [3137] = false,  -- mystical canteen
        [3300] = false,  -- shiny Ra'Kaznarian plate
        [3052] = false,  -- Ambuscade Primer Vol. 1
        [3053] = false,  -- Ambuscade Primer Vol. 2
        [3234] = false,  -- Moglophone II (variant 1)
        [3235] = false,  -- Moglophone II (variant 2)
        [3236] = false,  -- Moglophone II (variant 3)
    },
    timestamps = T{
        [3212] = 0,  -- moglophone
        [3137] = 0,  -- mystical canteen
        [3300] = 0,  -- shiny Ra'Kaznarian plate
        -- Note: Moglophone II variants (3234, 3235, 3236) have no cooldown, so no timestamps needed
    },
    storage_canteens = 0,
    last_canteen_time = 0,
    dynamis_d_entry_time = 0,
    dynamis_projected_ready_time = 0,
    hourglass_time = 0,
    hourglass_packet_timestamp = 0,
    hourglass_accumulated_time = 0,  -- Accumulated time since last packet
    hourglass_last_save_timestamp = 0,  -- Timestamp when accumulated time was last saved
    packet_ruspix_time = 0,  -- Ruspix Plate timer from packet data
    ruspix_accumulated_time = 0,  -- Accumulated time for Ruspix Plate accrual
    ruspix_last_save_timestamp = 0,  -- Timestamp when Ruspix accumulated time was last saved
}

-- Public API: load
function persistence.load_state(debug_print)
    if debug_print then debug_print('Loading settings via Ashita settings library') end
    
    local settings_tbl = settingslib.load(DEFAULTS, SETTINGS_ALIAS)

    -- Coerce numeric fields
    settings_tbl.storage_canteens = tonumber(settings_tbl.storage_canteens) or 0
    settings_tbl.last_canteen_time = tonumber(settings_tbl.last_canteen_time) or 0
    settings_tbl.dynamis_d_entry_time = tonumber(settings_tbl.dynamis_d_entry_time) or 0
    settings_tbl.dynamis_projected_ready_time = tonumber(settings_tbl.dynamis_projected_ready_time) or 0
    settings_tbl.hourglass_time = tonumber(settings_tbl.hourglass_time) or 0
    settings_tbl.hourglass_packet_timestamp = tonumber(settings_tbl.hourglass_packet_timestamp) or 0
    settings_tbl.hourglass_accumulated_time = tonumber(settings_tbl.hourglass_accumulated_time) or 0
    settings_tbl.hourglass_last_save_timestamp = tonumber(settings_tbl.hourglass_last_save_timestamp) or 0
    settings_tbl.packet_ruspix_time = tonumber(settings_tbl.packet_ruspix_time) or 0
    settings_tbl.ruspix_accumulated_time = tonumber(settings_tbl.ruspix_accumulated_time) or 0
    settings_tbl.ruspix_last_save_timestamp = tonumber(settings_tbl.ruspix_last_save_timestamp) or 0

    -- Ensure key_items exist and have numeric keys
    if not settings_tbl.key_items then
        settings_tbl.key_items = {}
        for id, _ in pairs(DEFAULTS.key_items) do
            settings_tbl.key_items[id] = false
        end
    end
    
    -- Only create timestamps for items that actually have cooldowns
    if not settings_tbl.timestamps then
        settings_tbl.timestamps = {}
        -- Only add timestamps for items with cooldowns (not Moglophone II variants)
        for id, _ in pairs(DEFAULTS.timestamps) do
            settings_tbl.timestamps[id] = 0
        end
    end

    if debug_print then
        debug_print('Loaded state successfully')
        debug_print('Key items loaded:')
        for id, owned in pairs(settings_tbl.key_items) do
            debug_print('  [' .. tostring(id) .. '] = ' .. tostring(owned))
        end
    end

    return settings_tbl
end

-- Public API: save
function persistence.save_state(state, debug_print)
    if not state or type(state) ~= 'table' then
        return false
    end



    -- Get the cached settings table from the library
    local cached = settingslib.get(SETTINGS_ALIAS)
    if not cached then
        cached = settingslib.load(DEFAULTS, SETTINGS_ALIAS)
    end

    -- Update the cached table with our state
    cached.key_items = cached.key_items or T{}
    for k in pairs(cached.key_items) do cached.key_items[k] = nil end
    for id, owned in pairs(state.key_items or {}) do
        cached.key_items[tonumber(id)] = owned == true
    end

    cached.timestamps = cached.timestamps or T{}
    for k in pairs(cached.timestamps) do cached.timestamps[k] = nil end
    for id, ts in pairs(state.timestamps or {}) do
        cached.timestamps[tonumber(id)] = tonumber(ts) or 0
    end

    cached.storage_canteens = tonumber(state.storage_canteens) or 0
    cached.last_canteen_time = tonumber(state.last_canteen_time) or 0
    cached.dynamis_d_entry_time = tonumber(state.dynamis_d_entry_time) or 0
    cached.dynamis_projected_ready_time = tonumber(state.dynamis_projected_ready_time) or 0
    cached.hourglass_time = tonumber(state.hourglass_time) or 0
    cached.hourglass_packet_timestamp = tonumber(state.hourglass_packet_timestamp) or 0
    cached.hourglass_accumulated_time = tonumber(state.hourglass_accumulated_time) or 0
    cached.hourglass_last_save_timestamp = tonumber(state.hourglass_last_save_timestamp) or 0
    cached.packet_ruspix_time = tonumber(state.packet_ruspix_time) or 0
    cached.ruspix_accumulated_time = tonumber(state.ruspix_accumulated_time) or 0
    cached.ruspix_last_save_timestamp = tonumber(state.ruspix_last_save_timestamp) or 0

    -- Save via settings library
    local ok = settingslib.save(SETTINGS_ALIAS)
    if ok then
        return true
    else
        return false
    end
end

-- Public API: clear all data
function persistence.clear_all_data(debug_print)
    if debug_print then debug_print('Clearing all persistence data...') end
    
    -- Load fresh defaults
    local cached = settingslib.load(DEFAULTS, SETTINGS_ALIAS)
    
    -- Save the defaults (this will overwrite any existing data)
    local ok = settingslib.save(SETTINGS_ALIAS)
    if ok then
        if debug_print then debug_print('Successfully cleared all data') end
        return true
    else
        if debug_print then debug_print('Failed to clear data') end
        return false
    end
end

-- Public API: get settings file path (for debugging)
function persistence.get_settings_path(debug_print)
    local path = settingslib.settings_path()
    local file_path = path .. '\\' .. SETTINGS_ALIAS .. '.lua'
    if debug_print then debug_print('Settings file path: ' .. file_path) end
    return file_path
end

-- Public API: save generic data
function persistence.save_data(key, data)
    if not key or not data then
        return false
    end
    
    -- Get the cached settings table from the library
    local cached = settingslib.get(SETTINGS_ALIAS)
    if not cached then
        cached = settingslib.load(DEFAULTS, SETTINGS_ALIAS)
    end
    
    -- Store the data
    cached[key] = data
    
    -- Save via settings library
    local ok = settingslib.save(SETTINGS_ALIAS)
    return ok
end

-- Public API: load generic data
function persistence.load_data(key)
    if not key then
        return nil
    end
    
    -- Get the cached settings table from the library
    local cached = settingslib.get(SETTINGS_ALIAS)
    if not cached then
        cached = settingslib.load(DEFAULTS, SETTINGS_ALIAS)
    end
    
    -- Return the data
    return cached[key]
end

return persistence