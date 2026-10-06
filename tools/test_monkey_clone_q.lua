package.path = "scripts/vscripts/?.lua;" .. package.path
-- Exercise the real clone modifier, shared Q service, runtime configuration and
-- critical-record helper. Only native entities/rendering and the scheduler are
-- fixtures; this is not a simulation of Dota's attack or particle engine.
local bus = require("core/event_bus")
local events = require("core/events")
local combat_events = require("combat/combat_events")
local runtime = require("config/generated/monkey_king_exclusive_runtime").by_id.monkey_king_exclusive
local tasks, heroes, snapshots, skills, created, particles, deals = {}, {}, {}, {}, {}, {}, {}
local serial, next_record, mirror_calls, stat_reads = 0, 1000, 0, 0
local rolls, sample = {}, 1
package.loaded["core/scheduler"] = {
    after=function(delay, callback, id) tasks[id]={delay=delay,callback=callback};return id end,
    every=function(delay, callback, id) tasks[id]={delay=delay,callback=callback};return id end,
    cancel=function(id) tasks[id]=nil end,
}
package.loaded["systems/hero_cosmetic_service"] = {
    sync_appearance=function() mirror_calls=mirror_calls+1;return true end,
    clear=function() end,
}
package.loaded["systems/hero_base_health_service"]={apply=function() return {} end}
package.loaded["systems/gameplay_phase_guard"]={post_clear_frozen=function() return false end}
local sounds={}
package.loaded["core/sound_service"]={play=function(name,params) sounds[#sounds+1]={name=name,params=params} end}
function class(value) return value end
function IsServer() return true end
function RandomFloat() return 99 end
function RollPercentage(chance) rolls[#rolls+1]=chance;return sample<=chance end
MODIFIER_PROPERTY_FIXED_ATTACK_RATE=1
DOTA_DAMAGE_CATEGORY_ATTACK,DOTA_DAMAGE_CATEGORY_SPELL=1,2
DAMAGE_TYPE_PURE=4
DOTA_UNIT_TARGET_TEAM_ENEMY,DOTA_UNIT_TARGET_HERO,DOTA_UNIT_TARGET_BASIC=2,4,8
DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES,FIND_ANY_ORDER,PATTACH_WORLDORIGIN=16,0,0
local rate_definition=require("modifiers/modifier_hero_exclusive_summon_attack_rate")
local clone_definition=require("modifiers/modifier_monkey_king_clone")
local secondary_records={}
modifier_weapon_attack_tracker={IsSecondaryAttackRecord=function(record) return secondary_records[record]==true end}
local vector={};vector.__index=vector
function Vector(x,y,z) return setmetatable({x=x,y=y,z=z or 0},vector) end
vector.__add=function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
vector.__sub=function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
vector.__mul=function(a,b) return Vector(a.x*b,a.y*b,a.z*b) end
function vector:Length2D() return math.sqrt(self.x*self.x+self.y*self.y) end
function vector:Normalized() return self*(1/self:Length2D()) end
RandomVector=function() return Vector(0,0,0) end
GetGroundPosition=function(position) return position end
FindClearSpaceForUnit=function() end
PlayerResource={GetPlayer=function(_,id) return {id=id} end}
ParticleManager={
    CreateParticle=function(_,name,attach,owner)
        particles[#particles+1]={name=name,owner=owner,controls={}}
        return #particles
    end,
    SetParticleControl=function(_,id,cp,value) particles[id].controls[cp]=value end,
    SetParticleControlForward=function(_,id,cp,value) particles[id].forward=value end,
    DestroyParticle=function(_,id) particles[id].destroyed=true end,
    ReleaseParticleIndex=function(_,id) particles[id].released=true end,
}
local function unit(player_id)
    serial=serial+1
    local u={id=serial,player_id=player_id,abilities={},modifiers={},health=500,maximum=1000,
        position=Vector(0,0,0),bat=1.7}
    function u:IsNull() return self.removed==true end
    function u:IsAlive() return not self.removed and not self.dead end
    function u:entindex() return self.id end
    function u:GetUnitName() return "npc_dota_hero_monkey_king" end
    function u:GetPlayerOwnerID() return self.player_id end
    function u:GetTeamNumber() return self.team or 2 end
    function u:GetAbsOrigin() return self.position end
    function u:GetForwardVector() return Vector(1,0,0) end
    function u:GetHullRadius() return 0 end
    function u:GetAbilityCount() return 0 end
    function u:FindAbilityByName(name) return self.abilities[name] end
    function u:AddAbility(name)
        local a={name=name,SetLevel=function() end,SetHidden=function() end,SetActivated=function() end}
        function a:IsNull() return false end
        self.abilities[name]=a;return a
    end
    function u:SetPlayerID(value) self.player_id=value end
    function u:SetOwner(value) self.owner=value end
    function u:GetHealth() return self.health end
    function u:GetMaxHealth() return self.maximum end
    function u:SetHealth(value) self.health=value end
    function u:SetBaseDamageMin(value) self.damage_min=value end
    function u:SetBaseDamageMax(value) self.damage_max=value end
    function u:GetBaseAttackTime() return self.bat end
    function u:SetBaseAttackTime() error("Q changes may not regress native BAT") end
    function u:GetAttacksPerSecond() return 10 end
    function u:FindModifierByName(name) return self.modifiers[name] end
    function u:AddNewModifier(_,_,name,params)
        local definition=name=="modifier_monkey_king_clone" and clone_definition or rate_definition
        local m=setmetatable({},{__index=definition})
        function m:GetParent() return u end
        function m:SetHasCustomTransmitterData() end
        function m:SendBuffRefreshToClients() end
        function m:ForceRefresh() self:OnRefresh({}) end
        self.modifiers[name]=m;m:OnCreated(params);return m
    end
    function u:AddNoDraw() self.hidden=true end
    for _,name in ipairs({"SetControllableByPlayer","SetHullRadius","SetBaseStrength",
        "SetBaseAgility","SetBaseIntellect","CalculateStatBonus"}) do u[name]=function() end end
    return u
end
CreateUnitByName=function(_,position,_,owner)
    local u=unit(owner.player_id);u.position=position;created[#created+1]=u;return u
end
UTIL_Remove=function(u) u.removed=true end
bus.reset()
bus.handle_request(events.HERO_SUMMON_GET_REQUEST,function(p) return {unit=heroes[p.player_id]} end)
bus.handle_request(events.HERO_SKILL_STATE_GET_REQUEST,function(p) return {snapshot={skills=skills[p.player_id] or {}}} end)
bus.handle_request(events.HERO_COMBAT_STATS_GET_REQUEST,function(p)
    stat_reads=stat_reads+1;return {snapshot=snapshots[p.player_id]}
end)
bus.handle_request(combat_events.DEAL_REQUEST,function(p) deals[#deals+1]=p;return {success=true} end)
local original_print=print
print=function(message) if tostring(message):find("%[EventBus%] handler error") then error(message) end end
local service=require("systems/monkey_king_exclusive_service")
service.init()
local Q="skill_monkey_king_exclusive"
local QA="ability_survival_monkey_king_exclusive"
local function summon(pid)
    local hero=unit(pid);hero.survival_hero_id="hero_monkey_king";hero:AddAbility(QA)
    heroes[pid]=hero
    snapshots[pid]={entindex=hero.id,max_health=1000,engine_attack_min=100,engine_attack_max=100,
        attack_min=1000000,attack_max=1000000,attack_speed=10,
        strength=10,agility=20,intellect=30,critical_chance_pct=20,critical_damage_pct=2000}
    skills[pid]={{skill_id=Q,level=1},{skill_id="skill_monkey_king_fury",level=1}}
    bus.emit(events.HERO_SKILL_CHANGED,{player_id=pid})
    return hero,created[#created],created[#created].modifiers.modifier_monkey_king_clone
end
local source,clone,modifier=summon(0)
local other_source,other_clone,other_modifier=summon(1)
local target=unit(-1);target.team=3;target.position=Vector(200,0,0);target.maximum=10000
local outside=unit(-1);outside.team=3;outside.position=Vector(200,101,0)
FindUnitsInRadius=function() return {target,outside} end
local function main_attack(hero,pid)
    bus.emit(events.HERO_MAIN_ATTACK_LANDED,{player_id=pid,attacker=hero,target=target,is_main_attack=true})
end
local function attack(m,u,extra)
    next_record=next_record+1
    local p={attacker=u,target=target,record=next_record}
    for key,value in pairs(extra or {}) do p[key]=value end
    m:OnAttackRecord(p);m:OnAttackLanded(p)
    return p
end
local function flush()
    local ids={}
    for id in pairs(service._test.impacts()) do ids[#ids+1]=id end
    table.sort(ids)
    for _,id in ipairs(ids) do
        local impact=service._test.impacts()[id]
        local task=assert(tasks[impact.task]);tasks[impact.task]=nil
        assert(task.delay==0.28,"clone and source use the same staff-fall timing")
        task.callback()
    end
end
local function impact_count()
    local n=0;for _ in pairs(service._test.impacts()) do n=n+1 end;return n
end
local function no_roll(label,fn)
    local count=#rolls;fn();assert(#rolls==count,label)
end
local visual_reads=mirror_calls
for i=1,100 do sample=i;main_attack(source,0) end
assert(#rolls==100 and impact_count()==10,"source probability fixture must produce ten single-roll procs")
for i=1,100 do sample=i;local p=attack(modifier,clone);modifier:OnAttackRecordDestroy(p) end
assert(#rolls==200 and impact_count()==20,"clone must use the same ten-percent roll once, not two rolls")
for _,chance in ipairs(rolls) do assert(chance==runtime.q_proc_chance_pct and chance==10) end
for _,impact in pairs(service._test.impacts()) do
    assert(impact.length==1200 and impact.total_width==200 and impact.attribute_damage==1800)
    assert(impact.origin.x==0 and impact.endpoint.x==1200)
    local p=particles[impact.drop_particle]
    assert(p.name=="particles/survival_monkey_king/survival_monkey_king_staff_drop.vpcf")
    assert(p.controls[0].x==600 and p.controls[0].z==1000 and p.controls[2].z==-350)
end
flush()
assert(#deals==20 and #particles==40,"each source/clone Q needs both staff drop and boundless impact")
local source_hits,clone_hits=0,0
for i,d in ipairs(deals) do
    assert(d.victim==target and d.damage_type==DAMAGE_TYPE_PURE and d.can_crit==false)
    assert(d.ability.name==QA and d.tags.source=="q" and d.source_kind=="ability")
    assert(d.base_damage==(i<=3 and 2800 or 1800),"source and clone share the same three max-health-hit allowance")
    if d.attacker==source then source_hits=source_hits+1 else assert(d.attacker==clone);clone_hits=clone_hits+1 end
end
assert(source_hits==10 and clone_hits==10)
for i=21,40 do
    local p=particles[i]
    assert(p.name=="particles/units/heroes/hero_monkey_king/monkey_king_strike.vpcf")
    assert(p.controls[0].x==0 and p.controls[1].x==1200 and p.released)
end
assert(mirror_calls==visual_reads,"ordinary Q hits must not scan/rebuild cosmetics")

-- Failed rolls and repeated callbacks have one chance per attack record.
sample=100
local miss=attack(modifier,clone)
no_roll("a missed proc cannot reroll on duplicate OnAttackLanded",function() modifier:OnAttackLanded(miss) end)
sample=1
local hit=attack(modifier,clone)
no_roll("a successful proc cannot duplicate its impact",function() modifier:OnAttackLanded(hit) end)
modifier:OnAttackRecordDestroy(hit)
local count=#rolls
modifier:OnAttackRecord(hit);modifier:OnAttackLanded(hit)
assert(#rolls==count+1,"engine record ids may be reused after destruction")
modifier:OnAttackRecordDestroy(hit)

-- Freeze temporary flags at record creation; also respect flags supplied only
-- at landing, tracked secondary records, and non-ordinary damage callbacks.
for _,extra in ipairs({{is_main_attack=false},{is_multishot_secondary=true},{no_attack_cooldown=1}}) do
    no_roll("secondary attacks may not roll Q",function() attack(modifier,clone,extra) end)
end
for _,flag in ipairs({"survival_next_drow_secondary","survival_next_multishot_secondary","survival_is_multishot_secondary"}) do
    next_record=next_record+1
    local p={attacker=clone,target=target,record=next_record}
    clone[flag]=true;modifier:OnAttackRecord(p);clone[flag]=nil
    no_roll("cleared transient secondary marker must remain isolated",function() modifier:OnAttackLanded(p) end)
end
next_record=next_record+1
local tracked={attacker=clone,target=target,record=next_record}
secondary_records[next_record]=true;modifier:OnAttackRecord(tracked);secondary_records[next_record]=nil
no_roll("tracker-marked secondary must remain isolated",function() modifier:OnAttackLanded(tracked) end)
for _,extra in ipairs({{inflictor=source.abilities[QA]},{damage_category=DOTA_DAMAGE_CATEGORY_SPELL}}) do
    no_roll("ability damage may not roll Q",function() attack(modifier,clone,extra) end)
end
no_roll("missing record and untracked record cannot trigger Q",function()
    modifier:OnAttackLanded({attacker=clone,target=target})
    modifier:OnAttackLanded({attacker=clone,target=target,record=-999})
    modifier:OnAttackLanded(nil);modifier:OnTakeDamage(nil);modifier:OnAttackRecordDestroy(nil)
end)
next_record=next_record+1
local crossed={attacker=clone,target=outside,record=next_record}
modifier:OnAttackRecord(crossed);crossed.target=target
no_roll("one attack record cannot proc from another victim",function() modifier:OnAttackLanded(crossed) end)
clone.survival_hero_id="hero_monkey_king"
no_roll("clone must not also enter the main-hero event path",function() main_attack(clone,0) end)
clone.survival_hero_id=nil

skills[0][1].locked=1
no_roll("locked Q must not proc",function() attack(modifier,clone) end)
skills[0][1].locked=nil;skills[0][1].level=0
no_roll("unlearned Q must not proc",function() attack(modifier,clone) end)
skills[0][1].level=1
local old_modifier_strength=modifier.combat_snapshot.strength
snapshots[0].strength=10000000;snapshots[0].agility=20000000;snapshots[0].intellect=30000000
local before=stat_reads
attack(modifier,clone)
assert(stat_reads==before+1,"Q reads current authoritative stats only when it procs")
assert(modifier.combat_snapshot.strength==old_modifier_strength,"fixture deliberately keeps clone snapshot stale")
local found=false
for _,impact in pairs(service._test.impacts()) do
    if impact.attribute_damage==1800000000 then found=true end
end
assert(found,"Q must use current logical attributes rather than old clone or projected native values")
assert(clone.damage_min==100,"fixture separates projected native attack from logical Q attributes")
no_roll("wrong player/foreign clone must not borrow another source's Q",function()
    assert(not service.trigger_clone_q(1,clone,target))
    assert(not service.trigger_clone_q(0,other_clone,target))
    assert(not service.trigger_clone_q(0,source,target))
end)
attack(other_modifier,other_clone)
local own_damage=false
for _,impact in pairs(service._test.impacts()) do
    if impact.attacker==other_clone then assert(impact.attribute_damage==1800);own_damage=true end
end
assert(own_damage,"another player keeps independent stats and source identity")
flush()

-- Killing blows still use the same single proc roll: the dead primary target
-- supplies the direction, while only surviving enemies receive line damage.
target.dead=true
local survivor=unit(-1);survivor.team=3;survivor.position=Vector(400,0,0)
FindUnitsInRadius=function() return {target,outside,survivor} end
local fatal_rolls,fatal_deals=#rolls,#deals
main_attack(source,0);attack(modifier,clone)
assert(#rolls==fatal_rolls+2 and impact_count()==2,"both killing blows get exactly one shared Q roll")
flush()
assert(#deals==fatal_deals+2)
for i=fatal_deals+1,#deals do
    assert(deals[i].victim==survivor and deals[i].base_damage==1800000100,
        "the staff targets the dead enemy's direction and damages living enemies using current logical stats")
end
sample=100
fatal_rolls=#rolls
main_attack(source,0);attack(modifier,clone)
assert(#rolls==fatal_rolls+2 and impact_count()==0,"fatal hits must not bypass the shared failed roll")
sample=1
target.dead=nil
FindUnitsInRadius=function() return {target,outside} end
no_roll("invalid and friendly targets may not roll Q",function()
    assert(not service.trigger_clone_q(0,clone,nil))
    target.removed=true;main_attack(source,0);attack(modifier,clone);target.removed=nil
    target.team=2;main_attack(source,0);attack(modifier,clone);target.team=3
end)

-- A permanent defender keeps its Q while its owner is dead; it cannot attack
-- as a corpse or keep invoking Q after its owner entity has been replaced.
source.dead=true
count=#rolls;attack(modifier,clone);assert(#rolls==count+1)
source.dead=nil
local impostor=unit(0);impostor.survival_hero_id="hero_monkey_king"
heroes[0]=impostor
no_roll("old clone may not use a replacement hero's stats",function() attack(modifier,clone) end)
heroes[0]=source
source.removed=true
no_roll("invalid owner prevents new clone Q",function() attack(modifier,clone) end)
source.removed=nil
clone.dead=true
no_roll("dead clone cannot start Q",function() attack(modifier,clone) end)
modifier:OnDeath({unit=clone})
assert(next(modifier.attack_records)==nil and modifier.active_attack_multiplier==nil)
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=clone})
local old_clone,old_modifier=clone,modifier
tasks["monkey_clone_respawn:0"].callback()
clone=created[#created];modifier=clone.modifiers.modifier_monkey_king_clone
assert(clone~=old_clone and next(modifier.attack_records)==nil)
count=#rolls;attack(modifier,clone);assert(#rolls==count+1,"replacement clone retains Q")
old_clone.dead=nil
no_roll("superseded clone cannot proc after a late landed callback",function() attack(old_modifier,old_clone) end)
old_clone.dead=true
local prior_deals=#deals
clone.dead=true;modifier:OnDeath({unit=clone});flush()
assert(#deals>prior_deals,"an already emitted Q finishes with the same death semantics as the owner")
clone.dead=nil
attack(modifier,clone)
heroes[0]=nil;source.removed=true
bus.emit(events.HERO_REMOVED,{player_id=0,unit=source,entindex=source.id})
assert(clone.removed)
for _,impact in pairs(service._test.impacts()) do assert(impact.player_id~=0) end
no_roll("removed clone cannot invoke Q",function() attack(modifier,clone) end)
other_modifier:OnDestroy()
assert(next(other_modifier.attack_records)==nil)
no_roll("destroyed modifier cannot invoke Q",function() attack(other_modifier,other_clone) end)
assert(mirror_calls==visual_reads+1,"only the respawn should mirror during combat regression")
print=original_print
print("MONKEY_CLONE_Q_PASS single shared 10% roll including killing blows; identical staff/impact/damage; live logical attributes; record/secondary/source/death isolation")
