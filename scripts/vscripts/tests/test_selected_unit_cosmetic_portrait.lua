package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local event_bus = require("core/event_bus")
local events = require("core/events")
local asset_catalog = require("config/asset_catalog")
local listeners = {}
local sent = {}
local hero_result = { ok = false }

package.loaded["systems/building_system"] = {}
package.loaded["ui/weapon_synthesis_snapshot_service"] = {}
package.loaded["core/scheduler"] = {
    after = function() end,
}

local unit = {
    survival_model_asset_id = "tower_multi_vengeful_shen_screeauk",
    survival_display_name = "炙热巨箭塔LV1",
    survival_level = 1,
    survival_attack_min = 308001,
    survival_attack_max = 308001,
    survival_attack_speed = 1,
}
function unit:IsNull() return false end
function unit:entindex() return 701 end
function unit:GetUnitName() return "building_arrow_tower" end
function unit:GetHealth() return 1000 end
function unit:GetMaxHealth() return 1000 end
function unit:GetMana() return 0 end
function unit:GetMaxMana() return 0 end
function unit:GetPhysicalArmorValue() return 0 end
function unit:GetAttackSpeed() return 100 end

PlayerResource = {
    IsValidPlayerID = function(_, player_id) return player_id == 0 end,
    GetPlayer = function(_, player_id)
        return player_id == 0 and { player_id = 0 } or nil
    end,
}
CustomGameEventManager = {
    RegisterListener = function(_, event_name, handler)
        listeners[event_name] = handler
    end,
    Send_ServerToPlayer = function(_, _, event_name, payload)
        sent[#sent + 1] = { event_name = event_name, payload = payload }
    end,
}
local units_by_entindex = { [701] = unit }
EntIndexToHScript = function(entindex) return units_by_entindex[entindex] end

event_bus.reset()
event_bus.handle_request(events.HERO_COMBAT_STATS_GET_REQUEST, function()
    return hero_result
end)

package.loaded["ui/ui_request_router"] = nil
local router = require("ui/ui_request_router")
router.init()
assert(listeners.ui_selected_unit_stats_request,
    "selected-unit request listener was not registered")
listeners.ui_selected_unit_stats_request(0, {
    PlayerID = 0,
    entindex = 701,
})

assert(#sent == 1, "selected cosmetic tower snapshot was not sent")
local snapshot = sent[1].payload
assert(snapshot.model_asset_id == "tower_multi_vengeful_shen_screeauk",
    "selected snapshot omitted the current model asset ID")
local initial_tower_asset = assert(asset_catalog.get(
    "tower_multi_vengeful_shen_screeauk"
))
assert(snapshot.portrait_unit_name == initial_tower_asset.portrait_unit_name
        and snapshot.portrait_item_def == (initial_tower_asset.portrait_item_def or ""),
    "selected native tower snapshot omitted CSV portrait metadata")

local tower_assets = {}
for _, stage in ipairs(asset_catalog.native_wearable_stages or {}) do
    tower_assets[#tower_assets + 1] = stage.asset_id
end
assert(#tower_assets == 21, "CSV native wearable stage count changed")
for _, asset_id in ipairs(tower_assets) do
    unit.survival_model_asset_id = asset_id
    local expected_asset = assert(asset_catalog.get(asset_id))
    sent = {}
    listeners.ui_selected_unit_stats_request(0, {
        PlayerID = 0,
        entindex = 701,
    })
    assert(sent[1].payload.model_asset_id == asset_id
            and sent[1].payload.portrait_unit_name
                == expected_asset.portrait_unit_name
            and sent[1].payload.portrait_item_def
                == (expected_asset.portrait_item_def or ""),
        "native tower snapshot omitted CSV portrait metadata: " .. asset_id)
end

unit.survival_model_asset_id = "tower_death_templar_assassin"
unit.survival_display_name = "【N】死亡之塔LV1"
unit.survival_level = 6
unit.survival_route_level = 1
unit.survival_tower_class = "class_1"
unit.survival_attack_min = 801
unit.survival_attack_max = 801
sent = {}
event_bus.emit(events.BUILDING_CHANGED, {
    player_id = 0,
    entindex = 701,
    display_name = "【N】死亡之塔LV1",
    level = 6,
    absolute_level = 6,
    route_level = 1,
    tower_class = "class_1",
    attack_min = 801,
    attack_max = 801,
    attack_speed = 1,
    reason = "tower_class_changed",
})
assert(#sent == 1
        and sent[1].event_name == "ui_selected_unit_stats_snapshot",
    "selected tower class change did not push an immediate snapshot")
assert(sent[1].payload.display_name == "【N】死亡之塔LV1"
        and sent[1].payload.level == 6
        and sent[1].payload.absolute_level == 6
        and sent[1].payload.route_level == 1
        and sent[1].payload.tower_class == "class_1",
    "selected tower class change did not publish the Death Tower name and level")
assert(sent[1].payload.attack_min == 801
        and sent[1].payload.attack_max == 801,
    "Death Tower name refresh changed its configured attack values")

local hero_portraits = {
    { "hero_doom" },
    { "hero_shadow_fiend" },
    { "hero_axe" },
    { "hero_drow_ranger" },
    { "hero_monkey_king" },
}
for _, expected in ipairs(hero_portraits) do
    local metadata = router._test.apply_portrait_metadata({
        survival_hero_id = expected[1],
    }, {})
    assert(metadata.model_asset_id == "hero_permanent_" .. expected[1]
            and metadata.portrait_unit_name == ""
            and metadata.portrait_item_def == "",
        "ordinary hero received custom portrait metadata: " .. expected[1])
end

local split_blademaster = router._test.apply_portrait_metadata({
    survival_hero_id = "hero_blademaster",
}, {})
assert(split_blademaster.model_asset_id == "hero_permanent_hero_blademaster"
        and split_blademaster.portrait_unit_name == "npc_dota_hero_juggernaut"
        and split_blademaster.portrait_item_def == "",
    "Blademaster world cosmetics leaked into the selected-unit portrait")

local explicit_asset = router._test.apply_portrait_metadata({
    survival_model_asset_id = "tower_death_templar_assassin",
    survival_hero_id = "hero_axe",
}, {})
assert(explicit_asset.model_asset_id == "tower_death_templar_assassin"
        and explicit_asset.portrait_unit_name == "npc_dota_hero_templar_assassin"
        and explicit_asset.portrait_item_def == "",
    "explicit model asset did not take precedence over the hero fallback")

local boss_asset = router._test.apply_portrait_metadata({
    survival_monster_default_wearable_asset_id = "monster_boss_ten_sin_06_abscession",
}, {})
assert(boss_asset.model_asset_id == "monster_boss_ten_sin_06_abscession"
        and boss_asset.portrait_unit_name == "npc_dota_hero_pudge"
        and boss_asset.portrait_item_def == "",
    "Boss world appearance did not publish its independent base portrait")

local wave_portraits = 0
for _, row in ipairs(require("config/generated/monster_archetypes").rows) do
    local id = tostring(row.default_wearable_asset_id or "")
    if id:match("^monster_wave_") then
        wave_portraits = wave_portraits + 1
        local metadata = router._test.apply_portrait_metadata({
            survival_monster_default_wearable_asset_id = id,
        }, {})
        assert(metadata.model_asset_id == id
            and metadata.portrait_unit_name:match("^npc_dota_hero_")
            and metadata.portrait_item_def == "",
            "wave outfit must publish the base hero portrait: " .. id)
    end
end

assert(wave_portraits == 39, "expected all 39 wave portraits")
print("WAVE_PORTRAIT_METADATA_PASS count=" .. wave_portraits)

local snapshot_fallback = router._test.apply_portrait_metadata({
    survival_model_asset_id = "missing_asset",
}, { hero_id = "hero_axe" })
assert(snapshot_fallback.model_asset_id == "hero_permanent_hero_axe"
        and snapshot_fallback.portrait_unit_name == ""
        and snapshot_fallback.portrait_item_def == "",
    "authoritative snapshot hero ID incorrectly enabled custom portrait")

local missing_asset = router._test.apply_portrait_metadata({
    survival_model_asset_id = "missing_asset",
}, {
    model_asset_id = "stale",
    portrait_unit_name = "stale",
    portrait_item_def = "stale",
})
assert(missing_asset.model_asset_id == ""
        and missing_asset.portrait_unit_name == ""
        and missing_asset.portrait_item_def == "",
    "missing portrait assets did not fail closed to empty strings")

local fake_monkey = router._test.apply_portrait_metadata({}, {})
assert(fake_monkey.model_asset_id == ""
        and fake_monkey.portrait_unit_name == ""
        and fake_monkey.portrait_item_def == "",
    "an unmarked unit incorrectly inherited Monkey King portrait metadata")
local monkey_clone = router._test.apply_portrait_metadata({
    survival_monkey_king_clone = true,
}, {})
assert(monkey_clone.model_asset_id == "hero_permanent_hero_monkey_king"
        and monkey_clone.portrait_unit_name == ""
        and monkey_clone.portrait_item_def == "",
    "Monkey King clone incorrectly enabled custom portrait metadata")

local function make_unit(entindex, unit_name)
    local candidate = {
        survival_display_name = unit_name,
        survival_attack_min = 100,
        survival_attack_max = 100,
        survival_attack_speed = 1,
    }
    function candidate:IsNull() return false end
    function candidate:entindex() return entindex end
    function candidate:GetUnitName() return unit_name end
    function candidate:GetHealth() return 1000 end
    function candidate:GetMaxHealth() return 1000 end
    function candidate:GetMana() return 100 end
    function candidate:GetMaxMana() return 100 end
    function candidate:GetPhysicalArmorValue() return 0 end
    function candidate:GetAttackSpeed() return 100 end
    function candidate:GetPlayerOwnerID() return 0 end
    return candidate
end

local function hero_snapshot(hero_id, entindex)
    return {
        player_id = 0,
        hero_id = hero_id,
        entindex = entindex,
        unit_name = "npc_dota_hero_axe",
        display_name = "斧王",
        attack_min = 100,
        attack_max = 100,
        attack_speed = 1,
        runtime_armor = 0,
        strength = 10,
        agility = 10,
        intellect = 10,
        refresh_version = 1,
    }
end

local function request_snapshot(candidate)
    units_by_entindex[candidate:entindex()] = candidate
    sent = {}
    listeners.ui_selected_unit_stats_request(0, {
        PlayerID = 0,
        entindex = candidate:entindex(),
    })
    assert(#sent == 1, "selected-unit request did not send exactly one snapshot")
    return sent[1].payload
end

local hero = make_unit(702, "npc_dota_hero_axe")
hero_result = { ok = true, snapshot = hero_snapshot("hero_axe", 702) }
local hero_ui = request_snapshot(hero)
assert(hero_ui.model_asset_id == "hero_permanent_hero_axe"
        and hero_ui.portrait_unit_name == ""
        and hero_ui.portrait_item_def == "",
    "ordinary hero snapshot incorrectly enabled custom portrait metadata")

sent = {}
event_bus.emit(events.HERO_COMBAT_STATS_CHANGED, {
    player_id = 0,
    snapshot = hero_snapshot("hero_axe", 702),
    reason = "portrait_metadata_test",
})
assert(#sent == 1
        and sent[1].payload.model_asset_id == "hero_permanent_hero_axe"
        and sent[1].payload.portrait_unit_name == ""
        and sent[1].payload.portrait_item_def == "",
    "ordinary hero combat-stat push incorrectly enabled custom portrait metadata")

local blademaster = make_unit(706, "npc_dota_hero_juggernaut")
hero_result = {
    ok = true,
    snapshot = hero_snapshot("hero_blademaster", 706),
}
local blademaster_ui = request_snapshot(blademaster)
assert(blademaster_ui.model_asset_id == "hero_permanent_hero_blademaster"
        and blademaster_ui.portrait_unit_name == "npc_dota_hero_juggernaut"
        and blademaster_ui.portrait_item_def == "",
    "Blademaster did not split its decorated world body from the base portrait")

local clone = make_unit(703, "npc_dota_hero_monkey_king")
clone.survival_monkey_king_clone = true
clone.survival_display_name = "混沌神猿分身"
hero_result = {
    ok = true,
    snapshot = hero_snapshot("hero_monkey_king", 799),
}
local clone_ui = request_snapshot(clone)
assert(clone_ui.entindex == 703
        and clone_ui.model_asset_id == "hero_permanent_hero_monkey_king"
        and clone_ui.portrait_unit_name == ""
        and clone_ui.portrait_item_def == "",
    "Monkey King clone incorrectly enabled custom portrait metadata")

local unmarked_monkey = make_unit(704, "npc_dota_hero_monkey_king")
hero_result = { ok = false }
local unmarked_ui = request_snapshot(unmarked_monkey)
assert(unmarked_ui.model_asset_id == ""
        and unmarked_ui.portrait_unit_name == ""
        and unmarked_ui.portrait_item_def == "",
    "Monkey King unit name bypassed strict clone identity")

local unknown = make_unit(705, "npc_survival_unknown")
unknown.survival_model_asset_id = "missing_asset"
local unknown_ui = request_snapshot(unknown)
assert(unknown_ui.model_asset_id == ""
        and unknown_ui.portrait_unit_name == ""
        and unknown_ui.portrait_item_def == "",
    "selected fallback unit published stale portrait metadata")

local portrait_source = assert(io.open(
    "../../../content/dota_addons/survival/panorama/scripts/custom_game/combat_stats.js",
    "rb"
)):read("*a")
assert(portrait_source:find("/^(tower_|monster_boss_|monster_wave_|monster_archive_|hero_permanent_hero_blademaster$)/", 1, true), "wave portraits excluded by client")
assert(portrait_source:find("function updateCosmeticPortrait", 1, true)
        and portrait_source:find("snapshot && snapshot.portrait_unit_name", 1, true)
        and portrait_source:find("isTowerPortrait", 1, true)
        and portrait_source:find("/^npc_dota_hero_/.test", 1, true)
        and portrait_source:find("SurvivalTowerPortraitOverlay", 1, true)
        and portrait_source:find("SurvivalTowerPortraitScene", 1, true)
        and portrait_source:find(
            'SetUnit(portraitUnit, "default", false)', 1, true
        )
        and portrait_source:find("portraitItemDef", 1, true)
        and portrait_source:find("scene_failed", 1, true)
        and portrait_source:find("function restoreNativePortraitsExcept(anchor)", 1, true)
        and portrait_source:find("function restoreNativePortraitOpacity()", 1, true)
        and portrait_source:find(
            "function nativePortraitScenePanel(container, root, depth)", 1, true
        )
        and portrait_source:find(
            "function mountTowerPortraitAtNativeLayer(overlay, anchor)", 1, true
        )
        and portrait_source:find("overlay.SetParent(host)", 1, true)
        and portrait_source:find("host.MoveChildAfter(overlay, anchor)", 1, true)
        and portrait_source:find("function restoreTowerPortraitHome(overlay)", 1, true)
        and portrait_source:find("function unitUsesTowerPortrait(unit)", 1, true)
        and portrait_source:find(
            'unitName === "npc_dota_hero_juggernaut"', 1, true
        )
        and portrait_source:find("hero_permanent_hero_blademaster$", 1, true)
        and portrait_source:find('=== "ability_destroy_arrow_tower"', 1, true)
        and portrait_source:find("function holdTowerPortraitTransition(reason)", 1, true)
        and portrait_source:find("var activePortraitEntity = -1;", 1, true)
        and portrait_source:find("function towerPortraitEntityUnchanged(unit)", 1, true)
        and portrait_source:find(
            "if (towerPortraitEntityUnchanged(Number(displayUnit()))) return;", 1, true
        )
        and portrait_source:find(
            "activePortraitEntity = Number(snapshot.entindex);", 1, true
        )
        and portrait_source:find(
            'transitionCosmeticPortrait("selection_transition")', 1, true
        )
        and portrait_source:find(
            'transitionCosmeticPortrait("snapshot_pending")', 1, true
        )
        and portrait_source:find("var TOWER_PORTRAIT_CONTENT_SCALE = 0.90;", 1, true)
        and portrait_source:find("function applyTowerPortraitContentScale(scene)", 1, true)
        and portrait_source:find("function resetTowerPortraitContentScale(scene)", 1, true)
        and portrait_source:find('scene.style.transformOrigin = "50% 50%"', 1, true)
        and portrait_source:find("applyTowerPortraitContentScale(scene);", 1, true)
        and portrait_source:find("resetTowerPortraitContentScale(scene);", 1, true)
        and portrait_source:find('hideCosmeticPortrait("context_shutdown")', 1, true)
        and portrait_source:find("var portraitMode = \"tower_scene\"", 1, true)
        and portrait_source:find("|| !isTowerPortrait", 1, true)
        and portrait_source:find(
            "Number(snapshot.entindex) !== Number(displayUnit())", 1, true
        ),
    "selected-unit portrait lacks CSV tower scene or current-unit gates")
local _, set_unit_count = portrait_source:gsub(
    'scene%.SetUnit%(portraitUnit, "default", false%)', ""
)
assert(set_unit_count == 1
        and portrait_source:find("if (activePortraitKey !== portraitKey)", 1, true),
    "tower ScenePanel SetUnit must remain identity-gated and unique")
assert(not portrait_source:find("isVideoPortrait", 1, true)
        and not portrait_source:find("isImagePortrait", 1, true)
        and not portrait_source:find("SurvivalHeroPortraitMovie", 1, true)
        and not portrait_source:find("SurvivalHeroPortraitImage", 1, true)
        and not portrait_source:find("SurvivalNativePortraitVideoOverlay", 1, true),
    "non-tower portrait mode still has a custom runtime path")
assert(not portrait_source:find("portraitCache", 1, true)
        and not portrait_source:find("showNativePortrait", 1, true),
    "selected-unit portrait still depends on the removed legacy cache")
assert(portrait_source:find("survival_dump_cursor_entities", 1, true)
        and portrait_source:find(
            "GameUI.FindScreenEntities(cursor[0], cursor[1])",
            1,
            true
        ),
    "cursor picking diagnostics are unavailable")

local function read_all(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

local selection_source = read_all(
    "../../../content/dota_addons/survival/panorama/scripts/custom_game/ui_bootstrap.js"
)
assert(selection_source:find('var displayIdentityMode = "selection"', 1, true)
        and selection_source:find("selectionIdentityLockUntil", 1, true)
        and selection_source:find("now + 250", 1, true)
        and selection_source:find(
            'mode === "query" && now < selectionIdentityLockUntil', 1, true
        )
        and selection_source:find("SetDisplayIdentityMode", 1, true)
        and selection_source:find('displayIdentityMode === "query"', 1, true)
        and selection_source:find("if (selected.length > 0) return selected[0]", 1, true)
        and portrait_source:find(
            'reason === "query_unit_event" ? "query" : "selection"', 1, true
        ),
    "display unit resolver can retain a stale portrait after a real selection change")

local hud_source = read_all(
    "../../../content/dota_addons/survival/panorama/layout/custom_game/survival_hud.xml"
)
local overlay_start = assert(hud_source:find(
    '<Panel id="SurvivalTowerPortraitOverlay"', 1, true
), "HUD layout is missing the independent tower portrait overlay")
local scene_start = assert(hud_source:find(
    '<DOTAScenePanel id="SurvivalTowerPortraitScene"', overlay_start, true
), "HUD layout is missing the dynamic tower portrait ScenePanel")
local legacy_hud_start = assert(hud_source:find(
    '<Panel id="SurvivalHeroBottomHUD"', 1, true
), "HUD layout is missing the legacy bottom HUD rollback tree")
local scene_count = 0
for _ in hud_source:gmatch("<DOTAScenePanel[%s>]" ) do
    scene_count = scene_count + 1
end
assert(scene_start < legacy_hud_start
        and scene_count == 1
        and not hud_source:find("<MoviePanel", 1, true)
        and not hud_source:find("SurvivalHeroPortraitImage", 1, true)
        and not hud_source:find("SurvivalNativePortraitVideoOverlay", 1, true),
    "non-tower custom portrait controls remain in the HUD layout")
assert(not hud_source:find("DOTAUnitImage", 1, true)
        and not hud_source:find("SurvivalHeroPortraitCache", 1, true),
    "HUD layout still contains an unsupported control or portrait cache")
assert(portrait_source:find('"PortraitGroup"', 1, true)
        and portrait_source:find("GetPositionWithinWindow", 1, true)
        and portrait_source:find("layer.actualuiscale_x", 1, true)
        and portrait_source:find("anchor.actuallayoutwidth", 1, true)
        and portrait_source:find(
            'transitionCosmeticPortrait("selected_unit_changed")', 1, true
        )
        and portrait_source:find("scheduleActive(0.10, cosmeticPortraitSentinel)", 1, true),
    "portrait overlay lacks Valve anchor geometry or HUD rebuild handling")
assert(not portrait_source:find('anchor.style.visibility = "collapse"', 1, true)
        and portrait_source:find('anchor.style.opacity = "0"', 1, true)
        and not portrait_source:find('anchor.style.width =', 1, true)
        and not portrait_source:find('anchor.style.height =', 1, true)
        and not portrait_source:find('anchor.style.transform =', 1, true),
    "tower portrait must only make the native Scene transparent before same-layer replacement")

local generated_catalog = read_all(
    "scripts/vscripts/config/generated/asset_catalog.lua"
)
local monkey_generated_row = assert(generated_catalog:match(
    '[^\r\n]+asset_id = "hero_permanent_hero_monkey_king"[^\r\n]+'
), "generated Monkey King asset catalog row is missing")
local monkey_cosmetic_models = {
    "models/items/monkey_king/mk_ti9_immortal_armor/mk_ti9_immortal_armor.vmdl",
    "models/items/monkey_king/monkey_king_arcana_head/mesh/monkey_king_arcana.vmdl",
    "models/items/monkey_king/mk_ti9_immortal_shoulder/mk_ti9_immortal_shoulder.vmdl",
    "models/items/monkey_king/mk_ti9_immortal_weapon/mk_ti9_immortal_weapon.vmdl",
}
for _, model_path in ipairs(monkey_cosmetic_models) do
    assert(monkey_generated_row:find(model_path, 1, true),
        "generated Monkey King bundle omitted requested model " .. model_path)
end
assert(monkey_generated_row:find(
        'portrait_unit_name = "npc_dota_hero_monkey_king"', 1, true)
        and not monkey_generated_row:find("portrait_item_def", 1, true)
        and monkey_generated_row:find("particle_resources", 1, true),
    "generated Monkey King bundle lacks requested cosmetics or base portrait split")

local blademaster_generated_row = assert(generated_catalog:match(
    '[^\r\n]+asset_id = "hero_permanent_hero_blademaster"[^\r\n]+'
), "generated Blademaster asset catalog row is missing")
assert(blademaster_generated_row:find(
        'primary_model = "models/heroes/juggernaut/juggernaut_arcana.vmdl"', 1, true)
        and blademaster_generated_row:find("model_skin = 1", 1, true)
        and blademaster_generated_row:find(
            "juggernaut_arcana_v2_body_ambient.vpcf", 1, true)
        and blademaster_generated_row:find(
            'portrait_unit_name = "npc_dota_hero_juggernaut"', 1, true)
        and not blademaster_generated_row:find("portrait_item_def", 1, true),
    "generated Blademaster bundle lacks red Arcana body or base portrait split")

local generated_components = read_all(
    "scripts/vscripts/config/generated/asset_components.lua"
)
local generated_effects = read_all(
    "scripts/vscripts/config/generated/asset_effects.lua"
)
for _, model_path in ipairs(monkey_cosmetic_models) do
    assert(generated_components:find(model_path, 1, true),
        "generated Monkey King components omitted requested model " .. model_path)
end
assert(generated_effects:find('asset_id = "hero_permanent_hero_monkey_king"', 1, true),
    "generated Monkey King effects are missing")
assert(not generated_components:find("ancient_exile_arms_arcana.vmdl", 1, true)
        and not generated_components:find("generic_wep_broadsword.vmdl", 1, true)
        and not generated_effects:find("ancient_exile_red_head_ambient.vpcf", 1, true)
        and not generated_effects:find("jugg_weapon_glow_variation_script.vpcf", 1, true),
    "Blademaster still contains removed cosmetic components or effects")
local requested_hero_models = {
    "models/items/axe/axe_lava_legion_commander_armor/axe_lava_legion_commander_armor.vmdl",
    "models/items/axe/ti9_jungle_axe/axe_ti9__undie.vmdl",
    "models/items/axe/axe_lava_legion_commander_weapon/axe_lava_legion_commander_weapon.vmdl",
    "models/items/drow/wandering_ranger_legs/wandering_ranger_legs.vmdl",
    "models/items/drow/wandering_ranger_head/wandering_ranger_head.vmdl",
    "models/items/drow/wandering_ranger_misc/wandering_ranger_misc.vmdl",
}
for _, model_path in ipairs(requested_hero_models) do
    assert(generated_components:find(model_path, 1, true),
        "generated hero components omitted requested model " .. model_path)
end
assert(not generated_components:find("searing_annihilator", 1, true)
        and generated_effects:find("lava_legion_head_ambient.vpcf", 1, true)
        and generated_effects:find("drow_2022_cc_quiver.vpcf", 1, true),
    "Axe or Drow cosmetic replacement is incomplete")

local hero_cosmetics = require("config/hero_cosmetics_config")
local doom_cosmetic_models = {
    "models/items/doom/herald_khorne_weapon_alt/herald_khorne_weapon_alt.vmdl",
    "models/items/doom/herald_khorne_head_alt/herald_khorne_head_alt.vmdl",
    "models/items/doom/herald_khorne_shoulder/herald_khorne_shoulder.vmdl",
}
for _, model_path in ipairs(doom_cosmetic_models) do
    assert(generated_components:find(model_path, 1, true),
        "generated Doom components omitted requested model " .. model_path)
end
assert(generated_effects:find("hero_permanent_hero_doom:eternal_khorne_weapon_ambient", 1, true)
        and generated_effects:find("doom_bringer_ambient.vpcf", 1, true),
    "Doom Eternal Daemon Prince cosmetic effect is missing")
local monkey_cosmetics = assert(hero_cosmetics.hero_monkey_king,
    "Monkey King cosmetic definition is missing")
assert(monkey_cosmetics.use_asset_body_model == true
        and monkey_cosmetics.hide_default_wearables == true
        and #(monkey_cosmetics.particles or {}) == 0,
    "Monkey King cosmetic definition is not deterministic")
local blademaster_cosmetics = assert(hero_cosmetics.hero_blademaster,
    "Blademaster cosmetic definition is missing")
assert(blademaster_cosmetics.use_asset_body_model == true
        and blademaster_cosmetics.body_skin == 1
        and blademaster_cosmetics.hide_default_wearables == true,
    "Blademaster cosmetic definition does not select the red Arcana body")

local npc_units_source = read_all("scripts/npc/npc_units_custom.txt")
local monkey_proxy = assert(npc_units_source:match(
    '"asset_proxy_hero_monkey_king"%s*(%b{})'
), "Monkey King preload proxy is missing")
local monkey_precache = assert(monkey_proxy:match(
    '"precache"%s*(%b{})'
), "Monkey King preload proxy has no precache block")
local monkey_proxy_model_count = 0
for _ in monkey_precache:gmatch('"model"%s+"[^"]+"') do
    monkey_proxy_model_count = monkey_proxy_model_count + 1
end
local native_monkey_models = {
    "models/heroes/monkey_king/monkey_king.vmdl",
    "models/heroes/monkey_king/monkey_king_hair.vmdl",
    "models/heroes/monkey_king/monkey_king_armor.vmdl",
    "models/heroes/monkey_king/monkey_king_base_weapon.vmdl",
    "models/heroes/monkey_king/monkey_king_shoulders.vmdl",
}
for _, model_path in ipairs(native_monkey_models) do
    assert(monkey_precache:find('"model" "' .. model_path .. '"', 1, true),
        "Monkey King preload proxy omitted native model " .. model_path)
end
assert(monkey_proxy_model_count == #native_monkey_models + #monkey_cosmetic_models
        and monkey_proxy:find('"particle"', 1, true),
    "Monkey King preload proxy lacks requested cosmetic resources")

local blademaster_proxy = assert(npc_units_source:match(
    '"asset_proxy_hero_blademaster"%s*(%b{})'
), "Blademaster preload proxy is missing")
local blademaster_precache = assert(blademaster_proxy:match(
    '"precache"%s*(%b{})'
), "Blademaster preload proxy has no precache block")
local proxy_model_count = 0
for _ in blademaster_precache:gmatch('"model"%s+"[^"]+"') do
    proxy_model_count = proxy_model_count + 1
end
local native_juggernaut_models = {
    "models/heroes/juggernaut/juggernaut_arcana.vmdl",
    "models/heroes/juggernaut/juggernaut.vmdl",
    "models/heroes/juggernaut/jugg_bracers.vmdl",
    "models/heroes/juggernaut/jugg_cape.vmdl",
    "models/heroes/juggernaut/jugg_mask.vmdl",
    "models/heroes/juggernaut/juggernaut_pants.vmdl",
    "models/heroes/juggernaut/jugg_sword.vmdl",
}
for _, model_path in ipairs(native_juggernaut_models) do
    assert(blademaster_precache:find('"model" "' .. model_path .. '"', 1, true),
        "Blademaster preload proxy omitted native model " .. model_path)
end
assert(proxy_model_count == #native_juggernaut_models
        and blademaster_proxy:find(
            '"Model" "models/heroes/juggernaut/juggernaut_arcana.vmdl"', 1, true)
        and blademaster_proxy:find(
            '"particle" "particles/econ/items/juggernaut/jugg_arcana/juggernaut_arcana_v2_body_ambient.vpcf"',
            1,
            true
        ),
    "Blademaster preload proxy lacks the Arcana body")

print("SELECTED_UNIT_COSMETIC_PORTRAIT_PASS")
