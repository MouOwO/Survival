-- The former wall-priority contract is replaced by nearest-to-tower acquisition
-- and a combat lock; exercise real targeting, auto-attack and relocation.
package.path = "scripts/vscripts/?.lua;" .. package.path
class = function(value) return value end
LinkLuaModifier = function() end
IsServer = function() return true end
DOTA_UNIT_TARGET_TEAM_ENEMY, DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC = 1, 1, 2
DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES, FIND_ANY_ORDER = 4, 0
local noop = function() end
local vector_mt = {__index = {Length2D = function() error("target selection must not take a square root") end}}
Vector = function(x, y, z) return setmetatable({x=x, y=y or 0, z=z or 0}, vector_mt) end
vector_mt.__sub = function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
local function unit(id,x,y,team)
    local value = {id=id, position=Vector(x,y), team=team or 3, alive=true}
    function value:IsNull() return self.removed == true end
    function value:IsAlive() return self.alive end
    function value:entindex() return self.id end
    function value:GetTeamNumber() return self.team end
    function value:GetUnitName() return self.name or "wave_monster" end
    function value:GetAbsOrigin() return self.position end
    function value:SetAbsOrigin(position) self.position=position end
    return value
end
local walls = {[0]=unit(90,1000,0,2), [1]=unit(91,-1000,0,2)}
local wall_queries = 0
package.loaded["systems/building_system"] = {wall_for_player=function(id)
    wall_queries=wall_queries+1; return walls[id]
end}
local tower = unit(1,0,0,2)
tower.survival_player_id, tower.survival_building_id = 0, "arrow_tower"
function tower:Script_GetAttackRange() return self.range or 1000 end
function tower:GetAttackRange() return 300 end -- stale getter cannot shrink script range
function tower:GetPlayerOwnerID() return 0 end
local candidates, queries = {}, {}
FindUnitsInRadius = function(_,origin,_,radius,_,_,_,order)
    assert(order == FIND_ANY_ORDER, "use one squared-distance pass over unsorted candidates")
    queries[#queries+1] = {origin=origin, radius=radius}
    return candidates
end
local targeting = require("systems/tower_targeting")
local near_tower, near_wall, outside = unit(20,50), unit(30,900), unit(2,1001)
local tree, friendly, dead = unit(3,995), unit(4,998,0,2), unit(5,999)
tree.name, dead.alive = "enemy_tree", false
candidates = {near_tower, outside, tree, friendly, dead, near_wall}
local original_sqrt = math.sqrt
math.sqrt = function() error("target selection must not take a square root") end
assert(targeting.select(tower) == near_tower, "choose the nearest in-range enemy to the tower")
assert(queries[#queries].radius == 1000)
assert(not targeting.valid(tower,outside), "old range tolerance must not retain an out-of-range target")
assert(targeting.select(tower,near_tower) == near_wall, "excluded corpse can still report alive")
near_wall.alive = false
assert(targeting.select(tower) == near_tower)
near_wall.alive = true
near_wall.position = Vector(1001,0)
assert(targeting.select(tower) == near_tower, "leaving range must select a legal alternative")
near_wall.position = Vector(900,0)

local negative = unit(40,-900)
candidates = {near_wall, negative, near_tower}
tower.survival_player_id = 1
assert(targeting.select(tower) == near_tower, "player slot cannot change distance from the tower")
tower.survival_player_id = nil
assert(targeting.select(tower) == near_tower, "native owner cannot override tower proximity")
tower.survival_player_id = 0
walls[0].position = Vector(-1000,0)
assert(targeting.select(tower) == near_tower, "moving a wall must not change tower acquisition priority")
walls[0].position = Vector(1000,0)
walls[0].alive = false
assert(targeting.select(tower) == near_tower, "tower priority does not require a living wall")
walls[0].alive = true
assert(wall_queries==0, "acquisition must not query building or wall ownership")

local diagonal, beyond_diagonal = unit(50,600,800), unit(51,600,800.01)
diagonal.position.z = 5000 -- range and proximity are horizontal
candidates = {beyond_diagonal, diagonal}
assert(targeting.select(tower) == diagonal and targeting.valid(tower,diagonal))
assert(not targeting.valid(tower,beyond_diagonal), "squared range must include both horizontal axes")
local tie_high, tie_low = unit(61,900,100), unit(60,900,-100)
candidates = {tie_high,tie_low}
assert(targeting.select(tower) == tie_low, "equal tower distances have a deterministic tie break")
candidates = {tie_low,tie_high}
assert(targeting.select(tower) == tie_low)

local dummy = unit(70,1000)
dummy.survival_is_training_dummy = true
candidates = {dummy, near_tower, tree}
assert(targeting.select(tower) == near_tower, "real enemies outrank training targets")
candidates = {dummy,tree}
assert(targeting.select(tower) == dummy)
local flying = unit(71,700)
flying.survival_movement_type = "flying"
tower.survival_tower_class = "class_7"
candidates = {near_wall,tree,flying}
assert(targeting.select(tower) == flying, "nearest acquisition must retain anti-air eligibility")
tower.survival_tower_class = nil
math.sqrt = original_sqrt

-- Exercise actual relocation and both target refreshes, rather than a fake move.
local auto_class = require("modifiers/modifier_tower_auto_attack")
local auto = setmetatable({}, {__index=auto_class})
function auto:GetParent() return tower end
function auto:GetStackCount() return self.stack or 0 end
function auto:SetStackCount(count) self.stack=count end
auto.ForceRefresh, auto.StartIntervalThink = noop, noop
function tower:GetAttackTarget() return self.target end
function tower:SetForceAttackTarget(target) self.forced=target end
function tower:MoveToTargetToAttack(target) self.target=target end
function tower:Stop() self.target=nil end
tower.SetAcquisitionRange, tower.SetIdleAcquire = noop, noop
function tower:FindModifierByName(name)
    if name == "modifier_tower_auto_attack" then return auto end
end
tower.RemoveModifierByName, tower.AddNewModifier = noop, noop
function tower:PerformAttack() error("relocation must not add attacks") end
function tower:AttackNoEarlierThan() error("relocation must not reset attack cooldown") end
auto:OnCreated()
local before_move, after_move = unit(80,700), unit(81,400)
local closest_after_move = unit(82,-400)
candidates = {closest_after_move,after_move,before_move}
auto:OnIntervalThink()
assert(tower.target == after_move)
auto:OnAttackStart({attacker=tower,target=after_move})
after_move.position = Vector(1001,0)
auto:OnIntervalThink()
assert(tower.target == closest_after_move and not auto.windup_target,
    "an out-of-range victim must be replaced even during windup")
after_move.position = Vector(400,0)
local locked_queries = #queries
auto:OnIntervalThink()
assert(tower.target == closest_after_move and #queries==locked_queries,
    "returning enemies must not cause a fresh query while the victim remains legal")
auto:OnAttackStart({attacker=tower,target=closest_after_move})

local bus, events = require("core/event_bus"), require("core/events")
local relocation = require("systems/building_relocation")
local state = {unit=tower, grid_x=0, grid_y=0, team=2, definition={footprint={x=2,y=2}}}
relocation.bind(function(id) assert(id==1); return state end, function(s) return s end)
bus.handle_request(events.GRID_CAN_PLACE_REQUEST, function(payload)
    return {ok=true, grid_x=1, grid_y=2, world_position=payload.position}
end)
bus.handle_request(events.GRID_RELEASE_REQUEST, function() return {ok=true} end)
bus.handle_request(events.GRID_OCCUPY_REQUEST, function() return {ok=true} end)
local refresh
GameRules = {GetGameModeEntity=function() return {SetContextThink=function(_,_,callback,delay)
    assert(delay==0.06, "keep the existing network refresh, add no new timer")
    refresh=callback
end} end}
local function move_and_check(position,expected)
    local count = #queries
    assert(relocation.move(tower,position))
    assert(tower.target==expected, "move must immediately select at the new position")
    assert(#queries==count+1 and queries[#queries].origin.x==position.x)
    assert(not auto.windup_target, "old windup must not lock the target after a move")
    assert(refresh() == nil)
    assert(tower.target==expected, "network refresh must restore nearest-to-tower targeting immediately")
    assert(#queries==count+2 and queries[#queries].origin.x==position.x)
end
move_and_check(Vector(-500,0),closest_after_move)
move_and_check(Vector(500,0),after_move) -- old victim is still in range; moving resets acquisition
print("TOWER_NEAREST_TARGETING_PASS: squared 2D tower proximity, wall independence, combat lock, range boundary, exclusions, ties, anti-air, real relocation and delayed refresh")
