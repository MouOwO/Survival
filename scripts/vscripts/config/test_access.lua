-- Restricted Workshop accounts; the owner added a fifth account on 2026-11-01.
-- Keep identifiers as strings: Lua 5.1 numbers cannot represent SteamID64.
return {
    enabled = true,
    allowed_steamids = {
        "76561198424163156",
        "76561198845461206",
        "76561198104787442",
        "76561198974301984",
        "76561198296534615",
    },
}
