-- Existing right-middle V4 mode court; no new map geometry or fishing NPC.
return {
    markers = { "v4_east_mode_entry", "v4_east_mode_field_1_center" },
    fallback = { x = 12416, y = -3072, z = 152 },
    -- Separate bounded landing patches keep all four players apart, including
    -- when a blocked point needs one of the nearby navigation-safe samples.
    player_offsets = {
        [0] = { x = -256, y = 192 },
        [1] = { x = 256, y = 192 },
        [2] = { x = -256, y = -192 },
        [3] = { x = 256, y = -192 },
    },
    samples = {
        { 0, 0 }, { 64, 0 }, { -64, 0 }, { 0, 64 }, { 0, -64 },
        { 64, 64 }, { -64, 64 }, { 64, -64 }, { -64, -64 },
    },
}
