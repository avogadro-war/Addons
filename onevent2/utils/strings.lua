--[[
    strings.lua
    String helper utilities: startswith, trim, split.
    Usage: local strings = require('utils.strings')
]]

local strings = {}

function strings.startswith(s, start)
    return s:sub(1, #start) == start
end

function strings.trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

function strings.split(s, sep)
    local t = {}
    for str in string.gmatch(s, "([^"..sep.."]+)") do
        table.insert(t, str)
    end
    return t
end

return strings
