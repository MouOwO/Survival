-- Reuse the engine doubles, while exercising production spawn_one and the
-- actual generated archetypes/profile data rather than a parallel renderer.
package.path = "scripts/vscripts/?.lua;" .. package.path
arg = arg or {}
local file = assert(io.open("tools/test_monster_appearance_spawn_paths.lua", "rb"))
local fixture = file:read("*a"); file:close()
local boundary = assert(fixture:find('deps["systems/wave_spawn_routing"]=load_service',1,true))
local cases = [=[
local profile=require("systems/human_wave_profile")
local rules=require("config/human_monster_rules")
local source=require("config/generated/wave_definitions").rows
local projection=require("combat/endless_stat_projection")
local actual_archetypes=require("config/generated/monster_archetypes")
deps["config/generated/monster_archetypes"]=actual_archetypes
deps["systems/human_wave_profile"]=profile
deps["combat/endless_stat_projection"]=projection
deps["systems/wave_native_attack_cap"]=require("systems/wave_native_attack_cap")
deps["systems/wave_spawn_routing"]=load_service("wave_spawn_routing")
local rolls=0
env.RandomInt=function() rolls=rolls+1;return rolls%2==1 and 51 or 50 end
local create=env.CreateUnitByName
env.CreateUnitByName=function(...)
    local value=create(...);value.applied={}
    for method,key in pairs({SetBaseMaxHealth="base_health",SetMaxHealth="max_health",
        SetHealth="health",SetBaseDamageMin="attack_min",SetBaseDamageMax="attack_max",
        SetPhysicalArmorBaseValue="armor",SetBaseAttackTime="bat",SetModel="model"}) do
        local field=key
        value[method]=function(self,argument)
            self.applied[field]=argument
            if field=="base_health" or field=="max_health" or field=="health"
                or field=="attack_min" or field=="attack_max" then
                assert(argument==math.floor(argument),"native setter received fractional authored stat")
            end
        end
    end
    function value:GetHealth() return self.applied.health end
    function value:GetMaxHealth() return self.applied.max_health end
    return value
end
local function close(a,b) return type(a)=="number" and type(b)=="number"
    and math.abs(a-b)<=math.max(1e-7,math.abs(b)*2e-14) end
local wave=load_service("wave_system")
local spawn=find_function(wave,"spawn_one")
upvalue(spawn,"monster_spawn_marker",marker)
upvalue(spawn,"state",{pending=100000,spawned=0,alive=0,alive_limit=math.huge,
    overflow_active=false,total_waves=30,game_mode="standard"})
local count=0
local function check(row,number,expected,channel)
    local before=#created
    spawn(row,0,number,1,nil,channel)
    assert(#created==before+1,"production spawn closure failed to create a unit")
    local target=created[#created]
    assert(close(target.applied.health*target.survival_endless_health_scale,expected.health))
    assert(close(target.applied.max_health*target.survival_endless_health_scale,expected.health))
    assert(close(target.applied.attack_min*target.survival_endless_attack_scale,expected.attack))
    assert(close(target.applied.attack_max*target.survival_endless_attack_scale,expected.attack))
    assert(close(tonumber(projection.for_ui(target,target:GetMaxHealth(),"health")),expected.health))
    assert(close(tonumber(projection.for_ui(target,target.applied.attack_min,"attack")),expected.attack))
    assert(close(projection.outgoing(target,target.applied.attack_min,true),expected.attack))
    assert(close(projection.incoming(target,expected.health/2),target:GetMaxHealth()/2))
    assert(projection.outgoing(target,123,false)==123,"spell damage scaled twice")
    assert(target.applied.armor==0 and target.survival_base_war3_armor==expected.war3_armor)
    assert(target.survival_effective_war3_armor==expected.war3_armor)
    assert(target.applied.bat==1/expected.attack_speed and target.survival_exact_stat_projection)
    assert(target.survival_is_boss==(row.member_role=="assault_boss"))
    assert(target.survival_monster_role==row.member_role)
    assert(target.survival_human_spec and target.survival_scourge_elite==(expected.human_spec_elite==true))
    assert(appearances[target] and appearances[target].fresh_unit==true)
    local definition=assert(actual_archetypes.by_id[row.archetype_id])
    local model=definition.model_path
    if row.member_role=="normal" and row.movement_type_override=="flying"
        and definition.normal_flying_model_path then model=definition.normal_flying_model_path end
    assert(target.applied.model==model,"formula integration changed existing model mapping")
    count=count+1
    return target
end
for mode_id,difficulties in pairs(rules.data.modes) do
    local highest=1;for number in pairs(difficulties) do highest=math.max(highest,number) end
    for _,number in ipairs({1,highest}) do
        local id="N"..number
        local built=assert(profile.build(source,{difficulty_id=id},mode_id))
        for _,wave_number in ipairs({4,5,8,12,24,built.total_waves}) do
            local rows=built.waves[wave_number]
            for _,index in ipairs({1,math.min(3,#rows),#rows}) do
                local row=rows[index]
                local expected=profile.resolve_spawn(row,function() return (rolls+1)%2==1 and 51 or 50 end)
                check(row,wave_number,expected)
            end
        end
    end
end
-- A reusable queue row is rolled again for each physical birth/player channel.
local disaster=assert(profile.build(source,{difficulty_id="N22"},"scourge"))
local row=disaster.waves[1][1]
rolls=0
local channels={[0]={player_id=0,marker=marker},[1]={player_id=1,marker=marker}}
upvalue(spawn,"wave_channels",channels)
deps["systems/wave_spawn_routing"].position=function() return {x=64,y=128,z=32} end
local ordinary=check(row,1,profile.resolve_spawn(row,function() return 51 end),channels[0])
local elite=check(row,1,profile.resolve_spawn(row,function() return 50 end),channels[1])
assert(not ordinary.survival_scourge_elite and elite.survival_scourge_elite and rolls==2)
assert(ordinary.survival_player_id==0 and elite.survival_player_id==1,"player channels lost independent ownership")
assert(row.human_spec_scourge_roll and row.human_spec_elite==nil,"spawn mutated next player's queued base row")
local before=rolls
check(disaster.waves[4][1],4,disaster.waves[4][1])
assert(rolls==before,"scourge first monster must bypass elite selection")
print("HUMAN_WAVE_SPAWNING_PASS births="..count..", exact logical values, original models and independent elite rolls")
]=]
local chunk=assert(loadstring(fixture:sub(1,boundary-1)..cases,"@human_wave_spawning_fixture"))
chunk()
