-- Read-only Workshop probe for the 26 integrated arenas in template_map.
-- Workshop console: script_reload_code tests/manual_integrated_arenas_check
-- The guarded entry reloads this module before running all areas.
-- From another guarded Lua tool, M.run('training_02') checks one area.
-- Does not spawn/move units, change GridNav or invoke any progression/save API.
-- GetGroundHeight/GridNav/path checks are live engine observations. AABB constants
-- are independently checked source bounds, not a claim of live prop bounds queries.
local M = {}
local PREFIX = '[INTEGRATED_ARENAS] '
local SOURCE_SHA256 = "4adaa5f6c817ab758b957b18438ba8c6ad53ff8586cda05d8fd14726039540cd"
local AREAS = {
    {id="training_01", origin={-6656,6784,128}, surface=128, clear={850.78125,869.53125}, bounds={{-7274.464407,6201.221773,2},{-6046.048821,7458.976753,587.01572}}, markers={{"challenge_01_entry",{-6656,7212.125,152}},{"challenge_01_home",{-6656,7135.5625,152}},{"challenge_01_spawn_01",{-6506.585937,6729.3125,152}},{"challenge_01_spawn_02",{-6550.348437,6823.225,152}},{"challenge_01_spawn_03",{-6656,6862.125,152}},{"challenge_01_spawn_04",{-6761.651562,6823.225,152}},{"challenge_01_spawn_05",{-6805.414062,6729.3125,152}},{"challenge_01_spawn_06",{-6761.651562,6635.4,152}},{"challenge_01_spawn_07",{-6656,6596.5,152}},{"challenge_01_spawn_08",{-6550.348437,6635.4,152}}}},
    {id="training_02", origin={-4352,6784,128}, surface=128, clear={850.78125,869.53125}, bounds={{-4970.464407,6201.221773,2},{-3742.048821,7458.976753,587.01572}}, markers={{"challenge_02_entry",{-4352,7212.125,152}},{"challenge_02_home",{-4352,7135.5625,152}},{"challenge_02_spawn_01",{-4202.585937,6729.3125,152}},{"challenge_02_spawn_02",{-4246.348437,6823.225,152}},{"challenge_02_spawn_03",{-4352,6862.125,152}},{"challenge_02_spawn_04",{-4457.651562,6823.225,152}},{"challenge_02_spawn_05",{-4501.414062,6729.3125,152}},{"challenge_02_spawn_06",{-4457.651562,6635.4,152}},{"challenge_02_spawn_07",{-4352,6596.5,152}},{"challenge_02_spawn_08",{-4246.348437,6635.4,152}}}},
    {id="training_03", origin={-4352,4480,128}, surface=128, clear={850.78125,869.53125}, bounds={{-4970.464407,3897.221773,2},{-3742.048821,5154.976753,587.01572}}, markers={{"challenge_03_entry",{-4352,4908.125,152}},{"challenge_03_home",{-4352,4831.5625,152}},{"challenge_03_spawn_01",{-4202.585937,4425.3125,152}},{"challenge_03_spawn_02",{-4246.348437,4519.225,152}},{"challenge_03_spawn_03",{-4352,4558.125,152}},{"challenge_03_spawn_04",{-4457.651562,4519.225,152}},{"challenge_03_spawn_05",{-4501.414062,4425.3125,152}},{"challenge_03_spawn_06",{-4457.651562,4331.4,152}},{"challenge_03_spawn_07",{-4352,4292.5,152}},{"challenge_03_spawn_08",{-4246.348437,4331.4,152}}}},
    {id="training_04", origin={-6656,4480,128}, surface=128, clear={850.78125,869.53125}, bounds={{-7274.464407,3897.221773,2},{-6046.048821,5154.976753,587.01572}}, markers={{"challenge_04_entry",{-6656,4908.125,152}},{"challenge_04_home",{-6656,4831.5625,152}},{"challenge_04_spawn_01",{-6506.585937,4425.3125,152}},{"challenge_04_spawn_02",{-6550.348437,4519.225,152}},{"challenge_04_spawn_03",{-6656,4558.125,152}},{"challenge_04_spawn_04",{-6761.651562,4519.225,152}},{"challenge_04_spawn_05",{-6805.414062,4425.3125,152}},{"challenge_04_spawn_06",{-6761.651562,4331.4,152}},{"challenge_04_spawn_07",{-6656,4292.5,152}},{"challenge_04_spawn_08",{-6550.348437,4331.4,152}}}},
    {id="training_07", origin={-6656,-4480,128}, surface=128, clear={850.78125,869.53125}, bounds={{-7313.483472,-5117.923106,2},{-6015.617461,-3871.037941,533.799246}}, markers={{"challenge_07_entry",{-6656,-4051.875,152}},{"challenge_07_home",{-6656,-4128.4375,152}},{"challenge_07_boss_spawn",{-6656,-4534.6875,152}},{"challenge_07_spawn_01",{-6495.599609,-4534.6875,152}},{"challenge_07_spawn_02",{-6526.233447,-4450.882031,152}},{"challenge_07_spawn_03",{-6606.433643,-4399.0875,152}},{"challenge_07_spawn_04",{-6705.566357,-4399.0875,152}},{"challenge_07_spawn_05",{-6785.766553,-4450.882031,152}},{"challenge_07_spawn_06",{-6816.400391,-4534.6875,152}},{"challenge_07_spawn_07",{-6785.766553,-4618.492969,152}},{"challenge_07_spawn_08",{-6705.566357,-4670.2875,152}},{"challenge_07_spawn_09",{-6606.433643,-4670.2875,152}},{"challenge_07_spawn_10",{-6526.233447,-4618.492969,152}}}},
    {id="training_08", origin={-6656,-6784,128}, surface=128, clear={850.78125,869.53125}, bounds={{-7313.483472,-7421.923106,2},{-6015.617461,-6175.037941,533.799246}}, markers={{"challenge_08_entry",{-6656,-6355.875,152}},{"challenge_08_home",{-6656,-6432.4375,152}},{"challenge_08_boss_spawn",{-6656,-6838.6875,152}},{"challenge_08_spawn_01",{-6495.599609,-6838.6875,152}},{"challenge_08_spawn_02",{-6526.233447,-6754.882031,152}},{"challenge_08_spawn_03",{-6606.433643,-6703.0875,152}},{"challenge_08_spawn_04",{-6705.566357,-6703.0875,152}},{"challenge_08_spawn_05",{-6785.766553,-6754.882031,152}},{"challenge_08_spawn_06",{-6816.400391,-6838.6875,152}},{"challenge_08_spawn_07",{-6785.766553,-6922.492969,152}},{"challenge_08_spawn_08",{-6705.566357,-6974.2875,152}},{"challenge_08_spawn_09",{-6606.433643,-6974.2875,152}},{"challenge_08_spawn_10",{-6526.233447,-6922.492969,152}}}},
    {id="rebirth_01", origin={7168,-3072,16}, surface=30, clear={936,486}, bounds={{6667.999969,-3347.000061,16},{7668.000031,-2796.999939,50}}, markers={{"rebirth_01_entry",{6868,-3072,54}},{"rebirth_01_boss_spawn",{7468,-3072,54}},{"ascension_arena_01_center",{7168,-3072,54}}}},
    {id="rebirth_02", origin={7168,-5120,16}, surface=44, clear={933,483}, bounds={{6667.999969,-5395.000061,16},{7668.000031,-4844.999939,64}}, markers={{"rebirth_02_entry",{6868,-5120,68}},{"rebirth_02_boss_spawn",{7468,-5120,68}},{"ascension_arena_02_center",{7168,-5120,68}}}},
    {id="rebirth_03", origin={7168,-7168,16}, surface=58, clear={930,480}, bounds={{6667.999969,-7443.000061,16},{7668.000031,-6892.999939,78}}, markers={{"rebirth_03_entry",{6868,-7168,82}},{"rebirth_03_boss_spawn",{7468,-7168,82}},{"ascension_arena_03_center",{7168,-7168,82}}}},
    {id="rebirth_04", origin={5120,-3072,16}, surface=72, clear={927,477}, bounds={{4619.999969,-3347.000061,16},{5620.000031,-2796.999939,90.5}}, markers={{"rebirth_04_entry",{4820,-3072,96}},{"rebirth_04_boss_spawn",{5420,-3072,96}},{"ascension_arena_04_center",{5120,-3072,96}}}},
    {id="rebirth_05", origin={5120,-5120,16}, surface=86, clear={924,474}, bounds={{4619.999969,-5395.000061,16},{5620.000031,-4844.999939,104.5}}, markers={{"rebirth_05_entry",{4820,-5120,110}},{"rebirth_05_boss_spawn",{5420,-5120,110}},{"ascension_arena_05_center",{5120,-5120,110}}}},
    {id="rebirth_06", origin={5120,-7168,16}, surface=100, clear={921,471}, bounds={{4619.999969,-7443.000061,16},{5620.000031,-6892.999939,118.5}}, markers={{"rebirth_06_entry",{4820,-7168,124}},{"rebirth_06_boss_spawn",{5420,-7168,124}},{"ascension_arena_06_center",{5120,-7168,124}}}},
    {id="rebirth_07", origin={3072,-3072,16}, surface=114, clear={918,468}, bounds={{2571.999969,-3347.000061,16},{3572.000031,-2796.999939,145}}, markers={{"rebirth_07_entry",{2772,-3072,138}},{"rebirth_07_boss_spawn",{3372,-3072,138}},{"ascension_arena_07_center",{3072,-3072,138}}}},
    {id="rebirth_08", origin={3072,-5120,16}, surface=128, clear={915,465}, bounds={{2572.872192,-5394.131775,16},{3570.99939,-4845.949036,140.5}}, markers={{"rebirth_08_entry",{2772,-5120,152}},{"rebirth_08_boss_spawn",{3372,-5120,152}},{"ascension_arena_08_center",{3072,-5120,152}}}},
    {id="rebirth_09", origin={3072,-7168,16}, surface=142, clear={912,462}, bounds={{2572.872192,-7442.131775,16},{3570.99939,-6893.949036,160}}, markers={{"rebirth_09_entry",{2772,-7168,166}},{"rebirth_09_boss_spawn",{3372,-7168,166}},{"ascension_arena_09_center",{3072,-7168,166}}}},
    {id="rebirth_10", origin={1024,-5120,16}, surface=156, clear={909,459}, bounds={{524.872192,-5394.131775,16},{1522.99939,-4845.949036,174}}, markers={{"rebirth_10_entry",{724,-5120,180}},{"rebirth_10_boss_spawn",{1324,-5120,180}},{"ascension_arena_10_center",{1024,-5120,180}}}},
    {id="ten_realm_01", origin={7168,7168,58}, surface=58, clear={612,612}, bounds={{6605.982787,6605.758329,-66.347666},{7734.562654,7733.330801,300}}, markers={{"challenge_11_stage_01_entry",{7168,6934,82}},{"challenge_11_stage_01_spawn",{7168,7402,82}},{"ten_realm_arena_01_center",{7168,7168,82}}}},
    {id="ten_realm_02", origin={7168,5120,58}, surface=58, clear={612,612}, bounds={{6602.219853,4556.553308,-66.310776},{7731.713623,5679.412138,310}}, markers={{"challenge_11_stage_02_entry",{7168,4886,82}},{"challenge_11_stage_02_spawn",{7168,5354,82}},{"ten_realm_arena_02_center",{7168,5120,82}}}},
    {id="ten_realm_03", origin={7168,3072,58}, surface=58, clear={612,612}, bounds={{6604.85729,2512.20472,-66.448226},{7732.461869,3636.427039,304}}, markers={{"challenge_11_stage_03_entry",{7168,2838,82}},{"challenge_11_stage_03_spawn",{7168,3306,82}},{"ten_realm_arena_03_center",{7168,3072,82}}}},
    {id="ten_realm_04", origin={5120,7168,58}, surface=58, clear={612,612}, bounds={{4556.859462,6603.308891,-66.498508},{5686.565716,7730.574677,234.005066}}, markers={{"challenge_11_stage_04_entry",{5120,6934,82}},{"challenge_11_stage_04_spawn",{5120,7402,82}},{"ten_realm_arena_04_center",{5120,7168,82}}}},
    {id="ten_realm_05", origin={5120,5120,58}, surface=58, clear={612,612}, bounds={{4554.535475,4557.484793,-66.460104},{5681.212005,5686.488242,314}}, markers={{"challenge_11_stage_05_entry",{5120,4886,82}},{"challenge_11_stage_05_spawn",{5120,5354,82}},{"ten_realm_arena_05_center",{5120,5120,82}}}},
    {id="ten_realm_06", origin={5120,3072,58}, surface=58, clear={612,612}, bounds={{4559.585153,2508.541371,-66.334493},{5684.142987,3636.498776,305}}, markers={{"challenge_11_stage_06_entry",{5120,2838,82}},{"challenge_11_stage_06_spawn",{5120,3306,82}},{"ten_realm_arena_06_center",{5120,3072,82}}}},
    {id="ten_realm_07", origin={3072,7168,58}, surface=58, clear={612,612}, bounds={{2507.764176,6602.389889,-66.343189},{3634.865391,7731.939184,221}}, markers={{"challenge_11_stage_07_entry",{3072,6934,82}},{"challenge_11_stage_07_spawn",{3072,7402,82}},{"ten_realm_arena_07_center",{3072,7168,82}}}},
    {id="ten_realm_08", origin={3072,5120,58}, surface=58, clear={612,612}, bounds={{2508.84532,4557.422052,-66.461484},{3636.333627,5686.906117,221}}, markers={{"challenge_11_stage_08_entry",{3072,4886,82}},{"challenge_11_stage_08_spawn",{3072,5354,82}},{"ten_realm_arena_08_center",{3072,5120,82}}}},
    {id="ten_realm_09", origin={3072,3072,58}, surface=58, clear={612,612}, bounds={{2507.911045,2506.198933,-66.492565},{3635.009022,3633.70321,305}}, markers={{"challenge_11_stage_09_entry",{3072,2838,82}},{"challenge_11_stage_09_spawn",{3072,3306,82}},{"ten_realm_arena_09_center",{3072,3072,82}}}},
    {id="ten_realm_10", origin={1024,5120,58}, surface=58, clear={612,612}, bounds={{460.558759,4558.538669,-66.434982},{1586.462593,5685.926299,310}}, markers={{"challenge_11_stage_10_entry",{1024,4886,82}},{"challenge_11_stage_10_spawn",{1024,5354,82}},{"ten_realm_arena_10_center",{1024,5120,82}}}},
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
