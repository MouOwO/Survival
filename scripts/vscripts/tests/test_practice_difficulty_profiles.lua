package.path="scripts/vscripts/?.lua;"..package.path
local config=require("config/challenge_combat_profile_config")
local difficulties=require("config/difficulty_config")
local members={"practice_wood","practice_gold","practice_attribute","practice_greater_attribute"}
for _,difficulty in ipairs(difficulties.rows) do
    for _,member in ipairs(members) do
        local row,err=config.resolve(member,difficulty.difficulty_id)
        assert(row and not err, tostring(err))
        assert(row.health>0 and row.attack>0 and row.war3_armor>=0)
        if difficulty.source_difficulty_id~=difficulty.difficulty_id then
            assert(row==config.resolve(member,difficulty.source_difficulty_id))
        end
    end
end
local missing,err=config.resolve("practice_wood","N999")
assert(not missing and err,"unknown difficulty must not silently use arbitrary stats")
print("PRACTICE_DIFFICULTY_PROFILES_PASS: all four rooms across N1-N10, declared N5 inheritance, unknown difficulty rejected")
