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
    for tier = 1, 10 do
        local difficulty = "N" .. tier
        local source_id = assert(balance.source_difficulty(mode, difficulty))
        local temporary = source_id ~= difficulty
        local built = assert(builder.build(source,difficulty,mode))
        assert(built.mode_id == mode and built.total_waves == (difficulty == "N1" and 25 or 30))
        assert(built.difficulty.difficulty_id == difficulty and built.source_difficulty_id == source_id)
        assert(built.temporary_config == temporary)
        local recorded = assert(builder.build(source, source_id, mode))
        for number,rows in ipairs(built.waves) do
            local count = 0
            for index,row in ipairs(rows) do
                assert(row.mode_id == mode and row.difficulty_id == difficulty and row.wave_number == number)
                assert(row.health > 0 and row.attack > 0 and row.war3_armor >= 0)
                assert(row.rich_field_sources.health.method and row.data_source == "data/balance/mode_monsters_20261020.json")
                local original = recorded.waves[number][index]
                for _, field in ipairs({"health", "attack", "war3_armor", "monster_count", "attack_speed", "wait_seconds",
                    "spawn_interval", "archetype_id", "member_role", "model_scale_multiplier"}) do
                    assert(row[field] == original[field], "temporary mode configuration must not multiply or alter recorded values: " .. field)
                end
                if temporary then
                    assert(row.temporary_config and row.balance_fallback and row.source_difficulty_id == source_id)
                    assert(row.source_wave_id == original.wave_id and row.wave_id ~= original.wave_id)
                    assert(row.data_status == "temporary_inherited" and row.source_data_status == original.data_status)
                    assert(equal(row.rich_field_sources, original.rich_field_sources), "recorded provenance is retained")
                end
                for variant_index, variant in ipairs(row.rich_stat_variants or {}) do
                    local prior = original.rich_stat_variants[variant_index]
                    assert(variant.difficulty_id == difficulty and variant.source_difficulty_id == source_id)
                    assert(variant.health == prior.health and variant.attack == prior.attack and variant.war3_armor == prior.war3_armor)
                    assert(equal(variant.field_sources, prior.field_sources))
                end
                count = count + row.monster_count
            end
            assert(count == 60)
        end
        local room = assert(profiles.resolve("practice_wood",difficulty,mode))
        local original_room = assert(profiles.resolve("practice_wood",source_id,mode))
        assert(room.difficulty_id == difficulty and room.source_difficulty_id == source_id)
        assert(room.health == original_room.health and room.attack == original_room.attack and room.war3_armor == original_room.war3_armor)
        if temporary then assert(room.temporary_config and room.source_profile_id == original_room.profile_id) end
        local health = room.health;room.health = -1;room.field_sources.health.method = "mutated_fixture"
        local fresh = assert(profiles.resolve("practice_wood",difficulty,mode))
        assert(fresh.health == health and fresh.field_sources.health.method ~= "mutated_fixture")
        local before = copy(builder.build(source,difficulty,"standard"))
        builder.build(source,difficulty,mode)
        assert(equal(before,builder.build(source,difficulty,"standard")),"mode values leaked into standard")
    end
end
assert(equal(source,ordinary),"the ordinary authoritative table was mutated")
for _, invalid in ipairs({"N0", "N01", "N11", "N999", "n5", "N5.0"}) do
    assert(not balance.has_difficulty("cold", invalid) and not balance.has_difficulty("scourge", invalid))
end
assert(not balance.source_difficulty("standard", "N5"), "temporary configuration never crosses modes")
local missing,reason = builder.build(source,"N11","cold")
assert(not missing and reason == "difficulty_not_found")
missing,reason = profiles.resolve("practice_wood","N11","cold")
assert(not missing and reason == "recorded_mode_member_missing:cold:N11:practice_wood")

PlayerResource = {IsValidPlayerID=function(_,id)return id==0 or id==1 end,
    IsFakeClient=function()return false end,GetPlayer=function(_,id)return {id=id} end,
    GetTeam=function()return 2 end,GetConnectionState=function()return 2 end}
GameRules = {PlayerHasCustomGameHostPrivileges=function(_,player)return player.id==0 end}
local authenticated_progress = {loaded=true, clear_counts={}, standard_clear_counts={n10=1},
    rich_clear_counts={n10=1}, cold_clear_counts={n10=1}, scourge_clear_counts={}}
package.loaded["systems/player_profile_service"] = {
    get_authenticated_progression=function(id) assert(id==0);return copy(authenticated_progress) end,
    get_progression=function(id,mode)
        assert(id==0 or id==1)
        local progress=copy(authenticated_progress);progress.mode_id=mode;return progress
    end,
}
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
local permissions = require("systems/team_difficulty_service")
for _, mode in ipairs({"cold", "scourge"}) do
    local snapshot=permissions.snapshot({0,1,0},mode)
    assert(snapshot.ready and #snapshot.options==10 and snapshot.max_difficulty_id=="N5")
    for index,option in ipairs(snapshot.options) do
        assert(option.unlocked==(index<=5 and 1 or 0) and balance.has_difficulty(mode,option.difficulty_id))
        local source_id=balance.source_difficulty(mode,option.difficulty_id)
        assert(option.source_difficulty_id==source_id)
        if source_id~=option.difficulty_id then
            assert(option.temporary_config==1 and option.description:find("临时配置",1,true)
                and option.description:find(source_id,1,true))
        else assert(option.temporary_config==0) end
    end
    authenticated_progress[mode.."_clear_counts"].n5=1
    snapshot=permissions.snapshot({0,1},mode)
    assert(snapshot.max_difficulty_id=="N10")
    for _,option in ipairs(snapshot.options) do assert(option.unlocked==1) end
    local archive_progress=require("systems/archive_clear_progress")
    assert(archive_progress.max_available(mode)==10)
    local archive={}
    assert(archive_progress.record(archive,{mode_id=mode,difficulty_id="n10",count=1},{},function() end))
    assert(archive.mode_clear_counts[mode].n10==1 and archive.mode_clear_counts[mode][mode=="cold" and "n4" or "n2"]==nil,
        "permanent mode clear keeps the selected tier instead of the temporary balance source")
    local accepted,error_code=archive_progress.record(archive,{mode_id=mode,difficulty_id="n11",count=1},{},function() end)
    assert(not accepted and error_code=="archive_mode_difficulty_unavailable")
end
print("RECORDED_MODE_CATALOG_PASS: twenty mode tiers, explicit temporary inheritance, selected-tier identity, exact source stats/provenance, immutable sources and real progression gates")
