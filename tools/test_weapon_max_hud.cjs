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
const check = (i, expected) => {
    assert.equal(!!(max(i) && max(i).visible), expected);
    for (const key of ['ItemCharges', 'ItemAltCharges', 'ItemChargesContainer']) {
        assert.equal(slots[i].children[key].style.opacity, expected ? '0' : '1');
    }
    if (expected) { assert.equal(max(i).text, 'MAX'); assert.equal(max(i).hittest, false); }
};
for (const family of ['growth_sword', 'frost_blade', 'ice_blade']) {
    items[0] = 'item_survival_' + family + '_04'; identities[0] = {is_max_level: 0}; refresh(); check(0, false);
    items[0] = 'item_survival_' + family + '_max'; identities[0] = {is_max_level: 1}; refresh(); check(0, true);
    const count = created; for (let i = 0; i < 10; i++) refresh(); assert.equal(created, count);
    // Native engine name fallback still works before identity replication arrives.
    delete identities[0]; refresh(); check(0, true);
}
items[0] = 'item_survival_legend_abyss_10'; identities[0] = {is_max_level: 1}; refresh(); check(0, true);
items[6] = items[0]; identities[6] = identities[0]; items[0] = null; refresh(); check(0, false); check(6, true);
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
console.log('WEAPON_MAX_HUD_PASS: real inventory renderer MAX/charge hiding, repeated refresh, backpack, lower level/native restoration; combat MAX and reduced progress');
