-- Real profile resolution and production spawn closure, with engine doubles.
package.path = 'scripts/vscripts/?.lua;' .. package.path
local profiles = require('config/challenge_combat_profile_config')
local rules = require('config/human_monster_rules')
local function close(a,b) assert(math.abs(a-b)<=math.max(1,math.abs(b))*1e-12,tostring(a)..' ~= '..tostring(b)) end
local total = 0
for mode, difficulties in pairs(rules.data.modes) do
    for number, difficulty in ipairs(difficulties) do
        for level, source in ipairs(rules.data.rebirth_bosses) do
            local id=string.format('encounter_rebirth_%02d',level)
            local first=(level==1 and (mode=='cold' or mode=='scourge')) and 0.5 or 1
            local attack=(mode=='scourge' or mode=='ruins' or mode=='celestial') and (3+number) or (1.8+0.2*number)
            local hp=source.health*difficulty.challenge_hp_multiplier*first*(mode=='rich' and 5 or 1)
            local damage=source.attack*attack*(mode=='rich' and 3 or 1)
            local armor=source.war3_armor*difficulty.challenge_armor_multiplier*first*(mode=='rich' and 2 or 1)
            local row=assert(profiles.resolve(id,'N'..number,mode))
            close(row.health,hp);close(row.attack,damage);close(row.war3_armor,armor)
            close(row.attack_speed,1/source.attack_interval)
            row.health=0
            close(assert(profiles.resolve(id,'N'..number,mode)).health,hp)
            total=total+1
        end
    end
end
assert(total==2350)
-- Literal anchors are independent of both the importer and runtime formula.
local first=assert(profiles.resolve('encounter_rebirth_01','N1','rich'))
assert(first.health==2250000 and first.attack==18000 and first.war3_armor==280)
local tenth=assert(profiles.resolve('encounter_rebirth_10','N10','rich'))
assert(tenth.health==310944684800 and tenth.attack==211130280 and tenth.war3_armor==6120)
local file=assert(io.open('tools/test_monster_appearance_spawn_paths.lua','rb'))
local fixture=file:read('*a');file:close()
local boundary=assert(fixture:find('deps["systems/wave_spawn_routing"]=load_service',1,true))
local cases=[=[
local profiles=require('config/challenge_combat_profile_config')
local projection=require('combat/endless_stat_projection')
deps['config/challenge_combat_profile_config']=profiles
deps['combat/endless_stat_projection']=projection
deps['config/generated/monster_encounters']=require('config/generated/monster_encounters')
deps['config/generated/monster_archetypes']=require('config/generated/monster_archetypes')
deps['config/generated/monster_spawn_points']=require('config/generated/monster_spawn_points')
local base_create=env.CreateUnitByName
env.CreateUnitByName=function(...)
    local body=base_create(...)
    body.SetBaseMaxHealth=function(self,v) self.base_health=v end
    body.SetMaxHealth=function(self,v) self.max_health=v end
    body.SetHealth=function(self,v) self.health=v end
    body.SetBaseDamageMin=function(self,v) self.attack_min=v end
    body.SetBaseDamageMax=function(self,v) self.attack_max=v end
    body.SetBaseAttackTime=function(self,v) self.bat=v end
    return body
end
local function close(a,b) assert(math.abs(a-b)<=math.max(1,math.abs(b))*1e-12,tostring(a)..' ~= '..tostring(b)) end
for number=1,30 do
    deps['core/event_bus'].request=function(name)
        if name==events.WAVE_STATE_GET_REQUEST then return {ok=true,difficulty_id='N'..number,game_mode='rich'} end
    end
    local service=load_service('monster_spawn_service')
    local start=find_function(service,'start_encounter')
    for level=1,10 do
        local id=string.format('encounter_rebirth_%02d',level)
        local result=start({encounter_id=id,player_id=0})
        assert(result.ok,tostring(result.error))
        local body=created[#created]
        local expected=assert(profiles.resolve(id,'N'..number,'rich'))
        close(projection.for_ui(body,body.health,'health'),expected.health)
        close(projection.for_ui(body,body.attack_max,'attack'),expected.attack)
        close(body.survival_war3_armor,expected.war3_armor)
        close(1/body.bat,expected.attack_speed)
        assert(body.health<=100000000 and body.attack_max<=100000000)
    end
end
assert(#created==300)
]=]
assert(loadstring(fixture:sub(1,boundary-1)..cases,'@rich_rebirth_spawn_fixture'))()
print('RICH_REBIRTH_BALANCE_PASS: 2350 mode/tier profiles, literal anchors, 300 production rich spawns, exact projected HP/attack/armor, repeated resolve, other modes unchanged')
