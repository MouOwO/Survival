-- Native category/provenance regression. No Dota process or production reload.
-- Uses the real filter, category rules, transaction repository/service/adapter.
package.path = "scripts/vscripts/?.lua;" .. package.path
DAMAGE_TYPE_PHYSICAL, DAMAGE_TYPE_MAGICAL, DAMAGE_TYPE_PURE = 1, 2, 4
DOTA_DAMAGE_CATEGORY_ATTACK, DOTA_DAMAGE_CATEGORY_SPELL = 1, 0
DOTA_DAMAGE_FLAG_IGNORES_PHYSICAL_ARMOR = 2
GameRules = {GetGameTime=function() return 0 end}
RandomFloat = function() return 1 end
local physical_ignore = 0
package.loaded["systems/rogue_effect_state_service"] = {
    has_effect=function() return false end,
    numeric=function(_,key) return key=="physical_armor_ignore_pct" and physical_ignore or 0 end,
}
local bus = require("core/event_bus")
local events = require("combat/combat_events")
local armor = require("config/armor_balance")
local rules = require("combat/damage_rule_config")
local repository = require("combat/damage_transaction_repository")
local projection = require("combat/endless_stat_projection")
local filter = require("combat/damage_filter_service")
local context = require("combat/damage_context")
local service = require("combat/damage_service")
local adapter = require("adapters/dota_damage_adapter")
local entities = {}
local function unit(index)
    local u = {index=index, survival_player_id=-1}
    entities[index] = u
    function u:IsNull() return false end
    function u:entindex() return self.index end
    function u:GetUnitName() return "npc_dota_creature" end
    function u:IsRealHero() return self.real_hero==true end
    function u:IsInvulnerable() return false end
    function u:HasModifier() return false end
    function u:FindModifierByName() return nil end
    function u:FindAllModifiersByName() return {} end
    function u:GetPhysicalArmorValue() return 0 end
    return u
end
local attacker, victim = unit(1), unit(2)
victim.survival_war3_armor_target = true
victim.survival_armor_mapping_version = armor.CUSTOM_WAR3_MAPPING_VERSION
victim.survival_effective_war3_armor = 512
EntIndexToHScript = function(index) return entities[index] end
repository.init(rules)
filter.init({event_bus=bus,events=events,repository=repository,config=rules})
service.init({event_bus=bus,events=events,context=context,rules=rules,
    repository=repository,adapter=adapter,debug={log=function() end}})
local latest, filtered_count, resolved_count, native_category, native_inflictor, submitted
bus.subscribe(events.DAMAGE_FILTERED, function(payload)
    latest, filtered_count = payload, filtered_count + 1
end)
bus.subscribe(events.DAMAGE_RESOLVED, function() resolved_count = resolved_count + 1 end)
local function near(actual, expected, label)
    assert(type(actual)=="number" and math.abs(actual-expected)
        <= math.max(1e-7,math.abs(expected)*1e-11),
        label .. ": " .. tostring(actual) .. " != " .. tostring(expected))
end
local function apply_native(damage, category, inflictor, field, other_category)
    local keys = {entindex_attacker_const=1,entindex_victim_const=2,
        entindex_inflictor_const=inflictor,damagetype_const=DAMAGE_TYPE_PHYSICAL,damage=damage}
    keys[field or "damage_category_const"] = category
    if other_category ~= nil then keys.damage_category = other_category end
    assert(filter._filter_for_test(filter,keys),"native damage unexpectedly blocked")
    return keys
end
ApplyDamage = function(input)
    -- The actual adapter omits ability when the request does. Native category
    -- is chosen independently here; no source-kind hint is added to keys.
    assert(input.ability==nil,"provenance case unexpectedly gained an ability")
    submitted = apply_native(input.damage,native_category,native_inflictor)
    return submitted.damage
end
local function check(logical, keys, transaction_id, ignore_pct)
    local after_armor = logical * armor.war3_physical_damage_multiplier(512,ignore_pct or 0)
    near(latest.final_damage,after_armor,"logical damage must scale only native basic hits")
    near(latest.engine_damage,after_armor,"logical engine payload precedes HP projection")
    near(keys.damage,after_armor/(victim.survival_endless_health_scale or 1),"native target HP projection")
    assert(latest.transaction_id==transaction_id,"filter lost transaction provenance")
    assert(filtered_count==1 and resolved_count==1,"damage must publish exactly one event pair")
    assert(keys.damage_flags==DOTA_DAMAGE_FLAG_IGNORES_PHYSICAL_ARMOR,
        "War3 armor must not be applied a second time by native armor")
end
local passed, failures = 0, {}
local function test(label, callback)
    latest, filtered_count, resolved_count, submitted = nil,0,0,nil
    local ok, problem = pcall(callback)
    assert(repository.debug_snapshot().pending_records==0,"case stranded pending provenance: " .. label)
    if ok then passed=passed+1 else failures[#failures+1]=label .. ": " .. tostring(problem) end
end
for _, amount in ipairs({1e12,9e15}) do
    local _, native = projection.prepare_attack(attacker,amount,amount,20)
    for _, scaled in ipairs({false,true}) do
        victim.survival_endless_health_scale = nil
        if scaled then projection.prepare(victim,{health=amount*1e4,attack=0}) end
        local prefix = tostring(amount) .. "/" .. (scaled and "scaled" or "ordinary") .. "/"
        for _, entry in ipairs({
            {name="explicit_spell_zero_no_inflictor",category=0,logical=amount},
            {name="string_spell_zero_no_inflictor",category="0",logical=amount},
            {name="spell_zero_legacy_field",category=0,field="damage_category",logical=amount},
            {name="spell_zero_beats_secondary_attack",category=0,other=1,logical=amount},
            {name="explicit_spell_zero_zero_inflictor",category=0,inflictor=0,logical=amount},
            {name="spell_with_inflictor",category=0,inflictor=999,logical=amount},
            {name="unknown_with_inflictor",inflictor=999,logical=amount},
            {name="native_basic",category=1,input=native,logical=amount},
            {name="native_basic_string",category="1",input=native,logical=amount},
            {name="native_basic_20x",category=1,input=native*20,logical=amount*20},
            {name="legacy_missing_category_raw_basic",input=native,logical=amount},
        }) do
            test(prefix..entry.name,function()
                check(entry.logical,apply_native(entry.input or amount,entry.category,
                    entry.inflictor,entry.field,entry.other),nil)
            end)
        end
        -- Every accepted Deal source is already logical. Even a missing native
        -- category/ability, or conflicting ATTACK category, cannot make it a
        -- projected native basic attack merely because the hero has a scale.
        for _, source_kind in ipairs({"ability","item","dot","reflection","splash","script"}) do
            for _, category in ipairs({{name="spell_zero",value=0},
                    {name="missing"},{name="attack",value=1}}) do
                test(prefix..source_kind.."/"..category.name,function()
                    native_category,native_inflictor=category.value,nil
                    local result=service:Deal({attacker=attacker,victim=victim,source_kind=source_kind,
                        base_damage=amount,damage_type=DAMAGE_TYPE_PHYSICAL,can_crit=false})
                    assert(result.success,"logical transaction was rejected")
                    check(amount,submitted,result.transaction_id)
                    near(result.final_damage,latest.final_damage,"Deal keeps unscaled logical result")
                end)
            end
        end
        attacker.real_hero,physical_ignore = true,25
        for _, entry in ipairs({
            {name="hero_spell_zero_no_basic_armor_ignore",category=0,input=amount,ignore=0},
            {name="hero_spell_string_zero_no_basic_armor_ignore",category="0",input=amount,ignore=0},
            {name="hero_native_attack_basic_armor_ignore",category=1,input=native,ignore=25},
            {name="hero_legacy_raw_attack_basic_armor_ignore",input=native,ignore=25},
        }) do
            test(prefix..entry.name,function()
                check(amount,apply_native(entry.input,entry.category),nil,entry.ignore)
            end)
        end
        test(prefix.."hero_logical_script_explicit_attack_no_basic_armor_ignore",function()
            native_category,native_inflictor=1,nil
            local result=service:Deal({attacker=attacker,victim=victim,source_kind="script",
                base_damage=amount,damage_type=DAMAGE_TYPE_PHYSICAL,can_crit=false})
            assert(result.success,"logical hero script was rejected")
            check(amount,submitted,result.transaction_id,0)
        end)
        attacker.real_hero,physical_ignore = false,0
    end
end
local failure_excerpt = {}
for index=1,math.min(6,#failures) do failure_excerpt[#failure_excerpt+1]=failures[index] end
assert(#failures==0,"PROJECTED_ATTACK_DAMAGE_CATEGORY_FAIL " .. #failures .. " cases (first six):\n" .. table.concat(failure_excerpt,"\n"))
print("PROJECTED_ATTACK_DAMAGE_CATEGORY_PASS " .. passed .. " native spell=0/basic/provenance cases; ordinary/scaled 1e12/9e15, 20x and War3 armor")
