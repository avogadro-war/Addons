--[[
    file.lua
    File helper utilities: file.exists(path)
    Usage: local file = require('utils.file')
]]

local file = {}

function file.exists(path)
    local ok, f = pcall(io.open, path, "r")
    if ok and f then f:close(); return true end
    return false
end

return file
