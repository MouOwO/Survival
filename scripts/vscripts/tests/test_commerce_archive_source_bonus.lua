package.path = "scripts/vscripts/?.lua;" .. package.path
local projection = require("systems/commerce_archive_source_bonus")
local shadow = require("config/generated/archive_shadow_items")
local cage = require("config/generated/archive_cage_items")
local bus = require("core/event_bus")
local events = require("core/events")
local guard = require("systems/gameplay_phase_guard")
package.loaded["core/scheduler"] = {every=function() end}
local profiles = {}
package.loaded["systems/player_profile_service"] = {get_profile=function(id) return profiles[id] end}
local effects = require("systems/permanent_reward_effect_service")
effects.init()
local tests = 0
local function equal(actual, expected, message)
    if type(expected)=="number" then
        assert(type(actual)=="number" and math.abs(actual-expected)<0.000000001,
            (message or "number")..": expected "..tostring(expected)..", got "..tostring(actual))
    else assert(actual==expected, message or "equality") end
end
local function empty(value) assert(next(value)==nil, "expected no projected bonus") end
local function test(name, run) run(); tests=tests+1; print("PASS "..name) end
local function copy(value)
    if type(value)~="table" then return value end
    local result={};for k,v in pairs(value) do result[k]=copy(v) end;return result
end
local function owned(archive)
    return {content_inventory={commerce_p151=1},archive=archive or {},gameplay_stats={}}
end
local function changed(id,reason)
    profiles[id].revision=(profiles[id].revision or 0)+1
    bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=id,reason=reason or "test_profile_changed"})
end
local function profile(save, mode)
    return {mode=mode or "standard",revision=1,entitlements={},save=save}
end
local function totals(id)
    return bus.request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,{player_id=id}).totals
end

test("no ownership, zero, negative, malformed or nonfinite ownership cannot grant",function()
    for _,value in ipairs({0,-1,0.5,math.huge,-math.huge,"1",{},false}) do
        local s=owned({shadow_counts={shadow_01=10}});s.content_inventory.commerce_p151=value;empty(projection.project(s))
    end
    empty(projection.project({archive={shadow_counts={shadow_01=10}}}))
    local s=owned({shadow_counts={shadow_01=10}});s.content_inventory.commerce_p151=0/0;empty(projection.project(s))
    empty(projection.project(nil));empty(projection.project("invalid"))
end)

test("only actual shadow/cage item effects receive twenty percent",function()
    local s=owned({shadow_counts={shadow_01=3,shadow_02=2,shadow_14=3},cage_counts={cage_01=2,cage_03=3,cage_04=4},
        social_counts={friend_01=999},completed={achievement=1},clear_counts={n1=999}})
    s.gameplay_stats={initial_wood=100000,hero_final_damage_bonus_pct=999}
    s.permanent_effects={initial_wood=5000}
    local b=projection.project(s)
    equal(b.initial_wood,14);equal(b.initial_gold,0.4);equal(b.wall_initial_health,300);equal(b.wood_per_second,1.4)
    equal(b.hero_final_damage_bonus_pct,nil);equal(b.map_level,nil)
end)

test("every current source definition is counted and bounded by formal maximum",function()
    for _,source in ipairs({{shadow,"shadow_counts"},{cage,"cage_counts"}}) do
        for _,item in ipairs(source[1].rows) do
            if item.enabled~=false then
                local s=owned({[source[2]]={[item.item_id]=item.max_owned+100}})
                local bonus=projection.project(s)
                for index,field in ipairs(item.effect_ids) do
                    equal(bonus[field],tonumber(item.effect_values[index])*item.max_owned*0.2,item.item_id.." "..field)
                end
            end
        end
    end
end)

test("bad counts and unknown ids never grant or poison projected numbers",function()
    for _,value in ipairs({-20,0,0.5,math.huge,-math.huge,"100",{},false}) do
        empty(projection.project(owned({shadow_counts={shadow_01=value},cage_counts={cage_01=value}})))
    end
    empty(projection.project(owned({shadow_counts={shadow_01=0/0},cage_counts={cage_01=0/0}})))
    empty(projection.project(owned({shadow_counts={unknown=999999},cage_counts={unknown=999999}})))
    empty(projection.project(owned({shadow_counts=false,cage_counts="malformed"})))
end)

test("repeated projection and gameplay refresh never write back or accumulate",function()
    local s=owned({shadow_counts={shadow_01=5},cage_counts={cage_01=2}})
    local archive=s.archive;local inventory=s.content_inventory;s.gameplay_stats.initial_wood=1090
    profiles[0]=profile(s)
    for i=1,100 do
        local b=projection.project(s);equal(b.initial_wood,18)
        changed(0);equal(effects.value(0,"initial_wood"),1108)
        equal(s.gameplay_stats.initial_wood,1090);equal(s.archive.shadow_counts.shadow_01,5)
        equal(s.archive,archive);equal(s.content_inventory,inventory)
    end
end)

test("acquiring item before or after source rewards produces identical totals",function()
    profiles[1]=profile({content_inventory={},archive={shadow_counts={shadow_01=5}},gameplay_stats={initial_wood=1050}})
    changed(1);equal(effects.value(1,"initial_wood"),1050)
    profiles[1].save.content_inventory.commerce_p151=1;changed(1);equal(effects.value(1,"initial_wood"),1060)
    profiles[2]=profile(owned());profiles[2].save.gameplay_stats.initial_wood=1000;changed(2)
    profiles[2].save.archive.shadow_counts={shadow_01=5};profiles[2].save.gameplay_stats.initial_wood=1050;changed(2)
    equal(effects.value(2,"initial_wood"),effects.value(1,"initial_wood"))
end)

test("ownership and effects never cross player boundaries",function()
    profiles[3]=profile({content_inventory={},archive={shadow_counts={shadow_01=100}},gameplay_stats={initial_wood=2000}})
    changed(3);equal(effects.value(3,"initial_wood"),2000)
    profiles[1].save.archive.shadow_counts.shadow_01=10;changed(1)
    equal(effects.value(3,"initial_wood"),2000);equal(effects.value(2,"initial_wood"),1060)
end)

test("pure mode uses only authenticated current-match source and ownership deltas",function()
    local raw={content_inventory={commerce_p151=1},archive={shadow_counts={shadow_01=400},cage_counts={cage_01=100}}}
    local s=owned({shadow_counts={shadow_01=2},cage_counts={cage_01=1}})
    s.gameplay_stats.initial_wood=1040
    profiles[4]=profile(s,"pure");profiles[4].raw_account_save=raw
    changed(4);equal(effects.value(4,"initial_wood"),1048)
    profiles[4].save.content_inventory={};changed(4);equal(effects.value(4,"initial_wood"),1040)
    equal(raw.archive.shadow_counts.shadow_01,400)
end)

test("source bonus precedes existing Longinus five-percent projection",function()
    local s=owned({shadow_counts={shadow_20=10,shadow_22=10},cage_counts={cage_09=5,cage_36=4}})
    s.content_inventory.commerce_p048=1
    s.gameplay_stats={hero_attribute_bonus_pct=100,hero_attribute_growth=20,hero_final_damage_bonus_pct=10}
    s.permanent_effects={hero_attribute_bonus_pct=5}
    profiles[5]=profile(s);changed(5)
    equal(effects.value(5,"hero_attribute_bonus_pct"),112.98)
    equal(effects.value(5,"hero_attribute_growth"),21.84)
    equal(effects.value(5,"hero_final_damage_bonus_pct"),11.13)
    for i=1,5 do changed(5);equal(effects.value(5,"hero_attribute_bonus_pct"),112.98) end
end)

test("time-orb per-match boss attack bonus retains deduplication and target fields",function()
    local s=owned({shadow_counts={shadow_21=2}});s.content_inventory.lottery_time_orb=1
    s.gameplay_stats={hero_attack_bonus_pct=4,hero_attribute_bonus_pct=7}
    profiles[6]=profile(s);changed(6)
    bus.emit("archive.wave_boss_killed",{player_id=6,kill_id="test_boss_one"})
    bus.emit("archive.wave_boss_killed",{player_id=6,kill_id="test_boss_one"})
    equal(totals(6).hero_attack_bonus_pct,6.12);equal(totals(6).hero_attribute_bonus_pct,7)
    changed(6);equal(totals(6).hero_attack_bonus_pct,6.12)
end)

test("frozen social draws retain exact effects and never thaw unrelated archive sources",function()
    local s=owned({shadow_counts={shadow_01=5},cage_counts={cage_01=2}})
    s.gameplay_stats={initial_wood=1090};profiles[7]=profile(s);changed(7)
    equal(effects.value(7,"initial_wood"),1108)
    guard.set_post_clear_frozen(true)
    s.archive.shadow_counts.shadow_01=10;s.archive.cage_counts.cage_01=10
    s.archive.social_last_draw={id="social_draw_one",pool_id="friend",effects={initial_wood=3}}
    changed(7,"archive_social_draw");equal(effects.value(7,"initial_wood"),1111)
    changed(7,"archive_social_draw");equal(effects.value(7,"initial_wood"),1111)
    changed(7,"archive_online_checkpoint");equal(effects.value(7,"initial_wood"),1111)
    changed(7,"archive_boss_refresh");equal(effects.value(7,"initial_wood"),1111)
    guard.reset()
end)

print("COMMERCE_ARCHIVE_SOURCE_BONUS_PASS tests="..tests.." source_definitions="..(#shadow.rows+#cage.rows))
