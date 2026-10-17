package.path='scripts/vscripts/?.lua;'..package.path
local bus=require('core/event_bus');local events=require('core/events')
local tasks,after={},{}
package.loaded['core/scheduler']={every=function(delay,fn,id)
    assert(delay==1);tasks[id]=fn;return id
end,cancel=function(id) tasks[id]=nil end,
after=function(delay,fn,id) assert(delay==0);after[id]=fn end}
local current_world={};local inventory,heroes,builders,defeated={},{},{},{}
local active={0,1,2,3};local additions,destructions,lookups=0,0,0
GameRules={GetGameModeEntity=function() return current_world end,GetGameTime=function() return 10 end}
LinkLuaModifier=function(name,path) assert(path=='modifiers/modifier_commerce_titan_aura') end
LUA_MODIFIER_MOTION_NONE=0
package.loaded['systems/player_profile_service']={get_content_inventory_count=function(id,item)
    lookups=lookups+1;return (inventory[id] or {})[item] or 0
end}
package.loaded['systems/player_context_service']={is_defeated=function(id) return defeated[id] end,
    active_player_ids=function() return active end}
FindUnitsInRadius=function() error('Titan service must use native aura, no Lua spatial scans') end
local function unit(index,player,team)
    local u={index=index,survival_player_id=player,team=team or 2,alive=true,mods={}}
    function u:IsNull() return false end
    function u:IsAlive() return self.alive end
    function u:entindex() return self.index end
    function u:GetTeamNumber() return self.team end
    function u:FindModifierByName(name) return self.mods[name] end
    function u:AddNewModifier(caster,ability,name,params)
        assert(caster==self and ability==nil and name=='modifier_commerce_titan_aura')
        additions=additions+1
        local m={parent=self}
        function m:IsNull() return self.destroyed==true end
        function m:Destroy()
            assert(not self.destroyed);self.destroyed=true;destructions=destructions+1
            if u.mods[name]==self then u.mods[name]=nil end
        end
        self.mods[name]=m;return m
    end
    return u
end
for id=0,3 do builders[id]=unit(100+id,id) end
heroes[2]=unit(202,2)
bus.handle_request(events.HERO_SUMMON_GET_REQUEST,function(p) return {unit=heroes[p.player_id]} end)
bus.handle_request(events.BUILDER_GET_REQUEST,function(p) return {builder=builders[p.player_id]} end)
inventory[0]={commerce_p016=1};inventory[2]={commerce_p016=1}
local service=require('systems/commerce_titan_aura_service')
assert(service.init());local tick=assert(tasks.commerce_titan_aura)
assert(tick() and additions==2 and destructions==0)
assert(builders[0].mods.modifier_commerce_titan_aura and heroes[2].mods.modifier_commerce_titan_aura)
assert(not builders[1].mods.modifier_commerce_titan_aura and not builders[3].mods.modifier_commerce_titan_aura)
assert(lookups==4,'one entitlement lookup per active owner per second')
for _=1,20 do assert(tick()) end
assert(additions==2 and destructions==0,'stable sources reuse their modifiers')
heroes[0]=unit(200,0);bus.emit(events.HERO_SUMMONED,{player_id=0,unit=heroes[0]})
assert(additions==3 and destructions==1 and not builders[0].mods.modifier_commerce_titan_aura)
local h0=heroes[0];heroes[0]=nil
bus.emit(events.HERO_REMOVED,{player_id=0,unit=h0})
assert(additions==4 and destructions==2 and builders[0].mods.modifier_commerce_titan_aura)
-- An identity mismatch must not put one player's privilege on another hero.
heroes[0]=heroes[2];tick()
assert(additions==4 and not heroes[2].mods.modifier_commerce_titan_aura:IsNull())
inventory[2]={};bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=2})
assert(destructions==3 and not heroes[2].mods.modifier_commerce_titan_aura)
defeated[0]=true;bus.emit(events.PLAYER_DEFEATED,{player_id=0})
assert(destructions==4 and not builders[0].mods.modifier_commerce_titan_aura)
defeated[0]=false;heroes[0]=nil;tick();assert(additions==5)
local old_tick=tick
assert(service.init());assert(destructions==5 and old_tick()==false)
tick=tasks.commerce_titan_aura;tick();assert(additions==6)
current_world={};assert(service.init())
assert(destructions==5,'old-world handles must never be destroyed in a new world')
assert(tick()==false,'old world polling cannot bind sources')
tick=tasks.commerce_titan_aura;tick();assert(additions==6,'new initialization adopts same valid native source, not duplicates')
active={1,2,3};tick();assert(destructions==6,'disconnected owner source released')

class=function(t) return t end
IsServer=function() return true end
DOTA_UNIT_TARGET_TEAM_BOTH=3;DOTA_UNIT_TARGET_HERO=1;DOTA_UNIT_TARGET_BASIC=2;DOTA_UNIT_TARGET_BUILDING=4
DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES=16
MODIFIER_PROPERTY_PHYSICAL_ARMOR_BONUS=1;MODIFIER_PROPERTY_HEALTH_REGEN_CONSTANT=2
require('modifiers/modifier_commerce_titan_aura')
local values=require('systems/commerce_titan_aura_values')
local armor=require('config/armor_balance')
local aura=setmetatable({},{__index=modifier_commerce_titan_aura})
function aura:GetParent() return builders[0] end
assert(aura:IsAura() and aura:GetAuraRadius()==2000 and aura:GetAuraDuration()==0.5)
assert(aura:GetAuraSearchType()==7 and aura:GetAuraSearchTeam()==3)
assert(aura:GetModifierAura()=='modifier_commerce_titan_aura_effect')
local tree=unit(900,0,3);tree.survival_tree_owner_id=0
assert(aura:GetAuraEntityReject(tree),'resource trees must not receive enemy debuff')
tree.survival_tree_owner_id=nil;tree.survival_visual_only=true
assert(aura:GetAuraEntityReject(tree))
tree.survival_visual_only=false;assert(not aura:GetAuraEntityReject(tree))
builders[0].alive=false;assert(not aura:IsAura());builders[0].alive=true
local changes=0
bus.subscribe(events.UNIT_COMBAT_STATS_CHANGED,function(p)
    assert(p.reason=='commerce_titan_armor_changed');changes=changes+1
end)
local function flush()
    local pending=after;after={};for _,fn in pairs(pending) do fn() end
end
local function buff(parent,caster)
    local b=setmetatable({stack=0},{__index=modifier_commerce_titan_aura_effect})
    function b:GetParent() return parent end
    function b:GetCaster() return caster end
    function b:SetStackCount(s) self.stack=s end
    function b:GetStackCount() return self.stack end
    b:OnCreated();return b
end
local friend=unit(1000,1,2);local enemy=unit(1001,nil,3)
local friendly1=buff(friend,builders[0]);flush()
assert(values.bonus(friend)==100 and friendly1:GetModifierConstantHealthRegen()==1000)
assert(friendly1:GetModifierPhysicalArmorBonus()==armor.from_war3_linear(100))
assert(not friendly1:IsDebuff() and changes==1)
local friendly2=buff(friend,heroes[2]);flush()
assert(friendly1:GetModifierConstantHealthRegen()+friendly2:GetModifierConstantHealthRegen()==1000)
assert(friendly1:GetModifierPhysicalArmorBonus()+friendly2:GetModifierPhysicalArmorBonus()==armor.from_war3_linear(100))
assert(changes==1 and values.bonus(friend)==100,'overlapping owners must not stack or repaint UI')
friendly1:OnRefresh();flush();assert(changes==1)
friendly1:OnDestroy();flush()
assert(friendly2:GetModifierConstantHealthRegen()==1000 and values.bonus(friend)==100 and changes==1)
friendly2:OnDestroy();flush();assert(values.bonus(friend)==0 and changes==2)
local enemy1=buff(enemy,builders[0]);local enemy2=buff(enemy,heroes[2]);flush()
assert(enemy1:IsDebuff() and enemy1:GetModifierConstantHealthRegen()==0)
assert(values.bonus(enemy)==-30)
assert(enemy1:GetModifierPhysicalArmorBonus()+enemy2:GetModifierPhysicalArmorBonus()==armor.from_war3_linear(-30))
enemy.survival_effective_war3_armor=117
assert(values.custom_armor(enemy)==87 and enemy.survival_effective_war3_armor==117)
-- A permanent research refresh replaces its own baseline while the aura stays
-- effective. Exit restores only this temporary layer, without refunding research.
enemy.survival_effective_war3_armor=80;assert(values.custom_armor(enemy)==50)
enemy1:OnDestroy();assert(values.custom_armor(enemy)==50)
enemy2:OnDestroy();assert(values.custom_armor(enemy)==80)
friend.survival_commerce_titan_armor=100
local raw={armor=50,attack_min=200}
local ui=values.for_ui(raw,friend);assert(ui.armor==150 and raw.armor==50)
assert(values.for_ui(ui,friend).armor==150,'UI projection must be idempotent')
friend.survival_commerce_titan_armor=nil
assert(values.for_ui(ui,friend).armor==50,'leaving aura restores projected armor')
-- Exercise the real custom War3 DamageFilter, not only a display field.
DAMAGE_TYPE_PHYSICAL=1;DAMAGE_TYPE_MAGICAL=2;DOTA_DAMAGE_FLAG_IGNORES_PHYSICAL_ARMOR=512
package.loaded['systems/tree_damage_rules']={is_tree=function() return false end,
    is_allowed_tree_attacker=function() return true end,is_arrow_tower=function() return false end,
    is_lumberjack=function() return false end,is_basic_attack_category=function() return false end,
    consume_basic_attack=function() return false end,allows_damage=function() return true end,
    reset_pending_attacks=function() end}
package.loaded['systems/anti_air_rules']={can_attack=function() return true end,has_damage_taken_aura=function() return false end}
package.loaded['config/generated/global_rules']={by_id={}}
package.loaded['systems/rogue_effect_state_service']={numeric=function() return 0 end,has_effect=function() return false end}
package.loaded['combat/damage_filter_service']=nil
local filter=require('combat/damage_filter_service')
local attacker=unit(2000,0,2)
function attacker:HasModifier() return false end
function enemy:HasModifier() return false end
function enemy:GetHealth() return 20000 end
function enemy:GetMaxHealth() return 20000 end
enemy.survival_war3_armor_target=true
enemy.survival_armor_mapping_version=armor.CUSTOM_WAR3_MAPPING_VERSION
enemy.survival_effective_war3_armor=117
EntIndexToHScript=function(i) return i==2000 and attacker or enemy end
filter.init({event_bus={emit=function() end},events={DAMAGE_BLOCKED='b',DAMAGE_FILTERED='f',DAMAGE_RESOLVED='r'},
    repository={consume_pending=function() end},config={global_post_bonus_pct=0,minimum_post_multiplier=0,
    boss_rules={enabled=false}}})
local function damage(ty)
    local k={damage=801,damagetype_const=ty or 1,entindex_attacker_const=2000,entindex_victim_const=1001,damage_flags=0}
    assert(filter._filter_for_test(nil,k));return k.damage
end
local function near(a,b) assert(math.abs(a-b)<0.00001,tostring(a)..' vs '..tostring(b)) end
near(damage(),801/3.34)
local reduction=buff(enemy,builders[0])
near(damage(),801/2.74);near(damage(2),801)
reduction:OnDestroy();near(damage(),801/3.34)
enemy.survival_commerce_titan_armor=100;near(damage(),801/5.34)
enemy.survival_commerce_titan_armor=nil
print('TITAN_AURA_PASS: 4-player source identity, live purchase/revoke, reuse, world reset, native radius/types, non-stacking armor/regen, removal, immutable UI projection and real custom-War3 damage')
