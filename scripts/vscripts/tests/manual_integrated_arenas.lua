-- Read-only Workshop probe for the 30 integrated arenas in template_map.
-- Workshop console: script_reload_code tests/manual_integrated_arenas_check
-- The guarded entry reloads this module before running all areas.
-- From another guarded Lua tool, M.run('training_02') checks one area.
-- Does not spawn/move units, change GridNav or invoke any progression/save API.
-- GetGroundHeight/GridNav/path checks are live engine observations. AABB constants
-- are independently checked source bounds, not a claim of live prop bounds queries.
local M = {}
local PREFIX = '[INTEGRATED_ARENAS] '
local SOURCE_SHA256 = "8be600a49c35d8054541fb31a1cd97f5cd89a33adf1035c64470e46c5fc91d0f"
local AREAS = {
    {id="training_01", origin={-6144,11904,128}, surface=128, clear={850.78125,869.53125}, bounds={{-6762.464407,11321.221773000001,2},{-5534.048821,12578.976752999999,587.01572}}, markers={{"challenge_01_entry",{-6144,12332.125,152}},{"challenge_01_home",{-6144,12255.5625,152}},{"challenge_01_spawn_01",{-5994.585937,11849.3125,152}},{"challenge_01_spawn_02",{-6038.348437,11943.225,152}},{"challenge_01_spawn_03",{-6144,11982.125,152}},{"challenge_01_spawn_04",{-6249.651562,11943.225,152}},{"challenge_01_spawn_05",{-6293.414062,11849.3125,152}},{"challenge_01_spawn_06",{-6249.651562,11755.4,152}},{"challenge_01_spawn_07",{-6144,11716.5,152}},{"challenge_01_spawn_08",{-6038.348437,11755.4,152}}}},
    {id="training_02", origin={-4096,11904,128}, surface=128, clear={850.78125,869.53125}, bounds={{-4714.464407,11321.221773000001,2},{-3486.048821,12578.976752999999,587.01572}}, markers={{"challenge_02_entry",{-4096,12332.125,152}},{"challenge_02_home",{-4096,12255.5625,152}},{"challenge_02_spawn_01",{-3946.585937,11849.3125,152}},{"challenge_02_spawn_02",{-3990.3484369999996,11943.225,152}},{"challenge_02_spawn_03",{-4096,11982.125,152}},{"challenge_02_spawn_04",{-4201.651562,11943.225,152}},{"challenge_02_spawn_05",{-4245.414062,11849.3125,152}},{"challenge_02_spawn_06",{-4201.651562,11755.4,152}},{"challenge_02_spawn_07",{-4096,11716.5,152}},{"challenge_02_spawn_08",{-3990.3484369999996,11755.4,152}}}},
    {id="training_03", origin={2048,11904,128}, surface=128, clear={850.78125,869.53125}, bounds={{1429.5355929999996,11321.221773000001,2},{2657.951179,12578.976752999999,587.01572}}, markers={{"challenge_03_entry",{2048,12332.125,152}},{"challenge_03_home",{2048,12255.5625,152}},{"challenge_03_spawn_01",{2197.414063,11849.3125,152}},{"challenge_03_spawn_02",{2153.6515630000004,11943.225,152}},{"challenge_03_spawn_03",{2048,11982.125,152}},{"challenge_03_spawn_04",{1942.348438,11943.225,152}},{"challenge_03_spawn_05",{1898.5859380000002,11849.3125,152}},{"challenge_03_spawn_06",{1942.348438,11755.4,152}},{"challenge_03_spawn_07",{2048,11716.5,152}},{"challenge_03_spawn_08",{2153.6515630000004,11755.4,152}}}},
    {id="training_04", origin={4096,11904,128}, surface=128, clear={850.78125,869.53125}, bounds={{3477.5355929999996,11321.221773000001,2},{4705.951179,12578.976752999999,587.01572}}, markers={{"challenge_04_entry",{4096,12332.125,152}},{"challenge_04_home",{4096,12255.5625,152}},{"challenge_04_spawn_01",{4245.414063,11849.3125,152}},{"challenge_04_spawn_02",{4201.651563,11943.225,152}},{"challenge_04_spawn_03",{4096,11982.125,152}},{"challenge_04_spawn_04",{3990.348438,11943.225,152}},{"challenge_04_spawn_05",{3946.585938,11849.3125,152}},{"challenge_04_spawn_06",{3990.348438,11755.4,152}},{"challenge_04_spawn_07",{4096,11716.5,152}},{"challenge_04_spawn_08",{4201.651563,11755.4,152}}}},
    {id="training_07", origin={-4096,-4224,128}, surface=128, clear={850.78125,869.53125}, bounds={{-4753.483472,-4861.923106,2},{-3455.617461,-3615.037941,533.799246}}, markers={{"challenge_07_entry",{-4096,-3795.875,152}},{"challenge_07_home",{-4096,-3872.4375,152}},{"challenge_07_boss_spawn",{-4096,-4278.6875,152}},{"challenge_07_spawn_01",{-3935.599609,-4278.6875,152}},{"challenge_07_spawn_02",{-3966.2334469999996,-4194.882031,152}},{"challenge_07_spawn_03",{-4046.4336430000003,-4143.0875,152}},{"challenge_07_spawn_04",{-4145.566357,-4143.0875,152}},{"challenge_07_spawn_05",{-4225.766553,-4194.882031,152}},{"challenge_07_spawn_06",{-4256.400391,-4278.6875,152}},{"challenge_07_spawn_07",{-4225.766553,-4362.492969,152}},{"challenge_07_spawn_08",{-4145.566357,-4414.2875,152}},{"challenge_07_spawn_09",{-4046.4336430000003,-4414.2875,152}},{"challenge_07_spawn_10",{-3966.2334469999996,-4362.492969,152}}}},
    {id="training_08", origin={2048,-4224,128}, surface=128, clear={850.78125,869.53125}, bounds={{1390.516528,-4861.923106,2},{2688.382539,-3615.0379409999996,533.799246}}, markers={{"challenge_08_entry",{2048,-3795.875,152}},{"challenge_08_home",{2048,-3872.4375,152}},{"challenge_08_boss_spawn",{2048,-4278.6875,152}},{"challenge_08_spawn_01",{2208.400391,-4278.6875,152}},{"challenge_08_spawn_02",{2177.7665530000004,-4194.882031,152}},{"challenge_08_spawn_03",{2097.5663569999997,-4143.0875,152}},{"challenge_08_spawn_04",{1998.4336430000003,-4143.0875,152}},{"challenge_08_spawn_05",{1918.2334469999996,-4194.882031,152}},{"challenge_08_spawn_06",{1887.5996089999999,-4278.6875,152}},{"challenge_08_spawn_07",{1918.2334469999996,-4362.492969,152}},{"challenge_08_spawn_08",{1998.4336430000003,-4414.2875,152}},{"challenge_08_spawn_09",{2097.5663569999997,-4414.2875,152}},{"challenge_08_spawn_10",{2177.7665530000004,-4362.492969,152}}}},
    {id="rebirth_01", origin={-8192,11776,16}, surface=30, clear={936,486}, bounds={{-8692.000031,11500.999939,16},{-7691.999969,12051.000061,50}}, markers={{"rebirth_01_entry",{-8492,11776,54}},{"rebirth_01_boss_spawn",{-7892,11776,54}},{"ascension_arena_01_center",{-8192,11776,54}}}},
    {id="rebirth_02", origin={-8192,9728,16}, surface=44, clear={933,483}, bounds={{-8692.000031,9452.999939000001,16},{-7691.999969,10003.000060999999,64}}, markers={{"rebirth_02_entry",{-8492,9728,68}},{"rebirth_02_boss_spawn",{-7892,9728,68}},{"ascension_arena_02_center",{-8192,9728,68}}}},
    {id="rebirth_03", origin={-8192,7680,16}, surface=58, clear={930,480}, bounds={{-8692.000031,7404.999939,16},{-7691.999969,7955.000061,78}}, markers={{"rebirth_03_entry",{-8492,7680,82}},{"rebirth_03_boss_spawn",{-7892,7680,82}},{"ascension_arena_03_center",{-8192,7680,82}}}},
    {id="rebirth_04", origin={-8192,5632,16}, surface=72, clear={927,477}, bounds={{-8692.000031,5356.999938999999,16},{-7691.999969,5907.000061000001,90.5}}, markers={{"rebirth_04_entry",{-8492,5632,96}},{"rebirth_04_boss_spawn",{-7892,5632,96}},{"ascension_arena_04_center",{-8192,5632,96}}}},
    {id="rebirth_05", origin={-8192,3584,16}, surface=86, clear={924,474}, bounds={{-8692.000031,3308.9999390000003,16},{-7691.999969,3859.0000609999997,104.5}}, markers={{"rebirth_05_entry",{-8492,3584,110}},{"rebirth_05_boss_spawn",{-7892,3584,110}},{"ascension_arena_05_center",{-8192,3584,110}}}},
    {id="rebirth_06", origin={-8192,1536,16}, surface=100, clear={921,471}, bounds={{-8692.000031,1260.9999390000003,16},{-7691.999969,1811.0000609999997,118.5}}, markers={{"rebirth_06_entry",{-8492,1536,124}},{"rebirth_06_boss_spawn",{-7892,1536,124}},{"ascension_arena_06_center",{-8192,1536,124}}}},
    {id="rebirth_07", origin={-8192,-512,16}, surface=114, clear={918,468}, bounds={{-8692.000031,-787.0000610000002,16},{-7691.999969,-236.9999389999998,145}}, markers={{"rebirth_07_entry",{-8492,-512,138}},{"rebirth_07_boss_spawn",{-7892,-512,138}},{"ascension_arena_07_center",{-8192,-512,138}}}},
    {id="rebirth_08", origin={-8192,-2560,16}, surface=128, clear={915,465}, bounds={{-8691.127808000001,-2834.131775,16},{-7693.00061,-2285.949036,140.5}}, markers={{"rebirth_08_entry",{-8492,-2560,152}},{"rebirth_08_boss_spawn",{-7892,-2560,152}},{"ascension_arena_08_center",{-8192,-2560,152}}}},
    {id="rebirth_09", origin={-8192,-4608,16}, surface=142, clear={912,462}, bounds={{-8691.127808000001,-4882.131775,16},{-7693.00061,-4333.949036,160}}, markers={{"rebirth_09_entry",{-8492,-4608,166}},{"rebirth_09_boss_spawn",{-7892,-4608,166}},{"ascension_arena_09_center",{-8192,-4608,166}}}},
    {id="rebirth_10", origin={-12800,4096,16}, surface=156, clear={909,459}, bounds={{-13299.127808,3821.868225,16},{-12301.00061,4370.050964,174}}, markers={{"rebirth_10_entry",{-13100,4096,180}},{"rebirth_10_boss_spawn",{-12500,4096,180}},{"ascension_arena_10_center",{-12800,4096,180}}}},
    {id="ten_realm_01", origin={8192,11776,58}, surface=58, clear={612,612}, bounds={{7629.982787,11213.758329,-66.347666},{8758.562654000001,12341.330801,300}}, markers={{"challenge_11_stage_01_entry",{8192,11542,82}},{"challenge_11_stage_01_spawn",{8192,12010,82}},{"ten_realm_arena_01_center",{8192,11776,82}}}},
    {id="ten_realm_02", origin={8192,9728,58}, surface=58, clear={612,612}, bounds={{7626.219853,9164.553307999999,-66.310776},{8755.713623,10287.412138,310}}, markers={{"challenge_11_stage_02_entry",{8192,9494,82}},{"challenge_11_stage_02_spawn",{8192,9962,82}},{"ten_realm_arena_02_center",{8192,9728,82}}}},
    {id="ten_realm_03", origin={8192,7680,58}, surface=58, clear={612,612}, bounds={{7628.85729,7120.20472,-66.448226},{8756.461868999999,8244.427039,304}}, markers={{"challenge_11_stage_03_entry",{8192,7446,82}},{"challenge_11_stage_03_spawn",{8192,7914,82}},{"ten_realm_arena_03_center",{8192,7680,82}}}},
    {id="ten_realm_04", origin={8192,5632,58}, surface=58, clear={612,612}, bounds={{7628.859462,5067.308891,-66.498508},{8758.565716000001,6194.574677,234.005066}}, markers={{"challenge_11_stage_04_entry",{8192,5398,82}},{"challenge_11_stage_04_spawn",{8192,5866,82}},{"ten_realm_arena_04_center",{8192,5632,82}}}},
    {id="ten_realm_05", origin={8192,3584,58}, surface=58, clear={612,612}, bounds={{7626.535475,3021.4847929999996,-66.460104},{8753.212005000001,4150.488242,314}}, markers={{"challenge_11_stage_05_entry",{8192,3350,82}},{"challenge_11_stage_05_spawn",{8192,3818,82}},{"ten_realm_arena_05_center",{8192,3584,82}}}},
    {id="ten_realm_06", origin={8192,1536,58}, surface=58, clear={612,612}, bounds={{7631.585153,972.5413709999998,-66.334493},{8756.142987,2100.498776,305}}, markers={{"challenge_11_stage_06_entry",{8192,1302,82}},{"challenge_11_stage_06_spawn",{8192,1770,82}},{"ten_realm_arena_06_center",{8192,1536,82}}}},
    {id="ten_realm_07", origin={8192,-512,58}, surface=58, clear={612,612}, bounds={{7627.764176000001,-1077.610111,-66.343189},{8754.865391,51.93918399999984,221}}, markers={{"challenge_11_stage_07_entry",{8192,-746,82}},{"challenge_11_stage_07_spawn",{8192,-278,82}},{"ten_realm_arena_07_center",{8192,-512,82}}}},
    {id="ten_realm_08", origin={8192,-2560,58}, surface=58, clear={612,612}, bounds={{7628.84532,-3122.577948,-66.461484},{8756.333627,-1993.0938829999996,221}}, markers={{"challenge_11_stage_08_entry",{8192,-2794,82}},{"challenge_11_stage_08_spawn",{8192,-2326,82}},{"ten_realm_arena_08_center",{8192,-2560,82}}}},
    {id="ten_realm_09", origin={8192,-4608,58}, surface=58, clear={612,612}, bounds={{7627.911045,-5173.801067,-66.492565},{8755.009022,-4046.29679,305}}, markers={{"challenge_11_stage_09_entry",{8192,-4842,82}},{"challenge_11_stage_09_spawn",{8192,-4374,82}},{"ten_realm_arena_09_center",{8192,-4608,82}}}},
    {id="ten_realm_10", origin={12544,6144,58}, surface=58, clear={612,612}, bounds={{11980.558759,5582.538669,-66.434982},{13106.462593,6709.926299,310}}, markers={{"challenge_11_stage_10_entry",{12544,5910,82}},{"challenge_11_stage_10_spawn",{12544,6378,82}},{"ten_realm_arena_10_center",{12544,6144,82}}}},
    {id="player_0_training", origin={-12800,11904,128}, surface=128, clear={850.78125,869.53125}, bounds={{-13418.464407,11321.221773000001,2},{-12190.048821,12578.976752999999,587.01572}}, markers={{"player_0_hero_spawn",{-12992,11904,152}},{"player_0_training_entry",{-12992,11904,152}},{"player_0_training_home",{-12992,11904,152}},{"player_0_training_target",{-12608,11904,152}}}},
    {id="player_1_training", origin={12800,11904,128}, surface=128, clear={850.78125,869.53125}, bounds={{12181.535593,11321.221773000001,2},{13409.951179,12578.976752999999,587.01572}}, markers={{"player_1_hero_spawn",{12608,11904,152}},{"player_1_training_entry",{12608,11904,152}},{"player_1_training_home",{12608,11904,152}},{"player_1_training_target",{12992,11904,152}}}},
    {id="player_2_training", origin={-12800,-11904,128}, surface=128, clear={850.78125,869.53125}, bounds={{-13418.464407,-12486.778226999999,2},{-12190.048821,-11229.023247000001,587.01572}}, markers={{"player_2_hero_spawn",{-12992,-11904,152}},{"player_2_training_entry",{-12992,-11904,152}},{"player_2_training_home",{-12992,-11904,152}},{"player_2_training_target",{-12608,-11904,152}}}},
    {id="player_3_training", origin={12800,-11904,128}, surface=128, clear={850.78125,869.53125}, bounds={{12181.535593,-12486.778226999999,2},{13409.951179,-11229.023247000001,587.01572}}, markers={{"player_3_hero_spawn",{12608,-11904,152}},{"player_3_training_entry",{12608,-11904,152}},{"player_3_training_home",{12608,-11904,152}},{"player_3_training_target",{12992,-11904,152}}}},
}

local function clear(p)
    return GridNav:IsTraversable(p) and not GridNav:IsBlocked(p)
end

local function point(area, x, y)
    return Vector(area.origin[1] + x, area.origin[2] + y, area.surface + 24)
end

local function xyz(p)
    return string.format('(%.2f,%.2f,%.2f)', p.x, p.y, p.z)
end

local function add(report, name, ok, detail)
    report.checked = report.checked + 1
    if not ok then report.failed = report.failed + 1 end
    report.results[#report.results + 1] = { name = name, ok = not not ok, detail = detail }
    print(PREFIX .. (ok and 'PASS ' or 'FAIL ') .. name .. (detail and (' ' .. detail) or ''))
end

local function actual_marker(report, expected)
    local name, epos = expected[1], expected[2]
    local entity = Entities:FindByName(nil, name)
    if not entity or entity:IsNull() then
        add(report, 'marker.' .. name, false, 'missing')
        return nil
    end
    local duplicate = Entities:FindByName(entity, name)
    local p = entity:GetAbsOrigin()
    local good = not duplicate and math.abs(p.x - epos[1]) < 1
        and math.abs(p.y - epos[2]) < 1 and math.abs(p.z - epos[3]) < 1
    add(report, 'marker.' .. name, good, xyz(p) .. (duplicate and ' duplicate' or ''))
    return p
end

local function overlap(a, b)
    return a[1][1] < b[2][1] and b[1][1] < a[2][1]
        and a[1][2] < b[2][2] and b[1][2] < a[2][2]
end

local function run_area(report, area)
    local entry, markers = nil, {}
    for _, expected in ipairs(area.markers) do
        local p = actual_marker(report, expected)
        if p then
            markers[#markers + 1] = { name = expected[1], p = p }
            if expected[1]:match('_entry$') then entry = p end
        end
    end
    local ground_count, bad_ground, bad_navigation, first_bad = 0, 0, 0, nil
    local min_ground, max_ground = math.huge, -math.huge
    local function sample(p, label)
        ground_count = ground_count + 1
        local ground = GetGroundHeight(p, nil)
        min_ground, max_ground = math.min(min_ground, ground), math.max(max_ground, ground)
        local floor_ok = math.abs(ground - area.surface) <= 2
        local nav_ok = clear(p)
        if not floor_ok then bad_ground = bad_ground + 1 end
        if not nav_ok then bad_navigation = bad_navigation + 1 end
        if (not floor_ok or not nav_ok) and not first_bad then
            first_bad = label .. ' at=' .. xyz(p) .. string.format(' ground=%.2f expected=%.2f nav=%s',
                ground, area.surface, tostring(nav_ok))
        end
    end
    sample(point(area, 0, 0), 'center')
    for _, marker in ipairs(markers) do sample(marker.p, marker.name) end
    -- 64-unit interior sampling avoids wall collision margins, and checks
    -- actual ground rather than the Z assigned to a floating info_target.
    local hx, hy = area.clear[1] / 2 - 64, area.clear[2] / 2 - 64
    for y = -hy, hy, 64 do
        for x = -hx, hx, 64 do sample(point(area, x, y), 'interior') end
    end
    add(report, area.id .. '.ground_and_navigation', bad_ground == 0 and bad_navigation == 0,
        string.format('samples=%d ground_range=%.2f..%.2f bad_ground=%d bad_nav=%d',
            ground_count, min_ground, max_ground, bad_ground, bad_navigation)
            .. (first_bad and (' first=' .. first_bad) or ''))
    local paths, blocked, first_path = 0, 0, nil
    local function path_to(p, label)
        paths = paths + 1
        if not entry or not GridNav:CanFindPath(entry, p) then
            blocked = blocked + 1
            first_path = first_path or label
        end
    end
    for _, marker in ipairs(markers) do path_to(marker.p, marker.name) end
    for _, xy in ipairs({{0,0}, {-hx,-hy}, {hx,-hy}, {-hx,hy}, {hx,hy}}) do
        path_to(point(area, xy[1], xy[2]), 'interior_corner')
    end
    add(report, area.id .. '.entry_paths', entry ~= nil and blocked == 0,
        string.format('paths=%d blocked=%d', paths, blocked) .. (first_path and (' first=' .. first_path) or ''))
    -- Water immediately outside the complete model footprint must stay blocked.
    local b, blocked_water, water_count = area.bounds, 0, 0
    for _, xy in ipairs({{b[1][1]-96, area.origin[2]}, {b[2][1]+96, area.origin[2]},
        {area.origin[1], b[1][2]-96}, {area.origin[1], b[2][2]+96}}) do
        water_count = water_count + 1
        if not clear(Vector(xy[1], xy[2], 16)) then blocked_water = blocked_water + 1 end
    end
    add(report, area.id .. '.water_boundary', blocked_water == water_count,
        string.format('blocked=%d/%d', blocked_water, water_count))
    return entry
end

function M.run(only)
    local report = { checked = 0, failed = 0, results = {}, source_sha256 = SOURCE_SHA256,
        map = GetMapName(), read_only_probe = true, complete = false }
    if not IsServer() or not IsInToolsMode() or report.map ~= 'template_map' then
        add(report, 'scope', false, 'requires server-side Workshop template_map')
        return report
    end
    local selected = {}
    for _, area in ipairs(AREAS) do if only == nil or only == area.id then selected[#selected + 1] = area end end
    if #selected == 0 then
        add(report, 'area_selector', false, 'unknown area id')
        return report
    end
    print(PREFIX .. 'BEGIN areas=' .. #selected .. ' source=' .. SOURCE_SHA256)
    local entries = {}
    for _, area in ipairs(selected) do
        local ok, result = pcall(run_area, report, area)
        if ok then entries[area.id] = result else add(report, area.id .. '.probe_exception', false, tostring(result)) end
    end
    local pairs, linked, first_link, overlapping = 0, 0, nil, 0
    for i = 1, #selected do
        local a = selected[i]
        for j = 1, i - 1 do
            local b = selected[j]
            if overlap(a.bounds, b.bounds) then overlapping = overlapping + 1 end
            pairs = pairs + 1
            if not entries[a.id] or not entries[b.id] or GridNav:CanFindPath(entries[a.id], entries[b.id]) then
                linked = linked + 1
                first_link = first_link or (a.id .. '/' .. b.id)
            end
        end
    end
    if #selected > 1 then
        add(report, 'source_model_bounds_disjoint', overlapping == 0,
            string.format('pairs=%d overlapping=%d', pairs, overlapping))
        add(report, 'region_path_isolation', linked == 0,
            string.format('pairs=%d linked_or_missing=%d', pairs, linked)
                .. (first_link and (' first=' .. first_link) or ''))
    end
    add(report, 'legacy_rank_ten_spawn_absent', Entities:FindByName(nil, 'rebirth_010_boss_spawn') == nil)
    report.complete = true
    report.status = report.failed == 0 and 'PASS' or 'FAIL'
    _G.INTEGRATED_ARENAS_LAST_REPORT = report
    print(PREFIX .. 'SUMMARY ' .. report.status .. ' areas=' .. #selected
        .. ' checked=' .. report.checked .. ' failed=' .. report.failed)
    return report
end

M.areas = AREAS
return M
