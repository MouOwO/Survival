-- Offline scheduling contract, not evidence about native pool behavior.
package.path='scripts/vscripts/?.lua;'..package.path
DOTA_TEAM_GOODGUYS=2;DOTA_TEAM_BADGUYS=3
DOTA_UNIT_CAP_NO_ATTACK=0;DOTA_UNIT_CAP_MELEE_ATTACK=1;DOTA_UNIT_CAP_RANGED_ATTACK=2
DOTA_UNIT_CAP_MOVE_GROUND=1;DOTA_UNIT_ORDER_ATTACK_TARGET=4;LUA_MODIFIER_MOTION_NONE=0
function IsServer() return true end
function IsInToolsMode() return true end
function Vector(x,y,z) return {x=x,y=y,z=z} end
function GetGroundHeight() return 0 end
function LinkLuaModifier() end
local clock,callback,actors,targets,removed,paused,next_id
local function reset()
    clock=0;callback=nil;actors={};targets={};removed={};paused=false;next_id=0
end
local mode={}
function mode:SetContextThink(_,fn) callback=fn end
GameRules={GetGameTime=function() return clock end,GetGameModeEntity=function() return mode end}
function PauseGame(value) paused=value end
function ExecuteOrderFromTable(order)
    assert(order.OrderType==DOTA_UNIT_ORDER_ATTACK_TARGET and order.Queue==false,'must issue ordinary native attacks')
end
local forbidden=function() error('stress must not invoke business or synthetic attacks') end
PerformAttack=forbidden;CreateHTTPRequest=forbidden;CreateHTTPRequestScriptVM=forbidden
FindUnitsInRadius=forbidden;ApplyDamage=forbidden;PlayerResource=setmetatable({},{__index=function() return forbidden end})
function CreateUnitByName(name,position,_,_,_,team)
    next_id=next_id+1
    local unit={id=next_id,name=name,position=position,team=team,removed=false,alive=true,stops=0,interrupts=0}
    function unit:entindex() return self.id end
    function unit:IsNull() return self.removed end
    function unit:IsAlive() return self.alive end
    function unit:IsInvulnerable() return false end
    function unit:RemoveModifierByName(name) assert(name=='modifier_invulnerable') end
    function unit:GetAttackCapability() return self.capability end
    function unit:SetAttackCapability(value) self.capability=value end
    function unit:SetHullRadius(value) assert(value==32);self.hull=value end
    function unit:SetMoveCapability(value) assert(value==DOTA_UNIT_CAP_MOVE_GROUND) end
    function unit:SetAcquisitionRange(value) assert(value==0) end
    function unit:SetForceAttackTarget(target) self.force=target end
    function unit:Stop() self.stops=self.stops+1 end
    function unit:Interrupt() self.interrupts=self.interrupts+1 end
    for _,method in ipairs({'SetMaxHealth','SetHealth','SetBaseHealthRegen','SetMinimumGoldBounty',
        'SetMaximumGoldBounty','SetDeathXP','SetBaseDamageMin','SetBaseDamageMax','SetBaseAttackTime'}) do
        unit[method]=function() end
    end
    function unit:AddNewModifier(caster,_,modifier_name)
        assert(caster==self and modifier_name=='modifier_wall_native_attack_record_audit')
        local modifier={}
        function modifier:SetStackCount(value) assert(value==1 or value==2);self.stack=value end
        function modifier:ForceRefresh() end
        function modifier:Destroy() self.destroyed=true end
        return modifier
    end
    if name=='building_wall' then targets[#targets+1]=unit else actors[#actors+1]=unit end
    return unit
end
function UTIL_Remove(unit)
    assert(not unit.removed,'cannot delete the same native fixture twice')
    if unit.name~='building_wall' then
        assert(unit.survival_native_attack_record_lifecycle==nil,'observer must detach only after all records drain')
        assert(unit.force==nil and unit.stops==1 and unit.interrupts==1,'delete must follow native stop/clear/interrupt')
    else
        for _,actor in ipairs(actors) do
            if not actor.removed then assert(actor.id>unit.id,'target must be removed after its own native attackers') end
        end
    end
    unit.removed=true;removed[#removed+1]=unit
end
local function pulse(seconds)
    clock=clock+(seconds or .03)
    local fn=callback
    assert(fn,'native context think must remain scheduled')
    local delay=fn()
    if delay==nil and callback==fn then callback=nil end
end
local function event(actor,record,destroy)
    local row=assert(actor.survival_native_attack_record_lifecycle,'observer required')
    row.owner[destroy and 'on_record_destroy' or 'on_record'](row.owner,actor,{attacker=actor,record=record})
end
local function fresh()
    reset();package.loaded['tests/wall_native_attack_record_stress']=nil
    return require('tests/wall_native_attack_record_stress')
end
local cases=0
local function test(name,fn) cases=cases+1;local ok,reason=pcall(fn);assert(ok,name..': '..tostring(reason)) end
test('isolated explicit guard prevents accidental live scene use',function()
    local p=fresh();SURVIVAL_SOLID_ISOLATED_RECORD_TEST=nil
    assert(not pcall(p.start,{origin=Vector(0,0,0)}),'isolated opt-in is mandatory')
    assert(#actors==0 and #targets==0 and not p.is_active(),'guard cannot spawn actors')
end)
test('real record events drive cross batch quiet cleanup and balanced final result',function()
    local p=fresh();SURVIVAL_SOLID_ISOLATED_RECORD_TEST=true
    p.start({origin=Vector(0,0,0),target_records=8,population=4,records_per_batch=4})
    pulse();pulse();assert(#actors==4 and #targets==1)
    for index=1,4 do event(actors[index],index) end
    pulse();assert(p.snapshot().phase=='draining' and #removed==0)
    for index=1,4 do event(actors[index],index,true) end
    pulse(.09);assert(#removed==0,'last destroy must receive full quiet and drain windows')
    pulse(.08);assert(#removed==5 and p.is_active(),'batch cleans only after native event drain')
    pulse();pulse();assert(#actors==8 and #targets==2,'only a clean previous batch may spawn another')
    for index=5,8 do event(actors[index],index) end
    pulse();for index=5,8 do event(actors[index],index,true) end
    pulse(.16)
    local value=assert(p.last_result)
    assert(not p.is_active() and value.ok and value.created==8 and value.destroyed==8 and value.pending==0)
    assert(value.batches==2 and value.ranged_pending_batches==2 and #value.completed_batches==2)
    assert(#removed==10 and not paused)
end)
test('pending deadline retains attackers and target and stops later batches',function()
    local p=fresh();SURVIVAL_SOLID_ISOLATED_RECORD_TEST=true
    p.start({origin=Vector(0,0,0),target_records=8,population=4,records_per_batch=4,attack_record_timeout=.2})
    pulse();pulse();for index=1,4 do event(actors[index],index) end
    pulse();pulse(.21)
    local value=assert(p.last_result)
    assert(p.is_active() and value.cleanup_blocked and not value.ok and value.pending==4)
    assert(paused and #removed==0 and #actors==4 and #targets==1 and callback==nil)
    assert(not pcall(p.start,{origin=Vector(0,0,0)}),'retained pending state must block a new campaign')
    for index=1,4 do event(actors[index],index,true) end
    p.retry_cleanup();pulse(.11)
    assert(not p.is_active() and not p.last_result.ok and #removed==5,'late drain may clean but never pass')
end)
test('empty run never invents native records and external stop fails safely',function()
    local p=fresh();SURVIVAL_SOLID_ISOLATED_RECORD_TEST=true
    p.start({origin=Vector(0,0,0),target_records=8,population=4,records_per_batch=4})
    pulse();pulse();assert(p.snapshot().created==0 and p.snapshot().destroyed==0)
    p.stop('smoke_stop');pulse(.16)
    assert(not p.is_active() and not p.last_result.ok and p.last_result.created==0 and #removed==5)
end)
print('WALL_NATIVE_ATTACK_RECORD_STRESS_CONTRACT_PASS cases='..cases
    ..' native_pool_evidence=false records=event_only batches=drain_gated timeout=retain_and_pause business=forbidden')
