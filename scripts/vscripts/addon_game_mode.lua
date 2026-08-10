local SURVIVAL_FORCE_HERO = "npc_dota_hero_undying"
local multiplayer_rules = require("config/generated/multiplayer_rules")

local function configured_max_players()
    local rule = (multiplayer_rules.by_id or {}).default_multiplayer
    return math.max(1, math.floor(tonumber(rule and rule.max_players) or 1))
end

local function configure_survival_launch_rules()
    local game_mode = GameRules:GetGameModeEntity()
    if not game_mode then
        return false, "game_mode_entity_unavailable"
    end
    game_mode:SetCustomGameForceHero(SURVIVAL_FORCE_HERO)
    GameRules:SetCustomGameSetupTimeout(0)
    GameRules:SetHeroSelectionTime(0)
    GameRules:SetShowcaseTime(0)
    GameRules:SetStrategyTime(0)
    GameRules:SetCustomGameTeamMaxPlayers(
        DOTA_TEAM_GOODGUYS,
        configured_max_players()
    )
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_BADGUYS, 0)
    GameRules:EnableCustomGameSetupAutoLaunch(true)
    GameRules:SetCustomGameSetupAutoLaunchDelay(0)
    return true, nil
end

-- Apply launch-critical rules before loading gameplay modules when the engine
-- entity already exists. Some Workshop startup paths create it only before
-- Activate; that case is recorded as deferred and retried there.
local launch_call_ok, launch_rules_applied, launch_rules_error =
    pcall(configure_survival_launch_rules)
local launch_rules_ok = launch_call_ok and launch_rules_applied == true
if not launch_call_ok then
    launch_rules_error = launch_rules_applied
end
local launch_map_name = GetMapName and GetMapName() or "unknown"
print(
    "[SURVIVAL_LAUNCH_RULES] phase=module_load map=" .. tostring(launch_map_name)
        .. " ok=" .. tostring(launch_rules_ok)
        .. " deferred=" .. tostring(
            launch_rules_error == "game_mode_entity_unavailable"
        )
        .. " error=" .. tostring(launch_rules_error)
)

local modifier_registry = require("core/modifier_registry")
local modifiers_valid, modifier_count_or_error = modifier_registry.register()
assert(modifiers_valid,
    "modifier registry validation failed: " .. tostring(modifier_count_or_error))
assert(modifier_single_health_bar ~= nil,
    "modifier_single_health_bar bootstrap failed")
assert(modifier_debug_attack_cap ~= nil,
    "modifier_debug_attack_cap bootstrap failed")
assert(modifier_enemy_wall_ai ~= nil,
    "modifier_enemy_wall_ai bootstrap failed")
print("[SURVIVAL_MODIFIER_BOOTSTRAP] registry_refreshed=true count="
    .. tostring(modifier_count_or_error)
    .. " health_bar=true attack_cap=true enemy_wall_ai=true")

local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local logger = require("core/logger")
local sound_service = require("core/sound_service")
local combat_bootstrap = require("bootstrap/combat_bootstrap")
print("[SURVIVAL_FINGERPRINT] addon_game_mode=20260730_skill_grant_transaction")
local unit_display_names = require("config/generated/unit_display_names")
local seven_sins_essences = require("config/seven_sins_essences")

local grid_system = require("systems/grid_placement_system")
local resource_system = require("systems/resource_system")
local building_system = require("systems/building_system")
local building_construction_visual = require(
    "systems/building_construction_visual_service"
)
local building_upgrade_system = require("systems/building_upgrade_system")
local tower_skill_effect_adapter = require("systems/tower_skill_effect_adapter")
local tower_special_skill_system = require("systems/tower_special_skill_system")
local tower_magic_supreme_system = require("systems/tower_magic_supreme_system")
local tower_fusion_service = require("systems/tower_fusion_service")
local tree_attack_order_filter = require("systems/tree_attack_order_filter")
local tree_system = require("systems/tree_system")
local worker_system = require("systems/worker_system")
local player_entitlement_service =
    require("systems/player_entitlement_service")
local hero_progression_system =
    require("systems/hero_progression_system")
local hero_skill_system = require("systems/hero_skill_system")
local hero_skill_pool_service =
    require("systems/hero_skill_pool_service")
local hero_skill_choice_service =
    require("systems/hero_skill_choice_service")
local hero_passive_skill_service =
    require("systems/hero_passive_skill_service")
local monkey_king_exclusive_service =
    require("systems/monkey_king_exclusive_service")
local hero_cosmetic_service =
    require("systems/hero_cosmetic_service")
local hero_anchor_service = require("systems/hero_anchor_service")
local builder_service = require("systems/builder_service")
local hero_summon_system = require("systems/hero_summon_system")
local builder_progression_system =
    require("systems/builder_progression_system")
local gold_mine_system = require("systems/gold_mine_system")
local monster_reward_service =
    require("systems/monster_reward_service")
local monster_spawn_service =
    require("systems/monster_spawn_service")
local asset_preload_service = require("systems/asset_preload_service")
local monster_visual_service = require("systems/monster_visual_service")
local unit_health_bar_service = require("systems/unit_health_bar_service")
local challenge_session_service =
    require("systems/challenge_session_service")
local training_room_service = require("systems/training_room_service")
local challenge_equipment_reward_service =
    require("systems/challenge_equipment_reward_service")
local challenge_upgrade_material_service =
    require("systems/challenge_upgrade_material_service")
local seven_sins_essence_service =
    require("systems/seven_sins_essence_service")
local polar_crystal_progression_service =
    require("systems/polar_crystal_progression_service")
local wave_system = require("systems/wave_system")
local buff_definitions = require("config/generated/buff_definitions")
local content_inventory_service =
    require("systems/content_inventory_service")
local inventory_transaction_service =
    require("systems/inventory_transaction_service")
local weapon_equipment_service =
    require("systems/weapon_equipment_service")
local weapon_synthesis_service =
    require("systems/weapon_synthesis_service")
local weapon_growth_service =
    require("systems/weapon_growth_service")
local equipment_instance_service =
    require("systems/equipment_instance_service")
local equipment_growth_service =
    require("systems/equipment_growth_service")
local hero_combat_stat_service =
    require("systems/hero_combat_stat_service")
local technology_stat_manager =
    require("systems/technology_stat_manager")
local research_armor_reduction_service =
    require("systems/research_armor_reduction_service")
local research_technology_bootstrap =
    require("bootstrap/research_technology_bootstrap")
local shop_system = require("systems/shop_system")

local ui_projection = require("ui/ui_projection")
local ui_snapshot_service = require("ui/ui_snapshot_service")
local ui_request_router = require("ui/ui_request_router")
local grid_placement_router = require("ui/grid_placement_router")
local client_data_service = require("ui/client_data_service")
local weapon_synthesis_snapshot_service =
    require("ui/weapon_synthesis_snapshot_service")
local ability_runtime_service =
    require("ui/ability_runtime_service")
local hero_summon_ui_service =
    require("ui/hero_summon_ui_service")
local hero_skill_ui_service =
    require("ui/hero_skill_ui_service")
local monster_encounter_ui_service =
    require("ui/monster_encounter_ui_service")
local combat_stats_ui_service =
    require("ui/combat_stats_ui_service")
local game_info_service = require("ui/game_info_service")
local cheat_command_service =
    require("debug/cheat_command_service")

require("abilities/survival_hero_skill")
require("items/item_survival_seven_sins_essence")
require("items/item_survival_challenge_reward")
require("abilities/ability_build_wall")
require("abilities/ability_build_main_city")
require("abilities/ability_build_arrow_tower")
require("abilities/ability_build_research_lab")
require("abilities/ability_build_farm")
require("abilities/ability_building_blink")
require("abilities/ability_survival_builder_blink")
require("abilities/ability_survival_hero_ball_lightning")
require("abilities/ability_build_gold_mine")
require("abilities/ability_build_hero_altar")
require("abilities/ability_summon_doom")
require("abilities/ability_summon_shadow_fiend")
require("abilities/ability_summon_axe")
require("abilities/ability_summon_drow_ranger")
require("abilities/ability_summon_monkey_king")
require("abilities/ability_summon_blademaster")
require("abilities/ability_enter_endless_training")
require("abilities/ability_enter_shadow_realm")
require("abilities/ability_open_hero_altar")
require("abilities/ability_upgrade_wall")
require("abilities/ability_upgrade_city")
require("abilities/ability_train_lumberjack")
require("abilities/ability_train_repairer")
require("abilities/ability_upgrade_farm")
require("abilities/ability_train_population")
require("abilities/ability_upgrade_tower")
require("abilities/ability_upgrade_tower_lv01")
require("abilities/ability_upgrade_tower_max")
require("abilities/tower_upgrade_ability_factory")
require("abilities/ability_tower_passive")
require("abilities/ability_upgrade_gold_mine")
require("abilities/ability_upgrade_gold_mine_efficiency")
require("abilities/ability_upgrade_gold_mine_crit")
require("abilities/ability_gold_mine_auto_upgrade")
require("abilities/ability_survival_pickup_materials")
require("abilities/ability_survival_return_home")
require("abilities/ability_tower_class_1")
require("abilities/ability_tower_class_2")
require("abilities/ability_tower_class_3")
require("abilities/ability_tower_class_4")
require("abilities/ability_tower_class_5")
require("abilities/ability_tower_class_6")
require("abilities/ability_tower_class_7")

local M = {}
local initialized = false
local replacing_forced_hero = {}
local ready_hero_entindex_by_player = {}

local function assign_player_to_survival_team(player_id)
    if player_id == nil or player_id < 0 then
        return
    end
    if GameRules:State_Get() >= DOTA_GAMERULES_STATE_HERO_SELECTION then
        return
    end
    PlayerResource:SetCustomTeamAssignment(player_id, DOTA_TEAM_GOODGUYS)
end

local function configure_game_rules()
    local launch_rules_applied, launch_error = configure_survival_launch_rules()
    if not launch_rules_applied then
        error("survival launch rules unavailable during Activate: "
            .. tostring(launch_error))
    end
    print("[SURVIVAL_LAUNCH_RULES] phase=activate ok=true deferred=false error=nil")
    local game_mode = GameRules:GetGameModeEntity()
    game_mode:SetBuybackEnabled(false)
    game_mode:SetCameraDistanceOverride(1500)
    game_mode:SetFixedRespawnTime(2)
    -- Human players must never occupy the enemy team. Allowing Badguys
    -- player slots made early Workshop runs assign the local player there.
    GameRules:SetCustomGameTeamMaxPlayers(
        DOTA_TEAM_GOODGUYS,
        configured_max_players()
    )
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_BADGUYS, 0)
    assign_player_to_survival_team(0)
    GameRules:SetHeroRespawnEnabled(true)
    GameRules:SetPreGameTime(5)
    GameRules:SetGoldPerTick(0)

    if game_mode.SetFogOfWarDisabled then
        game_mode:SetFogOfWarDisabled(true)
    end
    if game_mode.SetUnseenFogOfWarEnabled then
        game_mode:SetUnseenFogOfWarEnabled(false)
    end
end

local function on_player_connected(keys)
    assign_player_to_survival_team(tonumber(keys.PlayerID))
end

local function initialize_survival_hero(hero)
    if not hero or hero:IsNull() then
        return
    end

    local player_id = hero:GetPlayerOwnerID()
    local unit_name = hero:GetUnitName()
    local hero_entindex = hero:entindex()
    if ready_hero_entindex_by_player[player_id] == hero_entindex then
        return
    end
    ready_hero_entindex_by_player[player_id] = hero_entindex
    replacing_forced_hero[player_id] = nil

    hero:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK)
    hero:SetGold(0, false)
    local display = (unit_display_names.by_id or {})[unit_name]
    if display and display.enabled ~= false then
        hero.survival_display_name = display.display_name
    end
    FindClearSpaceForUnit(hero, Vector(0, 0, 256), true)
    hero_anchor_service.register_placeholder(player_id, hero)

    event_bus.emit(events.HERO_READY, {
        hero = hero,
        player_id = player_id,
        team = hero:GetTeamNumber(),
    })
    ui_snapshot_service.publish_player(player_id)
end

local function on_hero_picked(keys)
    local hero = keys.heroindex
        and EntIndexToHScript(keys.heroindex) or nil
    if not hero or hero:IsNull() then
        return
    end

    local player_id = hero:GetPlayerOwnerID()
    local unit_name = hero:GetUnitName()
    if unit_name ~= SURVIVAL_FORCE_HERO then
        if player_id >= 0
            and hero_anchor_service.is_placeholder_phase(player_id)
            and not replacing_forced_hero[player_id] then
            replacing_forced_hero[player_id] = true
            print(
                "[SURVIVAL_FORCE_HERO] replacing player=" .. tostring(player_id)
                    .. " native=" .. tostring(unit_name)
            )
            local replacement = PlayerResource:ReplaceHeroWith(
                player_id,
                SURVIVAL_FORCE_HERO,
                0,
                0
            )
            if replacement and not replacement:IsNull()
                and replacement:GetUnitName() == SURVIVAL_FORCE_HERO then
                initialize_survival_hero(replacement)
            end
        end
        return
    end
    initialize_survival_hero(hero)
end

local function on_npc_spawned(keys)
    local unit = keys.entindex
        and EntIndexToHScript(keys.entindex) or nil
    if not unit or unit:IsNull()
        or unit:GetUnitName() ~= SURVIVAL_FORCE_HERO then
        return
    end

    local player_id = unit:GetPlayerOwnerID()
    if ready_hero_entindex_by_player[player_id] ~= unit:entindex() then
        return
    end
    if not hero_anchor_service.is_placeholder_phase(player_id) then
        return
    end

    -- Hero respawn can rebuild or detach cosmetic children depending on the
    -- engine version. Reapplying is idempotent because the service first
    -- removes only the addon-owned wearable and particles.
    hero_anchor_service.isolate_placeholder(player_id, unit)
end

local function on_game_state_changed()
    if GameRules:State_Get()
        == DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
        event_bus.emit(events.GAME_STARTED, {})
    end
end

local function on_entity_killed(keys)
    local victim = keys.entindex_killed
        and EntIndexToHScript(keys.entindex_killed) or nil
    local attacker = keys.entindex_attacker
        and EntIndexToHScript(keys.entindex_attacker) or nil
    if not victim then
        return
    end
    event_bus.emit(events.ENGINE_ENTITY_KILLED, {
        victim = victim,
        attacker = attacker,
        keys = keys,
    })
end

local function item_slot_for(unit, item)
    if not unit or unit:IsNull() or not item or item:IsNull() then return -1 end
    for slot = 0, 8 do
        if unit:GetItemInSlot(slot) == item then return slot end
    end
    return -1
end

local function resolve_item_pickup_hero(keys, item)
    local player_id = tonumber(keys.PlayerID)
        or tonumber(item and item.survival_owner_player_id)
    local candidates = {}
    local seen = {}
    local function add_candidate(unit, source)
        if not unit or unit:IsNull() then return end
        local entindex = unit:entindex()
        if seen[entindex] then return end
        seen[entindex] = true
        candidates[#candidates + 1] = { unit = unit, source = source }
    end

    local event_hero = keys.HeroEntityIndex
        and EntIndexToHScript(keys.HeroEntityIndex) or nil
    add_candidate(event_hero, "event")
    if player_id ~= nil and player_id >= 0 then
        local summoned = event_bus.request(events.HERO_SUMMON_GET_REQUEST, {
            player_id = player_id,
        })
        add_candidate(summoned and summoned.unit, "summoned")
        add_candidate(PlayerResource:GetSelectedHeroEntity(player_id), "selected")
    end

    for _, candidate in ipairs(candidates) do
        local slot = item_slot_for(candidate.unit, item)
        if slot >= 0 then
            return candidate.unit, candidate.source .. "_holder", slot
        end
    end
    local fallback = candidates[1]
    return fallback and fallback.unit or nil,
        fallback and fallback.source or "missing", -1
end

local function on_item_picked_up(keys)
    local item = keys.ItemEntityIndex
        and EntIndexToHScript(keys.ItemEntityIndex) or nil
    if not item or item:IsNull() then return end
    local item_name = item:GetAbilityName()
    local is_challenge_reward = item.survival_ground_reward == true
        or (item_name == "item_survival_challenge_reward"
            and item.survival_claimed ~= true)
    local is_seven_sins_essence =
        seven_sins_essences.by_engine_item_name[item_name] ~= nil
    if not is_challenge_reward and not is_seven_sins_essence then return end
    local hero, hero_source, item_slot = resolve_item_pickup_hero(keys, item)
    if not hero then
        print(string.format(
            "[ITEM_PICKUP_HERO_MISSING] player=%s item=%s entindex=%s",
            tostring(keys.PlayerID or item.survival_owner_player_id),
            tostring(item_name),
            tostring(item:entindex())
        ))
        return
    end

    print(string.format(
        "[ITEM_PICKUP_HERO_RESOLVED] player=%s hero=%s source=%s item=%s slot=%s",
        tostring(hero:GetPlayerOwnerID()),
        tostring(hero:entindex()),
        tostring(hero_source),
        tostring(item:entindex()),
        tostring(item_slot)
    ))
    if item_slot < 0 or item_slot > 8 then
        if hero.DropItemAtPositionImmediate then
            hero:DropItemAtPositionImmediate(item, hero:GetAbsOrigin())
        end
        event_bus.emit(events.UI_NOTIFICATION, {
            player_id = tonumber(item.survival_owner_player_id)
                or hero:GetPlayerOwnerID(),
            message = "装备栏已满，请腾出位置后再拾取",
            level = "error",
        })
        return
    end

    -- Essences remain real items in equipment slots. Claim means "use now",
    -- so calling it during pickup was the regression that dropped every essence
    -- straight back onto the ground when its upgrade requirement was unmet.
    if item.SetPurchaser then item:SetPurchaser(hero) end

    if is_seven_sins_essence then return end
    if item.Claim then
        local claimed = item:Claim(hero)
        if claimed == false and item and not item:IsNull()
            and hero.DropItemAtPositionImmediate then
            hero:DropItemAtPositionImmediate(item, hero:GetAbsOrigin())
        end
    end
end

function M.precache(context)
    -- 魔法塔技能粒子不是单位的普通攻击弹道，必须单独预加载。
    tower_magic_supreme_system.precache(context)
    sound_service.precache(context)
    building_construction_visual.precache(context)
    monster_visual_service.precache_range(context, 1, 1)
    PrecacheResource(
        "particle",
        "particles/items_fx/blink_dagger_start.vpcf",
        context
    )
    PrecacheResource(
        "particle",
        "particles/items_fx/blink_dagger_end.vpcf",
        context
    )
    local units = {
        "npc_dota_hero_undying",
        "npc_survival_builder_proxy",
        "npc_dota_hero_doom_bringer",
        "npc_dota_hero_nevermore",
        "npc_dota_hero_axe",
        "npc_dota_hero_drow_ranger",
        "npc_dota_hero_monkey_king",
        "npc_dota_hero_sven",
        "npc_survival_doom_infernal",
        "npc_survival_drow_companion",
        "building_wall",
        "building_main_city",
        "building_arrow_tower",
        "building_research_lab",
        "building_farm",
        "building_gold_mine",
        "building_hero_altar",
        "npc_survival_upgrade_material",
        "npc_survival_lumberjack",
        "npc_survival_repairer",
        "enemy_tree",
        "npc_survival_wave_monster",
    }
    for _, unit_name in ipairs(units) do
        PrecacheUnitByNameSync(unit_name, context)
    end
    local training_definitions = require("config/generated/training_definitions")
    local precached_worker_models = {}
    for _, row in ipairs(training_definitions.rows or {}) do
        local model_name = tostring(row.model_name or "")
        if model_name ~= "" and not precached_worker_models[model_name] then
            PrecacheResource("model", model_name, context)
            precached_worker_models[model_name] = true
        end
    end
    for _, module_name in ipairs({
        "config/generated/building_visual_levels",
        "config/generated/world_visual_definitions",
    }) do
        local definitions = require(module_name)
        for _, row in ipairs(definitions.rows or {}) do
            local model_name = tostring(row.model_name or "")
            if model_name ~= "" and not precached_worker_models[model_name] then
                PrecacheResource("model", model_name, context)
                precached_worker_models[model_name] = true
            end
        end
    end
    PrecacheResource(
        "particle",
        "particles/units/heroes/hero_tinker/tinker_laser.vpcf",
        context
    )
    PrecacheResource(
        "particle",
        "particles/units/heroes/hero_stormspirit/stormspirit_ball_lightning.vpcf",
        context
    )
    PrecacheResource(
        "soundfile",
        "soundevents/game_sounds_heroes/game_sounds_stormspirit.vsndevts",
        context
    )
    PrecacheResource(
        "particle",
        "particles/basic_explosion/basic_explosion.vpcf",
        context
    )
    PrecacheResource(
        "particle",
        "particles/units/heroes/hero_skywrath_mage/skywrath_mage_mystic_flare.vpcf",
        context
    )
    PrecacheResource(
        "particle",
        "particles/units/heroes/hero_lina/lina_spell_light_strike_array.vpcf",
        context
    )
    PrecacheResource(
        "particle",
        "particles/units/heroes/hero_snapfire/hero_snapfire_ultimate.vpcf",
        context
    )
    PrecacheResource(
        "particle",
        "particles/units/heroes/hero_snapfire/hero_snapfire_ultimate_impact.vpcf",
        context
    )
    PrecacheResource(
        "particle",
        "particles/units/heroes/hero_huskar/huskar_burning_spear_debuff.vpcf",
        context
    )
    PrecacheResource(
        "particle",
        "particles/units/heroes/hero_viper/viper_nethertoxin.vpcf",
        context
    )
    PrecacheResource(
        "particle",
        "particles/units/heroes/hero_invoker/invoker_chaos_meteor_fly.vpcf",
        context
    )
    PrecacheResource(
        "particle",
        "particles/units/heroes/hero_warlock/warlock_rain_of_chaos_explosion.vpcf",
        context
    )
    PrecacheResource(
        "particle",
        "particles/econ/items/crystal_maiden/crystal_maiden_maiden_of_icewrack/maiden_freezing_field_snow_arcana1.vpcf",
        context
    )
    PrecacheResource(
        "particle",
        "particles/econ/items/crystal_maiden/crystal_maiden_maiden_of_icewrack/maiden_freezing_field_explosion_arcana1.vpcf",
        context
    )
    PrecacheResource(
        "particle",
        "particles/units/heroes/hero_leshrac/leshrac_lightning_bolt.vpcf",
        context
    )
    PrecacheResource(
        "particle",
        "particles/units/heroes/hero_puck/puck_illusory_orb_main.vpcf",
        context
    )
    PrecacheResource(
        "particle",
        "particles/basic_projectile/basic_projectile.vpcf",
        context
    )
    PrecacheResource(
        "particle",
        "particles/survival_earth_line/survival_earth_line_chaos_meteor.vpcf",
        context
    )
    PrecacheResource(
        "particle",
        "particles/basic_projectile/basic_projectile_explosion.vpcf",
        context
    )
    PrecacheResource(
        "particle",
        "particles/units/heroes/hero_hoodwink/hoodwink_acorn_shot_tracking.vpcf",
        context
    )
    PrecacheResource(
        "particle",
        "particles/units/heroes/hero_sven/sven_spell_storm_bolt.vpcf",
        context
    )
    PrecacheResource(
        "particle",
        "particles/units/heroes/hero_sven/sven_storm_bolt_projectile_explosion.vpcf",
        context
    )
    PrecacheResource(
        "particle",
        "particles/units/heroes/hero_tiny/tiny_avalanche.vpcf",
        context
    )
    PrecacheResource(
        "particle",
        "particles/units/heroes/hero_magnataur/magnataur_shockwave.vpcf",
        context
    )
    PrecacheResource(
        "particle",
        "particles/survival_echo_slash/survival_echo_slash_follow.vpcf",
        context
    )
    PrecacheResource(
        "particle",
        "particles/survival_tornado/survival_tornado_follow.vpcf",
        context
    )
    PrecacheResource(
        "particle",
        "particles/units/heroes/hero_nevermore/nevermore_shadowraze.vpcf",
        context
    )
    PrecacheResource(
        "particle",
        "particles/units/heroes/hero_axe/axe_attack_blur_counterhelix.vpcf",
        context
    )
    PrecacheResource(
        "particle",
        "particles/units/heroes/hero_monkey_king/monkey_king_strike.vpcf",
        context
    )
    PrecacheResource(
        "particle",
        "particles/survival_monkey_king/survival_monkey_king_staff_drop.vpcf",
        context
    )
    local precached_buff_particles = {}
    for _, row in ipairs(buff_definitions.rows or {}) do
        local particle = row.enabled ~= false and row.particle_name or nil
        if particle and particle ~= "" and not precached_buff_particles[particle] then
            PrecacheResource("particle", particle, context)
            precached_buff_particles[particle] = true
        end
        local status_effect = row.enabled ~= false and row.status_effect_name or nil
        if status_effect and status_effect ~= ""
            and not precached_buff_particles[status_effect] then
            PrecacheResource("particle", status_effect, context)
            precached_buff_particles[status_effect] = true
        end
    end
    asset_preload_service.precache_initial(context)
    hero_cosmetic_service.precache(context)
end

local function initialize_services()
    hero_anchor_service.init()
    require("systems/forbidden_region_service").init()
    require("systems/player_context_service").init()
    builder_service.init()
    asset_preload_service.init()
    unit_health_bar_service.init()
    combat_bootstrap.init()
    assert(tree_attack_order_filter.register(),
        "tree attack order filter registration failed")

    tower_magic_supreme_system.init()
    tower_fusion_service.init()
    tower_special_skill_system.init()
    tower_skill_effect_adapter.init()
    ui_projection.init()
    client_data_service.init()
    ability_runtime_service.init()
    ui_snapshot_service.init()
    ui_request_router.init()
    hero_summon_ui_service.init()
    hero_skill_ui_service.init()
    monster_encounter_ui_service.init()
    combat_stats_ui_service.init()

    grid_system.init()
    resource_system.init()
    player_entitlement_service.init()
    hero_progression_system.init()
    research_technology_bootstrap.init()
    technology_stat_manager.init()
    research_armor_reduction_service.init()
    training_room_service.init()
    building_system.init()
    grid_placement_router.init()
    building_upgrade_system.init()
    tree_system.init()
    worker_system.init()
    hero_skill_system.init()
    hero_skill_pool_service.init()
    hero_skill_choice_service.init()
    content_inventory_service.init()
    inventory_transaction_service.init()
    polar_crystal_progression_service.init()
    challenge_upgrade_material_service.init()
    seven_sins_essence_service.init()
    challenge_equipment_reward_service.init()
    equipment_instance_service.init()
    equipment_growth_service.init()
    weapon_equipment_service.init()
    weapon_synthesis_service.init()
    weapon_growth_service.init()
    weapon_synthesis_snapshot_service.init()
    hero_combat_stat_service.init()
    game_info_service.init()
    hero_passive_skill_service.init()
    monkey_king_exclusive_service.init()
    hero_summon_system.init()
    require("systems/hero_boundary_guard_service").init()
    builder_progression_system.init()
    gold_mine_system.init()
    monster_reward_service.init()
    challenge_session_service.init()
    monster_spawn_service.init()
    wave_system.init()
    shop_system.init()
    cheat_command_service.init()
    require("systems/monster_corpse_lifecycle_service").init()
end

function M.activate()
    if initialized then
        return
    end
    initialized = true
    replacing_forced_hero = {}
    ready_hero_entindex_by_player = {}

    event_bus.reset()
    configure_game_rules()
    scheduler.init()
    sound_service.init()
    initialize_services()

    ListenToGameEvent(
        "game_rules_state_change",
        on_game_state_changed,
        nil
    )
    ListenToGameEvent(
        "player_connect_full",
        on_player_connected,
        nil
    )
    ListenToGameEvent(
        "dota_player_pick_hero",
        on_hero_picked,
        nil
    )
    ListenToGameEvent("npc_spawned", on_npc_spawned, nil)
    ListenToGameEvent("entity_killed", on_entity_killed, nil)
    ListenToGameEvent("dota_item_picked_up", on_item_picked_up, nil)
    -- End setup only after every HERO_READY subscriber and engine listener is
    -- installed; forced hero creation can happen synchronously from here.
    GameRules:FinishCustomGameSetup()
    logger.info(
        "Addon",
        "initialized V1.6 logical weapon growth core"
    )
end

function Precache(context)
    M.precache(context)
end

function Activate()
    M.activate()
end

return M
