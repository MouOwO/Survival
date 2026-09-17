package.path = "scripts/vscripts/?.lua;" .. package.path
local f = assert(io.open("scripts/vscripts/systems/hero_combat_stat_service.lua", "rb"))
local source = f:read("*a"); f:close()
local body = assert(source:match("local function debug_set_attack%(payload%)(.-)\nlocal function get_stats"))
local removed = 0
local state = { unit = { IsNull = function() return false end,
    RemoveModifierByName = function(_, name)
        assert(name == "modifier_debug_attack_bonus"); removed = removed + 1
    end }, snapshot = { attack_min = 200 } }
local environment = setmetatable({
    current = function(id) if id == 0 then return state end end,
    recalculate = function()
        state.snapshot = { attack_min = state.debug_attack_override or 200 }
        return state.snapshot
    end,
}, { __index = _G })
local chunk = assert(loadstring("return function(payload)" .. body))
setfenv(chunk, environment)
local apply = chunk()
assert(apply({ player_id = 0, attack_delta = 50 }).snapshot.attack_min == 250)
assert(apply({ player_id = 0, attack = 1111111111, attack_speed = 5 }).ok)
assert(apply({ player_id = 0, attack_delta = 1000000000 }).snapshot.attack_min == 2111111111)
assert(apply({ player_id = 0, attack_delta = 1000000000 }).snapshot.attack_min == 3111111111)
assert(state.debug_attack_speed_override == 5)
assert(apply({ player_id = 0, attack_delta = -1111111111 }).snapshot.attack_min == 2000000000)
local before = state.debug_attack_override
for _, delta in ipairs({math.huge, -math.huge, 0/0, -3e9, 1e16}) do
    assert(not apply({ player_id = 0, attack_delta = delta }).ok)
    assert(state.debug_attack_override == before)
end
assert(not apply({ player_id = 1, attack_delta = 100 }).ok)
assert(not apply({ player_id = 0, attack_delta = 1, attack = 5 }).ok)
assert(removed == 5)
print("ADDATTACK_PASS: normal hero, wudi, repeated billions, negative delta, validation")
