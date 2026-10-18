-- Independent numbers read from stable video panels, not generated expectations.
package.path = "scripts/vscripts/?.lua;" .. package.path
local builder = require("systems/wave_difficulty_builder")
local source = require("config/generated/wave_definitions").rows
local encounters = require("config/challenge_combat_profile_config")
local rich = { N2 = assert(builder.build(source, "N2", "rich")),
    N3 = assert(builder.build(source, "N3", "rich")) }
local function batch(id, number, name)
    for _, row in ipairs(rich[id].waves[number]) do
        if row.batch_id == name then return row end
    end
    error("missing video fixture " .. id .. "/" .. number .. "/" .. name)
end
local function stats(row, health, attack, armor, label)
    assert(row.health == health, label .. " maximum health: " .. tostring(row.health))
    assert(row.attack == attack, label .. " attack: " .. tostring(row.attack))
    assert(row.war3_armor == armor, label .. " armor: " .. tostring(row.war3_armor))
end
local fixtures = {
    {"N2",1,"1N1",1600,17,10}, {"N2",3,"3N1",4800,130,20},
    {"N2",4,"4L",80000,1922,80}, {"N2",6,"6L",320000,14082,100},
    {"N2",6,"6N1",32000,3522,50},
    {"N2",8,"8N1",64000,7202,125}, {"N2",8,"8N2",64000,7202,150},
    {"N2",8,"8L",640000,28802,300},
    {"N2",11,"11N1",160000,16002,200}, {"N2",11,"11N3",160000,8002,200},
    {"N2",13,"13N1",480000,22402,300}, {"N2",13,"13N3",240000,16002,300},
    {"N2",24,"24N1",4800000,320002,750},
    {"N2",24,"24N3",4800000,368002,775},
    {"N2",24,"24N4",5600000,144002,725},
    {"N2",24,"24L",48000000,1280002,1500},
    {"N2",26,"26L",96000000,1920002,1650},
    {"N2",27,"27N1",11200000,640002,850},
    {"N2",28,"28L",128000000,3200002,1750},
    {"N2",30,"30N1",19200000,960002,925},
    {"N3",3,"3N1",10800,290,28}, {"N3",4,"4N1",18000,1082,56},
    {"N3",8,"8N1",144000,16202,175}, {"N3",8,"8N2",144000,16202,210},
    {"N3",11,"11N1",360000,36002,280}, {"N3",11,"11N3",360000,18002,280},
    {"N3",12,"12L",4320000,86402,630},
    {"N3",13,"13N1",1080000,50402,420}, {"N3",13,"13N3",540000,36002,420},
    {"N3",16,"16N1",1800000,144002,700}, {"N3",16,"16N3",1800000,126002,630},
    {"N3",16,"16L",18000000,576002,1400},
    {"N3",24,"24N1",10800000,720002,1050},
    {"N3",24,"24N3",10800000,828002,1085},
    {"N3",24,"24N4",12600000,324002,1015},
    {"N3",24,"24L",108000000,2880002,2100},
    {"N3",30,"30N1",43200000,2160002,1295},
}
for _, f in ipairs(fixtures) do
    stats(batch(f[1],f[2],f[3]),f[4],f[5],f[6],f[1] .. "/" .. f[3])
end
local bosses = {
    N2 = {{5,160080,10402,490},{10,480080,64002,1990},{15,2400080,240002,4990},
        {20,8000080,968002,4990},{25,48000080,1600002,4990},{30,128000000,2560002,4990}},
    N3 = {{5,360180,23402,686},{10,1080180,144002,2786},{15,5400180,540002,6986},
        {20,18000180,2178002,6986},{25,108000000,1800002,6986},{30,288000000,5760002,6986}},
}
for id, list in pairs(bosses) do
    for _, f in ipairs(list) do
        local row = batch(id,f[1],f[1] .. "B")
        stats(row,f[2],f[3],f[4],id .. " boss " .. f[1])
        assert(row.rich_stats_estimated == false and row.rich_stats_source == "video")
    end
end
-- N3 boss25 actually displays less attack than boss20; preserve the observation
-- instead of silently replacing it with the usual cross-difficulty curve.
assert(batch("N3",25,"25B").attack < batch("N3",20,"20B").attack)
for _, f in ipairs({{"N2",32000,3522,50,75},{"N3",72000,7922,70,105}}) do
    local row = batch(f[1],6,"6N1")
    assert(#row.rich_stat_variants == 2)
    stats(row.rich_stat_variants[1],f[2],f[3],f[4],f[1] .. " W6 base")
    stats(row.rich_stat_variants[2],f[2],f[3],f[5],f[1] .. " W6 second armor group")
    assert(row.monster_count == 59, "variants must share the original quota")
end
local nonwave = {
    {"N2","practice_wood",150000,11000,125},
    {"N2","practice_gold",2500000,550000,125},
    {"N2","practice_attribute",4444440,1100000,500},
    {"N2","practice_greater_attribute",14444440,4155554,2220},
    {"N2","encounter_rebirth_10",2101000000,40744436,850},
    {"N2","challenge_08_boss",25524800,220000,750},
    {"N2","boss_ten_sin_01",95524790,2200000,1250},
    {"N3","boss_ten_sin_01",133700000,2400000,1750},
    {"N3","boss_ten_sin_07",350700000,6240000,2800},
    {"N3","challenge_07_molten_minion",840000,19200,1050},
}
for _, f in ipairs(nonwave) do
    stats(assert(encounters.resolve(f[2],f[1],"rich")),f[3],f[4],f[5],f[1] .. "/" .. f[2])
end
local estimated = assert(encounters.resolve("encounter_rebirth_10","N3","rich"))
assert(estimated.health == 2941400000 and estimated.estimated,
    "unselected N3 rebirth10 needs an explicit estimate above32-bit native health")
assert(batch("N3",1,"1N1").rich_stats_estimated,
    "unselected early N3 wave cannot be claimed as a direct observation")
print("RICH_N2_N3_VIDEO_FIXTURES_PASS: independent panels, mixed units, all bosses, W6 variants, nonwave and explicit missing-data estimates")
