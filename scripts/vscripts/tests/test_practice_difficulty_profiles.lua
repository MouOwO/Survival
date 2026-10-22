package.path="scripts/vscripts/?.lua;"..package.path
local config=require("config/challenge_combat_profile_config")
local rules=require("config/human_monster_rules")
local members={"practice_wood","practice_gold","practice_attribute","practice_greater_attribute"}
local total=0
for mode,definitions in pairs(rules.data.modes) do
 for number,difficulty in ipairs(definitions) do
    for index,member in ipairs(members) do
        local row,err=config.resolve(member,"N"..number,mode)
        assert(row and not err, tostring(err))
        assert(row.health>0 and row.attack>0 and row.war3_armor>=0)
        local source=rules.data.rooms[index]
        assert(row.health==source.health*difficulty.challenge_hp_multiplier)
        assert(row.war3_armor==source.war3_armor*difficulty.challenge_armor_multiplier)
        assert(row.attack==source.attack*(1.8+0.2*number),"rooms do not use the special-BOSS attack formula")
        total=total+1
    end
 end
end
local missing,err=config.resolve("practice_wood","N999")
assert(not missing and err,"unknown difficulty must not silently use arbitrary stats")
assert(total==940)
print("PRACTICE_DIFFICULTY_PROFILES_PASS: all 940 room/mode/difficulty formulas, no recorded-tier fallback, unknown difficulty rejected")
