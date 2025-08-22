local ffi = require('ffi')
local struct = require('struct')

ffi.cdef[[
    int32_t memcmp(const void* buff1, const void* buff2, size_t count);
]]

local packet_dedupe = {}

local last_chunk_buffer
local reference_buffer = T{}

-- Called from packet_in when chunk packet received (e.chunk_data_raw + e.chunk_size)
function packet_dedupe.record_packets(e)
    if e.chunk_data_raw and e.chunk_size then
        if ffi.C.memcmp(e.data_raw, e.chunk_data_raw, e.size) == 0 then
            if #reference_buffer > 2 then
                reference_buffer[#reference_buffer] = nil
            end
            if last_chunk_buffer then
                table.insert(reference_buffer, 1, last_chunk_buffer)
            end

            last_chunk_buffer = T{}
            local offset = 0
            while (offset < e.chunk_size) do
                local size = ashita.bits.unpack_be(e.chunk_data_raw, offset, 9, 7) * 4
                local chunk_packet = struct.unpack('c' .. size, e.chunk_data, offset + 1)
                last_chunk_buffer:append(chunk_packet)
                offset = offset + size
            end
        end
    end
end

-- Called for each incoming packet: check if its content matches known duplicates
function packet_dedupe.check_duplicates(e)
    local packet = struct.unpack('c' .. e.size, e.data, 1)
    for _, chunk in ipairs(reference_buffer) do
        for _, bufferEntry in ipairs(chunk) do
            if packet == bufferEntry then
                e.blocked = true
                return true
            end
        end
    end
    return false
end

return packet_dedupe