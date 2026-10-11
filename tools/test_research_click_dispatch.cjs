// Exercise production snapshot admission through the real central ability
// dispatcher. Public owner rows can lag behind a complete viewer projection.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');
const scriptDir = path.join(root, 'panorama/src/scripts/custom_game');
const production = fs.readFileSync(process.argv[2] || path.join(scriptDir, 'production_progress.js'), 'utf8');
const combat = fs.readFileSync(path.join(scriptDir, 'combat_stats.js'), 'utf8');
function slice(first, last) {
    const start = combat.indexOf(first), end = combat.indexOf(last, start);
    assert(start >= 0 && end > start, 'real combat dispatch source anchors exist');
    return combat.slice(start, end);
}
function fixture({unit = 718, player = 0, ability = 721, name = 'ability_research_tower_attack', shared = false} = {}) {
    const nodes = {}, callbacks = {}, publicRows = {}, requests = [], messages = [], pending = [];
    let selected = unit, sequence = 0, modal = null;
    function panel(id = '') {
        const value = {id, style: {}, text: '', visible: true, handlers: {}, classes: new Set(),
            IsValid: () => true, FindChildTraverse: key => nodes[key] || null,
            RemoveAndDeleteChildren() {}, SetImage() {},
            AddClass(key) { this.classes.add(key); },
            SetHasClass(key, on) { on ? this.classes.add(key) : this.classes.delete(key); },
            SetPanelEvent(key, fn) { this.handlers[key] = fn; }};
        if (id) nodes[id] = value;
        return value;
    }
    const ctx = panel('Context');
    panel('SurvivalProductionPanel'); panel('SurvivalResearchAutoMarkers');
    const cfg = {SurvivalSelectionResolver: {ResolveDisplayUnit: () => selected},
        SurvivalUILayers: {Top: () => modal}};
    const engineBindings = {[unit]: [ability]};
    const $ = {GetContextPanel: () => ctx, CreatePanel: (type, parent, id) => panel(id),
        DispatchEvent() {}, Schedule: (delay, fn) => pending.push(fn),
        Msg: (...parts) => messages.push(parts.join('')), Warning: (...parts) => messages.push(parts.join(''))};
    const env = {$, GameUI: {CustomUIConfig: () => cfg},
        Game: {GetLocalPlayerID: () => player, GetGameTime: () => 10},
        Players: {GetLocalPlayerPortraitUnit: () => selected},
        Entities: {GetUnitName: id => Number(id) === unit
            ? (shared ? 'building_advanced_research_lab' : 'building_research_lab') : 'npc_survival_builder_proxy'},
        Abilities: {GetAbilityName: id => Number(id) === ability ? name : ''},
        CustomNetTables: {GetTableValue: (table, key) => table === 'survival_ability_runtime' ? publicRows[key] : undefined},
        GameEvents: {Subscribe: (event, fn) => { callbacks[event] = fn; },
            SendCustomGameEventToServer: (event, payload) => requests.push({event, payload})}};
    publicRows[ability] = {ability_name: name, ability_entindex: ability, owner_entindex: unit,
        technology_group: name.slice('ability_research_'.length), prerequisite_met: 1, available: 1, can_afford: 1};
    vm.runInNewContext(production, env, {filename: 'production_progress.js'});
    const hud = cfg.SurvivalProductionHUD;
    assert(hud, 'real production module initializes');
    const dispatch = {...env, selectedUnit: () => selected,
        unitAbilityCount: id => (engineBindings[id] || []).length,
        abilityIndexForSlot: (id, slot) => (engineBindings[id] || [])[slot]};
    vm.runInNewContext(slice('    function abilityRuntime(', '    function setAbilityRuntimeDisabled('), dispatch);
    vm.runInNewContext(slice('    function unitOwnsAbility(', '    function setPointTargetHint('), dispatch);
    vm.runInNewContext(slice('    function executeAbility(', '    // ability_tooltip.js loads first'), dispatch);
    const geometry = {x: 350, y: 700, scale: .5, height: 330, centerWidth: 618, minimapSize: 220};
    function publish(row, extra = {}, snapshotPlayer = player) {
        callbacks.ui_selected_unit_stats_snapshot({success: 1, player_id: snapshotPlayer, entindex: unit,
            refresh_sequence: ++sequence, research: {abilities_by_name: row ? {[name]: row} : {}, ...extra}});
        hud.Refresh(geometry, selected, true, [{ability, name}]);
    }
    function learn() { return dispatch.executeAbility(ability); }
    function sent() { return requests.filter(request => request.event === 'ui_research_queue_request'); }
    return {hud, dispatch, publicRows, callbacks, nodes, messages, requests, publish, learn, sent,
        select: id => { selected = id; }, modal: id => { modal = id; },
        unit, ability, name};
}
const viewer = (group = 'tower_attack', extra = {}) => ({technology_group: group,
    prerequisite_met: 1, available: 1, can_afford: 1, resource_check_on_cast: 1,
    research_status_code: 'queue_available', status_text: '可加入研究队列', ...extra});
function assertRequest(f, group) {
    assert.equal(f.sent().length, 1, 'one click emits exactly one research queue intent');
    const {payload} = f.sent()[0];
    assert.equal(payload.source_entindex, f.unit, 'server source is the actual selected laboratory');
    assert.equal(payload.technology_group, group, 'technology identity follows the viewer projection');
    assert.match(payload.request_id, /^production_research_/, 'response uses a production correlation ID');
    return payload;
}
const failures = [];
let passed = 0;
function test(name, run) {
    try { run(); passed++; console.log('PASS ' + name); }
    catch (error) { failures.push(name); console.error('FAIL ' + name + ': ' + error.message); }
}
test('complete private snapshot survives absent public technology metadata', () => {
    const f = fixture();
    f.publicRows[f.ability] = {ability_name: f.name, ability_entindex: f.ability, owner_entindex: f.unit};
    f.publish(viewer());
    assert.equal(f.dispatch.abilityRuntime(f.ability).available, 1, 'tooltip and dispatcher see available private data');
    assert.equal(f.learn(), true, 'the same available research can be queued');
    assertRequest(f, 'tower_attack');
});
test('complete private snapshot remains usable before the public row arrives', () => {
    const f = fixture();
    delete f.publicRows[f.ability];
    f.publish(viewer());
    assert.equal(f.dispatch.abilityRuntime(f.ability).ability_name, f.name,
        'real engine ability identifies the private row without a public row');
    assert.equal(f.learn(), true);
    assertRequest(f, 'tower_attack');
});
test('reused entity index resolves the current engine name instead of stale public name', () => {
    const f = fixture();
    Object.assign(f.publicRows[f.ability], {ability_name: 'ability_research_lumberjack_speed',
        technology_group: 'lumberjack_speed', owner_entindex: 999, removed: 1});
    f.publish(viewer());
    const projected = f.dispatch.abilityRuntime(f.ability);
    assert.equal(projected.ability_name, f.name, 'private lookup uses the current engine name');
    assert.equal(projected.owner_entindex, f.unit, 'private binding follows the selected laboratory');
    assert.equal(projected.removed, undefined, 'old entity removal cannot invalidate a current private projection');
    assert.equal(f.learn(), true);
    assertRequest(f, 'tower_attack');
});
test('stale public owner and group cannot replace current engine binding and private group', () => {
    const f = fixture();
    f.publicRows[f.ability].owner_entindex = 999;
    f.publicRows[f.ability].technology_group = 'lumberjack_speed';
    f.publish(viewer());
    assert.equal(f.learn(), true, 'authoritative viewer data remains usable after owner metadata lags');
    assertRequest(f, 'tower_attack');
});
test('shared laboratory uses viewer prerequisite and lets server validate current wallet', () => {
    const f = fixture({unit: 850, player: 1, ability: 830, name: 'ability_research_ars_05', shared: true});
    f.publicRows[f.ability].available = 0;
    f.publicRows[f.ability].prerequisite_met = 0;
    f.publicRows[f.ability].completed = 1;
    f.publish(viewer('researcher_super_tower_attack', {available: 0, can_afford: 0,
        completed: 0, research_status_code: 'insufficient_resources', status_text: '木材不足'}));
    assert.equal(f.learn(), true, 'stale resource projection still reaches authoritative server validation');
    assertRequest(f, 'researcher_super_tower_attack');
});
test('automatic research toggles the same private technology as a manual click', () => {
    const f = fixture({unit: 850, player: 1, ability: 830, name: 'ability_research_ars_05', shared: true});
    f.publicRows[f.ability] = {ability_name: 'ability_research_lumberjack_speed',
        technology_group: 'lumberjack_speed', owner_entindex: 999, auto_research_available: 0};
    f.publish(viewer('researcher_super_tower_attack', {auto_research_available: 1, auto_research_enabled: 0}));
    assert.equal(f.hud.ToggleResearch(f.ability, f.unit), true);
    const toggles = f.requests.filter(request => request.event === 'ui_shop_auto_research_toggle_request');
    assert.equal(toggles.length, 1);
    assert.equal(toggles[0].payload.technology_group, 'researcher_super_tower_attack');
    assert.equal(toggles[0].payload.source_entindex, f.unit);
    assert.equal(f.learn(), true);
    assertRequest(f, toggles[0].payload.technology_group);
    f.publish(viewer('researcher_super_tower_attack', {auto_research_available: 0, auto_research_enabled: 0,
        prerequisite_met: 0, available: 0, research_status_code: 'prerequisite_not_met'}));
    assert.equal(f.hud.ToggleResearch(f.ability, f.unit), false, 'viewer learning lock also prevents enabling automation');
    assert.equal(f.requests.filter(request => request.event === 'ui_shop_auto_research_toggle_request').length, 1);
});
test('shared viewer lock overrides another player unlocked public state', () => {
    const f = fixture({unit: 850, player: 1, shared: true});
    f.publish(viewer('tower_attack', {prerequisite_met: 0, available: 0,
        research_status_code: 'prerequisite_not_met'}));
    f.publish(viewer(), {}, 0); // An unrelated player's private response must be ignored.
    assert.equal(f.learn(), false);
    assert.equal(f.sent().length, 0);
});
test('unsynchronized and completed research do not create queue requests', () => {
    const f = fixture();
    assert.equal(f.learn(), false, 'absence of a viewer snapshot is a real learning lock');
    assert.equal(f.sent().length, 0);
    f.publish(viewer('tower_attack', {completed: 1}));
    assert.equal(f.learn(), false, 'completed technology cannot be added');
    assert.equal(f.sent().length, 0);
});
test('full research queue reaches server instead of silently swallowing the click', () => {
    const f = fixture();
    f.publish(viewer('tower_attack', {available: 0, can_afford: 0, research_status_code: 'research_queue_full'}),
        {queue_capacity: 7, queue_count: 7, queued: Array.from({length: 6}, (_, i) => ({job_id: 'queued-' + i}))});
    assert.equal(f.learn(), true);
    assertRequest(f, 'tower_attack');
});
test('actual selection and caster mismatch never dispatch research', () => {
    const f = fixture();
    f.publish(viewer());
    f.select(999);
    assert.equal(f.dispatch.casterForAbility(f.ability, f.publicRows[f.ability]), f.unit,
        'old owner really still owns the engine ability');
    assert.equal(f.learn(), false, 'unselected owner cannot become research source');
    assert.equal(f.sent().length, 0);
    f.select(f.unit); f.modal('rogue_reward');
    assert.equal(f.learn(), false, 'active modal still blocks action-bar input');
    assert.equal(f.sent().length, 0);
});
test('research results log request identity and server rejection reason', () => {
    const f = fixture(); f.publish(viewer());
    assert.equal(f.learn(), true);
    const request = assertRequest(f, 'tower_attack');
    f.callbacks.ui_operation_result({operation: 'research_queue', request_id: request.request_id,
        source_entindex: f.unit, success: 0, error: '研究队列已满',
        error_code: 'research_queue_full', status_code: 'obsolete_fallback'});
    const failureLog = f.messages.find(message => message.includes('[SURVIVAL_RESEARCH][CLIENT] RESULT')
        && message.includes(request.request_id) && message.includes('success=0'));
    assert(failureLog, 'server rejection is observable as a correlated research RESULT');
    assert(failureLog.includes('research_queue') && failureLog.includes('研究队列已满')
        && failureLog.includes('research_queue_full'), 'RESULT retains operation, error and machine status');
    assert(!failureLog.includes('obsolete_fallback'), 'canonical server error_code takes priority over legacy status_code');
    f.callbacks.ui_operation_result({operation: 'research_queue', request_id: request.request_id,
        source_entindex: f.unit, success: 1, error: '', error_code: ''});
    assert(f.messages.some(message => message.includes('[SURVIVAL_RESEARCH][CLIENT] RESULT')
        && message.includes(request.request_id) && message.includes('success=1')), 'accepted queue intent logs success');
    f.callbacks.ui_operation_result({operation: 'research_queue', request_id: request.request_id,
        source_entindex: f.unit, success: 0, error: '木材不足', status_code: 'wood_not_enough'});
    assert(f.messages.some(message => message.includes('[SURVIVAL_RESEARCH][CLIENT] RESULT')
        && message.includes(request.request_id) && message.includes('status_code=wood_not_enough')),
    'legacy status_code remains readable for an older server response');
});
console.log('RESEARCH_CLICK_DISPATCH: ' + passed + ' passed, ' + failures.length + ' failed');
if (failures.length) process.exitCode = 1;
