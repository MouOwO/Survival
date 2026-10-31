package.path = "scripts/vscripts/?.lua;" .. package.path
local developer_unlock = false
package.loaded["debug/mode_unlock_test"] = {
    reset=function() end, is_enabled=function() return developer_unlock end,
}
local authenticated = { loaded=true, standard_clear_counts={n3=1,n5=1},
    rich_clear_counts={}, cold_clear_counts={}, scourge_clear_counts={},
    ruins_clear_counts={}, celestial_clear_counts={}, mode_clear_counts={pure={}} }
package.loaded["systems/player_profile_service"] = {
    get_authenticated_progression=function(id) assert(id==0); return authenticated end,
}
PlayerResource = {
    IsValidPlayerID=function(_,id) return id==0 end,
    IsFakeClient=function() return false end,
    GetTeam=function() return 2 end,
    GetPlayer=function(_,id) return id==0 and {} or nil end,
    GetConnectionState=function() return 2 end,
}
GameRules = {PlayerHasCustomGameHostPrivileges=function() return true end}
local setup = require("systems/match_setup_service")
local release = require("config/mode_release_config")
local rules = require("config/human_monster_rules")
local difficulties = require("config/difficulty_config")
assert(release.all_difficulties_unlocked == false, "normal shipped matches must not enter read-only acceptance")
setup.init("human_release_scope")
local options = setup.snapshot().mode_options
assert(#options==4)
local seen = {}
for _,row in ipairs(options) do assert(release.is_released(row.mode_id));seen[row.mode_id]=true end
for _,mode in ipairs({"standard","cold","rich","pure"}) do
    assert(not release.is_difficulty_open(mode), "normal matches obey authenticated progression")
    assert(seen[mode]);setup.init("human_release_"..mode)
    local selected=setup.select_mode(0,mode,setup.get_session_id())
    assert(selected.ok and setup.get_mode()==mode)
end
release.all_difficulties_unlocked=true
for _,mode in ipairs({"standard","cold","rich","pure"}) do
    assert(release.is_difficulty_open(mode), "explicit acceptance still opens released tiers")
end
for _,debug in ipairs({false,true}) do
    developer_unlock=debug
    for _,mode in ipairs({"scourge","ruins","celestial","fishing"}) do
        assert(not release.is_difficulty_open(mode), "tier acceptance cannot release an unreleased mode")
        setup.init("human_closed_"..mode)
        local selected=setup.select_mode(0,mode,setup.get_session_id())
        assert(not selected.ok and selected.error=="mode_not_released")
        assert(not setup.is_mode_selected())
    end
end
developer_unlock=false
release.all_difficulties_unlocked=false
for mode, expected in pairs({standard=10,pure=10,rich=30,cold=50,scourge=50,ruins=50,celestial=35}) do
    local all=difficulties.client_options(nil,mode)
    assert(#all==expected and difficulties.get("N"..expected,mode))
    assert(not difficulties.get("N"..(expected+1),mode))
    assert(rules.mode(mode,"N1").total_waves==25)
    assert(rules.mode(mode,"N2").total_waves==30)
end
authenticated.cold_clear_counts.n49=1
assert(difficulties.is_unlocked("N50",authenticated,"cold"))
assert(not difficulties.is_unlocked("N50",authenticated,"standard"))
print("HUMAN_SPEC_MODE_RELEASE_PASS: four menu modes; closed modes reject direct/debug requests; seven complete mode ranges; cold N50 permissions")
