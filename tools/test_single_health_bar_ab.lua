-- Offline exact-handle/deferred native destruction contracts. No Dota/TCP.
local helper_path=arg[1] or 'scripts/vscripts/tests/manual_single_health_bar_ab.lua'
local helper=assert(loadfile(helper_path))()
local KEY,BAR,AI,CAP='SURVIVAL_MANUAL_SINGLE_HEALTH_BAR_AB','modifier_single_health_bar','modifier_enemy_wall_ai','modifier_debug_attack_cap'
assert(not _G[KEY],'Inert load')
local forbidden_count=0
local function forbidden() forbidden_count=forbidden_count+1;error('forbidden scan/timer/order/stat setter') end
FindUnitsInRadius,EntIndexToHScript,CreateUnitByName=forbidden,forbidden,forbidden
Entities={FindAllByClassname=forbidden};Timers={CreateTimer=forbidden};Convars={RegisterCommand=forbidden}
local is_tools=true
IsServer=function() return true end;IsInToolsMode=function() return is_tools end
local mode={IsNull=function() return false end};GameRules={GetGameModeEntity=function() return mode end}
local destroy_count,add_count,next_index=0,0,0
local deferred={}
local function bar(unit)
    local m={unit=unit,caster=unit,stack=0,duration=-1}
    function m:IsNull() return self.null==true end
    function m:GetParent() return self.unit end
    function m:GetCaster() return self.caster end
    function m:GetName() return BAR end
    function m:GetAbility() return self.ability end
    function m:GetDuration() return self.duration end
    function m:GetStackCount() return self.stack end
    function m:Destroy()
        destroy_count=destroy_count+1
        if self.unit.destroy_before then error('destroy_before') end
        if not self.unit.defer_list then self.unit.bars={} end
        deferred[#deferred+1]=self
        if self.unit.destroy_after then error('destroy_after') end
    end
    return m
end
local function frame()
    for _,m in ipairs(deferred) do
        if m.unit.bars[1]==m then m.unit.bars={} end;m.null=true
    end
    deferred={}
end
local function unit(owner)
    next_index=next_index+1
    local u={index=next_index,survival_player_id=owner or 0,survival_is_wave_monster=true,
        health=1000,maximum=1000,team=3,capability=2,speed=1.2,aps=1.8,display=120,force={},alive=true}
    function u:IsNull() return self.null==true end
    function u:IsAlive() return self.alive end
    function u:entindex() return self.index end
    function u:GetHealth() return self.health end
    function u:GetMaxHealth() return self.maximum end
    function u:GetTeamNumber() return self.team end
    function u:GetAttackCapability() return self.capability end
    function u:GetForceAttackTarget() return self.force end
    function u:GetAttackSpeed(ignore) assert(ignore==false);return self.speed end
    function u:GetAttacksPerSecond(ignore) assert(ignore==false);return self.aps end
    function u:GetDisplayAttackSpeed() return self.display end
    u.ai={shared_attack_observer=true,ai_state='chase',wall_entindex=100+u.survival_player_id,
        IsNull=function(self) return self.null==true end,GetParent=function() return u end,GetStackCount=function() return 0 end}
    u.survival_enemy_attack_owner=u.ai
    u.cap={IsNull=function(self) return self.null==true end,GetParent=function() return u end}
    u.bars={bar(u)}
    function u:FindAllModifiersByName(name)
        if name==BAR then return self.bars end;assert(name==CAP);return self.no_cap and {} or {self.cap}
    end
    function u:FindModifierByName(name) assert(name==AI);return self.ai end
    function u:AddNewModifier(caster,ability,name,options)
        assert(caster==self and ability==nil and name==BAR and next(options)==nil and #self.bars==0)
        add_count=add_count+1
        if self.add_before then error('add_before') end
        self.bars={bar(self)}
        if self.add_after then error('add_after') end
        return self.bars[1]
    end
    u.SetHealth,u.SetAttackCapability,u.SetForceAttackTarget,u.Stop,u.StartIntervalThink=forbidden,forbidden,forbidden,forbidden,forbidden
    return u
end
local function reset() _G[KEY]=nil;deferred={} end
local function ready(list)
    assert(helper.start(list));local ok,reason=helper.verify();assert(not ok and reason=='removal_pending')
    frame();assert(helper.finalize());assert(helper.snapshot().ready)
end
local all={};for index=1,244 do all[index]=unit(math.floor((index-1)/61));all[index].defer_list=index%2==0 end
ready(all);assert(helper.snapshot().unit_count==244 and destroy_count==244)
assert(not helper.start({unit()}),'Active capture cannot be replaced')
assert(helper.verify());assert(helper.restore() and add_count==244)
assert(helper.restore() and add_count==244,'Restore is idempotent')
assert(not helper.snapshot().restore_pending)
-- An independent module load shares pending/restore ownership on this map.
reset();local original=unit();assert(helper.start({original}))
local reload=assert(loadfile(helper_path))();assert(not reload.start({unit()}));frame();assert(reload.verify());assert(reload.restore())
-- Every input is validated before the first removal.
for _,bad in ipairs({'missing_bar','foreign_caster','finite_duration','bar_stack','dead','foreign_owner','no_cap','bad_ai','nan'}) do
    reset();local a,b=unit(),unit()
    if bad=='missing_bar' then b.bars={} elseif bad=='foreign_caster' then b.bars[1].caster=a
    elseif bad=='finite_duration' then b.bars[1].duration=3 elseif bad=='bar_stack' then b.bars[1].stack=1
    elseif bad=='dead' then b.alive=false elseif bad=='foreign_owner' then b.survival_player_id=8
    elseif bad=='no_cap' then b.no_cap=true elseif bad=='bad_ai' then b.ai.shared_attack_observer=false
    else b.speed=0/0 end
    local before=destroy_count;assert(not helper.start({a,b}) and destroy_count==before,bad..' mutates nothing')
end
for _,list in ipairs({{}, {[2]=unit()}, {unit(),unit(),false}, {[0]=unit()}}) do reset();assert(not helper.start(list)) end
reset();local duplicate=unit();assert(not helper.start({duplicate,duplicate}))
reset();is_tools=false;assert(not helper.start({unit()}));is_tools=true
-- A successful Destroy may stay in the native list until another engine frame.
reset();local delayed=unit();delayed.defer_list=true;assert(helper.start({delayed}))
assert(not helper.restore() and helper.snapshot().restore_pending);frame();assert(helper.restore())
for _,failure in ipairs({'destroy_before','destroy_after','add_before','add_after'}) do
    reset();local u=unit()
    if failure:find('destroy',1,true) then
        u[failure]=true;assert(not helper.start({u}));u[failure]=false;frame();assert(helper.restore())
    else ready({u});u[failure]=true;assert(not helper.restore());u[failure]=false;assert(helper.restore()) end
    assert(#u.bars==1 and not helper.snapshot().restore_pending,failure..' recovery')
end
-- Any changed combat/AI state or death invalidates timing, without reverting it.
for _,field in ipairs({'health','maximum','team','capability','speed','aps','display','force','ai','cap','owner','dead','index'}) do
    reset();local u=unit();ready({u})
    if field=='dead' then u.alive=false elseif field=='owner' then u.survival_player_id=1
    elseif field=='ai' then u.ai={IsNull=function() return false end}
    elseif field=='cap' then u.cap={IsNull=function() return false end,GetParent=function() return u end}
    elseif field=='force' then u.force={} else u[field]=u[field]+1 end
    assert(not helper.verify() and not helper.snapshot().ready,field..' rejects changed state')
    if field=='index' then assert(helper.snapshot().restore_pending);u.index=u.index-1;assert(helper.restore()) end
    assert(#u.bars==1,field..' restores only the bar')
end
reset();local expired=unit();ready({expired});expired.null=true
local adds_before=add_count;assert(not helper.verify());assert(helper.snapshot().expired_count==1 and add_count==adds_before)
reset();local changed_world=unit();ready({changed_world});local old_mode=mode;mode={IsNull=function() return false end}
assert(not helper.verify() and helper.snapshot().restore_pending);mode=old_mode;assert(helper.restore())
reset();local foreign=unit();ready({foreign});foreign.bars={bar(foreign)}
assert(not helper.verify() and #foreign.bars==1,'Foreign re-added compatible bars are retained, never duplicated')
assert(forbidden_count==0,'No scans, setters, AI/cap changes, orders, hooks or timers')
print('SINGLE_HEALTH_BAR_AB_PASS: 244 exact owners, atomic preflight, deferred native destroy/list, explicit verify, unchanged combat/AI/cap, death/identity/world invalidation, exact/idempotent restore, rollback/retry and inert reload')
