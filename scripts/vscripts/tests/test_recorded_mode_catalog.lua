package.path = "scripts/vscripts/?.lua;" .. package.path
local balance = require("config/recorded_mode_balance")
local builder = require("systems/wave_difficulty_builder")
local source = require("config/generated/wave_definitions").rows
local profiles = require("config/challenge_combat_profile_config")
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for k,v in pairs(value) do result[k] = copy(v) end; return result
end
local function equal(a,b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local ordinary = copy(source)
for mode, definition in pairs(balance.modes) do
    for _, difficulty in ipairs(definition.difficulties) do
        local built = assert(builder.build(source,difficulty,mode))
        assert(built.mode_id == mode and built.total_waves == (difficulty == "N1" and 25 or 30))
        for number,rows in ipairs(built.waves) do
            local count = 0
            for _,row in ipairs(rows) do
                assert(row.mode_id == mode and row.difficulty_id == difficulty and row.wave_number == number)
                assert(row.health > 0 and row.attack > 0 and row.war3_armor >= 0)
                assert(row.rich_field_sources.health.method and row.data_source == "data/balance/mode_monsters_20261020.json")
                count = count + row.monster_count
            end
            assert(count == 60)
        end
        local room = assert(profiles.resolve("practice_wood",difficulty,mode))
        local health = room.health;room.health = -1;room.field_sources.health.method = "mutated_fixture"
        local fresh = assert(profiles.resolve("practice_wood",difficulty,mode))
        assert(fresh.health == health and fresh.field_sources.health.method ~= "mutated_fixture")
        local before = copy(builder.build(source,difficulty,"standard"))
        builder.build(source,difficulty,mode)
        assert(equal(before,builder.build(source,difficulty,"standard")),"mode values leaked into standard")
    end
end
assert(equal(source,ordinary),"the ordinary authoritative table was mutated")
local missing,reason = builder.build(source,"N5","cold")
assert(not missing and reason == "recorded_mode_difficulty_missing:cold:N5")
missing,reason = builder.build(source,"N3","scourge")
assert(not missing and reason == "recorded_mode_difficulty_missing:scourge:N3")
missing,reason = profiles.resolve("practice_wood","N5","cold")
assert(not missing and reason == "recorded_mode_member_missing:cold:N5:practice_wood")

PlayerResource = {IsValidPlayerID=function(_,id)return id==0 or id==1 end,
    IsFakeClient=function()return false end,GetPlayer=function(_,id)return {id=id} end,
    GetTeam=function()return 2 end,GetConnectionState=function()return 2 end}
GameRules = {PlayerHasCustomGameHostPrivileges=function(_,player)return player.id==0 end}
local setup = require("systems/match_setup_service")
for _,mode in ipairs({"cold","scourge"}) do
    local session = "mode-fixture-" .. mode;setup.init(session)
    assert(#setup.snapshot().mode_options==6)
    assert(setup.select_mode(1,mode,session).error == "selection_not_host")
    assert(setup.select_mode(0,mode,session).ok)
    assert(setup.get_mode()==mode and setup.get_profile_mode()=="standard")
    assert(not setup.is_rich_mode() and not setup.is_fishing_mode())
    assert(setup.select_mode(0,"standard",session).error=="mode_locked")
end
package.loaded["systems/player_profile_service"] = {get_progression=function(id,mode)
    assert(id==0 or id==1);return {loaded=true,clear_counts={}}
end}
local permissions = require("systems/team_difficulty_service")
for mode,maximum in pairs({cold=4,scourge=2}) do
    local snapshot=permissions.snapshot({0,1,0},mode)
    assert(snapshot.ready and #snapshot.options==maximum and snapshot.max_difficulty_id=="N"..maximum)
    for _,option in ipairs(snapshot.options) do assert(option.unlocked==1 and balance.has_difficulty(mode,option.difficulty_id)) end
end
print("RECORDED_MODE_CATALOG_PASS: independent final values, immutable sources, no unsupported-difficulty fallback, six server-owned choices and standard account contract")
