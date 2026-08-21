local event_bus = require("core/event_bus")
local events = require("core/events")
local event_names = require("research/research_event_names")
local Repository = require("research/research_technology_repository")
local EffectService = require("research/research_effect_service")
local Service = require("research/research_technology_service")

local M = {}
local repository
local effects
local service

local function valid_player(player_id)
    return player_id ~= nil and player_id >= 0
        and PlayerResource:IsValidPlayerID(player_id)
end

local function team_for(player_id)
    if not valid_player(player_id) then return nil end
    return PlayerResource:GetTeam(player_id)
end

local function resources(player_id)
    local team = team_for(player_id)
    if team == nil then return nil end
    return event_bus.request(events.RESOURCE_GET_REQUEST, {
        player_id = player_id, team = team })
end

local function spend(player_id, cost, tech_id)
    return event_bus.request(events.RESOURCE_TRY_SPEND_REQUEST, {
        player_id = player_id,
        team = team_for(player_id),
        gold = cost.gold,
        wood = cost.wood,
        population = 0,
        reason = "research_upgrade:" .. tech_id,
    })
end

local function refund(player_id, cost, tech_id)
    return event_bus.request(events.RESOURCE_ADD_REQUEST, {
        player_id = player_id,
        team = team_for(player_id),
        gold = cost.gold,
        wood = cost.wood,
        reason = "research_refund:" .. tech_id,
    })
end

local function reincarnation_level(player_id)
    local response = event_bus.request(events.HERO_PROGRESSION_GET_REQUEST, {
        player_id = player_id,
    })
    return tonumber(response and response.snapshot
        and response.snapshot.rebirth_level) or 0
end

local function research_access_state(player_id)
    local response = event_bus.request(events.TECHNOLOGY_STATE_GET_REQUEST, {
        player_id = player_id,
    })
    return {
        research_lab = response and response.ok == true
            and response.research_unlocked == true or false,
        advanced_research_lab = response and response.ok == true
            and response.advanced_researcher_unlocked == true or false,
    }
end

local function sync_client(player_id, snapshot)
    if CustomNetTables then
        CustomNetTables:SetTableValue(
            "survival_research",
            tostring(player_id),
            snapshot
        )
    end
end

local function each_team_player(team, callback)
    local limit = tonumber(DOTA_MAX_TEAM_PLAYERS) or 24
    for player_id = 0, limit - 1 do
        if valid_player(player_id) and team_for(player_id) == team then
            callback(player_id)
        end
    end
end

local function register_handlers()
    event_bus.handle_request(event_names.UPGRADE_REQUESTED, function(payload)
        return service:RequestUpgrade(payload)
    end)
    event_bus.handle_request(event_names.UPGRADE_BEGIN_REQUESTED, function(payload)
        return service:BeginUpgrade(payload)
    end)
    event_bus.handle_request(event_names.UPGRADE_COMMIT_REQUESTED, function(payload)
        return service:CommitUpgrade(payload)
    end)
    event_bus.handle_request(event_names.UPGRADE_ROLLBACK_REQUESTED, function(payload)
        return service:RollbackUpgrade(payload)
    end)
    event_bus.handle_request(event_names.STATE_GET_REQUESTED, function(payload)
        local player_id = tonumber(payload and payload.player_id)
        if not valid_player(player_id) then
            return { ok = false, error = "invalid_player" }
        end
        return { ok = true, levels = repository:GetAllLevels(player_id),
            legacy_levels = repository:GetLegacyLevels(player_id) }
    end)
    event_bus.handle_request(event_names.EFFECTS_GET_REQUESTED, function(payload)
        local player_id = tonumber(payload and payload.player_id)
        if not valid_player(player_id) then
            return { ok = false, error = "invalid_player" }
        end
        return { ok = true, snapshot = effects:Get(player_id) }
    end)
    event_bus.handle_request(event_names.LEVEL_SET_REQUESTED, function(payload)
        local player_id = tonumber(payload and payload.player_id)
        local tech_id = tostring(payload and payload.tech_id or "")
        local level = tonumber(payload and payload.level)
        if not valid_player(player_id) or not repository:SetLevel(
            player_id, tech_id, level) then
            return { ok = false, error = "research_level_invalid" }
        end
        local snapshot = effects:Recalculate(player_id)
        local data = { player_id = player_id, tech_id = tech_id, level = level,
            levels = repository:GetAllLevels(player_id),
            legacy_levels = repository:GetLegacyLevels(player_id),
            effects = snapshot, reason = payload.reason or "level_set" }
        event_bus.emit(event_names.LEVEL_CHANGED, data)
        event_bus.emit(event_names.EFFECTS_CHANGED, {
            player_id = player_id, tech_id = tech_id, snapshot = snapshot,
        })
        sync_client(player_id, service:BuildClientSnapshot(player_id))
        return { ok = true, snapshot = data }
    end)
    event_bus.handle_request(event_names.CLIENT_SNAPSHOT_REQUESTED, function(payload)
        local player_id = tonumber(payload and payload.player_id)
        if not valid_player(player_id) then
            return { ok = false, error = "invalid_player" }
        end
        local snapshot = service:BuildClientSnapshot(player_id)
        sync_client(player_id, snapshot)
        return { ok = true, snapshot = snapshot }
    end)
end

function M.init()
    repository = Repository.new({ resolve_team = team_for })
    effects = EffectService.new(repository)
    service = Service.new({ repository = repository, effects = effects,
        event_bus = event_bus, valid_player = valid_player,
        get_resources = resources, spend_resources = spend,
        refund_resources = refund, get_reincarnation_level = reincarnation_level,
        get_access_state = research_access_state,
        sync_client = sync_client })
    register_handlers()
    event_bus.subscribe(event_names.LEVEL_CHANGED, function(payload)
        if payload.team_propagated == true then return end
        local source_player_id = tonumber(payload and payload.player_id)
        local team = source_player_id ~= nil and team_for(source_player_id) or nil
        if team == nil then return end
        each_team_player(team, function(player_id)
            if player_id == source_player_id then return end
            local projection = effects:Recalculate(player_id)
            local propagated = {
                player_id = player_id,
                tech_id = payload.tech_id,
                old_level = payload.old_level,
                new_level = payload.new_level,
                gold_cost = payload.gold_cost,
                wood_cost = payload.wood_cost,
                levels = repository:GetAllLevels(player_id),
                legacy_levels = repository:GetLegacyLevels(player_id),
                effects = projection,
                reason = "team_research_level_changed",
                team_propagated = true,
            }
            event_bus.emit(event_names.LEVEL_CHANGED, propagated)
            event_bus.emit(event_names.EFFECTS_CHANGED, {
                player_id = player_id,
                tech_id = payload.tech_id,
                snapshot = projection,
                team_propagated = true,
            })
            sync_client(player_id, service:BuildClientSnapshot(player_id))
        end)
    end)
    event_bus.subscribe(events.RESOURCE_CHANGED, function(payload)
        each_team_player(payload.team, function(player_id)
            sync_client(player_id, service:BuildClientSnapshot(player_id))
        end)
    end)
    event_bus.subscribe(events.HERO_PROGRESSION_CHANGED, function(payload)
        local player_id = tonumber(payload and payload.player_id)
        if valid_player(player_id) then
            sync_client(player_id, service:BuildClientSnapshot(player_id))
        end
    end)
    event_bus.subscribe(events.HERO_READY, function(payload)
        local player_id = tonumber(payload and payload.player_id)
        if valid_player(player_id) then
            effects:Recalculate(player_id)
            sync_client(player_id, service:BuildClientSnapshot(player_id))
        end
    end)
end

function M.service() return service end
function M.repository() return repository end
function M.effects() return effects end

return M