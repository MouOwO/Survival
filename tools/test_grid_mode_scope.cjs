// Real controller + projection + state helpers. Reproduce the startup ordinary
// atlas followed by each authored arena, including deliberately late packets.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');

function fixture() {
    const panels = [], ids = new Map(), sent = [], listeners = {}, scheduled = [];
    let now = 100, world = [0, 4096, 384], camera = world.slice(), mouse;
    function panel(id, parent) {
        const p = {id, parent, visible: false, style: {}, classes: new Set(),
            actuallayoutwidth: 1600, actuallayoutheight: 900, actualuiscale_x: 1, actualuiscale_y: 1,
            AddClass(c) { this.classes.add(c); }, RemoveClass(c) { this.classes.delete(c); },
            SetHasClass(c, v) { v ? this.classes.add(c) : this.classes.delete(c); },
            BHasClass(c) { return this.classes.has(c); }, GetParent() { return this.parent; },
            FindChildTraverse(name) { return ids.get(name); }};
        panels.push(p); if (id) ids.set(id, p); return p;
    }
    for (const id of ['GridPlacementRoot', 'GridPlacementStaticMask', 'GridPlacementStaticMesh',
        'GridPlacementCells', 'GridPlacementTerrain', 'GridPlacementFootprintTiles',
        'GridPlacementFootprint', 'GridPlacementTitle', 'GridPlacementStatus',
        'GridPlacementCursorIcon', 'GridPlacementPlaneRange', 'SurvivalPointTargetHint']) panel(id);
    const shared = {SurvivalPointTargetState: {active: false, name: 'build', unit: 10, ability: 20},
        SurvivalInputDispatcher: {RegisterMouseHandler(_, fn) { mouse = fn; }, RegisterKeyHandler() {}}};
    const $ = id => ids.get(id.replace(/^#/, ''));
    $.CreatePanel = (_, parent, id) => panel(id, parent);
    $.GetContextPanel = () => ids.get('GridPlacementRoot'); $.Msg = () => {};
    $.Schedule = (delay, fn) => scheduled.push({delay, fn});
    function screen(p) { return [800 + (p[0] - camera[0]) * .5,
        450 + (p[1] - camera[1]) * .25 - (p[2] - camera[2]) * .5]; }
    const context = vm.createContext({$, GameUI: {CustomUIConfig: () => shared,
        GetCursorPosition: () => screen(world),
        GetScreenWorldPosition: p => p[0] === 800 && p[1] === 450 ? camera.slice() : world.slice()},
        Game: {GetGameTime: () => now, WorldToScreenX: (x, y, z) => screen([x, y, z])[0],
            WorldToScreenY: (x, y, z) => screen([x, y, z])[1]},
        Particles: {CreateParticle: () => 1, SetParticleControl() {}, DestroyParticleEffect() {}, ReleaseParticleIndex() {}},
        ParticleAttachment_t: {PATTACH_WORLDORIGIN: 6},
        GameEvents: {Subscribe: (name, fn) => listeners[name] = fn,
            SendCustomGameEventToServer: (name, data) => sent.push({name, data})},
        Abilities: {GetLocalPlayerActiveAbility: () => -1}, Entities: {GetUnitName: () => 'builder'},
        CustomNetTables: {GetTableValue: () => null}});
    for (const name of ['survival_static_grid.js', 'survival_grid_state.js', 'survival_grid_placement.js']) {
        vm.runInContext(fs.readFileSync('panorama/src/scripts/custom_game/' + name, 'utf8'), context);
    }
    const update = scheduled.find(e => e.fn.name === 'updateLoop').fn;
    return {shared, panels, ids, sent, listeners, scheduled,
        step() { now += .2; update(); },
        teleport(point) { world = point.slice(); camera = point.slice(); },
        activate() { shared.SurvivalPointTargetState.active = true; },
        foot() { return panels.filter(p => p.classes.has('FootprintTile') && p.visible); },
        request() { return sent.filter(p => p.name === 'ui_grid_placement_validate').at(-1).data; },
        mouse: (...args) => mouse(...args)};
}
const mapBounds = {min_x: -16384, max_x: 16384, min_y: -16384, max_y: 16384};
const ordinaryBounds = {min_x: -4096, max_x: 2048, min_y: 1024, max_y: 7168};
function profiles(scope, version, point, bounds) {
    return {grid_scope: scope, grid_scope_version: version, layout_ready: 1, cell_size: 64,
        static_grid: {bounds: mapBounds, build_bounds: bounds, height: point[2]},
        profiles: [{ability_name: 'build', grid_footprint_x: 4, grid_footprint_y: 4, building_id: 'wall'}]};
}
function area(point, blocked = false) {
    return `3|64|${Math.floor(point[0] / 64) - 2}|${Math.floor(point[1] / 64) - 2}|4|4|${point[2]}|${(blocked ? '5' : 'a').repeat(8)}`;
}
function validation(request, scope, version, point, complete = 1) {
    return {...request, grid_scope: scope, grid_scope_version: version, success: 1,
        request_anchor_x: Math.floor(point[0] / 64) - 2, request_anchor_y: Math.floor(point[1] / 64) - 2,
        anchor_x: Math.floor(point[0] / 64) - 2, anchor_y: Math.floor(point[1] / 64) - 2,
        world_x: point[0], world_y: point[1], world_z: point[2],
        cells: [], area: area(point), area_complete: complete};
}
const modes = [
    {id: 'rich', point: [0, -9984, 128], bounds: {min_x: -1088, min_y: -11328, max_x: 1088, max_y: -8768}},
    {id: 'cold', point: [14336, 7936, 256], bounds: {min_x: 12800, min_y: 7680, max_x: 15104, max_y: 8960}},
    {id: 'scourge', point: [-14080, 12800, 128], bounds: {min_x: -15360, min_y: 11520, max_x: -12800, max_y: 14336}},
];
for (const mode of modes) {
    const f = fixture(), ordinary = [0, 4096, 384], oldScope = 'match:unselected:0', scope = `match:${mode.id}:0`;
    const oldProfiles = profiles(oldScope, 1, ordinary, ordinaryBounds);
    f.listeners.ui_grid_placement_profiles(oldProfiles);
    f.listeners.ui_grid_placement_static_area({grid_scope: oldScope, grid_scope_version: 1, area: area(ordinary)});
    f.activate(); f.step();
    assert.equal(f.foot().length, 16); assert(f.foot().every(p => p.classes.has('Clear')));
    f.listeners.ui_grid_placement_validation(validation(f.request(), oldScope, 1, ordinary)); f.step();
    const decodes = f.shared.SurvivalGridStatePerformance.dynamic_decodes;
    f.teleport(mode.point);
    f.listeners.ui_grid_placement_profiles(profiles(scope, 2, mode.point, mode.bounds)); f.step();
    assert.equal(f.foot().length, 16, `${mode.id}: footprint projects onto the new arena plane`);
    assert(f.foot().every(p => p.classes.has('Unknown')), `${mode.id}: old ordinary atlas/dynamic colors are cleared`);
    const req = f.request();
    assert.equal(Number(req.z), mode.point[2], `${mode.id}: validation and model use current construction height`);
    assert.deepEqual([Number(req.x), Number(req.y)], mode.point.slice(0, 2));

    // Give every late packet the CURRENT preview session and anchor so only
    // the explicit scope check can reject its obsolete geometry.
    f.listeners.ui_grid_placement_static_area({grid_scope: oldScope, grid_scope_version: 1, area: area(mode.point, true)});
    f.listeners.ui_grid_placement_validation({...validation(req, oldScope, 1, mode.point), success: 0, area: area(mode.point, true)});
    f.listeners.ui_grid_placement_area({grid_scope: oldScope, grid_scope_version: 1,
        session_id: req.session_id, ability_name: 'build', complete: 1, area: area(mode.point, true)});
    f.listeners.ui_grid_placement_profiles(oldProfiles); f.step();
    assert.equal(f.foot().length, 16);
    assert(f.foot().every(p => p.classes.has('Unknown')), `${mode.id}: old scope cannot reintroduce ordinary red/height`);
    assert.equal(Number(f.request().z), mode.point[2], 'late ordinary profiles cannot roll the construction plane back');
    f.listeners.ui_grid_placement_validation(validation(f.request(), scope, 2, mode.point, 0)); f.step();
    assert.equal(f.shared.SurvivalGridStatePerformance.dynamic_decodes, decodes,
        'old completedArea is not reused when the new scope sends an incomplete scan');
    f.listeners.ui_grid_placement_area({grid_scope: scope, grid_scope_version: 2,
        session_id: f.request().session_id, ability_name: 'build', complete: 1, area: area(mode.point)}); f.step();
    assert.equal(f.foot().length, 16);
    assert(f.foot().every(p => p.classes.has('Clear')), `${mode.id}: current dynamic results render green on the actual plane`);

    // No permanent green fallback while region discovery is unavailable.
    const nextScope = `next:${mode.id}:0`;
    f.listeners.ui_grid_placement_profiles({grid_scope: nextScope, grid_scope_version: 3,
        layout_ready: 0, cell_size: 64, profiles: []});
    const count = f.sent.filter(e => e.name === 'ui_grid_placement_validate').length;
    f.step();
    assert.equal(f.foot().length, 0, 'pending region hides old footprint/terrain');
    assert.equal(f.sent.filter(e => e.name === 'ui_grid_placement_validate').length, count);
    const retries = f.sent.filter(e => e.name === 'ui_grid_placement_profiles_request').length;
    const retry = f.scheduled.find(e => /profilesRetryScheduled=false/.test(e.fn.toString())).fn;
    retry();
    assert.equal(f.sent.filter(e => e.name === 'ui_grid_placement_profiles_request').length, retries + 1,
        'region pending restarts profile polling after the initial ordinary preload stopped');
    f.listeners.ui_grid_placement_profiles(profiles(nextScope, 3, mode.point, mode.bounds)); f.step();
    assert.equal(f.foot().length, 16);
    assert(f.foot().every(p => p.classes.has('Unknown')), 'ready region starts without stale cached permission');
}
console.log('GRID_MODE_SCOPE_CLIENT_PASS: ordinary -> rich/cold/scourge, actual plane, stale packets, cleared buffers and pending retry');
