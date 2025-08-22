-- Tracked Key Items Configuration
-- Contains both cooldown data and name mappings for tracked items

-- Tracked Key Items Configuration
-- Contains both cooldown data and name mappings for tracked items

-- Note: Persistence functions will be injected by the main addon to avoid circular dependencies
local persistence_functions = nil

-- Function to set persistence functions (called by main addon)
local function set_persistence_functions(save_func, load_func)
    persistence_functions = {
        save = save_func,
        load = load_func
    }
end

local trackedKeyItems = {
    -- Items with cooldowns
    [3212] = { cooldown = 72000, name = "Moglophone" },  -- 20 hour cooldown
    [3137] = { cooldown = 0, name = "Mystical Canteen" }, -- storage-based generation (no individual cooldown)
    [3300] = { cooldown = 72000, name = "shiny Ra'Kaznarian plate" }, -- 20 hour cooldown
    
    -- Items without cooldowns 
    [3052] = { cooldown = 0, name = "Ambuscade Primer Vol. 1" },
    [3053] = { cooldown = 0, name = "Ambuscade Primer Vol. 2" },
    -- Add more items without cooldowns here as needed
}

-- Create optimized mappings for backward compatibility
local key_items = {
    nameToId = {},
    idToName = {}
}

-- Build the optimized mappings from tracked items
local function rebuild_mappings()
    key_items.nameToId = {}
    key_items.idToName = {}
    
    for id, data in pairs(trackedKeyItems) do
        key_items.idToName[id] = data.name
        key_items.nameToId[data.name] = id
    end
end

-- Load tracked items from file
local function load_tracked_items()
    if not persistence_functions or not persistence_functions.load then
        return false
    end
    
    local success, data = pcall(function()
        return persistence_functions.load('tracked_items')
    end)
    
    if success and data then
        -- Validate the loaded data
        local valid = true
        for id, item_data in pairs(data) do
            if type(id) ~= 'number' or type(item_data) ~= 'table' or 
               type(item_data.name) ~= 'string' or type(item_data.cooldown) ~= 'number' then
                valid = false
                break
            end
        end
        
        if valid then
            trackedKeyItems = data
            rebuild_mappings()
            return true
        end
    end
    
    return false
end

-- Save tracked items to file
local function save_tracked_items()
    if not persistence_functions or not persistence_functions.save then
        return false
    end
    
    local success = pcall(function()
        persistence_functions.save('tracked_items', trackedKeyItems)
    end)
    return success
end

-- Initialize mappings and load data
rebuild_mappings()
load_tracked_items()

-- Management functions
local function add_tracked_item(id, name, cooldown)
    if type(id) ~= 'number' or id <= 0 then
        return false, "Invalid item ID"
    end
    
    if type(name) ~= 'string' or name == "" then
        return false, "Invalid item name"
    end
    
    if type(cooldown) ~= 'number' or cooldown < 0 then
        return false, "Invalid cooldown value"
    end
    
    -- Check if item already exists
    if trackedKeyItems[id] then
        return false, "Item ID already exists"
    end
    
    if key_items.nameToId[name] then
        return false, "Item name already exists"
    end
    
    -- Add the item
    trackedKeyItems[id] = { cooldown = cooldown, name = name }
    rebuild_mappings()
    
    -- Save to file
    if save_tracked_items() then
        return true, "Item added successfully"
    else
        return false, "Item added but failed to save to file"
    end
end

local function remove_tracked_item(id)
    if not trackedKeyItems[id] then
        return false, "Item not found"
    end
    
    trackedKeyItems[id] = nil
    rebuild_mappings()
    
    -- Save to file
    if save_tracked_items() then
        return true, "Item removed successfully"
    else
        return false, "Item removed but failed to save to file"
    end
end

local function edit_tracked_item(id, name, cooldown)
    if not trackedKeyItems[id] then
        return false, "Item not found"
    end
    
    if type(name) ~= 'string' or name == "" then
        return false, "Invalid item name"
    end
    
    if type(cooldown) ~= 'number' or cooldown < 0 then
        return false, "Invalid cooldown value"
    end
    
    -- Check if name conflicts with other items
    local existing_id = key_items.nameToId[name]
    if existing_id and existing_id ~= id then
        return false, "Item name already exists"
    end
    
    -- Update the item
    trackedKeyItems[id] = { cooldown = cooldown, name = name }
    rebuild_mappings()
    
    -- Save to file
    if save_tracked_items() then
        return true, "Item updated successfully"
    else
        return false, "Item updated but failed to save to file"
    end
end

local function get_tracked_items()
    local items = {}
    for id, data in pairs(trackedKeyItems) do
        table.insert(items, {
            id = id,
            name = data.name,
            cooldown = data.cooldown
        })
    end
    
    -- Sort by name for consistent display
    table.sort(items, function(a, b) return a.name < b.name end)
    return items
end

local function search_items(query)
    if not query or query == "" then
        return {}
    end
    
    query = query:lower()
    local results = {}
    
    -- Try to load the reference file for search
    local success, ref_data = pcall(require, 'key_items_reference')
    if success and ref_data and ref_data.nameToId then
        for name, id in pairs(ref_data.nameToId) do
            if name:lower():find(query, 1, true) or tostring(id):find(query, 1, true) then
                table.insert(results, { id = id, name = name })
            end
        end
    end
    
    -- Sort by name and limit results
    table.sort(results, function(a, b) return a.name < b.name end)
    return results
end

-- Fallback function for unknown items
function key_items.get_name(id)
    return key_items.idToName[id] or ("Unknown ID: " .. tostring(id))
end

function key_items.get_id(name)
    return key_items.nameToId[name]
end

-- Get item name from tracked items
local function get_item_name(id)
    if trackedKeyItems[id] then
        return trackedKeyItems[id].name
    end
    return nil
end

-- Return both the original tracked items and the optimized mappings
return {
    tracked = trackedKeyItems,
    key_items = key_items,
    -- Management functions
    add_item = add_tracked_item,
    remove_item = remove_tracked_item,
    edit_item = edit_tracked_item,
    get_items = get_tracked_items,
    get_item_name = get_item_name,
    search_items = search_items,
    rebuild_mappings = rebuild_mappings,
    save_items = save_tracked_items,
    load_items = load_tracked_items,
    set_persistence_functions = set_persistence_functions
}