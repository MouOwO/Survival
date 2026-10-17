-- Reuse the project router + NetTable engine fixture's setup and factories.
-- Assertions below exercise the actual current request/event/publication paths.
local f=assert(io.open('scripts/vscripts/tests/test_portrait_metadata_channels.lua','rb'))
local fixture=f:read('*a'):gsub('\r\n','\n');f:close()
local stale='assert(router._test.apply_portrait_metadata == metadata.apply, "router seam must use the shared mapping")'
local at=assert(fixture:find(stale,1,true))
fixture=fixture:sub(1,at-1)..'-- Historical private seam replaced by a production wrapper.'..fixture:sub(at+#stale)
fixture=fixture:sub(1,assert(fixture:find('local heroes = {',1,true))-1)
fixture=fixture..[[

initialize(false)
local owner={survival_player_id=0,survival_hero_id='hero_doom',
    IsNull=function() return false end,IsAlive=function() return true end,
    GetPlayerOwnerID=function() return 0 end}
entities[777]=owner
raw=snapshot_for('hero_doom',777,25)
raw.armor=50;raw.stat_units_version=2;raw.armor_unit='war3_display'
for _,bonus in ipairs({0,100,100,0}) do
    owner.survival_commerce_titan_armor=bonus~=0 and bonus or nil
    local expected=50+bonus
    listeners.ui_selected_unit_stats_request(nil,{PlayerID=0,entindex=777})
    assert(sent[#sent].snapshot.armor==expected,'selected hero armor lost/doubled Titan')
    bus.emit(events.HERO_COMBAT_STATS_CHANGED,{player_id=0,snapshot=raw})
    assert(tables[#tables].snapshot.armor==expected,'regular hero armor lost/doubled Titan')
    assert(sent[#sent].snapshot.armor==expected,'coalesced hero armor lost/doubled Titan')
    assert(raw.armor==50 and raw.commerce_titan_armor==nil,'projected bonus leaked into authoritative hero snapshot')
end
-- Custom War3 monsters use the same armor layer for selected-unit reads.
entities[778]={survival_player_id=0,IsNull=function() return false end,
    entindex=function() return 778 end,GetUnitName=function() return 'monster_test' end,
    survival_armor_mapping_version=3,survival_war3_armor=117,
    survival_effective_war3_armor=117,survival_commerce_titan_armor=-30}
listeners.ui_selected_unit_stats_request(nil,{PlayerID=0,entindex=778})
assert(sent[#sent].snapshot.armor==87,'custom War3 UI must match 117-30 damage mitigation')
assert(entities[778].survival_effective_war3_armor==117,'UI mutated permanent armor baseline')
print('TITAN_UI_PASS: actual selected/coalesced/NetTable hero channels, entry/repeat/exit, custom War3 monster, raw snapshot unchanged')
]]
assert(loadstring(fixture,'@actual_project_ui_channels'))()
