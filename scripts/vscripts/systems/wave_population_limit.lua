-- One shared assault-wave budget and one cancellable game-time deadline.
local M = {}

function M.update(state, context)
    if state.defeat_settled or state.post_clear_frozen or context.ended()
        or state.alive <= state.alive_limit then
        context.clear()
        return false
    end
    if not state.overflow_active then
        state.overflow_active = true
        state.overflow_deadline = context.now() + state.overflow_grace_seconds
        context.scheduler.every(1, function()
            if context.current_state() ~= state then return false end
            context.prune()
            context.publish("monster_limit_countdown")
            return state.overflow_active == true and not state.defeat_settled
        end, context.task_id)
    end
    state.overflow_remaining = math.max(0, math.ceil(state.overflow_deadline - context.now()))
    return state.overflow_remaining <= 0
end

return M
