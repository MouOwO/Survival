local event_bus = require("core/event_bus")
local scheduler = require("core/scheduler")
local events = require("core/events")
local event_names = require("research/research_event_names")
local Repository = require("research/research_technology_repository")
local EffectService = require("research/research_effect_service")
local Service = require("research/research_technology_service")

local M = {}
local repository
local effects
local service
local pending_resource_refresh = {}
-- Research client rows depend on rebirth, technology levels and building
-- access; attack/attribute counters are unrelated. One authoritative scalar
-- read per growth event replaces a 19-row rebuild and unchanged NetTable set.
local projected_rebirth = {}
local projection_epoch = {}
local projection_lifecycle
local function invalidate_projection(player_id)
    if player_id == nil then return end
    projected_rebirth[player_id] = nil
    projection_epoch[player_id] = (projection_epoch[player_id] or 0) + 1
end

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
    invalidate_projection(player_id)
    if CustomNetTables then
        CustomNetTables:SetTableValue(
            "survival_research",
            tostring(player_id),
            snapshot
        )
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
    projected_rebirth, projection_epoch = {}, {}
    local lifecycle, world = {}, event_bus.get_generation()
    projection_lifecycle = lifecycle
    local function current()
        return projection_lifecycle == lifecycle and event_bus.get_generation() == world
    end
    for player_id in pairs(pending_resource_refresh) do
        scheduler.cancel("research_resource_refresh_" .. player_id)
    end
    pending_resource_refresh = {}
    repository = Repository.new({ resolve_team = team_for })
    effects = EffectService.new(repository)
    service = Service.new({ repository = repository, effects = effects,
        event_bus = event_bus, valid_player = valid_player,
        get_resources = resources, spend_resources = spend,
        refund_resources = refund, get_reincarnation_level = reincarnation_level,
        get_access_state = research_access_state,
        sync_client = sync_client })
    register_handlers()
    -- Levels/effects belong to the purchasing player. Team research broadcasts
    -- would change another player's pending target while its timer is running.
    event_bus.subscribe(events.HERO_PROGRESSION_CHANGED, function(payload)
        if not current() then return end
        local player_id = tonumber(payload and payload.player_id)
        if not valid_player(player_id) then return end
        local before = (projection_epoch[player_id] or 0) + 1
        projection_epoch[player_id] = before
        local cached = projected_rebirth[player_id]
        local rank = reincarnation_level(player_id)
        if not current() then return end
        if cached == rank and before == (projection_epoch[player_id] or 0) then return end
        local build_epoch = projection_epoch[player_id] or 0
        sync_client(player_id, service:BuildClientSnapshot(player_id))
        local published_epoch = projection_epoch[player_id] or 0
        local after_rank = reincarnation_level(player_id)
        if current() and after_rank == rank and published_epoch == build_epoch + 1
            and published_epoch == (projection_epoch[player_id] or 0) then
            projected_rebirth[player_id] = rank
        end
    end)
    -- Existing level operations own their normal client publication. Building
    -- access changes invalidate only the bounded cached player set, avoiding
    -- a false unchanged-rank proof on the next progression refresh.
    event_bus.subscribe(event_names.LEVEL_CHANGED, function(payload)
        if current() then invalidate_projection(tonumber(payload and payload.player_id)) end
    end)
    for _, event in ipairs({events.HERO_READY, events.PLAYER_DISCONNECTED, events.PLAYER_DEFEATED}) do
        event_bus.subscribe(event, function(payload)
            if current() then invalidate_projection(tonumber(payload and payload.player_id)) end
        end)
    end
    for _, event in ipairs({events.BUILDING_CREATED, events.BUILDING_DESTROYED}) do
        event_bus.subscribe(event, function(payload)
            if not current() or not payload then return end
            if payload.building_id == "building_research_lab" then
                invalidate_projection(tonumber(payload.player_id))
            elseif payload.building_id == "building_advanced_research_lab" then
                for player_id in pairs(projected_rebirth) do
                    if team_for(player_id) == tonumber(payload.team) then invalidate_projection(player_id) end
                end
            end
        end)
    end
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
