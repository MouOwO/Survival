-- Reuse the wall's existing damage callback. Only idle workers in its owner
-- bucket are notified, at most once per second; no new global damage listeners.
local M = {}
local repair_policy = require('systems/repair_target_policy')
local UNOWNED = {}
local records, teams = {}, {}

function M.unregister(modifier)
    local record = records[modifier]
    if not record then return end
    records[modifier] = nil
    local owners = teams[record.team]
    local bucket = owners and owners[record.owner]
    if bucket then
        bucket.workers[modifier] = nil
        if next(bucket.workers) == nil then owners[record.owner] = nil end
        if next(owners) == nil then teams[record.team] = nil end
    end
end

function M.register(modifier, parent)
    M.unregister(modifier)
    local team, owner = parent:GetTeamNumber(), tonumber(parent.survival_player_id) or UNOWNED
    teams[team] = teams[team] or {}
    local owners = teams[team]
    owners[owner] = owners[owner] or {workers = {}}
    local record = {team = team, owner = owner, parent = parent}
    records[modifier], owners[owner].workers[modifier] = record, record
end

local function now()
    if GameRules and GameRules.GetGameTime then return GameRules:GetGameTime() end
    if type(Time) == 'function' then return Time() end
end

local function notify(bucket, wall, time)
    if not bucket then return end
    if time and bucket.last_wake and time >= bucket.last_wake
        and time - bucket.last_wake < 1 then return end
    bucket.last_wake = time
    for modifier, record in pairs(bucket.workers) do
        if record.parent:IsNull() or (modifier.IsNull and modifier:IsNull()) then
            M.unregister(modifier)
        elseif modifier.WakeForDamagedBuilding then
            modifier:WakeForDamagedBuilding(wall)
        end
    end
end

function M.wall_damaged(wall)
    local owners = teams[wall:GetTeamNumber()]
    if not owners or not repair_policy.needs_repair(wall) then return end
    local owner, time = tonumber(wall.survival_player_id), now()
    if owner == nil then
        for _, bucket in pairs(owners) do notify(bucket, wall, time) end
    else
        notify(owners[owner], wall, time)
        notify(owners[UNOWNED], wall, time)
    end
end

return M
