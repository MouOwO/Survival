-- Pure Lua A/B verification of the real four-player damage pipeline.
-- No game process, save writes, network, timing hook or native binding is used.
package.path='scripts/vscripts/?.lua;'..package.path
local function suite(sourcecode,optimized)
local bus=require('core/event_bus');bus.reset()
for _,name in ipairs({'systems/permanent_reward_effect_service','systems/weapon_growth_service','ui/combat_stats_ui_service'})do package.loaded[name]=nil end
local bus,ev=require('core/event_bus'),require('core/events')
local defs,weapons=require('config/generated/player_gameplay_stats'),require('config/generated/weapon_definitions')
local profiles,heroes,mods,ledger,published,jobs,entities,before={},{},{},{},{},{},{},{}
local floats,shots={},0
local acceptedRecords={}
local function encode(v)
 if type(v)~='table' then return tostring(v) end
 if type(v.entindex)=='function' then return 'entity:'..v:entindex() end
 local keys,out={},{};for k in pairs(v)do keys[#keys+1]=k end;table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
 for _,k in ipairs(keys)do out[#out+1]=tostring(k)..'='..encode(v[k])end;return '{'..table.concat(out,',')..'}'
end
PlayerResource={IsValidPlayerID=function(_,id)return id>=0 and id<4 end}
package.loaded['systems/player_context_service']=nil
local context=require('systems/player_context_service');local resolve_owner
resolve_owner=context.owner_player_id
context.owner_player_id=function(u)
 if u.owner_probe=='throw' then error('owner query failed') end
 if u.owner_probe=='nil' then return nil end
 if type(u.owner_probe)=='number' then return u.owner_probe end
 return resolve_owner(u)
end
package.loaded['core/scheduler']={every=function()end,after=function(_,fn)jobs[#jobs+1]=fn end,cancel=function()end}
package.loaded['systems/gameplay_phase_guard']={post_clear_frozen=function()return false end}
package.loaded['systems/technology_stat_manager']={get=function(id)return {own=id}end,training_room_multiplier=function(id,target)return target.survival_training_owner_player_id==id and id+2 or 1 end}
package.loaded['systems/player_profile_service']={get_profile=function(id)return profiles[id]end}
CustomNetTables={SetTableValue=function(_,t,key,value)published[t..':'..key]=value end}
EntIndexToHScript=function(id)return entities[id]end
class=function(t)return t end;IsServer=function()return true end;DAMAGE_TYPE_PHYSICAL=1
local function unit(id,owner,kind)
 local u={index=id,owner=owner,team=kind=='enemy' and 3 or 2,alive=true,health=100,maximum=1000,survival_player_id=owner}
 function u:IsNull()return false end;function u:entindex()return self.index end;function u:GetTeamNumber()return self.team end
 function u:AddNewModifier()end;function u:IsBuilding()return kind=='tower' or kind=='city' end
 function u:IsClone()return kind=='clone' end;function u:IsAlive()return self.alive end;function u:IsIllusion()return false end
 function u:GetOwnerEntity()return self.parent end;function u:GetPlayerOwnerID()return self.owner end
 function u:GetUnitName()return kind=='enemy' and 'enemy_monster' or kind=='worker' and 'npc_survival_lumberjack' or 'npc_dota_hero_axe' end
 function u:GetPhysicalArmorValue()return 0 end;function u:GetHealth()return self.health end;function u:GetMaxHealth()return self.maximum end
 function u:Kill(_,killer)self.alive=false;self.killer=killer end
 entities[id]=u;return u
end
local ids={};for id,d in pairs(weapons.by_id)do if d.series_id=='ice_blade' then ids[#ids+1]=id end end;table.sort(ids);assert(#ids>=4)
local permanent=require('systems/permanent_reward_effect_service');permanent.init()
local growth=require('systems/weapon_growth_service');growth.init()
local ui=require('ui/combat_stats_ui_service');ui.init()
bus.handle_request(ev.RESOURCE_ADD_REQUEST,function(p)local l=ledger[p.player_id];l.wood=l.wood+(p.wood or 0);l.gold=l.gold+(p.gold or 0);return {ok=true}end)
bus.handle_request(ev.CONTENT_INVENTORY_GET_REQUEST,function()return {ok=true,snapshot={counts={}}}end)
local emissions=0;bus.subscribe(ev.COMBAT_DAMAGE_RESOLVED,function(p)
 emissions=emissions+1
 -- Snapshot acceptance while the event is delivered; ownership can later change.
 if p.owner_hero==p.attacker or (p.attacker.GetOwnerEntity and p.attacker:GetOwnerEntity()==p.owner_hero)
  or p.player_id==nil then acceptedRecords[#acceptedRecords+1]=encode(p) end
end)
assert(loadstring(sourcecode, '@modifier_weapon_stat_projection_under_test.lua'))();
modifier_weapon_stat_projection.ShowFinalAttackDamage=function(id,a,t,p)floats[#floats+1]=encode({type='attack',player=id,attacker=a,target=t,damage=p.damage})end
modifier_weapon_stat_projection.ShowFinalAbilityDamage=function(id,a,t,p)floats[#floats+1]=encode({type='ability',player=id,attacker=a,target=t,damage=p.damage})end
local function totals(id)return bus.request(ev.PERMANENT_REWARD_EFFECTS_GET_REQUEST,{player_id=id}).totals end
local function weapon(id)return bus.request(ev.WEAPON_GROWTH_GET_REQUEST,{player_id=id}).snapshot end
for id=0,3 do
 local s={};for _,r in ipairs(defs.rows)do s[r.field_id]=r.default_value end
 s.hero_damage_attack_growth=10*(id+1);s.hero_attributes_per_damage=3*(id+1);s.hero_damage_wood_flat=7*(id+1);s.hero_damage_gold_flat=2*(id+1);s.hero_execute_health_threshold_pct=id==1 and 90 or 0
 profiles[id]={mode='pure',revision=id+1,save={gameplay_stats=s,permanent_effects={},match_boss_effects={}}};ledger[id]={wood=0,gold=0};heroes[id]=unit(100+id,id,'hero')
 bus.emit(ev.PLAYER_PROFILE_CHANGED,{player_id=id});bus.emit(ev.HERO_SUMMONED,{player_id=id,unit=heroes[id]});bus.emit(ev.WEAPON_EQUIPPED_CHANGED,{player_id=id,slot='main_hand',content_id=ids[id+1]})
 mods[id]=setmetatable({player_id=id,parent=heroes[id]},{__index=modifier_weapon_stat_projection});mods[id].GetParent=function(self)return self.parent end
 local t=totals(id);before[id]={attack=t.hero_attack_flat or 0,attrs=t.hero_all_attributes_flat or 0}
end
local function shot(attacker,target)
 shots=shots+1;target=target or unit(500+shots,nil,'enemy');for id=0,3 do mods[id]:OnTakeDamage({attacker=attacker,unit=target,damage=11,damage_type=1})end
 for _,fn in ipairs(jobs)do fn()end;jobs={};return target
end
local target=unit(500,nil,'enemy');local count=emissions;shot(heroes[0],target);assert(emissions-count==(optimized and 1 or 4) and target.alive,'foreign P1 threshold must not execute P0 target')
for id=0,3 do
 assert(ledger[id].wood==(id==0 and 7 or 0) and ledger[id].gold==(id==0 and 2 or 0),'resource owner isolation')
 assert((totals(id).hero_attack_flat or 0)-before[id].attack==(id==0 and 10 or 0),'permanent attack delta isolation')
 assert((totals(id).hero_all_attributes_flat or 0)-before[id].attrs==(id==0 and 3 or 0),'permanent attribute delta isolation')
 assert(weapon(id).growth_attack==(id==0 and weapons.by_id[ids[1]].attack_gain_per_attack or 0),'weapon growth isolation')
 local d=published['survival_combat_debug:player_'..id];assert(d.hit_count==(id==0 and 1 or 0),'UI debug owner isolation')
end
local clone=unit(600,0,'clone');clone.survival_monkey_king_clone=true;clone.parent=heroes[0];local growth_before=weapon(0).growth_attack;shot(clone)
assert(weapon(0).growth_attack-growth_before==weapons.by_id[ids[1]].attack_gain_per_attack,'owned clone own weapon growth')
assert(ledger[0].wood==7 and totals(0).hero_attack_flat-before[0].attack==10,'clone cannot trigger direct-hero rewards')
local tower=unit(610,0,'tower');tower.parent=heroes[0];shot(tower);local city=unit(620,0,'city');local worker=unit(621,0,'worker');worker.parent=city;shot(worker)
for id=0,3 do assert(ledger[id].wood==(id==0 and 7 or 0),'tower/worker cannot grant hero resources')end
local killed=shot(heroes[1]);assert(not killed.alive and killed.killer==heroes[1],'P1 own threshold preserved')
for id=0,3 do local w=ledger[id];assert(w.wood==(id==0 and 7 or id==1 and 14 or 0),'independent save resources');assert(w.gold==(id==0 and 2 or id==1 and 4 or 0))end
local ownBusiness={};for id=0,3 do ownBusiness[id]={totals=totals(id),weapon=weapon(id),ledger=ledger[id],ui=published['survival_combat_debug:player_'..id]}end
-- Same-player families, native-only IDs, current ownership transfer and fallback contracts.
local derived=unit(700,0,'derived');derived.parent=heroes[0];derived.survival_player_id=nil
local prior=emissions;shot(derived);assert(emissions-prior==(optimized and 1 or 4),'native owner routes once')
derived.owner=1;derived.parent=heroes[1];prior=emissions;shot(derived);assert(emissions-prior==(optimized and 1 or 4),'current owner is queried rather than cached')
local registered=unit(710,0,'derived');registered.parent=heroes[0]
assert(context.register_unit(0,registered,'test_damage_source'))
prior=emissions;shot(registered);assert(emissions-prior==(optimized and 1 or 4),'formal registered source remains owned')
registered.survival_player_id=1
prior=emissions;shot(registered);assert(emissions-prior==4,'conflicting formal owner retains legacy delivery')
local nativeThrow=unit(711,nil,'derived');nativeThrow.parent=heroes[0]
nativeThrow.GetPlayerOwnerID=function()error('native owner unavailable')end
prior=emissions;shot(nativeThrow);assert(emissions-prior==4,'failed native owner query retains legacy delivery')
nativeThrow.GetPlayerOwner=function()return {GetPlayerID=function()return 0 end}end
prior=emissions;shot(nativeThrow);assert(emissions-prior==(optimized and 1 or 4),'native player-object fallback remains owned')
local unknownCases={};for _,mode in ipairs({'nil','throw',-1,math.huge,0/0,1.25,99})do
 local d=unit(720+#unknownCases,0,'derived');d.parent=heroes[0];d.survival_player_id=nil;d.owner_probe=mode
 local start=emissions;shot(d);assert(emissions-start==4,'unknown/throw/invalid owner retains legacy delivery')
 unknownCases[#unknownCases+1]=true
end
local resourceValid=PlayerResource.IsValidPlayerID;PlayerResource.IsValidPlayerID=function()error('validity query failed')end
prior=emissions;shot(derived);assert(emissions-prior==4,'failed native validity retains legacy delivery');PlayerResource.IsValidPlayerID=resourceValid
local ghost=mods[2].player_id;mods[2].player_id=nil
prior=emissions;shot(heroes[0]);assert(emissions-prior==(optimized and 2 or 4),'receiver pid absent retains its legacy event');mods[2].player_id=ghost
-- Retired/invalid packets are rejected before owner work exactly as before.
for _,damage in ipairs({0,-5})do prior=emissions;for id=0,3 do mods[id]:OnTakeDamage({attacker=heroes[0],unit=target,damage=damage})end;assert(emissions==prior)end
local results={business=ownBusiness,floats=floats,final={},acceptedRecords=acceptedRecords}
for id=0,3 do results.final[id]={totals=totals(id),weapon=weapon(id),ledger=ledger[id],ui=published['survival_combat_debug:player_'..id]}end
return encode(results),emissions


end
local function read_source(path)
 local file=assert(io.open(path,'rb'));local source=file:read('*a');file:close();return (source:gsub('\r\n','\n'))
end
local source=read_source('scripts/vscripts/modifiers/modifier_weapon_stat_projection.lua')
local function remove_once(text,chunk)
 local first,last=text:find(chunk,1,true)
 assert(first,'Expected owner-filter change absent')
 assert(not text:find(chunk,last+1,true),'Owner-filter change occurs more than once')
 return text:sub(1,first-1)..text:sub(last+1)
end
-- A/B the real implementation: remove only this optimization from the baseline.
-- This keeps every pre-existing damage payload/getter/consumer in the comparison.
local baseline=arg[1] and read_source(arg[1]) or source
if not arg[1] then
 baseline=remove_once(baseline,'local player_context = require("systems/player_context_service")\n')
 local first=assert(baseline:find('-- Only a confirmed current owner can prune the old same-team delivery.',1,true))
 local last=assert(baseline:find('function modifier_weapon_stat_projection:OnTakeDamage(params)',first,true))
 baseline=baseline:sub(1,first-1)..baseline:sub(last)
 baseline=remove_once(baseline,[=[    local receiver = tonumber(self.player_id)
    if receiver ~= nil and receiver == receiver and receiver >= 0
        and receiver < math.huge and receiver == math.floor(receiver) then
        local owner = confirmed_damage_owner(attacker)
        if owner ~= nil and owner ~= receiver then return end
    end
]=])
end
local before,beforeEvents=suite(baseline,false)
local after,afterEvents=suite(source,true)
assert(before==after,'Accepted consumer data/event fields and own floating damage traces must remain byte-identical')
assert(afterEvents<beforeEvents,'Known foreign payloads were pruned')
print('WEAPON_DAMAGE_OWNER_FILTER_PASS 4 actual emitters -> actual permanent/growth/execution/UI: all accepted data/event fields/floating calls identical; native/context current owner and legal clone/derived; unknown/error/invalid/pid missing legacy; events '..beforeEvents..' -> '..afterEvents)
