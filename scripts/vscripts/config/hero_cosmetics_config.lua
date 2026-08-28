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
        material_group = "1",
        hide_default_wearables = true,
        wearables = {
            "models/items/axe/searing_annihilator_head/searing_annihilator_head.vmdl",
            "models/items/axe/searing_annihilator_armor/searing_annihilator_armor.vmdl",
            "models/items/axe/searing_annihilator_weapon/searing_annihilator_weapon.vmdl",
            "models/items/axe/searing_annihilator_belt/searing_annihilator_belt.vmdl",
            "models/items/axe/searing_annihilator_arms/searing_annihilator_arms.vmdl",
        },
    },
    hero_slark = {
        material_group = "1",
        hide_default_wearables = true,
        wearables = {
            "models/items/slark/dark_reef_head/dark_reef_head.vmdl",
            "models/items/slark/dark_reef_back/dark_reef_back.vmdl",
            "models/items/slark/dark_reef_arms/dark_reef_arms.vmdl",
            "models/items/slark/dark_reef_shoulders/dark_reef_shoulders.vmdl",
            "models/items/slark/dark_reef_weapon/dark_reef_weapon.vmdl",
        },
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
        hide_default_wearables = false,
        wearables = {},
        particles = {},
    },
}

return M
