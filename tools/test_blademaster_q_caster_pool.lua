-- Real production service, public events and real scheduler/bus; no native render.
package.path = "scripts/vscripts/?.lua;" .. package.path
local now, mode, in_tools, server = 0, {}, true, true
function IsServer() return server end
function IsInToolsMode() return in_tools end
function GetMapName() return "template_map" end
function class(value) value = value or {}; value.__index = value; return value end
function Vector(x,y,z) return {x=x,y=y,z=z} end
GameRules = {GetGameTime=function() return now end, GetGameModeEntity=function() return mode end}
DOTA_UNIT_CAP_NO_ATTACK, DOTA_UNIT_ORDER_CAST_POSITION, LUA_MODIFIER_MOTION_NONE = 0, 5, 0
DOTA_UNIT_ORDER_CAST_NO_TARGET, DOTA_ABILITY_BEHAVIOR_NO_TARGET, DOTA_ABILITY_BEHAVIOR_POINT = 8, 4, 16
EF_NODRAW = 32
DOTA_UNIT_TARGET_TEAM_ENEMY, DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC = 1, 2, 4
DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES, FIND_ANY_ORDER, DAMAGE_TYPE_PURE = 8, 0, 4
local state_names = {"INVULNERABLE","UNSELECTABLE","NO_HEALTH_BAR","NO_UNIT_COLLISION",
    "NOT_ON_MINIMAP","COMMAND_RESTRICTED","DISARMED","SILENCED","MUTED","ROOTED","OUT_OF_GAME"}
for index,name in ipairs(state_names) do _G["MODIFIER_STATE_"..name] = index end
local linked = {}
function LinkLuaModifier(name,path)
    linked[name] = require(path)
end
package.loaded["systems/gameplay_phase_guard"] = {post_clear_frozen=function() return false end}
package.loaded["systems/hero_cosmetic_service"] = {sync_appearance=function() return true end,clear=function() end}
package.loaded["systems/hero_summon_attack_rate"] = {apply=function() return 100 end}
package.loaded["combat/endless_stat_projection"] = {prepare=function(_,value) return value end}
package.loaded["config/armor_balance"] = {from_war3=function(value) return value end}
package.loaded["systems/destination_validation_service"] = {validate=function() return true end}
local bus, events = require("core/event_bus"), require("core/events")
local scheduler, combat = require("core/scheduler"), require("combat/combat_events")
local timers, cast_timers, after = {}, {}, scheduler.after
local schedule_cast_throw = false
local canceled_tasks, cancel = {}, scheduler.cancel
scheduler.cancel = function(id)
    canceled_tasks[id]=(canceled_tasks[id] or 0)+1
    return cancel(id)
end
scheduler.after = function(delay,callback,id)
    if id and id:match("^blademaster_q_cast:") then
        assert(delay==0.03,"NO_TARGET must wait the actual next-frame cast delay")
        if schedule_cast_throw then schedule_cast_throw=false;error("injected cast schedule allocation failure") end
    end
    local result = after(delay,callback,id)
    if id and id:match("^blademaster_q_pool:") then timers[#timers+1] = callback end
    if id and id:match("^blademaster_q_cast:") then
        cast_timers[#cast_timers+1]={callback=callback,id=result,queued_at=now,due=now+delay}
    end
    return result
end
local units, created, removed, casts, deals, hero_by_player = {}, {}, {}, {}, {}, {}
local remove_attempts = {}
local order_attempts = {}
local canonical_requests = 0
local next_id, configure_throw, order_throw, hide_throw = 1000, nil, false, false
local owner_api_fault, players = nil, {}
local legacy_prepare_fault
local function legacy_api_fault(u,method,stage)
    if u.name~="npc_dota_hero_legion_commander" or not u.survival_blademaster_visual_caster
        or u.survival_blademaster_q_pool_entry then return end
    if stage=="before" then
        u.legacy_prepare_trace=u.legacy_prepare_trace or {}
        u.legacy_prepare_trace[#u.legacy_prepare_trace+1]=method
    end
    if legacy_prepare_fault and legacy_prepare_fault.method==method
        and legacy_prepare_fault.stage==stage then
        legacy_prepare_fault=nil
        error("injected legacy "..method.." "..stage.." failure")
    end
end
local native_q_behavior, child_fixture = 134217764, nil
local submit_q
local function has_behavior(value, flag) return value % (flag*2) >= flag end
local function player_owner(player_id)
    if not players[player_id] then
        players[player_id] = {id=2+player_id,player=player_id,is_player=true,
            IsNull=function() return false end,
            entindex=function(self) return self.id end}
    end
    return players[player_id]
end
local e_active, w_active, frozen = false, false, false
package.loaded["systems/gameplay_phase_guard"].post_clear_frozen=function() return frozen end
package.loaded["combat/endless_stat_projection"].prepare=function(u,value)
    u.survival_endless_attack_scale=1;u.survival_endless_health_scale=1;return value
end
local function unit(id,team,player)
    local u = {id=id,team=team,player=player,life=true,mana=315,max_mana=315,
        modifiers={},world=mode,owner=player_owner(player),born_at=now,
        acquire=true,acquire_range=600,pending_order="startup_autonomous_order"}
    function u:IsNull() return self.null==true end
    function u:IsAlive() return self.life end
    function u:entindex() return self.id end
    function u:GetTeamNumber() return self.team end
    function u:GetPlayerOwnerID() return self.player end
    function u:SetPlayerID(value) self.player=value end
    function u:GetUnitName() return self.name or "npc_dota_hero_juggernaut" end
    function u:GetOwner() return self.owner end
    function u:SetOwner(value)
        legacy_api_fault(self,"SetOwner","before")
        self.set_owner_calls=(self.set_owner_calls or 0)+1
        self.owner_before_set=self.owner
        if self.survival_blademaster_q_pool_entry and self.set_owner_calls==1 then
            assert(self.survival_blademaster_q_pool_entry.unit==self
                and self.survival_blademaster_q_pool_entry.owner==value,
                "pool must own the candidate before fallible SetOwner")
        end
        local fault=owner_api_fault
        owner_api_fault=nil
        if fault=="throw" then error("injected SetOwner failure") end
        if fault=="reject" then return false end
        if fault=="noop" then return end -- Native void API can silently leave ownership unchanged.
        self.owner=value
        if fault=="after_throw" then error("injected SetOwner failure after ownership side effect") end
        legacy_api_fault(self,"SetOwner","after")
    end
    function u:GetAbsOrigin() return self.position or Vector(10,20,0) end
    function u:SetAbsOrigin(value) self.position=value;self.position_set_at=now end
    function u:SetControllableByPlayer(value,enabled)
        self.controllable,self.control_player=enabled,value
        if self.survival_blademaster_visual_caster then
            assert(value==self.player and enabled==false,
                "visual caster must use the precise player and disable player control")
        end
        self.owner_after_controllable=self.owner -- This API never changes GetOwner().
    end
    function u:SetAttackCapability(value) self.attack=value end
    function u:SetHullRadius(value) self.hull=value end
    function u:SetIdleAcquire(value)
        legacy_api_fault(self,"SetIdleAcquire","before")
        self.acquire=value
        legacy_api_fault(self,"SetIdleAcquire","after")
    end
    function u:SetAcquisitionRange(value)
        legacy_api_fault(self,"SetAcquisitionRange","before")
        self.acquire_range=value
        legacy_api_fault(self,"SetAcquisitionRange","after")
    end
    function u:SetDayTimeVisionRange(value) self.dayvision=value end
    function u:SetNightTimeVisionRange(value) self.nightvision=value end
    function u:AddNoDraw()
        if hide_throw then hide_throw=false; error("injected hide failure") end
        self.hidden=true
    end
    function u:RemoveNoDraw() self.hidden=false end
    function u:FirstMoveChild() return self.children and self.children[1] end
    function u:Stop()
        legacy_api_fault(self,"Stop","before")
        self.stopped=(self.stopped or 0)+1;self.channeling=false
        self.pending_order=nil
        for _,native in pairs(self.abilities or {}) do native.phase=false end
        legacy_api_fault(self,"Stop","after")
    end
    function u:IsChanneling() return self.channeling==true end
    function u:RemoveModifierByName(name) self.modifiers[name]=nil end
    function u:GetMaxMana() return self.max_mana end
    function u:GetMaxHealth() return self.max_health or 100 end
    function u:GetHealth() return self.health or 100 end
    function u:SetBaseMaxHealth(value) self.base_health=value end
    function u:SetMaxHealth(value) self.max_health=value end
    function u:SetHealth(value) self.health=value end
    function u:SetBaseDamageMin(value) self.damage_min=value end
    function u:SetBaseDamageMax(value) self.damage_max=value end
    function u:FindModifierByName(name) return self.modifiers[name] end
    function u:SetMana(value)
        if configure_throw=="SetMana" then configure_throw=nil;error("injected mana failure") end
        self.mana=value
    end
    function u:AddNewModifier(_,_,name)
        local modifier = {name=name,unit=self,IsNull=function() return false end}
        if linked[name] then setmetatable(modifier,linked[name]) end
        self.modifiers[name]=modifier
        return modifier
    end
    function u:FindAbilityByName(name) return self.abilities and self.abilities[name] end
    function u:AddAbility(name)
        local a={id=self.id*10,name=name,unit=self,ready=true,phase=false,behavior=native_q_behavior}
        function a:IsNull() return self.unit:IsNull() end
        function a:entindex() return self.id end
        function a:SetLevel(value) self.level=value end
        function a:SetHidden(value) self.hidden=value end
        function a:SetActivated(value) self.activated=value end
        if name=="legion_commander_overwhelming_odds" then
            function a:GetBehavior() return self.behavior end
        end
        function a:GetCastPoint() return self.name=="legion_commander_overwhelming_odds" and 0 or 0.2 end
        function a:GetCastRange() return self.name=="legion_commander_overwhelming_odds" and 0 or 600 end
        function a:EndCooldown()
            if configure_throw=="EndCooldown" then configure_throw=nil;error("injected cooldown failure") end
            self.ready=true;self.cooldown=0
        end
        function a:IsCooldownReady() return self.ready end
        function a:GetCooldownTimeRemaining() return self.cooldown or 0 end
        function a:IsInAbilityPhase() return self.phase end
        self.abilities=self.abilities or {};self.abilities[name]=a
        return a
    end
    function u:CastAbilityNoTarget(native,player)
        if native.name=="legion_commander_overwhelming_odds" then
            submit_q(self,native,"CastAbilityNoTarget",nil,player)
        else casts[#casts+1]={unit=self,ability=native.name,e=true,player=player} end
    end
    function u:CastAbilityOnPosition(position,native,player)
        submit_q(self,native,"CastAbilityOnPosition",position,player)
    end
    units[id]=u
    return u
end
function CreateUnitByName(name,position,clear,owner,owner_entity,team)
    next_id=next_id+1
    local u=unit(next_id,team,owner and owner.player or -1)
    u.name,u.position=name,position
    u.create_owner_arg,u.create_owner_entity_arg=owner,owner_entity
    u.birth_owner=u.owner -- Native hero creation binds the Player, not either hero argument.
    if name=="npc_dota_hero_legion_commander" and owner_api_fault=="missing" then
        u.SetOwner=nil;owner_api_fault=nil
    end
    if name=="npc_dota_hero_legion_commander" and child_fixture then
        local effects = {hidden=false,IsNull=function(self) return self.null==true end}
        function effects:AddNoDraw() self.hidden=true;self.hide_calls=(self.hide_calls or 0)+1 end
        if child_fixture~="missing" then
            function effects:RemoveEffects(mask)
                assert(mask==EF_NODRAW,"wearable fallback must remove only native NODRAW")
                self.remove_effects_calls=(self.remove_effects_calls or 0)+1
                if child_fixture=="throw" then child_fixture="normal";error("injected wearable RemoveEffects failure") end
                self.hidden=false
            end
        end
        local direct = {hidden=false,IsNull=function(self) return self.null==true end}
        function direct:AddNoDraw() self.hidden=true;self.hide_calls=(self.hide_calls or 0)+1 end
        function direct:RemoveNoDraw() self.hidden=false;self.remove_nodraw_calls=(self.remove_nodraw_calls or 0)+1 end
        local plain = {IsNull=function(self) return self.null==true end}
        function effects:NextMovePeer() return direct end
        function direct:NextMovePeer() return plain end
        function plain:NextMovePeer() return nil end
        u.children={effects,direct,plain}
    end
    created[#created+1]=u
    return u
end
function UTIL_Remove(u)
    remove_attempts[#remove_attempts+1]=u -- Record even rejected attempts hidden by production pcall.
    assert(u.world==mode,"old world native handle removed")
    u.remove_calls=(u.remove_calls or 0)+1
    if not u.null then removed[#removed+1]=u end
    u.null=true;u.life=false
end
function ExecuteOrderFromTable(order)
    local u=assert(units[order.UnitIndex])
    local a=assert(u:FindAbilityByName("legion_commander_overwhelming_odds"))
    assert(order.Queue==false)
    assert(order.AbilityIndex==a.id)
    local method=order.OrderType==DOTA_UNIT_ORDER_CAST_POSITION and "ExecuteOrderFromTable:POINT"
        or order.OrderType==DOTA_UNIT_ORDER_CAST_NO_TARGET and "ExecuteOrderFromTable:NO_TARGET"
    assert(method,"unexpected Q order type")
    submit_q(u,a,method,order.Position,u.player)
end
submit_q=function(u,a,method,position,player)
    local attempt={unit=u,ability=a,method=method,position=position,player=player,at=now}
    order_attempts[#order_attempts+1]=attempt
    local no_target=method=="CastAbilityNoTarget" or method=="ExecuteOrderFromTable:NO_TARGET"
    if no_target~=has_behavior(a:GetBehavior(),DOTA_ABILITY_BEHAVIOR_NO_TARGET) then
        attempt.ignored="wrong_behavior";return -- Native can silently discard an invalid order.
    end
    assert(no_target and position==nil or not no_target and position,
        "native order shape must match the ability behavior")
    assert(player==u.player,"Q native command must keep the source player")
    assert(a.level==1 and a.hidden==false and a.activated==true)
    assert(not u.modifiers.modifier_blademaster_q_caster_idle,
        "borrow must restore original native cast state")
    if no_target and (method=="CastAbilityNoTarget" or now < math.max(u.born_at,u.position_set_at or 0)+0.03-0.0000001) then
        attempt.ignored=method=="CastAbilityNoTarget" and "direct_no_effect" or "born_frame_order"
        return -- Root native probe: direct method and same-frame Exec leave CD/mana/buff unchanged.
    end
    if not no_target then assert(not u.hidden,"point order keeps its original synchronous visible state") end
    -- Model competing native orders; this hypothesis is not a proof of the
    -- exact cause of root's old OFF misses. Actual all-event native retest remains required.
    if u:GetOwner().is_player or u.acquire and u.acquire_range>0 or u.pending_order then
        attempt.ignored="autonomous_order_competition";return
    end
    assert(a.ready and u.mana==u.max_mana and not u.modifiers.modifier_legion_commander_overwhelming_odds,
        "native cooldown, mana and old Q buff must reset")
    for _,child in ipairs(u.children or {}) do
        if child.AddNoDraw and not no_target then
            assert(not child.hidden,"point checkout must restore its hidden wearable before submitting")
        end
    end
    if order_throw then order_throw=false;error("injected native order failure") end
    casts[#casts+1]={unit=u,ability=a.name,position=position,player=player,method=method,no_target=no_target,at=now}
    a.ready=false;a.cooldown=18;a.phase=true;u.mana=u.mana-90
    u.modifiers.modifier_legion_commander_overwhelming_odds={native=true}
end
local enemy, other, corpse = unit(101,3,9),unit(102,3,9),unit(103,3,9)
corpse.life=false
function FindUnitsInRadius() return {enemy,other,corpse} end
function RollPercentage() return true end
local service=require("systems/blademaster_exclusive_service")
local pool=require("systems/blademaster_q_caster_pool")
local function handlers()
    bus.handle_request(events.HERO_SKILL_STATE_GET_REQUEST,function()
        return {snapshot={skills={
            {skill_id="skill_blademaster_exclusive",level=1,locked=0},
            {skill_id="skill_blademaster_agility",level=w_active and 1 or 0,locked=0},
            {skill_id="skill_blademaster_swiftness",level=e_active and 1 or 0,locked=0}}}}
    end)
    bus.handle_request(events.HERO_COMBAT_STATS_GET_REQUEST,function() return {snapshot={}} end)
    bus.handle_request(events.HERO_SUMMON_GET_REQUEST,function(p)
        canonical_requests=canonical_requests+1
        return {ok=true,unit=hero_by_player[p.player_id]}
    end)
    bus.handle_request(combat.DEAL_REQUEST,function(payload)
        assert(payload.damage_type==DAMAGE_TYPE_PURE and payload.can_crit==false and payload.tags.non_recursive==true)
        deals[#deals+1]=payload
        return {success=true,final_damage=payload.base_damage}
    end)
end
local function fresh()
    bus.reset();scheduler.clear();handlers();service.init()
    now=0;mode={}
    _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION=nil
    created,removed,casts,deals,timers,cast_timers={},{},{},{},{},{}
    remove_attempts={}
    order_attempts,canceled_tasks={},{}
    canonical_requests=0
    schedule_cast_throw=false
    e_active,w_active,frozen=false,false,false
    owner_api_fault=nil
    legacy_prepare_fault=nil
    native_q_behavior,child_fixture=134217764,nil
end
local function hero(id,player)
    local h=unit(id or 200,2,player or 2)
    h.survival_hero_id="hero_blademaster"
    hero_by_player[h.player]=h
    return h
end
local function enable()
    _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=mode}
    assert(pool.set_probe(true))
end
local function queue_hit(h,target,extra)
    local payload={player_id=h and h.player or 2,attacker=h,target=target or enemy,
        final_damage=12345,critical=true,is_main_attack=true}
    for k,v in pairs(extra or {}) do payload[k]=v end
    bus.emit(events.HERO_FINAL_CRITICAL_ATTACK_DAMAGE,payload)
end
local function advance(delta) now=now+delta;scheduler.think() end
local function flush_casts() advance(0.031) end
local function hit(h,target,extra) queue_hit(h,target,extra);flush_casts() end
local function damage_count(n)
    assert(#deals==n*2,"each Q must copy unchanged damage to exactly two living enemies")
    for _,d in ipairs(deals) do assert(d.base_damage==12345 and d.tags.source=="q_copy") end
end

fresh()
local h=hero()
assert(pool.snapshot().enabled==false and not pool.set_probe(true),"default OFF and real guard required")
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=mode}
in_tools=false;assert(not pool.set_probe(true));in_tools=true
server=false;assert(not pool.set_probe(true));server=true
hit(h);damage_count(1);assert(#created==1 and #casts==1 and pool.snapshot().total==0,
    "legacy Q must produce exactly one effective queued native command with pool OFF")
assert(created[1].birth_owner==player_owner(h.player)
    and created[1]:GetOwner()==h and created[1].owner_before_set==created[1].birth_owner
    and created[1].owner_after_controllable==created[1].birth_owner
    and created[1].set_owner_calls==1 and created[1].acquire==false
    and created[1].acquire_range==0 and created[1].stopped==1 and not created[1].pending_order,
    "legacy must bind its Player-owned birth and stop autonomous acquisition before queued Q")
assert(pool.set_probe(true));hit(h);damage_count(2)
assert(not created[1].survival_blademaster_q_pool_entry,"already existing legacy caster must never migrate into pool")
assert(#created==2 and pool.snapshot().busy==1,
    "native Player-owned birth must be explicitly bound before pool identity admission")
advance(1.2);assert(#removed==1 and pool.snapshot().idle==1,"legacy path keeps original temporary lifetime")
print("CASE default_off_scope_and_no_legacy_migration PASS")

fresh();h=hero();enable()
hit(h,corpse);damage_count(1)
local borrowed=created[1]
assert(#casts==1 and pool.snapshot().busy==1 and borrowed.hidden)
assert(borrowed.birth_owner==player_owner(h.player) and borrowed.birth_owner~=h
    and borrowed.create_owner_arg==h and borrowed.create_owner_entity_arg==h
    and borrowed.owner_before_set==borrowed.birth_owner
    and borrowed:GetOwner()==h and borrowed.owner_after_controllable==h
    and borrowed.set_owner_calls==1,
    "pool must explicitly bind the exact hero after native Player-owned birth")
local old_timer=timers[1]
advance(1.2)
assert(pool.snapshot().idle==1 and #removed==0 and borrowed.position.z==-10000)
assert(borrowed.attack==DOTA_UNIT_CAP_NO_ATTACK and borrowed.acquire==false and borrowed.acquire_range==0)
local idle=borrowed.modifiers.modifier_blademaster_q_caster_idle
local checked=idle:CheckState()
for _,name in ipairs(state_names) do assert(checked[_G["MODIFIER_STATE_"..name]],"idle state missing "..name) end
hit(h);damage_count(2);assert(#created==1 and #casts==2 and pool.snapshot().counters.reused==1)
assert(borrowed:GetOwner()==h and borrowed.set_owner_calls==1,
    "reuse must validate the existing binding rather than silently recreate/rebind the caster")
old_timer();assert(pool.snapshot().busy==1,"late old timer cannot return new lease")
advance(1.2);assert(pool.snapshot().idle==1)
hit(h,enemy,{critical=false});hit(h,enemy,{is_main_attack=false});hit(h,enemy,{blademaster_secondary=true})
assert(#casts==2);damage_count(2)
print("CASE reuse_cooldown_mana_buff_dead_target_token_and_filters PASS")

fresh();h=hero();enable()
for i=1,40 do queue_hit(h) end
damage_count(40)
assert(#casts==0 and #cast_timers==40,"all 40 simultaneous Q damage copies precede queued native submission")
flush_casts()
assert(#casts==40 and #created==40,"overflow must preserve simultaneous effects")
assert(pool.snapshot().total==32 and pool.snapshot().busy==32 and pool.snapshot().counters.overflow==8)
advance(1.2)
assert(pool.snapshot().total==4 and pool.snapshot().idle==4 and #removed==36,
    "only four idle retained per owner; overflow and surplus are removed")
print("CASE overflow_total_and_idle_caps_same_damage PASS")

fresh();enable()
for player=0,3 do
    local source=hero(210+player,player)
    for i=1,14 do queue_hit(source) end
end
damage_count(56)
assert(#casts==0 and #cast_timers==56,"four-owner simultaneous damage must not depend on immediate native cast")
flush_casts()
assert(#casts==56 and pool.snapshot().busy==32 and pool.snapshot().counters.overflow==24)
advance(1.2)
local owner_idle={}
for _,u in ipairs(created) do
    if not u.null and u.survival_blademaster_q_pool_entry then
        owner_idle[u.owner]=(owner_idle[u.owner] or 0)+1
    end
end
for _,n in pairs(owner_idle) do assert(n<=4) end
assert(pool.snapshot().total<=16 and pool.snapshot().total<=32)
pool.set_probe(false);assert(pool.snapshot().total==0)
print("CASE four_owner_concurrent_capacity_and_disable_cleanup PASS")

fresh();h=hero();enable()
hit(h);hit(h);advance(1.2);hit(h)
h.life=false;bus.emit(events.ENGINE_ENTITY_KILLED,{victim=h})
assert(pool.snapshot().total==0 and #removed==2,"dead owner destroys both busy and idle")
for _,callback in ipairs(timers) do callback() end
assert(pool.snapshot().total==0)
hit(h);assert(#casts==3,"dead owner event is not a Q")
print("CASE dead_owner_busy_idle_and_late_callbacks PASS")

fresh();h=hero();enable();hit(h);advance(1.2)
local replacement=hero(201,2)
bus.emit(events.HERO_SUMMONED,{unit=replacement,player_id=2})
assert(pool.snapshot().total==0 and #removed==1)
hit(replacement);assert(pool.snapshot().busy==1)
bus.emit(events.HERO_REMOVED,{unit=h,player_id=2})
assert(pool.snapshot().busy==1,"late removed old handle must not retire new owner's lease")
bus.emit(events.HERO_REMOVED,{unit=replacement,player_id=2})
assert(pool.snapshot().total==0)
print("CASE exact_owner_replacement_and_late_remove PASS")

fresh();h=hero();enable();hit(h);advance(1.2)
local original=created[1]
h.team=4;hit(h)
assert(original.null and #created==2 and created[2].team==4)
advance(1.2)
local reused_index_owner=hero(h.id,2)
reused_index_owner.team=4
hit(reused_index_owner)
assert(#created==3,"same entindex with another handle does not borrow old owner's caster")
bus.emit(events.PLAYER_DEFEATED,{player_id=2})
assert(pool.snapshot().total==0)
print("CASE owner_team_handle_and_defeat PASS")

fresh();h=hero();enable();w_active=true;frozen=true
local clone
bus.subscribe(events.HERO_CLONE_CREATED,function(payload) clone=payload.unit end)
bus.emit(events.HERO_SKILL_CHANGED,{player_id=2})
assert(clone and clone.survival_blademaster_clone==true,"real service must create W clone")
assert(clone:GetOwner()==player_owner(h.player),"native clone birth must also retain its Player owner")
assert(clone.control_player==h.player and clone.controllable==true,
    "actual W clone keeps its original owner player control")
assert(service.trigger_clone_q(2,clone,enemy,12345));damage_count(1)
assert(#casts==0,"public W clone Q must queue its native cast after immediate damage")
flush_casts()
assert(pool.snapshot().total==1 and created[2].owner==clone)
assert(created[2].birth_owner==player_owner(h.player) and created[2].owner_before_set~=clone
    and created[2].set_owner_calls==1,"clone Q must bind the precise clone handle, not its Player/main hero")
advance(1.2)
assert(service.trigger_clone_q(2,clone,corpse,12345));damage_count(2)
flush_casts()
assert(#created==2 and #casts==2 and pool.snapshot().counters.reused==1)
bus.emit(events.HERO_REMOVED,{unit=h,player_id=2})
assert(pool.snapshot().total==0,"source hero removal clears clone-owned Q casters")
print("CASE real_W_clone_public_trigger_same_damage_and_source_remove PASS")

for _,fault in ipairs({"throw","after_throw","reject","missing","noop"}) do
    fresh();h=hero();enable();owner_api_fault=fault
    hit(h);damage_count(1)
    local candidate,legacy=created[1],created[2]
    local snapshot=pool.snapshot()
    assert(#created==2 and #removed==1 and #casts==1 and casts[1].unit==legacy,
        "SetOwner failure must retire precisely its candidate before one legacy order: "..fault)
    assert(candidate.null and candidate.remove_calls==1
        and candidate.survival_blademaster_q_pool_entry==nil and snapshot.total==0
        and snapshot.idle==0 and snapshot.busy==0 and snapshot.counters.created==1
        and snapshot.counters.failed==1 and snapshot.counters.removed==1
        and snapshot.counters.submitted==0 and snapshot.counters.reused==0,
        "failed SetOwner must not retain resources or a lease: "..fault)
    assert(#remove_attempts==1 and remove_attempts[1]==candidate,
        "SetOwner cleanup must attempt removal only for its precise owned candidate: "..fault)
    assert(not h.null and candidate.birth_owner==player_owner(h.player)
        and legacy:GetOwner()==h and legacy.birth_owner==player_owner(h.player) and legacy.set_owner_calls==1,
        "cleanup/fallback must not mutate or remove the source hero or Player: "..fault)
    if fault=="after_throw" then assert(candidate:GetOwner()==h,
        "a throwing SetOwner can already have changed native ownership") end
    if fault=="noop" then assert(snapshot.last_error:find("checkout superseded",1,true),
        "silent native owner mismatch must still fail the exact identity check")
    elseif fault=="missing" then assert(snapshot.last_error:find("API missing: SetOwner",1,true))
    elseif fault=="reject" then assert(snapshot.last_error:find("API rejected: SetOwner",1,true))
    else assert(snapshot.last_error:find("injected SetOwner failure",1,true)) end
    advance(1.2)
    assert(#removed==2 and legacy.remove_calls==1 and candidate.remove_calls==1,
        "failed owner binding keeps the original legacy deadline and cannot remove twice")
    assert(#remove_attempts==2 and remove_attempts[1]==candidate and remove_attempts[2]==legacy,
        "removal attempts must preserve exact candidate/fallback identity and order")
    for _,callback in ipairs(timers) do callback() end
    assert(candidate.remove_calls==1 and legacy.remove_calls==1 and pool.snapshot().total==0
        and #remove_attempts==2)
    hit(h);damage_count(2)
    assert(pool.snapshot().busy==1 and #created==3 and #casts==2
        and created[3]:GetOwner()==h and created[3].set_owner_calls==1,
        "one owner API failure must not prevent the next valid public Q")
    advance(1.2);hit(h);damage_count(3)
    assert(#created==3 and #casts==3 and pool.snapshot().counters.reused==1,
        "post-failure native binding must allow the later valid reuse")
    print("CASE native_player_birth_SetOwner_"..fault.."_cleanup_and_fallback PASS")
end

fresh();h=hero();enable();hit(h);advance(1.2)
local owner_tampered=created[1]
owner_tampered:SetOwner(player_owner(h.player))
hit(h);damage_count(2)
assert(owner_tampered.null and owner_tampered.remove_calls==1 and #created==2
    and #casts==2 and created[2]:GetOwner()==h and pool.snapshot().busy==1,
    "a changed actual GetOwner must retire stale idle identity, not repair and reuse it")
print("CASE native_owner_tamper_retires_exact_idle_handle PASS")

for _,behavior in ipairs({134217764,134217748}) do
    fresh();h=hero();native_q_behavior=behavior
    queue_hit(h);damage_count(1)
    local legacy=created[1]
    local legacy_native=legacy:FindAbilityByName("legion_commander_overwhelming_odds")
    assert(#casts==0 and #order_attempts==0 and legacy_native:GetCooldownTimeRemaining()==0
        and legacy.mana==315 and not legacy.modifiers.modifier_legion_commander_overwhelming_odds,
        "public legacy Q copies damage immediately but must not issue on the birth frame")
    advance(0.029);assert(#casts==0 and #order_attempts==0,"the actual cast task must wait at least .03")
    advance(0.002)
    assert(casts[1].method=="ExecuteOrderFromTable:NO_TARGET" and casts[1].no_target
        and casts[1].position==nil and casts[1].player==h.player,
        "legacy Q must submit the actual queued no-target Exec for current/mixed native flags")
    assert(legacy_native:GetCastPoint()==0 and legacy_native:GetCooldownTimeRemaining()==18
        and legacy.mana==225 and legacy.modifiers.modifier_legion_commander_overwhelming_odds,
        "accepted queued Exec updates the mock native state matching root's separated probe")
    advance(0.959);assert(#removed==0,"native zero cast point retains the original minimum one-second deadline")
    advance(0.02);assert(#removed==1)
    enable();queue_hit(h);damage_count(2)
    local candidate=created[2]
    assert(#casts==1 and candidate:GetOwner()==h and pool.snapshot().busy==1
        and candidate.survival_blademaster_q_pool_entry.lease.cast_task==cast_timers[2].id,
        "pool must own the exact queued native cast task before its execution")
    flush_casts()
    assert(casts[2].method=="ExecuteOrderFromTable:NO_TARGET")
    advance(1.01);queue_hit(h);damage_count(3)
    assert(#casts==2 and pool.snapshot().counters.reused==1,
        "reuse still queues a new cast independently after immediate copied damage")
    flush_casts()
    assert(#created==2 and #casts==3 and casts[3].method=="ExecuteOrderFromTable:NO_TARGET"
        and pool.snapshot().counters.reused==1,
        "pool reuse must submit the same no-target native ability/player as the legacy path")
    print("CASE native_Q_no_target_behavior_"..behavior.."_legacy_pool_and_deadline PASS")
end

fresh();h=hero();native_q_behavior=DOTA_ABILITY_BEHAVIOR_POINT
hit(h);enable();hit(h);advance(1.01);hit(h);damage_count(3)
for _,cast in ipairs(casts) do
    assert(cast.method=="ExecuteOrderFromTable:POINT" and not cast.no_target
        and cast.position and cast.position.x==enemy:GetAbsOrigin().x,
        "older point behavior must retain its original position-order shape")
end
assert(#created==2 and pool.snapshot().counters.reused==1)
print("CASE native_Q_point_behavior_retains_position_order PASS")

fresh();h=hero();native_q_behavior=DOTA_ABILITY_BEHAVIOR_POINT
local native_execute=ExecuteOrderFromTable
ExecuteOrderFromTable=nil
hit(h);enable();hit(h);damage_count(2)
assert(casts[1].method=="CastAbilityOnPosition" and casts[2].method=="CastAbilityOnPosition",
    "older point behavior retains its direct API fallback when ExecuteOrderFromTable is absent")
ExecuteOrderFromTable=native_execute
print("CASE native_Q_point_direct_API_fallback PASS")

fresh();h=hero();enable();child_fixture="normal"
hit(h);damage_count(1)
local with_wearables=created[1]
assert(pool.snapshot().busy==1 and #created==1 and #casts==1,
    "native wearable without RemoveNoDraw must use RemoveEffects and retain its pooled caster")
assert(with_wearables.children[1].remove_effects_calls==1
    and with_wearables.children[2].remove_nodraw_calls==1
    and with_wearables.children[1].hidden and with_wearables.children[2].hidden,
    "wearable APIs differ from BaseNPC; show must restore and normal submission must hide them")
advance(1.01);hit(h);damage_count(2)
assert(#created==1 and #casts==2 and pool.snapshot().counters.reused==1
    and with_wearables.children[1].remove_effects_calls==2
    and with_wearables.children[2].remove_nodraw_calls==2,
    "reuse restores only hidden-capable children; the plain child has no draw API")
print("CASE native_wearable_RemoveEffects_fallback_and_plain_child_reuse PASS")

for _,fault in ipairs({"throw","missing"}) do
    fresh();h=hero();enable();child_fixture=fault
    hit(h);damage_count(1)
    local candidate,legacy=created[1],created[2]
    assert(#created==2 and #casts==1 and casts[1].unit==legacy and #removed==1
        and candidate.null and candidate.remove_calls==1
        and pool.snapshot().total==0 and pool.snapshot().counters.submitted==0,
        "wearable show failure must retire the candidate and issue one legacy effect")
    assert(not h.null and candidate.survival_blademaster_q_pool_entry==nil)
    assert(#remove_attempts==1 and remove_attempts[1]==candidate)
    advance(1.01)
    assert(candidate.remove_calls==1 and legacy.remove_calls==1 and #removed==2
        and #remove_attempts==2 and remove_attempts[2]==legacy)
    print("CASE native_wearable_RemoveEffects_"..fault.."_cleanup_and_fallback PASS")
end

fresh();h=hero();enable()
hit(nil);assert(#created==0 and #casts==0 and #deals==0)
configure_throw="SetMana";hit(h);damage_count(1)
assert(#created==2 and #removed==1 and #casts==1 and pool.snapshot().total==0,
    "configuration failure cleans candidate and falls back before submitting")
configure_throw="EndCooldown";hit(h);damage_count(2)
assert(#casts==2 and #created==4 and #removed==2)
order_throw=true;queue_hit(h);damage_count(3)
assert(#casts==2 and #created==5 and #removed==2 and pool.snapshot().busy==1,
    "queued submission is owned before its later native API failure")
flush_casts()
assert(#casts==2 and #created==5 and #removed==2 and pool.snapshot().busy==1,
    "async Exec failure cannot safely retry a native order or duplicate its damage")
advance(1.2)
assert(#removed==4 and pool.snapshot().idle==1,
    "async failure keeps the pool deadline while both legacy fallbacks retire once")
hide_throw=true;hit(h);damage_count(4)
assert(#casts==3 and #created==5 and #removed==4 and pool.snapshot().busy==1,
    "post-queue hide failure keeps the same task/deadline without duplicate native effect")
advance(1.2);assert(pool.snapshot().idle==1)
print("CASE noowner_configuration_async_order_and_postqueue_hide_throw PASS")

fresh();h=hero();enable();schedule_cast_throw=true
queue_hit(h);damage_count(1)
assert(#created==2 and #removed==1 and #casts==0 and pool.snapshot().total==0,
    "prequeue allocation failure must cancel its candidate deadline and fall back once")
flush_casts();assert(#casts==1 and casts[1].unit==created[2] and #created==2)
advance(1.01);assert(#removed==2 and created[1].remove_calls==1 and created[2].remove_calls==1)
print("CASE queued_cast_allocation_failure_precise_cleanup_and_legacy_fallback PASS")

fresh();h=hero();enable();queue_hit(h);damage_count(1)
local born=created[1]
local born_native=born:FindAbilityByName("legion_commander_overwhelming_odds")
born:CastAbilityNoTarget(born_native,h.player)
ExecuteOrderFromTable({UnitIndex=born.id,AbilityIndex=born_native.id,
    OrderType=DOTA_UNIT_ORDER_CAST_NO_TARGET,Queue=false})
assert(#casts==0 and #order_attempts==2
    and order_attempts[1].ignored=="direct_no_effect" and order_attempts[2].ignored=="born_frame_order"
    and born.mana==315 and born_native:GetCooldownTimeRemaining()==0
    and not born.modifiers.modifier_legion_commander_overwhelming_odds,
    "the native boundary must model both separated ineffective APIs without hiding the queued order")
flush_casts()
assert(#casts==1 and #order_attempts==3 and born.mana==225
    and born_native:GetCooldownTimeRemaining()==18 and born.modifiers.modifier_legion_commander_overwhelming_odds)
damage_count(1)
print("CASE native_direct_and_birth_frame_Exec_ineffective_queued_Exec_accepted PASS")

for _,pooled in ipairs({false,true}) do
    for _,action in ipairs({"owner_death","owner_remove","owner_replace","caster_kill","service_reset"}) do
        fresh();h=hero();if pooled then enable() end
        queue_hit(h);damage_count(1)
        local candidate,queued=created[1],cast_timers[1]
        assert(#casts==0 and #order_attempts==0 and queued and queued.due==now+0.03)
        local successor
        if action=="owner_death" then
            h.life=false;bus.emit(events.ENGINE_ENTITY_KILLED,{victim=h})
        elseif action=="owner_remove" then
            bus.emit(events.HERO_REMOVED,{unit=h,player_id=h.player})
        elseif action=="owner_replace" then
            successor=hero(201,h.player)
            if not pooled then bus.emit(events.HERO_REMOVED,{unit=h,player_id=h.player}) end
            bus.emit(events.HERO_SUMMONED,{unit=successor,player_id=h.player})
        elseif action=="caster_kill" then
            candidate.life=false;bus.emit(events.ENGINE_ENTITY_KILLED,{victim=candidate})
        else
            bus.reset();handlers();service.init()
        end
        assert(candidate.null and candidate.remove_calls==1 and #remove_attempts==1
            and remove_attempts[1]==candidate and pool.snapshot().total==0
            and canceled_tasks[queued.id],"public lifecycle must cancel and retire its exact queued caster: "..action)
        queued.callback();flush_casts()
        assert(#casts==0 and #order_attempts==0 and #remove_attempts==1,
            "canceled queued lifecycle cannot later submit/remove again: "..action)
        successor=successor or hero(201,h.player)
        if pooled then enable() end
        queue_hit(successor);damage_count(2)
        local requests_before=canonical_requests
        queued.callback()
        assert(canonical_requests==requests_before and #order_attempts==0,
            "old canceled callback must not issue or query the new lifecycle")
        flush_casts()
        assert(#casts==1 and #order_attempts==1 and casts[1].unit==created[2])
        queued.callback();assert(#order_attempts==1 and candidate.remove_calls==1)
        print("CASE queued_"..(pooled and "pool" or "legacy").."_"..action.."_cancel_and_successor_guard PASS")
    end
end

for _,context in ipairs({"owner_dead_without_event","owner_removed_without_event","caster_removed_without_event",
    "guard_replaced","bus_reset","canonical_missing_after_queue","canonical_replaced_without_event"}) do
    fresh();h=hero();enable();queue_hit(h);damage_count(1)
    local candidate,queued=created[1],cast_timers[1]
    local requests_before=canonical_requests
    if context=="owner_dead_without_event" then h.life=false
    elseif context=="owner_removed_without_event" then h.null=true;h.life=false
    elseif context=="caster_removed_without_event" then candidate.null=true;candidate.life=false
    elseif context=="guard_replaced" then _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=mode}
    elseif context=="bus_reset" then bus.reset();handlers()
    elseif context=="canonical_missing_after_queue" then hero_by_player[h.player]=nil
    else hero(201,h.player) end
    flush_casts()
    assert(#casts==0 and #order_attempts==0,"revoked context must not submit a queued native order: "..context)
    if context~="canonical_replaced_without_event" and context~="canonical_missing_after_queue" then
        assert(canonical_requests==requests_before,"revoked old context must not call a new/current bus handler: "..context)
    end
    queued.callback();assert(#order_attempts==0)
    advance(0.26)
    assert(pool.snapshot().total==0,"scope sweep must release revoked owned pool entries: "..context)
    assert(candidate.null and #remove_attempts==(context=="caster_removed_without_event" and 0 or 1),
        "scope sweep must retire exactly its valid owned caster, not an already removed handle")
    queued.callback();assert(#order_attempts==0)
    print("CASE queued_pool_"..context.."_noorder_and_owned_cleanup PASS")
end

fresh();h=hero();enable();hero_by_player[h.player]=nil
queue_hit(h);damage_count(1)
assert(#created==1 and #removed==0 and pool.snapshot().total==0
    and pool.snapshot().counters.created==0 and not created[1].survival_blademaster_q_pool_entry,
    "unknown canonical hero must decline pool admission and retain one legacy fallback")
flush_casts();assert(#casts==1 and #order_attempts==1 and casts[1].unit==created[1])
advance(1.01);assert(#removed==1 and created[1].remove_calls==1)
print("CASE queued_missing_canonical_admission_legacy_fallback PASS")

fresh();h=hero();enable();queue_hit(h);damage_count(1)
local lease_caster,old_cast,old_return=created[1],cast_timers[1],timers[1]
advance(0.01);old_return()
assert(pool.snapshot().idle==1 and canceled_tasks[old_cast.id] and #order_attempts==0)
queue_hit(h);damage_count(2)
local new_cast=cast_timers[2]
assert(#created==1 and pool.snapshot().busy==1 and new_cast.id~=old_cast.id)
old_cast.callback();old_return()
assert(#order_attempts==0 and not canceled_tasks[new_cast.id]
    and pool.snapshot().busy==1,"old lease callbacks must neither cast nor cancel/return the new lease")
flush_casts();assert(#casts==1 and #order_attempts==1 and casts[1].unit==lease_caster)
old_cast.callback();assert(#order_attempts==1,"late old cast cannot issue against the reused same native handle")
advance(1.01);assert(pool.snapshot().idle==1)
print("CASE queued_old_lease_cast_and_return_do_not_touch_new_lease PASS")

fresh();h=hero();enable();queue_hit(h);damage_count(1)
local disabled_cast=cast_timers[1]
pool.set_probe(false)
disabled_cast.callback();flush_casts()
assert(#order_attempts==0 and #removed==1 and pool.snapshot().total==0 and canceled_tasks[disabled_cast.id])
print("CASE queued_pool_disable_precise_cancellation PASS")

for _,pooled in ipairs({false,true}) do
    fresh();h=hero();if pooled then enable() end
    queue_hit(h);damage_count(1)
    local old_caster,old_cast=created[1],cast_timers[1]
    mode={};_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=mode}
    local requests_before=canonical_requests
    old_cast.callback();flush_casts()
    assert(#order_attempts==0 and canonical_requests==requests_before and #remove_attempts==0,
        "valid old-world handles must never issue/query/remove in the new world")
    -- A fresh map invalidates engine legacy handles; pool already has a world-safe reset.
    if not pooled then old_caster.null=true;old_caster.life=false end
    bus.reset();scheduler.clear();handlers();service.init()
    local successor=hero(201,h.player)
    if pooled then enable() end
    next_id=old_caster.id-1 -- Deliberately recycle the native entity/ability indices.
    queue_hit(successor);damage_count(2)
    assert(created[2].id==old_caster.id and created[2]~=old_caster)
    requests_before=canonical_requests;old_cast.callback()
    assert(#order_attempts==0 and canonical_requests==requests_before)
    flush_casts();assert(#casts==1 and #order_attempts==1 and casts[1].unit==created[2])
    old_cast.callback();assert(#order_attempts==1 and #remove_attempts==0,
        "cross-world old callback cannot cast on a new lease with recycled native indices")
    print("CASE queued_"..(pooled and "pool" or "legacy").."_crossworld_recycled_indices_guard PASS")
end

fresh();h=hero();enable();hit(h);hit(h);advance(1.2);hit(h)
local before=#removed
bus.reset();scheduler.clear();handlers();service.init()
assert(#removed==before+2 and pool.snapshot().total==0 and not pool.snapshot().enabled,
    "same-world init retires every idle/busy unit before dropping ownership")
for _,callback in ipairs(timers) do callback() end
assert(#removed==before+2,"old bus/timers do not remove twice")
print("CASE init_and_bus_generation PASS")

fresh();h=hero();enable();hit(h);advance(1.2)
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=mode}
hit(h);damage_count(2)
assert(#removed==1 and #casts==2 and pool.snapshot().total==0,
    "guard replacement retires candidate and uses legacy")
advance(0.25);assert(not pool.snapshot().enabled)
print("CASE guard_change_fallback PASS")

fresh();h=hero();enable();hit(h)
local old_world_removed=#removed
mode={}
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=mode}
bus.reset();scheduler.clear();handlers();service.init()
assert(#removed==old_world_removed,"new world must not issue native removal for old handles")
assert(pool.snapshot().total==0 and not pool.snapshot().enabled)
print("CASE old_world_handle_isolation PASS")

fresh();h=hero();queue_hit(h);damage_count(1)
local hardened=created[1]
assert(hardened.birth_owner==player_owner(h.player) and hardened:GetOwner()==h
    and hardened.owner_after_controllable==hardened.birth_owner,
    "legacy preparation must bind the exact hero after native Player-owned birth")
assert(table.concat(hardened.legacy_prepare_trace,",")=="SetOwner,SetIdleAcquire,SetAcquisitionRange,Stop"
    and hardened.acquire==false and hardened.acquire_range==0 and not hardened.pending_order
    and hardened.stopped==1 and #order_attempts==0,
    "legacy must clear inherited/startup acquisition before the queued command settles")
-- Inject a competing native order into the boundary model. It is a causal
-- fixture, not a claim that this is the proven reason for every real OFF miss.
hardened.pending_order="competing_native_order"
local competition_native=hardened:FindAbilityByName("legion_commander_overwhelming_odds")
advance(0.031)
assert(#casts==0 and #order_attempts==1 and order_attempts[1].ignored=="autonomous_order_competition",
    "the native boundary must not turn a competing discarded order into a successful cast")
hardened:Stop()
ExecuteOrderFromTable({UnitIndex=hardened.id,AbilityIndex=competition_native.id,
    OrderType=DOTA_UNIT_ORDER_CAST_NO_TARGET,Queue=false})
assert(#casts==1 and #order_attempts==2 and hardened.mana==225
    and competition_native:GetCooldownTimeRemaining()==18)
damage_count(1)
advance(1.01);assert(#removed==1 and remove_attempts[1]==hardened)
print("CASE legacy_Player_birth_preparation_and_competing_order_model PASS")

for _,method in ipairs({"SetOwner","SetIdleAcquire","SetAcquisitionRange","Stop"}) do
    for _,stage in ipairs({"before","after"}) do
        fresh();h=hero()
        local task_count_before=scheduler.task_count()
        legacy_prepare_fault={method=method,stage=stage}
        queue_hit(h);damage_count(1)
        local failed=created[1]
        assert(#created==1 and #removed==1 and #remove_attempts==1
            and remove_attempts[1]==failed and failed.remove_calls==1 and failed.null,
            "legacy prepare failure must remove exactly its own newly created caster")
        assert(not h.null and h:GetOwner()==player_owner(h.player)
            and #casts==0 and #order_attempts==0 and #cast_timers==0
            and scheduler.task_count()==task_count_before and pool.snapshot().total==0,
            "legacy prepare failure must not touch hero/Player, queue a task, or suppress copied damage")
        assert(failed:FindAbilityByName("legion_commander_overwhelming_odds")==nil,
            "failed legacy configuration must retire before native ability preparation")
        if method=="SetOwner" and stage=="before" then
            assert(failed:GetOwner()==failed.birth_owner)
        else assert(failed:GetOwner()==h,"owned caster removal remains precise after ownership side effects") end
        advance(1.1)
        assert(#remove_attempts==1 and failed.remove_calls==1 and #casts==0,
            "failed prepare must leave no late task that removes or casts again")
        queue_hit(h);damage_count(2)
        assert(#created==2 and #removed==1 and #casts==0)
        flush_casts()
        assert(#casts==1 and #order_attempts==1 and casts[1].unit==created[2]
            and created[2]:GetOwner()==h and created[2].acquire==false
            and created[2].acquire_range==0 and not created[2].pending_order,
            "one failing legacy API must not prevent the next correctly prepared public Q")
        advance(1.01)
        assert(#removed==2 and #remove_attempts==2 and remove_attempts[2]==created[2]
            and created[2].remove_calls==1 and failed.remove_calls==1)
        print("CASE legacy_prepare_"..method.."_"..stage.."_failure_exact_cleanup_same_damage PASS")
    end
end

fresh();h=hero();enable();hit(h);advance(1.2)
e_active=true
bus.emit(events.HERO_MAIN_ATTACK_LANDED,{attacker=h,target=enemy,player_id=2,is_main_attack=true})
assert(#created==2 and casts[#casts].e==true and created[2].name=="npc_dota_hero_juggernaut")
assert(created[2]:GetOwner()==created[2].birth_owner and not created[2].set_owner_calls
    and created[2].acquire==true and created[2].acquire_range==600 and not created[2].stopped,
    "new Q-only legacy preparation must not modify the original E caster configuration")
assert(pool.snapshot().total==1,"E caster never enters Q pool")
bus.emit(events.PLAYER_DISCONNECTED,{player_id=2})
assert(pool.snapshot().total==0)
print("CASE E_unchanged_and_disconnect PASS")
print("BLADEMASTER_Q_CASTER_POOL_PASS: full service/public events and real scheduler; default OFF; 40 concurrent queued Q orders; unchanged immediate damage; Player/native child ABI; .03 NO_TARGET Exec; cancel/context/old lease/world guards; native scene/render not simulated")
