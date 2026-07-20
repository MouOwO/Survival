local M = {
    total_waves = 30,
    initial_delay = 30,
    interval_after_spawn_complete = 30,
    spawn_interval = 0.30,
    boss_every = 5,
    spawn_point = { x = 0, y = 1600, z = 128 },
    waves = {},
}

for wave = 1, M.total_waves do
    M.waves[wave] = {
        wave_number = wave,
        enemy_id = "zombie_basic",
        count = 5 + wave * 2,
        boss_id = (wave % M.boss_every == 0) and "zombie_boss" or nil,
        boss_count = (wave % M.boss_every == 0) and 1 or 0,
        spawn_interval = M.spawn_interval,
    }
end

return M
