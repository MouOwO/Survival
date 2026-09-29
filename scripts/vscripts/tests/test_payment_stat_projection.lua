-- Drive real profile -> permanent effects -> resource/building consumers.
-- Engine units are stubs; reward arithmetic and event order remain real.
package.path='scripts/vscripts/?.lua;'..package.path
local bus=require('core/event_bus');local events=require('core/events')
local config=require('config/buildings_config')
local noop=function()end
package.loaded['core/scheduler']={every=noop,cancel=noop}
for _,name in ipairs({'tower_skill_runtime','tower_ability_sync','building_population_service',
 'building_visual_service','asset_preload_service','building_sound_service','tower_utility_ability_sync'}) do
 package.loaded['systems/'..name]={reset=noop,apply=noop,sync=noop}
end
package.loaded['debug/dev_wall_stats']={apply=noop}
package.loaded['systems/building_upgrade_process']={reset=noop,is_active=function()return false end}
package.loaded['systems/rogue_effect_state_service']={wall_health_flat=function()return 0 end}
package.loaded['systems/technology_stat_manager']={get=function()return {final={tower={},wall={}}} end}
local stats={initial_wood=80,initial_gold=0,wall_armor=30,wall_initial_health=1100,tower_attack_flat=0}
local profile={revision=1,save={gameplay_stats=stats}}
package.loaded['systems/player_profile_service']={get_profile=function()return profile end}
PlayerResource={GetTeam=function()return 2 end}
Entities={FindAllByClassname=function()return {} end}
local errors={};local real_print=print
print=function(message,...)
 if tostring(message):find('[EventBus] handler error',1,true) then errors[#errors+1]=tostring(message)
 else real_print(message,...) end
end
local function unit(id)
 local u={index=id,damage=100,health=100,max_health=100,survival_player_id=0,modifiers={}}
 function u:IsNull()return false end
 function u:IsAlive()return true end
 function u:entindex()return self.index end
 function u:GetPlayerOwnerID()return 0 end
 function u:GetTeamNumber()return 2 end
 function u:GetUnitName()return self.name end
 function u:GetBaseDamageMin()return self.damage end
 function u:SetBaseDamageMin(value)self.damage=value end
 function u:GetMaxHealth()return self.max_health end
 function u:GetHealth()return self.health end
 function u:SetMaxHealth(value)self.max_health=value end
 function u:SetHealth(value)self.health=value end
 function u:HasModifier(name)return self.modifiers[name]~=nil end
 function u:AddNewModifier(_,_,name)self.modifiers[name]={} end
 for _,method in ipairs({'SetBaseDamageMax','SetBaseAttackTime','Script_SetAttackRange','SetAcquisitionRange',
  'SetProjectileSpeed','SetBaseMaxHealth','SetPhysicalArmorBaseValue','SetBaseHealthRegen'}) do u[method]=noop end
 return u
end
require('systems/permanent_reward_effect_service').init()
require('systems/resource_system').init()
require('systems/building_upgrade_system').init()
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,reason='login'})
local wall,tower=unit(10),unit(11);wall.name='building_wall';tower.name='building_arrow_tower'
for _,v in ipairs({{wall,'wall',config.wall},{tower,'arrow_tower',config.arrow_tower}}) do
 bus.emit(events.BUILDING_CREATED,{unit=v[1],entindex=v[1].index,definition=v[3],building_id=v[2],
  level=1,team=2,player_id=0,base_attack_damage=100})
end
local function values()
 local wallet=bus.request(events.RESOURCE_GET_REQUEST,{player_id=0})
 return {wallet.wood,wallet.gold,wall.survival_war3_armor,wall:GetMaxHealth(),tower:GetBaseDamageMin()}
end
local baseline=values()
local fields={'initial_wood','initial_gold','wall_armor','wall_initial_health','tower_attack_flat'}
for index,field in ipairs(fields) do
 local before=values();stats[field]=stats[field]+100;profile.revision=profile.revision+1
 bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,reason='payment_delivered'})
 local after=values()
 assert(#errors==0,table.concat(errors,'\n'))
 for i=1,5 do assert(after[i]-before[i]==(i==index and 100 or 0),field..' changed wrong live stat') end
 bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,reason='payment_delivered'})
 local repeated=values();for i=1,5 do assert(repeated[i]==after[i],'duplicate snapshot reapplied reward') end
end
for _,field in ipairs(fields) do stats[field]=stats[field]-100 end
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,reason='payment_test_reset'})
local reset=values();for i=1,5 do assert(reset[i]==baseline[i],'reset must restore resources/buildings') end
assert(#errors==0,table.concat(errors,'\n'))
print('PAYMENT_STAT_PROJECTION_PASS: five exact +100 live effects, idempotent refresh, reset reversal')
