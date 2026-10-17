-- Native-instance boundaries are modeled; real rogue numeric effects, hero
-- attack projection, lifesteal scaling and health guard are exercised.
package.path='scripts/vscripts/?.lua;'..package.path
class=function(base) base.__index=base;return base end
local server,tools,mode=true,true,{}
IsServer=function() return server end;IsInToolsMode=function() return tools end
GameRules={GetGameModeEntity=function() return mode end}
MODIFIER_PROPERTY_BASEDAMAGEOUTGOING_PERCENTAGE=101
MODIFIER_PROPERTY_PREATTACK_BONUS_DAMAGE=102
MODIFIER_EVENT_ON_TAKEDAMAGE=103
DOTA_DAMAGE_CATEGORY_ATTACK=1
local bus,events=require('core/event_bus'),require('core/events')
local effects=require('systems/rogue_effect_state_service')
local guard={mode=mode};_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION=guard
local rows,query_count={},0
package.loaded['systems/player_context_service']={is_owned_by=function(id,u) return (u.context_id or u.survival_player_id)==id end}
local serial=0
local function unit(id,hero,kind)
    serial=serial+1
    local u={index=serial,survival_player_id=id,survival_building_id=kind,native_id=-1,hero=hero,
        team=2,health=100,healed=0,survival_endless_health_scale=2,survival_endless_attack_scale=2}
    function u:IsNull() return false end;function u:IsRealHero() return self.hero end
    function u:GetClassname() return self.hero and 'npc_dota_hero' or 'npc_dota_creature' end
    function u:GetPlayerOwnerID() return self.native_id end;function u:entindex() return self.index end
    function u:GetTeamNumber() return self.team end;function u:Heal(amount) self.health=self.health+amount;self.healed=self.healed+amount end
    function u:GetAverageTrueAttackDamage() return 1000 end
    rows[u.index]={unit=u,building_id=kind,player_id=id};return u
end
local summoned=unit(0,true)
summoned.survival_endless_attack_scale=4
bus.handle_request(events.BUILDING_QUERY_REQUEST,function(p) query_count=query_count+1;return rows[p.entindex] end)
bus.handle_request(events.HERO_SUMMON_GET_REQUEST,function() return {ok=true,unit=summoned} end)
effects.set_numeric(0,'unit_attack_bonus_pct',30)
effects.set_numeric(0,'tower_hero_attack_projection_pct',25)
effects.set_numeric(0,'hero_lifesteal_pct',50)
require('modifiers/modifier_rogue_combat_effects')
local C=modifier_rogue_combat_bonus
local function instance(u,created)
    local m=setmetatable({parent=u},{__index=C})
    function m:GetParent() return self.parent end
    if created~=false then m:OnCreated({player_id=u.survival_player_id}) end
    return m
end
local function declared(m,event)
    local list=m:DeclareFunctions()
    assert(list[1]==101 and list[2]==102,'Both native damage properties retain order/value on every side and role')
    assert(#list==(event and 3 or 2));assert((list[3]==103)==event)
    return list
end
local function enable()
    _G.SURVIVAL_ROGUE_COMBAT_DAMAGE_DECL_PROBE={enabled=true,mode=mode,guard=guard}
end
declared(C,true)
assert(C.survival_rogue_damage_decl_sampled==nil,'Class-level introspection must not poison future instance sampling')
_G.SURVIVAL_ROGUE_COMBAT_DAMAGE_DECL_PROBE=nil
local before=query_count
local default=instance(unit(0,false,'arrow_tower'));declared(default,true)
assert(query_count==before and default.survival_rogue_damage_decl_reason=='probe_disabled_at_creation','Default production adds no registration reads or changes to legacy event list')
enable();declared(default,true)
assert(not default.survival_rogue_damage_decl_omitted,'Enabling cannot resample an existing instance')
local tower=unit(0,false,'arrow_tower');local candidate=instance(tower);declared(candidate,false)
assert(candidate.survival_rogue_damage_decl_reason=='tools_formal_nonhero_arrow_tower')
assert(candidate:GetModifierBaseDamageOutgoing_Percentage()==30 and candidate:GetModifierPreAttack_BonusDamage()==500,'All real tower projections stay identical with the candidate')
local old=instance(unit(0,false,'arrow_tower'),false);declared(old,true)
old:OnCreated({player_id=0});declared(old,true)
assert(old.survival_rogue_damage_decl_reason=='declaration_before_creation_or_legacy_instance','Early native declarations lock legacy instead of changing cached callbacks later')
_G.SURVIVAL_ROGUE_COMBAT_DAMAGE_DECL_PROBE.enabled=false;declared(candidate,false)
assert(candidate:GetModifierBaseDamageOutgoing_Percentage()==30 and candidate:GetModifierPreAttack_BonusDamage()==500)
enable();local hero=unit(0,true);hero.native_id=0;local hero_modifier=instance(hero);declared(hero_modifier,true)
local victim=unit(99,false);victim.team=3;victim.survival_endless_health_scale=5
hero_modifier:OnTakeDamage({attacker=hero,unit=victim,damage_category=1,damage=200})
assert(hero.healed==250,'Real hero attack lifesteal must preserve native-to-logical-to-attacker health scaling')
hero_modifier:OnTakeDamage({attacker=hero,unit=victim,damage_category=0,damage=200})
hero_modifier:OnTakeDamage({attacker=unit(0,true),unit=victim,damage_category=1,damage=200})
local ally=unit(0,false)
hero_modifier:OnTakeDamage({attacker=hero,unit=ally,damage_category=1,damage=200})
assert(hero.healed==250,'Spell, foreign-attacker and friendly damage cannot acquire new lifesteal')
local enemy_heal_before=tower.healed
candidate:OnTakeDamage({attacker=tower,unit=victim,damage_category=1,damage=200})
assert(tower.healed==enemy_heal_before,'The omitted nonhero callback genuinely has no gameplay heal effect')
-- A role/registration failure is always legacy, never a best-guess omission.
local rejects={
    function(u) u.survival_building_id='wall' end,
    function(u) u.survival_player_id=1 end,
    function(u) u.native_id=1 end,
    function(u) u.context_id=1 end,
    function(u) rows[u.index].unit=unit(0,false,'arrow_tower') end,
    function(u) rows[u.index].player_id=1 end,
    function(u) rows[u.index].building_id='main_city' end,
    function(u) rows[u.index]=nil end,
    function(u) u.IsRealHero=function() error('unknown native role') end end,
    function(u) u.IsRealHero=function() return nil end end,
    function(u) u.GetClassname=function() return 'unknown_creature' end end,
}
for _,change in ipairs(rejects) do
    local u=unit(0,false,'arrow_tower');change(u)
    local m=instance(u,false);m:OnCreated({player_id=0});declared(m,true)
end
local initial_hero=instance(unit(0,true));initial_hero.parent.hero=false
initial_hero.parent.survival_building_id='arrow_tower';declared(initial_hero,true)
assert(not initial_hero.survival_rogue_damage_decl_omitted,'An initially heroic role cannot be reclassified by later model/flags')
local initial_tower=candidate;initial_tower.parent.survival_building_id='wall';declared(initial_tower,false)
assert(initial_tower.survival_rogue_damage_decl_omitted,'A sampled instance never mutates its native declaration when Lua identity changes')
enable();tools=false;local non_tools=instance(unit(0,false,'arrow_tower'));declared(non_tools,true);tools=true
server=false;local client=instance(unit(0,false,'arrow_tower'));declared(client,true)
assert(client:GetModifierBaseDamageOutgoing_Percentage()==30 and client:GetModifierPreAttack_BonusDamage()==500,'Client and server property values are identical; only the server event candidate differs')
server=true;enable();_G.SURVIVAL_ROGUE_COMBAT_DAMAGE_DECL_PROBE.mode={};declared(instance(unit(0,false,'arrow_tower')),true)
enable();_G.SURVIVAL_ROGUE_COMBAT_DAMAGE_DECL_PROBE.guard={mode=mode};declared(instance(unit(0,false,'arrow_tower')),true)
enable();mode={};declared(instance(unit(0,false,'arrow_tower')),true)
print('ROGUE_DAMAGE_DECL_PROBE_PASS: default legacy/no reads; creation-only sampling; both property callbacks/scales; real hero attack lifesteal; spell/ally/other-attacker rejection; native/formal/context role guards; client properties; early-declaration fallback; no live resampling')
