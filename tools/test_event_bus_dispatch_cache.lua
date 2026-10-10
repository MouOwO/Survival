package.path='scripts/vscripts/?.lua;'..package.path
local bus=require('core/event_bus')
local function equal(actual,expected)
    assert(table.concat(actual,'|')==table.concat(expected,'|'),table.concat(actual,'|'))
end
local function upvalue(fn,wanted)
    for index=1,30 do
        local name,value=debug.getupvalue(fn,index)
        if name==wanted then return value end
        if not name then break end
    end
    error('Missing diagnostic upvalue '..wanted)
end

bus.reset()
local received,insertions=0,0
local callbacks={}
for index=1,8 do
    callbacks[index]=bus.subscribe('hot',function(payload)
        assert(payload.value==4);received=received+1
    end)
end
local original_insert=table.insert
table.insert=function(t,value) insertions=insertions+1;return original_insert(t,value) end
for _=1,10000 do bus.emit('hot',{value=4}) end
assert(received==80000 and insertions==8, 'Unchanged subscriptions need exactly one snapshot')
local other=bus.subscribe('other',function() end)
bus.emit('other',{})
bus.emit('hot',{value=4})
assert(insertions==9, 'Changes to one topic cannot rebuild another topic')
bus.unsubscribe({event_name='hot',token=-900})
bus.emit('hot',{value=4})
assert(insertions==9, 'No-op unsubscribe does not rebuild')
bus.unsubscribe(callbacks[1])
bus.emit('hot',{value=4})
assert(insertions==16 and received==80023)
table.insert=original_insert

-- Preserve existing pairs-derived order, regardless of what it happens to be
-- on this Lua build. Unsubscription changes only subsequent emissions.
bus.reset()
local trace,initial,subscriptions={}, {}, {}
for _,id in ipairs({'alpha','beta','gamma'}) do
    local name=id
    subscriptions[name]=bus.subscribe('mutation',function(payload)
        if payload.phase=='prime' then initial[#initial+1]=name;return end
        trace[#trace+1]=payload.phase..':'..name
        if payload.phase=='outer' and name==initial[1] then
            bus.unsubscribe(subscriptions[initial[2]])
            bus.unsubscribe(subscriptions[name])
            bus.subscribe('mutation',function(inner) trace[#trace+1]=inner.phase..':new' end)
            bus.emit('mutation',{phase='nested'})
        end
    end)
end
bus.emit('mutation',{phase='prime'})
bus.emit('mutation',{phase='outer'})
assert(#trace==5 and trace[1]=='outer:'..initial[1])
assert(trace[4]=='outer:'..initial[2] and trace[5]=='outer:'..initial[3],
    'Outer emit retains even unsubscribed pending handlers in original order')
local nested={trace[2],trace[3]};table.sort(nested)
local expected={'nested:'..initial[3],'nested:new'};table.sort(expected);equal(nested,expected)
trace={};bus.emit('mutation',{phase='later'})
assert(#trace==2)
local later={(trace[1]:gsub('later:','nested:')),(trace[2]:gsub('later:','nested:'))}
table.sort(later);equal(later,expected)

-- A reset inside a callback makes nested emits use new subscriptions, while
-- the already-running emission still completes its pre-reset list.
bus.reset();trace={};initial={}
for index=1,3 do
    local id=index
    bus.subscribe('resetting',function(payload)
        if payload.prime then initial[#initial+1]=id;return end
        trace[#trace+1]='old'..id
        if id==initial[1] then
            bus.reset()
            bus.subscribe('resetting',function() trace[#trace+1]='new' end)
            bus.emit('resetting',{})
        end
    end)
end
bus.emit('resetting',{prime=true});bus.emit('resetting',{})
equal(trace,{'old'..initial[1],'new','old'..initial[2],'old'..initial[3]})
trace={};bus.emit('resetting',{});equal(trace,{'new'})

bus.reset();local duplicates=0
local same=function() duplicates=duplicates+1 end
local one=bus.subscribe('duplicates',same)
bus.subscribe('duplicates',same)
bus.emit('duplicates',{});assert(duplicates==2)
bus.unsubscribe(one);bus.emit('duplicates',{});assert(duplicates==3)

-- Nil/false payloads still produce separate empty tables per subscriber;
-- explicit tables are shared, and one handler failure does not abort siblings.
bus.reset()
local payloads,success,logs={},0,{}
local original_print=print
print=function(value) logs[#logs+1]=value end
bus.subscribe('errors',function(payload) payloads[#payloads+1]=payload;error('expected_handler_failure') end)
bus.subscribe('errors',function(payload) payloads[#payloads+1]=payload;success=success+1 end)
bus.emit('errors');bus.emit('errors',false)
assert(success==2 and #logs==2 and payloads[1]~=payloads[2] and payloads[3]~=payloads[4])
local explicit={};bus.emit('errors',explicit)
assert(payloads[5]==explicit and payloads[6]==explicit and success==3)
print=original_print

-- Opt-in instrumentation modifies the actual callback slot, then explicitly
-- invalidates its immutable dispatch snapshot. Restoring is symmetric.
bus.reset();local calls,wrapped=0,0
local original=function() calls=calls+1 end
local token=bus.subscribe('wrapped',original)
bus.emit('wrapped',{})
local slots=upvalue(bus.emit,'subscribers')
slots.wrapped[token.token]=function() wrapped=wrapped+1;original() end
bus.invalidate_dispatch('wrapped');bus.emit('wrapped',{})
assert(calls==2 and wrapped==1)
slots.wrapped[token.token]=original
bus.invalidate_dispatch();bus.emit('wrapped',{})
assert(calls==3 and wrapped==1)
bus.handle_request('unchanged_request',function(payload) return payload end)
assert(bus.request('unchanged_request',explicit)==explicit)
assert(not pcall(bus.handle_request,'unchanged_request',same))
local result,err=bus.request('missing')
assert(result==nil and err=='no_request_handler:missing')
assert(not pcall(bus.subscribe,{},same) and not pcall(bus.subscribe,'bad',{}))
assert(not pcall(bus.unsubscribe,{event_name='wrapped'}), 'Invalid tokens retain the original error')
bus.reset();assert(next(upvalue(bus.emit,'dispatch_snapshots'))==nil)
print('EVENT_BUS_DISPATCH_CACHE_PASS: 80000 deliveries / 8 copies; immutable mutation/reset/nesting/order, duplicate/error/payload contracts, probe invalidation')

-- Subscription identities cannot cross a bus reset or a module replacement.
bus.reset();local first_generation=bus.get_generation()
local old=bus.subscribe('recycled',function()error('retired callback')end)
bus.reset();assert(bus.get_generation()~=first_generation)
local calls=0;local current=bus.subscribe('recycled',function()calls=calls+1 end)
assert(old.token==current.token and old.generation~=current.generation)
bus.unsubscribe(old);bus.emit('recycled',{});assert(calls==1)
bus.unsubscribe(current);bus.emit('recycled',{});assert(calls==1)
bus.reset();local retired=bus.subscribe('reloaded',function()error('old module callback')end)
package.loaded['core/event_bus']=nil;local replacement=require('core/event_bus')
assert(replacement.get_generation()~=bus.get_generation())
local delivered=0;local fresh=replacement.subscribe('reloaded',function()delivered=delivered+1 end)
assert(fresh.token==retired.token)
replacement.unsubscribe(retired);replacement.emit('reloaded',{});assert(delivered==1)
replacement.unsubscribe(fresh);replacement.emit('reloaded',{});assert(delivered==1)
print('EVENT_BUS_GENERATION_PASS: reset/module replacement, exact tokens, stale cleanup rejection')
