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
        -- Bladeform Legacy ("尊享·剑心之遗"), Origins/phase 2.
        use_asset_body_model = true,
        body_model = "models/heroes/juggernaut/juggernaut_arcana.vmdl",
        body_skin = 0,
        hide_default_wearables = true,
        wearables = {
            { id = "arms", model = "models/items/juggernaut/armor_for_the_favorite_arms/armor_for_the_favorite_arms.vmdl" },
            { id = "back", model = "models/items/juggernaut/armor_for_the_favorite_back/armor_for_the_favorite_back.vmdl" },
            { id = "head", model = "models/items/juggernaut/armor_for_the_favorite_head/armor_for_the_favorite_head.vmdl" },
            { id = "legs", model = "models/items/juggernaut/armor_for_the_favorite_legs/armor_for_the_favorite_legs.vmdl" },
            { id = "weapon", model = "models/items/juggernaut/fall20_juggernaut_katz_weapon/fall20_juggernaut_katz_weapon.vmdl", skin = 1 },
        },
        particles = {
            { id = "arcana_ambient", path = "particles/econ/items/juggernaut/jugg_arcana/juggernaut_arcana_ambient.vpcf", attach_type = "PATTACH_ABSORIGIN_FOLLOW" },
        },
        spawn_particles = {
            { id = "arcana_spawn_model", path = "particles/econ/items/juggernaut/jugg_arcana/juggernaut_arcana_loadout_spawn_model.vpcf", attach_type = "PATTACH_ABSORIGIN_FOLLOW" },
            { id = "arcana_spawn_model_2", path = "particles/econ/items/juggernaut/jugg_arcana/juggernaut_arcana_loadout_spawn_model.vpcf", attach_type = "PATTACH_ABSORIGIN_FOLLOW" },
            { id = "arcana_spawn_model_3", path = "particles/econ/items/juggernaut/jugg_arcana/juggernaut_arcana_loadout_spawn_model.vpcf", attach_type = "PATTACH_ABSORIGIN_FOLLOW" },
            { id = "arcana_spawn_model_4", path = "particles/econ/items/juggernaut/jugg_arcana/juggernaut_arcana_loadout_spawn_model.vpcf", attach_type = "PATTACH_ABSORIGIN_FOLLOW" },
        },
        activity_modifiers = {
            { modifier_name = "arcana" },
        },
    },
}

return M
