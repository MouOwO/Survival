-- Reuse the established full router/publisher engine fixture, not its obsolete
-- historical assertion requiring duplicate custom-event + NetTable delivery.
package.path="scripts/vscripts/?.lua;"..package.path
package.loaded["core/test_access_policy"]={enabled=function()return false end,enforce=function()return true end}
local input=assert(io.open("scripts/vscripts/tests/test_portrait_metadata_channels.lua","rb"))
local text=input:read("*a");input:close()
local start=assert(text:find("local index = 200",1,true))
local fixture=text:sub(1,start-1)
-- That old seam now intentionally wraps building_stat_display before metadata.
local seam='assert(router._test.apply_portrait_metadata == metadata.apply, "router seam must use the shared mapping")'
local first,last=assert(fixture:find(seam,1,true))
fixture=fixture:sub(1,first-1)..fixture:sub(last+1)
local checks=[[
local clock=1000
GameRules.GetGameTime=function()return clock end
for _,first in ipairs({false,true})do
    initialize(first)
    entities[200]={survival_hero_id="hero_doom",IsNull=function()return false end,
        GetPhysicalArmorValue=function()return 2 end}
    raw=snapshot_for("hero_doom",200,1)
    listeners.ui_selected_unit_stats_request(nil,{PlayerID=0,entindex=200})
    assert(#sent==1 and sent[1].name=="ui_selected_unit_stats_snapshot","selection response remains immediate")
    sent,tables={},{}
    for version=1,500 do
        raw=snapshot_for("hero_doom",200,version)
        bus.emit(events.HERO_COMBAT_STATS_CHANGED,{player_id=0,snapshot=raw})
    end
    assert(#tables==500 and #sent==0 and scheduler.task_count()==0,
        "500 real hero updates use one existing regular channel, no duplicate event jobs")
    assert(tables[#tables].snapshot.refresh_version==500)
    bus.emit(events.UNIT_COMBAT_STATS_CHANGED,{player_id=0,entindex=200,reason="research_armor_reduction"})
    clock=clock+.11;scheduler.think()
    assert(#sent==1 and sent[1].snapshot.push_phase=="coalesced",
        "temporary unit armor supplement retains its custom-event path")
    assert(sent[1].snapshot.runtime_armor==2)
end
print("HERO_SINGLE_CHANNEL_PASS: 500 updates x both init orders => 500 NetTables, 0 duplicate events/tasks; selection and armor supplement retained")
]]
assert(loadstring(fixture..checks,"actual_hero_router_fixture"))()
