package.path = "scripts/vscripts/?.lua;" .. package.path
local handlers, notifications = {}, {}
package.loaded['core/events'] = {UI_NOTIFICATION='notice',CHALLENGE_MATERIAL_DROP_REQUEST='drop',CHALLENGE_MATERIAL_PICKUP_REQUEST='pickup'}
package.loaded['core/event_bus'] = {emit=function(_,p) notifications[#notifications+1]=p end,handle_request=function(k,f) handlers[k]=f end}
local vector = {}; vector.__index=vector
function Vector(x,y,z) return setmetatable({x=x,y=y or 0,z=z or 0},vector) end
function vector.__sub(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function vector:Length2D() return math.sqrt(self.x*self.x+self.y*self.y) end
function class(t) return t end
function IsServer() return true end
UF_SUCCESS=0;UF_FAIL_CUSTOM=1;PATTACH_WORLDORIGIN=0;DOTA_TEAM_GOODGUYS=2
local index=0
local function entity(x)
 index=index+1;local id=index
 return {IsNull=function()return false end,GetAbsOrigin=function()return Vector(x)end,entindex=function()return id end,AddNewModifier=function()end}
end
local caster=entity(0);caster.GetPlayerOwnerID=function()return 0 end
local inventory,picked={},{}
function caster:GetItemInSlot(slot) return inventory[slot] end
function caster:AddItem(item) for i=0,8 do if not inventory[i] then inventory[i]=item;picked[#picked+1]=item;return end end end
local drops={}
local function ground(x,owner)
 local box,item=entity(x),entity(x);item.survival_owner_player_id=owner
 box.GetContainedItem=function()return item end;drops[#drops+1]=box;return item
end
local at_hero=ground(0,0);local at_target=ground(700,0);local edge=ground(1000,0)
ground(1001,0);ground(800,1)
Entities={FindAllByClassname=function()return drops end}
local ground_service=require('systems/ground_item_pickup_service')
local candidates=ground_service.nearby(caster,0,Vector(700))
assert(#candidates==2 and candidates[1].item==at_target and candidates[2].item==edge)
assert(#ground_service.nearby(caster,0)==1,'legacy hero-centered callers remain supported')
CreateUnitByName=function(_,pos)return entity(pos.x)end
local upgrades=require('systems/challenge_upgrade_material_service');upgrades.init()
for _,v in ipairs({{800,0},{0,0},{900,1}})do
 assert(handlers.drop({authoritative=true,challenge_id='challenge_10',required_stage=0,player_id=v[2],position=Vector(v[1])}).ok)
end
assert(#upgrades.nearby(caster,0,Vector(700))==1)
assert(#upgrades.nearby(caster,0)==1)
local upgrade_count=0;upgrades.pickup_candidate=function()upgrade_count=upgrade_count+1;return {ok=true}end
local cleanup={};local created,destroyed,released=0,0,0
ParticleManager={CreateParticle=function(_,path)assert(path=='particles/units/heroes/hero_riki/riki_smokebomb.vpcf');created=created+1;return created end,SetParticleControl=function(_,particle,point,value)if point==1 then assert(value.x==300)end end,DestroyParticle=function(_,particle,immediate)assert(immediate==true);destroyed=destroyed+1 end,ReleaseParticleIndex=function()released=released+1 end}
GameRules={GetGameModeEntity=function()return {SetContextThink=function(_,_,fn,delay)assert(delay==0.5);cleanup[#cleanup+1]=fn end}end}
require('abilities/ability_survival_pickup_materials')
local ability=setmetatable({},{__index=ability_survival_pickup_materials})
local target=Vector(700);ability.GetCaster=function()return caster end;ability.GetCursorPosition=function()return target end
local refunded=0;ability.EndCooldown=function()refunded=refunded+1 end
assert(ability:GetAOERadius()==300 and ability:GetCastRange()==700)
assert(ability:CastFilterResultLocation(Vector(700))==UF_SUCCESS)
assert(ability:CastFilterResultLocation(Vector(701))==UF_FAIL_CUSTOM)
assert(ability:CastFilterResultLocation(Vector(500,500))==UF_FAIL_CUSTOM)
ability:OnSpellStart()
assert(#picked==2 and picked[1]==at_target and picked[2]==edge and upgrade_count==1)
assert(picked[1]~=at_hero,'click must not collect around the hero')
target=Vector(701);ability:OnSpellStart();assert(#picked==2 and refunded==1 and created==1)
target=Vector(700);for i=0,8 do inventory[i]={}end
ability:OnSpellStart();assert(#picked==2 and upgrade_count==1,'full inventory stops before later candidates')
assert(notifications[#notifications].message:find('装备栏已满'))
for _,fn in ipairs(cleanup)do fn()end
assert(created==destroyed and created==released,'area effects are cleaned up')
print('TARGETED_AREA_PICKUP_PASS: 700 cast / 300 target radius, boundary, ownership, both drop types, full inventory, effect cleanup')
