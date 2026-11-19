-- Original private-test roster retained as the explicit non-public fallback.
-- Keep identifiers as strings: Lua 5.1 numbers cannot represent SteamID64.
return {
    enabled = true,
    -- Public admission is an explicit production release choice. Identity is
    -- still read from PlayerResource and Steam web authorization stays required.
    public_release = true,
    allowed_steamids = {
        "76561198424163156",
        "76561198845461206",
        "76561198104787442",
        "76561198974301984",
        "76561198296534615",
    },
}
