-- Only real configured difficulties; archive final values must never inherit
-- their wave multipliers. Admission/release of modes remains a separate gate.
package.path="scripts/vscripts/?.lua;"..package.path
local definitions=require("config/generated/archive_challenge_definitions")
local authored=require("config/generated/archive_challenge_stats")
local balance=require("config/human_challenge_balance")
local difficulties=require("config/difficulty_config")
local combinations,modes,checks=0,0,0
local attributes={"health","attack","war3_armor","attack_speed","move_speed","attack_range","magic_resistance","count"}
for mode,rows in pairs(difficulties.rows_by_mode) do
    modes=modes+1
    for _,difficulty in ipairs(rows) do
        assert(difficulties.get(difficulty.difficulty_id,mode)==difficulty)
        for _,definition in ipairs(definitions.rows) do
            local fixed=assert(authored.by_id[definition.challenge_id.."_N1"])
            local actual=assert(balance.archive(definition.challenge_id,difficulty.difficulty_id,mode))
            combinations=combinations+1
            assert(actual.difficulty_id==difficulty.difficulty_id and actual.human_spec and actual.fixed_archive_stats)
            for _,field in ipairs(attributes) do
                checks=checks+1
                assert(actual[field]==fixed[field],mode.."/"..difficulty.difficulty_id.."/"..definition.challenge_id.." scaled "..field)
            end
            assert(actual.count==(definition.challenge_id=="football" and 5 or 1))
        end
    end
end
assert(modes==7 and combinations==8460 and not definitions.by_id.pet)
assert(balance.archive("hunt_01","N1").health~=balance.archive("hunt_08","N1").health,
    "different challenge identities retain their own authored profiles")
print("ARCHIVE_FIXED_ALL_MODES_PASS: "..combinations.." valid combinations / "..modes.." configured modes / "..checks.." exact field comparisons; Pal excluded")
