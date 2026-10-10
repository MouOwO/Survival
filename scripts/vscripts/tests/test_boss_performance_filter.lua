package.path="scripts/vscripts/?.lua;"..package.path
local tools,now,cpu=false,0,0
IsServer=function() return true end
IsInToolsMode=function() return tools end
Time=function() return now end
GetSystemTimeMS=function() return cpu end
local mode={}
local engine_filter,engine_owner,timer
mode.SetContextThink=function(_,_,callback) timer=callback end
mode.SetDamageFilter=function(_,fn,owner) engine_filter,engine_owner=fn,owner end
GameRules={GetGameModeEntity=function() return mode end}
local original=function(owner,keys)
    assert(owner==engine_owner)
    cpu=cpu+2
    if keys.fail then error("original_filter_error") end
    keys.damage=keys.damage+7
    return true
end
local service={_filter_for_test=original}
package.loaded["combat/damage_filter_service"]=service
mode:SetDamageFilter(original,service)
local lines={};local saved_print=print
print=function(line) lines[#lines+1]=line end
local probe=require("tests/manual_boss_performance")
assert(engine_filter==original,"merely requiring diagnostics outside Tools must not alter native filter")
tools=true;assert(probe.run(5))
assert(engine_filter~=original and engine_owner==service)
local keys={damage=10};assert(engine_filter(engine_owner,keys) and keys.damage==17)
local ok,err=pcall(engine_filter,engine_owner,{damage=10,fail=true})
assert(not ok and err:find("original_filter_error",1,true))
assert(probe.stop("test") and engine_filter==original and service._filter_for_test==original)
assert(not probe.stop() and timer()==nil)
local logs=table.concat(lines,"\n")
assert(logs:find("callback name=damage_filter calls=2 total_ms=4.000",1,true))
assert(probe.run(5))
mode={SetDamageFilter=function() error("do not replace the new world's native filter") end}
assert(probe.stop("world_changed") and service._filter_for_test==original)
print=saved_print
print("PASS Tools damage-filter diagnostics preserve keys, returns, errors and native binding; world-aware cleanup")
