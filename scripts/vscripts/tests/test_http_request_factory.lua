package.path = "scripts/vscripts/?.lua;" .. package.path
local checks, calls, sent = 0, {}, 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local function object()
    return { Send = function() sent = sent + 1; return false end }
end
local function factory(label, result)
    return function(method, url)
        calls[#calls + 1] = label
        check(method == "POST" and url == "https://example.invalid/auth", "original method and URL preserved")
        if result == "throw" then error("PRIVATE_NATIVE_ERROR") end
        return result
    end
end
CreateHTTPRequestScriptVM = factory("primary", object())
CreateHTTPRequest = factory("legacy", object())
local request_factory = require("core/http_request_factory")
check(#calls == 0 and sent == 0, "import performs no native or HTTP operation")
local request, outcome, available = request_factory.create("POST", "https://example.invalid/auth")
check(request and outcome == "os" and available and #calls == 1, "healthy path creates exactly once")
check(sent == 0, "constructor helper never sends")
request:Send()
check(sent == 1 and #calls == 1, "explicit false Send cannot cause a constructor retry")
for _, case in ipairs({{nil, "n"}, {false, "n"}, {"throw", "t"}, {true, "i"}, {17, "i"}, {"invalid", "i"}}) do
    calls = {}; local expected = object()
    CreateHTTPRequestScriptVM = factory("primary", case[1])
    CreateHTTPRequest = factory("legacy", expected)
    request, outcome, available = request_factory.create("POST", "https://example.invalid/auth")
    check(request == expected and outcome == case[2] .. "o" and available, "only pre-object failure selects legacy")
    check(#calls == 2 and calls[1] == "primary" and calls[2] == "legacy", "at most two ordered constructors")
end
for _, case in ipairs({{nil, "n"}, {"throw", "t"}}) do
    calls = {}; CreateHTTPRequestScriptVM = factory("primary", case[1]); CreateHTTPRequest = factory("legacy", nil)
    request, outcome, available = request_factory.create("POST", "https://example.invalid/auth")
    check(not request and outcome == case[2] .. "n" and available and #calls == 2, "both failures return bounded enum without retry or error text")
end
CreateHTTPRequestScriptVM, CreateHTTPRequest = nil, nil
request, outcome, available = request_factory.create("POST", "https://example.invalid/auth")
check(not request and outcome == "mm" and not available, "missing APIs are distinct from empty objects")
CreateHTTPRequest = factory("legacy", object()); calls = {}
request, outcome, available = request_factory.create("POST", "https://example.invalid/auth")
check(request and outcome == "mo" and available and #calls == 1, "legacy-only engine remains supported")

-- Lua 5.1 negative control for native bindings that inspect the Lua caller.
-- This checks call-frame mechanics; it is not a claim about Dota's root cause.
local expected, frame_calls = object(), 0
CreateHTTPRequestScriptVM = function()
    frame_calls = frame_calls + 1
    if debug.getinfo(2, "S").what ~= "Lua" then return nil end
    return expected
end
local ok, old = pcall(CreateHTTPRequestScriptVM, "POST", "https://example.invalid/auth")
check(ok and not old, "direct pcall negative control lacks a Lua caller frame")
request, outcome = request_factory.create("POST", "https://example.invalid/auth")
check(request == expected and outcome == "os" and frame_calls == 2, "protected non-tail Lua call preserves the caller frame")
calls = {}; CreateHTTPRequestScriptVM = factory("primary", object())
request, outcome = request_factory.create("POST", "")
check(not request and outcome == "ii" and #calls == 0, "invalid input performs zero native calls")
check(sent == 1, "all failure paths performed zero Send operations")
local inherited = object()
local globals = _G
local env = setmetatable({}, {__index = function(_, name)
    if name == "CreateHTTPRequestScriptVM" then return function() return inherited end end
    if name == "CreateHTTPRequest" then return nil end
    return globals[name]
end})
env._G = env
local chunk = assert(loadfile("scripts/vscripts/core/http_request_factory.lua"))
setfenv(chunk, env)
local scoped = chunk()
request, outcome = scoped.create("POST", "https://example.invalid/auth")
check(request == inherited and outcome == "os", "inherited native globals must use ordinary Lua environment lookup")
print("HTTP_REQUEST_FACTORY_PASS checks=" .. checks .. "; healthy1/failure<=2 constructors; zero automatic Send; protected Lua frame")
