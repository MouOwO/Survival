package.path = "scripts/vscripts/?.lua;" .. package.path
local rules = require("config/human_monster_rules")
local profile = require("systems/human_wave_profile")
local builder = require("systems/wave_difficulty_builder")
local sequence = require("systems/wave_spawn_sequence")
local source = require("config/generated/wave_definitions").rows
local function close(a,b)
    return type(a)=="number" and type(b)=="number"
        and math.abs(a-b)<=math.max(1e-8,math.abs(b)*2e-14)
end
local excluded = {[1]=true,[2]=true,[3]=true,[5]=true,[10]=true,[15]=true,[20]=true,[25]=true,[30]=true}
local tiers, waves, members = 0, 0, 0
for mode_id, difficulties in pairs(rules.data.modes) do
    for number, mode in pairs(difficulties) do
        local difficulty = "N"..number
        local built, reason = builder.build(source,difficulty,mode_id)
        assert(built,reason)
        assert(built.mode_id==mode_id and built.total_waves==mode.total_waves)
        local bosses = 0
        for wave_number=1,mode.total_waves do
            local rows = assert(built.waves[wave_number])
            local count = rules.count(mode_id,difficulty,wave_number)
            assert(#rows==count.count,"total must include leaders, rotations and assault boss")
            local ordered = sequence.build(rows,{enabled=true,movement_type=function(row)
                return row.movement_type_override
            end})
            assert(#ordered==#rows)
            local leaders, wave_bosses = 0, 0
            for index,row in ipairs(rows) do
                assert(ordered[index]==row,"legacy movement mixing changed specification positions")
                assert(row.monster_count==1 and row.spawn_interval==count.spawn_interval)
                assert(row.human_spec_stats and row.rich_stat_variants==nil)
                assert(row.health>0 and row.attack>=0 and row.war3_armor>=0)
                if row.member_role=="wave_leader" then leaders=leaders+1
                    assert(index==1 and not excluded[wave_number] and not row.human_spec_scourge_roll)
                    local base=rules.wave_base(wave_number)
                    assert(close(row.health,base.health*mode.hp_multiplier*(mode_id=="scourge" and 2 or 10)))
                    assert(close(row.war3_armor,base.war3_armor*mode.armor_multiplier*(mode_id=="scourge" and 1 or 2)))
                    assert(close(row.attack,base.attack*mode.hp_multiplier*(mode_id=="scourge" and 2 or 4)))
                elseif row.member_role=="assault_boss" then
                    bosses, wave_bosses = bosses+1,wave_bosses+1
                    assert(index==1 and wave_number%5==0 and not row.human_spec_scourge_roll,
                        "keep the existing fifth-wave boss arrival before ordinary monsters")
                    local base=assert(rules.data.attack_bosses[wave_number])
                    local extra=mode_id=="ruins" or mode_id=="celestial"
                    assert(close(row.health,base.health*mode.hp_multiplier*(extra and 5 or 1)))
                    assert(close(row.attack,base.attack*mode.hp_multiplier*(extra and 3 or 1)))
                    assert(close(row.war3_armor,base.war3_armor*mode.armor_multiplier))
                    assert(close(row.attack_speed,1/base.attack_interval))
                elseif mode_id=="scourge" then
                    assert(row.human_spec_scourge_roll and not row.human_spec_rotation_position)
                    local normal=profile.resolve_spawn(row,function() return 51 end)
                    local elite=profile.resolve_spawn(row,function() return 50 end)
                    local base=rules.wave_base(wave_number)
                    assert(not normal.human_spec_elite and elite.human_spec_elite)
                    assert(close(normal.health,base.health*mode.hp_multiplier*3))
                    assert(close(elite.health,base.health*mode.hp_multiplier*5))
                    assert(close(normal.attack,base.attack*mode.hp_multiplier))
                    assert(close(elite.attack,base.attack*mode.hp_multiplier*2))
                    assert(close(normal.war3_armor,elite.war3_armor))
                    assert(row.human_spec_scourge_roll,"sampling mutated the reusable queued row")
                end
                if wave_number==12 or wave_number==14 then
                    assert(row.movement_type_override=="flying","whole flight wave must fly")
                end
            end
            assert(leaders==(excluded[wave_number] and 0 or 1))
            assert(wave_bosses==(wave_number%5==0 and 1 or 0))
            waves, members = waves+1,members+#rows
        end
        assert(bosses==(number==1 and 5 or 6),"one assault boss each five waves, not five bosses per wave")
        tiers = tiers+1
    end
end
assert(tiers==235)
local n1=assert(builder.build(source,"N1","standard"))
local b5=n1.waves[5][1]
assert(b5.health==20010 and b5.attack==1300 and close(b5.war3_armor,117.6))
assert(math.floor(b5.war3_armor)==117,"display floors armor while internal armor stays fractional")
local eighth=n1.waves[8]
assert(eighth[1].member_role=="wave_leader" and eighth[2].health==8000
    and eighth[3].health==2210 and eighth[3].attack==1800
    and close(eighth[3].war3_armor,18) and eighth[4].health==8000)
-- The confirmed rich N10 correction is a final value for the flying rotation,
-- never a change to the shared base, the leader, or adjacent modes/tiers.
local rich_tenth=assert(builder.build(source,"N10","rich")).waves[8]
local corrected=0
for _,row in ipairs(rich_tenth) do
    if row.human_spec_rotation_position==2 then
        assert(row.archetype_id=="flying_red_gargoyle" and row.member_role=="normal")
        assert(row.health==1420000 and row.attack==160000 and row.war3_armor==270)
        corrected=corrected+1
    elseif row.member_role=="wave_leader" then
        assert(row.health==14240000 and row.attack==640800)
    else
        assert(row.health==1424000 and row.attack==160200)
    end
end
assert(corrected==20,"all twenty flying rotation members must use the confirmed health and attack")
for _,case in ipairs({{"rich","N9"},{"rich","N11"},{"standard","N10"},
    {"cold","N10"},{"pure","N10"}}) do
    local rows=assert(builder.build(source,case[2],case[1])).waves[8]
    local multiplier=rules.mode(case[1],case[2]).hp_multiplier
    for _,row in ipairs(rows) do
        if row.human_spec_rotation_position==2 then
            assert(close(row.health,1105*multiplier),"health correction leaked into another mode/tier")
            assert(close(row.attack,900*multiplier),"attack correction leaked into another mode/tier")
        end
    end
end
local w24=n1.waves[24]
assert(w24[2].human_spec_rotation_position==nil and w24[3].human_spec_rotation_position==2
    and w24[4].human_spec_rotation_position==3 and w24[5].human_spec_rotation_position==nil)
assert(w24[3].attack==46000 and w24[4].attack==18000)
local disaster=assert(builder.build(source,"N22","scourge"))
local normal=profile.resolve_spawn(disaster.waves[1][1],function() return 51 end)
local elite=profile.resolve_spawn(disaster.waves[1][1],function() return 50 end)
assert(close(normal.health,64033710) and close(normal.war3_armor,2698.8) and close(normal.attack,213445.7))
assert(close(elite.health,106722850) and close(elite.war3_armor,2698.8) and close(elite.attack,426891.4))
local roll_calls=0
local leader=disaster.waves[4][1]
assert(profile.resolve_spawn(leader,function() roll_calls=roll_calls+1;return 1 end)==leader and roll_calls==0)
assert(close(leader.health,213445700) and close(leader.war3_armor,5397.6) and close(leader.attack,12806742))
print(string.format("HUMAN_WAVE_SPEC_PASS tiers=%d waves=%d members=%d, totals include bosses; fractions/rotations/scourge verified",tiers,waves,members))
