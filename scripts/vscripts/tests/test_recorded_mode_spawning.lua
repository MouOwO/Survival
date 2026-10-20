-- Real production spawn closures with engine doubles from the shared fixture.
-- Generated mode rows remain authoritative; only explicit boundary cases use
-- returned copies with forced large values.
package.path = "scripts/vscripts/?.lua;" .. package.path
local file = assert(io.open("tools/test_monster_appearance_spawn_paths.lua", "rb"))
local fixture = file:read("*a"); file:close()
local boundary = assert(fixture:find('deps["systems/wave_spawn_routing"]=load_service', 1, true))
local cases = [=[
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, child in pairs(value) do result[key] = copy(child) end
    return result
end
local function equal(a,b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key,value in pairs(a) do if not equal(value,b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function close(a,b)
    return type(a)=="number" and type(b)=="number"
        and math.abs(a-b)<=math.max(.00001,math.abs(b)*1e-13)
end
local balance = require("config/recorded_mode_balance")
local profiles = require("config/challenge_combat_profile_config")
local difficulty_config = require("config/difficulty_config")
local variants = require("systems/rich_stat_variant_row")
local projection = require("combat/endless_stat_projection")
local actual_members = require("config/generated/encounter_members").rows
local actual_encounters = require("config/generated/monster_encounters")
local sources = {
    require("config/generated/recorded_mode_wave_definitions"),
    require("config/generated/recorded_mode_wave_stat_variants"),
    require("config/generated/recorded_mode_challenge_combat_profiles"),
    require("config/generated/challenge_combat_profiles"),
    require("config/generated/rich_wave_definitions"),
}
local source_before = copy(sources)
deps["config/generated/monster_archetypes"] = require("config/generated/monster_archetypes")
deps["config/generated/monster_encounters"] = actual_encounters
deps["config/generated/monster_spawn_points"] = require("config/generated/monster_spawn_points")
deps["config/generated/encounter_members"] = require("config/generated/encounter_members")
deps["config/generated/challenge_definitions"] = require("config/generated/challenge_definitions")
deps["systems/destination_validation_service"] = {validate=function() return true end}
deps["combat/endless_stat_projection"] = projection
deps["systems/wave_native_attack_cap"] = require("systems/wave_native_attack_cap")
local selected_mode, selected_difficulty, override = "cold", "N2", nil
local snapshots, resolve_calls = 0, {}
local hero = {IsNull=function() return false end, IsAlive=function() return true end,
    entindex=function() return 99999 end, SetAbsOrigin=no_op, Stop=no_op}
deps["core/event_bus"].request = function(name)
    if name==events.WAVE_STATE_GET_REQUEST then
        snapshots=snapshots+1
        return {ok=true,difficulty_id=selected_difficulty,game_mode=selected_mode}
    end
    if name==events.HERO_SUMMON_GET_REQUEST then return {unit=hero} end
    if name==events.CONTENT_INVENTORY_GET_REQUEST then return {snapshot={counts={}}} end
end
deps["config/challenge_combat_profile_config"] = {resolve=function(id,difficulty,mode)
    resolve_calls[#resolve_calls+1]={id=id,difficulty=difficulty,mode=mode}
    local value,reason=profiles.resolve(id,difficulty,mode)
    if value and override and override.id==id and override.mode==mode and override.difficulty==difficulty then
        value=copy(value)
        for key,number in pairs(override.stats) do value[key]=number end
    end
    return value,reason
end}
env.RandomInt=function(low) return low end
env.DoUniqueString=function(value) return value..":recorded_fixture" end
env.FindUnitsInRadius=function() return {} end
env.DOTA_UNIT_TARGET_HERO,env.DOTA_UNIT_TARGET_BASIC=1,2
deps["systems/player_room_locations"].resolve=function()
    return {entry_target_name="test_spawn",home_target_name="test_spawn",
        spawn_target_names={"test_spawn","test_spawn_2"}}
end
local create=env.CreateUnitByName
env.CreateUnitByName=function(...)
    local value=create(...); value.applied={}
    for method,key in pairs({SetBaseMaxHealth="base_health",SetMaxHealth="max_health",
        SetHealth="health",SetBaseDamageMin="attack_min",SetBaseDamageMax="attack_max",
        SetPhysicalArmorBaseValue="native_armor",SetBaseAttackTime="bat"}) do
        local field=key
        value[method]=function(self,argument) self.applied[field]=argument end
    end
    function value:GetHealth() return self.applied.health end
    function value:GetMaxHealth() return self.applied.max_health end
    return value
end
local function check(value,expected,mode,label)
    local hs=value.survival_endless_health_scale or 1
    local ats=value.survival_endless_attack_scale or 1
    assert(close(value.applied.base_health*hs,expected.health)
        and close(value.applied.max_health*hs,expected.health)
        and close(value.applied.health*hs,expected.health),label.." logical health changed")
    assert(close(value.applied.attack_min*ats,expected.attack)
        and close(value.applied.attack_max*ats,expected.attack),label.." logical attack changed")
    assert(close(tonumber(projection.for_ui(value,value:GetMaxHealth(),"health")),expected.health)
        and close(tonumber(projection.for_ui(value,value.applied.attack_min,"attack")),expected.attack),
        label.." UI did not recover logical values")
    local projected=(mode=="cold" or mode=="scourge")
        and (expected.health>100000000 or expected.attack>100000000)
    if projected then
        assert(value.applied.max_health<=100000000.00001
            and value.applied.attack_min<=100000000.00001,label.." exceeded native cap")
        assert(value.survival_endless_health==expected.health
            and value.survival_endless_attack==expected.attack,label.." logical fields missing")
        assert(close(projection.incoming(value,expected.health/2)/value:GetMaxHealth(),.5),
            label.." incoming damage scaled incorrectly")
        assert(close(projection.outgoing(value,value.applied.attack_min,true),expected.attack),
            label.." basic damage scaled incorrectly")
        assert(projection.outgoing(value,123,false)==123,label.." spell damage scaled twice")
    else
        assert(value.survival_endless_health_scale==nil and value.survival_endless_attack_scale==nil,
            label.." small/legacy mode unexpectedly projected")
    end
    assert(value.applied.native_armor==0 and value.survival_base_war3_armor==expected.war3_armor
        and value.survival_effective_war3_armor==expected.war3_armor,label.." custom armor changed")
end
local formal_count,variant_count,member_count,rebirth_count=0,0,0,0
local crossing=false
local selections={}
for _,mode in ipairs({"cold","scourge"}) do
    for number=1,10 do selections[#selections+1]={mode,"N"..number} end
end
for _,selection in ipairs(selections) do
    local mode,difficulty=selection[1],selection[2]
    selected_mode,selected_difficulty=mode,difficulty
    local built,reason=balance.build_waves(assert(difficulty_config.get(difficulty)),mode)
    assert(built,reason)
    for number,rows in pairs(built.waves) do
        local total=0;for _,row in ipairs(rows) do total=total+row.monster_count end
        assert(total==60,mode..difficulty.." wave "..number.." must total 60 including boss")
    end
    local wave=load_service("wave_system")
    local spawn=find_function(wave,"spawn_one")
    upvalue(find_function(wave,"refresh_selection_state"),"difficulty_selected",true)
    upvalue(spawn,"monster_spawn_marker",marker)
    upvalue(spawn,"state",{pending=100000,spawned=0,alive=0,alive_limit=math.huge,
        overflow_active=false,game_mode=mode,mode_selected=true,total_waves=built.total_waves})
    local before=#created
    for _,row in ipairs(built.waves[built.total_waves]) do
        local row_before=copy(row)
        for ordinal=1,row.monster_count do
            local expected=variants.resolve(row,ordinal)
            local previous=#created
            spawn(expected,0,built.total_waves,ordinal)
            assert(#created==previous+1,"formal spawn did not create exactly one unit")
            check(created[#created],expected,mode,mode..difficulty.." formal")
            if expected.health>2147483647 then crossing=true end
            assert(created[#created].survival_monster_role==row.member_role,"formal role changed")
            formal_count=formal_count+1
        end
        assert(equal(row,row_before),"formal spawn/variants mutated source row")
    end
    assert(#created-before==60,"real formal closures must produce exactly 60 births")
    for _,row in ipairs(built.rows) do
        if type(row.rich_stat_variants)=="table" then
            local source=copy(row)
            for ordinal=1,#row.rich_stat_variants do
                local expected=variants.resolve(row,ordinal)
                spawn(expected,0,row.wave_number,ordinal)
                check(created[#created],expected,mode,mode..difficulty.." cyclic variant")
                assert(expected.rich_variant_index==ordinal,"variant order changed")
                variant_count=variant_count+1
            end
            assert(equal(row,source),"cyclic variant birth mutated shared source/provenance")
        end
    end
    local rooms=load_service("challenge_session_service")
    local spawn_member=find_function(rooms,"spawn_member")
    for _,member in ipairs(actual_members) do
        local expected=assert(profiles.resolve(member.member_id,difficulty,mode))
        local session={player_id=0,team=2,difficulty_id=difficulty,game_mode=mode,
            challenge={challenge_id=member.encounter_id=="encounter_challenge_11" and "challenge_11" or "test_challenge"},
            encounter_id=member.encounter_id,encounter={},monsters={},monster_count=0}
        selected_mode,selected_difficulty="fishing","N1"
        local value,err=spawn_member(session,member)
        assert(value,err);check(value,expected,mode,mode..difficulty.." member "..member.member_id)
        local called=resolve_calls[#resolve_calls]
        assert(called.mode==mode and called.difficulty==difficulty and called.id==member.member_id,
            "room respawn must retain session selection despite a different global mode")
        member_count=member_count+1
    end
    selected_mode,selected_difficulty=mode,difficulty
    local wilderness=load_service("monster_spawn_service")
    local start=find_function(wilderness,"start_encounter")
    for _,encounter in ipairs(actual_encounters.rows) do
        if encounter.encounter_type=="rebirth_boss" then
            local expected=assert(profiles.resolve(encounter.encounter_id,difficulty,mode))
            local previous=snapshots
            local result=start({encounter_id=encounter.encounter_id,player_id=0,
                game_mode="untrusted_client_mode",difficulty_id="N999"})
            assert(result.ok,result.error);assert(snapshots==previous+1,"rebirth must read one authoritative snapshot")
            check(created[#created],expected,mode,mode..difficulty.." rebirth "..encounter.encounter_id)
            rebirth_count=rebirth_count+1
        end
    end
end
assert(crossing,"real recorded formal waves must exercise HP above signed int32")
assert(variant_count>0,"real recorded rows must exercise cyclic stat variants")
-- Force both native boundaries on all three birth paths independently of the
-- current balance curve; metadata and source rows remain untouched.
for _,mode in ipairs({"cold","scourge"}) do
    selected_mode,selected_difficulty=mode,"N2"
    local huge={health=5615000003,attack=1000000007,war3_armor=4321}
    local built=assert(balance.build_waves(assert(difficulty_config.get("N2")),mode))
    local row=copy(built.waves[1][1]);for key,value in pairs(huge) do row[key]=value end
    local row_before=copy(row)
    local wave=load_service("wave_system");local spawn=find_function(wave,"spawn_one")
    upvalue(find_function(wave,"refresh_selection_state"),"difficulty_selected",true)
    upvalue(spawn,"monster_spawn_marker",marker)
    upvalue(spawn,"state",{pending=100,spawned=0,alive=0,alive_limit=math.huge,
        overflow_active=false,game_mode=mode,mode_selected=true,total_waves=30})
    spawn(row,0,1,1);check(created[#created],huge,mode,"forced formal "..mode)
    assert(equal(row,row_before),"projection mutated formal input")
    override={id="encounter_rebirth_10",mode=mode,difficulty="N2",stats=huge}
    local wilderness=load_service("monster_spawn_service")
    local result=find_function(wilderness,"start_encounter")({encounter_id=override.id,player_id=0})
    assert(result.ok,result.error);check(created[#created],huge,mode,"forced rebirth "..mode)
    local member
    for _,candidate in ipairs(actual_members) do if candidate.member_id=="practice_greater_attribute" then member=candidate end end
    override.id=member.member_id
    local rooms=load_service("challenge_session_service")
    local value,err=find_function(rooms,"spawn_member")({player_id=0,team=2,difficulty_id="N2",game_mode=mode,
        challenge={challenge_id="test_challenge"},encounter_id=member.encounter_id,encounter={},monsters={},monster_count=0},member)
    assert(value,err);check(value,huge,mode,"forced room "..mode)
    override=nil
end
for _,mode in ipairs({"standard","pure","fishing"}) do
    local expected=assert(profiles.resolve("practice_wood","N2"))
    assert(profiles.resolve("practice_wood","N2",mode)==expected,"legacy mode profile changed")
end
local missing,reason=balance.build_waves({difficulty_id="N11",total_waves=30},"scourge")
assert(missing==nil and reason=="recorded_mode_difficulty_missing:scourge:N11",
    "temporary configuration must never open invalid difficulties")
assert(equal(sources,source_before),"recorded spawn or mode lookup mutated generated data/provenance")
print(string.format("RECORDED_MODE_SPAWNING_PASS formal=%d variants=%d members=%d rebirth=%d; all supported pairs, 60 counts, native limits, armor, immutable sources, mode isolation",
    formal_count,variant_count,member_count,rebirth_count))
]=]
assert(loadstring(fixture:sub(1,boundary-1)..cases,"test_recorded_mode_spawn"))()
