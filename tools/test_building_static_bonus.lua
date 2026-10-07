package.path="scripts/vscripts/?.lua;"..package.path
local bus=require("core/event_bus")
local events=require("core/events")
local tick
package.loaded["core/scheduler"]={every=function(_,fn)tick=fn end}
local profile={mode="pure",save={gameplay_stats={tower_attack_flat=20,tower_attack_bonus_pct=10,
 tower_attack_per_second=2,tower_attack_pct_per_minute=3,tower_damage_attack_growth=4,tower_basic_attack_growth=5,
 wall_armor=6,wall_health_per_second=7,wall_armor_per_second=8},permanent_effects={},match_boss_effects={}}}
package.loaded["systems/player_profile_service"]={get_profile=function()return profile end}
require("systems/permanent_reward_effect_service").init()
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0})
local function snapshot()return bus.request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,{player_id=0})end
local before=snapshot()
for i=1,60 do tick() end
bus.emit(events.TOWER_ATTACK_LANDED,{tower={survival_player_id=0}})
local after=snapshot()
assert(after.totals.tower_attack_flat==149 and after.totals.tower_attack_bonus_pct==13)
assert(after.totals.wall_health_growth_flat==420 and after.totals.wall_armor_growth_flat==480)
assert(after.display_totals.tower_attack_flat==20 and after.display_totals.tower_attack_bonus_pct==10)
assert(after.display_totals.wall_armor==6 and after.display_totals.wall_health_growth_flat==nil)
local bonus=require("combat/building_display_bonus")
local a=bonus.tower(100,{},before.display_totals).attack_bonus
local b=bonus.tower(100,{},after.display_totals).attack_bonus
assert(math.abs(a-32)<.0001 and a==b)
local wall=bonus.wall(2000,10,{technology_health_bonus_pct=20,technology_armor_bonus=2},after.display_totals,100)
assert(wall.health_bonus==500 and wall.armor_bonus==12)
local display=require("ui/building_stat_display")
local requested={}
local tower={survival_building_id="arrow_tower",survival_level=1,survival_hud_base_attack=100,survival_hud_stat_bonuses={attack_bonus=32,attack_pct=10},
 FindModifierByName=function(_,name)requested[name]=true; if name=="modifier_rogue_base_tower_attack" then return {GetModifierBaseDamageOutgoing_Percentage=function()return 50 end} end end}
local result=display.apply(tower,{attack_max=99999})
assert(result.building_stat_details.attack_bonus==98 and math.abs(result.building_stat_details.attack_pct-65)<.0001)
assert(not requested.modifier_rogue_tower_growth and not requested.modifier_rogue_sharp_volley_growth,'wave/kill and hit growth must never enter fixed bonus')
print("BUILDING_STATIC_BONUS_PASS: real 60 ticks + attack/damage/minute growth remain in totals; static display unchanged; wall ticks excluded; fixed talent included; kill/hit modifiers excluded")

local flat_only=bonus.tower(72,{attack_flat=60.7},{})
assert(math.abs(flat_only.attack_bonus-60.7)<.0001 and flat_only.attack_pct==0, "flat bonuses must not masquerade as 84.3 percent")
