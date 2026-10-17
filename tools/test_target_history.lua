-- Production regression: real services/EventBus/Scheduler; native fixtures.
-- Native entities/rendering are fixtures. EventBus and Scheduler are real.
package.path = "scripts/vscripts/?.lua;" .. package.path
local clock, world, particle_serial = 0, {}, 0
GameRules = {
    GetGameTime = function() return clock end,
    GetGameModeEntity = function() return world end,
}
local vector = {}; vector.__index = vector
function Vector(x,y,z) return setmetatable({x=x,y=y,z=z or 0},vector) end
vector.__add = function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
vector.__sub = function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
vector.__mul = function(a,b) return Vector(a.x*b,a.y*b,a.z*b) end
function vector:Length2D() return math.sqrt(self.x*self.x+self.y*self.y) end
function vector:Normalized() return self*(1/self:Length2D()) end
function IsServer() return true end
function RollPercentage() return true end
PATTACH_WORLDORIGIN, FIND_ANY_ORDER, FIND_CLOSEST = 0,0,0
DOTA_UNIT_TARGET_TEAM_ENEMY, DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC = 2,4,8
DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES, DAMAGE_TYPE_PURE = 16,4
GetGroundPosition = function(position) return position end
ParticleManager = {
    CreateParticle = function() particle_serial=particle_serial+1;return particle_serial end,
    SetParticleControl = function() end,
    SetParticleControlForward = function() end,
    DestroyParticle = function() end,
    ReleaseParticleIndex = function() end,
}
package.loaded["systems/combat_effect_visibility"] = {manager=function()return ParticleManager end}
package.loaded["systems/hero_cosmetic_service"] = {clear=function()end,sync_appearance=function()end}
package.loaded["systems/gameplay_phase_guard"] = {post_clear_frozen=function()return false end}
package.loaded["core/sound_service"] = {play=function()end}
local bus = require("core/event_bus")
local events = require("core/events")
local combat_events = require("combat/combat_events")
local scheduler = require("core/scheduler")
local monkey = require("systems/monkey_king_exclusive_service")
local shadow = require("systems/hero_exclusive_passive_service")
local definition = require("config/hero_passive_skill_definitions").by_id.skill_shadow_fiend_raze
local heroes, candidates, deals, groups, deal_handler
local assertions, cases = 0,0
local function check(ok, message)
    assertions=assertions+1
    assert(ok, message)
end
local function count_keys(value)
    local n=0;for _ in pairs(value or {}) do n=n+1 end;return n
end
local function near(actual, expected) return math.abs(actual-expected)<0.0000001 end
local function upvalue(fn, wanted)
    local index=1
    while true do
        local name,value=debug.getupvalue(fn,index)
        if not name then error("production upvalue absent: "..wanted) end
        if name==wanted then return value end
        index=index+1
    end
end
local function unit(id, player_id, x)
    local value={id=id,player_id=player_id or -1,team=3,position=Vector(x or 200,0,0),maximum=10000}
    function value:IsNull() return self.removed==true end
    function value:IsAlive() return not self.removed and not self.dead end
    function value:entindex() return self.id end
    function value:GetAbsOrigin() return self.position end
    function value:GetForwardVector() return Vector(1,0,0) end
    function value:GetHullRadius() return 0 end
    function value:GetTeamNumber() return self.team end
    function value:GetMaxHealth() return self.maximum end
    function value:GetPlayerOwnerID() return self.player_id end
    function value:FindAbilityByName(name) return {name=name} end
    return value
end
local function reset()
    clock=0;heroes={};candidates={};deals={};groups={};deal_handler=nil
    scheduler.clear();bus.reset()
    for pid=0,1 do
        local hero=unit(1+pid,pid,0);hero.team=2;hero.survival_hero_id="hero_monkey_king"
        heroes[pid]=hero
    end
    FindUnitsInRadius=function() return candidates end
    bus.handle_request(events.HERO_SUMMON_GET_REQUEST,function(p)return {unit=heroes[p.player_id]} end)
    bus.handle_request(events.HERO_SKILL_STATE_GET_REQUEST,function()
        return {snapshot={skills={{skill_id="skill_monkey_king_exclusive",level=1}}}}
    end)
    bus.handle_request(events.HERO_COMBAT_STATS_GET_REQUEST,function()
        return {snapshot={strength=10,agility=20,intellect=30}}
    end)
    bus.handle_request(combat_events.DEAL_REQUEST,function(p)
        deals[#deals+1]=p
        return deal_handler and deal_handler(p) or {success=true}
    end)
    monkey.init()
    shadow.init({deal_group=function(context,targets,multiplier)
        groups[#groups+1]={context=context,targets=targets,multiplier=multiplier}
    end})
end
local function advance(delta)
    clock=clock+delta;scheduler.think()
end
local function q(target, pid)
    pid=pid or 0
    local before=count_keys(monkey._test.impacts())
    bus.emit(events.HERO_MAIN_ATTACK_LANDED,{
        player_id=pid,attacker=heroes[pid],target=target,is_main_attack=true,
    })
    check(count_keys(monkey._test.impacts())==before+1,"real main-attack event creates one impact")
    local before_deals=#deals
    advance(0.279)
    check(#deals==before_deals,"Q history is updated only at the real staff-fall deadline")
    advance(0.002)
    check(count_keys(monkey._test.impacts())==before,"scheduler consumes exact impact")
    return deals[#deals]
end
local function raze(target, attacker)
    local ok=shadow.runners.skill_shadow_fiend_raze({
        player_id=0,attacker=attacker or heroes[0],target=target,level=1,
        skill_id=definition.skill_id,attack_id="characterization",
    },definition)
    check(ok==true,"actual production shadow runner accepts valid primary target")
    return groups[#groups]
end
local function run(name, callback)
    reset();callback();cases=cases+1;print("CASE_PASS: "..name)
end

run("MK same living handle keeps the shared three-hit maximum-health allowance",function()
    local target=unit(100);candidates={target}
    for i=1,4 do check(q(target).base_damage==(i<=3 and 2800 or 1800),"same-unit allowance must stay 3") end
    check(monkey._test.health_hits()[0][target]==3,"limit stays recorded by exact handle")
end)
run("MK valid corpse aims the Q while living neighbours alone consume allowance",function()
    local corpse,neighbour=unit(101),unit(102)
    candidates={corpse};for _=1,3 do q(corpse) end
    corpse.dead=true
    bus.emit(events.ENGINE_ENTITY_KILLED,{victim=corpse,victim_entindex=corpse.id})
    candidates={corpse,neighbour}
    local result=q(corpse)
    check(result.victim==neighbour and result.base_damage==2800,"dead primary still aims line damage")
    check(monkey._test.health_hits()[0][corpse]==3,"death does not clear original target allowance")
    corpse.dead=false;candidates={corpse}
    check(q(corpse).base_damage==1800,"same handle revival retains used allowance")
end)
run("MK new target reusing an index receives its own full health-hit allowance",function()
    local old=unit(103);candidates={old};for _=1,3 do q(old) end
    old.removed=true
    local replacement=unit(103);candidates={replacement}
    check(old~=replacement and q(replacement).base_damage==2800,"new target must receive its own first health-hit slot")
end)
run("MK no TTL: living and dead-valid histories survive long elapsed time",function()
    local target=unit(104);candidates={target};for _=1,3 do q(target) end
    advance(3600)
    check(q(target).base_damage==1800,"living target cannot regain health-hit allowance by TTL")
    target.dead=true;advance(3600);target.dead=false
    check(q(target).base_damage==1800,"valid corpse and revival preserve the original count")
end)
run("MK failed damage rolls back only the reserved health-hit increment",function()
    local target=unit(105);candidates={target};deal_handler=function()return {success=false} end
    check(q(target).base_damage==2800 and monkey._test.health_hits()[0][target]==0,"failure restores zero count")
    deal_handler=nil
    check(q(target).base_damage==2800 and monkey._test.health_hits()[0][target]==1,"next successful Q consumes first slot")
end)
run("MK 1000 removed targets are eventually reclaimed without death events",function()
    for id=2000,2999 do
        local target=unit(id);candidates={target};q(target);target.removed=true
    end
    candidates={};advance(3600)
    check(count_keys(monkey._test.health_hits()[0])==0,"invalid handles are reclaimed")
    check(upvalue(monkey.init,"q_health_history"):snapshot().task==nil,"empty Q-history sweep stops")
end)
run("MK exact player removal and same-world init preserve current lifecycle boundaries",function()
    local target=unit(106);candidates={target};q(target,0);q(target,1)
    bus.emit(events.HERO_REMOVED,{player_id=0,unit=heroes[0]})
    check(monkey._test.health_hits()[0]==nil and monkey._test.health_hits()[1][target]==1,"only removed player's history is cleared")
    bus.reset();scheduler.clear();monkey.init()
    check(count_keys(monkey._test.health_hits())==0,"same-world init clears all player histories")
end)
run("MK failed damage plus synchronous owner removal does not reattach its detached bucket",function()
    local target=unit(107);candidates={target}
    deal_handler=function()
        bus.emit(events.HERO_REMOVED,{player_id=0,unit=heroes[0]})
        return {success=false}
    end
    q(target)
    check(monkey._test.health_hits()[0]==nil,"late rollback touches detached table only")
end)
run("Shadow death event preserves unexpired layers and valid corpse secondary proc",function()
    local target,neighbour=unit(108),unit(109);candidates={neighbour}
    check(near(raze(target).multiplier,27.5) and near(raze(target).multiplier,30),"original live sequence")
    target.dead=true
    bus.emit(events.ENGINE_ENTITY_KILLED,{victim=target,victim_entindex=target.id})
    local result=raze(target)
    check(near(result.multiplier,32.5) and result.targets[1]==neighbour,"valid corpse retains stack bonus and secondary victim")
    target.dead=false
    check(near(raze(target).multiplier,35),"same-handle revival preserves active layers")
end)
run("Shadow natural expiry equality and capped layer multipliers remain unchanged",function()
    local target=unit(110);candidates={target}
    for _,expected in ipairs({27.5,30,32.5,35,37.5,37.5}) do check(near(raze(target).multiplier,expected),"original cap sequence") end
    clock=2.999;check(near(raze(target).multiplier,37.5),"layers are live strictly before deadline")
    clock=3;check(near(raze(target).multiplier,30),"expiry equality removes old layers but retains the one added at 2.999")
    clock=6;check(near(raze(target).multiplier,27.5),"all expired layers reset next proc")
end)
run("Shadow new target reusing an index starts with one layer",function()
    local old=unit(111);candidates={old};raze(old);raze(old);old.removed=true
    local replacement=unit(111);candidates={replacement}
    check(old~=replacement and near(raze(replacement).multiplier,27.5),"new handle cannot inherit old layers")
    clock=3
    check(near(raze(replacement).multiplier,27.5),"natural expiry still resets the next proc")
end)
run("Shadow 1000 expired removed targets are reclaimed without further hits",function()
    for id=3000,3999 do
        local target=unit(id);candidates={target};raze(target);target.removed=true
    end
    candidates={};for _=1,16 do advance(0.25) end
    local history=upvalue(shadow._test.live_raze_layers,"shadow_raze_history")
    check(count_keys(history:all_values()[1])==0,"fixed-budget sweeps remove all 1000 invalid keys")
    check(history:snapshot().pending==0 and history:snapshot().task==nil,"empty shadow sweep stops")
end)
run("Shadow shared target history spans attackers and same-world init clears it",function()
    local target=unit(112);candidates={target}
    check(near(raze(target,heroes[0]).multiplier,27.5) and near(raze(target,heroes[1]).multiplier,30),"same target's layers remain shared")
    shadow.init({deal_group=function(context,targets,multiplier)
        groups[#groups+1]={context=context,targets=targets,multiplier=multiplier}
    end})
    check(near(raze(target).multiplier,27.5),"same-world init resets layers")
end)
local history_factory = require("core/target_history")
local function callback_of(store)
    local id=assert(store:snapshot().task)
    return assert(upvalue(scheduler.after,"tasks")[id]).callback
end
run("MK living allowance survives collector cycles without TTL or live-entry eviction",function()
    local target=unit(113);candidates={target};for _=1,3 do q(target) end
    for _=1,20 do advance(10) end
    check(monkey._test.health_hits()[0][target]==3,"idle sweeps cannot reset living count")
    check(q(target).base_damage==1800,"used allowance stays used")
end)
run("Shadow entirely expired living target is reclaimed without another hit",function()
    local target=unit(114);candidates={target};raze(target);raze(target)
    local history=upvalue(shadow._test.live_raze_layers,"shadow_raze_history")
    advance(3)
    check(history:all_values()[1][target]==nil and history:snapshot().task==nil,"expiry frees even living target after all layers end")
    check(near(raze(target).multiplier,27.5),"next proc equals original lazy-expiry behavior")
end)
run("Late old-target death and index-only death payload cannot erase replacement target",function()
    local old,replacement=unit(115),unit(115);candidates={old};q(old);raze(old);old.removed=true
    candidates={replacement};q(replacement);raze(replacement)
    bus.emit(events.ENGINE_ENTITY_KILLED,{victim=old,victim_entindex=115})
    bus.emit(events.ENGINE_ENTITY_KILLED,{victim_entindex=115})
    check(monkey._test.health_hits()[0][replacement]==1,"old death cannot clear new handle count")
    check(near(raze(replacement).multiplier,30),"old death cannot clear new handle's active layer")
end)
run("Source owner removal plus successor bucket rejects old sweep callback",function()
    local old=unit(116);candidates={old};q(old)
    local history=upvalue(monkey.init,"q_health_history")
    local old_callback=callback_of(history)
    bus.emit(events.HERO_REMOVED,{player_id=0,unit=heroes[0]})
    old.removed=true
    local replacement=unit(116);candidates={replacement};q(replacement)
    old_callback()
    check(monkey._test.health_hits()[0][replacement]==1,"retired player bucket cannot erase successor bucket")
    check(history:snapshot().pending==1,"successor stays registered")
end)
run("Source same-world init rejects old Q and shadow collector callbacks",function()
    local old=unit(117);candidates={old};q(old);raze(old)
    local old_q=callback_of(upvalue(monkey.init,"q_health_history"))
    local old_shadow=callback_of(upvalue(shadow._test.live_raze_layers,"shadow_raze_history"))
    reset()
    local replacement=unit(117);candidates={replacement};q(replacement);raze(replacement)
    old_q();old_shadow()
    check(monkey._test.health_hits()[0][replacement]==1,"old init timer cannot erase new Q count")
    check(near(raze(replacement).multiplier,30),"old init timer cannot erase new shadow layers")
end)
run("Source world change before service init rebinds histories and rejects old timers",function()
    local old=unit(118);candidates={old};q(old);raze(old)
    local old_q=callback_of(upvalue(monkey.init,"q_health_history"))
    local old_shadow=callback_of(upvalue(shadow._test.live_raze_layers,"shadow_raze_history"))
    world={};old.removed=true
    local replacement=unit(118);candidates={replacement}
    check(q(replacement).base_damage==2800 and near(raze(replacement).multiplier,27.5),"new world starts fresh exact identities")
    old_q();old_shadow()
    check(monkey._test.health_hits()[0][replacement]==1,"old world callback cannot clear new world entry")
    check(near(raze(replacement).multiplier,30),"old world callback cannot clear new world layers")
end)
run("Collector budget visits each queued record at most once per tick and stops empty",function()
    local store=history_factory.new({budget=2,interval=0.25})
    local bucket=store:bucket(0)
    for id=120,124 do local target=unit(id);target.removed=true;bucket[target]=1;store:track(0,target) end
    advance(0.25)
    check(count_keys(bucket)==3 and store:snapshot().pending==3,"first tick is exactly two records")
    advance(0.25)
    check(count_keys(bucket)==1 and store:snapshot().pending==1,"second tick is exactly two records")
    advance(0.25)
    check(count_keys(bucket)==0 and store:snapshot().pending==0 and store:snapshot().task==nil,"third tick finishes and stops")
end)
run("Strong keys retain live handle through GC and release it after native removal",function()
    local store=history_factory.new({budget=64})
    local bucket=store:bucket(0)
    local target=unit(125)
    local weak=setmetatable({target},{__mode="v"})
    bucket[target]=3;store:track(0,target);target=nil
    collectgarbage("collect");collectgarbage("collect")
    check(weak[1]~=nil,"live history must not disappear under Lua GC")
    advance(0.25)
    check(bucket[weak[1]]==3,"live count is retained after collection")
    weak[1].removed=true;advance(0.25)
    collectgarbage("collect");collectgarbage("collect")
    check(weak[1]==nil and count_keys(bucket)==0,"retired history drops all its strong handle references")
end)
run("Bus generation replacement rejects old callbacks without touching successor data",function()
    local store=history_factory.new()
    local target=unit(126);local old=store:bucket(0);old[target]=3;store:track(0,target)
    local old_callback=callback_of(store)
    bus.reset()
    local fresh=store:bucket(0);fresh[target]=1;store:track(0,target)
    old_callback()
    check(old~=fresh and fresh[target]==1 and store:all_values()[0]==fresh,"old bus cannot mutate new bucket")
end)
run("Clear scope detaches ownership first and drains old nodes under fixed budget",function()
    local store=history_factory.new({budget=2})
    local old=store:bucket(0)
    for id=127,131 do local target=unit(id);old[target]=3;store:track(0,target) end
    store:clear_scope(0)
    check(store:all_values()[0]==nil and store:snapshot().pending==5,"ownership is removed before draining")
    local fresh=store:bucket(0);local target=unit(127);fresh[target]=1;store:track(0,target)
    advance(0.25)
    check(store:snapshot().pending==4 and fresh[target]==1,"old nodes drain two at a time and successor is untouched")
    advance(0.25);advance(0.25)
    check(store:snapshot().pending==1 and fresh[target]==1,"only valid successor remains registered")
end)
run("Reentrant refresh during IsNull cannot lose registration or delete new layer array",function()
    local store=history_factory.new({expired=function(layers,current)return layers[1]<=current end})
    local bucket=store:bucket(0);local target=unit(132);bucket[target]={0};store:track(0,target)
    local refreshed=false
    function target:IsNull()
        if not refreshed then refreshed=true;bucket[target]={100};store:track(0,self) end
        return false
    end
    advance(0.25)
    check(bucket[target][1]==100 and store:snapshot().pending==1,"successor layers remain registered")
    advance(100)
    check(bucket[target]==nil and store:snapshot().task==nil,"refreshed entry is eventually reclaimable")
end)
run("Reentrant reset during native validation cannot clear replacement store entries",function()
    local store=history_factory.new();local bucket=store:bucket(0);local old=unit(133)
    bucket[old]=3;store:track(0,old);local old_callback=callback_of(store)
    local replacement=unit(133)
    function old:IsNull()
        store:reset();local fresh=store:bucket(0);fresh[replacement]=1;store:track(0,replacement)
        return true
    end
    advance(0.25);old_callback()
    check(store:all_values()[0][replacement]==1 and store:snapshot().pending==1,"old validation cannot erase new epoch")
end)
run("Late old epoch callback cannot collect a removed successor before its own deadline",function()
    local store=history_factory.new();local old=unit(135)
    store:bucket(0)[old]=3;store:track(0,old);local old_callback=callback_of(store)
    store:reset()
    local replacement=unit(135);replacement.removed=true
    local fresh=store:bucket(0);fresh[replacement]=1;store:track(0,replacement)
    local task=store:snapshot().task
    old_callback()
    check(fresh[replacement]==1 and store:snapshot().task==task,"stale callback cannot write or cancel successor ownership")
    advance(0.25)
    check(fresh[replacement]==nil and store:snapshot().task==nil,"current callback owns eventual reclamation")
end)
run("Reset reentered from the native clock cannot detach new epoch queue nodes",function()
    local store=history_factory.new();local old=unit(136)
    store:bucket(0)[old]=3;store:track(0,old);local callback=callback_of(store)
    local replacement=unit(136);replacement.removed=true
    local previous=GameRules.GetGameTime
    GameRules.GetGameTime=function()
        GameRules.GetGameTime=previous
        store:reset();local fresh=store:bucket(0);fresh[replacement]=1;store:track(0,replacement)
        return clock
    end
    callback()
    check(store:all_values()[0][replacement]==1 and store:snapshot().pending==1,"old clock boundary cannot detach successor queue")
    advance(0.25)
    check(store:all_values()[0][replacement]==nil and store:snapshot().task==nil,"successor queue remains reclaimable")
end)
run("Cleanup scheduling failure preserves combat and retries on the next hit",function()
    local target=unit(134);candidates={target}
    local original=scheduler.after;local failed=false
    scheduler.after=function(delay,callback,id)
        if id and id:find("monkey_q_history:",1,true) and not failed then
            failed=true;original(delay,callback,id);error("injected sweep allocation after scheduling")
        end
        return original(delay,callback,id)
    end
    local result=q(target);scheduler.after=original
    check(failed and result.base_damage==2800 and monkey._test.health_hits()[0][target]==1,"optional sweep failure preserves damage/count")
    check(q(target).base_damage==2800,"next hit retries safely without losing allowance")
    target.removed=true;advance(0.25)
    check(monkey._test.health_hits()[0][target]==nil,"retry reclaims the exact invalid entry")
end)
print(string.format("TARGET_HISTORY_REGRESSION_PASS: %d cases, %d assertions; exact handle identity, preserved corpse/revival/business semantics, bounded cleanup",cases,assertions))
