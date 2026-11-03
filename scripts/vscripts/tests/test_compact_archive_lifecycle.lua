-- Real archive source/projector and real event_bus generation; only the native
-- transport seam is deterministic. No engine, persistence, HTTP or SDK calls.
local file=assert(io.open("scripts/vscripts/tests/test_archive_ui_wire_budget.lua","rb"))
local text=file:read("*a");file:close()
local prefix=assert(text:match("^(.-)\nreset%(%)\nlocal before_timers"))
local body=[=[
reset()
local handlers,registrations,published={},0,0
package.loaded["ui/compact_ui_transport"]={
 register_view=function(id,handler)
  assert(id>=101 and id<=120 and not handlers[id]);handlers[id]=handler
  registrations=registrations+1;return true
 end,
 publish=function()published=published+1;return true end
}
package.loaded["ui/compact_archive_views"]=nil
local module=require("ui/compact_archive_views")
local first=module.init()
assert(registrations==20 and module.init()==first and registrations==20,
 "same-world init must reuse the one registered bridge")
assert(handlers[101].open(0))
local old_handler=handlers[101]
assert(first.inspect().opens==1)
bus.reset()
-- The default transport rebuilds its registry on this same real generation.
handlers={}
local expired,why=old_handler.open(0)
assert(expired==nil and why=="archive_world_expired",
 "queued old-world callbacks expire even before the next init")
local second=module.init()
assert(second~=first and registrations==40 and module.init()==second and registrations==40)
local count=0;for _ in pairs(handlers) do count=count+1 end
assert(count==20 and second.inspect().opens==0,
 "retained Lua modules must register all twenty handlers for the new world")
assert(handlers[101].open(0) and second.inspect().opens==1)
local before=published
assert(old_handler.snapshot(0)==nil and old_handler.probe(0)==nil
 and old_handler.close(0)==nil and old_handler.intent(0,"archive_action",{})==nil)
assert(first.changed(0,profile,{replace=true})==nil)
assert(first.complete(0,"clear","old",{ok=true,terminal=true})==nil)
assert(published==before and first.inspect().opens==1,
 "retired handler/business callbacks cannot render, publish or mutate the new world")
raw_print("COMPACT_ARCHIVE_LIFECYCLE_PASS: real bus.reset, 20 handlers per world, same-world reuse, stale callbacks0work")
]=]
assert(loadstring(prefix.."\n"..body,"@real_compact_archive_lifecycle"))()
