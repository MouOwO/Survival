package.path = "scripts/vscripts/?.lua;" .. package.path
local entries = {}
Entities = { FindByName = function(_, _, name)
    if entries[name] then return { IsNull = function() return false end } end
end }
local locations = require("config/generated/challenge_locations")
local resolver = require("systems/player_room_locations")
for player = 0, 3 do
    for room = 1, 4 do
        local base = string.format("challenge_%02d", room)
        entries["player_" .. player .. "_" .. base .. "_entry"] = true
        local row = resolver.resolve(base .. "_room", player)
        assert(row.entry_target_name == "player_" .. player .. "_" .. base .. "_entry")
        assert(row.home_target_name == "player_" .. player .. "_" .. base .. "_home")
        for i, name in ipairs(row.spawn_target_names) do
            assert(name == string.format("player_%d_%s_spawn_%02d", player, base, i))
        end
        assert(locations.by_id[base .. "_room"].entry_target_name == base .. "_entry")
    end
    entries["player_" .. player .. "_endless_cycle_sanctum_entry"] = true
    local row = resolver.resolve("endless_cycle_sanctum", player)
    assert(row.spawn_target_names[1] == "player_" .. player .. "_endless_cycle_sanctum_target")
    assert(resolver.marker_name("challenge_08_boss_spawn", player) == "challenge_08_boss_spawn")
end
entries = {}
assert(resolver.resolve("challenge_01_room", 0) == locations.by_id.challenge_01_room)
assert(resolver.marker_name("challenge_01_spawn_01", 0) == "challenge_01_spawn_01")
assert(resolver.marker_name(nil, 0) == nil)
assert(resolver.resolve("missing", 0) == nil)
print("player_room_locations: 16 private rooms, 4 endless rooms, shared boss and legacy fallback passed")
