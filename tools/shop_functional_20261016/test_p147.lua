-- Reuse the existing production/native boundary regression as an engine fixture.
-- The assertions below then exercise actual hero aggregation, damage filtering
-- and skill-choice services with four isolated inventory/source profiles.
local output = print
dofile("tools/test_hero_large_attack_projection.lua")
local bus, events = require("core/event_bus"), require("core/events")
local scheduler = require("core/scheduler")
local damage_events = require("combat/combat_events")
local profiles, source = {}, {}
-- Pure-mode match inventory is empty while its separate account UI owns the
-- privilege. Combat must never fall back to the account presentation profile.
local account_profiles = {[3]={mode="standard",save={content_inventory={commerce_p147=1}}}}
local reads, account_reads = 0, 0
package.loaded["systems/player_profile_service"] = {
    get_content_inventory_count = function(id, item)
        reads = reads + 1
        return ((profiles[id] or {})[item]) or 0
    end,
    get_account_profile = function(id)
        account_reads=account_reads+1
        return account_profiles[id]
    end,
}
local function near(actual, expected, label)
    assert(type(actual) == "number" and math.abs(actual-expected) <= math.max(1e-7,math.abs(expected)*1e-10),
        (label or "number")..": "..tostring(actual).." != "..tostring(expected))
end
local function request(event, fn) bus.handle_request(event, fn) end
local function stats(id)
    local result, err = bus.request(events.HERO_COMBAT_STATS_GET_REQUEST,{player_id=id})
    assert(result and result.ok,tostring(err));return result.snapshot
end
local function profile_changed(id, reason)
    bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=id,reason=reason or "purchase_receipt"})
end
bus.reset();scheduler.clear()
local technology = require("systems/technology_stat_manager")
technology.get = function(id) return {final={hero=source[id].technology}} end
for id=0,3 do
    profiles[id]={}
    source[id]={
        permanent={hero_all_attributes_flat=20,hero_attributes_per_level=3,
            hero_attribute_bonus_pct=50,hero_rebirth_attribute_bonus_pct=10,
            hero_final_damage_bonus_pct=25,global_final_damage_bonus_pct=10},
        progression={all_attributes=100,rebirth_level=2},
        technology={all_attributes_flat=30,final_damage_bonus_pct=20},
        gear={all_attributes_flat=40},growth={growth_strength=5,growth_agility=6,growth_intellect=7},
        essence={all_attributes_pct=30,final_damage_pct=15},
        monkey={strength=10,agility=11,intellect=12},
    }
end
request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,function(p)
    return {totals=source[p.player_id].permanent,display_totals=source[p.player_id].permanent}
end)
for _,entry in ipairs({
    {events.HERO_PROGRESSION_GET_REQUEST,"progression"},
    {events.WEAPON_GROWTH_GET_REQUEST,"growth"},
    {events.SEVEN_SINS_ESSENCE_STATS_GET_REQUEST,"essence"},
    {events.MONKEY_KING_BONUS_STATS_GET_REQUEST,"monkey"},
}) do
    local event, key=entry[1],entry[2]
    request(event,function(p) return {ok=true,snapshot=source[p.player_id][key]} end)
end
request(events.EQUIPMENT_STATS_GET_REQUEST,function(p) return {snapshot={values=source[p.player_id].gear}} end)
request(events.WEAPON_EQUIPMENT_GET_REQUEST,function() return {snapshot={main_hand_content_id="weapon_growth_sword_01"}} end)
request(events.HERO_SKILL_STATE_GET_REQUEST,function() return {snapshot={skills={}}} end)
local hero_service=require("systems/hero_combat_stat_service")
hero_service.init()
local hero,neighbor=EntIndexToHScript(101),EntIndexToHScript(102)
for id,u in pairs({[0]=hero,[1]=neighbor}) do
    u.modifiers={};u.null=false;u.dead=false;u.survival_player_id=id;u.survival_hero_id="hero_monkey_king"
    bus.emit(events.HERO_SUMMONED,{player_id=id,hero_id="hero_monkey_king",unit=u})
end
local before,other_before=stats(0),stats(1)
profiles[0].commerce_p147=1
profile_changed(0)
local owned=stats(0)
for _,key in ipairs({"strength","agility","intellect"}) do
    near(owned[key],before[key]*1.08,"independent EX includes every live "..key.." source")
    local base=require("config/generated/hero_definitions").by_id.hero_monkey_king["base_"..key]
    near(owned["display_"..key.."_bonus"]+base,
        (before["display_"..key.."_bonus"]+base)*1.08,"static HUD source shares EX")
end
near(owned.commerce_ex_attribute_multiplier,1.08)
near(hero.survival_commerce_hero_ex_damage_multiplier,1.08)
assert(stats(1)==other_before,"purchasing privilege cannot refresh another player's snapshot")
profiles[0].commerce_p147=99;profile_changed(0)
assert(stats(0)==owned,"copies of an owned privilege cannot stack EX or refresh unchanged stats")
local before_growth=stats(0).strength
source[0].progression.all_attributes=175
bus.emit(events.HERO_PROGRESSION_CHANGED,{player_id=0})
near(stats(0).strength-before_growth,75*1.5*1.2*1.3*1.08,"future attack/time progression receives EX")
before_growth=stats(0).strength
source[0].growth.growth_strength=12
bus.emit(events.WEAPON_GROWTH_CHANGED,{player_id=0})
near(stats(0).strength-before_growth,7*1.5*1.2*1.3*1.08,"future weapon growth receives EX")
before_growth=stats(0).strength
source[0].technology.all_attributes_flat=42
bus.emit(events.TECHNOLOGY_STATS_CHANGED,{player_id=0,changed_section="hero"})
near(stats(0).strength-before_growth,12*1.5*1.2*1.3*1.08,"future research receives EX")
local stable=stats(0)
for index=1,100 do profile_changed(0,"online_checkpoint") end
assert(stats(0)==stable,"unchanged profile checkpoints must not recalculate hero stats")
assert(stats(1)==other_before,"growth and profile updates remain player isolated")

local config=require("combat/damage_rule_config")
local repository=require("combat/damage_transaction_repository")
local filter=require("combat/damage_filter_service")
repository.init(config);filter.init({event_bus=bus,events=damage_events,repository=repository,config=config})
local victim=EntIndexToHScript(201)
victim.survival_endless_health_scale=1;victim.survival_building_id=nil
local function hit(attacker,category,kind)
    local keys={entindex_attacker_const=attacker:entindex(),entindex_victim_const=victim:entindex(),
        damage=100,damage_category_const=category,damagetype_const=kind or DAMAGE_TYPE_PURE}
    assert(filter._filter_for_test(filter,keys));return keys.damage
end
local normal=(1+.20+.15+.25+.10)
near(hit(hero,DOTA_DAMAGE_CATEGORY_SPELL),100*normal*1.08,"skill final damage EX is multiplicative")
near(hit(hero,DOTA_DAMAGE_CATEGORY_ATTACK),100*normal*1.08,"basic final damage EX is multiplicative")
near(hit(neighbor,DOTA_DAMAGE_CATEGORY_SPELL),100*normal,"unowned neighboring hero receives no EX")
local before_reads=reads
for index=1,200 do hit(hero,DOTA_DAMAGE_CATEGORY_SPELL) end
assert(reads==before_reads,"EX hot path cannot read profiles on every hit")
profiles[0].commerce_p147=0;profile_changed(0)
near(stats(0).commerce_ex_attribute_multiplier,1,"ownership removal recomputes even when normal stats unchanged")
near(hero.survival_commerce_hero_ex_damage_multiplier,1)
near(hit(hero,DOTA_DAMAGE_CATEGORY_SPELL),100*normal,"ownership removal clears cached damage EX")
output("P147_EX_PASS complete live stat sources; dynamic progression/weapon/research; static HUD; independent skill/basic damage; ownership changes; no per-hit profile reads; player isolation")

-- A new world boundary resets only match state, never stored inventory.
bus.reset();scheduler.clear()
local tables,active,draw_fail,draw_count={},{},false,0
CustomNetTables={SetTableValue=function(_,name,key,value)
    tables[name]=tables[name] or {};tables[name][key]=value
end}
profiles[0]={commerce_p147=1};profiles[1]={};profiles[2]={commerce_p147=1};profiles[3]={}
for id=0,3 do active[id]={} end
request(events.HERO_SKILL_STATE_GET_REQUEST,function(p)
    return {snapshot={hero_ready=active[p.player_id] and 1 or 0,hero_id="hero_shadow_fiend",
        public_skill_count=0,public_skill_capacity=3,skills={}}}
end)
request(events.HERO_SKILL_POOL_DRAW_REQUEST,function()
    draw_count=draw_count+1
    return draw_fail and {ok=false,error="simulated_draw_failure"}
        or {ok=true,candidates={{skill_id="proto_flame_burst"}}}
end)
request(events.HERO_SKILL_GRANT_REQUEST,function() return {ok=true} end)
local choices=require("systems/hero_skill_choice_service")
choices.init()
local function choice(id)
    return assert(bus.request(events.HERO_SKILL_CHOICE_GET_REQUEST,{player_id=id})).snapshot
end
local function offer(id)
    local result=bus.request(events.HERO_SKILL_CHOICE_CREATE_REQUEST,{player_id=id,trigger_level=2})
    assert(result and result.ok,result and result.error);return choice(id)
end
local function reroll(id)
    return bus.request(events.HERO_SKILL_CHOICE_SELECT_REQUEST,
        {player_id=id,choice_token=choice(id).choice_token,reroll=true})
end
near(choice(0).rerolls,5,"initial owner gets five even before a pending offer")
near(choice(1).rerolls,0);near(choice(2).rerolls,5);near(choice(3).rerolls,0)
local pure=require("systems/commerce_hero_privileges").for_player(3)
near(pure.attribute_multiplier,1);near(pure.final_damage_multiplier,1);near(pure.skill_rerolls,0)
assert(account_profiles[3].save.content_inventory.commerce_p147==1 and account_reads==0,
    "pure-mode EX and rerolls must use only mode-filtered match inventory, never account/UI ownership")
for index=1,100 do profile_changed(0,"reconnect_snapshot");choice(0) end
near(choice(0).rerolls,5,"reconnects and repeated reads never grant again")
offer(0)
for left=4,0,-1 do assert(reroll(0).ok);near(choice(0).rerolls,left) end
local empty=reroll(0);assert(not empty.ok and empty.error=="skill_reroll_empty")
local previous=offer(1)
profiles[1].commerce_p147=1;profile_changed(1,"mid_match_purchase")
near(choice(1).rerolls,5);assert(choice(1).choice_token==previous.choice_token,"purchase cannot replace pending options")
draw_fail=true;assert(not reroll(1).ok);near(choice(1).rerolls,5,"failed reroll never consumes a charge")
assert(choice(1).choice_token==previous.choice_token);draw_fail=false
assert(reroll(1).ok);near(choice(1).rerolls,4)
local old_hero=active[0]
bus.emit(events.HERO_REMOVED,{player_id=0,unit=old_hero});active[0]={}
bus.emit(events.HERO_SUMMONED,{player_id=0,unit=active[0]})
profile_changed(0,"reconnect_after_resummon")
near(choice(0).rerolls,0,"hero death/removal/replacement cannot restore spent charges")
near(choice(1).rerolls,4);near(choice(2).rerolls,5);near(choice(3).rerolls,0)
profiles[1].lottery_sky_turning_seal=1
bus.emit("commerce.skill_learned",{player_id=1})
near(choice(1).rerolls,5,"existing learned-skill privilege remains additive")
profiles[1].commerce_p147=0;profile_changed(1)
profiles[1].commerce_p147=1;profile_changed(1)
near(choice(1).rerolls,5,"ownership loss/regain in same match never reissues five")
bus.reset();scheduler.clear();choices.init()
near(choice(0).rerolls,5,"new match grants the initial five anew")
near(choice(1).rerolls,5);near(choice(2).rerolls,5);near(choice(3).rerolls,0)
output("P147_REROLLS_PASS four players; pure-mode account/match inventory isolation; start/mid-match ownership; five successful uses; failed draws; reconnect; resummon; existing bonuses; repeated snapshots; loss/regain; fresh match")
