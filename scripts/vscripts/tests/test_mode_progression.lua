package.path = "scripts/vscripts/?.lua;" .. package.path
local rules = require("config/mode_progression")
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, child in pairs(value) do result[key] = copy(child) end; return result
end
local limits = {standard=10,pure=10,rich=30,cold=50,scourge=50,ruins=50,celestial=35}
local entry = {rich=3,cold=5,scourge=9,ruins=9,celestial=11}
local function profile()
    return {loaded=true,clear_counts={},standard_clear_counts={},mode_clear_counts={pure={}},
        rich_clear_counts={},cold_clear_counts={},scourge_clear_counts={},ruins_clear_counts={},celestial_clear_counts={}}
end
local progress=profile()
assert(rules.entry_unlocked("standard") and rules.entry_unlocked("pure") and rules.entry_unlocked("fishing"))
assert(not rules.entry_unlocked("unknown",progress))
assert(rules.difficulty_unlocked("unknown","N1",progress)==nil)
for mode,maximum in pairs(limits) do
    local saved=profile()
    if entry[mode] then
        local donor=entry[mode]<=10 and saved.mode_clear_counts.pure or saved.cold_clear_counts
        donor["n"..entry[mode]]=1
    end
    for number=1,maximum do
        assert(rules.difficulty_unlocked(mode,"N"..number,saved)==(number<=4),"only N1-N4 start unlocked")
    end
    assert(not rules.difficulty_unlocked(mode,"N"..(maximum+1),saved),"mode-specific maximum is authoritative")
    assert(not rules.difficulty_unlocked(mode,"n5",saved),"difficulty IDs remain canonical")
    local own=assert(rules.counts(mode,saved))
    own.n4=1
    assert(rules.difficulty_unlocked(mode,"N5",saved) and not rules.difficulty_unlocked(mode,"N6",saved))
    own.n5=1
    assert(rules.difficulty_unlocked(mode,"N6",saved) and not rules.difficulty_unlocked(mode,"N10",saved),
        "own N5 advances one difficulty; it never opens a whole bracket")
    own.n9=1
    assert(rules.difficulty_unlocked(mode,"N10",saved))
    for _,invalid in ipairs({false,true,"1",0,-1,1.5,math.huge,0/0}) do
        own.n9=invalid
        assert(not rules.difficulty_unlocked(mode,"N10",saved),"malformed counters cannot grant a higher difficulty")
    end
end
for mode,required in pairs(entry) do
    local saved=profile()
    assert(not rules.entry_unlocked(mode,saved))
    saved.standard_clear_counts["n"..(required+1)]=1
    saved.highest_difficulty=50
    assert(not rules.entry_unlocked(mode,saved),"higher labels do not prove an exact persisted entry clear")
    local donor=required<=10 and saved.mode_clear_counts.pure or saved.cold_clear_counts
    donor["n"..required]=1
    assert(rules.entry_unlocked(mode,saved),"an authenticated clear of the exact tier can qualify across modes")
    assert(rules.clear_field(mode)==mode.."_clear_counts" and rules.parent_mode(mode))
    local unsupported=copy(saved);unsupported[rules.clear_field(mode)]=nil
    assert(not rules.entry_unlocked(mode,unsupported) and not rules.difficulty_unlocked(mode,"N1",unsupported),
        "missing authenticated independent capability must fail closed")
    for _,invalid in ipairs({false,true,"1",0,-1,1.5,math.huge,0/0}) do
        local bad=copy(saved)
        local bad_donor=required<=10 and bad.mode_clear_counts.pure or bad.cold_clear_counts
        bad_donor["n"..required]=invalid
        assert(not rules.entry_unlocked(mode,bad),"invalid cross-mode entry evidence is rejected")
    end
    local not_loaded=copy(saved);not_loaded.loaded=false
    assert(not rules.entry_unlocked(mode,not_loaded))
    saved.standard_clear_counts.n4=1
    assert(not rules.difficulty_unlocked(mode,"N5",saved),"cross-mode entry cannot unlock own later tiers")
    saved[rules.clear_field(mode)].n4=1
    assert(rules.difficulty_unlocked(mode,"N5",saved))
end
local mixed=profile();mixed.clear_counts.n3=1;mixed.mode_clear_counts=nil
assert(not rules.entry_unlocked("rich",mixed),"an explicit empty standard provenance map blocks historical mixed wins")
mixed.standard_clear_counts=nil
assert(rules.entry_unlocked("rich",mixed),"historical accounts without provenance retain authoritative standard qualification")
print("MODE_PROGRESSION_PASS: exact any-mode entry, N1-N4 then own sequential tiers, seven mode limits, strict capability/provenance")
