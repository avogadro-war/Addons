local M = {
    current_buffs = {}, -- [buff_id][actor_id] = true
    alerted_buffs = {}, -- [buff_id][actor_id] = true
}

function M.gain_buff(buff_id, actor_id)
    if not M.current_buffs[buff_id] then
        M.current_buffs[buff_id] = {}
    end
    if not M.current_buffs[buff_id][actor_id] then
        M.current_buffs[buff_id][actor_id] = true
        return true
    end
    return false
end

function M.lose_buff(buff_id, actor_id)
    if M.current_buffs[buff_id] then
        M.current_buffs[buff_id][actor_id] = nil
        if next(M.current_buffs[buff_id]) == nil then
            M.current_buffs[buff_id] = nil
        end
    end
    if M.alerted_buffs[buff_id] then
        M.alerted_buffs[buff_id][actor_id] = nil
        if next(M.alerted_buffs[buff_id]) == nil then
            M.alerted_buffs[buff_id] = nil
        end
    end
end

function M.should_alert(buff_id, actor_id)
    if not M.alerted_buffs[buff_id] then return true end
    return not M.alerted_buffs[buff_id][actor_id]
end

function M.mark_alerted(buff_id, actor_id)
    if not M.alerted_buffs[buff_id] then
        M.alerted_buffs[buff_id] = {}
    end
    M.alerted_buffs[buff_id][actor_id] = true
end

function M.reset_all()
    M.current_buffs = {}
    -- Do NOT clear alerted_buffs, so we remember which buffs have already triggered alerts
end

return M
