-- Explicit-handle Tools experiment contracts, entirely offline. Never Dota/TCP.
package.path='scripts/vscripts/?.lua;'..package.path
local KEY,CAP='SURVIVAL_MANUAL_NATIVE_ATTACK_CAP_AB','modifier_debug_attack_cap'
local tools,server=true,true
IsInToolsMode=function() return tools end
IsServer=function() return server end
local forbidden_calls=0
local function forbidden() forbidden_calls=forbidden_calls+1;error('forbidden scan/timer/setter/hook') end
FindUnitsInRadius,FindUnitsInLine,EntIndexToHScript=forbidden,forbidden,forbidden
Entities={FindAllByClassname=forbidden,FindAllByName=forbidden}
Convars={RegisterCommand=forbidden}
Timers={CreateTimer=forbidden}
local mode={maximum=7,minimum=0,native_minimum=0.2}
function mode:IsNull() return false end
function mode:GetMaximumAttackSpeed() return self.maximum end
function mode:GetMinimumAttackSpeed() return self.minimum end
mode.SetMaximumAttackSpeed,mode.SetMinimumAttackSpeed,mode.SetContextThink=forbidden,forbidden,forbidden
local current_mode=mode
GameRules={GetGameModeEntity=function() return current_mode end}
local mutations={destroy=0,add=0}
local deferred={}
local function engine_frame()
    -- The harness advances native destruction explicitly. The helper itself
    -- cannot schedule, poll, sleep, or drive this simulated engine frame.
    for _,value in ipairs(deferred) do
        for index,entry in ipairs(value.unit.mods) do
            if entry==value then table.remove(value.unit.mods,index);break end
        end
        value.null=true
    end
    deferred={}
end
local function modifier(unit)
    local result={unit=unit,caster=unit,duration=-1,stack=0,null=false}
    function result:IsNull() return self.null end
    function result:GetName() return CAP end
    function result:GetParent() return self.unit end
    function result:GetCaster() return self.caster end
    function result:GetAbility() return self.ability end
    function result:GetDuration() return self.duration end
    function result:GetStackCount() return self.stack end
    function result:Destroy()
        mutations.destroy=mutations.destroy+1
        if self.fail_before then error('destroy failed before removal') end
        if not self.unit.defer_list then
            for index,value in ipairs(self.unit.mods) do
                if value==self then table.remove(self.unit.mods,index);break end
            end
        end
        if self.unit.defer_destroy then deferred[#deferred+1]=self else self.null=true end
        if self.fail_after then error('destroy failed after removal') end
    end
    return result
end
local next_index=0
local function unit(speed)
    next_index=next_index+1
    local result={index=next_index,speed=speed or 1,bat=0.5,mods={},alive=true,null=false,adds=0}
    function result:IsNull() return self.null end
    function result:IsAlive() return self.alive end
    function result:entindex() return self.index end
    function result:FindAllModifiersByName(name)
        assert(name==CAP)
        local copy={};for i,value in ipairs(self.mods) do copy[i]=value end;return copy
    end
    function result:GetAttackSpeed(ignore_temporary)
        assert(ignore_temporary==false)
        if self.read_error then error('transient getter failure') end
        local value=self.speed
        if #self.mods==0 then value=math.max(mode.native_minimum,math.min(mode.maximum,value)) end
        if self.on_speed then self:on_speed() end
        return value
    end
    function result:GetAttacksPerSecond(ignore_temporary)
        assert(ignore_temporary==false)
        return self:GetAttackSpeed(false)/self.bat+(self.aps_delta or 0)
    end
    function result:GetDisplayAttackSpeed()
        return self:GetAttackSpeed(false)*100+(self.display_delta or 0)
    end
    function result:AddNewModifier(caster,ability,name,options)
        mutations.add=mutations.add+1;self.adds=self.adds+1
        assert(caster==self and ability==nil and name==CAP and next(options)==nil)
        assert(not self.null and #self.mods==0,'Only missing caps on the exact original may be added')
        if self.fail_add then error('transient add failure') end
        local added=modifier(self);self.mods[1]=added
        if self.fail_add_after then error('add succeeded before error') end
        return added
    end
    result.SetBaseAttackTime,result.SetAttackSpeed,result.SetBaseAttackSpeed=forbidden,forbidden,forbidden
    result.SetMaximumAttackSpeed,result.SetMinimumAttackSpeed=forbidden,forbidden
    result.mods[1]=modifier(result)
    return result
end
local function pristine(...)
    for _,value in ipairs({...}) do
        assert(#value.mods==1 and not value.mods[1].null and value.mods[1].caster==value)
    end
end
local function reset()
    _G[KEY]=nil;current_mode=mode;mode.maximum,mode.minimum=7,0
    mutations.destroy,mutations.add=0,0
    assert(#deferred==0,'Every deferred destruction is explicitly completed before the next case')
end
local ab=require('tests/manual_native_attack_cap_ab')
assert(ab.snapshot().phase=='not_started' and mutations.destroy==0 and mutations.add==0)
tools=false;assert(not ab.start({unit()}));tools,server=true,false
assert(not ab.start({unit()}));server=true

-- A four-owner 414-unit managed population is passed explicitly. No registry
-- enumeration or all-map API exists in this harness. All metrics remain equal.
local subjects={}
for index=1,414 do subjects[index]=unit(1+(index%9)/10) end
subjects[415]=subjects[1]
local original_caps={};for index=1,414 do original_caps[index]=subjects[index].mods[1] end
local ok,reason,proof=ab.start(subjects)
assert(ok and reason=='pending_removal' and not proof.ready and proof.unit_count==414 and proof.duplicate_count==1)
assert(proof.removal_requested_count==414 and proof.removed_count==0)
assert(mutations.destroy==414 and mutations.add==0)
assert(mode.maximum==7 and mode.minimum==0)
ok,reason,proof=ab.finalize()
assert(ok and reason=='ready' and proof.ready and proof.removed_count==414)
for _,row in ipairs(proof.rows) do
    assert(row.before.multiplier==row.after.multiplier and row.before.aps==row.after.aps
        and row.before.display==row.after.display)
end
assert(ab.verify())
proof.rows[1].before.multiplier=999
assert(ab.snapshot().rows[1].before.multiplier~=999,'Snapshots never expose mutable private records')
assert(not ab.start(subjects))
package.loaded['tests/manual_native_attack_cap_ab']=nil
ab=require('tests/manual_native_attack_cap_ab')
assert(ab.snapshot().ready and ab.verify(),'Module reload retains original handles')
assert(ab.restore())
assert(mutations.add==414 and ab.snapshot().phase=='restored' and not ab.snapshot().restore_pending)
for index=1,414 do
    pristine(subjects[index]);assert(subjects[index].mods[1]~=original_caps[index])
end
local adds=mutations.add
assert(ab.stop() and mutations.add==adds,'Restore is idempotent after completion')

-- Complete prevalidation before any mutation, including an unsafe last unit.
reset();local first,last=unit(),unit(7)
ok,reason=ab.start({first,last})
assert(not ok and reason=='unsafe_attack_speed' and mutations.destroy==0 and mutations.add==0)
pristine(first,last)
for _,list in ipairs({{}, {[1]=first,[3]=last}, {first,label='foreign'}, {[1025]=first}}) do
    assert(not ab.start(list) and mutations.destroy==0)
end
last.speed=1;last.read_error=true
assert(not ab.start({first,last}) and mutations.destroy==0)
last.read_error=false;last.speed=0/0
assert(not ab.start({first,last}) and mutations.destroy==0)
last.speed=1;last.mods[1].duration=20
assert(not ab.start({first,last}) and mutations.destroy==0)
last.mods[1].duration=-1;last.mods[1].stack=1
assert(not ab.start({first,last}) and mutations.destroy==0)
last.mods[1].stack=0;last.mods[1].caster=first
assert(not ab.start({first,last}) and mutations.destroy==0)
last.mods[1].caster=last;last.mods[2]=modifier(last)
assert(not ab.start({first,last}) and mutations.destroy==0)
last.mods[2]=nil;last.index=first.index
assert(not ab.start({first,last}) and mutations.destroy==0)

-- A destroy failure both before and after removal restores earlier subjects
-- and the failing subject when necessary; untouched later subjects stay exact.
for _,failure in ipairs({'fail_before','fail_after'}) do
    reset();local a,b,c=unit(),unit(),unit()
    b.mods[1][failure]=true;local untouched=c.mods[1]
    ok,reason,proof=ab.start({a,b,c})
    assert(not ok and reason=='cap_destroy_failed' and not proof.restore_pending)
    pristine(a,b,c);assert(c.mods[1]==untouched and c.adds==0)
    assert(mutations.add==(failure=='fail_after' and 2 or 1))
end

-- IgnoreAttackSpeedLimit also changes the lower clamp. Strict below-max alone
-- is insufficient: the after-removal metrics check catches this and rolls back.
reset();local slow=unit(0.1)
assert(ab.start({slow}))
ok,reason,proof=ab.finalize()
assert(not ok and reason=='attack_metrics_changed' and not proof.restore_pending)
pristine(slow);assert(slow:GetAttackSpeed(false)==0.1)

-- Transient getters can fail after actual removal. Every other original is
-- still restored; the unresolved record prevents another experiment and can retry.
reset();local a,b,c=unit(),unit(),unit()
assert(ab.start({a,b,c}));b.read_error=true
ok,reason,proof=ab.verify()
assert(not ok and reason=='attack_speed_unavailable' and proof.restore_pending and proof.restore_failures==1)
pristine(a,b,c)
assert(not ab.start({unit()}))
b.read_error=false;assert(ab.restore() and not ab.snapshot().restore_pending)

-- A failed add retains exact originals and retries only the missing cap.
reset();a,b,c=unit(),unit(),unit();assert(ab.start({a,b,c}));b.fail_add=true
ok,reason,proof=ab.restore()
assert(not ok and reason=='cap_restore_failed' and proof.restore_pending)
pristine(a,c);assert(#b.mods==0 and a.adds==1 and c.adds==1)
b.fail_add=false;assert(ab.restore());pristine(a,b,c)
assert(a.adds==1 and c.adds==1 and b.adds==2)

-- Native Destroy can remove list membership now but invalidate the exact old
-- handle only next frame. All 33 calls must be requested, without timing yet.
reset();local delayed={}
for index=1,33 do delayed[index]=unit();delayed[index].defer_destroy=true end
ok,reason,proof=ab.start(delayed)
assert(ok and reason=='pending_removal' and not proof.ready and mutations.destroy==33)
assert(proof.removal_requested_count==33 and proof.removed_count==0 and mutations.add==0)
ok,reason,proof=ab.verify()
assert(not ok and reason=='removal_pending' and proof.phase=='pending_removal' and not proof.ready)
assert(mutations.add==0 and #deferred==33)
engine_frame()
ok,reason,proof=ab.finalize()
assert(ok and reason=='ready' and proof.ready and proof.removed_count==33)
assert(ab.verify() and ab.restore())
for _,value in ipairs(delayed) do pristine(value) end
assert(mutations.add==33)

-- Some native implementations also keep the old modifier in the list until
-- next frame. Early rollback must not claim that scheduled old cap restored.
for _,keep_list in ipairs({false,true}) do
    reset();a,b=unit(),unit()
    a.defer_destroy,b.defer_destroy=true,true
    a.defer_list,b.defer_list=keep_list,keep_list
    assert(ab.start({a,b}))
    ok,reason,proof=ab.finalize()
    assert(not ok and reason=='removal_pending' and not proof.ready)
    ok,reason,proof=ab.restore()
    assert(not ok and reason=='removal_pending' and proof.restore_pending and mutations.add==0)
    assert(not ab.start({unit()}),'Pending native deletion retains ownership and blocks another experiment')
    engine_frame();assert(ab.restore());pristine(a,b)
    assert(mutations.add==2 and not ab.snapshot().restore_pending)
end

-- Error after scheduling destruction leaves earlier/failing handles pending,
-- but later untouched units are preserved. A later explicit restore recovers.
reset();a,b,c=unit(),unit(),unit()
a.defer_destroy,b.defer_destroy=true,true
b.mods[1].fail_after=true
ok,reason,proof=ab.start({a,b,c})
assert(not ok and reason=='cap_destroy_failed' and proof.restore_pending and mutations.add==0)
assert(c.mods[1] and c.adds==0)
engine_frame();assert(ab.restore());pristine(a,b,c)
assert(mutations.add==2 and c.adds==0)

-- A new compatible instance can appear while the original native destruction
-- is still pending. Do not touch it or claim rollback complete until detached.
reset();a=unit();a.defer_destroy=true;assert(ab.start({a}))
local pending_replacement=modifier(a);a.mods[1]=pending_replacement
ok,reason,proof=ab.verify()
assert(not ok and proof.restore_pending and a.mods[1]==pending_replacement and a.adds==0)
engine_frame();assert(ab.restore())
assert(a.mods[1]==pending_replacement and not pending_replacement.null and a.adds==0)

-- An AddNewModifier can also mutate and then raise. Never overwrite the
-- surviving new instance when verifying/retrying its restoration.
reset();a=unit();assert(ab.start({a}));a.fail_add_after=true
assert(not ab.restore() and #a.mods==1)
local added=a.mods[1];a.fail_add_after=false
assert(ab.restore() and a.mods[1]==added and a.adds==1)

-- Production may re-add a compatible cap. The experiment becomes invalid,
-- but rollback does not destroy/refresh that independently created instance.
reset();a,b=unit(),unit();assert(ab.start({a,b}))
local replacement=modifier(a);a.mods[1]=replacement
ok,reason,proof=ab.verify()
assert(not ok and reason=='cap_readded' and not proof.restore_pending)
assert(a.mods[1]==replacement and a.adds==0 and not replacement.null);pristine(b)

-- No acceptance when a property query itself re-adds a cap or destroys a unit.
reset();a=unit();assert(ab.start({a}))
a.on_speed=function(self) self.mods[1]=self.mods[1] or modifier(self);self.on_speed=nil end
assert(not ab.verify() and #a.mods==1 and a.adds==0)
reset();a,b=unit(),unit();assert(ab.start({a,b}))
a.on_speed=function(self) self.null=true;self.on_speed=nil end
ok,reason,proof=ab.verify()
assert(not ok and reason=='original_unit_expired' and proof.expired_count==1 and a.adds==0)
pristine(b)

-- Entity deletion/index reuse never resolves the replacement by entity index.
reset();a,b=unit(),unit();assert(ab.start({a,b}));a.null=true
replacement=unit();replacement.index=a.index;local foreign=replacement.mods[1]
ok,reason,proof=ab.verify()
assert(not ok and reason=='original_unit_expired' and proof.expired_count==1)
assert(a.adds==0 and replacement.adds==0 and replacement.mods[1]==foreign);pristine(b)
reset();a=unit();assert(ab.start({a}));a.index=a.index+10000
ok,reason,proof=ab.verify()
assert(not ok and reason=='original_entity_changed' and proof.expired_count==1 and a.adds==0)

-- Death is not destruction. The permanent original cap must survive the same
-- hero/unit's eventual respawn, so restoring to an existing dead handle is safe.
reset();a=unit();assert(ab.start({a}));a.alive=false
assert(ab.restore() and a.adds==1);pristine(a)

-- APS and display are independently verified, not inferred from multiplier.
for _,field in ipairs({'aps_delta','display_delta'}) do
    reset();a=unit();assert(ab.start({a}));a[field]=1
    ok,reason,proof=ab.verify()
    assert(not ok and reason=='attack_metrics_changed' and proof.restore_pending)
    pristine(a);a[field]=nil;assert(ab.restore())
end

-- Changing public global limits invalidates the sample; restore never writes
-- them back. A replaced GameMode blocks all old-handle mutations until resolved.
reset();a=unit();assert(ab.start({a}));mode.maximum=8
ok,reason=ab.verify()
assert(not ok and reason=='native_limits_changed' and mode.maximum==8);pristine(a)
reset();a=unit();assert(ab.start({a}));current_mode={IsNull=function() return false end}
local before=mutations.add
ok,reason,proof=ab.verify()
assert(not ok and reason=='match_changed' and proof.restore_pending and mutations.add==before)
assert(not ab.start({unit()}));current_mode=mode;assert(ab.restore());pristine(a)

assert(forbidden_calls==0,'No scans, timers, commands, stat/global setters, or entindex lookups')
assert(mode.maximum==7 and mode.minimum==0)
print('native attack cap A/B: PASS (414 explicit units, deferred native destruction/explicit finalize/rollback retry, prevalidation, three independent metrics, original-handle lifecycle/reuse/death, foreign cap preservation, reload/idempotence, zero scans/timers/setters)')
