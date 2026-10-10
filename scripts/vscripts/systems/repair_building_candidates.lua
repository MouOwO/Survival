-- Completed formal building handles, seeded once and maintained by lifecycle
-- events. Idle repair workers visit only their owner and ownerless allies.
local bus = require("core/event_bus")
local events = require("core/events")
local M = {}
local UNOWNED = {}
local by_unit, by_index, by_team, by_owner = {}, {}, {}, {}
local listening, seeded = false, false
local subscriptions = {}
local subscription_generation
local active_binding

function M.reset()
    active_binding = nil
    for _, subscription in ipairs(subscriptions) do bus.unsubscribe(subscription) end
    subscriptions = {}
    subscription_generation = nil
    by_unit, by_index, by_team, by_owner = {}, {}, {}, {}
    listening, seeded = false, false
end

local function remove(record)
    if not record then return end
    by_unit[record.unit] = nil
    if by_index[record.index] == record then by_index[record.index] = nil end
    local team = by_team[record.team]
    if team then team[record.unit] = nil end
    local owners = by_owner[record.team]
    local bucket = owners and owners[record.owner]
    if bucket then
        bucket[record.unit] = nil
        if next(bucket) == nil then owners[record.owner] = nil end
    end
    if team and next(team) == nil then by_team[record.team], by_owner[record.team] = nil, nil end
end

local function add(payload)
    local unit = payload and payload.unit
    if not unit or unit:IsNull() then return end
    local index, team = unit:entindex(), unit:GetTeamNumber()
    -- Match the existing repair policy's nil-owner allowance, rather than
    -- changing it to the registry's fallback player ID.
    local owner = tonumber(unit.survival_player_id) or UNOWNED
    local previous = by_unit[unit]
    if previous and previous.index == index and previous.team == team and previous.owner == owner then return end
    remove(previous)
    remove(by_index[index])
    local record = {unit = unit, index = index, team = team, owner = owner}
    by_unit[unit], by_index[index] = record, record
    by_team[team] = by_team[team] or {}
    by_team[team][unit] = record
    by_owner[team] = by_owner[team] or {}
    by_owner[team][owner] = by_owner[team][owner] or {}
    by_owner[team][owner][unit] = record
end

local function destroyed(payload)
    local record = payload and (payload.unit and by_unit[payload.unit] or by_index[tonumber(payload.entindex)])
    -- A late event for a removed handle must not retire a replacement that
    -- now owns its recycled entity index.
    if record and (not payload.unit or payload.unit == record.unit) then remove(record) end
end

local function ensure_seeded()
    local current_bus = package.loaded["core/event_bus"]
    if type(current_bus) == "table" and current_bus ~= bus then
        -- Detach the old exact bus before binding the replacement module.
        M.reset()
        bus = current_bus
    end
    local generation = type(bus.get_generation) == "function" and bus.get_generation() or bus
    if subscription_generation ~= generation then M.reset() end
    if not listening then
        listening = true
        subscription_generation = generation
        local binding = {}
        active_binding = binding
        local function guarded(handler)
            return function(payload)
                local current = package.loaded["core/event_bus"]
                local current_generation = type(bus.get_generation) == "function" and bus.get_generation() or bus
                if active_binding == binding and current_generation == generation
                    and (current == nil or current == bus) then return handler(payload) end
            end
        end
        subscriptions = {
            bus.subscribe(events.BUILDING_CREATED, guarded(add)),
            bus.subscribe(events.BUILDING_CHANGED, guarded(add)),
            bus.subscribe(events.BUILDING_DESTROYED, guarded(destroyed)),
            bus.subscribe(events.GAME_STARTED, guarded(M.reset)),
        }
    end
    if seeded then return true end
    local result = bus.request(events.BUILDING_LIST_REQUEST, {handles_only = true})
    if not result or type(result.buildings) ~= "table" then return false end
    for _, payload in ipairs(result.buildings) do add(payload) end
    seeded = true
    return true
end

local function nearest(bucket, parent, origin, limit, accept, best, best_distance, best_index)
    if not bucket then return best, best_distance, best_index end
    for unit, record in pairs(bucket) do
        if unit:IsNull() then
            remove(record)
        elseif accept(parent, unit) then
            local ok, actual = pcall(EntIndexToHScript, record.index)
            if not ok or actual ~= unit then
                remove(record)
            else
                local position = unit:GetAbsOrigin()
                local dx, dy = position.x - origin.x, position.y - origin.y
                local distance = dx * dx + dy * dy
                if distance <= limit and (distance < best_distance
                    or (distance == best_distance and record.index < best_index)) then
                    best, best_distance, best_index = unit, distance, record.index
                end
            end
        end
    end
    return best, best_distance, best_index
end

function M.closest(parent, radius, accept)
    if not ensure_seeded() then return nil end
    local team, owner = parent:GetTeamNumber(), tonumber(parent.survival_player_id)
    local origin = parent:GetAbsOrigin()
    local limit = radius == FIND_UNITS_EVERYWHERE and math.huge or radius * radius
    if owner == nil then
        return (nearest(by_team[team], parent, origin, limit, accept, nil, math.huge, math.huge))
    end
    local buckets = by_owner[team]
    if not buckets then return nil end
    local best, distance, index = nearest(buckets[owner], parent, origin, limit, accept, nil, math.huge, math.huge)
    return (nearest(buckets[UNOWNED], parent, origin, limit, accept, best, distance, index))
end

return M
