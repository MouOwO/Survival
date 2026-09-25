-- Subscription snapshot construction count; not a game frame-time claim.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = arg and arg[1] and dofile(arg[1]) or require("core/event_bus")
local delivered, copied = 0, 0
for i = 1, 8 do bus.subscribe("fixture", function() delivered = delivered + 1 end) end
local original_insert = table.insert
table.insert = function(t, value) copied = copied + 1; return original_insert(t, value) end
for i = 1, 10000 do bus.emit("fixture", {}) end
table.insert = original_insert
assert(delivered == 80000)
print(string.format('{"kind":"offline_lua_simulation","emissions":10000,"listeners":8,"delivered":%d,"snapshot_handler_copies":%d}', delivered, copied))
