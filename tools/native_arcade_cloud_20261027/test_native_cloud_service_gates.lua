-- Run the same roster/auth/profile integration against ROOT or the generated
-- frozen startup patch without importing unrelated unreleased UI expectations.
local function read(path)
    local file = assert(io.open(path, "rb"))
    local raw = file:read("*a"); file:close(); return raw
end
local source = read("scripts/vscripts/tests/test_startup_loading_service.lua")
local fixture_end = assert(source:find("-- Browser approval remains a normal wait", 1, true))
local scenario_start = assert(source:find("-- The target VM can initially expose only the host", 1, true))
local scenario_end = assert(source:find("-- Exercise the actual addon lifecycle callback", scenario_start, true))
local scenario = source:sub(scenario_start, scenario_end - 1)
assert(scenario:find("STARTUP_EXPECTED_CROSS_MAP_ROSTER_PASS", 1, true))
assert(scenario:find("actual_native_count=1", 1, true)
    and scenario:find("profile_success(profile_requests[2])", 1, true),
    "The focused fixture must preserve host-only native count and finished-profile checks")
if arg and arg[1] then
    assert(arg[1] == "output/native_arcade_cloud_20261027/startup_loading_frozen_roster.lua",
        "Only the builder-generated frozen startup test artifact is accepted")
    package.preload["systems/startup_loading_service"] = assert(loadfile(arg[1]))
end
local context = "\nlocal previous_is_server=IsServer\n"
    .. "local automatic_think,automatic_enabled,automatic_remaining,automatic_countdowns=nil,nil,nil,0\n"
local chunk = assert(loadstring(source:sub(1,fixture_end-1) .. context .. scenario,
    arg and arg[1] and "frozen_native_cloud_roster_gate" or "root_native_cloud_roster_gate"))
chunk()
print(arg and arg[1] and "FROZEN_NATIVE_CLOUD_SERVICE_GATES_PASS" or "ROOT_NATIVE_CLOUD_SERVICE_GATES_PASS")
