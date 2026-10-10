package.path="scripts/vscripts/?.lua;"..package.path
local time=0
GameRules={GetGameTime=function() return time end}
local repository=require("combat/damage_transaction_repository")
repository.init({maximum_recursion_depth=6})
local attacker,victim={},{}
local parent
for depth=0,7 do
    local record=repository.create({transaction_id="chain:"..depth,parent_transaction_id=parent,
        attacker=attacker,victim=victim,tags={retained=false}})
    assert(record.recursion_depth==depth)
    assert((record.blocked~=nil)==(depth==7))
    parent=record.transaction_id
    repository.mark_submitted(record)
    if depth%2==0 then assert(repository.consume_pending(attacker,victim)==record) end
    repository.finish(record)
    assert(repository.consume_pending(attacker,victim)==nil,"no stale pending after finish")
    local memo=repository.get(record.transaction_id)
    assert(memo and memo.recursion_depth==depth and not memo.attacker and not memo.victim and not memo.tags)
end
local duplicate=repository.create({transaction_id="chain:0"})
assert(duplicate.blocked=="duplicate_transaction_id")
repository.finish(duplicate)
assert(repository.get("chain:0"),"duplicate cannot retire another transaction")
time=11
assert(repository.get("chain:0")==nil,"history expires even before a sweep")
assert(not repository.create({transaction_id="chain:0"}).blocked)
repository.remove("chain:0")
repository.init({maximum_recursion_depth=6})
local seen={}
for i=1,100000 do
    local r=repository.create({attacker=attacker,victim=victim})
    assert(not seen[r.transaction_id] and not r.blocked,"same-frame IDs must be unique")
    seen[r.transaction_id]=true
    repository.mark_submitted(r)
    assert(repository.consume_pending(attacker,victim)==r)
    repository.finish(r)
end
local snapshot=repository.debug_snapshot()
assert(snapshot.active_records==0 and snapshot.pending_records==0)
assert(snapshot.recent_records<=snapshot.history_limit,"same-frame history bounded")
-- Completed records must not pin engine entities, including idle sessions.
repository.init({maximum_recursion_depth=6})
local weak=setmetatable({}, {__mode="v"})
do
    local a,b={},{};weak[1],weak[2]=a,b
    local r=repository.create({attacker=a,victim=b});repository.finish(r)
end
collectgarbage("collect")
assert(weak[1]==nil and weak[2]==nil,"completed entities leaked")
local service=require("combat/damage_service")
DAMAGE_TYPE_PURE=4
local entity={IsNull=function() return false end,entindex=function() return 1 end}
local mode="error"
service.init({event_bus={emit=function() end},events=require("combat/combat_events"),
    context=require("combat/damage_context"),rules={source_kind_rules={}},repository=repository,
    debug={log=function() end},adapter={Apply=function()
        if mode=="error" then error("native apply failure") end
        if mode=="blocked" then return {ok=false,error="invalid_entity"} end
        return {ok=true}
    end}})
local request={attacker=entity,victim=entity,source_kind="script",base_damage=10,damage_type=4}
local ok,err=pcall(service.Deal,service,request)
assert(not ok and tostring(err):find("native apply failure",1,true))
mode="blocked";assert(not service:Deal(request).success)
mode="no_filter";assert(service:Deal(request).success)
assert(not service:Deal({}).success)
snapshot=repository.debug_snapshot()
assert(snapshot.active_records==0 and snapshot.pending_records==0,"all submission exits release records")
print("DAMAGE_TRANSACTION_LIFECYCLE_PASS: unique burst IDs, bounded history, recursion/replay, weak entities, native error/blocked/no-filter exits")
