local M = {
    builder_undying = {
        -- Keep the native Undying body and wearables visible. The previous
        -- oversized Head prop could remain visible while the body failed to
        -- render, making the builder appear to be an attacking floating crown.
        hide_default_wearables = false,
        wearables = {},
        particles = {},
    },
    hero_axe = {
        hide_default_wearables = true,
    },
    hero_drow_ranger = {
        hide_default_wearables = true,
    },
    hero_juggernaut = {
        material_group = "1",
        hide_default_wearables = true,
        wearables = {
            "models/items/juggernaut/wandering_demon_mask/wandering_demon_mask.vmdl",
            "models/items/juggernaut/wandering_demon_arms/wandering_demon_arms.vmdl",
            "models/items/juggernaut/wandering_demon_top/wandering_demon_top.vmdl",
            "models/items/juggernaut/wandering_demon_legs/wandering_demon_legs.vmdl",
            "models/items/juggernaut/wandering_demon_sword/wandering_demon_sword.vmdl",
        },
    },
    hero_monkey_king = {
        use_asset_body_model = true,
        hide_default_wearables = true,
        particles = {},
    },
    hero_blademaster = {
        use_asset_body_model = true,
        body_skin = 1,
        hide_default_wearables = true,
    },
}

return M
