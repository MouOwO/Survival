package.path="scripts/vscripts/?.lua;"..package.path
-- Admission is exercised elsewhere; this fixture starts with admitted players.
package.loaded["core/test_access_policy"]={enabled=function() return false end}
local mode,frozen,defeated="rich",false,{}
local tasks,notices,snapshots={},{},{}
package.loaded["core/scheduler"]={cancel=function(k) tasks[k]=nil end,
    every=function(_,fn,k) tasks[k]=fn end}
package.loaded["systems/match_setup_service"]={get_mode=function() return mode end}
package.loaded["systems/gameplay_phase_guard"]={post_clear_frozen=function() return frozen end}
package.loaded["systems/player_context_service"]={is_defeated=function(id) return defeated[id] end}
package.loaded["systems/tree_damage_rules"]={is_allowed_tree_attacker=function() return true end}
package.loaded["systems/rogue_effect_state_service"]={numeric=function() return 0 end}
package.loaded["systems/harvest_feedback_service"]={reset=function() end,add=function() end}
package.loaded["core/particle_manager"]={show_green_number=function() end}
local stats={[0]={initial_wood=10,wood_per_second=3},[1]={initial_wood=10,wood_per_second=0}}
package.loaded["systems/player_profile_service"]={get_profile=function(id)
    return {save={gameplay_stats=stats[id]}}
end}
Vector=function(x,y,z) return {x=x,y=y,z=z or 0} end
PlayerResource={GetTeam=function() return 2 end,GetPlayer=function(_,id) return {id=id} end}
RandomFloat=function() return 99 end
local bus,events=require("core/event_bus"),require("core/events")
local tree_system=require("systems/tree_system")
local resources=require("systems/resource_system")
local config=require("config/tree_config")
local function entity(index)
    return {health=100,max=100,IsNull=function() return false end,entindex=function() return index end,
        HasModifier=function() return false end,SetPhysicalArmorBaseValue=function() end,
        SetBaseMaxHealth=function(self,h) self.max=h end,SetMaxHealth=function(self,h) self.max=h end,
        SetHealth=function(self,h) self.health=h end,GetHealth=function(self) return self.health end,
        GetMaxHealth=function(self) return self.max end}
end
local function balance(id) return assert(bus.request(events.RESOURCE_GET_REQUEST,{player_id=id})).wood end
local function tick(id) return assert(tasks["resource_income:"..id])() end
local function start(current_mode)
    mode=current_mode;frozen=false;defeated={};tasks={};notices={};snapshots={}
    bus.reset();resources.init();tree_system.init()
    bus.subscribe(events.UI_NOTIFICATION,function(p) notices[#notices+1]=p end)
    bus.subscribe(events.TREE_CHANGED,function(p) snapshots[p.player_id]=p end)
    for id=0,1 do bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=id}) end
end
start("rich")
local tree,other=entity(100),entity(101)
tree_system._reset_for_test(1,tree,0);tree_system._reset_for_test(1,other,1)
assert(balance(0)==10 and balance(1)==10)
tick(0);assert(balance(0)==13,"Lv1 retains only profile income")
tree_system._upgrade_tree_for_test(tree)
assert(snapshots[0].level==2 and snapshots[0].lumber_efficiency_buff==config.lumber_efficiency_buff_per_level+20)
assert(snapshots[0].rich_level2_wood_per_second==20)
assert(#notices==1 and notices[1].player_id==0 and notices[1].message:find("+20",1,true))
assert(not notices[1].audience,"reward notice belongs only to the owner")
tick(0);tick(1);assert(balance(0)==36 and balance(1)==10,"20/sec adds to profile income, never to teammates")
local before=balance(0)
local attacker=entity(200)
bus.emit(events.TREE_HIT,{target=other,attacker=attacker,player_id=0,
    source="lumberjack",base_lumber_efficiency=10,fusion_count=3})
assert(balance(0)-before==10+3*(config.lumber_efficiency_buff_per_level+20),
    "settlement uses the attacker's own reward and the existing fusion rule, even on another player's tree")
before=balance(1)
bus.emit(events.TREE_HIT,{target=tree,attacker=attacker,player_id=1,
    source="lumberjack",base_lumber_efficiency=10})
assert(balance(1)-before==10,"hitting an upgraded foreign tree cannot borrow its reward")
before=balance(0)
for _=1,8 do bus.emit(events.TREE_CHANGED,snapshots[0]) end
tree_system._upgrade_tree_for_test(tree)
assert(#notices==1 and snapshots[0].lumber_efficiency_buff==2*config.lumber_efficiency_buff_per_level+20)
stats[0].wood_per_second=5
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0})
bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED,{player_id=0,totals=stats[0]})
tick(0);assert(balance(0)-before==25,"duplicate snapshots, Lv3 and profile refresh cannot duplicate or erase the reward")
before=balance(0);frozen=true;tick(0);assert(balance(0)==before,"post-clear freeze still applies");frozen=false
-- A replacement Lv1 tree keeps the already earned match reward; no second prize.
local replacement=entity(102);tree_system._reset_for_test(1,replacement,0)
tree_system._upgrade_tree_for_test(replacement);tick(0)
assert(#notices==1 and balance(0)-before==25)
tree_system._reset_for_test(config.max_level,tree,0);tree_system._upgrade_tree_for_test(tree)
assert(#notices==1,"level-cap resets do not reward again")
tree_system._upgrade_tree_for_test(other)
assert(#notices==2 and notices[2].player_id==1)
before=balance(1);tick(1);assert(balance(1)-before==20,"each owner earns independently")
defeated[1]=true;before=balance(1);assert(tick(1)==false and balance(1)==before)
-- New match clears the reward. The saved profile remains untouched.
start("rich");tick(0);assert(balance(0)==15 and stats[0].lumberjack_efficiency==nil)
for _,other_mode in ipairs({"standard","pure","cold","scourge"}) do
    start(other_mode);tree_system._reset_for_test(1,tree,0);tree_system._upgrade_tree_for_test(tree)
    assert(snapshots[0].lumber_efficiency_buff==config.lumber_efficiency_buff_per_level)
    assert(snapshots[0].rich_level2_wood_per_second==0 and #notices==0)
    before=balance(0);tick(0);assert(balance(0)-before==5,"other modes retain their existing income")
end
-- Late profile admission starts income without losing an already earned reward.
mode="rich";tasks={};bus.reset();resources.init();tree_system.init()
tree_system._reset_for_test(1,tree,0);tree_system._upgrade_tree_for_test(tree)
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0});tick(0)
assert(balance(0)==35,"late profile initialization keeps the pending match income")
print("RICH_TREE_LEVEL2_REWARD_PASS: one match-only +20/+20 owner reward, harvest/fusion, foreign-tree isolation, profile refresh, replacement/cap replay, independent owners, reset/mode/freeze/defeat guards")
