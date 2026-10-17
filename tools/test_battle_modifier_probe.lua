-- Pure contract regression. C stack examples are not proof of Dota native calls.
package.path='scripts/vscripts/?.lua;'..package.path
local probe=require('tests/manual_battle_modifier_probe')
assert(probe.snapshot().status=='not_started' and probe.start().status=='disabled')
local clock,world,tools,clock_failed=0,{},true,false
local timers,entity_reads={},0
IsServer=function() return true end;IsInToolsMode=function() return tools end
GetSystemTimeMS=function() if clock_failed then error('diagnostic clock failure') end;return clock*1000 end
GameRules={GetGameModeEntity=function() return world end}
function world:SetContextThink(key,fn) timers[key]=fn end
local declarations,hits,intervals,handles=0,0,0,0
local error_object={expected_original_error=true}
local original=function(self,p,...)
    hits=hits+1
    if p.fail then error(error_object) end
    return p,nil,'unchanged',select('#',...)
end
local decl=function() declarations=declarations+1;return {9} end
modifier_rogue_combat_bonus={DeclareFunctions=decl,OnTakeDamage=original,GetMinHealth=function() return 1,nil,'property' end}
local equipment_base={OnTakeDamage=original}
modifier_equipment_effects=setmetatable({},{__index=equipment_base})
modifier_single_health_bar={OnIntervalThink=function(self,...) intervals=intervals+1;return nil,select('#',...) end,
    CheckState=function() return {hidden=true},nil,'state' end,publish_state=function() return false,nil,'publish' end}
modifier_building_damage_sound={HandleTakeDamage=function() handles=handles+1 end,
    OnTakeDamage=function(self,p) return self:HandleTakeDamage(p) end}
modifier_rogue_corrosive_shield_attack={OnAttack=function() end}
local serial=0
local function entity(kind,owner,alive)
    serial=serial+1
    local u={id=serial,kind=kind,owner=owner,alive=alive,mods={}}
    function u:IsNull() return false end;function u:IsAlive() return self.alive end
    function u:entindex() return self.id end;function u:GetUnitName() return self.kind end
    function u:GetPlayerOwnerID() return self.owner end
    function u:FindAllModifiers() return self.mods end
    return u
end
local function instance(class,p)
    local mod=setmetatable({parent=p,parent_reads=0},{__index=_G[class]})
    function mod:GetParent() self.parent_reads=self.parent_reads+1;return self.parent end
    function mod:GetName() return class end
    p.mods[#p.mods+1]=mod;return mod
end
local a,b,c=entity('npc_dota_hero_monkey_king',0,true),entity('npc_survival_arrow_tower',1,true),entity('npc_dota_thinker',-1,false)
local x,y,h,w,v=instance('modifier_rogue_combat_bonus',a),instance('modifier_equipment_effects',b),instance('modifier_single_health_bar',c),instance('modifier_building_damage_sound',b),instance('modifier_rogue_corrosive_shield_attack',a)
h.health_bar_staging_paused=true;w.shared_wall_feedback_observer=true
local prop={IsNull=function() return false end};local all={a,prop,b,c}
Entities={First=function() entity_reads=entity_reads+1;return all[1] end,
    Next=function(_,u) for i,e in ipairs(all) do if e==u then return all[i+1] end end;error('foreign iterator cursor') end}
local selected={'modifier_rogue_combat_bonus','modifier_rogue_combat_bonus','modifier_equipment_effects',
    'modifier_single_health_bar','modifier_building_damage_sound','modifier_rogue_corrosive_shield_attack'}
tools=false;assert(probe.start({enabled=true}).error=='requires_workshop_server' and entity_reads==0);tools=true
assert(probe.start({enabled=true,seconds=21}).status=='rejected')
assert(probe.start({enabled=true,seconds=0}).status=='rejected')
assert(probe.start({enabled=true,classes={'not_allowed'}}).status=='rejected')
local started=probe.start({enabled=true,seconds=20,classes=selected})
assert(started.status=='running' and #started.classes==5 and declarations==0 and hits==0 and intervals==0 and handles==0,
    'Start/census cannot invoke callbacks, declarations, create, refresh or destroy')
assert(started.census_before.complete and started.census_before.entities_visited==4
    and started.census_before.modifier_containers==3 and started.census_before.selected_instances==5)
local function row(class,method)
    for _,r in ipairs(probe.snapshot().classes) do if r.class==class then return r.methods[method],r end end
    error('class not found '..class)
end
local unrelated={attacker={},unit={},target={}}
for _=1,129 do local p,n,tag,argc=x:OnTakeDamage(unrelated,nil,'extra');assert(p==unrelated and n==nil and tag=='unchanged' and argc==2) end
local related={attacker=a,unit=b,target=b}
x:OnTakeDamage(related);x:OnTakeDamage({unit=a});x:OnTakeDamage({})
local ok,err=pcall(x.OnTakeDamage,x,{fail=true});assert(not ok and err==error_object,'Original error object must propagate unchanged')
y:OnTakeDamage(unrelated)
h:OnIntervalThink(nil,'extra');local states,n,tag=h:CheckState();assert(states.hidden and n==nil and tag=='state')
local value,nil_value,publish_tag=h:publish_state();assert(value==false and nil_value==nil and publish_tag=='publish')
local health,nothing,property_tag=x:GetMinHealth();assert(health==1 and nothing==nil and property_tag=='property')
w:OnTakeDamage({unit=b})
-- The same payload reaching two native instances/classes is not deduplicated.
table.foreach({[v]={attacker=a}},modifier_rogue_corrosive_shield_attack.OnAttack)
local r=row('modifier_rogue_combat_bonus','OnTakeDamage')
assert(r.calls==133 and r.parent_related==2 and r.parent_unrelated==129 and r.relevance_unknown==2
    and r.parent_as_attacker==1 and r.parent_as_unit==1 and r.sampled_caller_reads==3)
assert(r.lua_frame_samples==3,'Protected caller sampling must skip its own pcall/wrapper')
local cr=row('modifier_rogue_corrosive_shield_attack','OnAttack')
assert(cr.calls==1 and cr.c_frame_samples==1,'A real C caller frame is sampled without calling gameplay artificially')
assert(row('modifier_equipment_effects','OnTakeDamage').calls==1 and hits==134)
assert(row('modifier_single_health_bar','OnIntervalThink').intrinsic_parent_calls==1 and intervals==1)
assert(row('modifier_building_damage_sound','HandleTakeDamage').kind=='shared_route' and handles==1)
local snap=probe.snapshot()
assert(snap.kind_totals.global_event==136 and snap.kind_totals.shared_route==1 and snap.kind_totals.interval==1
    and snap.kind_totals.property_query==1 and snap.native_global_dispatch_total_proven==false)
assert(snap.manual_declaration_or_callback_calls==0 and snap.modifier_create_refresh_or_destroy_calls==0)
assert(x.parent_reads==2,'Parent lookup is cached per actual instance after the initial native census')
assert(snap.census_before.classes[3].class=='modifier_single_health_bar'
    and snap.census_before.classes[3].dead_parents==1,'Readonly census includes actual thinker/dead instance, not only creatures')
snap.classes[1].class='tampered';assert(probe.snapshot().classes[1].class=='modifier_rogue_combat_bonus')
local census=probe.census({classes=selected,attach_to_report=true})
assert(census.complete and probe.snapshot().census_after.selected_instances==5)
-- Capacity bounds do not drop real callbacks or deduplicate same-event fanout.
for _=1,2200 do local u=entity('npc_many',0,true);local mod=instance('modifier_rogue_combat_bonus',u);mod:OnTakeDamage(unrelated) end
snap=probe.snapshot();assert(snap.parent_cache_entries==2048 and snap.parent_cache_overflow>0
    and #snap.caller_samples<=64 and row('modifier_rogue_combat_bonus','OnTakeDamage').calls==2333)
local own_wrapper=modifier_rogue_combat_bonus.OnTakeDamage
local newer=function() return 'newer_owner' end;modifier_rogue_combat_bonus.OnTakeDamage=newer
clock=20;assert(timers[started.context]()==nil)
snap=probe.snapshot();assert(snap.status=='stopped' and snap.reason=='complete' and snap.restore_skipped==1)
assert(modifier_rogue_combat_bonus.OnTakeDamage==newer and modifier_rogue_combat_bonus.DeclareFunctions==decl
    and rawget(modifier_equipment_effects,'OnTakeDamage')==nil and modifier_equipment_effects.OnTakeDamage==original,
    'Restore preserves foreign overrides and original inherited slot shape')
local before=row('modifier_rogue_combat_bonus','OnTakeDamage').calls
own_wrapper(x,related);assert(row('modifier_rogue_combat_bonus','OnTakeDamage').calls==before,'Queued wrapper is inert after stop')
assert(probe.stop('again').reason=='complete' and timers[started.context]==nil)
modifier_rogue_combat_bonus.OnTakeDamage=original
clock=30;probe.start({enabled=true,seconds=1,classes={'modifier_rogue_combat_bonus'}})
clock=31;local returned=x:OnTakeDamage(related);assert(returned==related and probe.snapshot().status=='stopped'
    and row('modifier_rogue_combat_bonus','OnTakeDamage').calls==0,'Deadline precedes metadata and does not suppress original call')
clock=32;probe.start({enabled=true,seconds=1,classes={'modifier_rogue_combat_bonus'}})
clock_failed=true
local p,n,z=x:OnTakeDamage(related);assert(p==related and n==nil and z=='unchanged' and probe.snapshot().metadata_errors==1,
    'Diagnostic metadata failure cannot change the original callback return or exception')
clock_failed=false;probe.stop('metadata_test_done')
clock=40;local second_world=probe.start({enabled=true,seconds=1,classes={'modifier_rogue_combat_bonus'}})
world={};assert(timers[second_world.context]()==nil and probe.snapshot().reason=='world_changed')
-- Incomplete actual native enumeration is explicitly reported, never guessed.
Entities.Next=function(_,u) return u end
assert(probe.census({classes=selected}).error=='native_iterator_cycle')
Entities.Next=function(_,u) for i,e in ipairs(all) do if e==u then return all[i+1] end end end
b.FindAllModifiers=function() error('native invalid entity') end
local bad=probe.census({classes=selected});assert(bad.entity_collection_complete and not bad.modifier_reads_complete and not bad.complete)
local original_all=all;all={}
for _=1,40 do local u=entity('npc_census',0,true);instance('modifier_rogue_combat_bonus',u);all[#all+1]=u end
local large=probe.census({classes={'modifier_rogue_combat_bonus'}})
assert(large.complete and large.selected_instances==40 and #large.examples==32,'Bounded examples cannot truncate full native instance counts')
all=original_all
Entities.First=nil;assert(probe.census().error=='full_native_entity_iterator_unavailable')
assert(declarations==0,'No manual DeclareFunctions anywhere in diagnostic')
print('BATTLE_MODIFIER_PROBE_PASS: inert/default-off; full native API census without declarations/lifecycle; same-class selection dedup only; exact args/nil/multi-returns/error identity; actual related/unrelated/intrinsic counters; C/Lua sampled frame offset; separate route/property/interval totals; bounded examples/callers/cache; own restore/inherited slots; queued/deadline/world guards; incomplete census honest; native origin/FPS UNVERIFIED')
