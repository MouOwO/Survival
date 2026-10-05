package.path="scripts/vscripts/?.lua;"..package.path
GameRules={GetGameTime=function() return 0 end}
IsServer=function() return true end
class=function(value) return value end
local bus=require("core/event_bus")
local events=require("core/events")
local scheduler=require("core/scheduler")
local balance=require("config/armor_balance")
local rule=require("config/generated/global_rules").by_id.runtime_detailed_diagnostics
assert(tonumber(rule.value)==0,"detailed combat diagnostics are disabled by default")
local profile={mode="pure",revision=1,entitlements={},save={
    gameplay_stats={hero_attack_armor_reduction=25,global_attack_armor_reduction=15,hero_attack_armor_reduction_pct=10},
    permanent_effects={},archive={boss_kills=0},match_boss_effects={}}}
for i=1,2000 do profile.save.permanent_effects["unrelated_"..i]=i end
package.loaded["systems/player_profile_service"]={get_profile=function() return profile end}
local effects=require("systems/permanent_reward_effect_service")
effects.init();bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0})
local function query(narrow)
    return bus.request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,{player_id=0,armor_reduction_only=narrow})
end
local full,narrow=query(false),query(true)
for _,field in ipairs({"hero_attack_armor_reduction","global_attack_armor_reduction","hero_attack_armor_reduction_pct"}) do
    assert(narrow.totals[field]==full.totals[field])
end
assert(narrow.test_isolation==full.test_isolation and narrow.totals.unrelated_1==nil)
narrow.totals.hero_attack_armor_reduction=999
assert(query(true).totals.hero_attack_armor_reduction==25,"request snapshots cannot mutate authority")
local original_pairs=pairs
local visits=0
pairs=function(value)
    local iterator,state,first=original_pairs(value)
    return function(s,k)
        local key,item=iterator(s,k)
        if key~=nil then visits=visits+1 end
        return key,item
    end,state,first
end
for i=1,100 do query(false) end
local full_visits=visits;visits=0
for i=1,100 do query(true) end
local narrow_visits=visits;pairs=original_pairs
assert(full_visits>=200000 and narrow_visits==0)
profile.save.gameplay_stats.hero_attack_armor_reduction=30
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0})
assert(query(true).totals.hero_attack_armor_reduction==30,"updates cannot leave a cached armor value")
assert(effects.set_test_isolation(0,"hero_attack_armor_reduction"))
assert(query(true).test_isolation and query(true).totals.hero_attack_armor_reduction==30)
assert(query(true).totals.global_attack_armor_reduction==nil)
assert(effects.clear_test_isolation(0))

local technology=0
package.loaded["systems/technology_stat_manager"]={get=function()
    return {final={hero={armor_reduction_per_attack=technology}}}
end}
local attacker={IsNull=function() return false end,entindex=function() return 933 end,GetTeamNumber=function() return 2 end}
local applied,armor_queries=0,0
local target={survival_effective_war3_armor=100,
    IsNull=function() return false end,entindex=function() return 626 end,GetTeamNumber=function() return 3 end,
    GetPhysicalArmorValue=function() armor_queries=armor_queries+1;return 100 end,
    AddNewModifier=function(_,_,_,name,params)
        assert(name=="modifier_research_armor_reduction")
        applied=applied+1
        assert(math.abs(params.armor_reduction_per_attack-(technology+balance.from_war3_linear(55)))<0.00001)
        return {GetStackCount=function() return 1 end}
    end}
local original_print=print;local logs={}
print=function(line) logs[#logs+1]=line end
local research=require("systems/research_armor_reduction_service")
research.init()
technology=3
for i=1,100 do research._test.on_main_attack_landed({player_id=0,attacker=attacker,target=target,attack_id=i}) end
research._test.on_main_attack_landed({player_id=0,attacker=attacker,target=target,attack_id=100})
assert(applied==100 and armor_queries==0 and #logs==0,"keep exact attack effects/dedup without native diagnostic reads or prints")
-- No technology or permanent effects: zero reduction is a normal silent skip.
profile.save.gameplay_stats={};technology=0
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0});logs={}
research._test.on_main_attack_landed({player_id=0,attacker=attacker,target=target,attack_id=101})
assert(applied==100 and #logs==0)
local original_add=target.AddNewModifier
target.AddNewModifier=function() return nil end;technology=3
research._test.on_main_attack_landed({player_id=0,attacker=attacker,target=target,attack_id=102})
assert(armor_queries==1 and #logs==1 and logs[1]:find("RESEARCH_ARMOR_APPLY_FAILED",1,true)
    and logs[1]:find("armor_before=100",1,true),"failures retain useful native armor details")
target.AddNewModifier=original_add;technology=0;logs={}

-- Fifty armor changes are applied immediately, with one final UI publication.
scheduler.clear()
require("modifiers/modifier_research_technology")
local parent={survival_armor_mapping_version=balance.CUSTOM_WAR3_MAPPING_VERSION,survival_war3_armor=100,
    IsNull=function(self) return self.removed==true end,entindex=function() return 626 end,
    GetPhysicalArmorValue=function() error("mapped armor must not fetch native armor for quiet diagnostic output") end}
local modifier=setmetatable({stack=0},{__index=modifier_research_armor_reduction})
function modifier:GetParent() return parent end
function modifier:GetStackCount() return self.stack end
function modifier:SetStackCount(value) self.stack=value end
local publications=0
bus.subscribe(events.UNIT_COMBAT_STATS_CHANGED,function(payload)
    publications=publications+1
    assert(payload.unit==parent and payload.research_armor_reduction==50)
end)
modifier:OnCreated({armor_reduction_per_attack=balance.from_war3_linear(1),diagnostic_hit=1})
for i=2,50 do modifier:OnRefresh({armor_reduction_per_attack=balance.from_war3_linear(1),diagnostic_hit=i}) end
assert(parent.survival_war3_armor_reduction==50 and scheduler.task_count()==1 and publications==0)
scheduler.think();assert(publications==1 and #logs==0)
modifier:OnRefresh({armor_reduction_per_attack=balance.from_war3_linear(1)})
parent.removed=true;scheduler.think();assert(publications==1,"dead target cannot publish a stale update")

-- Detailed-log gating keeps damage numbers, critical state and dedup unchanged.
DOTA_DAMAGE_CATEGORY_ATTACK=1;OVERHEAD_ALERT_CRITICAL=3;OVERHEAD_ALERT_BONUS_SPELL_DAMAGE=4
PlayerResource={GetPlayer=function() return "player" end}
RandomFloat=function() return 0 end
local damage_numbers={}
SendOverheadEventMessage=function(_,style,victim,damage) damage_numbers[#damage_numbers+1]={style=style,victim=victim,damage=damage} end
local damage_target={IsNull=function() return false end,entindex=function() return 627 end}
local function damage_case(enabled,record)
    rule.value=enabled and 1 or 0
    package.loaded["modifiers/modifier_weapon_stat_projection"]=nil
    require("modifiers/modifier_weapon_stat_projection")
    local projection=modifier_weapon_stat_projection
    assert(projection.RollCriticalAttackRecord(record,{critical_chance_pct=100,critical_damage_pct=200},attacker)==200)
    assert(projection.ShowFinalAttackDamage(0,attacker,damage_target,{damage=479,record=record,damage_category=1}))
    assert(not projection.ShowFinalAttackDamage(0,attacker,damage_target,{damage=479,record=record,damage_category=1}))
    projection.ClearCriticalAttackRecord(attacker,record)
end
logs={};damage_case(false,1);assert(#logs==0 and #damage_numbers==1)
damage_case(true,2);assert(#logs>0 and #damage_numbers==2)
assert(damage_numbers[1].damage==479 and damage_numbers[2].damage==479
    and damage_numbers[1].style==3 and damage_numbers[2].style==3)
rule.value=0;print=original_print
print(string.format("ATTACK_HOT_PATH_PASS 100 queries full_visits=%d narrow_visits=%d; current stats/isolation/dedup; 100 unchanged armor hits; 50 hits/one UI update; unchanged quiet/debug critical numbers",full_visits,narrow_visits))
