// Compact purple commerce presentation. Catalog and checkout stay in their controllers.
(function () {
    "use strict";
    var cfg=GameUI.CustomUIConfig(),U=cfg.SurvivalUI,J={},activeDetail=null;
    function valid(p){return p&&(!p.IsValid||p.IsValid());}
    function panel(type,parent,cls){var p=$.CreatePanel(type,parent,"");if(cls)cls.split(/\s+/).forEach(function(c){p.AddClass(c);});return p;}
    function box(p,x,y,w,h){p.style.position=x+"px "+y+"px 0px";p.style.width=w+"px";p.style.height=h+"px";return p;}
    function label(parent,value,cls){var p=panel("Label",parent,cls);p.text=String(value===undefined?"":value);p.hittest=false;return p;}
    function original(parent,uri,cls){
        var p=panel("Image",parent,cls);
        var resolved=J.NormalizeIconURI(uri);if(resolved)p.SetImage(resolved);
        p.SetScaling("stretch-to-fit-preserve-aspect");p.hittest=false;p.hittestchildren=false;return p;
    }
    J.Box=box;J.Label=label;
    // BEGIN GENERATED COMMERCE PRODUCT ART V1
    // Source: data/ui/commerce_product_art_v1.json; SHA256 92ec02af5914bd45eda74991baa8cb451ab275e228bd1d4f84f60b5cd467bfbe
    var productArt={
        "archive_pass_monthly":{"item_id":"daily_wealth_talisman","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/daily_wealth_talisman.vtex","legacy_icons":["custom_game/reward_art_v5/daily_wealth_talisman.png"]},
        "gold_100_test_50_v3":{"item_id":"lottery_wealth_crystal","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_wealth_crystal.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_wealth_crystal.png","custom_game/reward_art_v5/lottery_wealth_crystal.png"]},
        "special_lottery_ticket_single":{"item_id":"special_lottery_ticket","runtime_uri":"s2r://panorama/images/custom_game/lottery_handoff_v1/ticket_illustrated_png.vtex","legacy_icons":["custom_game/lottery_handoff_v1/ticket_illustrated.png"]},
        "starter_bundle_v4":{"item_id":"commerce_gift_bundle","runtime_uri":"s2r://panorama/images/custom_game/commerce_jade_v1/gift_light_png.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png"]},
        "tower_attack_100_test_50_v3":{"item_id":"lottery_sharp_spirit","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_sharp_spirit.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_sharp_spirit.png","custom_game/reward_art_v5/lottery_sharp_spirit.png"]},
        "video_bundle_b001":{"item_id":"commerce_gift_bundle","runtime_uri":"s2r://panorama/images/custom_game/commerce_jade_v1/gift_light_png.vtex","legacy_icons":["custom_game/commerce_jade_v1/gift_light.png"]},
        "video_bundle_b002":{"item_id":"commerce_gift_bundle","runtime_uri":"s2r://panorama/images/custom_game/commerce_jade_v1/gift_light_png.vtex","legacy_icons":["custom_game/commerce_jade_v1/gift_light.png"]},
        "video_bundle_b003":{"item_id":"commerce_gift_bundle","runtime_uri":"s2r://panorama/images/custom_game/commerce_jade_v1/gift_light_png.vtex","legacy_icons":["custom_game/commerce_jade_v1/gift_light.png"]},
        "video_bundle_b004":{"item_id":"commerce_gift_bundle","runtime_uri":"s2r://panorama/images/custom_game/commerce_jade_v1/gift_light_png.vtex","legacy_icons":["custom_game/commerce_jade_v1/gift_light.png"]},
        "video_bundle_b005":{"item_id":"commerce_gift_bundle","runtime_uri":"s2r://panorama/images/custom_game/commerce_jade_v1/gift_light_png.vtex","legacy_icons":["custom_game/commerce_jade_v1/gift_light.png"]},
        "video_bundle_vip_01":{"item_id":"commerce_gift_bundle","runtime_uri":"s2r://panorama/images/custom_game/commerce_jade_v1/gift_light_png.vtex","legacy_icons":["custom_game/commerce_jade_v1/gift_light.png"]},
        "video_bundle_vip_02":{"item_id":"commerce_gift_bundle","runtime_uri":"s2r://panorama/images/custom_game/commerce_jade_v1/gift_light_png.vtex","legacy_icons":["custom_game/commerce_jade_v1/gift_light.png"]},
        "video_bundle_vip_03":{"item_id":"commerce_gift_bundle","runtime_uri":"s2r://panorama/images/custom_game/commerce_jade_v1/gift_light_png.vtex","legacy_icons":["custom_game/commerce_jade_v1/gift_light.png"]},
        "video_bundle_vip_04":{"item_id":"commerce_gift_bundle","runtime_uri":"s2r://panorama/images/custom_game/commerce_jade_v1/gift_light_png.vtex","legacy_icons":["custom_game/commerce_jade_v1/gift_light.png"]},
        "video_bundle_vip_05":{"item_id":"commerce_gift_bundle","runtime_uri":"s2r://panorama/images/custom_game/commerce_jade_v1/gift_light_png.vtex","legacy_icons":["custom_game/commerce_jade_v1/gift_light.png"]},
        "video_bundle_vip_06":{"item_id":"commerce_gift_bundle","runtime_uri":"s2r://panorama/images/custom_game/commerce_jade_v1/gift_light_png.vtex","legacy_icons":["custom_game/commerce_jade_v1/gift_light.png"]},
        "video_bundle_vip_07":{"item_id":"commerce_gift_bundle","runtime_uri":"s2r://panorama/images/custom_game/commerce_jade_v1/gift_light_png.vtex","legacy_icons":["custom_game/commerce_jade_v1/gift_light.png"]},
        "video_bundle_vip_08":{"item_id":"commerce_gift_bundle","runtime_uri":"s2r://panorama/images/custom_game/commerce_jade_v1/gift_light_png.vtex","legacy_icons":["custom_game/commerce_jade_v1/gift_light.png"]},
        "video_bundle_vip_09":{"item_id":"commerce_gift_bundle","runtime_uri":"s2r://panorama/images/custom_game/commerce_jade_v1/gift_light_png.vtex","legacy_icons":["custom_game/commerce_jade_v1/gift_light.png"]},
        "video_bundle_vip_10":{"item_id":"commerce_gift_bundle","runtime_uri":"s2r://panorama/images/custom_game/commerce_jade_v1/gift_light_png.vtex","legacy_icons":["custom_game/commerce_jade_v1/gift_light.png"]},
        "video_p001":{"item_id":"special_lottery_ticket","runtime_uri":"s2r://panorama/images/custom_game/lottery_handoff_v1/ticket_illustrated_png.vtex","legacy_icons":["custom_game/lottery_handoff_v1/ticket_illustrated.png"]},
        "video_p004":{"item_id":"native_null_talisman","runtime_uri":"file://{images}/items/null_talisman.png","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","items/null_talisman.png"]},
        "video_p005":{"item_id":"native_tpscroll","runtime_uri":"file://{images}/items/tpscroll.png","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","items/tpscroll.png"]},
        "video_p011":{"item_id":"native_orb_of_venom","runtime_uri":"file://{images}/items/orb_of_venom.png","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","items/orb_of_venom.png"]},
        "video_p012":{"item_id":"native_juggernaut_blade_fury","runtime_uri":"file://{images}/spellicons/juggernaut_blade_fury.png","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","spellicons/juggernaut_blade_fury.png"]},
        "video_p013":{"item_id":"native_meteor_hammer","runtime_uri":"file://{images}/items/meteor_hammer.png","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","items/meteor_hammer.png"]},
        "video_p014":{"item_id":"native_platemail","runtime_uri":"file://{images}/items/platemail.png","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","items/platemail.png"]},
        "video_p015":{"item_id":"native_bfury","runtime_uri":"file://{images}/items/bfury.png","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","items/bfury.png"]},
        "video_p016":{"item_id":"commerce_titan_shield","runtime_uri":"s2r://panorama/images/custom_game/commerce_art_v1/titan_shield.vtex","legacy_icons":["custom_game/reward_art_v5/lottery_dimensional_barrier.png","s2r://panorama/images/custom_game/reward_art_v5/lottery_dimensional_barrier.vtex"]},
        "video_p017":{"item_id":"native_ogre_axe","runtime_uri":"file://{images}/items/ogre_axe.png","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","items/ogre_axe.png"]},
        "video_p018":{"item_id":"native_faceless_void_time_lock","runtime_uri":"file://{images}/spellicons/faceless_void_time_lock.png","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","spellicons/faceless_void_time_lock.png"]},
        "video_p019":{"item_id":"native_bloodthorn","runtime_uri":"file://{images}/items/bloodthorn.png","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","items/bloodthorn.png"]},
        "video_p020":{"item_id":"native_shredder_whirling_death","runtime_uri":"file://{images}/spellicons/shredder_whirling_death.png","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","spellicons/shredder_whirling_death.png"]},
        "video_p021":{"item_id":"native_armlet","runtime_uri":"file://{images}/items/armlet.png","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","items/armlet.png"]},
        "video_p022":{"item_id":"native_shredder_timber_chain","runtime_uri":"file://{images}/spellicons/shredder_timber_chain.png","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","spellicons/shredder_timber_chain.png"]},
        "video_p023":{"item_id":"native_relic","runtime_uri":"file://{images}/items/relic.png","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","items/relic.png"]},
        "video_p024":{"item_id":"native_recipe","runtime_uri":"file://{images}/items/recipe.png","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","items/recipe.png"]},
        "video_p025":{"item_id":"native_philosophers_stone","runtime_uri":"file://{images}/items/philosophers_stone.png","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","items/philosophers_stone.png"]},
        "video_p026":{"item_id":"native_blink","runtime_uri":"file://{images}/items/blink.png","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","items/blink.png"]},
        "video_p027":{"item_id":"native_assault","runtime_uri":"file://{images}/items/assault.png","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","items/assault.png"]},
        "video_p028":{"item_id":"commerce_master_foreman","runtime_uri":"s2r://panorama/images/custom_game/commerce_art_v1/master_foreman.vtex","legacy_icons":["custom_game/reward_art_v5/lottery_seed_of_all_wood.png","s2r://panorama/images/custom_game/reward_art_v5/lottery_seed_of_all_wood.vtex"]},
        "video_p029":{"item_id":"native_alchemist_goblins_greed","runtime_uri":"file://{images}/spellicons/alchemist_goblins_greed.png","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","spellicons/alchemist_goblins_greed.png"]},
        "video_p030":{"item_id":"native_iron_talon","runtime_uri":"file://{images}/items/iron_talon.png","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","items/iron_talon.png"]},
        "video_p031":{"item_id":"native_windrunner_powershot","runtime_uri":"file://{images}/spellicons/windrunner_powershot.png","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","spellicons/windrunner_powershot.png"]},
        "video_p032":{"item_id":"native_repair_kit","runtime_uri":"file://{images}/items/repair_kit.png","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","items/repair_kit.png"]},
        "video_p033":{"item_id":"native_quelling_blade","runtime_uri":"file://{images}/items/quelling_blade.png","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","items/quelling_blade.png"]},
        "video_p037":{"item_id":"native_branches","runtime_uri":"file://{images}/items/branches.png","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","items/branches.png"]},
        "video_p038":{"item_id":"native_hand_of_midas","runtime_uri":"file://{images}/items/hand_of_midas.png","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","items/hand_of_midas.png"]},
        "video_p042":{"item_id":"lottery_muramasa","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_muramasa.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","custom_game/reward_art_v5/lottery_muramasa.png"]},
        "video_p043":{"item_id":"lottery_kings_treasure","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_kings_treasure.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","custom_game/reward_art_v5/lottery_kings_treasure.png"]},
        "video_p045":{"item_id":"lottery_raven_eye","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_raven_eye.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","custom_game/reward_art_v5/lottery_raven_eye.png"]},
        "video_p046":{"item_id":"lottery_magic_book","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_magic_book.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","custom_game/reward_art_v5/lottery_magic_book.png"]},
        "video_p048":{"item_id":"lottery_spear_of_longinus","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_spear_of_longinus.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","custom_game/reward_art_v5/lottery_spear_of_longinus.png"]},
        "video_p049":{"item_id":"lottery_withered_branch_lantern","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_withered_branch_lantern.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","custom_game/reward_art_v5/lottery_withered_branch_lantern.png"]},
        "video_p050":{"item_id":"lottery_echo_compass","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_echo_compass.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","custom_game/reward_art_v5/lottery_echo_compass.png"]},
        "video_p051":{"item_id":"lottery_rift_implant","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_rift_implant.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_rift_implant.png","custom_game/reward_art_v5/lottery_rift_implant.png"]},
        "video_p052":{"item_id":"lottery_magnetic_disruption_turret","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_magnetic_disruption_turret.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_magnetic_disruption_turret.png","custom_game/reward_art_v5/lottery_magnetic_disruption_turret.png"]},
        "video_p053":{"item_id":"lottery_pulse_conduction_turret","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_pulse_conduction_turret.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_pulse_conduction_turret.png","custom_game/reward_art_v5/lottery_pulse_conduction_turret.png"]},
        "video_p054":{"item_id":"lottery_cybernetic_implant","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_cybernetic_implant.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_cybernetic_implant.png","custom_game/reward_art_v5/lottery_cybernetic_implant.png"]},
        "video_p055":{"item_id":"lottery_crystalline_armor","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_crystalline_armor.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_crystalline_armor.png","custom_game/reward_art_v5/lottery_crystalline_armor.png"]},
        "video_p056":{"item_id":"lottery_signal_hub","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_signal_hub.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_signal_hub.png","custom_game/reward_art_v5/lottery_signal_hub.png"]},
        "video_p057":{"item_id":"lottery_data_unit","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_data_unit.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_data_unit.png","custom_game/reward_art_v5/lottery_data_unit.png"]},
        "video_p058":{"item_id":"lottery_nitride_alloy_wall","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_nitride_alloy_wall.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_nitride_alloy_wall.png","custom_game/reward_art_v5/lottery_nitride_alloy_wall.png"]},
        "video_p061":{"item_id":"lottery_orbital_cannon_core","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_orbital_cannon_core.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_orbital_cannon_core.png","custom_game/reward_art_v5/lottery_orbital_cannon_core.png"]},
        "video_p063":{"item_id":"lottery_nano_cluster","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_nano_cluster.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_nano_cluster.png","custom_game/reward_art_v5/lottery_nano_cluster.png"]},
        "video_p065":{"item_id":"lottery_dimensional_barrier","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_dimensional_barrier.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_dimensional_barrier.png","custom_game/reward_art_v5/lottery_dimensional_barrier.png"]},
        "video_p066":{"item_id":"lottery_fallen_sky_mine","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_fallen_sky_mine.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_fallen_sky_mine.png","custom_game/reward_art_v5/lottery_fallen_sky_mine.png"]},
        "video_p067":{"item_id":"lottery_mountain_sea_kunpeng","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_mountain_sea_kunpeng.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_mountain_sea_kunpeng.png","custom_game/reward_art_v5/lottery_mountain_sea_kunpeng.png"]},
        "video_p068":{"item_id":"lottery_reincarnation_immortal_stele","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_reincarnation_immortal_stele.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_reincarnation_immortal_stele.png","custom_game/reward_art_v5/lottery_reincarnation_immortal_stele.png"]},
        "video_p069":{"item_id":"lottery_emerald_wood_origin","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_emerald_wood_origin.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_emerald_wood_origin.png","custom_game/reward_art_v5/lottery_emerald_wood_origin.png"]},
        "video_p070":{"item_id":"lottery_forestcast_thousand_bolts","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_forestcast_thousand_bolts.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_forestcast_thousand_bolts.png","custom_game/reward_art_v5/lottery_forestcast_thousand_bolts.png"]},
        "video_p071":{"item_id":"lottery_woodcraft_grandmaster","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_woodcraft_grandmaster.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_woodcraft_grandmaster.png","custom_game/reward_art_v5/lottery_woodcraft_grandmaster.png"]},
        "video_p072":{"item_id":"lottery_ancient_pine_fortification","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_ancient_pine_fortification.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_ancient_pine_fortification.png","custom_game/reward_art_v5/lottery_ancient_pine_fortification.png"]},
        "video_p075":{"item_id":"lottery_immortal_slaying_sword_array","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_immortal_slaying_sword_array.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_immortal_slaying_sword_array.png","custom_game/reward_art_v5/lottery_immortal_slaying_sword_array.png"]},
        "video_p077":{"item_id":"lottery_sky_turning_seal","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_sky_turning_seal.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_sky_turning_seal.png","custom_game/reward_art_v5/lottery_sky_turning_seal.png"]},
        "video_p078":{"item_id":"lottery_immortal_nirvana","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_immortal_nirvana.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_immortal_nirvana.png","custom_game/reward_art_v5/lottery_immortal_nirvana.png"]},
        "video_p079":{"item_id":"lottery_monkey_king","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_monkey_king.vtex","legacy_icons":["custom_game/reward_art_v5/lottery_monkey_king.png"]},
        "video_p082":{"item_id":"lottery_heaven_reaching_tower_seal","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_heaven_reaching_tower_seal.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_heaven_reaching_tower_seal.png","custom_game/reward_art_v5/lottery_heaven_reaching_tower_seal.png"]},
        "video_p083":{"item_id":"lottery_sovereign_under_heaven","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_sovereign_under_heaven.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_sovereign_under_heaven.png","custom_game/reward_art_v5/lottery_sovereign_under_heaven.png"]},
        "video_p084":{"item_id":"lottery_greenwood_rampart","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_greenwood_rampart.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_greenwood_rampart.png","custom_game/reward_art_v5/lottery_greenwood_rampart.png"]},
        "video_p086":{"item_id":"lottery_greenwood_nirvana","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_greenwood_nirvana.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_greenwood_nirvana.png","custom_game/reward_art_v5/lottery_greenwood_nirvana.png"]},
        "video_p087":{"item_id":"lottery_woodforged_thousand_arrows","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_woodforged_thousand_arrows.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_woodforged_thousand_arrows.png","custom_game/reward_art_v5/lottery_woodforged_thousand_arrows.png"]},
        "video_p088":{"item_id":"lottery_lumber_expert","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_lumber_expert.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_lumber_expert.png","custom_game/reward_art_v5/lottery_lumber_expert.png"]},
        "video_p089":{"item_id":"lottery_ember_of_legacy","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_ember_of_legacy.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_ember_of_legacy.png","custom_game/reward_art_v5/lottery_ember_of_legacy.png"]},
        "video_p090":{"item_id":"lottery_flame_wall","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_flame_wall.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_flame_wall.png","custom_game/reward_art_v5/lottery_flame_wall.png"]},
        "video_p092":{"item_id":"lottery_lumber_immortal","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_lumber_immortal.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_lumber_immortal.png","custom_game/reward_art_v5/lottery_lumber_immortal.png"]},
        "video_p094":{"item_id":"lottery_endless_growth_ring","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_endless_growth_ring.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_endless_growth_ring.png","custom_game/reward_art_v5/lottery_endless_growth_ring.png"]},
        "video_p095":{"item_id":"lottery_lumber_fury","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_lumber_fury.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_lumber_fury.png","custom_game/reward_art_v5/lottery_lumber_fury.png"]},
        "video_p096":{"item_id":"lottery_supreme_fishing_rod","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_supreme_fishing_rod.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_supreme_fishing_rod.png","custom_game/reward_art_v5/lottery_supreme_fishing_rod.png"]},
        "video_p097":{"item_id":"lottery_hero_medal","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_hero_medal.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_hero_medal.png","custom_game/reward_art_v5/lottery_hero_medal.png"]},
        "video_p098":{"item_id":"lottery_sharpwood_tower_core","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_sharpwood_tower_core.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_sharpwood_tower_core.png","custom_game/reward_art_v5/lottery_sharpwood_tower_core.png"]},
        "video_p099":{"item_id":"lottery_seed_of_all_wood","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_seed_of_all_wood.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_seed_of_all_wood.png","custom_game/reward_art_v5/lottery_seed_of_all_wood.png"]},
        "video_p100":{"item_id":"lottery_oak_bulwark","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_oak_bulwark.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_oak_bulwark.png","custom_game/reward_art_v5/lottery_oak_bulwark.png"]},
        "video_p101":{"item_id":"lottery_titan_shield","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_titan_shield.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_titan_shield.png","custom_game/reward_art_v5/lottery_titan_shield.png"]},
        "video_p102":{"item_id":"lottery_omniscience_blessing","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_omniscience_blessing.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_omniscience_blessing.png","custom_game/reward_art_v5/lottery_omniscience_blessing.png"]},
        "video_p103":{"item_id":"lottery_ember_of_legacy","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_ember_of_legacy.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_ember_of_legacy.png","custom_game/reward_art_v5/lottery_ember_of_legacy.png"]},
        "video_p104":{"item_id":"lottery_soul_devouring_blade","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_soul_devouring_blade.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_soul_devouring_blade.png","custom_game/reward_art_v5/lottery_soul_devouring_blade.png"]},
        "video_p105":{"item_id":"lottery_tower_retrofit","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_tower_retrofit.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_tower_retrofit.png","custom_game/reward_art_v5/lottery_tower_retrofit.png"]},
        "video_p106":{"item_id":"lottery_steel_wall","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_steel_wall.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_steel_wall.png","custom_game/reward_art_v5/lottery_steel_wall.png"]},
        "video_p107":{"item_id":"lottery_gathering_grimoire","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_gathering_grimoire.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_gathering_grimoire.png","custom_game/reward_art_v5/lottery_gathering_grimoire.png"]},
        "video_p108":{"item_id":"lottery_time_orb","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_time_orb.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_time_orb.png","custom_game/reward_art_v5/lottery_time_orb.png"]},
        "video_p109":{"item_id":"lottery_quick_dry_cement","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_quick_dry_cement.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_quick_dry_cement.png","custom_game/reward_art_v5/lottery_quick_dry_cement.png"]},
        "video_p110":{"item_id":"commerce_swift_winch","runtime_uri":"s2r://panorama/images/custom_game/commerce_art_v1/swift_winch.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_swift_emblem.png","s2r://panorama/images/custom_game/reward_art_v5/lottery_swift_emblem.vtex","custom_game/reward_art_v5/lottery_swift_emblem.png"]},
        "video_p111":{"item_id":"lottery_gale_bow","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_gale_bow.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_gale_bow.png","custom_game/reward_art_v5/lottery_gale_bow.png"]},
        "video_p112":{"item_id":"lottery_universal_tool","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_universal_tool.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_universal_tool.png","custom_game/reward_art_v5/lottery_universal_tool.png"]},
        "video_p113":{"item_id":"lottery_life_spirit","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_life_spirit.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_life_spirit.png","custom_game/reward_art_v5/lottery_life_spirit.png"]},
        "video_p114":{"item_id":"lottery_sharp_spirit","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_sharp_spirit.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_sharp_spirit.png","custom_game/reward_art_v5/lottery_sharp_spirit.png"]},
        "video_p116":{"item_id":"lottery_recovery_spirit","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_recovery_spirit.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_recovery_spirit.png","custom_game/reward_art_v5/lottery_recovery_spirit.png"]},
        "video_p117":{"item_id":"lottery_lumber_crystal","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_lumber_crystal.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_lumber_crystal.png","custom_game/reward_art_v5/lottery_lumber_crystal.png"]},
        "video_p118":{"item_id":"lottery_wealth_crystal","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_wealth_crystal.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_wealth_crystal.png","custom_game/reward_art_v5/lottery_wealth_crystal.png"]},
        "video_p119":{"item_id":"lottery_shooting_crystal","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_shooting_crystal.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_shooting_crystal.png","custom_game/reward_art_v5/lottery_shooting_crystal.png"]},
        "video_p120":{"item_id":"lottery_nature_crystal","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_nature_crystal.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_nature_crystal.png","custom_game/reward_art_v5/lottery_nature_crystal.png"]},
        "video_p121":{"item_id":"lottery_bombardment_crystal","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_bombardment_crystal.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_bombardment_crystal.png","custom_game/reward_art_v5/lottery_bombardment_crystal.png"]},
        "video_p122":{"item_id":"lottery_resistance_crystal","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_resistance_crystal.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_resistance_crystal.png","custom_game/reward_art_v5/lottery_resistance_crystal.png"]},
        "video_p123":{"item_id":"lottery_expansion_crystal","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_expansion_crystal.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_expansion_crystal.png","custom_game/reward_art_v5/lottery_expansion_crystal.png"]},
        "video_p124":{"item_id":"lottery_protection_crystal","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_protection_crystal.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_protection_crystal.png","custom_game/reward_art_v5/lottery_protection_crystal.png"]},
        "video_p125":{"item_id":"lottery_attribute_crystal","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_attribute_crystal.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_attribute_crystal.png","custom_game/reward_art_v5/lottery_attribute_crystal.png"]},
        "video_p126":{"item_id":"lottery_recovery_crystal","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_recovery_crystal.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_recovery_crystal.png","custom_game/reward_art_v5/lottery_recovery_crystal.png"]},
        "video_p127":{"item_id":"lottery_windspeed_bowstring","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_windspeed_bowstring.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_windspeed_bowstring.png","custom_game/reward_art_v5/lottery_windspeed_bowstring.png"]},
        "video_p128":{"item_id":"lottery_darksteel_wall","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_darksteel_wall.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_darksteel_wall.png","custom_game/reward_art_v5/lottery_darksteel_wall.png"]},
        "video_p129":{"item_id":"lottery_aaron_cannon","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_aaron_cannon.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_aaron_cannon.png","custom_game/reward_art_v5/lottery_aaron_cannon.png"]},
        "video_p130":{"item_id":"lottery_gathering_divine_codex","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_gathering_divine_codex.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_gathering_divine_codex.png","custom_game/reward_art_v5/lottery_gathering_divine_codex.png"]},
        "video_p131":{"item_id":"lottery_hippogryph_onslaught","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_hippogryph_onslaught.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_hippogryph_onslaught.png","custom_game/reward_art_v5/lottery_hippogryph_onslaught.png"]},
        "video_p132":{"item_id":"lottery_lumber_legacy","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_lumber_legacy.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_lumber_legacy.png","custom_game/reward_art_v5/lottery_lumber_legacy.png"]},
        "video_p133":{"item_id":"lottery_divine_tower_blessing","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_divine_tower_blessing.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_divine_tower_blessing.png","custom_game/reward_art_v5/lottery_divine_tower_blessing.png"]},
        "video_p134":{"item_id":"lottery_reincarnation_orb","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_reincarnation_orb.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_reincarnation_orb.png","custom_game/reward_art_v5/lottery_reincarnation_orb.png"]},
        "video_p135":{"item_id":"lottery_unbreakable_fortress","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_unbreakable_fortress.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_unbreakable_fortress.png","custom_game/reward_art_v5/lottery_unbreakable_fortress.png"]},
        "video_p136":{"item_id":"lottery_abundance_blessing","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_abundance_blessing.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_abundance_blessing.png","custom_game/reward_art_v5/lottery_abundance_blessing.png"]},
        "video_p137":{"item_id":"lottery_chief_god_blessing","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_chief_god_blessing.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_chief_god_blessing.png","custom_game/reward_art_v5/lottery_chief_god_blessing.png"]},
        "video_p138":{"item_id":"lottery_chosen_hero","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_chosen_hero.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_chosen_hero.png","custom_game/reward_art_v5/lottery_chosen_hero.png"]},
        "video_p139":{"item_id":"lottery_struggle_diary","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_struggle_diary.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_struggle_diary.png","custom_game/reward_art_v5/lottery_struggle_diary.png"]},
        "video_p140":{"item_id":"lottery_nature_spirit","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_nature_spirit.vtex","legacy_icons":["custom_game/reward_art_v5/lottery_nature_spirit.png"]},
        "video_p147":{"item_id":"commerce_lament_seed","runtime_uri":"s2r://panorama/images/custom_game/commerce_art_v1/lament_seed.vtex","legacy_icons":["custom_game/reward_art_v5/lottery_seed_of_all_wood.png","s2r://panorama/images/custom_game/reward_art_v5/lottery_seed_of_all_wood.vtex"]},
        "video_p151":{"item_id":"commerce_spirit_katana","runtime_uri":"s2r://panorama/images/custom_game/commerce_art_v1/spirit_katana.vtex","legacy_icons":["custom_game/reward_art_v5/lottery_muramasa.png","s2r://panorama/images/custom_game/reward_art_v5/lottery_muramasa.vtex"]},
        "wall_armor_100_test_50_v3":{"item_id":"lottery_protection_crystal","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_protection_crystal.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_protection_crystal.png","custom_game/reward_art_v5/lottery_protection_crystal.png"]},
        "wall_health_100_test_50_v3":{"item_id":"lottery_life_spirit","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_life_spirit.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_life_spirit.png","custom_game/reward_art_v5/lottery_life_spirit.png"]},
        "wood_100_test_50_v3":{"item_id":"lottery_lumber_crystal","runtime_uri":"s2r://panorama/images/custom_game/reward_art_v5/lottery_lumber_crystal.vtex","legacy_icons":["custom_game/archive_items_v2/lottery_lumber_crystal.png","custom_game/reward_art_v5/lottery_lumber_crystal.png"]}
    };
    // END GENERATED COMMERCE PRODUCT ART V1
    // All consumers share the same constrained image namespace. No URLs,
    // traversal, encoded paths or arbitrary resource types cross this boundary.
    J.NormalizeIconURI=function(value){
        if(typeof value!=="string"||value.length>512||/\s/.test(value))return "";
        var relative=value.indexOf("file://{images}/")===0?value.substring(16):value;
        if(/^(custom_game|items|spellicons)\/(?:[A-Za-z0-9_-]+\/)*[A-Za-z0-9_-]+\.png$/.test(relative))return "file://{images}/"+relative;
        if(/^s2r:\/\/panorama\/images\/(?:[A-Za-z0-9_-]+\/)*[A-Za-z0-9_-]+\.vtex$/.test(value))return value;
        return "";
    };
    J.ProductIcon=function(item){
        if(!item)return undefined;
        var icon=item.icon,row=Object.prototype.hasOwnProperty.call(productArt,item.sku)?productArt[item.sku]:null;
        if(!row)return icon;
        var supplied=J.NormalizeIconURI(icon),expected=J.NormalizeIconURI(row.runtime_uri);
        // A new, dedicated server image stays authoritative for that product.
        // Only the reviewed legacy images of this exact SKU are replaced.
        if(supplied&&supplied!==expected&&!row.legacy_icons.some(function(uri){return J.NormalizeIconURI(uri)===supplied;}))return icon;
        var art=cfg.SurvivalItemArt,known=art&&art.Lookup?art.Lookup({item_id:row.item_id}):null;
        // A conflicting copied catalog cannot redirect an explicit SKU binding.
        // The manifest URI also works in standalone metadata/build consumers.
        if(known&&(known.item_id||known.id||known.content_id)===row.item_id&&J.NormalizeIconURI(known.runtime_uri)===expected)return known.runtime_uri;
        return row.runtime_uri;
    };
    J.Art=function(parent,file,cls){return original(parent,"custom_game/commerce_jade_v1/"+file+".png",cls);};
    J.Window=function(root,onClose){
        var scrim=panel("Button",root,"RCBackdrop"),p=panel("Panel",root,"RCWindow MenuV10Commerce");
        var menu=cfg.SurvivalMenuV10.Adopt({id:"commerce",navId:"commerce",root:root,panel:p,scrim:scrim,title:"商城",onClose:onClose});
        menu.Close();return {panel:p,scrim:scrim,shell:menu.shell,menu:menu,canvas:menu.canvas,content:menu.content,actions:menu.actions,detailLayer:menu.detailLayer};
    };
    J.Nav=function(parent,c,index,selected,fn){
        var b=box(panel("Button",parent,"RCTab CommercePurpleNav"),0,index*62,208,58);
        b.hittestchildren=false;b.SetHasClass("UISelected",selected);
        box(label(b,c.label,"RCTabText"),12,0,182,58);b.SetPanelEvent("onactivate",fn);return b;
    };
    J.Action=function(parent,value,fn,cls){
        var b=panel("Button",parent,"CJBuy CommercePurpleBuy"+(cls?" "+cls:""));
        label(b,value,"");
        b.hittestchildren=false;b.SetPanelEvent("onactivate",function(){if(valid(b)&&b.enabled!==false&&fn)fn();return true;});return b;
    };
    J.Price=function(parent,item,x,y,w){
        var p=box(panel("Panel",parent,"CJPrice"),x,y,w||272,36),row=panel("Panel",p,"CJPriceRow");
        var wallet=item.purchase_method==="wallet",currency=wallet?item.currency_name:"元",amount=wallet?item.price:(item.amount_fen/100).toFixed(2);
        var isU=item.currency==="u_coin" || item.u_coin_price!==undefined || item.u_coin_per_yuan!==undefined;
        var fen=item.amount_fen,uCoin=item.u_coin_price;
        var validU=isU && item.disabled_reason!=="payment_price_unavailable" && typeof uCoin==="number" && uCoin>0 && uCoin%1===0 && item.u_coin_per_yuan===1000 && typeof fen==="number" && fen>0 && fen<=1000000 && fen%1===0 && uCoin===fen*10;
        var paidMeta=item.u_coin_price!==undefined || item.u_coin_per_yuan!==undefined || fen!==undefined || item.disabled_reason==="payment_price_unavailable";
        var previewCoin=!paidMeta && typeof item.price==="number" && item.price>0 && item.price%1===0?item.price:null;
        if(wallet || isU){
            var uri=item.currency==="shop_points"?"custom_game/commerce_jade_v1/crystal.png":"custom_game/commerce_jade_v1/coin.png";
            original(row,uri,"CJPriceIcon");
        }else label(row,"¥","CJYuanIcon");
        var uText=validU?uCoin+" U币 / ¥"+(fen/100).toFixed(2):(previewCoin!==null?previewCoin+" U币":"U币价格待同步")+" / 人民币金额待同步";
        label(row,isU?uText:amount+" "+currency,"CJPriceValue");p.hittest=false;p.hittestchildren=false;return p;
    };
    function detailQuality(item, rewards) {
        var art=cfg.SurvivalItemArt;
        function quality(row){var value=String(row&&row.quality||"").toUpperCase();return /^(N|R|SR|SSR|UR)$/.test(value)?value:"";}
        function lookup(value){return art&&art.Lookup?art.Lookup(value):null;}
        var value=quality(item)||quality(lookup(item));
        if(value)return value;
        if(item.product_type==="bundle")return "";
        var items=(rewards||[]).filter(function(row){return row.kind==="item";});
        if(items.length===1){value=quality(lookup({item_id:items[0].id}));if(value)return value;}
        var match=/^custom_game\/archive_items_v2\/(lottery_[a-z0-9_]+)\.png$/.exec(String(item.icon||""));
        var row=match&&lookup({item_id:match[1]});
        var name=String(item.title||"").replace(/\s*[·•]\s*永久\s*$/,"");
        return row&&row.display_name===name?quality(row):"";
    }
    function detail(card,item,props,bundle){
        var layer=valid(props.detailLayer)?props.detailLayer:card;
        var tip=panel("Panel",layer,"RCPurpleDetail MenuV10CommerceDetail");tip.hittest=false;tip.hittestchildren=false;
        var skin=cfg.SurvivalMenuV10.SkinTooltip(tip),body=panel("Panel",skin.surface,"MenuV10CommerceDetailBody");
        tip.__purpleSource=card;
        tip.style.position="202px 0px 0px";tip.style.width="312px";
        label(body,item.title,"RCPurpleDetailTitle");
        label(body,"品级："+(detailQuality(item,props.rewards)||"未配置"),"RCPurpleDetailQuality");
        var summary=props.effect||item.description||"";
        if(bundle&&(props.rewards||[]).length)summary=props.rewards.map(function(reward){
            return reward.description?(reward.label?reward.label+"：":"")+reward.description
                :String(reward.label||reward.id||"")+" ×"+String(reward.quantity===undefined?1:reward.quantity);
        }).join("\n");
        var effect=label(body,summary,"RCProductEffect");effect.visible=!!effect.text;
        var positionJob=null,serial=0,disposed=false,dismiss=null;
        function cancel(){serial++;if(positionJob!==null&&$.CancelScheduled)$.CancelScheduled(positionJob);positionJob=null;}
        function hide(){cancel();if(dismiss)dismiss.Hidden();if(valid(tip)){tip.RemoveClass("Visible");tip.hittest=false;tip.hittestchildren=false;}if(valid(card)){card.RemoveClass("ShopSelected");card.style.zIndex="0";}if(activeDetail&&activeDetail.tip===tip)activeDetail=null;}
        function dispose(){if(disposed)return;hide();disposed=true;if(dismiss)dismiss.Dispose();if(valid(tip))tip.DeleteAsync(0);}
        function tooltipRect(node){var at=node.GetPositionWithinWindow(),scale=props.menu?props.menu.Scale():1;return {x:at.x,y:at.y,width:node.actuallayoutwidth*scale,height:node.actuallayoutheight*scale};}
        function guard(){
            if(!dismiss&&cfg.SurvivalTooltipDismiss)dismiss=cfg.SurvivalTooltipDismiss.Create({
                panel:tip,surface:skin.surface,getRect:tooltipRect,hide:hide,
                isAlive:function(){return !disposed&&valid(card)&&valid(tip)&&valid(layer);},
                isVisible:function(){return tip.BHasClass("Visible");}
            });
            return dismiss;
        }
        function place(){
            if(disposed)return;
            if(!valid(card)||!valid(tip)||!valid(layer)){dispose();return;}
            if(!card.GetPositionWithinWindow)return;
            var source=card.GetPositionWithinWindow(),root=card;
            while(valid(root)&&root.GetParent&&valid(root.GetParent()))root=root.GetParent();
            var width=Number(root.actuallayoutwidth)||1920,height=Number(root.actuallayoutheight)||1080;
            var origin=layer.GetPositionWithinWindow(),menu=props.menu;
            var scale=Math.max(.001,(Number(layer.actualuiscale_x)||1)*(menu?menu.Scale():1));
            var nativeScale=Math.max(.001,Number(layer.actualuiscale_y)||1);
            var logicalHeight=Math.min(704,Math.max(96,(Number(body.actuallayoutheight)||80*nativeScale)/nativeScale+88));
            skin.Resize(368,logicalHeight);tip.style.width="368px";tip.style.height=logicalHeight+"px";
            var sw=144*scale,tw=368*scale,th=logicalHeight*scale;
            // Native paints the owned layer inside its window despite overflow:noclip.
            // Keep the complete detail in both that clip and the viewport safety area.
            var pad=12*scale,leftEdge=pad,rightEdge=width-pad,topEdge=pad,bottomEdge=height-pad;
            var clip=valid(props.detailLayer)&&layer.GetParent?layer.GetParent():null;
            if(valid(clip)){
                var clipOrigin=clip.GetPositionWithinWindow(),cw=1672*scale,ch=941*scale;
                leftEdge=Math.max(leftEdge,clipOrigin.x+pad);rightEdge=Math.min(rightEdge,clipOrigin.x+cw-pad);
                topEdge=Math.max(topEdge,clipOrigin.y+pad);bottomEdge=Math.min(bottomEdge,clipOrigin.y+ch-pad);
            }
            var x=source.x+sw+pad;
            if(x+tw>rightEdge)x=source.x-tw-pad;
            x=Math.max(leftEdge,Math.min(x,rightEdge-tw));
            var y=Math.max(topEdge,Math.min(source.y,bottomEdge-th));
            if(!isFinite(x)||!isFinite(y)||!isFinite(origin.x)||!isFinite(origin.y))return;
            tip.style.position=Math.round((x-origin.x)/scale)+"px "+Math.round((y-origin.y)/scale)+"px 0px";
        }
        function show(){
            if(disposed)return;
            if(!valid(card)||!valid(tip)||!valid(layer)){dispose();return;}
            var policy=guard();if(policy&&!policy.CanShow(card))return;
            if(activeDetail&&activeDetail.tip!==tip)activeDetail.hide();
            cancel();activeDetail={tip:tip,hide:hide};
            tip.AddClass("Visible");card.AddClass("ShopSelected");card.style.zIndex="30";
            tip.hittest=false;tip.hittestchildren=false;skin.surface.hittest=false;skin.surface.hittestchildren=false;
            place();if(policy)policy.Shown(card);
            var epoch=serial;
            positionJob=$.Schedule(0,function(){positionJob=null;if(epoch===serial&&!disposed&&valid(tip)&&activeDetail&&activeDetail.tip===tip&&tip.BHasClass("Visible"))place();});
        }
        function leave(){if(dismiss)dismiss.Dismiss();else hide();}
        card.SetPanelEvent("onmouseover",show);card.SetPanelEvent("onmouseout",leave);
        card.SetPanelEvent("onactivate",function(){show();if(!props.market&&props.action)props.action();return true;});
        tip.SetPanelEvent("onmouseover",leave);
        card.__purpleDetail=tip;card.__purpleHide=hide;card.__purpleShow=show;
        card.__purpleDispose=dispose;tip.__purpleDispose=dispose;
        card.__purpleRebuildDetail=function(){if(disposed&&valid(card)&&valid(layer))return detail(card,item,props,bundle);return valid(tip)?tip:null;};
        return tip;
    }
    function compactCard(parent,item,props,bundle){
        props=props||{};var card=U.CardShell(parent,{bodyVariant:"product"});
        card.AddClass("RCProduct");card.AddClass(bundle?"CJBundle":"CJProduct");card.AddClass("CommercePurpleProduct");
        var well=box(panel("Panel",card,"CommercePurpleArtWell"),12,9,120,120);
        box(original(well,J.ProductIcon(item),"RCProductArt"),0,0,120,120);
        var caption=box(label(card,String(item.title||item.sku||"").replace(/\s*[·•]\s*永久\s*$/,""),"RCProductName"),7,134,130,35);
        var owned=Number(item.owned)>0?label(card,String(item.owned),"RCStockState"):null;
        card.__menuCell={iconPanel:well,namePanel:caption,countPanel:owned};
        detail(card,item,props,bundle);return card;
    }
    J.BindDetail=detail;
    J.Product=function(parent,item,props){return compactCard(parent,item,props,false);};
    J.Bundle=function(parent,item,props){return compactCard(parent,item,props,true);};
    cfg.SurvivalCommerceComponents=J;
})();
