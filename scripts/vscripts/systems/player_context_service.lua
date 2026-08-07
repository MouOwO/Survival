local rules = require("config/generated/multiplayer_rules")
local slots = require("config/generated/player_slots")

local M = {}

local owner_by_entindex = {}
local slot_by_player = {}
local active_rule = nil

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function normalized_player_id(player_id)
    player_id = tonumber(player_id)
    if player_id == nil or player_id < 0 then return nil end
    return math.floor(player_id)
end

local function configured_rule()
    if active_rule then return active_rule end
    for _, row in ipairs(rules.rows or {}) do
        if row.enabled ~= false then
            active_rule = row
            return row
        end
    end
    return nil
end

local function rebuild_slots()
    slot_by_player = {}
    for _, row in ipairs(slots.rows or {}) do
        local player_id = normalized_player_id(row.player_id)
        if row.enabled ~= false and player_id ~= nil then
            assert(slot_by_player[player_id] == nil,
                "duplicate multiplayer player slot: " .. tostring(player_id))
            slot_by_player[player_id] = row
        end
    end
end

local function find_marker(marker_name)
    marker_name = tostring(marker_name or "")
    if marker_name == "" or not Entities or not Entities.FindByName then
        return nil
    end
    local ok, marker = pcall(Entities.FindByName, Entities, nil, marker_name)
    if ok and valid_entity(marker) then return marker end
    return nil
end

function M.max_players()
    local rule = configured_rule()
    return math.max(1, math.floor(tonumber(rule and rule.max_players) or 1))
end

function M.initial_slice_players()
    local rule = configured_rule()
    return math.max(1, math.floor(tonumber(rule and rule.initial_slice_players) or 1))
end

function M.slot(player_id)
    player_id = normalized_player_id(player_id)
    return player_id and slot_by_player[player_id] or nil
end

function M.resolve_builder_spawn(player_id)
    player_id = normalized_player_id(player_id)
    local slot = M.slot(player_id)
    if player_id == nil or not slot then
        return nil, "player_slot_not_configured"
    end

    local marker = find_marker(slot.builder_spawn_marker)
    if marker then
        return {
            position = marker:GetAbsOrigin(),
            marker = slot.builder_spawn_marker,
            slot_id = slot.slot_id,
            source = "hammer_marker",
        }
    end

    if slot.allow_legacy_builder_fallback == true then
        return {
            position = Vector(
                tonumber(slot.legacy_builder_x) or 0,
                tonumber(slot.legacy_builder_y) or 0,
                tonumber(slot.legacy_builder_z) or 256
            ),
            marker = slot.builder_spawn_marker,
            slot_id = slot.slot_id,
            source = "legacy_coordinates",
        }
    end

    return nil, "builder_spawn_marker_missing:" .. tostring(slot.builder_spawn_marker)
end

function M.register_unit(player_id, unit, identity)
    player_id = normalized_player_id(player_id)
    if player_id == nil then return false, "invalid_player_id" end
    if not valid_entity(unit) then return false, "invalid_unit" end

    local entindex = tonumber(unit:entindex())
    if entindex == nil or entindex < 0 then return false, "invalid_entindex" end
    local existing = owner_by_entindex[entindex]
    if existing ~= nil and existing ~= player_id then
        return false, "unit_owner_conflict"
    end

    local entity_owner = normalized_player_id(unit.survival_player_id)
    if entity_owner ~= nil and entity_owner ~= player_id then
        return false, "unit_owner_conflict"
    end

    owner_by_entindex[entindex] = player_id
    unit.survival_player_id = player_id
    if identity and identity ~= "" then
        unit.survival_owner_identity = tostring(identity)
    end
    return true, nil
end

function M.owner_player_id(unit)
    if not valid_entity(unit) then return nil end
    local entity_owner = normalized_player_id(unit.survival_player_id)
    local entindex = tonumber(unit:entindex())
    local registered_owner = entindex and owner_by_entindex[entindex] or nil
    if entity_owner ~= nil and registered_owner ~= nil
        and entity_owner ~= registered_owner then
        return nil
    end
    return registered_owner or entity_owner
end

function M.is_owned_by(player_id, unit)
    player_id = normalized_player_id(player_id)
    return player_id ~= nil and M.owner_player_id(unit) == player_id
end

function M.unregister_unit(unit)
    if not valid_entity(unit) then return false end
    local entindex = tonumber(unit:entindex())
    if entindex == nil then return false end
    owner_by_entindex[entindex] = nil
    return true
end

rebuild_slots()

function M.init()
    owner_by_entindex = {}
    active_rule = nil
    rebuild_slots()
    local rule = configured_rule()
    assert(rule ~= nil, "enabled multiplayer rule missing")
    assert(M.max_players() <= 24, "multiplayer max_players exceeds Dota player limit")
    for player_id = 0, M.max_players() - 1 do
        assert(slot_by_player[player_id] ~= nil,
            "multiplayer player slot missing: " .. tostring(player_id))
    end
    print(string.format(
        "[MULTIPLAYER_CONTEXT] initialized max_players=%d initial_slice=%d slots=%d",
        M.max_players(), M.initial_slice_players(), M.max_players()))
end

M._reset_for_test = function()
    owner_by_entindex = {}
    active_rule = nil
    rebuild_slots()
end

return M