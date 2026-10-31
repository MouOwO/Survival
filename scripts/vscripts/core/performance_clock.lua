-- Choose elapsed time for a synchronous work budget, never simulation time.
local M = {}

function M.new()
    local system = rawget(_G, "GetSystemTimeMS")
    if type(system) == "function" then
        local ok, value = pcall(system)
        if ok and type(value) == "number" and value == value
            and value ~= math.huge and value ~= -math.huge then
            return function() return system() / 1000 end
        end
    end
    -- CPU time remains useful for bounded Lua work in standalone tests.
    return os.clock
end

return M
