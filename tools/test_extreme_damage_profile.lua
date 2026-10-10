-- Offline damage-probe contracts; no connection to Dota or real engine filters.
package.path = 'scripts/vscripts/?.lua;' .. package.path
local original_print, lines = print, {}
print = function(value) lines[#lines + 1] = tostring(value) end
local wall_ms, clock_reads, entity_reads, metadata_ms = 1000, 0, 0, 0
local tools_mode = false
local function advance(ms) wall_ms = wall_ms + ms end
GetSystemTimeMS = function() clock_reads = clock_reads + 1; return wall_ms end
IsServer = function() return true end
IsInToolsMode = function() return tools_mode end
local mode = {
    SetContextThink = function() end,
    SetDamageFilter = function() error('The installed engine filter must not be replaced') end,
}
GameRules = {GetGameModeEntity = function() return mode end,
    GetGameTime = function() return wall_ms / 1000 end,
    IsGamePaused = function() return false end}
local function unit(index, name, flags)
    flags.entindex = function() entity_reads = entity_reads + 1; advance(metadata_ms); return index end
    flags.GetUnitName = function() entity_reads = entity_reads + 1; advance(metadata_ms); return name end
    return flags
end
local attacker = unit(501, 'npc_sr_lightning_tower', {survival_building_id = 'arrow_tower'})
local victim = unit(601, 'npc_wave_15', {survival_is_wave_monster = true, survival_is_boss = true})
local worker = unit(701, 'npc_lumberjack', {survival_lumberjack_attack_owner = {}})
local tree = unit(801, 'enemy_tree', {survival_tree_owner_id = 0})
local failure = {reason = 'exact_damage_error'}
local pending = {consume_pending = function(a, v)
    advance(1); return a, nil, v, nil
end}
local tree_rules = {is_tree = function(value) advance(0.5); return value == tree end}
local anti_air = {has_damage_taken_aura = function() advance(0.5); return false end}
local armor = {war3_physical_damage_multiplier = function() advance(0.5); return 1 end}
package.loaded['combat/damage_transaction_repository'] = pending
package.loaded['systems/tree_damage_rules'] = tree_rules
package.loaded['systems/anti_air_rules'] = anti_air
package.loaded['config/armor_balance'] = armor
local pending_original, tree_original, aura_original, armor_original = pending.consume_pending,
    tree_rules.is_tree, anti_air.has_damage_taken_aura, armor.war3_physical_damage_multiplier
-- The already-installed private filter keeps the module table references,
-- exactly as the production filter does. It is never exchanged for a wrapper.
local function installed_filter(args)
    pending.consume_pending(args.attacker, args.victim)
    tree_rules.is_tree(args.victim)
    anti_air.has_damage_taken_aura(args.victim)
    armor.war3_physical_damage_multiplier(1, 0)
    return args.damage >= 0
end
local filter_service = {_filter_for_test = installed_filter}
package.loaded['combat/damage_filter_service'] = filter_service
local adapter, damage = {}, {}
local native_original = function(args)
    assert(installed_filter(args))
    advance(args.delay or 11)
    if args.fail then error(failure, 0) end
    return args.damage, nil, 'native_tail', nil
end
ApplyDamage = native_original
function adapter:Apply(args) return ApplyDamage(args) end
function damage:Deal(request)
    if request.inner then self:Deal(request.inner) end
    if request.direct then ApplyDamage(request.direct) end
    return adapter:Apply({attacker = request.attacker, victim = request.victim,
        damage = request.base_damage, damage_type = request.damage_type,
        damage_flags = request.damage_flags, damage_category = request.damage_category,
        delay = request.delay, fail = request.fail})
end
local deal_original, adapter_original = damage.Deal, adapter.Apply
package.loaded['combat/damage_service'], package.loaded['adapters/dota_damage_adapter'] = damage, adapter
local profile = require('tests/manual_extreme_profile')
assert(not profile.run(15))
assert(ApplyDamage == native_original and damage.Deal == deal_original and clock_reads == 0)
tools_mode = true
local function request(source, a, v, amount)
    return {source_kind = source, attacker = a or attacker, victim = v or victim,
        base_damage = amount or 55, damage_type = 2, damage_flags = 0, tags = {'chain', 'jump'}}
end
local function count(...) return select('#', ...), ... end
local function near(value, wanted) assert(math.abs(value - wanted) < 0.00001, tostring(value)) end
assert(profile.run(15, {top = 1}))
assert(filter_service._filter_for_test == installed_filter)
assert(pending.consume_pending ~= pending_original and anti_air.has_damage_taken_aura ~= aura_original)
local fast = request('fast'); fast.delay = 1
damage:Deal(fast)
assert(entity_reads == 0 and #profile.snapshot().damage_details.rows == 0,
    'Fast hits must not inspect or retain unit handles')
local first_request = request('script_chain'); first_request.damage_category = 2
metadata_ms = 100
local n, first, middle, tail, last = count(damage:Deal(first_request))
metadata_ms = 0
assert(n == 4 and first == 55 and middle == nil and tail == 'native_tail' and last == nil)
local capture = profile.snapshot()
local row = assert(capture.damage_details.rows[1])
near(row.elapsed_ms, 13.5)
near(capture.rows.ApplyDamage.max_ms, 13.5)
assert(row.source_kind == 'script_chain' and row.tags == 'chain|jump')
assert(row.damage == 55 and row.requested_damage == 55 and row.damage_type == 2 and row.category == 2)
assert(row.attacker.entindex == 501 and row.attacker.name == 'npc_sr_lightning_tower'
    and row.attacker.kind == 'building' and row.attacker.building_id == 'arrow_tower')
assert(row.target.entindex == 601 and row.target.kind == 'wave_monster' and row.target.boss)
assert(row.origin:find('test_extreme_damage_profile.lua', 1, true))
assert(capture.damage_details.filter_status == 'engine_closure_not_replaced_dynamic_callees_only')
assert(capture.rows['combat.damage_transaction_repository.consume_pending'].calls == 2)
near(capture.rows['systems.anti_air_rules.has_damage_taken_aura'].total_ms, 1)
capture.damage_details.rows[1].attacker.name = 'mutated_snapshot'
assert(profile.snapshot().damage_details.rows[1].attacker.name == 'npc_sr_lightning_tower')

-- Nested service requests restore the enclosing source; unrelated direct
-- native calls must not inherit that source merely because they are nested.
local outer = request('outer', attacker, victim, 99)
outer.inner = request('inner', worker, tree, 77)
outer.direct = {attacker = worker, victim = tree, damage = 88, damage_type = 1}
local lines_before = #lines
damage:Deal(outer)
local details = profile.snapshot().damage_details
assert(details.rows[2].source_kind == 'inner' and details.rows[2].target.kind == 'tree'
    and details.rows[2].attacker.kind == 'worker')
assert(details.rows[3].source_kind == 'native_unclassified' and details.rows[3].requested_damage == 'unavailable')
assert(details.rows[3].category == 'engine_unspecified', 'Do not mistake damage type for category')
assert(details.rows[4].source_kind == 'outer' and details.rows[4].damage == 99)
assert(#lines == lines_before, 'No hit-time diagnostic printing')
local failing = request('failing'); failing.fail = true
local ok, err = pcall(damage.Deal, damage, failing)
assert(not ok and err == failure, 'Preserve exact error object through both wrappers')
ApplyDamage({attacker = attacker, victim = victim, damage = 100, damage_type = 1})
details = profile.snapshot().damage_details
assert(details.rows[5].error and details.rows[5].source_kind == 'failing')
assert(details.rows[6].source_kind == 'native_unclassified', 'Failure must restore the request context')
local opaque = setmetatable({}, {__index = function() error('dead unit access') end})
ApplyDamage({attacker = opaque, victim = opaque, damage = 3})
assert(profile.snapshot().damage_details.metadata_errors == 0, 'Dead entity reads stay isolated')

-- More than twelve spikes keep only twelve largest primitive-only snapshots.
for index = 1, 30 do
    ApplyDamage({attacker = worker, victim = tree, damage = index, delay = 20 + index})
end
details = profile.snapshot().damage_details
assert(#details.rows == 12 and details.omitted == details.slow_calls - 12)
for _, value in ipairs(details.rows) do assert(value.elapsed_ms > 40 and type(value.attacker.entindex) ~= 'table') end
local reads_before = entity_reads
ApplyDamage({attacker = worker, victim = tree, damage = 999, delay = 11})
assert(entity_reads == reads_before, 'Discarded lower spikes must not inspect entities')
assert(profile.stop('damage_test'))
assert(ApplyDamage == native_original and damage.Deal == deal_original and adapter.Apply == adapter_original)
assert(pending.consume_pending == pending_original and tree_rules.is_tree == tree_original
    and anti_air.has_damage_taken_aura == aura_original and armor.war3_physical_damage_multiplier == armor_original)
assert(filter_service._filter_for_test == installed_filter)
local printed_details, printed_stages = 0, 0
for _, line in ipairs(lines) do
    if line:find('[EXTREME_DAMAGE_SLOW]', 1, true) then printed_details = printed_details + 1 end
    if line:find('damage_stage name=', 1, true) then printed_stages = printed_stages + 1 end
end
assert(printed_details == 12 and printed_stages == 6,
    'Bound details; report available fixed damage stages independently of TOP')
local reads_after = clock_reads
damage:Deal(request('after_stop'))
assert(clock_reads == reads_after, 'No diagnostic overhead after stop')

assert(profile.run(15, {damage_details = false}))
assert(damage.Deal == deal_original and pending.consume_pending == pending_original)
assert(profile.snapshot().damage_details == nil and ApplyDamage ~= native_original)
profile.stop('damage_details_disabled')
assert(profile.run(15, {native_api = false}))
assert(ApplyDamage == native_original and damage.Deal == deal_original and profile.snapshot().damage_details == nil)
profile.stop('native_api_disabled')
print = original_print
print('extreme damage profile: PASS (nested context, safe metadata, bounded output, exact semantics, installed filter preserved)')
