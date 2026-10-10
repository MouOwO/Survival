// Exercise the real HUD paint paths and archive tooltip ownership checks.
// This verifies runtime behavior; rendered Workshop pixels are not simulated.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {setup} = require('./test_combat_stats_callbacks.cjs');
const source = fs.readFileSync(process.env.SURVIVAL_TOOLTIP_TEST_SOURCE
    || 'panorama/src/scripts/custom_game/ability_tooltip.js', 'utf8');
const names = new Map(), slots = new Map();
const hud = setup({portrait: true, abilities: {
    GetAbilityName: ability => names.get(ability) || '', IsPassive: () => false,
}});
const official = new hud.Panel('abilities', hud.root);
let selected = 7;
const tooltip = {
    bindingSnapshot: null,
    maxAbilityEngineSlots: 32,
    bindingPerformance: {abilityScans: 0},
    readTooltipTable: (_, key) => hud.runtime[key] || null,
    Abilities: {GetAbilityName: ability => names.get(ability) || '', IsHidden: () => false},
    Entities: {
        GetAbility: (unit, slot) => (slots.get(Number(unit)) || [])[slot] ?? -1,
        GetUnitName: unit => 'npc_archive_challenge_' + (Number(unit) - 6),
    },
};
function extract(first, last) {
    const start = source.indexOf('    function ' + first + '(');
    const end = source.indexOf('    function ' + last + '(', start);
    assert(start >= 0 && end > start, 'Missing production tooltip anchors: ' + first);
    return source.slice(start, end);
}
vm.runInNewContext(extract('managedRuntime', 'selectedUnit'), tooltip);
vm.runInNewContext(extract('unitAbilityCount', 'visibleAbilityEntries'), tooltip);
vm.runInNewContext(extract('unitOwnsAbility', 'engineSlotForAbility'), tooltip);
vm.runInNewContext(extract('isManagedBuildingAction', 'isLumberjackAbility'), tooltip);
vm.runInNewContext(extract('managedProjectAbility', 'isSelectedBuilderVisibleAbility'), tooltip);

function binding(unit, ability, name) {
    selected = unit;
    hud.select(unit, 'npc_archive_challenge_' + (unit - 6));
    names.set(ability, name);
    slots.set(unit, [ability]);
    hud.runtime['unit:' + unit] = {owner_entindex: unit, ability_count: 1};
    const panel = new hud.Panel('Ability' + unit, official);
    const anchor = new hud.Panel('AbilityButton', panel);
    const image = new hud.Panel('AbilityImage', anchor);
    new hud.Panel('HotkeyContainer', panel);
    image.values.saturation = '1';
    image.values.brightness = '1';
    let writes = 0;
    image.style = new Proxy(image.style, {
        get(target, key) {
            const value = target[key];
            return (key === 'saturation' || key === 'brightness') && Number.isFinite(parseFloat(value))
                ? parseFloat(value).toFixed(3) : value;
        },
        set(target, key, value) { writes++; target[key] = value; return true; },
    });
    panel.BHasClass = name => !!(panel.classes && panel.classes[name]);
    return {entry: {ability, name, slot: 0}, panel, anchor, image, nodeIndex: 0,
        writes: () => writes, reset: () => { writes = 0; }};
}
function directPaint(mapping) {
    hud.api.applyAbilityRuntime(mapping.panel, mapping.entry.ability);
}
function nativeRefresh(mapping) {
    assert(hud.api.refreshOfficialUtilityHotkeys([mapping.entry], [mapping]));
}
function row(mapping, ready) {
    return {ability_name: mapping.entry.name, ability_entindex: mapping.entry.ability,
        owner_entindex: selected, available: ready ? 1 : 0,
        prerequisite_met: ready ? 1 : 0, can_afford: 1,
        status_text: ready ? '可以挑战' : '本局已挑战（每个技能仅限一次）'};
}
function stable(mapping, ready) {
    directPaint(mapping);
    mapping.reset();
    for (let frame = 0; frame < 40; frame++) {
        nativeRefresh(mapping);
        directPaint(mapping);
        assert.equal(Number(mapping.image.style.saturation), ready ? 1 : 0);
        assert.equal(Number(mapping.image.style.brightness), ready ? 1 : 0.45);
        assert.equal(mapping.panel.BHasClass('DOTADisabled'), !ready);
        assert.equal(mapping.panel.hittest, true, 'locked archive buttons retain hover');
    }
    assert.equal(mapping.writes(), 0, 'stable archive state must not rewrite native colors');
}

const legacy = binding(7, 100, 'ability_archive_shadow_1');
hud.runtime['100'] = {ability_name: legacy.entry.name, owner_entindex: 7,
    available: 0, can_afford: 1};
directPaint(legacy);
assert.equal(Number(legacy.image.style.saturation), 0);
nativeRefresh(legacy);
assert.equal(Number(legacy.image.style.saturation), 1,
    'incomplete archive identity reproduces the old gray/bright conflict');
assert.equal(tooltip.managedProjectAbility(100, legacy.entry.name), false);

for (const [unit, ability, name] of [
    [7, 101, 'ability_archive_shadow_2'],
    [8, 102, 'ability_archive_endless'],
    [9, 103, 'ability_archive_finish'],
]) {
    const mapping = binding(unit, ability, name);
    for (const ready of [false, true, false, true]) {
        hud.runtime[ability] = row(mapping, ready);
        assert.equal(tooltip.managedProjectAbility(ability, name), true,
            name + ': complete archive identity enables its project tooltip');
        stable(mapping, ready);
    }
    hud.runtime[ability].owner_entindex = unit === 7 ? 8 : 7;
    assert.equal(tooltip.managedProjectAbility(ability, name), false,
        'an archive prefix cannot bypass the actual caster ownership check');
    hud.runtime[ability] = row(mapping, true);
    hud.runtime[ability].ability_entindex = ability + 1000;
    assert.equal(tooltip.managedProjectAbility(ability, name), false,
        'reused or mismatched ability identities remain rejected');
    hud.runtime[ability] = {...row(mapping, true), removed: 1};
    assert.equal(tooltip.managedProjectAbility(ability, name), false,
        'removed archive skills cannot retain tooltip management');
}
console.log('ARCHIVE_RUNTIME_FLICKER_PASS: legacy conflict reproduced; challenge/endless/finish stable over 40 alternating paints with zero color writes; tooltip identity, ownership and removal checks');
