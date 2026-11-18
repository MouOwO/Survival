-- Creation only. Never retry Send, a callback, or an ambiguous transaction.
local M = {}

local function attempt(api, method, url)
    if type(api) ~= "function" then return nil, "m" end
    -- Keep a Lua caller frame for native bindings. Do not turn this into a
    -- tail call or pass the native function directly to pcall.
    local ok, request = pcall(function()
        local value = api(method, url)
        return value
    end)
    if not ok then return nil, "t" end
    if request == nil or request == false then return nil, "n" end
    if type(request) ~= "table" and type(request) ~= "userdata" then return nil, "i" end
    return request, "o"
end

function M.create(method, url)
    if type(method) ~= "string" or type(url) ~= "string" or url == "" then return nil, "ii", false end
    local primary, legacy = CreateHTTPRequestScriptVM, CreateHTTPRequest
    local request, first = attempt(primary, method, url)
    if request then return request, "os", true end
    local second
    request, second = attempt(legacy, method, url)
    return request, first .. second, type(primary) == "function" or type(legacy) == "function"
end

-- No startup work, scans, timers or HTTP. Per request: at most two native
-- creations, then exactly the caller's existing Send path for one object.
return M
