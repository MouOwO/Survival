package.path="scripts/vscripts/?.lua;"..package.path
local context=require("ui/compact_profile_context")
local outer,inner,other={inventory={"a"}},{daily_state=true},{entitlement=true}
assert(context.current(0)==nil)
local a,b=context.with(0,outer,function()
    assert(context.current(0)==outer and context.current(1)==nil)
    context.with(1,other,function()assert(context.current(0)==outer and context.current(1)==other)end)
    assert(context.current(1)==nil)
    local ok=pcall(function()context.with(0,inner,function()
        assert(context.current(0)==inner);error("synthetic_commit_failure")
    end)end)
    assert(not ok and context.current(0)==outer)
    return 17,"unchanged_callback_result"
end)
assert(a==17 and b=="unchanged_callback_result" and context.current(0)==nil)
for i=1,1000 do context.with(0,outer,function()assert(context.current(0)==outer)end)end
assert(context.current(0)==nil)
print("COMPACT_PROFILE_CONTEXT_PASS: scoped synchronous metadata, two players, reentrant exception, original results, no retained frames")
