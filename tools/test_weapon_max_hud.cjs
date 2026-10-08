const fs = require('fs'), vm = require('vm'), assert = require('assert');
class Panel {
    constructor() { this.style = {}; this.children = {}; this.visible = true; }
    FindChildTraverse(id) { return this.children[id] || null; }
}
const inventory = new Panel(), items = [], identities = {};
const slots = Array.from({length: 9}, (_, i) => {
    const slot = inventory.children['inventory_slot_' + i] = new Panel();
    for (const name of ['ItemCharges', 'ItemAltCharges', 'ItemChargesContainer']) slot.children[name] = new Panel();
    return slot;
});
let created = 0;
const env = {cfg: {}, valid: p => !!p, native: () => inventory, selectedUnit: () => 7,
    Entities: {GetItemInSlot: (_, i) => items[i] ? i : -1}, Abilities: {GetAbilityName: i => items[i]},
    CustomNetTables: {GetTableValue: (_, id) => identities[id]},
    style: (p, values) => Object.assign(p.style, values),
    child: (p, id, values) => Object.assign(p.children[id].style, values),
    $: {CreatePanel: (type, p, id) => { assert.equal(type, 'Label'); created++; return p.children[id] = new Panel(); }}};
const source = fs.readFileSync('panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js', 'utf8');
vm.runInNewContext(source.slice(source.indexOf('    function refreshInventoryPresentation()'), source.indexOf('    function nativeLayout(')), env);
const refresh = () => env.refreshInventoryPresentation();
const max = i => slots[i].children.SurvivalInventoryArmorMax;
const check = (i, expected, label = 'MAX') => {
    assert.equal(!!(max(i) && max(i).visible), expected);
    for (const key of ['ItemCharges', 'ItemAltCharges', 'ItemChargesContainer']) {
        assert.equal(slots[i].children[key].style.opacity, expected ? '0' : '1');
    }
    if (expected) { assert.equal(max(i).text, label); assert.equal(max(i).hittest, false); }
};
for (const family of ['growth_sword', 'frost_blade', 'ice_blade']) {
    items[0] = 'item_survival_' + family + '_04'; identities[0] = {is_max_level: 0}; refresh(); check(0, false);
    items[0] = 'item_survival_' + family + '_max'; identities[0] = {is_max_level: 1}; refresh(); check(0, true);
    const count = created; for (let i = 0; i < 10; i++) refresh(); assert.equal(created, count);
    // Native engine name fallback still works before identity replication arrives.
    delete identities[0]; refresh(); check(0, true);
}
// Native name fallback renders enhancement before identity replication arrives.
for (const family of ['epic_icefire', 'legend_abyss']) {
    const terminal = family === 'legend_abyss' ? 10 : 6;
    for (let level = 0; level <= terminal; level++) {
        items[0] = 'item_survival_' + family + '_' + String(level).padStart(2, '0');
        delete identities[0]; refresh(); check(0, true, '+' + Math.max(1, level));
        identities[0] = {content_id: 'weapon_' + family + '_' + String(level).padStart(2, '0'),
            is_max_level: level === 10 ? 1 : 0, upgrade_level: Math.max(1, level)};
        refresh(); check(0, true, '+' + Math.max(1, level));
        const count = created; refresh(); refresh(); assert.equal(created, count);
    }
}
items[0] = 'item_survival_legend_abyss_10'; identities[0] = {is_max_level: 1, upgrade_level: 10}; refresh(); check(0, true, '+10');
items[6] = items[0]; identities[6] = identities[0]; items[0] = null; refresh(); check(0, false); check(6, true, '+10');
identities[6] = {is_max_level: 1, removed: 1}; refresh(); check(6, false);
items[6] = 'item_survival_ice_blade_01'; identities[6] = {is_max_level: 0}; refresh(); check(6, false);
items[6] = 'item_blink'; delete identities[6]; refresh(); check(6, false);

// Execute the actual combat progress rendering statement as well.
const combat = fs.readFileSync('panorama/src/scripts/custom_game/combat_stats.js', 'utf8');
let text;
const render = combat.slice(combat.indexOf('        var target = Number(snapshot.stage_attack_target'), combat.indexOf('        setText("CombatScaleValue"'));
const renderEnv = {snapshot: {is_max_level: 1, stage_attack_count: 99, stage_attack_target: 200},
    formatNumber: String, setText: (id, value) => { assert.equal(id, 'CombatProgressValue'); text = value; }};
vm.runInNewContext(render, renderEnv); assert.equal(text, 'MAX');
renderEnv.snapshot = {is_max_level: 0, stage_attack_count: 10, stage_attack_target: 165};
vm.runInNewContext(render, renderEnv); assert.equal(text, '攻击次数 10/165');
console.log('WEAPON_MAX_HUD_PASS: MAX and +1..+10 enhancement, native fallback, no counter overlap, repeated refresh, backpack/removal and other item restoration; combat progress unchanged');
