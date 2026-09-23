-- Approved V4, 128 x 128 native tiles. Central art retained at (-1024,4096).
return {
    map_name = "template_map",
    center = { x = -1024, y = 4096, z = 4 },
    build_bounds = { min_x = -4096, max_x = 2048, min_y = 1024, max_y = 7168 },
    resource_tree = { x = 646, y = 5462, z = 400 },
    -- Engine IDs 0..3 correspond to UI player1..4, NW/NE/SW/SE.
    player_training_markers = {
        [0] = "player_0_training_entry", [1] = "player_1_training_entry",
        [2] = "player_2_training_entry", [3] = "player_3_training_entry",
    },
    -- Room service prefixes challenge_01..04 markers with player_N_.
    player_training_order = { "wood", "gold", "attribute", "greater_attribute" },
    player_endless_markers = {
        [0] = "player_0_endless_cycle_sanctum_entry",
        [1] = "player_1_endless_cycle_sanctum_entry",
        [2] = "player_2_endless_cycle_sanctum_entry",
        [3] = "player_3_endless_cycle_sanctum_entry",
    },
    -- Map contracts for the two alternating four-lane continents. Spawn and
    -- field center share Y/Z; gate markers identify the opening for walls.
    mode_region_prefixes = {
        snow = "v4_northeast_field_",
        radiant = "v4_southwest_a_field_",
        radiant_cross = "v4_southwest_b_field_",
        dire = "v4_northwest_field_",
        east = "v4_east_mode_field_",
    },
}
