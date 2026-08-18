if LinkLuaModifier then
    LinkLuaModifier("modifier_enemy_wall_ai", "modifiers/modifier_enemy_wall_ai", LUA_MODIFIER_MOTION_NONE)
end
modifier_enemy_wall_ai = class({})
_G.modifier_enemy_wall_ai = modifier_enemy_wall_ai
local M = modifier_enemy_wall_ai
local team_alignment = require("core/team_alignment")
local wall_engagement_slots = require("systems/wall_engagement_slots")
local ARRIVAL_DISTANCE = 24
local DEPARTURE_DISTANCE = 48

function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end

function M:OnCreated(params)
    self.no_unit_collision = tonumber(params.no_unit_collision) == 1
    if not IsServer() then return end
    self.wall_entindex = tonumber(params.wall_entindex) or -1
    self:StartIntervalThink(0.5)
end

function M:CheckState()
    if not self.no_unit_collision then return {} end
    return {
        [MODIFIER_STATE_NO_UNIT_COLLISION] = true,
    }
end

function M:SetWallEntIndex(entindex)
    local parent = self:GetParent()
    local previous_wall_entindex = self.wall_entindex
    self.wall_entindex = tonumber(entindex) or -1
    if previous_wall_entindex ~= self.wall_entindex and parent and not parent:IsNull() then
        wall_engagement_slots.release(previous_wall_entindex, parent:entindex())
        self.engagement_slot = nil
        self.engagement_arrived = nil
        self.navigation_key = nil
        self.navigation_position = nil
    end
    if parent and not parent:IsNull() and self.wall_entindex < 0 then
        parent:SetForceAttackTarget(nil)
        parent:Stop()
    end
end

local function is_ground(unit)
    return (unit.survival_wave_movement_type
        or unit.survival_movement_type_override
        or unit.survival_movement_type
        or "ground") == "ground"
end

local function distance_2d(a, b)
    local x, y = a.x - b.x, a.y - b.y
    return math.sqrt(x * x + y * y)
end

local function move_to(parent, position)
    ExecuteOrderFromTable({
        UnitIndex = parent:entindex(),
        OrderType = DOTA_UNIT_ORDER_MOVE_TO_POSITION,
        Position = position,
        Queue = false,
    })
end

local function same_position(a, b)
    return a ~= nil and b ~= nil and distance_2d(a, b) <= 1
end

function M:MoveToOnce(parent, position, navigation_key)
    if self.navigation_key == navigation_key
        and same_position(self.navigation_position, position)
    then
        return
    end
    self.navigation_key = navigation_key
    self.navigation_position = Vector(position.x, position.y, position.z or 0)
    move_to(parent, position)
end

function M:UpdateGroundEngagement(parent, wall)
    local previous_slot = self.engagement_slot
    self.engagement_slot = wall_engagement_slots.claim(wall, parent)
    if previous_slot ~= self.engagement_slot then
        self.engagement_arrived = nil
        self.navigation_key = nil
        self.navigation_position = nil
    end
    local position, navigation_key
    if self.engagement_slot then
        position = wall_engagement_slots.position(wall, self.engagement_slot, 0)
        navigation_key = "slot:" .. tostring(self.engagement_slot)
    else
        local queue_slot, queue_row
        position, queue_slot, queue_row = wall_engagement_slots.queue_position(wall, parent)
        navigation_key = "queue:" .. tostring(queue_slot) .. ":" .. tostring(queue_row)
    end
    if not position then return false end

    local distance = distance_2d(parent:GetAbsOrigin(), position)
    if self.engagement_slot then
        if self.engagement_arrived
            and distance <= DEPARTURE_DISTANCE
        then
            self.navigation_key = nil
            self.navigation_position = nil
            return false
        end
        if distance <= ARRIVAL_DISTANCE then
            self.engagement_arrived = true
            self.navigation_key = nil
            self.navigation_position = nil
            return false
        end
    end

    self.engagement_arrived = nil
    self:MoveToOnce(parent, position, navigation_key)
    if not self.engagement_slot or distance > ARRIVAL_DISTANCE then
        return true
    end
    return false
end

function M:OnIntervalThink()
    if not IsServer() then return end
    local parent = self:GetParent()
    if not parent or parent:IsNull() or not parent:IsAlive() then return end

    if self.wall_entindex < 0 then
        parent:SetForceAttackTarget(nil)
        return
    end

    local wall = EntIndexToHScript(self.wall_entindex)
    if not wall or wall:IsNull() or not wall:IsAlive() then
        self:SetWallEntIndex(-1)
        return
    end

    team_alignment.enforce(parent, DOTA_TEAM_BADGUYS, "wave_enemy_ai")
    if not team_alignment.are_enemies(parent, wall) then
        team_alignment.enforce(wall, DOTA_TEAM_GOODGUYS, "wall_target")
    end
    if not team_alignment.are_enemies(parent, wall) then return end

    if is_ground(parent) then
        -- Engagement positions only control movement. The wall remains the
        -- unit's sole target even while it waits behind the front row.
        parent:SetForceAttackTarget(wall)
        self:UpdateGroundEngagement(parent, wall)
        if parent:GetAttackTarget() ~= wall then
            ExecuteOrderFromTable({
                UnitIndex = parent:entindex(),
                OrderType = DOTA_UNIT_ORDER_ATTACK_TARGET,
                TargetIndex = wall:entindex(),
                Queue = false,
            })
        end
        return
    end

    parent:SetForceAttackTarget(wall)
    if parent:GetAttackTarget() ~= wall then
        ExecuteOrderFromTable({
            UnitIndex = parent:entindex(),
            OrderType = DOTA_UNIT_ORDER_ATTACK_TARGET,
            TargetIndex = wall:entindex(),
            Queue = false,
        })
    end
end

function M:OnDestroy()
    if not IsServer() then return end
    local parent = self:GetParent()
    if parent and not parent:IsNull() then
        wall_engagement_slots.release(self.wall_entindex, parent:entindex())
        parent:SetForceAttackTarget(nil)
    end
end

return M
