-- Real Lua 5.1 debug API tests. Never connects Dota or performs any attack.
local source=(arg[1] or '.')..'/scripts/vscripts/tests/manual_sync_lua_call_counter.lua'
IsServer=function()return true end;IsInToolsMode=function()return true end
local ticks,step=0,0
GetSystemTimeMS=function()local value=ticks;ticks=ticks+step;return value end
local counter=dofile(source)
local assertions=0
local function check(value,message)assertions=assertions+1;assert(value,message or ('check '..assertions))end
local function clear()local hook,mask,count=debug.gethook();check(hook==nil and mask=='' and count==0,'current hook restored')end
local function reset_clock()ticks,step=0,0 end
local marker={};local executed=0
local r,values=counter.capture(function(a,b,c)executed=executed+1;return a,b,c end,{},1,nil,marker)
check(r.called and r.call_ok and r.capture_valid and not r.truncated and not r.timing_valid)
check(executed==1 and values.n==4 and values[1] and values[2]==1 and values[3]==nil and values[4]==marker);clear()
-- Lua 5.1's main thread has no addressable coroutine handle; synchronous local
-- install/cleanup nevertheless works and never requires a cross-tick watchdog.
check(coroutine.running()==nil)
local calls=0
local callback=assert(loadstring('return function(_,v) v.count=v.count+1 end','@sync_fixture_callbacks.lua'))()
local original=callback;local items={a={count=0},b={count=0},c={count=0}}
callback=function()error('reloaded replacement is not the cached pointer')end
r=counter.capture(function()table.foreach(items,original)end)
local counted=0;for _,row in ipairs(r.rows)do if row.source=='sync_fixture_callbacks.lua' then counted=counted+row.calls end end
check(counted==3 and items.a.count==1 and items.c.count==1,'C -> cached Lua callback counted');clear()
-- Preserve errors/results and clear after both normal and throwing functions.
r,values=counter.capture(function()error(marker)end)
check(r.called and not r.call_ok and r.restore_confirmed and values.n==2 and values[2]==marker);clear()
-- Existing tools' hooks are never replaced, including non-call masks/counts.
for _,setting in ipairs({{'c',0},{'l',0},{'',3}})do
 local observed=0;local existing=function()observed=observed+1 end
 debug.sethook(existing,setting[1],setting[2])
 local ran=false;r=counter.capture(function()ran=true end)
 local actual,mask,count=debug.gethook()
 check(not ran and not r.called and r.reason=='existing_or_unreadable_hook')
 check(actual==existing and mask==setting[1] and count==setting[2]);debug.sethook();clear()
end
-- Saturation truncates only the diagnostic, never the supplied operation.
local effect=0;r,values=counter.capture(function()for i=1,1000 do math.abs(i);effect=effect+1 end;return effect end,{max_calls=10})
check(r.events==10 and r.truncated and r.reason=='call_limit' and effect==1000 and values[2]==1000);clear()
reset_clock();step=1;r=counter.capture(function()for i=1,1000 do math.abs(i)end end,{max_wall_ms=5})
check(r.truncated and r.reason=='wall_limit' and r.events<=5 and r.restore_confirmed);clear();reset_clock()
-- Bounds apply to all caller settings; source rows remain bounded after many
-- distinct callbacks, while omitted calls retain honest accounting.
local functions={};for i=1,20 do functions[i]=assert(loadstring('return function() end','@row_'..i..'.lua'))()end
r=counter.capture(function()for _,f in ipairs(functions)do f()end end,{max_rows=2,max_calls=1000000,max_wall_ms=900})
check(#r.rows<=2 and r.omitted_calls>0 and r.max_calls==10000 and r.max_wall_ms==50);clear()
-- Never leak a Lua 5.1 inherited hook mask into a newly created coroutine.
local child;r=counter.capture(function()child=coroutine.create(function()return 42 end)end)
local h,m,c=debug.gethook(child);check(r.reason=='coroutine_create' and r.truncated and h==nil and m=='' and c==0);clear()
local child_clear=false;r=counter.capture(function()local wrapped=coroutine.wrap(function()local h,m,c=debug.gethook();child_clear=h==nil and m=='' and c==0 end);wrapped()end)
check(r.reason=='coroutine_wrap' and child_clear);clear()
local resumed=0;local child=coroutine.create(function()resumed=resumed+1 end)
r=counter.capture(function()assert(coroutine.resume(child))end)
check(r.reason=='coroutine_resume' and resumed==1);clear()
-- A yield is rejected by Lua5.1 pcall, but our hook detaches before the attempt.
local child=coroutine.create(function()local report=counter.capture(function()coroutine.yield()end);return report end)
local success,report=coroutine.resume(child);check(success and report.reason=='coroutine_yield' and not report.call_ok)
local h,m,c=debug.gethook(child);check(h==nil and m=='' and c==0);clear()
-- Nested counter refuses the current diagnostic rather than replacing it.
local inner;r=counter.capture(function()inner=counter.capture(function()error('must not run')end)end)
check(inner.reason=='existing_or_unreadable_hook' and not inner.called and r.restore_confirmed);clear()
-- Explicit hook replacement belongs to the supplied function. We detach before
-- its sethook call and preserve its replacement instead of silently clearing it.
local foreign=function()end;r=counter.capture(function()debug.sethook(foreign,'c',0)end)
local current=debug.gethook();check(current==foreign and r.replacement_preserved and r.reason=='hook_change' and not r.restart_required)
debug.sethook();clear()
-- Missing/invalid native clock and Tools guard never execute the operation.
local clock=GetSystemTimeMS;GetSystemTimeMS=nil;r=counter.capture(function()error('must not run')end);check(not r.called and r.reason=='native_debug_clock_unavailable');GetSystemTimeMS=clock
IsInToolsMode=function()return false end;r=counter.capture(function()error('must not run')end);check(not r.called and r.reason=='tools_server_only');IsInToolsMode=function()return true end
step=-1;ticks=2;r=counter.capture(function()math.abs(1)end);check(r.reason=='clock_invalid' and r.restore_confirmed);clear();reset_clock()
-- A missing/throwing debug metadata API aborts safely before the supplied fn.
local info=debug.getinfo;debug.getinfo=function()error('test metadata unavailable')end
local ran=false;r=counter.capture(function()ran=true end);debug.getinfo=info
check(not ran and r.reason=='getinfo_failed' and r.restore_confirmed);clear()
-- Install failure never invokes fn. Cleanup failure is NOT falsely certified;
-- the test retains the genuine API and cleans its deliberately broken shim.
local sethook=debug.sethook;debug.sethook=function()error('install unavailable')end
local ran=false;r=counter.capture(function()ran=true end);debug.sethook=sethook
check(not ran and not r.called and r.restore_confirmed and not r.capture_valid);clear()
debug.sethook=function(h,mask,count)if h~=nil then return sethook(h,mask,count)end;error('clear unavailable')end
r=counter.capture(function()math.abs(1)end);debug.sethook=sethook;sethook()
check(r.restart_required and not r.restore_confirmed and not r.capture_valid);clear()
-- Anonymous chunk text is opaque even if it contains sensitive text.
local opaque=assert(loadstring('return function() local private_token="DO_NOT_PRINT_FULL_CHUNK" end'))()
r=counter.capture(opaque);for _,row in ipairs(r.rows)do check(not row.source:find('DO_NOT_PRINT_FULL_CHUNK',1,true))end;clear()

-- C symbols must not be collapsed into the first observed name. The capture
-- itself invokes pcall/unpack; neither should leak into game C rows.
local function named_c_counts(report)
 local result={};for _,row in ipairs(report.rows)do if row.source=='[C]' then result[row.name]=(result[row.name] or 0)+row.calls end end
 return result
end
r=counter.capture(function()for i=1,3 do math.abs(-i)end;for i=1,2 do math.floor(i+.5)end end,{max_rows=256})
local native=named_c_counts(r)
check(native.abs==3 and native.floor==2,'C names have independent counts')
check(native.pcall==nil and native.unpack==nil,'capture pcall/unpack excluded')
check(r.c_calls==5 and r.probe_calls>0 and r.events==r.c_calls+r.lua_calls+r.probe_calls+r.unknown_calls,'honest category totals');clear()
-- The caller may genuinely use those same APIs; only own source is excluded.
r=counter.capture(function()pcall(math.abs,-1);unpack({1,2});select('#',1,2)end)
native=named_c_counts(r);check(native.pcall==1 and native.unpack==1 and native.select==1,'gameplay same-name C calls retained');clear()
local absolute=assert(loadstring('return function()end','@D:/game/addons/survival/scripts/vscripts/fixture.lua'))()
local relative=assert(loadstring('return function()end','@scripts/vscripts/fixture.lua'))()
r=counter.capture(function()absolute();relative()end)
local paths=0;for _,row in ipairs(r.rows)do if row.source=='scripts/vscripts/fixture.lua' then paths=paths+1;check(row.calls==2)end end
check(paths==1,'native absolute and require relative source merged');clear()
-- An explicitly re-entrant native clock callback must not count hook work or
-- recurse forever. Real VM call/return behavior remains under genuine Lua5.1.
local ordinary_clock=GetSystemTimeMS
GetSystemTimeMS=function()local h=debug.gethook();if h then h('call')end;return 0 end
r=counter.capture(function()math.abs(-1)end)
GetSystemTimeMS=ordinary_clock;native=named_c_counts(r)
check(r.capture_valid and not r.truncated and native.abs==1,'hook internal re-entry excluded');clear()


-- A C API shared by distinct Lua callers/lines must retain attribution even
-- when Lua exposes no native function name (e.g. a C __index metamethod).
local split=assert(loadstring([[return function()
 math.abs(-1)
 math.abs(-2)
end]],'@scripts/vscripts/c_caller_fixture.lua'))()
r=counter.capture(split,{max_rows=256})
local sites={};for _,row in ipairs(r.rows)do if row.source=='[C]' and row.name=='abs' then
 check(row.calls==1 and row.caller_source=='scripts/vscripts/c_caller_fixture.lua' and row.caller_kind=='Lua')
 sites[row.caller_line]=true
end end
check(sites[2] and sites[3],'same C native distinct call sites');clear()
local object=setmetatable({},{__index=tostring})
local metamethod=assert(loadstring('return function(object) return object.missing end','@scripts/vscripts/c_meta_fixture.lua'))()
r,values=counter.capture(metamethod,{max_rows=256},object)
local unnamed=false;for _,row in ipairs(r.rows)do if row.source=='[C]' and row.caller_source=='scripts/vscripts/c_meta_fixture.lua' then
 check(row.calls==1 and row.caller_line==1 and row.caller_defined==1 and row.caller_kind=='Lua')
 unnamed=true
end end
check(unnamed and r.call_ok and type(values[2])=='string','native metamethod source retained');clear()


-- Unnamed C callbacks through C pcall get bounded opaque identities and the
-- nearest Lua callsite. Distinct C functions must never collapse together.
r=counter.capture(function()pcall(math.abs,-1);pcall(math.floor,2.5);pcall(math.abs,-2)end,{max_rows=256})
local ids,stacked={},0
for _,row in ipairs(r.rows)do if row.native_id then
 check(row.native_id>0 and row.caller_native_id>0 and row.stack_walk_depth<=8 and #row.stack_sample<=3)
 check(row.nearest_lua_source:find('test_sync_lua_call_counter.lua',1,true) and row.nearest_lua_line>0)
 ids[row.native_id]=(ids[row.native_id] or 0)+row.calls;stacked=stacked+row.calls
end end
local separate=0;for _,count in pairs(ids)do check(count==1 or count==2);separate=separate+1 end
check(separate==2 and stacked==3 and r.stack_walk_events==3);clear()
local iterators={};for i=1,80 do iterators[i]=string.gmatch('x','x')end
r=counter.capture(function()for _,iterator in ipairs(iterators)do pcall(iterator)end end,{max_rows=256})
check(r.native_identity_count==64 and r.native_identity_limit==64 and r.native_identity_overflow_calls>0,'opaque function references capped')
check(#r.rows<=256 and r.max_rows==256 and r.call_ok and r.restore_confirmed);clear()
r=counter.capture(function()pcall(pcall,pcall,pcall,pcall,pcall,pcall,pcall,pcall,pcall,math.abs,-1)end,{max_rows=256})
local limited=false
for _,row in ipairs(r.rows)do if row.native_id then
 check(row.stack_walk_depth<=8 and #row.stack_sample<=3)
 if row.stack_limit_reached then limited=true;check(row.nearest_lua_source=='[no_lua_within_limit]')end
end end
check(limited and r.call_ok and r.restore_confirmed,'deep C stack limited without disturbing operation');clear()

print('SYNC_LUA_CALL_COUNTER_PASS '..assertions..' checks: real main-thread calls/C->Lua cached callbacks, bounded counts/wall/rows, fn errors and nil results, existing/foreign hooks, coroutine inheritance/yield boundaries, failed metadata, no timers/attacks')
