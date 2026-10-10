const fs = require('fs');
const vm = require('vm');
const assert = require('assert');
const path = process.argv[2] || 'panorama/src/scripts/custom_game/combat_stats.js';
const source = fs.readFileSync(path, 'utf8');
const before = process.argv[3] && fs.readFileSync(process.argv[3], 'utf8');

function fixture(code) {
  const first = code.indexOf('    function abilityIndexForSlot(');
  const end = code.indexOf('    function refreshInventory()', first);
  const hotkeyFirst = code.indexOf('    function hotkeyForAbilityEntry(');
  const hotkeyEnd = code.indexOf('    function refreshOfficialUtilityHotkeys(', hotkeyFirst);
  assert(first >= 0 && end > first && hotkeyFirst >= 0 && hotkeyEnd > hotkeyFirst,
    'execute actual production enumeration, ordering and passive hotkey functions');
  const state = {
    unit: 12, name: 'npc_fixture_hero', metadata: null, slots: [], names: {}, hidden: new Set(),
    passive: new Set(), runtime: {}, throwSlot: -1, throwHidden: -1, countQueries: 0, abilityReads: 0,
  };
  const env = {
    Entities: {
      GetUnitName: () => state.name,
      GetAbility: (unit, slot) => {
        assert.equal(unit, state.unit);state.abilityReads++;
        if (slot === state.throwSlot) throw new Error('removed native slot');
        return state.slots[slot] === undefined ? -1 : state.slots[slot];
      },
    },
    Abilities: {
      GetAbilityName: ability => state.names[ability] || '',
      IsHidden: ability => {
        if (ability === state.throwHidden) throw new Error('native hidden state unavailable');
        return state.hidden.has(ability);
      },
    },
    CustomNetTables: {GetTableValue: (table, key) => {
      assert.equal(table, 'survival_ability_runtime');
      assert.equal(key, `unit:${state.unit}`);state.countQueries++;return state.metadata;
    }},
    utilityHotkeys: {ability_utility_late: 'F2', ability_utility_first: 'G'},
    utilityDisplayOrder: {ability_utility_late: 20, ability_utility_first: 10},
    standardAbilityHotkeys: ['Q', 'W', 'E', 'R', 'T', 'Y'], builderHotkeysBySlotOrder: [],
    isPassiveAbility: ability => state.passive.has(ability),
    abilityRuntime: ability => state.runtime[ability] || {},
  };
  vm.createContext(env);
  vm.runInContext(code.slice(first, end) + code.slice(hotkeyFirst, hotkeyEnd), env);
  function add(slot, name, options = {}) {
    const ability = 100 + slot;state.slots[slot] = ability;state.names[ability] = name;
    if (options.hidden) state.hidden.add(ability);
    if (options.passive) state.passive.add(ability);
    if (options.completed) state.runtime[ability] = {completed: 1};
    return ability;
  }
  function count(n) {state.metadata = {owner_entindex: state.unit, ability_count: n};}
  function run(visible = false) {
    state.countQueries = 0;state.abilityReads = 0;
    const result = (visible ? env.visibleAbilityEntries : env.nativeAbilityEntries)(state.unit);
    return JSON.parse(JSON.stringify({result, countQueries: state.countQueries, abilityReads: state.abilityReads}));
  }
  return {state, env, add, count, run};
}

function sixAbilities(code, metadata, visible = false) {
  const test = fixture(code);
  for (let slot = 0; slot < 6; slot++) test.add(slot, `ability_active_${slot}`);
  if (metadata) test.count(6);
  return test.run(visible);
}
const withMetadata = sixAbilities(source, true);
assert.equal(withMetadata.result.length, 6);
assert.equal(withMetadata.countQueries, 1, 'one unit count lookup per synchronous enumeration');
assert.equal(withMetadata.abilityReads, 6);
const withoutMetadata = sixAbilities(source, false);
assert.equal(withoutMetadata.countQueries, 1);
assert.equal(withoutMetadata.abilityReads, 16, 'one 10-slot fallback discovery plus six slot reads');
for (const metadata of [true, false]) {
  const visible = sixAbilities(source, metadata, true);
  assert.deepEqual(visible, sixAbilities(source, metadata), 'visible enumeration shares one count snapshot');
}
if (before) {
  const oldWith = sixAbilities(before, true), oldWithout = sixAbilities(before, false);
  assert.deepEqual(withMetadata.result, oldWith.result);
  assert.deepEqual(withoutMetadata.result, oldWithout.result);
  assert.equal(oldWith.countQueries, 13);
  assert.equal(oldWithout.countQueries, 13);
  assert.equal(oldWithout.abilityReads, 136);
  console.log('ENUMERATION_COUNT_BEFORE_AFTER: metadata table reads13->1; missing metadata native slot reads136->16, identical six entries');
}

function behavior(code) {
  const test = fixture(code), outputs = [];
  test.add(0, 'ability_active');
  const passive = test.add(1, 'ability_passive', {passive: true});
  test.add(2, 'special_bonus_fixture');test.add(3, 'ability_hidden', {hidden: true});
  test.add(4, 'ability_utility_late');test.add(5, 'ability_utility_first');test.count(6);
  outputs.push(test.run().result);
  assert.deepEqual(outputs[0].map(entry => entry.name),
    ['ability_active', 'ability_passive', 'ability_utility_first', 'ability_utility_late']);
  assert.equal(outputs[0][1].standardHotkeyIndex, -1);
  assert.equal(test.env.hotkeyForAbilityEntry(outputs[0][1], test.state.name), '', 'passive has no key');
  assert.equal(test.env.hotkeyForAbilityEntry(outputs[0][0], test.state.name), 'Q');
  test.state.runtime[passive] = {completed: 1};
  outputs.push(test.run(true).result);
  assert(!outputs[1].some(entry => entry.ability === passive), 'completed ability remains filtered');
  test.add(6, 'ability_learned');test.count(7);
  outputs.push(test.run(true).result);
  assert(outputs[2].some(entry => entry.name === 'ability_learned'), 'next refresh discovers learned skill');
  test.state.slots[6] = -1;test.count(5);
  outputs.push(test.run(true).result);
  assert(!outputs[3].some(entry => entry.name === 'ability_learned' || entry.name === 'ability_utility_first'),
    'next refresh observes ability removal and count decrease');
  test.state.hidden.delete(103);
  outputs.push(test.run(true).result);
  assert(outputs[4].some(entry => entry.name === 'ability_hidden'), 'hidden flag changes are read again');
  test.state.throwSlot = 3;
  outputs.push(test.run(true).result);
  assert(!outputs[5].some(entry => entry.slot === 3), 'native slot exception skips only that slot');
  test.state.throwSlot = -1;test.state.throwHidden = 103;
  outputs.push(test.run(true).result);
  assert(outputs[6].some(entry => entry.slot === 3), 'hidden-state exceptions retain original fallback');

  const sparse = fixture(code);
  sparse.add(0, 'ability_zero');sparse.add(3, 'ability_three');sparse.add(5, 'ability_five');
  outputs.push(sparse.run().result);
  assert.deepEqual(outputs[7].map(entry => entry.slot), [0, 3, 5], 'missing metadata retains sparse fallback discovery');
  sparse.add(23, 'ability_last_sparse_slot');sparse.count(24);
  outputs.push(sparse.run().result);
  assert(outputs[8].some(entry => entry.slot === 23), 'authoritative count retains late sparse ability');
  sparse.state.metadata = {owner_entindex: 999, ability_count: 24};
  outputs.push(sparse.run().result);
  assert(!outputs[9].some(entry => entry.slot === 23), 'stale owner metadata still uses existing fallback');
  sparse.state.metadata = {owner_entindex: 12, ability_count: 24, removed: 1};
  outputs.push(sparse.run().result);
  assert.deepEqual(outputs[9], outputs[10], 'removed metadata still uses existing fallback');

  for (const name of ['npc_survival_repairer_1', 'npc_survival_lumberjack_1', 'npc_survival_super_lumberjack_1']) {
    const worker = fixture(code);worker.state.name = name;
    worker.add(0, 'ability_unrelated');worker.add(1, 'ability_repairer_suicide');
    worker.add(2, 'ability_fuse_lumberjack_2');worker.add(3, 'ability_lumberjack_personality_hardworking');
    worker.count(4);const entries = worker.run().result;outputs.push(entries);
    assert.deepEqual(entries.map(entry => entry.name), name.includes('repairer')
      ? ['ability_repairer_suicide'] : ['ability_fuse_lumberjack_2', 'ability_lumberjack_personality_hardworking']);
  }
  const empty = fixture(code);const emptyResult = empty.run();outputs.push(emptyResult.result);
  assert.equal(emptyResult.abilityReads, 24, 'empty missing metadata keeps bounded 24-slot discovery');
  return outputs;
}
const currentBehavior = behavior(source);
if (before) assert.deepEqual(currentBehavior, behavior(before), 'all actual enumeration results match saved baseline');
console.log('ABILITY_ENUMERATION_COUNT_PASS: one count per refresh, metadata fallback, sparse slots, learning/removal, hidden/completed filters, passive keys, worker roles and native exceptions');
