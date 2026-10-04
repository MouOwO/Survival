package.path='scripts/vscripts/?.lua;'..package.path
local bus=require('core/event_bus');local events=require('core/events')
local clock=0;local tasks={};local owned={teleporter=true,saw=true,orbital=true,lumberyard=true}
GameRules={GetGameTime=function() return clock end}
package.loaded['core/scheduler']={every=function(_,f,key) tasks[key]=f end}
package.loaded['systems/commerce_effects']={owned=function(id,key)return id==0 and owned[key] end,invalidate=function()end}
package.loaded['systems/player_context_service']={is_defeated=function()return false end,active_player_ids=function()return {0} end}
package.loaded['systems/worker_system']={refresh_commerce_capacity=function()end}
package.loaded['systems/gameplay_phase_guard']={post_clear_frozen=function()return false end}
local moved,allowed=0,false
package.loaded['systems/destination_validation_service']={teleport=function() if not allowed then return false,'blocked' end;moved=moved+1;return true end}
PlayerResource={IsValidPlayerID=function(_,id)return id==0 end}
local tables={};CustomNetTables={SetTableValue=function(_,name,key,value)tables[name..key]=value end}
CustomGameEventManager={RegisterListener=function()end}
Vector=function(x,y,z)return {x=x,y=y,z=z}end
GetGroundHeight=function()return 0 end
DOTA_UNIT_TARGET_TEAM_ENEMY=1;DOTA_UNIT_TARGET_HERO=1;DOTA_UNIT_TARGET_BASIC=2;DOTA_UNIT_TARGET_FLAG_NONE=0;FIND_ANY_ORDER=0;DAMAGE_TYPE_PHYSICAL=1
local function unit(id,boss)
    return {survival_player_id=id,survival_is_wave_monster=true,survival_is_boss=boss,
        IsNull=function()return false end,IsAlive=function()return true end,GetTeamNumber=function()return 2 end,
        GetAbsOrigin=function()return Vector(0,0,0)end,GetStrength=function()return 2 end,GetAgility=function()return 3 end,GetIntellect=function()return 5 end,
        AddNewModifier=function(self)self.stripped=(self.stripped or 0)+1 end,Kill=function(self)self.killed=true end}
end
local hero,wall=unit(0),unit(0)
local mine,foreign,boss=unit(0),unit(1),unit(0,true)
FindUnitsInRadius=function()return {mine,foreign,boss}end
local damage={};ApplyDamage=function(p)damage[#damage+1]=p end
bus.handle_request(events.HERO_SUMMON_GET_REQUEST,function()return {unit=hero}end)
bus.handle_request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,function()return {totals={hero_attack_armor_reduction=10}}end)
local research={};local grants=0
bus.handle_request(events.RESEARCH_STATE_GET_REQUEST,function()return {levels=research}end)
bus.handle_request(events.RESEARCH_LEVEL_SET_REQUEST,function(p)research[p.tech_id]=p.level;grants=grants+1;return {ok=true}end)
local runtime=require('systems/commerce_runtime');runtime.init()
runtime.action({PlayerID=1,action='blink',x=100,y=100});assert(moved==0)
runtime.action({PlayerID=0,action='blink',x=100,y=100});assert(moved==0)
allowed=true;runtime.action({PlayerID=0,action='blink',x=100,y=100});assert(moved==1,'failed blink must not consume cooldown')
runtime.action({PlayerID=0,action='blink',x=100,y=100});assert(moved==1)
clock=10;runtime.action({PlayerID=0,action='blink',x=100,y=100});assert(moved==2)
clock=20;runtime.action({PlayerID=0,action='blink',x=math.huge,y=100});assert(moved==2)
runtime.action({PlayerID=0,action='bomb'});assert(mine.killed and not foreign.killed and not boss.killed)
mine.killed=false;runtime.action({PlayerID=0,action='bomb'});assert(not mine.killed,'bomb only once per match')
tasks.commerce_runtime();tasks.commerce_runtime();assert(grants==2 and research['RS-06']==5 and research['RS-08']==5)
bus.emit(events.BUILDING_CREATED,{player_id=0,building_id='wall',unit=wall})
runtime.orbital(0,'wave:1');local shot=tasks.commerce_orbital_0;assert(shot)
for i=1,20 do assert(shot()==(i<20)) end
assert(#damage==40 and mine.stripped==20 and boss.stripped==20 and not foreign.stripped)
assert(damage[1].damage==100 and damage[1].attacker==hero)
tasks.commerce_orbital_0=nil;runtime.orbital(0,'wave:1');assert(not tasks.commerce_orbital_0,'repeated wave ignored')
runtime.orbital(0,'wave:2');assert(not tasks.commerce_orbital_0,'ten-second cooldown')
clock=30;runtime.orbital(0,'endless:1');assert(tasks.commerce_orbital_0)
print('COMMERCE_RUNTIME_PASS: blink validation, cooldown, owner-only one-use bomb, research once, twenty orbital ticks, endless and dedup')
