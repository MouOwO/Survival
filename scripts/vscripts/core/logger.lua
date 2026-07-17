local M = {}

local function output(level, scope, message)
    print(string.format("[Survival][%s][%s] %s", level, scope, tostring(message)))
end

function M.info(scope, message)
    output("INFO", scope, message)
end

function M.warn(scope, message)
    output("WARN", scope, message)
end

function M.error(scope, message)
    output("ERROR", scope, message)
end

return M
