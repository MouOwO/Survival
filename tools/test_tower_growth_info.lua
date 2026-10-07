package.path = "scripts/vscripts/?.lua;" .. package.path
local bus, events = require("core/event_bus"), require("core/events")
local callbacks, scheduled, writes, snapshot = {}, 0, 0
package.loaded["core/scheduler"] = {
    after=function(delay, fn, id)
        assert(delay==0.1);scheduled=scheduled+1;callbacks[id]=fn
    end,
    cancel=function(id) callbacks[id]=nil end,
}
CustomGameEventManager={RegisterListener=function() end}
CustomNetTables={SetTableValue=function(_, name, key, value)
    assert(name=="survival_game_info");writes=writes+1;snapshot=value
end}
local growth=0
bus.handle_request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,function()
    return {ok=true,totals={tower_attack_flat=growth}}
end)
local service=require("ui/game_info_service")
service.init()
local function hit(value)
    growth=value
    bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED,
        {player_id=0,changed_section="tower",reason="gameplay_stats_tower_attack_growth"})
end
for i=1,200 do hit(i) end
assert(scheduled==1 and writes==0, "a burst queues one presentation refresh")
local function flush()
    local due=callbacks;callbacks={}
    for _, fn in pairs(due) do fn() end
end
flush()
assert(writes==1)
local found=false
for _, field in ipairs(snapshot.fields) do
    if field.id=="tower_attack_flat" then assert(field.value==200);found=true end
end
assert(found, "the merged UI refresh must include the latest total")
hit(201)
local stale
for _, fn in pairs(callbacks) do stale=fn end
bus.reset() -- World startup resets subscriptions before initializing services.
service.init()
stale()
assert(writes==1 and next(callbacks)==nil, "old callbacks are harmless after reinit")
bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED,
    {player_id=0,reason="profile_changed"})
assert(writes==2, "normal profile changes retain immediate publication")
print("TOWER_GROWTH_INFO_PASS: 200 hits, one deferred UI snapshot, latest totals, reset/cancel races, immediate normal profile updates")
