-- ============================================================================
-- KEYRING PERSISTENCE MODULE
-- ============================================================================
-- Handles all data persistence for the Keyring addon
-- Uses Ashita's settings library for reliable data storage across sessions
-- Manages key item ownership, cooldown timestamps, and system state
-- ============================================================================

require('common')
local chat = require('chat')
local settingslib = require('settings')

local persistence = {}

-- ============================================================================
-- CONFIGURATION CONSTANTS
-- ============================================================================
local SETTINGS_ALIAS = 'settings'

-- ============================================================================
-- DEFAULT STATE VALUES
-- ============================================================================
-- Default values for all persistent data fields
-- These ensure data integrity and provide fallback values for missing data
local DEFAULTS = {
    dynamis_d_entry_time = 0,           -- Timestamp of last Dynamis [D] entry
    dynamis_projected_ready_time = 0,   -- Projected time when Dynamis [D] will be ready
    hourglass_packet_timestamp = 0,     -- Timestamp when hourglass packet was received
    hourglass_time = -1,                -- -1 represents "Unknown" until packet value is received
    key_items = {},                     -- Table of key item ownership status
    packet_ruspix_time = 0,             -- Ruspix Plate timer from packet data
    storage_canteens = 0,               -- Count of canteens in storage
    timestamps = {},                    -- Table of item acquisition timestamps
}

-- ============================================================================
-- PUBLIC API FUNCTIONS
-- ============================================================================
-- Load persistent state from Ashita settings library
-- Validates and converts all data to proper types for safe usage
function persistence.load_state(debug_print)
    if debug_print then debug_print('Loading settings via Ashita settings library') end
    
    local settings_tbl = settingslib.load(DEFAULTS, SETTINGS_ALIAS)

    -- ============================================================================
    -- DATA VALIDATION AND TYPE CONVERSION
    -- ============================================================================
    -- Ensure all numeric fields are properly converted and have fallback values
    settings_tbl.dynamis_d_entry_time = tonumber(settings_tbl.dynamis_d_entry_time) or 0
    settings_tbl.dynamis_projected_ready_time = tonumber(settings_tbl.dynamis_projected_ready_time) or 0
    settings_tbl.hourglass_packet_timestamp = tonumber(settings_tbl.hourglass_packet_timestamp) or 0
    settings_tbl.hourglass_time = tonumber(settings_tbl.hourglass_time) or -1
    settings_tbl.packet_ruspix_time = tonumber(settings_tbl.packet_ruspix_time) or 0
    settings_tbl.storage_canteens = tonumber(settings_tbl.storage_canteens) or 0

    -- ============================================================================
    -- TABLE STRUCTURE VALIDATION
    -- ============================================================================
    -- Ensure key_items table exists and has proper structure
    if not settings_tbl.key_items then
        settings_tbl.key_items = {}
        for id, _ in pairs(DEFAULTS.key_items) do
            settings_tbl.key_items[id] = false
        end
    end
    
    -- Ensure timestamps table exists and has proper structure
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

-- Save persistent state to Ashita settings library
-- Updates cached settings and writes to disk
function persistence.save_state(state, debug_print)
    if not state or type(state) ~= 'table' then
        return false
    end



    -- Get the cached settings table from the library
    local cached = settingslib.get(SETTINGS_ALIAS)
    if not cached then
        cached = settingslib.load(DEFAULTS, SETTINGS_ALIAS)
    end

    -- Update the cached table with our state (in alphabetical order)
    cached.dynamis_d_entry_time = tonumber(state.dynamis_d_entry_time) or 0
    cached.dynamis_projected_ready_time = tonumber(state.dynamis_projected_ready_time) or 0
    cached.hourglass_packet_timestamp = tonumber(state.hourglass_packet_timestamp) or 0
    cached.hourglass_time = tonumber(state.hourglass_time) or -1
    cached.key_items = cached.key_items or T{}
    for k in pairs(cached.key_items) do cached.key_items[k] = nil end
    for id, owned in pairs(state.key_items or {}) do
        cached.key_items[tonumber(id)] = owned == true
    end
    cached.packet_ruspix_time = tonumber(state.packet_ruspix_time) or 0
    cached.storage_canteens = tonumber(state.storage_canteens) or 0
    cached.timestamps = cached.timestamps or T{}
    for k in pairs(cached.timestamps) do cached.timestamps[k] = nil end
    for id, ts in pairs(state.timestamps or {}) do
        cached.timestamps[tonumber(id)] = tonumber(ts) or 0
    end

    -- Save via settings library
    local ok = settingslib.save(SETTINGS_ALIAS)
    if ok then
        return true
    else
        return false
    end
end

-- Clear all persistence data and reset to default values
-- Use this for troubleshooting or complete reset scenarios
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

-- Get the full path to the settings file for debugging purposes
-- Returns the absolute path where persistence data is stored
function persistence.get_settings_path(debug_print)
    local path = settingslib.settings_path()
    local file_path = path .. '\\' .. SETTINGS_ALIAS .. '.lua'
    if debug_print then debug_print('Settings file path: ' .. file_path) end
    return file_path
end

-- Save generic key-value data to the persistence system
-- Useful for storing additional addon data beyond the main state
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

-- Load generic key-value data from the persistence system
-- Returns the stored value or nil if not found
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