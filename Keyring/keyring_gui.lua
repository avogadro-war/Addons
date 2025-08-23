-- Keyring GUI Module
-- Handles all ImGui rendering logic for the keyring addon

local imgui = require('imgui')
local chat = require('chat')
local trackedData = require('tracked_key_items')
local key_items = trackedData.key_items
local trackedKeyItems = trackedData.tracked

local gui = {}

-- GUI state
local showGui = { false }

-- Dynamic window sizing constants
local HEADER_HEIGHT = 30
local ITEM_HEIGHT = 22
local SPACING_HEIGHT = 2
local PADDING = 35
local MIN_HEIGHT = 100
local MIN_WIDTH = 450
local MAX_WIDTH = 1200
local BASE_WIDTH = 400

-- Object pool for color tables to reduce garbage collection
local color_pool = {
    red = {1, 0.2, 0.2, 1},
    green = {0, 1, 0, 1},
    gray = {0.7, 0.7, 0.7, 1},
    white = {1, 1, 1, 1},
    bright_green = {0.2, 1, 0.2, 1},
    soft_gray = {0.6, 0.6, 0.6, 1}
}

-- Reusable table for calculations to avoid creating new tables
local calc_buffer = {}

function gui.is_visible()
    return showGui[1]
end

function gui.toggle()
    showGui[1] = not showGui[1]
    return showGui[1]
end

function gui.set_visible(visible)
    showGui[1] = visible
end

-- Cache for window dimensions to prevent unnecessary recalculations
local window_dimension_cache = {}
local last_dimension_update = 0
local DIMENSION_CACHE_DURATION = 1.0 -- Cache dimensions for 1 second

-- Calculate dynamic window dimensions based on content
local function calculate_window_dimensions(keyItemStatuses, trackedKeyItems)
    local current_time = os.clock()
    
    -- Check cache first
    if window_dimension_cache.result and (current_time - last_dimension_update) < DIMENSION_CACHE_DURATION then
        return window_dimension_cache.result.width, window_dimension_cache.result.height
    end
    
    local itemCount = #keyItemStatuses
    if itemCount == 0 then
        -- If no status data, count items from trackedKeyItems
        itemCount = 0
        for _ in pairs(trackedKeyItems) do
            itemCount = itemCount + 1
        end
    end
    
    -- Calculate height for key items section
    local spacingCount = math.max(0, itemCount - 1)
    local keyItemsHeight = HEADER_HEIGHT + (itemCount * ITEM_HEIGHT) + (spacingCount * SPACING_HEIGHT)
    
    -- Calculate height for Dynamis [D] section (reduced padding)
    local dynamisHeaderHeight = 20      -- "Dynamis [D] Entry Cooldown" text
    local dynamisStatusHeight = 18      -- Status line
    local dynamisSpacing = 4            -- Reduced spacing between elements
    local dynamisSeparatorHeight = 8    -- Separator line
    local dynamisPadding = 8            -- Reduced padding for auto-scaling safety
    local dynamisBottomPadding = 5      -- Reduced padding below the row
    
    local dynamisSectionHeight = dynamisHeaderHeight + dynamisStatusHeight + 
                                dynamisSpacing + dynamisSeparatorHeight + 
                                dynamisPadding + dynamisBottomPadding
    
         -- Calculate height for Hourglass section (similar to Dynamis)
     local hourglassHeaderHeight = 20    -- "Empty Hourglass" text
     local hourglassStatusHeight = 18    -- Status line (single line for most cases)
     local hourglassSpacing = 4          -- Reduced spacing between elements
     local hourglassSeparatorHeight = 8  -- Separator line
     local hourglassPadding = 8          -- Reduced padding for auto-scaling safety
     local hourglassBottomPadding = 5    -- Reduced padding below the row
     
     local hourglassSectionHeight = hourglassHeaderHeight + hourglassStatusHeight + 
                                   hourglassSpacing + hourglassSeparatorHeight + 
                                   hourglassPadding + hourglassBottomPadding
    
    -- Calculate height for Ruspix Plate section (similar to Hourglass)
    local ruspixHeaderHeight = 16      -- "Ruspix Plate" text (further reduced)
    local ruspixStatusHeight = 14      -- Status line (further reduced)
    local ruspixSpacing = 0            -- No spacing between elements
    local ruspixSeparatorHeight = 4    -- Separator line (further reduced)
    local ruspixPadding = 0            -- No padding for auto-scaling safety
    local ruspixBottomPadding = 0      -- No padding below the row
    
    local ruspixSectionHeight = ruspixHeaderHeight + ruspixStatusHeight + 
                               ruspixSpacing + ruspixSeparatorHeight + 
                               ruspixPadding + ruspixBottomPadding
    
         -- Total height calculation with minimal padding (removed Item Management section)
     local totalContentHeight = keyItemsHeight + dynamisSectionHeight + hourglassSectionHeight + ruspixSectionHeight
     local requiredHeight = math.max(totalContentHeight + 1, MIN_HEIGHT)  -- Minimal padding of 1px
     
    -- Calculate width based on longest item name
    local maxNameLength = 0
    if #keyItemStatuses > 0 then
        for _, item in ipairs(keyItemStatuses) do
            if item.name and #item.name > maxNameLength then
                maxNameLength = #item.name
            end
        end
    else
        -- If no status data, check trackedKeyItems
        for id, _ in pairs(trackedKeyItems) do
            local name = key_items.idToName[id] or ('Unknown ID: ' .. tostring(id))
            if #name > maxNameLength then
                maxNameLength = #name
            end
        end
    end
    
         local dynamicWidth = math.min(math.max(BASE_WIDTH + (maxNameLength * 5), MIN_WIDTH), MAX_WIDTH)
     
    -- Cache the result
    window_dimension_cache.result = {width = dynamicWidth, height = requiredHeight}
    last_dimension_update = current_time
    
    return dynamicWidth, requiredHeight
end

-- Center text within current column
local function center_text(text)
    local col_start = imgui.GetColumnOffset()
    local col_width = imgui.GetColumnWidth()
    local text_width = imgui.CalcTextSize(text)
    local pos_x = col_start + (col_width - text_width) / 2
    imgui.SetCursorPosX(pos_x)
    imgui.Text(text)
end

-- Render column headers
local function render_headers(total_width)
    imgui.Columns(3, 'cooldownColumns', true)
    
         -- Responsive column widths with minimum sizes
     local minNameWidth = 180
     local minStatusWidth = 70
     local minTimeWidth = 140
     
     local nameWidth = math.max(total_width * 0.48, minNameWidth)
     local statusWidth = math.max(total_width * 0.15, minStatusWidth)
     local timeWidth = math.max(total_width * 0.37, minTimeWidth)
     
    imgui.SetColumnWidth(0, nameWidth)      -- Key Item
    imgui.SetColumnWidth(1, statusWidth)    -- Have?
    imgui.SetColumnWidth(2, timeWidth)      -- Time Remaining

    -- Headers
    center_text('Key Item')
    imgui.NextColumn()
    center_text('Have?')
    imgui.NextColumn()
    center_text('Time Remaining')
    imgui.NextColumn()
    imgui.Separator()
end

-- Time formatting cache to avoid repeated calculations
local time_format_cache = {}
local last_cache_cleanup = 0

-- Helper function to format time with caching
local function format_time_cached(seconds)
    if seconds <= 0 then return 'Ready.' end
    
    local cache_key = math.floor(seconds / 60) -- Cache by minute to reduce cache size
    local cached = time_format_cache[cache_key]
    if cached then
        return cached
    end
    
    local rh = math.floor(seconds / 3600)
    local rm = math.floor((seconds % 3600) / 60)
    local rs = seconds % 60
    local formatted = string.format('%02dh:%02dm:%02ds', rh, rm, rs)
    
    -- Clean cache every 5 minutes to prevent memory bloat
    local current_time = os.time()
    if current_time - last_cache_cleanup > 300 then
        time_format_cache = {}
        last_cache_cleanup = current_time
    end
    
    time_format_cache[cache_key] = formatted
    return formatted
end

-- Render time remaining with special canteen handling
local function render_time_remaining(item, hasItem, storage_canteens, packet_tracker)
    local displayText
    local textColor = color_pool.red -- Use pooled color
    local show_canteen_count = (item.id == 3137)
    
    if show_canteen_count then
        -- Special handling for canteen - show generation time instead of cooldown
        if storage_canteens >= 3 then
            -- Storage is full - no more canteens will be generated
            textColor = {0.7, 0.7, 0.7, 1} -- gray
            displayText = 'Storage Full'
        else
            -- Check generation time
            local generationRemaining = packet_tracker.get_canteen_generation_remaining()
            if generationRemaining == nil then
                textColor = {0.7, 0.7, 0.7, 1} -- gray
                displayText = 'Unknown'
            elseif generationRemaining <= 0 then
                textColor = {0, 1, 0, 1} -- green
                displayText = 'Ready'
            else
                local rh = math.floor(generationRemaining / 3600)
                local rm = math.floor((generationRemaining % 3600) / 60)
                local rs = generationRemaining % 60
                displayText = string.format('%02dh:%02dm:%02ds', rh, rm, rs)
            end
        end
    else
        -- Regular key item cooldown logic
        local timestamp = item.timestamp or 0
        
        -- Check if this item has no cooldown (cooldown = 0)
        local cooldown = 0
        
        if item.group == "moglophone_ii" then
            -- Moglophone II variants have no cooldown
            cooldown = 0
        elseif trackedKeyItems[item.id] then
            -- Regular items - get cooldown from tracked items
            cooldown = trackedKeyItems[item.id].cooldown
        end
        
        if cooldown == 0 then
            -- Item has no cooldown - show dash in time column
            textColor = {0.7, 0.7, 0.7, 1} -- gray
            displayText = '-'
        elseif item.id == 3300 and hasItem and (timestamp == 0 or item.remaining == nil or item.remaining <= 0) then
            -- Special handling for Shiny Rakaznar Plate (ID 3300)
            -- Player has the plate and no cooldown - show dash since cooldown starts when used
            textColor = {0.7, 0.7, 0.7, 1} -- gray
            displayText = '-'
        elseif timestamp == 0 or item.remaining == nil then
            -- No timestamp recorded yet or no remaining time calculated
            textColor = {0.7, 0.7, 0.7, 1} -- gray
            displayText = 'Unknown'
        elseif item.remaining <= 0 then
            textColor = {0, 1, 0, 1} -- green
            displayText = 'Available'
        elseif item.remaining > 0 then
            local rh = math.floor(item.remaining / 3600)
            local rm = math.floor((item.remaining % 3600) / 60)
            local rs = item.remaining % 60
            displayText = string.format('%02dh:%02dm:%02ds', rh, rm, rs)
        else
            -- Fallback for any calculation issues
            textColor = {0.7, 0.7, 0.7, 1} -- gray
            displayText = 'Unknown'
        end
    end

    -- Calculate positioning for centered text
    local col_start = imgui.GetColumnOffset()
    local col_width = imgui.GetColumnWidth()
    
    if show_canteen_count then
        -- For canteen, render main text and count separately
        local mainTextWidth = imgui.CalcTextSize(displayText)
        local canteenText = string.format(' (%d/3)', storage_canteens)
        local canteenTextWidth = imgui.CalcTextSize(canteenText)
        local totalWidth = mainTextWidth + canteenTextWidth
        local pos_x = col_start + (col_width - totalWidth) / 2
        
        -- Render main status text
        imgui.SetCursorPosX(pos_x)
        imgui.TextColored(textColor, displayText)
        
        -- Render canteen count in white
        imgui.SameLine()
        imgui.TextColored({1, 1, 1, 1}, canteenText)
    else
        -- For non-canteen items, render normally
        local text_width = imgui.CalcTextSize(displayText)
        local pos_x = col_start + (col_width - text_width) / 2
        imgui.SetCursorPosX(pos_x)
        imgui.TextColored(textColor, displayText)
    end

    -- Tooltip
    if imgui.IsItemHovered() then
        imgui.BeginTooltip()
        if show_canteen_count then
            -- Canteen-specific tooltip
            if storage_canteens >= 3 then
                imgui.Text('Storage is full (3/3 canteens).')
                imgui.Text('Use a canteen to start generation timer.')
            else
                local generationRemaining = packet_tracker.get_canteen_generation_remaining()
                if generationRemaining == nil then
                    imgui.Text('Generation time unknown.')
                    imgui.Text('Waiting for canteen data.')
                elseif generationRemaining <= 0 then
                    imgui.Text('Next canteen is ready to generate.')
                else
                    imgui.Text('Time until next canteen generation.')
                end
            end
        else
            -- Regular key item tooltip
            local timestamp = item.timestamp or 0
            
            -- Check if this item has no cooldown
            local cooldown = trackedKeyItems[item.id] and trackedKeyItems[item.id].cooldown
            
            if cooldown == 0 then
                -- Item has no cooldown
                if hasItem then
                    imgui.Text('You own this item.')
                    imgui.Text('No cooldown - permanent acquisition.')
                else
                    imgui.Text('You do not own this item.')
                    imgui.Text('Acquire it to add to your collection.')
                end
            elseif timestamp == 0 or item.remaining == nil then
                imgui.Text('No acquisition time recorded yet.')
                imgui.Text('Acquire the item to start tracking.')
            elseif item.remaining <= 0 then
                imgui.Text('Available now.')
            elseif item.remaining > 0 then
                imgui.Text('Still on cooldown.')
            else
                imgui.Text('Time calculation error.')
                imgui.Text('Please reload the addon.')
            end
        end
        imgui.EndTooltip()
    end
end

-- Render a single key item row
local function render_key_item_row(item, hasItem, storage_canteens, packet_tracker)
    -- Key Item Name (left aligned)
    imgui.Text(item.name)
    imgui.NextColumn()

    -- Have? (centered, colored)
    local statusText, statusColor
    
    if item.group == "moglophone_ii" then
        -- For grouped Moglophone II, show count
        statusText = tostring(item.variant_count)
        if item.variant_count >= 3 then
            statusColor = {0, 1, 0, 1} -- Green when all 3 variants owned
        else
            statusColor = {1, 1, 0, 1} -- Yellow when less than 3 variants
        end
    else
        -- Regular items
        statusText = hasItem and 'Yes' or 'No'
        statusColor = hasItem and {0, 1, 0, 1} or {1, 0.2, 0.2, 1}
    end

    do
        local col_start = imgui.GetColumnOffset()
        local col_width = imgui.GetColumnWidth()
        local text_width = imgui.CalcTextSize(statusText)
        local pos_x = col_start + (col_width - text_width) / 2
        imgui.SetCursorPosX(pos_x)
        imgui.TextColored(statusColor, statusText)
    end
    imgui.NextColumn()

    -- Time Remaining
    render_time_remaining(item, hasItem, storage_canteens, packet_tracker)
    imgui.NextColumn()
    
    -- Add spacing between rows
    imgui.Spacing()
end

-- Render Dynamis [D] cooldown section
local function render_dynamis_d_section(packet_tracker, total_width)
    -- Add spacing for visual separation
    imgui.Spacing()
    imgui.Spacing()
    
         -- Set up 3 columns for Dynamis [D] section (no separator between columns)
     imgui.Columns(3, 'dynamisColumns', false)
     
     -- Fixed column widths for better layout
     local labelWidth = total_width * 0.35  -- Left column for labels (increased to prevent clipping)
     local statusWidth = total_width * 0.35  -- Center column for status
     local timeWidth = total_width * 0.30   -- Right column for time values
     
    imgui.SetColumnWidth(0, labelWidth)      -- Label (left justified)
    imgui.SetColumnWidth(1, statusWidth)     -- Status (centered)
    imgui.SetColumnWidth(2, timeWidth)       -- Time (right justified)
    
    -- Section header (left column) - left justified
    local headerText = 'Dynamis [D] Entry'
    imgui.Text(headerText)  -- Left justified
    imgui.NextColumn()
    
    -- Get cooldown status
    local remaining = packet_tracker.get_dynamis_d_cooldown_remaining()
    local entry_time = packet_tracker.get_dynamis_d_entry_time()
    
    -- Check Dynamis availability (no longer managing hourglass increment)
    local is_dynamis_available = (remaining == nil or remaining <= 0)
    
         -- Status display - centered across entire window
     if entry_time == 0 or entry_time == nil then
         -- No entry recorded
         local display_text = 'Unknown'
         local text_color = {0.6, 0.6, 0.6, 1} -- Softer gray
         
        -- Center the status text across the entire window
        local text_width = imgui.CalcTextSize(display_text)
        local pos_x = (total_width - text_width) / 2
        imgui.SetCursorPosX(pos_x)
         imgui.TextColored(text_color, display_text)
         
     elseif remaining and remaining > 0 then
         -- On cooldown - show status only (time goes in right column)
         local display_text = 'On cooldown.'
         local text_color = {1, 0.2, 0.2, 1} -- Red text
         
        -- Center the status text across the entire window
        local text_width = imgui.CalcTextSize(display_text)
        local pos_x = (total_width - text_width) / 2
        imgui.SetCursorPosX(pos_x)
         imgui.TextColored(text_color, display_text)
         
     else
         -- Available
         local display_text = 'Ready'
         local text_color = {0.2, 1, 0.2, 1} -- Brighter green
         
        -- Center the status text across the entire window
        local text_width = imgui.CalcTextSize(display_text)
        local pos_x = (total_width - text_width) / 2
        imgui.SetCursorPosX(pos_x)
         imgui.TextColored(text_color, display_text)
     end
     
     imgui.NextColumn()
     
     -- Time display (right column) - right justified
     if entry_time == 0 or entry_time == nil then
         -- No entry recorded - no time to display
         imgui.Text('')
     elseif remaining and remaining > 0 then
         -- On cooldown - show time remaining
         local hours = math.floor(remaining / 3600)
         local minutes = math.floor((remaining % 3600) / 60)
         local seconds = remaining % 60
                   local timeText = string.format('%02dh:%02dm:%02ds', hours, minutes, seconds)
         
         -- Right justify the time text
         local col_start = imgui.GetColumnOffset()
         local col_width = imgui.GetColumnWidth()
         local text_width = imgui.CalcTextSize(timeText)
         local pos_x = col_start + col_width - text_width
         imgui.SetCursorPosX(pos_x)
         imgui.TextColored({1, 1, 1, 1}, timeText)  -- White text
     else
         -- Available - no time to display
         imgui.Text('')
     end
    
    -- Enhanced tooltip with more detailed info
    if imgui.IsItemHovered() then
        imgui.BeginTooltip()
        imgui.PushStyleColor(0, {1, 0.8, 0, 1})  -- Text color
        imgui.Text('Dynamis [D] Entry System')
        imgui.PopStyleColor()
        imgui.Separator()
        imgui.Text('• 60-hour cooldown between entries')
        imgui.Text('• Automatically tracked on zone entry')
        imgui.Text('• Entry zones: Jeuno, Bastok, San d\'Oria, Windurst')
        if entry_time ~= 0 and entry_time ~= nil then
            local entryDate = os.date('%Y-%m-%d %H:%M', entry_time)
            imgui.Text('• Last entry: ' .. entryDate)
        end
        imgui.EndTooltip()
         end
     
     imgui.NextColumn()
     
           -- Minimal spacing at the bottom
      imgui.Spacing()
end

-- Render Hourglass cooldown section
local function render_hourglass_section(packet_tracker, total_width)
    -- Add spacing for visual separation
    imgui.Spacing()
    imgui.Spacing()
    
         -- Set up 3 columns for Hourglass section (no separator between columns)
     imgui.Columns(3, 'hourglassColumns', false)
     
     -- Fixed column widths for better layout
     local labelWidth = total_width * 0.35  -- Left column for labels (increased to prevent clipping)
     local statusWidth = total_width * 0.35  -- Center column for status
     local timeWidth = total_width * 0.30   -- Right column for time values
     
    imgui.SetColumnWidth(0, labelWidth)      -- Label (left justified)
    imgui.SetColumnWidth(1, statusWidth)     -- Status (centered)
    imgui.SetColumnWidth(2, timeWidth)       -- Time (right justified)
    
         -- Section header (left column) - left justified
     local headerText = 'Empty Hourglass'
     imgui.Text(headerText)  -- Left justified
     imgui.NextColumn()
     
     -- Add spacing to match Dynamis vertical alignment
     imgui.Spacing()
     imgui.Spacing()
    
    -- Get hourglass status
    local hourglass_remaining = packet_tracker.get_hourglass_time_remaining()
    local hourglass_time = packet_tracker.get_hourglass_time()
    local dynamis_remaining = packet_tracker.get_dynamis_d_cooldown_remaining()
    local is_dynamis_available = (dynamis_remaining == nil or dynamis_remaining <= 0)
    
                                                           -- Status display - centered across entire window
       if hourglass_time == 0 or hourglass_time == nil then
           -- No hourglass use recorded
           local display_text = 'Unknown'
           local text_color = {0.6, 0.6, 0.6, 1} -- Softer gray
           
           -- Center the status text across the entire window
           local text_width = imgui.CalcTextSize(display_text)
           local pos_x = (total_width - text_width) / 2
           imgui.SetCursorPosX(pos_x)
           imgui.TextColored(text_color, display_text)
          
      else
          -- Calculate if hourglass has enough time to bypass Dynamis cooldown
          local dynamis_remaining = dynamis_remaining or 0
          
          local display_text
          local text_color
          
          if hourglass_time >= dynamis_remaining then
              -- Case 1: Hourglass time >= remaining cooldown → "Ready" in green
              display_text = 'Ready'
              text_color = {0.2, 1, 0.2, 1} -- Green
          else
              -- Case 2: Hourglass time < remaining cooldown → "Not enough time" in red
              display_text = 'Not enough time'
              text_color = {1, 0.2, 0.2, 1} -- Red
          end
          
           -- Center the status text across the entire window
           local text_width = imgui.CalcTextSize(display_text)
           local pos_x = (total_width - text_width) / 2
          imgui.SetCursorPosX(pos_x)
          imgui.TextColored(text_color, display_text)
      end
     
     imgui.NextColumn()
     
     -- Time display (right column) - right justified
     if hourglass_time == 0 or hourglass_time == nil then
         -- No hourglass use recorded - no time to display
         imgui.Text('')
     else
                 -- Helper function to format seconds as hh"h":mm"m":ss"s"
        local function format_time_readable(seconds)
            local hours = math.floor(seconds / 3600)
            local minutes = math.floor((seconds % 3600) / 60)
            local secs = seconds % 60
            return string.format('%02dh:%02dm:%02ds', hours, minutes, secs)
        end
        
        local timeText = string.format('%s', format_time_readable(hourglass_time))
         
                   -- Add spacing to match vertical alignment first
          imgui.Spacing()
          imgui.Spacing()
          
          -- Right justify the time text
          local col_start = imgui.GetColumnOffset()
          local col_width = imgui.GetColumnWidth()
          local text_width = imgui.CalcTextSize(timeText)
          local pos_x = col_start + col_width - text_width
          imgui.SetCursorPosX(pos_x)
          
          imgui.TextColored({1, 1, 1, 1}, timeText)  -- White text
     end
    
    -- Enhanced tooltip with more detailed info
    if imgui.IsItemHovered() then
        imgui.BeginTooltip()
        imgui.PushStyleColor(0, {1, 1, 1, 1})  -- Text color (white)
        imgui.Text('Empty Hourglass System')
        imgui.Separator()
                 imgui.Text('• Shows the time value stored in the hourglass')
         imgui.Text('• Time is consumed when entering Dynamis [D] with cooldown')
         imgui.Text('• Time automatically increases by 1 second every 5 seconds')
         imgui.Text('• Accrual starts after Dynamis [D] entry time + 60 hours')
         imgui.Text('• Green "Ready": Enough time to bypass current Dynamis cooldown')
         imgui.Text('• Red "Not enough time": Not enough time to bypass current Dynamis cooldown')
         if hourglass_time ~= 0 and hourglass_time ~= nil then
             imgui.Text('• Time stored: ' .. hourglass_time .. ' seconds')
         end
         
         -- Show "Last checked" timestamp if available
         local packet_timestamp = packet_tracker.get_hourglass_packet_timestamp()
         if packet_timestamp and packet_timestamp > 0 then
             local last_checked_date = os.date('%Y-%m-%d %H:%M', packet_timestamp)
             imgui.Text('• Last checked: ' .. last_checked_date)
         end
         imgui.EndTooltip()
     end
     
     imgui.NextColumn()
     
     -- Minimal spacing at the bottom
     imgui.Spacing()
end

-- Ruspix Plate section renderer
local function render_ruspix_plate_section(packet_tracker, total_width)
    -- Set up 3 columns for Ruspix Plate section (no separator between columns)
    imgui.Columns(3, 'ruspixPlateColumns', false)
    
    -- Fixed column widths for better layout
    local labelWidth = total_width * 0.35  -- Left column for labels
    local statusWidth = total_width * 0.35  -- Center column for status
    local timeWidth = total_width * 0.30   -- Right column for time values
    
    imgui.SetColumnWidth(0, labelWidth)      -- Label (left justified)
    imgui.SetColumnWidth(1, statusWidth)     -- Status (centered)
    imgui.SetColumnWidth(2, timeWidth)       -- Time (right justified)
    
    -- Section header (left column) - left justified
    local headerText = 'Ruspix Plate'
    imgui.Text(headerText)  -- Left justified
    imgui.NextColumn()
    
    -- Add spacing to match other sections vertical alignment
    imgui.Spacing()
    imgui.Spacing()
    
    -- Get Ruspix Plate status
    local ruspix_time = packet_tracker and packet_tracker.get_ruspix_time and packet_tracker.get_ruspix_time() or 0
    local ruspix_accumulated = packet_tracker and packet_tracker.get_ruspix_accumulated_time and packet_tracker.get_ruspix_accumulated_time() or 0
    local packet_ruspix_time = packet_tracker and packet_tracker.get_ruspix_packet_time and packet_tracker.get_ruspix_packet_time() or 0
    
    -- Ensure values are numbers
    ruspix_time = tonumber(ruspix_time) or 0
    ruspix_accumulated = tonumber(ruspix_accumulated) or 0
    packet_ruspix_time = tonumber(packet_ruspix_time) or 0
    
    -- Debug output to help troubleshoot
               -- Debug output removed to prevent spam
    
    -- Status display - centered across entire window
    -- Check if we've ever received valid packet data for Ruspix Plate
    local has_received_packet_data = packet_ruspix_time > 0
    
    if not has_received_packet_data then
        -- No valid packet data received yet - show "Unknown"
        local display_text = 'Unknown'
        local text_color = {0.6, 0.6, 0.6, 1} -- Softer gray
        
        -- Center the status text across the entire window
        local text_width = imgui.CalcTextSize(display_text)
        local pos_x = (total_width - text_width) / 2
        imgui.SetCursorPosX(pos_x)
        imgui.TextColored(text_color, display_text)
    elseif ruspix_time == 0 or ruspix_time == nil then
        -- Packet data received but time is 0 - show "Ready" (since 0 means no cooldown)
        local display_text = 'Ready'
        local text_color = {0.2, 1, 0.2, 1} -- Green
        
        -- Center the status text across the entire window
        local text_width = imgui.CalcTextSize(display_text)
        local pos_x = (total_width - text_width) / 2
        imgui.SetCursorPosX(pos_x)
        imgui.TextColored(text_color, display_text)
    else
        -- Calculate if Ruspix Plate is ready (total time >= 72000)
        local display_text
        local text_color
        
        -- Get Shiny Rakaznarian Plate cooldown from tracked items
        local shiny_plate_cooldown = trackedKeyItems and trackedKeyItems[3300] and trackedKeyItems[3300].cooldown or 72000
        
        if ruspix_time >= shiny_plate_cooldown then
            -- Case 1: Total time >= Shiny Rakaznarian Plate cooldown → "Ready" in green
            display_text = 'Ready'
            text_color = {0.2, 1, 0.2, 1} -- Green
        else
            -- Case 2: Total time < Shiny Rakaznarian Plate cooldown → "On cooldown." in red
            display_text = 'On cooldown.'
            text_color = {1, 0.2, 0.2, 1} -- Red
        end
        
        -- Center the status text across the entire window
        local text_width = imgui.CalcTextSize(display_text)
        local pos_x = (total_width - text_width) / 2
        imgui.SetCursorPosX(pos_x)
        imgui.TextColored(text_color, display_text)
    end
    
    imgui.NextColumn()
    
    -- Time display (right column) - right justified
    if not has_received_packet_data then
        -- No valid packet data received yet - show "Unknown"
        imgui.Text('')
    elseif ruspix_time == 0 or ruspix_time == nil then
        -- Packet data received but time is 0 - show "0h:00m:00s"
        local timeText = '0h:00m:00s'
        
        -- Add spacing to match vertical alignment first
        imgui.Spacing()
        imgui.Spacing()
        
        -- Right justify the time text
        local col_start = imgui.GetColumnOffset()
        local col_width = imgui.GetColumnWidth()
        local text_width = imgui.CalcTextSize(timeText)
        local pos_x = col_start + col_width - text_width
        imgui.SetCursorPosX(pos_x)
        
        imgui.TextColored({1, 1, 1, 1}, timeText)  -- White text
    else
        -- Helper function to format seconds as hh"h":mm"m":ss"s"
        local function format_time_readable(seconds)
            local hours = math.floor(seconds / 3600)
            local minutes = math.floor((seconds % 3600) / 60)
            local secs = seconds % 60
            return string.format('%02dh:%02dm:%02ds', hours, minutes, secs)
        end
        
        local timeText = format_time_readable(ruspix_time)
        
        -- Add spacing to match vertical alignment first
        imgui.Spacing()
        imgui.Spacing()
        
        -- Right justify the time text
        local col_start = imgui.GetColumnOffset()
        local col_width = imgui.GetColumnWidth()
        local text_width = imgui.CalcTextSize(timeText)
        local pos_x = col_start + col_width - text_width
        imgui.SetCursorPosX(pos_x)
        
        imgui.TextColored({1, 1, 1, 1}, timeText)  -- White text
    end
    
    -- Enhanced tooltip with more detailed info
    if imgui.IsItemHovered() then
        imgui.BeginTooltip()
        imgui.PushStyleColor(0, {1, 1, 1, 1})  -- Text color (white)
        imgui.Text('Ruspix Plate System')
        imgui.Separator()
        imgui.Text('• Shows the time value for Ruspix Plate')
        imgui.Text('• Time is obtained from talking to Ruspix NPC')
        imgui.Text('• Time automatically increases by 1 second every 5 seconds')
        imgui.Text('• Accrual occurs when Shiny Rakaznarian Plate is off cooldown')
        imgui.Text('• Green "Ready": Total time >= 72000 seconds (20 hours)')
        imgui.Text('• Red "Time remaining": Not enough time to reach 72000 seconds')
        if ruspix_time ~= 0 and ruspix_time ~= nil then
            imgui.Text('• Total time: ' .. ruspix_time .. ' seconds')
            if packet_ruspix_time and packet_ruspix_time > 0 then
                imgui.Text('• Packet time: ' .. packet_ruspix_time .. ' seconds')
            end
            if ruspix_accumulated and ruspix_accumulated > 0 then
                imgui.Text('• Accumulated time: ' .. ruspix_accumulated .. ' seconds')
            end
        end
        
        imgui.EndTooltip()
    end
    
    imgui.NextColumn()
    
    -- Minimal spacing at the bottom
    imgui.Spacing()
end

-- Item Management functionality moved to separate GUI file

-- Main render function
function gui.render(keyItemStatuses, trackedKeyItems, storage_canteens, packet_tracker)
    if not showGui[1] then return end

    -- Calculate dynamic window dimensions (includes Dynamis [D] section)
    local width, height = calculate_window_dimensions(keyItemStatuses, trackedKeyItems)
    
    imgui.SetNextWindowSizeConstraints({width, height}, {width, height})

    if not imgui.Begin('Keyring', showGui) then
        imgui.End()
        return
    end

    local total_width = imgui.GetWindowContentRegionWidth()
    
    -- Render headers
    render_headers(total_width)

    -- Sort key item rows alphabetically by name
    local sortedItems = {}
    

    
    -- If we have status data, use it; otherwise create items from trackedKeyItems
    if #keyItemStatuses > 0 then
        for i, item in ipairs(keyItemStatuses) do
            table.insert(sortedItems, item)
        end
    else
        -- Create items from trackedKeyItems when no status data is available
        for id, data in pairs(trackedKeyItems) do
            local name = key_items.idToName[id] or ('Unknown ID: ' .. tostring(id))
            table.insert(sortedItems, {
                id = id,
                name = name,
                remaining = nil,
                timestamp = 0,
                owned = false,
            })
        end
    end
    
    table.sort(sortedItems, function(a, b) return a.name < b.name end)
    
    -- Render key item rows
    for i, item in ipairs(sortedItems) do
        local hasItem = item.owned
        
        -- For grouped items, we need to handle them specially
        if item.group == "moglophone_ii" then
            -- Grouped items are always considered "owned" if they have variants
            hasItem = item.variant_count > 0
        end
        
        render_key_item_row(item, hasItem, storage_canteens, packet_tracker)
    end

         imgui.Columns(1)
     
      -- Top separator for the unified section
      imgui.Separator()
      
      -- Render Dynamis [D] section
      render_dynamis_d_section(packet_tracker, total_width)
      
      -- Row separator between Dynamis and Hourglass
      imgui.Separator()
      
      -- Render Hourglass section
      render_hourglass_section(packet_tracker, total_width)
      
      -- Row separator between Hourglass and Ruspix Plate
      imgui.Separator()
      
      -- Add spacing before Ruspix Plate section
      imgui.Spacing()
      imgui.Spacing()

      -- Render Ruspix Plate section
      render_ruspix_plate_section(packet_tracker, total_width)
      
      -- Bottom separator for the unified section (no extra padding)
      imgui.Separator()
      
      -- Item Management section removed - now handled by separate GUI
    
    imgui.End()
end

return gui