package.path = "scripts/vscripts/?.lua;" .. package.path
local profile = require("config/release_profile")
assert(profile.channel == "production", "checked-in source must deny development by default")
local policy = require("core/release_policy")
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
    for _, server in ipairs(variants) do
        IsServer = server.fn
        for _, tools in ipairs(variants) do
            IsInToolsMode = tools.fn
            for _, cheats in ipairs({false,true}) do
                GameRules = {IsCheatMode=function() return cheats end,
                    PlayerHasCustomGameHostPrivileges=function() return true end}
                local expected = channel == "development"
                    and server.name == "true" and tools.name == "true"
                assert(policy.development_allowed() == expected,
                    channel .. ":" .. server.name .. ":" .. tools.name)
                checked = checked + 1
            end
        end
    end
end
profile.channel = nil
IsServer, IsInToolsMode = function() return true end, function() return true end
assert(not policy.development_allowed(), "missing channel fails closed")
profile.channel = "production"
assert(policy.is_production() and not policy.denied_result().ok)
print("RELEASE_DEBUG_POLICY_PASS cases=" .. checked .. " plus missing channel")
