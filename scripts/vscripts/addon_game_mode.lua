local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local logger = require("core/logger")
local modifier_registry = require("core/modifier_registry")
local ability_utils = require("core/ability_utils")

local grid_system = require("systems/grid_system")
local resource_system = require("systems/resource_system")
local building_system = require("systems/building_system")
local building_upgrade_system = require("systems/building_upgrade_system")
local tree_system = require("systems/tree_system")
local worker_system = require("systems/worker_system")
local builder_unlock_system = require("systems/builder_unlock_system")
local gold_mine_system = require("systems/gold_mine_system")
local wave_system = require("systems/wave_system")
local shop_system = require("systems/shop_system")
local ui_projection = require("ui/ui_projection")
local ui_snapshot_service = require("ui/ui_snapshot_service")
local ui_request_router = require("ui/ui_request_router")
local client_data_service = require("ui/client_data_service")
local ability_runtime_service = require("ui/ability_runtime_service")
local shop_debug_command_service = require("ui/shop_debug_command_service")

require("abilities/ability_build_wall")
require("abilities/ability_build_main_city")
require("abilities/ability_build_arrow_tower")
require("abilities/ability_build_gold_mine")
require("abilities/ability_upgrade_wall")
require("abilities/ability_upgrade_city")
require("abilities/ability_train_lumberjack")
require("abilities/ability_upgrade_tower")
require("abilities/ability_upgrade_gold_mine")
require("abilities/ability_upgrade_gold_mine_crit")
require("abilities/ability_tower_class_1")
require("abilities/ability_tower_class_2")
require("abilities/ability_tower_class_3")
require("abilities/ability_tower_class_4")
require("abilities/ability_tower_class_5")

-- Register all engine modifier adapters immediately when this file is loaded.
-- This intentionally runs outside Precache so script_reload and development
-- startup paths cannot reach AddNewModifier before the modifier is known.
modifier_registry.register()

local M = {}
local initialized = false

local function configure_game_rules()
    local game_mode = GameRules:GetGameModeEntity()
    game_mode:SetCustomGameForceHero("npc_dota_hero_undying")
    game_mode:SetBuybackEnabled(false)
    game_mode:SetCameraDistanceOverride(1500)
    game_mode:SetFixedRespawnTime(99999)
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_GOODGUYS, 1)
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_BADGUYS, 10)
    GameRules:SetHeroRespawnEnabled(false)
    GameRules:SetHeroSelectionTime(0)
    GameRules:SetShowcaseTime(0)
    GameRules:SetStrategyTime(0)
    GameRules:SetPreGameTime(5)
    GameRules:SetCustomGameSetupAutoLaunchDelay(0)
    GameRules:SetGoldPerTick(0)

    -- This survival mode uses full-map information rather than Dota fog.
    if game_mode.SetFogOfWarDisabled then
        game_mode:SetFogOfWarDisabled(true)
    end
    if game_mode.SetUnseenFogOfWarEnabled then
        game_mode:SetUnseenFogOfWarEnabled(false)
    end
end

local function clear_hero_abilities(hero)
    ability_utils.remove_all(hero)
end

local function add_hero_ability(hero, ability_name)
    local ability = hero:AddAbility(ability_name)
    if ability then ability:SetLevel(1) end
end

local function on_hero_picked(keys)
    local hero = keys.heroindex and EntIndexToHScript(keys.heroindex) or nil
    if not hero or hero:IsNull() then return end

    clear_hero_abilities(hero)
    add_hero_ability(hero, "ability_build_wall")
    add_hero_ability(hero, "ability_build_main_city")
    add_hero_ability(hero, "ability_build_arrow_tower")
    add_hero_ability(hero, "ability_build_gold_mine")
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
    if GameRules:State_Get() == DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
        event_bus.emit(events.GAME_STARTED, {})
    end
end

local function on_entity_killed(keys)
    local victim = keys.entindex_killed and EntIndexToHScript(keys.entindex_killed) or nil
    local attacker = keys.entindex_attacker and EntIndexToHScript(keys.entindex_attacker) or nil
    if not victim then return end
    event_bus.emit(events.ENGINE_ENTITY_KILLED, {
        victim = victim,
        attacker = attacker,
        keys = keys,
    })
end

function M.precache(context)
    local units = {
        "npc_dota_hero_undying",
        "building_wall",
        "building_main_city",
        "building_arrow_tower",
        "building_gold_mine",
        "npc_survival_lumberjack",
        "enemy_tree",
        "zombie_basic",
        "zombie_boss",
    }
    for _, unit_name in ipairs(units) do
        PrecacheUnitByNameSync(unit_name, context)
    end
end

function M.activate()
    if initialized then return end
    initialized = true

    event_bus.reset()
    configure_game_rules()
    scheduler.init()

    -- Read models first, then initialize domain systems and UI adapters.
    ui_projection.init()
    client_data_service.init()
    ability_runtime_service.init()
    ui_snapshot_service.init()
    ui_request_router.init()
    shop_debug_command_service.init()
    grid_system.init()
    resource_system.init()
    building_system.init()
    building_upgrade_system.init()
    tree_system.init()
    worker_system.init()
    builder_unlock_system.init()
    gold_mine_system.init()
    wave_system.init()
    shop_system.init()

    ListenToGameEvent("game_rules_state_change", on_game_state_changed, nil)
    ListenToGameEvent("dota_player_pick_hero", on_hero_picked, nil)
    ListenToGameEvent("entity_killed", on_entity_killed, nil)
    logger.info("Addon", "initialized V1.4 realtime HUD and gold mine")
end

-- Dota engine adapter globals. No business state is stored globally.
function Precache(context)
    M.precache(context)
end

function Activate()
    M.activate()
end

return M
