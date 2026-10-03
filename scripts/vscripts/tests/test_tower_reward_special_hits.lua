-- Appended after the existing production special-attack fixture and the former failing audit cases.
for _,r in ipairs(VIP_SPECIAL_AUDIT) do assert(r.ok,r.id..': '..r.actual..' expected '..r.expected) end
local function near(a,b)assert(math.abs(a-b)<.000001,tostring(a)..' expected '..b)end
local function private(fn,wanted,seen)
 seen=seen or {};if seen[fn] then return end;seen[fn]=true
 for i=1,100 do local n,v=debug.getupvalue(fn,i);if not n then break end;if n==wanted then return v end end
 for i=1,100 do local n,v=debug.getupvalue(fn,i);if not n then break end;if type(v)=='function' then local r=private(v,wanted,seen);if r~=nil then return r end end end
end
-- Feed the actual projectile hit into the production permanent-reward consumer.
local permanent=require('systems/permanent_reward_effect_service')
local original_value=permanent.value
permanent.value=function(_,key)return ({tower_damage_attack_growth=1.5,tower_attack_armor_reduction=.6})[key] or 0 end
local hit=assert(private(permanent.init,'on_tower_attack'))
local original_hit=subscribers[events.TOWER_ATTACK_LANDED]
subscribers[events.TOWER_ATTACK_LANDED]=function(payload)original_hit(payload);hit(payload)end
special.init() -- clear any charged critical skill state from earlier fixtures
subscribers[events.TOWER_ATTACK_LANDED]=function(payload)original_hit(payload);hit(payload)end
clear();m=modifier({burning});tower.survival_super_tower_crit_chance=0;tower.survival_tower_personal_attack_growth=0
m:OnAttackStart({attacker=tower,target=dummy});local extra=linear[1].ExtraData
special.on_burning_wave_projectile_hit(ability,dummy,nil,extra)
near(tower.survival_tower_personal_attack_growth,1.5);near(buffs[#buffs].options.armor_reduction_per_attack,.2)
local buffs_before=#buffs
special.on_burning_wave_projectile_hit(ability,dummy,nil,extra)
m:OnAttackLanded({attacker=tower,target=dummy,damage=0})
near(tower.survival_tower_personal_attack_growth,1.5);assert(#buffs==buffs_before)
special.on_burning_wave_projectile_hit(ability,second,nil,extra)
near(tower.survival_tower_personal_attack_growth,3);assert(#buffs==buffs_before+1)
assert(#linear==1 and count_event(events.TOWER_ATTACK_LANDED)==2,'hit must not relaunch projectile or duplicate native hit')
-- A rejected damage request never grants growth or reduction.
clear();m=modifier({burning});m:OnAttackStart({attacker=tower,target=dummy});extra=linear[1].ExtraData
local damage_service=package.loaded['combat/damage_service'];local saved_deal=damage_service.Deal
damage_service.Deal=function()return {success=false}end
special.on_burning_wave_projectile_hit(ability,dummy,nil,extra)
near(tower.survival_tower_personal_attack_growth,3);assert(count_event(events.TOWER_ATTACK_LANDED)==0 and #buffs==0)
damage_service.Deal=saved_deal;permanent.value=original_value;subscribers[events.TOWER_ATTACK_LANDED]=original_hit
print('PASS burning actual growth +1.5 and armor -.6 per successful unique hit; failed damage, duplicate and native callbacks grant nothing')
-- The native placeholder of replacement multi-arrow must not consume another crit roll.
clear();tower.survival_model_asset_id='tower_multi_medusa_anamnessa';m=modifier({{skill_id='multi_attack_lv01',max_targets=4,damage_multiplier=1}});m.current_attack_target=dummy
local before=count_request(events.TOWER_CRITICAL_QUERY);assert(m:GetModifierPreAttack_CriticalStrike()==0)
assert(count_request(events.TOWER_CRITICAL_QUERY)==before)
-- Continuous-beam frequency follows project-owned haste while ramp remains real-time.
clear();m=modifier({laser});tower.attack_target=dummy
now=100;tower.survival_research_base_attack_time=1;tower.survival_attack_interval=.5
m:OnAttackStart({attacker=tower,target=dummy});assert(#damage==1);near(damage[1].base_damage,100)
now=100.49;m:OnIntervalThink();assert(#damage==1)
now=100.5;m:OnIntervalThink();assert(#damage==2);near(damage[2].base_damage,100)
now=101;m:OnIntervalThink();assert(#damage==3);near(damage[3].base_damage,105)
now=102;m:OnIntervalThink();assert(#damage==5);near(damage[4].base_damage,105);near(damage[5].base_damage,110)
-- Refreshing attack-start on the same target must not add an immediate extra tick.
m:OnAttackStart({attacker=tower,target=dummy});assert(#damage==5)
tower.survival_attack_interval=1;now=102.5;m:OnIntervalThink();assert(#damage==5)
now=103;m:OnIntervalThink();assert(#damage==6);near(damage[6].base_damage,115)
dummy.alive=false;now=104;m:OnIntervalThink();assert(#damage==6 and m.laser_target==nil);dummy.alive=true
local interval=require('systems/tower_laser_damage').interval
tower.survival_attack_interval=1/1.1;near(interval(tower,laser),1/1.1)
tower.survival_attack_interval=1/1.15;near(interval(tower,laser),1/1.15)
tower.survival_research_base_attack_time=nil;tower.survival_attack_interval=nil;near(interval(tower,laser),1)
print('PASS laser +10%/+15%/+100% haste, delayed-frame catchup, time-based ramp, live haste removal, same-target refresh and dead-target stop')
