local M = {
    builder_undying = {
        -- The Hallows Within Bundle (21800): hero wearable 14963.
        -- Valve packages the visible hero transformation as one oversized
        -- Head-slot wearable rather than separate armor/arms/weapon pieces.
        hide_default_wearables = true,
        wearables = {
            {
                id = "hallows_head",
                model = "models/items/undying/undying_fall20_immortal_head/undying_fall20_immortal_head.vmdl",
            },
        },
        particles = {
            {
                id = "hallows_head_ambient",
                path = "particles/econ/items/undying/fall20_undying_head/fall20_undying_head_ambient.vpcf",
                owner = "hallows_head",
                attach_type = "PATTACH_ABSORIGIN_FOLLOW",
            },
        },
        -- Recorded but intentionally not applied in this task:
        -- Tombstone item 14994 uses undying_fall20_immortal_tombstone.vmdl,
        -- undying_fall20_immortal_minion.vmdl and
        -- fall20_undying_tombstone_ambient.vpcf.
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
        material_group = "1",
        hide_default_wearables = false,
        wearables = {
            "models/items/monkey_king/monkey_king_immortal_weapon/monkey_king_immortal_weapon.vmdl",
        },
    },
    hero_blademaster = {
        material_group = "1",
        hide_default_wearables = true,
        wearables = {
            "models/items/sven/gaze_cyclopean_marauder/gaze_cyclopean_marauder.vmdl",
            "models/items/sven/pauldron_cyclopean_marauder/pauldron_cyclopean_marauder.vmdl",
            "models/items/sven/gauntlet_cyclopean_marauder/gauntlet_cyclopean_marauder.vmdl",
            "models/items/sven/fauld_cyclopean_marauder/fauld_cyclopean_marauder.vmdl",
            "models/items/sven/greatsword_cyclopean_marauder/greatsword_cyclopean_marauder.vmdl",
        },
    },
}

return M
