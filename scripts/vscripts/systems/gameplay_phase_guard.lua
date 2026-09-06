local M = {}
local frozen = false

function M.post_clear_frozen()
    return frozen
end

function M.set_post_clear_frozen(value)
    frozen = value == true
end

function M.reset()
    frozen = false
end

return M
