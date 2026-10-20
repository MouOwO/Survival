package.path = "scripts/vscripts/?.lua;" .. package.path
local rules = require("config/mode_progression")
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, child in pairs(value) do result[key] = copy(child) end; return result
end
local progress = {loaded=true,clear_counts={n10=99},standard_clear_counts={},
    rich_clear_counts={},cold_clear_counts={},scourge_clear_counts={}}
assert(rules.entry_unlocked("standard") and rules.entry_unlocked("pure") and rules.entry_unlocked("fishing"))
assert(not rules.entry_unlocked("unknown",progress))
assert(rules.difficulty_unlocked("standard","N10",progress)==nil,"ordinary difficulty keeps its existing policy")
assert(not rules.entry_unlocked("rich",progress),"explicit standard provenance must override mixed historical wins")
progress.standard_clear_counts=nil
assert(rules.entry_unlocked("rich",progress),"pre-mode historical qualification is preserved once")
progress.standard_clear_counts={n10=1}
for _, mode in ipairs({"rich","cold","scourge"}) do
    local parent = rules.parent_mode(mode)
    assert(parent and rules.clear_field(mode)==mode.."_clear_counts")
    if mode~="rich" then
        assert(not rules.entry_unlocked(mode,progress),"another mode's N10 cannot skip the predecessor")
        progress[rules.clear_field(parent)].n10=1
    end
    assert(rules.entry_unlocked(mode,progress))
    for number=1,10 do
        assert(rules.difficulty_unlocked(mode,"N"..number,progress)==(number<=5),"first bracket is N1-N5 only")
    end
    progress[rules.clear_field(mode)].n5=1
    for number=1,10 do assert(rules.difficulty_unlocked(mode,"N"..number,progress),"N5 opens the whole N6-N10 bracket") end
    assert(not rules.difficulty_unlocked(mode,"N11",progress))
    local unsupported=copy(progress);unsupported[rules.clear_field(mode)]=nil
    assert(not rules.entry_unlocked(mode,unsupported),"missing authenticated capability is fail-closed")
    assert(not rules.difficulty_unlocked(mode,"N1",unsupported))
    for _, invalid in ipairs({false,true,"1",0,-1,1.5,math.huge}) do
        local bad=copy(progress);bad[rules.clear_field(parent)].n10=invalid
        assert(not rules.entry_unlocked(mode,bad),"malformed predecessor wins cannot grant admission")
        bad=copy(progress);bad[rules.clear_field(mode)].n5=invalid
        assert(not rules.difficulty_unlocked(mode,"N10",bad),"malformed N5 cannot grant the second bracket")
    end
    local not_loaded=copy(progress);not_loaded.loaded=false
    assert(not rules.entry_unlocked(mode,not_loaded))
end
print("MODE_PROGRESSION_PASS: predecessor N10 chain, independent N5 brackets, strict capability and historical provenance")
