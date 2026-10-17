-- Real v3 helper with strict native API signatures. No production AI/order
-- replacement: only the optional helper's boundary inputs are simulated.
package.path="scripts/vscripts/?.lua;"..package.path
local now,world,tools,server,map=0,{},true,true,"template_map"
local sequence,record=100,1000
IsServer=function() return server end
IsInToolsMode=function() return tools end
GetMapName=function() return map end
GameRules={GetGameTime=function() return now end,GetGameModeEntity=function() return world end}
DOTA_TEAM_GOODGUYS,DOTA_TEAM_BADGUYS=2,3
DOTA_UNIT_CAP_RANGED_ATTACK=2
MODIFIER_STATE_ROOTED=3
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=world}
package.loaded["core/team_alignment"]={are_enemies=function(a,b) return a.team~=b.team end}
local bus=require("core/event_bus")
ExecuteOrderFromTable=function() error("candidate issued an attack/move order") end
local probe=require("systems/enemy_ranged_stationary")
assert(_G.SURVIVAL_RANGED_IDLE_ACQUIRE_STABLE_PROBE==nil,"require enabled optional candidate")
local function unit(index,team,x)
    local u={index=index,team=team,p={x=x,y=0,z=0},range=600,hull=32,alive=true,
        idle_acquire=true,idle_reads=0,idle_writes=0,log={},rate=1,bat=1.7,
        survival_is_wave_monster=true,survival_wave_movement_type="ground"}
    function u:IsNull() return self.removed==true end
    function u:entindex() return self.index end
    function u:IsAlive() return self.alive end
    function u:GetClassname() return "npc_dota_creature" end
    function u:GetTeamNumber() return self.team end
    function u:GetAttackCapability() return self.attack_cap or 2 end
    function u:GetAbsOrigin() return self.p end
    function u:Script_GetAttackRange() return self.range end
    function u:GetHullRadius() return self.hull end
    function u:GetAttackTarget() return self.target end
    function u:GetForceAttackTarget() return self.force end
    function u:FindAllModifiers() return self.modifiers end
    function u:IsStunned() return self.stunned==true end
    function u:IsDisarmed() return self.disarmed==true end
    function u:IsCommandRestricted() return self.restricted==true end
    function u:IsCurrentlyHorizontalMotionControlled() return self.motion==true end
    function u:IsCurrentlyVerticalMotionControlled() return self.vertical==true end
    function u:IsRooted() return self.external_root==true or (self.owner and self.owner.contact_mode==6) or false end
    function u:IsControllableByAnyPlayer() return self.player_controlled==true end
    function u:IsInvulnerable() return self.invulnerable==true end
    function u:IsAttackImmune() return self.immune==true end
    function u:CanEntityBeSeenByMyTeam() return self.hidden~=true end
    function u:GetAttacksPerSecond(native_bool) assert(native_bool==false);return self.rate end
    function u:GetBaseAttackTime(native_bool) assert(native_bool==false);return self.bat end
    function u:ShouldIdleAcquire() self.idle_reads=self.idle_reads+1;return self.idle_acquire end
    function u:SetIdleAcquire(value)
        assert(type(value)=="boolean","restoration guessed a non-boolean")
        self.idle_writes=self.idle_writes+1
        self.log[#self.log+1]="idle:"..tostring(value)
        self.idle_acquire=value
        if self.set_hook then self:set_hook(value) end
    end
    function u:GetIdleAcquire() error("nonexistent native getter used") end
    function u:Stop() error("candidate stopped native attack") end
    function u:SetForceAttackTarget() error("candidate reset native force target") end
    function u:SetBaseAttackTime() error("candidate changed BAT") end
    function u:SetAttackCapability() error("candidate changed attack capability") end
    function u:SetMoveCapability() error("candidate changed movement capability") end
    function u:SetHullRadius() error("candidate changed hull/collision") end
    return u
end
local wall=unit(1,2,0);wall.hull=128
local other_wall=unit(2,2,1000)
local function fixture()
    sequence=sequence+1
    local parent=unit(sequence,3,-735)
    local owner={parent=parent,wall_entindex=1,goal_wall=wall,ai_state="chase",contact_mode=0}
    function owner:GetParent() return self.parent end
    function owner:SetContactMode(value)
        self.contact_mode=value;parent.log[#parent.log+1]="mode:"..tostring(value)
    end
    parent.owner=owner;parent.modifiers={owner};parent.force,parent.target=wall,wall
    return parent,owner
end
local function event(parent,owner,kind,id,target)
    probe.observe(owner,parent,target or wall,kind,{attacker=parent,target=target or wall,record=id})
end
local function step(parent,owner,dt)
    now=now+(dt or .5);probe.observe(owner,parent,wall)
end
local function prove(parent,owner)
    record=record+1
    event(parent,owner,"start")
    event(parent,owner,"fired",record)
    assert(not owner.ranged_stationary_hold,"one release is not stationary landing proof")
    now=now+.1;event(parent,owner,"landed",record)
    assert(owner.ranged_stationary_hold and owner.contact_mode==6)
end
local function enable()
    assert(probe.stop_idle_acquire_probe())
    assert(probe.set_probe_enabled(true))
    probe.reset_counters()
    assert(probe.set_idle_acquire_probe_enabled(true))
end
local function enter()
    local parent,owner=fixture();prove(parent,owner)
    assert(parent.idle_writes==0,"new v3 hold was immediately treated as existing hold")
    step(parent,owner,.01)
    assert(owner.ranged_idle_acquire_hold and parent.idle_acquire==false and parent.idle_writes==1)
    return parent,owner
end
local function clean(parent,owner)
    probe.release(owner,parent,"destroyed")
    assert(not owner.ranged_stationary_hold and not owner.ranged_idle_acquire_hold)
end
local function idle() return probe.snapshot().idle_acquire end
local function restored_before_mode(parent)
    assert(parent.log[#parent.log-1]=="idle:true" and parent.log[#parent.log]=="mode:0",
        "owned acquisition must restore before root is relinquished")
end

-- Default-off/native production behavior: no additional native API calls.
local p,a=fixture();probe.observe(a,p,wall);probe.snapshot()
assert(p.idle_reads==0 and p.idle_writes==0)
assert(not probe.set_idle_acquire_probe_enabled(true),"idle flag must require v3")
assert(probe.set_probe_enabled(true));prove(p,a);step(p,a)
assert(p.idle_reads==0 and p.idle_writes==0 and a.ranged_stationary_hold)
clean(p,a);assert(probe.set_probe_enabled(false))
_G.SURVIVAL_RANGED_IDLE_ACQUIRE_STABLE_PROBE=true
p,a=fixture();event(p,a,"fired",1);event(p,a,"landed",1);probe.snapshot()
assert(p.idle_reads==0 and p.idle_writes==0,"raw new flag bypassed disabled v3")
for _,change in ipairs({
    function() tools=false end,function() server=false end,function() map="other_map" end,
    function() _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode={}} end}) do
    assert(probe.set_probe_enabled(true));change()
    assert(not probe.set_idle_acquire_probe_enabled(true))
    event(p,a,"fired",2);event(p,a,"landed",2);step(p,a)
    assert(p.idle_reads==0 and p.idle_writes==0,"unauthorized candidate read idle API")
    tools,server,map=true,true,"template_map"
    _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=world}
    clean(p,a)
end

-- Ordinary moving chase and unmatched records never even read the getter.
enable();p,a=fixture();step(p,a);event(p,a,"fired",30);event(p,a,"landed",31)
assert(not a.ranged_stationary_hold and p.idle_reads==0 and p.idle_writes==0)
event(p,a,"landed",30);assert(a.ranged_stationary_hold and p.idle_reads==0)
p.target=nil;step(p,a,.1)
assert(a.ranged_stationary_hold and not a.ranged_idle_acquire_hold and p.idle_reads==0)
assert(idle().admission_rejections.native_target_not_wall==1)
p.target=wall;step(p,a,.1);assert(p.idle_acquire==false)
assert(a.ai_state=="chase","candidate renamed established FSM")
clean(p,a);restored_before_mode(p)

-- Native bool false is already external state: no ownership, write or restore.
enable();p,a=fixture();p.idle_acquire=false;prove(p,a);step(p,a)
assert(p.idle_writes==0 and not a.ranged_idle_acquire_hold and idle().original_false==1)
clean(p,a);assert(p.idle_acquire==false)
for _,getter in ipairs({
    function() return 0 end,function() return 1 end,function() return "false" end,
    function() return {} end,function() return nil end,function() error("native failed") end}) do
    enable();p,a=fixture();p.ShouldIdleAcquire=getter;prove(p,a);step(p,a)
    assert(p.idle_writes==0 and not a.ranged_idle_acquire_hold,"non-boolean getter authorized mutation")
    clean(p,a)
end
enable();p,a=fixture();p.ShouldIdleAcquire=nil;prove(p,a);step(p,a)
assert(p.idle_writes==0 and idle().admission_rejections.getter_missing==1);clean(p,a)
enable();p,a=fixture();p.SetIdleAcquire=nil;prove(p,a);step(p,a)
assert(p.idle_reads==0 and idle().admission_rejections.setter_missing==1);clean(p,a)
enable();p,a=fixture();prove(p,a);p.GetAttackTarget=function() error("native target getter failed") end;step(p,a)
assert(p.idle_reads==0 and p.idle_writes==0 and not a.ranged_idle_acquire_hold);clean(p,a)
enable();p,a=fixture();prove(p,a);p.survival_ranged_idle_acquire_owner={};step(p,a)
assert(p.idle_reads==0 and p.idle_writes==0);clean(p,a)

-- Return values alone cannot establish mutation. Partial throws, false readback
-- failure, target/control/geometry changes during the setter restore and exit.
for _,hook in ipairs({
    function(self,value) if not value then error("threw after applying false") end end,
    function(self,value) if not value then self.target=nil end end,
    function(self,value) if not value then self.target=other_wall end end,
    function(self,value) if not value then self.p.x=self.p.x+1 end end,
    function(self,value) if not value then self.stunned=true end end}) do
    enable();p,a=fixture();p.set_hook=hook;prove(p,a);step(p,a)
    assert(not a.ranged_stationary_hold and not a.ranged_idle_acquire_hold and p.idle_acquire==true)
    assert(p.idle_writes==2 and idle().entered==0 and idle().aborted_before_entry==1)
    restored_before_mode(p);clean(p,a)
end
enable();p,a=fixture()
p.SetIdleAcquire=function(self,value) self.idle_writes=self.idle_writes+1;return false end
prove(p,a);step(p,a)
assert(not a.ranged_stationary_hold and p.idle_acquire==true and p.idle_writes==1)
assert(idle().set_readback_failures==1 and idle().restore_successes==1)
-- Do not repeatedly suppress fire after a known failed entry in one session.
prove(p,a);step(p,a)
assert(p.idle_writes==1 and idle().admission_rejections.previous_failure_this_generation==1);clean(p,a)

-- Setting during Fired happens after that real event. Its later landing is an
-- in-flight pre-set projectile, never proof that attacks continued after set.
enable();p,a=fixture();prove(p,a)
event(p,a,"fired",40)
assert(a.ranged_idle_acquire_hold and idle().post_set_fired==0)
now=now+.1;event(p,a,"landed",40)
assert(idle().pre_set_inflight_ignored==1 and idle().post_set_pairs==0)
event(p,a,"fired");event(p,a,"landed")
assert(idle().post_set_record_missing==2 and idle().post_set_pairs==0)
event(p,a,"fired",41);event(p,a,"fired",41);event(p,a,"landed",42)
assert(idle().post_set_fired==1 and idle().post_set_pairs==0)
now=now+.1;event(p,a,"landed",41);event(p,a,"landed",41)
assert(idle().post_set_fired==1 and idle().post_set_landed==1 and idle().post_set_pairs==1,
    "post-set continuity guessed missing, duplicate or different record")
for i=1,60 do
    now=now+.4;event(p,a,"fired",100+i)
    now=now+.1;event(p,a,"landed",100+i)
end
local c=idle()
assert(c.entered==1 and c.active_owned_mutations==1 and c.post_set_fired==61 and c.post_set_pairs==61)
assert(p.idle_writes==1 and p.bat==1.7 and p.range==600 and p.hull==32 and wall.hull==128)
assert(c.samples[1].fire_interval_count==60 and c.samples[1].land_interval_count==60)
assert(math.abs(c.samples[1].land_interval_min-.5)<.000001)
assert(c.post_set_native_continuity_verified==false,"pure fixture was mislabeled native acceptance")
clean(p,a);assert(idle().restore_successes==1 and idle().restore_errors==0)

-- Each v3 release path restores first. Existing external root remains intact.
for _,change in ipairs({
    function(u) u.target=nil end,function(u) u.target=other_wall end,
    function(u) u.force=other_wall end,function(u) u.alive=false end,
    function(u) u.stunned=true end,function(u) u.disarmed=true end,
    function(u) u.restricted=true end,function(u) u.motion=true end,
    function(u) u.vertical=true end,function(u) u.hidden=true end,
    function(u) u.player_controlled=true end,function(u) u.p.z=1 end,
    function(u) u.range=601 end,function(u) u.hull=33 end,
    function(u) u.team=2 end,function(u) u.attack_cap=1 end,
    function(u) u.modifiers[#u.modifiers+1]={GetName=function() return "unknown_native" end} end,
    function(u) u.external_root=true;u.modifiers[#u.modifiers+1]={GetName=function() return "external_root" end,
        CheckState=function() return {[MODIFIER_STATE_ROOTED]=true} end} end}) do
    enable();p,a=enter();change(p);step(p,a,.1)
    assert(p.idle_acquire==true and p.idle_writes==2 and a.contact_mode==0)
    assert(not a.ranged_stationary_hold and not a.ranged_idle_acquire_hold)
    restored_before_mode(p);clean(p,a)
end
for _,change in ipairs({
    function() wall.alive=false end,function() wall.invulnerable=true end,
    function() wall.immune=true end,function() wall.p.y=1 end,function() wall.hull=129 end,
    function() a.wall_entindex=2;a.goal_wall=other_wall end,
    function() a.ai_state="retreat" end}) do
    enable();p,a=enter();change();step(p,a,.1)
    assert(p.idle_acquire and not a.ranged_stationary_hold and not a.ranged_idle_acquire_hold)
    restored_before_mode(p)
    wall.alive,wall.invulnerable,wall.immune,wall.p.y,wall.hull=true,false,false,0,128
    clean(p,a)
end
for _,reason in ipairs({"destroyed","recovery_order","target_changed","position_changed"}) do
    enable();p,a=enter();probe.release(a,p,reason);restored_before_mode(p)
    local writes=p.idle_writes;probe.release(a,p,reason)
    assert(p.idle_writes==writes and idle().exited==1,"release was not idempotent")
end
enable();p,a=enter();a.contact_mode=2;probe.release(a,p,"contact_mode_changed")
assert(p.idle_acquire and a.contact_mode==2,"release cleared external contact mode")

-- API toggle-off is immediate; raw flag, v3 off, guard/world/bus exit restore
-- on the existing callback/think. No timer, changed interval or order required.
enable();p,a=enter();assert(probe.set_idle_acquire_probe_enabled(false));restored_before_mode(p)
assert(p.idle_acquire and not a.ranged_stationary_hold and idle().active_owned_mutations==0)
enable();p,a=enter();_G.SURVIVAL_RANGED_IDLE_ACQUIRE_STABLE_PROBE=false;step(p,a,.1);restored_before_mode(p)
enable();p,a=enter();assert(probe.set_probe_enabled(false));restored_before_mode(p)
enable();p,a=enter();local oldworld=world;world={};step(p,a,.1);restored_before_mode(p)
assert(not probe.enabled() and not probe.idle_acquire_probe_enabled());world=oldworld
enable();p,a=enter();local oldguard=_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=world};step(p,a,.1);restored_before_mode(p)
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION=oldguard
enable();p,a=enter();bus.reset();step(p,a,.1);restored_before_mode(p)
enable();p,a=enter();local oldbus=package.loaded["core/event_bus"]
package.loaded["core/event_bus"]={get_generation=function() return {} end};step(p,a,.1);restored_before_mode(p)
package.loaded["core/event_bus"]=oldbus
enable();p,a=enter();tools=false;step(p,a,.1);restored_before_mode(p);tools=true

-- Preserve external bool changes and owner replacements. Never touch another
-- unit resolved by the same index, nor an unrelated holder's marker.
enable();p,a=enter();p.idle_acquire=true;step(p,a,.1)
assert(p.idle_writes==1 and not a.ranged_idle_acquire_hold and idle().restore_external_value_preserved==1)
enable();p,a=enter();local foreign={};p.survival_ranged_idle_acquire_owner=foreign;step(p,a,.1)
assert(p.idle_writes==1 and p.survival_ranged_idle_acquire_owner==foreign)
assert(idle().restore_ownership_lost==1 and not a.ranged_stationary_hold)
enable();p,a=enter();foreign={};a.ranged_idle_acquire_hold=foreign;step(p,a,.1)
assert(p.idle_writes==1 and a.ranged_idle_acquire_hold==foreign and idle().restore_ownership_lost==1)
enable();p,a=enter();local replacement=unit(p.index,3,-735);a.parent=replacement;step(p,a,.1)
assert(p.idle_writes==1 and replacement.idle_reads==0 and replacement.idle_writes==0)
assert(idle().restore_ownership_lost==1)
enable();p,a=enter();p.removed=true;probe.release(a,p,"destroyed")
assert(p.idle_writes==1 and idle().restore_invalid_unit==1 and idle().active_owned_mutations==0)

-- Restore failures retain a bounded owned recovery token. A later explicit
-- stop retries the saved bool, even with flags off and no v3 hold remaining.
enable();p,a=enter();local setter=p.SetIdleAcquire;p.SetIdleAcquire=nil
probe.release(a,p,"destroyed")
assert(a.ranged_idle_acquire_hold and not a.ranged_stationary_hold and a.contact_mode==0)
assert(idle().restore_errors==1 and idle().recovery_pending==1)
local ok,status=probe.stop_idle_acquire_probe()
assert(not ok and status.remaining_owned_mutations==1 and status.restore_errors==1)
p.SetIdleAcquire=setter;assert(probe.stop_idle_acquire_probe())
assert(p.idle_acquire and not a.ranged_idle_acquire_hold and idle().recovery_pending==0)
enable();p,a=enter();local getter=p.ShouldIdleAcquire
p.ShouldIdleAcquire=function() error("native readback unavailable") end
probe.release(a,p,"destroyed")
assert(p.idle_acquire and a.ranged_idle_acquire_hold and idle().restore_errors==1)
p.ShouldIdleAcquire=getter;assert(probe.stop_idle_acquire_probe());assert(not a.ranged_idle_acquire_hold)

-- Existing grace respects slow APS. Pre-set projectile landings may refresh
-- v3 proof, but cannot conceal a post-set interruption for the idle candidate.
enable();p,a=enter();p.rate=.2;step(p,a,5)
assert(a.ranged_idle_acquire_hold and p.idle_acquire==false)
step(p,a,6);assert(p.idle_acquire and not a.ranged_stationary_hold)
enable();assert(probe.set_idle_acquire_probe_enabled(false))
p,a=fixture();prove(p,a);event(p,a,"fired",500)
assert(probe.set_idle_acquire_probe_enabled(true));step(p,a,.01)
now=now+2.8;event(p,a,"landed",500)
assert(a.ranged_idle_acquire_hold and idle().post_set_pairs==0)
step(p,a,.3)
assert(p.idle_acquire and not a.ranged_stationary_hold and idle().post_set_stalls==1)
assert(idle().reasons.idle_post_set_stalled==1)
prove(p,a);step(p,a,.01)
assert(p.idle_writes==2 and not a.ranged_idle_acquire_hold,
    "known interrupted candidate repeatedly disabled acquisition in one generation")
clean(p,a)

-- Pending state and sample history remain bounded, without extra native events.
enable();p,a=enter()
for i=1,16 do event(p,a,"fired",10000+i) end
assert(#a.ranged_idle_acquire_hold.pending==16)
event(p,a,"fired",10017)
assert(not a.ranged_idle_acquire_hold and p.idle_acquire and probe.snapshot().pending_overflow==1,
    "candidate bypassed original v3 overflow invalidation")
clean(p,a)
enable()
for i=1,100 do p,a=enter();clean(p,a) end
c=idle();assert(c.entered==100 and c.exited==100 and #c.samples==32 and c.samples_overwritten==68)
assert(c.active_owned_mutations==0 and c.restore_errors==0 and c.owner_limit==1024)
assert(probe.snapshot().observation_interval_seconds==.5 and c.attack_orders_issued==0)
enable()
local held={}
for i=1,1024 do
    p,a=enter();held[#held+1]={parent=p,owner=a}
end
p,a=fixture();prove(p,a);step(p,a,.01)
assert(p.idle_writes==0 and p.idle_reads==0 and idle().admission_rejections.owner_limit==1,
    "live owned mutation registry exceeded its explicit bound")
assert(idle().active_owned_mutations==1024 and #idle().samples==32)
assert(probe.stop_idle_acquire_probe())
for _,entry in ipairs(held) do
    assert(entry.parent.idle_acquire and entry.parent.idle_writes==2
        and not entry.owner.ranged_idle_acquire_hold and not entry.owner.ranged_stationary_hold)
end
clean(p,a)
assert(idle().active_owned_mutations==0 and idle().restore_errors==0)
assert(probe.stop_idle_acquire_probe());probe.set_probe_enabled(false)
print("RANGED_IDLE_ACQUIRE_STABLE_PASS: actual v3 proof, strict bool/native wall target, default-off zero idle calls, one setter, exact post-set records, pre-set inflight exclusion, bounded cadence/history, all root exits restore first, external ownership/value preservation, retryable restoration failures, slow/stalled attacks; native continuity/FPS UNVERIFIED")
