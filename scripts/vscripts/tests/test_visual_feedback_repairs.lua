-- Engine-slot bounds and explicit wall-repair lifecycle regression.
package.path = 'scripts/vscripts/?.lua;' .. package.path
local function ability(name)
    return {GetAbilityName=function() return name end, IsNull=function() return false end,
        IsHidden=function() return false end, SetLevel=function() end, SetActivated=function() end, SetHidden=function() end}
end
local u={slots={ability('route_upgrade'),ability('route_passive')},reads=0}
function u:IsNull() return false end
function u:GetAbilityCount() return #self.slots end
function u:GetAbilityByIndex(i)
    assert(i>=0 and i<#self.slots,'out-of-range engine skill index')
    self.reads=self.reads+1;return self.slots[i+1]
end
function u:FindAbilityByName(name) for _,a in ipairs(self.slots) do if a:GetAbilityName()==name then return a end end end
function u:RemoveAbility(name) for i=#self.slots,1,-1 do if self.slots[i]:GetAbilityName()==name then table.remove(self.slots,i) end end end
function u:AddAbility(name) local a=ability(name);self.slots[#self.slots+1]=a;return a end
local utility=require('systems/tower_utility_ability_sync')
local row={active_skill_ids={utility.MOVE_ABILITY,utility.DESTROY_ABILITY}}
for i=1,3 do utility.sync({unit=u,building_id='arrow_tower'},row) end
assert(u.reads==6 and #u.slots==4)
u.slots={};utility.sync({unit=u,building_id='arrow_tower'},row)
assert(u.reads==6 and #u.slots==2,'empty native slot list must not read slot zero')
print('ABILITY_SLOT_BOUNDS_PASS')
class=function(t) t.__index=t;return t end
IsServer=function() return true end
DOTA_UNIT_ORDER_STOP=1;DOTA_UNIT_ORDER_MOVE_TO_TARGET=2;DOTA_UNIT_ORDER_ATTACK_TARGET=3;DOTA_UNIT_ORDER_MOVE_TO_POSITION=4
FIND_UNITS_EVERYWHERE=99999;ACT_DOTA_ATTACK=1
local function vec(x,y,z)
    return setmetatable({x=x,y=y,z=z or 0},{__sub=function(a,b) return vec(a.x-b.x,a.y-b.y,a.z-b.z) end,
        __index={Length2D=function(v) return math.sqrt(v.x*v.x+v.y*v.y) end}})
end
Vector=vec
local entities={}
local function entity(id,position)
    local e={position=position,health=1000,survival_player_id=0}
    function e:entindex() return id end
    function e:IsNull() return false end
    function e:IsAlive() return true end
    function e:GetTeamNumber() return 2 end
    function e:GetHealth() return self.health end
    function e:GetMaxHealth() return 1000 end
    function e:SetHealth(h) self.health=h end
    function e:GetAbsOrigin() return self.position end
    function e:GetHullRadius() return 32 end
    function e:HasModifier() return false end
    function e:FaceTowards() end
    function e:StartGesture() self.gestures=(self.gestures or 0)+1 end
    entities[id]=e;return e
end
EntIndexToHScript=function(id) return entities[id] end
local worker=entity(1,vec(0,0));local wall=entity(2,vec(1000,0));wall.survival_is_building=true
local approach=vec(800,0)
local path_calls=0
package.loaded['systems/builder_work_position_service']={find=function(parent,definition,origin)
    assert(parent==worker and origin==wall.position);path_calls=path_calls+1;return approach
end}
local repair=require('modifiers/modifier_repair_worker_ai')
local m=setmetatable({},repair)
function m:GetParent() return worker end
function m:StartIntervalThink() end
function worker:FindModifierByName() return m end
local orders={}
local service=require('systems/repair_order_service')
ExecuteOrderFromTable=function(order)
    orders[#orders+1]=order
    assert(not service.process({order_type=order.OrderType,units={1}}),'internal repair order must not replace target')
end
m:OnCreated({repair_max_health_pct_per_second=2,repair_range=200})
assert(service.process({order_type=DOTA_UNIT_ORDER_MOVE_TO_TARGET,entindex_target=2,units={1}}),'right-click full friendly wall must station repairer')
m:OnIntervalThink()
assert(orders[#orders].Position==approach and orders[#orders].Position~=wall.position)
for i=1,3 do m:OnIntervalThink() end
assert(path_calls==1,'path search and move order must not repeat every think')
worker.position=approach;m:OnIntervalThink()
assert(m.manual_repair_target_entindex==2 and worker.gestures==nil,'wait by a full wall')
wall.health=985
for i=1,3 do m:OnIntervalThink() end
assert(wall.health==1000 and m.manual_repair_target_entindex==2,'repair same 2 percent per second then stay assigned')
wall.health=900;m:OnIntervalThink();assert(wall.health==905,'later damage automatically resumes repair')
assert(not service.process({order_type=DOTA_UNIT_ORDER_MOVE_TO_POSITION,units={1}}))
assert(m.manual_repair_target_entindex==nil,'player movement cancels manual repair')
wall.survival_player_id=1
assert(not service.process({order_type=DOTA_UNIT_ORDER_MOVE_TO_TARGET,entindex_target=2,units={1}}),'cannot repair another owner wall')
print('MANUAL_WALL_REPAIR_PASS: full wall, safe approach, throttled path, resume, unchanged heal rate, cancel, owner')
-- Model bodies must remain under the NPC activity graph after applying an outfit.
package.loaded['config/asset_catalog']={resolve=function() return {asset_id='wave10',asset_type='model_bundle',primary_model='bloodseeker.vmdl',components={{component_id='head'}}} end}
local part={}
function part:IsNull() return false end
function part:ResetSequence(name) assert(name=='idle');self.idle=true end
package.loaded['visual/model_appearance_service']={Apply=function() return true,'ok',{head=part} end}
package.loaded['visual/monster_cosmetic_details']={apply=function() end}
package.loaded['core/logger']={warn=function() end}
local body={}
function body:IsNull() return false end
function body:ResetSequence() error('NPC body must not be locked to idle') end
function body:SetPlaybackRate(rate) self.rate=rate end
local model=require('systems/monster_hero_visual_service')
assert(model.apply(body,{default_wearable_asset_id='wave10'},{formal_wave=true,wave_number=10}))
assert(body.rate==1 and part.idle)
print('MONSTER_ACTIVITY_OWNERSHIP_PASS')
