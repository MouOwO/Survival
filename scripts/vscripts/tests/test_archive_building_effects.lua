package.path="scripts/vscripts/?.lua;"..package.path
local bus=require("core/event_bus")
local events=require("core/events")
local guard=require("systems/gameplay_phase_guard")
local tick
package.loaded["core/scheduler"]={every=function(_,fn) tick=fn end}
local profile={revision=1,save={gameplay_stats={hero_attack_pct_per_minute=5,
    tower_attack_pct_per_minute=5,hero_attributes_pct_per_minute=10,wall_wave_boss_stun_seconds=10}}}
package.loaded["systems/player_profile_service"]={get_profile=function()return profile end}
local effects=require("systems/permanent_reward_effect_service")
effects.init()
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0})
local function totals()return bus.request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,{player_id=0}).totals end
for i=1,59 do tick() end
assert(totals().hero_attack_bonus_pct==0)
tick()
assert(totals().hero_attack_bonus_pct==5 and totals().tower_attack_bonus_pct==5)
assert(totals().hero_attribute_bonus_pct==10)
for i=1,60 do tick() end
assert(totals().hero_attack_bonus_pct==10 and totals().hero_attribute_bonus_pct==20)
guard.set_post_clear_frozen(true)
for i=1,60 do tick() end
assert(totals().hero_attack_bonus_pct==10, "post-clear growth frozen")
guard.set_post_clear_frozen(false)
package.loaded["core/event_bus"]=nil
package.loaded["systems/permanent_reward_effect_service"]=nil
bus=require("core/event_bus")
effects=require("systems/permanent_reward_effect_service")
effects.init()
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0})
assert(totals().hero_attack_bonus_pct==0, "match-local growth resets")
class=function()return {} end
IsServer=function()return true end
MODIFIER_EVENT_ON_ATTACK_LANDED=1
require("modifiers/modifier_enemy_wall_ai")
local stun_count=0
local boss={survival_is_wave_monster=true,survival_is_boss=true}
boss.AddNewModifier=function(_,caster,ability,name,args)
    assert(name=="modifier_stunned" and args.duration==10);stun_count=stun_count+1
end
local wall={survival_player_id=0,IsNull=function()return false end,entindex=function()return 10 end}
local modifier=setmetatable({wall_entindex=10,GetParent=function()return boss end},{__index=modifier_enemy_wall_ai})
modifier:OnAttackLanded({attacker=boss,target=wall})
assert(stun_count==1)
boss.survival_is_wave_monster=false
modifier:OnAttackLanded({attacker=boss,target=wall})
assert(stun_count==1,"challenge bosses excluded")
boss.survival_is_wave_monster=true;boss.survival_is_boss=false
modifier:OnAttackLanded({attacker=boss,target=wall})
assert(stun_count==1,"normal enemies excluded")
boss.survival_is_boss=true;modifier.wall_entindex=11
modifier:OnAttackLanded({attacker=boss,target=wall})
assert(stun_count==1,"only attacks on the assigned wall trigger")
print("ARCHIVE_BUILDING_EFFECTS_PASS")
