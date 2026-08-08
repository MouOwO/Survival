local sounds = require("core/sound_service")

local M = {}

local ROUTE_NAMES = {
    class_1 = "death",
    class_2 = "mystery",
    class_3 = "lightning",
    class_4 = "machine_gun",
    class_5 = "multi",
    class_6 = "frost",
    class_7 = "magic",
}

local STRUCTURE_BUILDINGS = {
    wall = true,
    main_city = true,
    hero_altar = true,
}

local function valid_entity(unit)
    if not unit then return false end
    if unit.IsNull then
        local ok, is_null = pcall(function() return unit:IsNull() end)
        if not ok or is_null then return false end
    end
    return true
end

local function play(cue_id, unit, team)
    if not valid_entity(unit) then return false, "invalid_building" end
    return sounds.play(cue_id, {
        unit = unit,
        source = unit,
        limiter_scope = "team:" .. tostring(team or "unknown"),
    })
end

local function play_for_unit(cue_id, unit)
    if not valid_entity(unit) then return false, "invalid_building" end
    return sounds.play(cue_id, {
        unit = unit,
        source = unit,
    })
end

function M.construction_started(unit, team)
    return play("building_construction_start", unit, team)
end

function M.construction_completed(unit, team)
    return play("building_construction_complete", unit, team)
end

function M.wall_damaged(unit)
    return play_for_unit("building_wall_damage", unit)
end

function M.upgrade_completed(options)
    options = options or {}
    local building_id = tostring(options.building_id or "")
    if building_id ~= "arrow_tower" then
        local cue_id = STRUCTURE_BUILDINGS[building_id]
            and "building_structure_upgrade_complete"
            or "building_standard_upgrade_complete"
        return play(cue_id, options.unit, options.team)
    end

    local tower_class = tostring(options.tower_class or "")
    local route_name = ROUTE_NAMES[tower_class]
    if not route_name then
        return play("tower_base_upgrade_complete", options.unit, options.team)
    end
    local suffix = (options.class_changed or options.stage_changed)
        and "_major_upgrade_complete" or "_upgrade_complete"
    return play("tower_" .. route_name .. suffix, options.unit, options.team)
end

M._route_names_for_test = ROUTE_NAMES

return M