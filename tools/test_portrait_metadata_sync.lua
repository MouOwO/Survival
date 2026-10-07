package.path="scripts/vscripts/?.lua;"..package.path
local bus=require("core/event_bus")
local events=require("core/events")
local metadata=require("ui/portrait_metadata")
local published={}
CustomNetTables={SetTableValue=function(_,name,key,value)
    if name=="survival_combat_stats" then published[#published+1]=value end
end}
bus.reset();require("ui/combat_stats_ui_service").init()
for _,hero in ipairs({"doom","blademaster"}) do
    local full=metadata.apply({survival_hero_id="hero_"..hero},{entindex=7})
    assert(full.portrait_unit_name~="")
    for i=1,30 do
        bus.emit(events.HERO_COMBAT_STATS_CHANGED,{player_id=0,snapshot={entindex=7,hero_id="hero_"..hero,health=100-i}})
        local regular=published[#published]
        assert(regular and regular.health==100-i)
        for _,key in ipairs({"model_asset_id","portrait_unit_name","portrait_item_def"}) do
            assert(regular[key]==full[key], "periodic stats erased "..key)
        end
    end
end
assert(#published==60)
local empty=metadata.apply(nil,{entindex=8})
assert(empty.model_asset_id=="" and empty.portrait_unit_name=="")
print("PORTRAIT_METADATA_SYNC_PASS: 60 real event/nettable publications match selected-unit identities")
-- Model swaps on shared monster unit names must reach regular snapshots.
local real = {GetModelName=function() return "models/heroes/rubick/rubick.vmdl" end}
EntIndexToHScript=function(index) if index==99 then return real end end
local model=metadata.apply(nil,{entindex=99})
assert(model.portrait_model_name=="models/heroes/rubick/rubick.vmdl")
real.GetModelName=function() return "models/heroes/ember_spirit/ember_spirit.vmdl" end
assert(metadata.apply(nil,{entindex=99}).portrait_model_name=="models/heroes/ember_spirit/ember_spirit.vmdl")
assert(metadata.apply(nil,{entindex=999,portrait_model_name="stale"}).portrait_model_name=="")
EntIndexToHScript=function() error("removed entity") end
assert(metadata.apply(nil,{entindex=99}).portrait_model_name=="")
print("PORTRAIT_RUNTIME_MODEL_PASS: actual entity, model swap, clear and removed entity")
