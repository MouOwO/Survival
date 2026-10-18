-- Explicit Tools console probe. Builds data only: no mode selection, units,
-- account writes, rewards, game state changes or production cache replacement.
assert(IsInToolsMode and IsInToolsMode(), "Tools server required")
local cached_builder = package.loaded["systems/wave_difficulty_builder"]
local setup = package.loaded["systems/match_setup_service"]
local mode_before = setup and setup.get_mode and setup.get_mode() or ""
local builder = assert(dofile("systems/wave_difficulty_builder"))
local source = assert(dofile("config/generated/wave_definitions")).rows
local summary = { difficulties = {}, unit_spawns = 0, account_writes = 0,
    mode_before = mode_before, validation = "native_data_build_only" }
for number = 1, 10 do
    local id = "N" .. number
    local rich = assert(builder.build(source, id, "rich"))
    local total = 0
    for wave_number = 1, rich.total_waves do
        local count = 0
        for _, row in ipairs(rich.waves[wave_number]) do
            count = count + row.monster_count
            assert(row.health > 0 and row.attack > 0 and row.war3_armor >= 0)
        end
        assert(count == 60, id .. "/" .. wave_number .. " must contain 60 monsters")
        total = total + count
    end
    summary.difficulties[id] = { waves = rich.total_waves, monsters_per_player = total }
    if id == "N1" then
        summary.wave1 = rich.waves[1][1]
        summary.bosses = {}
        for wave_number = 5, 25, 5 do
            for _, row in ipairs(rich.waves[wave_number]) do
                if row.member_role == "assault_boss" then
                    summary.bosses[tostring(wave_number)] = {
                        attack = row.attack, health = row.health, war3_armor = row.war3_armor,
                        estimated = row.rich_stats_estimated,
                    }
                end
            end
        end
    end
end
assert(package.loaded["systems/wave_difficulty_builder"] == cached_builder,
    "native data probe must not replace the live builder")
summary.mode_after = setup and setup.get_mode and setup.get_mode() or ""
assert(summary.mode_after == mode_before, "native data probe changed selected mode")
summary.status = "PASS"
print("[RICH_WAVE_NATIVE_DATA] " .. require("core/json_encoder").encode(summary))
print("RICH_WAVE_NATIVE_DATA_DONE")
