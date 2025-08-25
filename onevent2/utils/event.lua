local event = {}

local event_object = {}

function event_object:trigger(...)
    for _, fn in pairs(self.handlers) do 
        fn(...) 
    end
    for _, fn in pairs(self.temp_handlers) do
        fn(...)
        self.temp_handlers[fn] = nil
    end
end

function event_object:register(fn) 
    self.handlers[fn] = fn 
end

function event_object:once(fn) self.temp_handlers[fn] = fn end

function event_object:unregister(fn) self.handlers[fn] = nil end

function event.new()
    local event_obj = setmetatable({handlers = {}, temp_handlers = {}},
                        {__index = event_object})
    return event_obj
end

return event
