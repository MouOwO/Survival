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
        -- Cult of the Demon Trickster (21425): armor 13008, head 13544,
        -- shoulder 13545 and weapon 13546. Use the base style assets only;
        -- the Wukong's Command replacements belong to ability cosmetics.
        material_group = "1",
        hide_default_wearables = true,
        wearables = {
            {
                id = "demon_trickster_armor",
                model = "models/items/monkey_king/mk_ti9_immortal_armor/mk_ti9_immortal_armor.vmdl",
            },
            {
                id = "demon_trickster_mask",
                model = "models/items/monkey_king/mk_ti9_immortal_head/mk_ti9_immortal_head.vmdl",
            },
            {
                id = "demon_trickster_shoulders",
                model = "models/items/monkey_king/mk_ti9_immortal_shoulder/mk_ti9_immortal_shoulder.vmdl",
            },
            {
                id = "demon_trickster_staff",
                model = "models/items/monkey_king/mk_ti9_immortal_weapon/mk_ti9_immortal_weapon.vmdl",
            },
        },
        particles = {
            {
                id = "demon_trickster_armor_ambient",
                path = "particles/econ/items/monkey_king/mk_ti9_immortal/mk_ti9_immortal_armor_ambient.vpcf",
                owner = "demon_trickster_armor",
                attach_type = "PATTACH_ABSORIGIN_FOLLOW",
            },
            {
                id = "demon_trickster_mask_ambient",
                path = "particles/econ/items/monkey_king/mk_ti9_immortal/mk_ti9_immortal_head_ambient.vpcf",
                owner = "demon_trickster_mask",
                attach_type = "PATTACH_ABSORIGIN_FOLLOW",
            },
            {
                id = "demon_trickster_shoulders_ambient",
                path = "particles/econ/items/monkey_king/mk_ti9_immortal/mk_ti9_immortal_shoulders_ambient.vpcf",
                owner = "demon_trickster_shoulders",
                attach_type = "PATTACH_ABSORIGIN_FOLLOW",
            },
            {
                id = "demon_trickster_staff_ambient",
                path = "particles/econ/items/monkey_king/mk_ti9_immortal/mk_ti9_immortal_weapon_ambient.vpcf",
                owner = "demon_trickster_staff",
                attach_type = "PATTACH_ABSORIGIN_FOLLOW",
            },
        },
    },
    hero_blademaster = {
        body_model = "models/heroes/juggernaut/juggernaut_arcana.vmdl",
        body_skin = 0,
        hide_default_wearables = true,
        wearables = {},
    },
}

return M
