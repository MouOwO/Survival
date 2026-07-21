local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local logger = require("core/logger")
print("[SURVIVAL_FINGERPRINT] addon_game_mode=20260720_1045_direct_building_path")
local modifier_registry = require("core/modifier_registry")
-- Explicit modifier links must execute during addon VM bootstrap, before any building is created.
LinkLuaModifier("modifier_building_stationary", "modifiers/modifier_building_stationary", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_building_no_health_bar", "modifiers/modifier_building_no_health_bar", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_tower_attack_effects", "modifiers/modifier_tower_attack_effects", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_debug_attack_cap", "modifiers/modifier_debug_attack_cap", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_building_blink_move", "modifiers/modifier_building_blink_move", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_weapon_attack_tracker", "modifiers/modifier_weapon_attack_tracker", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_weapon_stat_projection", "modifiers/modifier_weapon_stat_projection", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_equipment_effects", "modifiers/modifier_equipment_effects", LUA_MODIFIER_MOTION_NONE)
require("modifiers/modifier_building_stationary")
require("modifiers/modifier_building_no_health_bar")
require("modifiers/modifier_tower_attack_effects")
require("modifiers/modifier_debug_attack_cap")
require("modifiers/modifier_building_blink_move")
require("modifiers/modifier_weapon_attack_tracker")
require("modifiers/modifier_weapon_stat_projection")
require("modifiers/modifier_equipment_effects")
assert(modifier_weapon_attack_tracker ~= nil, "modifier_weapon_attack_tracker bootstrap failed")
assert(modifier_weapon_stat_projection ~= nil, "modifier_weapon_stat_projection bootstrap failed")
assert(modifier_equipment_effects ~= nil, "modifier_equipment_effects bootstrap failed")
print("[SURVIVAL_MODIFIER_BOOTSTRAP] weapon_attack_tracker=true weapon_stat_projection=true equipment_effects=true")
modifier_registry.register()
local ability_utils = require("core/ability_utils")

local grid_system = require("systems/grid_system")
local resource_system = require("systems/resource_system")
local building_system = require("systems/building_system")
local building_upgrade_system = require("systems/building_upgrade_system")
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
local hero_cosmetic_service =
    require("systems/hero_cosmetic_service")
local hero_summon_system = require("systems/hero_summon_system")
local builder_progression_system =
    require("systems/builder_progression_system")
local gold_mine_system = require("systems/gold_mine_system")
local monster_reward_service =
    require("systems/monster_reward_service")
local monster_spawn_service =
    require("systems/monster_spawn_service")
local wave_system = require("systems/wave_system")
local monster_archetypes = require("config/generated/monster_archetypes")
local arrow_tower_base = require("config/generated/arrow_tower_base")
local tower_route_config = require("config/tower_route_config")
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
local shop_system = require("systems/shop_system")

local ui_projection = require("ui/ui_projection")
local ui_snapshot_service = require("ui/ui_snapshot_service")
local ui_request_router = require("ui/ui_request_router")
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
local cheat_command_service =
    require("debug/cheat_command_service")

require("abilities/survival_hero_skill")
require("abilities/ability_build_wall")
require("abilities/ability_build_main_city")
require("abilities/ability_build_arrow_tower")
require("abilities/ability_building_blink")
require("abilities/ability_build_gold_mine")
require("abilities/ability_build_hero_altar")
require("abilities/ability_summon_axe")
require("abilities/ability_summon_slark")
require("abilities/ability_summon_juggernaut")
require("abilities/ability_summon_monkey_king")
require("abilities/ability_summon_blademaster")
require("abilities/ability_open_hero_altar")
require("abilities/ability_upgrade_wall")
require("abilities/ability_upgrade_city")
require("abilities/ability_train_lumberjack")
require("abilities/ability_upgrade_tower")
require("abilities/ability_upgrade_tower_lv01")
require("abilities/ability_upgrade_tower_max")
require("abilities/tower_upgrade_ability_factory")
require("abilities/ability_tower_passive")
require("abilities/ability_upgrade_gold_mine")
require("abilities/ability_upgrade_gold_mine_crit")
require("abilities/ability_tower_class_1")
require("abilities/ability_tower_class_2")
require("abilities/ability_tower_class_3")
require("abilities/ability_tower_class_4")
require("abilities/ability_tower_class_5")
require("abilities/ability_tower_class_6")
require("abilities/ability_tower_class_7")

local M = {}
local initialized = false

local function configure_game_rules()
    local game_mode = GameRules:GetGameModeEntity()
    game_mode:SetCustomGameForceHero("npc_dota_hero_undying")
    game_mode:SetBuybackEnabled(false)
    game_mode:SetCameraDistanceOverride(1500)
    game_mode:SetFixedRespawnTime(2)
    -- Human players must never occupy the enemy team. Allowing Badguys
    -- player slots made early Workshop runs assign the local player there.
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_GOODGUYS, 1)
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_BADGUYS, 0)
    GameRules:SetHeroRespawnEnabled(true)
    GameRules:SetHeroSelectionTime(0)
    GameRules:SetShowcaseTime(0)
    GameRules:SetStrategyTime(0)
    GameRules:SetPreGameTime(5)
    GameRules:SetCustomGameSetupAutoLaunchDelay(0)
    GameRules:SetGoldPerTick(0)

    if game_mode.SetFogOfWarDisabled then
        game_mode:SetFogOfWarDisabled(true)
    end
    if game_mode.SetUnseenFogOfWarEnabled then
        game_mode:SetUnseenFogOfWarEnabled(false)
    end
end

local function on_hero_picked(keys)
    local hero = keys.heroindex
        and EntIndexToHScript(keys.heroindex) or nil
    if not hero or hero:IsNull() then
        return
    end

    ability_utils.remove_all(hero)
    hero:SetGold(0, false)
    FindClearSpaceForUnit(hero, Vector(0, 0, 256), true)

    local player_id = hero:GetPlayerOwnerID()
    event_bus.emit(events.HERO_READY, {
        hero = hero,
        player_id = player_id,
        team = hero:GetTeamNumber(),
    })
    ui_snapshot_service.publish_player(player_id)
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

function M.precache(context)
    local units = {
        "npc_dota_hero_undying",
        "npc_dota_hero_axe",
        "npc_dota_hero_slark",
        "npc_dota_hero_juggernaut",
        "npc_dota_hero_monkey_king",
        "npc_dota_hero_sven",
        "building_wall",
        "building_main_city",
        "building_arrow_tower",
        "building_gold_mine",
        "building_hero_altar",
        "npc_survival_lumberjack",
        "npc_dota_hero_doom",
        "npc_dota_hero_sven",
        "npc_dota_hero_abyssal_underlord",
        "npc_dota_hero_keeper_of_the_light",
        "npc_dota_hero_obsidian_destroyer",
        "npc_dota_hero_zuus",
        "npc_dota_hero_razor",
        "npc_dota_hero_storm_spirit",
        "npc_dota_hero_sniper",
        "npc_dota_hero_gyrocopter",
        "npc_dota_hero_tinker",
        "npc_dota_hero_drow_ranger",
        "npc_dota_hero_windrunner",
        "npc_dota_hero_clinkz",
        "npc_dota_hero_lich",
        "npc_dota_hero_crystal_maiden",
        "npc_dota_hero_ancient_apparition",
        "npc_dota_hero_skywrath_mage",
        "npc_dota_hero_vengefulspirit",
        "enemy_tree",
        "zombie_basic",
        "zombie_boss",
        "npc_survival_wave_monster",
    }
    for _, unit_name in ipairs(units) do
        PrecacheUnitByNameSync(unit_name, context)
    end
    -- These models are assigned directly to the arrow-tower entity, so
    -- precache the model resources explicitly instead of relying only on
    -- hero unit precaching.
    PrecacheModel("models/heroes/zuus/zuus.vmdl", context)
    PrecacheModel("models/heroes/drow_ranger/drow_ranger.vmdl", context)
    PrecacheModel("models/props_structures/radiant_tower001.vmdl", context)
    local precached_models = {}
    local precached_projectiles = {}
    local function precache_projectile(path)
        if path and path ~= "" and not precached_projectiles[path] then
            PrecacheResource("particle", path, context)
            precached_projectiles[path] = true
        end
    end
    for _, row in ipairs(arrow_tower_base.rows or {}) do
        precache_projectile(row.projectile_model)
        if row.model_name and row.model_name ~= "" then
            PrecacheModel(row.model_name, context)
        end
    end
    for class_id = 1, 7 do
        for _, row in ipairs(tower_route_config.get_route("class_" .. class_id) or {}) do
            precache_projectile(row.projectile_model)
            if row.model_name and row.model_name ~= "" then
                PrecacheModel(row.model_name, context)
            end
        end
    end
    for _, archetype in ipairs(monster_archetypes.rows or {}) do
        if archetype.enabled ~= false and archetype.model_path
            and archetype.model_path ~= "" and not precached_models[archetype.model_path] then
            PrecacheModel(archetype.model_path, context)
            precached_models[archetype.model_path] = true
        end
    end
    hero_cosmetic_service.precache(context)
end

function M.activate()
    if initialized then
        return
    end
    initialized = true

    event_bus.reset()
    configure_game_rules()
    scheduler.init()

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
    building_system.init()
    building_upgrade_system.init()
    tree_system.init()
    worker_system.init()
    player_entitlement_service.init()
    hero_progression_system.init()
    hero_skill_system.init()
    hero_skill_pool_service.init()
    hero_skill_choice_service.init()
    content_inventory_service.init()
    inventory_transaction_service.init()
    equipment_instance_service.init()
    equipment_growth_service.init()
    weapon_equipment_service.init()
    weapon_synthesis_service.init()
    weapon_growth_service.init()
    weapon_synthesis_snapshot_service.init()
    hero_combat_stat_service.init()
    hero_summon_system.init()
    builder_progression_system.init()
    gold_mine_system.init()
    monster_reward_service.init()
    monster_spawn_service.init()
    wave_system.init()
    shop_system.init()
    cheat_command_service.init()

    ListenToGameEvent(
        "game_rules_state_change",
        on_game_state_changed,
        nil
    )
    ListenToGameEvent(
        "dota_player_pick_hero",
        on_hero_picked,
        nil
    )
    ListenToGameEvent("entity_killed", on_entity_killed, nil)
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
