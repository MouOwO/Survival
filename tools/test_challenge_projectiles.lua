-- Exercise the production challenge spawn with real member/archetype/profile
-- data; the shared melee combat template must not win over ranged presentation.
package.path='scripts/vscripts/?.lua;'..package.path
arg=arg or {}
local file=assert(io.open('tools/test_monster_appearance_spawn_paths.lua','rb'))
local fixture=file:read('*a');file:close()
local boundary=assert(fixture:find('deps["systems/wave_spawn_routing"]=load_service',1,true))
local cases=[=[
local archetypes=require('config/generated/monster_archetypes')
local members=require('config/generated/encounter_members')
local profiles=require('config/challenge_combat_profile_config')
local projection=require('combat/endless_stat_projection')
deps['config/generated/monster_archetypes']=archetypes
deps['config/challenge_combat_profile_config']=profiles
deps['combat/endless_stat_projection']=projection
deps['systems/building_visual_service']={apply=function() return true end}
deps['systems/challenge_monster_visual_service']=load_service('challenge_monster_visual_service')
local old_create=env.CreateUnitByName
local fallback=false
env.CreateUnitByName=function(...)
    local body=old_create(...)
    body.applied={range=128}
    local add_modifier=body.AddNewModifier
    local mods={}
    body.FindModifierByName=function(_,name) return mods[name] end
    body.GetProjectileSpeed=function(self) return self.applied.projectile_speed or 900 end
    body.AddNewModifier=function(self,a,b,name,params)
        add_modifier(self,a,b,name,params)
        if name=='modifier_survival_hero_attack_range' then
            mods[name]={SetAttackRange=function(_,value) self.applied.range=value end}
            mods[name]:SetAttackRange(params.attack_range)
        elseif name=='modifier_survival_hero_projectile_speed' then
            local mod={bonus=0}
            function mod:GetStackCount() return self.bonus end
            function mod:SetProjectileSpeedBonus(value) self.bonus=value;body.applied.projectile_speed=900+value end
            mods[name]=mod;mod:SetProjectileSpeedBonus(params.projectile_speed_bonus)
        end
    end
    for method,field in pairs({SetBaseMaxHealth='base_health',SetMaxHealth='max_health',SetHealth='health',
        SetBaseDamageMin='attack_min',SetBaseDamageMax='attack_max',SetBaseAttackTime='bat',
        Script_SetAttackRange='range',SetAttackRange='range',SetAttackCapability='capability',
        SetRangedProjectileName='projectile',SetProjectileSpeed='projectile_speed'}) do
        local key=field;body[method]=function(self,v) self.applied[key]=v end
    end
    if fallback then body.Script_SetAttackRange=nil;body.SetAttackRange=nil;body.SetProjectileSpeed=nil end
    return body
end
local spawn=find_function(load_service('challenge_session_service'),'spawn_member')
local expected={
 challenge_07_molten_minion='particles/units/heroes/hero_lina/lina_base_attack.vpcf',
 challenge_08_boss='particles/survival/challenge/fire_troll_attack.vpcf',
 challenge_09_boss='particles/units/heroes/hero_ancient_apparition/ancient_apparition_base_attack.vpcf',
 challenge_05_boss='particles/units/heroes/hero_wisp/wisp_base_attack.vpcf',
 seven_sins_minion='particles/units/heroes/hero_viper/viper_base_attack.vpcf',
}
local count=0
local function close(a,b) assert(math.abs(tonumber(a)-tonumber(b))<=math.max(1,math.abs(b))*1e-12) end
for _,mode in ipairs({'standard','pure','rich','cold'}) do
 for _,use_fallback in ipairs({false,true}) do
    fallback=use_fallback
    for id,projectile in pairs(expected) do
        local member={};for k,v in pairs(assert(members.by_id[id])) do member[k]=v end
        member.spawn_target_name='test_spawn'
        local difficulty=mode=='rich' and 'N15' or mode=='cold' and 'N50' or 'N1'
        local session={player_id=0,team=2,difficulty_id=difficulty,game_mode=mode,
            challenge={challenge_id=member.encounter_id:gsub('^encounter_','')},
            encounter_id=member.encounter_id,encounter={},monsters={},monster_count=0}
        for attempt=1,2 do
            local body,err=spawn(session,member);assert(body,tostring(err))
            local applied=body.applied
            assert(applied.capability==DOTA_UNIT_CAP_RANGED_ATTACK,id..' remained melee')
            assert(applied.range==300,id..' range overwritten by the melee template')
            assert(applied.projectile==projectile,id..' wrong projectile')
            assert(applied.projectile_speed==1600)
            -- Reapplying an outfit cannot accumulate projectile-speed bonuses.
            deps['systems/challenge_monster_visual_service'].apply(body,archetypes.by_id[member.archetype_id])
            assert(applied.range==300 and applied.projectile_speed==1600)
            local stats=assert(profiles.resolve(id,difficulty,mode))
            close(projection.for_ui(body,applied.health,'health'),stats.health)
            close(projection.for_ui(body,applied.attack_max,'attack'),stats.attack)
            close(body.survival_war3_armor,stats.war3_armor)
            close(1/applied.bat,stats.attack_speed)
            count=count+1
        end
    end
 end
end
assert(count==80 and #created==80)
-- Existing melee challenges keep their combat range and have no projectile.
local body=env.CreateUnitByName()
deps['systems/challenge_monster_visual_service'].apply(body,{attack_type='melee',attack_range=999})
assert(body.applied.capability==DOTA_UNIT_CAP_MELEE_ATTACK and body.applied.range==128 and body.applied.projectile=='')
-- Keep the pre-existing Morphling presentation contract outside this policy.
local morphling=env.CreateUnitByName()
deps['systems/challenge_monster_visual_service'].apply(morphling,archetypes.by_id.challenge_06_morphling)
assert(morphling.applied.range==128 and morphling:GetProjectileSpeed()==900)
print('CHALLENGE_PROJECTILES_PASS: 80 production spawns, five effects/ranged/300/1600, four modes, repeated respawn/reapply, absent range/projectile setters, combat stats unchanged; melee isolation')
]=]
assert(loadstring(fixture:sub(1,boundary-1)..cases,'@challenge_projectile_spawn_fixture'))()
