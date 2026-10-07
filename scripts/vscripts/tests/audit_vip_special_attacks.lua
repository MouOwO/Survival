-- Append to test_tower_skill_tree_exclusion.lua to reuse real special attack entry points.
VIP_SPECIAL_AUDIT={}
local function record(id,actual,expected,detail)
 VIP_SPECIAL_AUDIT[#VIP_SPECIAL_AUDIT+1]={id=id,actual=actual,expected=expected,ok=math.abs(actual-expected)<.0001,detail=detail}
end
RandomFloat=function()return 0 end
clear();m=modifier({})
tower.survival_super_tower_crit_chance=100;tower.survival_gameplay_critical_damage_pct=200
m.current_attack_target=dummy
record('normal_tower_crit',m:GetModifierPreAttack_CriticalStrike(),200,'ordinary attacks respond to 100% crit')
clear();m=modifier({{skill_id='machine_gun_lv01',barrage_interval=.1,max_targets=1}})
assert(effects._fire_machine_gun_hit_for_test(m,tower,dummy,1))
record('machine_gun_crit',damage[1].base_damage,200,'machine-gun script damage rolls crit before damage service')
clear();m=modifier({burning})
m:OnAttackStart({attacker=tower,target=dummy});assert(#linear==1)
local extra=linear[1].ExtraData
special.on_burning_wave_projectile_hit(ability,dummy,nil,extra)
m:OnAttackLanded({attacker=tower,target=dummy,damage=0})
record('burning_arrow_crit',damage[1].base_damage,648,'100% crit: base 100 * skill 3.24 deals 648')
record('burning_arrow_growth_armor_event',count_event(events.TOWER_ATTACK_LANDED),1,'one real giant-arrow hit emits one growth/armor event')
clear();m=modifier({laser})
effects._deal_laser_tick_for_test(m,tower,dummy,laser,beam)
record('laser_tick_crit',damage[1].base_damage,200,'100% tower crit applies to laser script tick')
local function multi_damage(chance)
 clear();tower.survival_super_tower_crit_chance=chance
 m=modifier({{skill_id='multi_attack_lv01',max_targets=4,damage_multiplier=1}})
 candidates={dummy,second};m:OnAttack({attacker=tower,target=dummy});drain()
 assert(#damage>0);return damage[1].base_damage
end
local multi_base=multi_damage(0)
record('multi_arrow_crit',multi_damage(100),multi_base*2,'same replacement arrow: 0% and 100% critical chance produce base and double damage')
print('VIP_SPECIAL_ATTACK_AUDIT_COMPLETE')
