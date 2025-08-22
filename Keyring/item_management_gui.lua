-- Item Management GUI
-- Separate GUI for managing tracked key items

local imgui = require('imgui')
local trackedData = require('tracked_key_items')

-- GUI state
local showItemManagementGui = { false }

-- Item Management GUI state
local item_management_state = {
    show_add_item = false,
    show_edit_item = false,
    show_search = false,
    search_query = "",
    search_results = {},
    selected_item = nil,
    new_item = { id = "", name = "", cooldown = "0" },
    edit_item = { id = "", name = "", cooldown = "0" },
    message = "",
    message_timer = 0
}

-- GUI functions
local gui = {}

function gui.toggle()
    showItemManagementGui[1] = not showItemManagementGui[1]
end

function gui.is_visible()
    return showItemManagementGui[1]
end

function gui.set_visible(visible)
    showItemManagementGui[1] = visible
end

function gui.show_add_item_dialog()
    showItemManagementGui[1] = true
    item_management_state.show_add_item = true
    item_management_state.show_edit_item = false
    item_management_state.show_search = false
    item_management_state.new_item = { id = "", name = "", cooldown = "0" }
    item_management_state.message = ""
end

-- Helper function to render Add Item dialog
local function render_add_item_dialog()
    imgui.Spacing()
    imgui.Separator()
    imgui.TextColored({0, 1, 1, 1}, "➕ Add New Item")
    imgui.Separator()
    imgui.Spacing()
    
    -- Item ID input
    imgui.TextColored({0.8, 0.8, 0.8, 1}, "🔢 Item ID:")
    imgui.SameLine()
    imgui.PushItemWidth(150)
    local changed, value = imgui.InputText("##item_id", {item_management_state.new_item.id}, 10)
    imgui.PopItemWidth()
    if value and type(value) == "table" and value[1] then
        item_management_state.new_item.id = value[1]
    end
    
    -- Item Name input
    imgui.TextColored({0.8, 0.8, 0.8, 1}, "📝 Item Name:")
    imgui.SameLine()
    imgui.PushItemWidth(250)
    local changed, value = imgui.InputText("##item_name", {item_management_state.new_item.name}, 50)
    imgui.PopItemWidth()
    if value and type(value) == "table" and value[1] then
        item_management_state.new_item.name = value[1]
    end
    
    -- Cooldown input
    imgui.TextColored({0.8, 0.8, 0.8, 1}, "⏱️ Cooldown (seconds):")
    imgui.SameLine()
    imgui.PushItemWidth(150)
    local changed, value = imgui.InputText("##item_cooldown", {item_management_state.new_item.cooldown}, 10)
    imgui.PopItemWidth()
    if value and type(value) == "table" and value[1] then
        item_management_state.new_item.cooldown = value[1]
    end
    
    imgui.Spacing()
    
    -- Add button
    if imgui.Button("✅ Add Item", {100, 25}) then
        local id = tonumber(item_management_state.new_item.id)
        local cooldown = tonumber(item_management_state.new_item.cooldown)
        
        if id and cooldown then
            local success, message = pcall(function()
                if trackedData and trackedData.add_item then
                    return trackedData.add_item(id, item_management_state.new_item.name, cooldown)
                else
                    return false, "Item management not available"
                end
            end)
            
            if success then
                if message then -- message is actually success flag here
                    item_management_state.message = "Item added successfully"
                    item_management_state.show_add_item = false
                    item_management_state.new_item = { id = "", name = "", cooldown = "0" }
                else
                    item_management_state.message = "Failed to add item"
                end
            else
                item_management_state.message = "Error: " .. tostring(message)
            end
        else
            item_management_state.message = "Invalid ID or cooldown value"
        end
    end
    
    imgui.SameLine()
    
    -- Cancel button
    if imgui.Button("❌ Cancel", {100, 25}) then
        item_management_state.show_add_item = false
        item_management_state.new_item = { id = "", name = "", cooldown = "0" }
    end
end

-- Helper function to render Search dialog
local function render_search_dialog()
    imgui.Spacing()
    imgui.Separator()
    imgui.TextColored({0, 1, 1, 1}, "🔍 Search Items")
    imgui.Separator()
    imgui.Spacing()
    
    -- Search input
    imgui.TextColored({0.8, 0.8, 0.8, 1}, "🔍 Search (name or ID):")
    imgui.SameLine()
    imgui.PushItemWidth(300)
    local changed, value = imgui.InputText("##search_query", {item_management_state.search_query}, 50)
    imgui.PopItemWidth()
    if value and type(value) == "table" and value[1] then
        item_management_state.search_query = value[1]
        -- Update search results
        local success, results = pcall(function()
            if trackedData and trackedData.search_items then
                return trackedData.search_items(value[1])
            else
                return {}
            end
        end)
        
        if success then
            item_management_state.search_results = results
        else
            item_management_state.search_results = {}
        end
    end
    
    imgui.Spacing()
    
    -- Search results
    if #item_management_state.search_results > 0 then
        imgui.TextColored({0.8, 0.8, 0.8, 1}, "📋 Results (click to add):")
        imgui.BeginChild("##search_results", {700, 200}, true)
        
        for i, result in ipairs(item_management_state.search_results) do
            local display_text = string.format("%s (ID: %d)", result.name, result.id)
            if imgui.Selectable(display_text, false) then
                -- Auto-fill the add item form
                item_management_state.show_add_item = true
                item_management_state.show_search = false
                item_management_state.new_item = { 
                    id = tostring(result.id), 
                    name = result.name, 
                    cooldown = "0" 
                }
            end
        end
        
        imgui.EndChild()
    end
    
    imgui.Spacing()
    
    -- Close button
    if imgui.Button("🔒 Close", {100, 25}) then
        item_management_state.show_search = false
        item_management_state.search_query = ""
        item_management_state.search_results = {}
    end
end

-- Helper function to render Manage Items dialog
local function render_manage_items_dialog()
    imgui.Spacing()
    imgui.Separator()
    imgui.TextColored({0, 1, 1, 1}, "⚙️ Manage Tracked Items")
    imgui.Separator()
    imgui.Spacing()
    
    local items = {}
    local success, result = pcall(function()
        if trackedData and trackedData.get_items then
            return trackedData.get_items()
        else
            return {}
        end
    end)
    
    if success then
        items = result
    end
    
    if #items > 0 then
        imgui.BeginChild("##tracked_items", {600, 250}, true)
        
        -- Use columns for a simple table layout
        imgui.Columns(2, "##items_table")
        imgui.SetColumnWidth(0, 500)  -- Most space for item text
        imgui.SetColumnWidth(1, 100)  -- Space for remove button
        
        for i, item in ipairs(items) do
            -- Create display text
            local display_text = string.format("%s (ID: %d, Cooldown: %d)", item.name, item.id, item.cooldown)
            
            -- Item text in first column
            if imgui.Selectable(display_text, item_management_state.selected_item == item.id) then
                item_management_state.selected_item = item.id
                item_management_state.edit_item = { 
                    id = tostring(item.id), 
                    name = item.name, 
                    cooldown = tostring(item.cooldown) 
                }
            end
            
            -- Move to next column for remove button
            imgui.NextColumn()
            imgui.PushID("remove_" .. item.id)
            if imgui.Button("Remove", {80, 20}) then
                local success, message = pcall(function()
                    if trackedData and trackedData.remove_item then
                        return trackedData.remove_item(item.id)
                    else
                        return false, "Item management not available"
                    end
                end)
                
                if success then
                    if message then -- message is actually success flag here
                        item_management_state.message = "Item removed successfully"
                        item_management_state.selected_item = nil
                        item_management_state.edit_item = { id = "", name = "", cooldown = "0" }
                    else
                        item_management_state.message = "Failed to remove item"
                    end
                else
                    item_management_state.message = "Error: " .. tostring(message)
                end
            end
            imgui.PopID()
            
            -- Move to next row
            imgui.NextColumn()
        end
        
        -- Reset columns
        imgui.Columns(1)
        
        imgui.EndChild()
        
        -- Edit selected item
        if item_management_state.selected_item then
            imgui.Spacing()
            imgui.Separator()
            imgui.TextColored({0.8, 0.8, 0.8, 1}, "✏️ Edit Item:")
            imgui.Separator()
            imgui.Spacing()
            
            -- Item Name input
            imgui.TextColored({0.8, 0.8, 0.8, 1}, "📝 Name:")
            imgui.SameLine()
            imgui.PushItemWidth(250)
            local changed, value = imgui.InputText("##edit_name", {item_management_state.edit_item.name}, 50)
            imgui.PopItemWidth()
            if value and type(value) == "table" and value[1] then
                item_management_state.edit_item.name = value[1]
            end
            
            -- Cooldown input
            imgui.TextColored({0.8, 0.8, 0.8, 1}, "⏱️ Cooldown (seconds):")
            imgui.SameLine()
            imgui.PushItemWidth(150)
            local changed, value = imgui.InputText("##edit_cooldown", {item_management_state.edit_item.cooldown}, 10)
            imgui.PopItemWidth()
            if value and type(value) == "table" and value[1] then
                item_management_state.edit_item.cooldown = value[1]
            end
            
            imgui.Spacing()
            
            -- Update button
            if imgui.Button("💾 Update", {100, 25}) then
                local cooldown = tonumber(item_management_state.edit_item.cooldown)
                
                if cooldown then
                    local success, message = pcall(function()
                        if trackedData and trackedData.edit_item then
                            return trackedData.edit_item(item_management_state.selected_item, item_management_state.edit_item.name, cooldown)
                        else
                            return false, "Item management not available"
                        end
                    end)
                    
                    if success then
                        if message then -- message is actually success flag here
                            item_management_state.message = "Item updated successfully"
                        else
                            item_management_state.message = "Failed to update item"
                        end
                    else
                        item_management_state.message = "Error: " .. tostring(message)
                    end
                else
                    item_management_state.message = "Invalid cooldown value"
                end
            end
        end
    else
        imgui.Text("No tracked items found.")
    end
    
    imgui.Spacing()
    
    -- Close button
    if imgui.Button("🔒 Close", {100, 25}) then
        item_management_state.show_edit_item = false
        item_management_state.selected_item = nil
        item_management_state.edit_item = { id = "", name = "", cooldown = "0" }
    end
end

-- Main render function
function gui.render()
    if not showItemManagementGui[1] then return end

    -- Set window size and position
    imgui.SetNextWindowSize({650, 500})
    imgui.SetNextWindowPos({100, 100})

    if not imgui.Begin('Item Management', showItemManagementGui) then
        imgui.End()
        return
    end

    local total_width = imgui.GetWindowContentRegionWidth()
    
    -- Section header
    imgui.TextColored({1, 1, 0, 1}, "📦 Item Management")
    imgui.Separator()
    imgui.Spacing()
    
    -- Calculate button widths for better spacing
    local button_width = 120
    local button_height = 25
    local small_button_width = (total_width - 20) / 2
    
    -- Main action buttons
    if not item_management_state.show_add_item and not item_management_state.show_search and not item_management_state.show_edit_item then
        -- Add Item button
        if imgui.Button("➕ Add Item", {button_width, button_height}) then
            item_management_state.show_add_item = true
            item_management_state.show_edit_item = false
            item_management_state.show_search = false
            item_management_state.new_item = { id = "", name = "", cooldown = "0" }
            item_management_state.message = ""
        end
        
        imgui.SameLine()
        
        -- Search Items button
        if imgui.Button("🔍 Search", {button_width, button_height}) then
            item_management_state.show_search = true
            item_management_state.show_add_item = false
            item_management_state.show_edit_item = false
            item_management_state.search_query = ""
            item_management_state.search_results = {}
            item_management_state.message = ""
        end
        
        imgui.Spacing()
        imgui.Spacing()
        
        -- Manage Items button
        if imgui.Button("⚙️ Manage", {button_width, button_height}) then
            item_management_state.show_edit_item = true
            item_management_state.show_add_item = false
            item_management_state.show_search = false
            item_management_state.message = ""
        end
    end
    
    -- Show message if any
    if item_management_state.message ~= "" then
        imgui.Spacing()
        imgui.Separator()
        
        local color = {1, 1, 0, 1} -- Yellow for info
        local icon = "(i)"
        
        -- Ensure message is a string before calling find
        local message_str = tostring(item_management_state.message)
        if message_str:find("successfully") then
            color = {0, 1, 0, 1} -- Green for success
            icon = "✅"
        elseif message_str:find("Invalid") or message_str:find("not found") or message_str:find("Error") then
            color = {1, 0, 0, 1} -- Red for error
            icon = "❌"
        end
        
        imgui.TextColored(color, icon .. " " .. item_management_state.message)
        
        -- Auto-clear message after 3 seconds
        item_management_state.message_timer = item_management_state.message_timer + imgui.GetIO().DeltaTime
        if item_management_state.message_timer > 3.0 then
            item_management_state.message = ""
            item_management_state.message_timer = 0
        end
        
        imgui.Separator()
    end
    
    -- Add Item Dialog
    if item_management_state.show_add_item then
        render_add_item_dialog()
    end
    
    -- Search Items Dialog
    if item_management_state.show_search then
        render_search_dialog()
    end
    
    -- Manage Items Dialog
    if item_management_state.show_edit_item then
        render_manage_items_dialog()
    end
    
    imgui.End()
end

return gui
