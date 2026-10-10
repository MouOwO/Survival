// Exercise the actual private snapshot receiver and the two competing native
// HUD paint paths. Optional argument runs against a pre-fix production source.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const dir = 'panorama/src/scripts/custom_game/';
const source = fs.readFileSync(process.argv[2] || dir + 'production_progress.js', 'utf8');
const combat = fs.readFileSync(dir + 'combat_stats.js', 'utf8');
const nodes = {}, callbacks = {}, publicRows = {}, sent = [];
let selected = 20;
function panel(id = '') {
    const p = {id, style: {}, classes: new Set(), IsValid: () => true,
        FindChildTraverse: name => nodes[name] || null,
        AddClass(name) { this.classes.add(name); },
        SetHasClass(name, on) { on ? this.classes.add(name) : this.classes.delete(name); },
        BHasClass(name) { return this.classes.has(name); },
        RemoveAndDeleteChildren() {}, SetPanelEvent() {}, SetImage() {}};
    if (id) nodes[id] = p;
    return p;
}
const ctx = panel('Context');
panel('SurvivalProductionPanel'); panel('SurvivalResearchAutoMarkers');
const cfg = {SurvivalSelectionResolver: {ResolveDisplayUnit: () => selected}};
const $ = {GetContextPanel: () => ctx, CreatePanel: (type, parent, id) => panel(id),
    DispatchEvent() {}, Schedule() {}};
const env = {$, GameUI: {CustomUIConfig: () => cfg},
    Game: {GetLocalPlayerID: () => 0, GetGameTime: () => 10},
    Players: {GetLocalPlayerPortraitUnit: () => selected},
    Entities: {GetUnitName: id => id === 20 ? 'building_research_lab' : 'building_advanced_research_lab'},
    CustomNetTables: {GetTableValue: (table, key) => publicRows[key]},
    GameEvents: {Subscribe: (name, fn) => { callbacks[name] = fn; },
        SendCustomGameEventToServer: (name, payload) => sent.push({name, payload})}};
vm.runInNewContext(source, env);
const hud = cfg.SurvivalProductionHUD;
const paint = {...env, selectedUnit: () => selected, validPortraitPanel: value => !!value};
function slice(first, last) {
    const start = combat.indexOf(first), end = combat.indexOf(last, start);
    assert(start >= 0 && end > start, 'production paint anchors must exist');
    return combat.slice(start, end);
}
vm.runInNewContext(slice('    function abilityRuntime(', '    function officialAbilityButtonAnchor('), paint);
vm.runInNewContext(slice('    function refreshOfficialAbilityRuntime(', '    function createAbilitySlot('), paint);
function binding(ability, name) {
    const p = panel(), image = panel(), writes = [];
    image.style = new Proxy({saturation: '1', brightness: '1'}, {
        set(target, key, value) { writes.push([key, value]); target[key] = value; return true; }
    });
    p.FindChildTraverse = id => id === 'AbilityImage' ? image : null;
    publicRows[ability] = {ability_name: name, ability_entindex: ability, owner_entindex: selected,
        technology_group: name.slice('ability_research_'.length), prerequisite_met: 1, available: 1};
    return {entry: {ability, name}, panel: p, image, writes};
}
function snapshot(rows, sequence, extra = {}) {
    callbacks.ui_selected_unit_stats_snapshot({success: 1, entindex: selected, player_id: 0,
        refresh_sequence: sequence, research: {abilities_by_name: rows}, ...extra});
}
function stable(mapping, locked) {
    const {panel: p, image, entry, writes} = mapping;
    paint.applyAbilityRuntime(p, entry.ability); // topnav's direct paint
    writes.length = 0;
    for (let i = 0; i < 20; i++) {
        paint.refreshOfficialAbilityRuntime([mapping]); // managed combat refresh
        assert.equal(image.style.saturation, locked ? '0' : '1', entry.name + ': combat refresh changed tint');
        assert.equal(p.BHasClass('DOTADisabled'), locked);
        paint.applyAbilityRuntime(p, entry.ability);
        assert.equal(image.style.brightness, locked ? '0.45' : '1');
    }
    assert.equal(writes.length, 0, 'stable prerequisites must not repeatedly write gray/bright styles');
    const row = hud.GetResearchRuntime(entry.ability, selected, publicRows[entry.ability]);
    assert.equal(row.ability_entindex, entry.ability);
    assert.equal(row.owner_entindex, selected);
}
const T = binding(201, 'ability_research_advanced_lumberjack_efficiency');
const locked = {prerequisite_met: 0, available: 0, can_afford: 1, resource_check_on_cast: 1};
snapshot({[T.entry.name]: locked}, 1);
stable(T, true); // pre-fix fails here: combat refresh restores the bright icon
// Partial stats events and out-of-order snapshots cannot clear viewer locks.
callbacks.ui_selected_unit_stats_snapshot({success: 1, entindex: selected, refresh_sequence: 2, attack: 50});
snapshot({[T.entry.name]: {prerequisite_met: 1, available: 1}}, 1);
stable(T, true);
// Actual unlock restores brightness once; execution state does not change the learning gate.
snapshot({[T.entry.name]: {prerequisite_met: 1, available: 0, can_afford: 0,
    research_status_code: 'research_queue_full'}}, 3);
stable(T, false);
snapshot({[T.entry.name]: locked}, 4);
stable(T, true);

selected = 21;
const advanced = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map((n) => binding(300 + n, 'ability_research_ars_' + String(n).padStart(2, '0')));
// Shared-lab owner's public skills are unlocked; viewer data has not arrived yet.
for (const mapping of advanced) {
    stable(mapping, true);
    assert.equal(hud.GetResearchRuntime(mapping.entry.ability, selected, publicRows[mapping.entry.ability]).research_status_code, 'syncing');
}
const privateRows = Object.fromEntries(advanced.map((m, i) => [m.entry.name,
    {prerequisite_met: i % 3 === 0 ? 1 : 0, available: i % 3 === 0 ? 1 : 0}]));
snapshot(privateRows, 1);
for (let pass = 0; pass < 3; pass++) {
    for (const [i, mapping] of advanced.entries()) {
        // Another player's public availability fluctuates independently.
        publicRows[mapping.entry.ability].prerequisite_met = pass % 2;
        publicRows[mapping.entry.ability].available = pass % 2;
        stable(mapping, i % 3 !== 0);
    }
}
snapshot(Object.fromEntries(advanced.map(m => [m.entry.name, {prerequisite_met: 1, available: 1}])), 20, {player_id: 1});
stable(advanced[1], true); // other player's private response is ignored
assert.equal(hud.QueueResearch(advanced[1].entry.ability, selected), false);
assert.equal(sent.length, 0, 'locked private state blocks input as well as tint');
// Selecting another lab and back must retain each lab's private state.
selected = 20; stable(T, true);
selected = 21; stable(advanced[1], true);
const ordinary = {ability_name: 'ability_upgrade_tower', ability_entindex: 700};
assert.strictEqual(hud.GetResearchRuntime(700, selected, ordinary), ordinary);
console.log('RESEARCH_RUNTIME_FLICKER_PASS: real snapshot lifecycle, repeated native paint, pending data, shared viewer locks and unlocks');
