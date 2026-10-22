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
-- Acceptance regression: N2's fourth-wave leader and ordinary monsters share
-- appearances, but their authored stats differ. Exercise every physical birth
-- after the same builder/sequence/variant boundaries used by start_wave, with
-- fixed workbook values rather than expectations copied from generated rows.
local builder=require("systems/wave_difficulty_builder")
local sequence=require("systems/wave_spawn_sequence")
local variants=require("systems/rich_stat_variant_row")
local rich_second=assert(builder.build(source,"N2","rich"))
local fourth=assert(rich_second.waves[4])
local ordered=sequence.build(fourth,{enabled=true,movement_type=function(row)
    return row.movement_type_override
end})
assert(#ordered==60 and ordered[1]==fourth[1],"N2 rich fourth-wave total/order changed")
local leader_stats={health=80000,attack=1920,war3_armor=80,attack_speed=1}
local normal_stats={health=8000,attack=480,war3_armor=40,attack_speed=1}
local before_fourth_rolls=rolls
for index,row in ipairs(ordered) do
    local expected_role=index==1 and "wave_leader" or "normal"
    assert(row.member_role==expected_role and row.human_spec_position==index,
        "fourth-wave leader was dropped or reordered")
    local target=check(variants.resolve(row,1),4,index==1 and leader_stats or normal_stats)
    assert(target.survival_monster_role==expected_role)
end
assert(rolls==before_fourth_rolls,"rich fourth wave must not consume scourge elite rolls")
local fifth=sequence.build(rich_second.waves[5],{enabled=true})
assert(#fifth==60 and fifth[1].member_role=="assault_boss")
local fifth_boss=check(variants.resolve(fifth[1],1),5,
    {health=160080,attack=10400,war3_armor=490,attack_speed=1})
assert(fifth_boss.survival_is_boss and fifth_boss.survival_monster_role=="assault_boss")
-- Other released modes must retain their own N2 multiplier and the same
-- leader/ordinary distinction, including pure mode's fractional armor.
for mode_id,expected in pairs({
    standard={leader={health=20000,attack=480,war3_armor=24,attack_speed=1},
        normal={health=2000,attack=120,war3_armor=12,attack_speed=1}},
    cold={leader={health=180000,attack=4320,war3_armor=112,attack_speed=1},
        normal={health=18000,attack=1080,war3_armor=56,attack_speed=1}},
    pure={leader={health=15000,attack=360,war3_armor=19.2,attack_speed=1},
        normal={health=1500,attack=90,war3_armor=9.6,attack_speed=1}},
}) do
    local rows=assert(builder.build(source,"N2",mode_id)).waves[4]
    assert(rows[1].member_role=="wave_leader" and rows[2].member_role=="normal")
    check(variants.resolve(rows[1],1),4,expected.leader)
    check(variants.resolve(rows[2],1),4,expected.normal)
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
