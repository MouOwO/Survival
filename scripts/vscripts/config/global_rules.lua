local generated = require("config/generated/global_rules")

local M = {}

function M.number(rule_id, fallback)
    local row = (generated.by_id or {})[rule_id]
    if not row or row.enabled == false then return fallback end
    local value = tonumber(row.value)
    return value ~= nil and value or fallback
end

M.tower_attack_range = M.number("tower_attack_range", 1000)
M.tower_acquisition_range = M.number(
    "tower_acquisition_range",
    M.tower_attack_range
)
M.tower_base_projectile_speed = M.number(
    "tower_base_projectile_speed",
    5000
)
M.tower_route_default_projectile_speed = M.number(
    "tower_route_default_projectile_speed",
    1250
)
M.tower_class_max_count = M.number("tower_class_max_count", 5)
M.tower_projectile_speed_multiplier = M.number(
    "tower_projectile_speed_multiplier",
    1
)
M.wave_monster_round_robin_enabled = M.number(
    "wave_monster_round_robin_enabled",
    1
)
M.wave_ground_monster_hull_radius = M.number(
    "wave_ground_monster_hull_radius",
    32
)
M.wall_engagement_slot_count = M.number("wall_engagement_slot_count", 4)
M.wall_engagement_slot_spacing = M.number("wall_engagement_slot_spacing", 40)
M.wall_engagement_normal_offset = M.number("wall_engagement_normal_offset", 144)
M.wall_engagement_arrival_distance = M.number("wall_engagement_arrival_distance", 24)
M.wall_engagement_departure_distance = M.number("wall_engagement_departure_distance", 48)
M.wall_engagement_queue_spacing = M.number("wall_engagement_queue_spacing", 120)
M.wall_engagement_debug_enabled = M.number("wall_engagement_debug_enabled", 0)
M.wall_engagement_debug_z_offset = M.number("wall_engagement_debug_z_offset", 96)
M.wall_engagement_debug_duration = M.number("wall_engagement_debug_duration", 0.6)
M.wall_collision_barrier_count = M.number("wall_collision_barrier_count", 3)
M.wall_collision_barrier_spacing = M.number("wall_collision_barrier_spacing", 80)
M.wall_collision_barrier_hull_radius = M.number("wall_collision_barrier_hull_radius", 32)
M.wall_collision_normal_offset = M.number("wall_collision_normal_offset", 288)
M.wall_collision_offset_x = M.number("wall_collision_offset_x", 0)
M.wall_collision_offset_y = M.number("wall_collision_offset_y", 0)
M.wall_collision_up_offset_x = M.number("wall_collision_up_offset_x", 0)
M.wall_collision_up_offset_y = M.number("wall_collision_up_offset_y", 0)
M.wall_collision_down_offset_x = M.number("wall_collision_down_offset_x", 0)
M.wall_collision_down_offset_y = M.number("wall_collision_down_offset_y", 0)
M.wall_collision_left_offset_x = M.number("wall_collision_left_offset_x", 0)
M.wall_collision_left_offset_y = M.number("wall_collision_left_offset_y", 0)
M.wall_collision_right_offset_x = M.number("wall_collision_right_offset_x", 0)
M.wall_collision_right_offset_y = M.number("wall_collision_right_offset_y", 0)
M.repair_detection_range = M.number(
    "repair_detection_range",
    FIND_UNITS_EVERYWHERE or 99999
)
M.building_challenge_hull_radius = M.number(
    "building_challenge_hull_radius",
    0
)
M.building_challenge_lifetime_seconds = M.number(
    "building_challenge_lifetime_seconds",
    60
)
M.building_challenge_wall_failure_health_pct = M.number(
    "building_challenge_wall_failure_health_pct",
    50
)
M.building_challenge_failure_check_interval_seconds = M.number(
    "building_challenge_failure_check_interval_seconds",
    0.1
)
--M.dev_wall_health = M.number("dev_wall_health", 10000000)
--M.dev_wall_war3_armor = M.number("dev_wall_war3_armor", 1000)

return M