package.path = "scripts/vscripts/?.lua;" .. package.path
-- Build identities are explicit fixtures; the owner's development checkout
-- and the signed online release exercise the same policy implementation.
local profile = { channel = "production" }
package.loaded["config/release_profile"] = profile
local policy = require("core/release_policy")
local web_config_name = "config/player_web_auth"
local offline_config = { enabled = false }
local configurations = {
    { name = "offline", value = offline_config, allowed = true },
    { name = "online", value = { enabled = true } },
    { name = "missing_flag", value = {} },
    { name = "numeric_flag", value = { enabled = 0 } },
    { name = "string_flag", value = { enabled = "false" } },
    { name = "non_table", value = "disabled" },
}
local variants = {
    {name="true",fn=function() return true end},
    {name="false",fn=function() return false end},
    {name="truthy",fn=function() return 1 end},
    {name="throws",fn=function() error("engine API unavailable") end},
    {name="missing"},
}
local checked = 0
for _, channel in ipairs({"production", "development", "test", "unknown", ""}) do
    profile.channel = channel
    for _, configuration in ipairs(configurations) do
        package.loaded[web_config_name] = configuration.value
        for _, server in ipairs(variants) do
            IsServer = server.fn
            for _, tools in ipairs(variants) do
                IsInToolsMode = tools.fn
                for _, cheats in ipairs({false,true}) do
                    GameRules = {IsCheatMode=function() return cheats end,
                        PlayerHasCustomGameHostPrivileges=function() return true end}
                    local expected = configuration.allowed == true and channel == "development"
                        and server.name == "true" and tools.name == "true"
                    assert(policy.development_allowed() == expected,
                        channel .. ":" .. configuration.name .. ":" .. server.name .. ":" .. tools.name)
                    checked = checked + 1
                end
            end
        end
    end
end
profile.channel = "development"
IsServer, IsInToolsMode = function() return true end, function() return true end
local original_preload = package.preload[web_config_name]
for _, load in ipairs({
    function() error("configuration module is missing") end,
    function() error("configuration syntax/load failure") end,
    function() return nil end,
    function() return false end,
}) do
    package.loaded[web_config_name] = nil
    package.preload[web_config_name] = load
    local ok, allowed = pcall(policy.development_allowed)
    assert(ok and allowed == false, "failed configuration denies cheats without failing game initialization")
    checked = checked + 1
end
package.preload[web_config_name] = original_preload
package.loaded[web_config_name] = setmetatable({}, {
    __index = function() error("configuration must not execute a dynamic flag getter") end,
})
assert(not policy.development_allowed(), "missing raw enabled flag is denied")
package.loaded[web_config_name] = offline_config
assert(policy.development_allowed(), "explicit offline development Tools retain cheat access")
assert(package.loaded["debug/offline_logic_test"] == nil,
    "policy must not import the offline provider or recurse into its configure gate")
profile.channel = nil
IsServer, IsInToolsMode = function() return true end, function() return true end
assert(not policy.development_allowed(), "missing channel fails closed")
profile.channel = "production"
assert(policy.is_production() and not policy.denied_result().ok)
print("RELEASE_DEBUG_POLICY_PASS cases=" .. checked .. " plus missing channel")
