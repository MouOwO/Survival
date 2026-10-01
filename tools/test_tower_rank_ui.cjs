// SIMULATION: execute production JS against a panel/engine double. Static checks
// inspect the real XML/CSS; this intentionally does not claim Workshop rendering.
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const sourceArg = process.argv.indexOf('--source');
const sourcePath = sourceArg >= 0 ? process.argv[sourceArg + 1] : 'panorama/src/scripts/custom_game/tower_rank_ui.js';
const source = fs.readFileSync(sourcePath, 'utf8');
const xml = fs.readFileSync('panorama/src/layout/custom_game/tower_rank_ui.xml', 'utf8');
const css = fs.readFileSync('panorama/src/styles/custom_game/tower_rank_ui.css', 'utf8');
assert(!/<(?:Image|Label)\b/.test(xml), 'empty initial layout must contain no display assets');
assert(/\.TowerRank\s*\{[^}]*visibility:\s*collapse/.test(css));
assert(/\.TowerRankUltimate\s*\{[^}]*width:\s*27px;[^}]*height:\s*27px;/.test(css),
    'UR native label has an explicit measured area after initial collapse');
let nextTask = 0, nextListener = 0, nextPanel = 0;
let styleWrites = 0, originReads = 0, projectionReads = 0;
const tasks = new Map(), listeners = new Map(), table = {}, config = {}, entities = {};
const debugListeners = new Map(), messages = [];
function panel(id = '') {
    return { id, children: [], style: new Proxy({}, { set(target, key, value) {
            styleWrites++; target[key] = value; return true;
        } }), classes: new Set(), deleted: false,
        actualuiscale_x: 1, actualuiscale_y: 1, actuallayoutwidth: 1920, actuallayoutheight: 1080,
        IsValid() { return !this.deleted; }, AddClass(c) { this.classes.add(c); },
        SetHasClass(c, on) { on ? this.classes.add(c) : this.classes.delete(c); },
        GetPositionWithinWindow() { return { x: 0, y: 0 }; },
        DeleteAsync() { this.deleted = true; }
    };
}
const root = panel('root');
const $ = id => id === '#SurvivalTowerRanks' ? root : null;
$.GetContextPanel = () => root;
$.CreatePanel = (type, parent, id) => { const p = panel(id || ++nextPanel); p.type = type; parent.children.push(p); return p; };
$.Schedule = (_, callback) => { const id = ++nextTask; tasks.set(id, callback); return id; };
$.CancelScheduled = id => tasks.delete(id);
$.Msg = message => messages.push(message);
const sandbox = { $, GameUI: { CustomUIConfig: () => config },
    GameEvents: { Subscribe: (_, fn) => { const id = ++nextListener; debugListeners.set(id, fn); return id; },
        Unsubscribe: id => debugListeners.delete(id) },
    CustomNetTables: {
        GetTableValue: (_, key) => table[key],
        GetAllTableValues: () => Object.keys(table).map(key => ({ key, value: table[key] })),
        SubscribeNetTableListener: (_, fn) => { const id = ++nextListener; listeners.set(id, fn); return id; },
        UnsubscribeNetTableListener: id => listeners.delete(id)
    },
    Entities: {
        IsValidEntity: id => !!entities[id], IsAlive: id => entities[id].alive,
        IsDormant: id => entities[id].dormant, GetUnitName: id => entities[id].name,
        GetAbsOrigin: id => { originReads++; if (entities[id].throws) throw Error('removed during frame'); return entities[id].origin; },
        GetHealthBarOffset: () => 190
    },
    Game: { WorldToScreenX: x => { projectionReads++; return x; },
        WorldToScreenY: (_, y) => { projectionReads++; return y; } }
};
function tick() { const due = [...tasks.values()]; tasks.clear(); due.forEach(fn => fn()); }
function update(key, value) { table[key] = value; [...listeners.values()].forEach(fn => fn('survival_tower_rank', key, value)); }
function bars() { return root.children.filter(p => !p.deleted); }
if (process.argv.includes('--measure')) {
    // Count production code paths, not elapsed CPU/GPU time. This exact harness
    // also accepts --source <baseline.js> for an identical before/after load.
    const counts = { native: 0, capture: 0, findPanel: 0 };
    delete sandbox.Entities.IsDormant; // Current Workshop API does not expose it.
    Object.keys(sandbox.Entities).forEach(name => {
        const call = sandbox.Entities[name];
        sandbox.Entities[name] = (...args) => { counts.native++; return call(...args); };
    });
    const blockers = {};
    root.FindChildTraverse = id => {
        counts.findPanel++;
        if (!blockers[id]) { blockers[id] = panel(id); blockers[id].visible = false; }
        return blockers[id];
    };
    let blocked = false;
    config.SurvivalUILayers = { Top: () => blocked };
    vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/world_overlay_visibility.js', 'utf8'), sandbox);
    const capture = config.SurvivalWorldOverlayVisibility.Capture;
    config.SurvivalWorldOverlayVisibility.Capture = () => { counts.capture++; return capture(); };
    table._session = { id: 'measure' };
    for (let id = 1; id <= 40; id++) {
        entities[id] = { alive: true, name: 'tower', origin: [600, 400, 0] };
        table['unit_' + id] = { entindex: id, unit_name: 'tower', rarity: 'R', stars: 1, session: 'measure' };
    }
    vm.runInNewContext(source, sandbox); tick();
    function captureFrames() {
        counts.native = counts.capture = counts.findPanel = 0;
        styleWrites = projectionReads = 0;
        for (let index = 0; index < 300; index++) tick();
        return { native_calls: counts.native, projection_calls: projectionReads,
            style_writes: styleWrites, overlay_captures: counts.capture, panel_searches: counts.findPanel };
    }
    const stable = captureFrames();
    blocked = true;
    const beforeHide = styleWrites; tick();
    const blockTransitionWrites = styleWrites - beforeHide;
    const fullScreenBlocked = captureFrames();
    for (let id = 1; id <= 40; id++) update('unit_' + id, { removed: 1, session: 'measure' });
    blocked = false; tick();
    const noTowers = captureFrames();
    console.log(JSON.stringify({ kind: 'offline_production_js_call_counts', source: sourcePath,
        towers: 40, frames_per_scenario: 300, stable, full_screen_blocked: fullScreenBlocked,
        block_transition_style_writes: blockTransitionWrites, no_towers: noTowers,
        caveat: 'Call counts only; not FPS, CPU/GPU frame time or measured Dota speedup.' }));
    process.exit(0);
}
vm.runInNewContext(source, sandbox);
assert.equal(bars().length, 0, 'no units = no image panels');
let emptyCaptures = 0;
config.SurvivalWorldOverlayVisibility = { Capture: () => { emptyCaptures++; return {}; } };
tick(); assert.equal(emptyCaptures, 0, 'zero tower state must skip HUD capture');
delete config.SurvivalWorldOverlayVisibility;
entities[1] = { alive: true, dormant: false, name: 'tower', origin: [600, 400, 0] };
update('unit_1', { entindex: 1, unit_name: 'tower', rarity: 'SSR', stars: 5, red_stars: 1, session: 'one' });
tick(); assert.equal(bars().length, 0, 'records cannot display before session metadata');
update('_session', { id: 'one' }); tick();
assert.equal(bars().length, 1);
let bar = bars()[0];
assert.equal(bar.style.visibility, 'visible');
assert(bar.classes.has('RankSSR'));
assert.equal(bar.__stars.filter(s => s.classes.has('ActiveStar')).length, 5);
assert.equal(bar.__stars.filter(s => s.classes.has('RedStar')).length, 1);
assert.equal(config.SurvivalTowerRanks.DebugSnapshot().visible_count, 1);
let priorWrites = styleWrites;
tick(); assert.equal(styleWrites, priorWrites, 'stable row position and visibility must not be rewritten');
const priorOriginReads = originReads, priorProjectionReads = projectionReads;
config.SurvivalWorldOverlayVisibility = { Capture: () => ({ blocked: true }),
    Overlaps: () => { throw Error('full-screen block should bypass per-row overlap checks'); } };
tick(); assert.equal(bar.style.visibility, 'collapse', 'new full-screen block hides an existing row');
assert.equal(originReads, priorOriginReads); assert.equal(projectionReads, priorProjectionReads);
priorWrites = styleWrites;
entities[1].origin[0] = 640; tick();
assert.equal(styleWrites, priorWrites, 'hidden rows are not repeatedly rewritten');
assert.equal(originReads, priorOriginReads, 'movement under a full-screen UI does not trigger entity reads');
delete config.SurvivalWorldOverlayVisibility;
tick();
assert.equal(bar.style.visibility, 'visible', 'closing full-screen UI restores the next-frame row');
assert.equal(bar.style.position, '589.00px 353.00px 0px', 'movement while covered is read on resume');
entities[1].origin[0] = 600; tick();
const dormantAPI = sandbox.Entities.IsDormant, offsetAPI = sandbox.Entities.GetHealthBarOffset;
delete sandbox.Entities.IsDormant; delete sandbox.Entities.GetHealthBarOffset;
tick(); assert.equal(bar.style.visibility, 'visible', 'optional missing engine APIs must not hide all towers');
assert.equal(config.SurvivalTowerRanks.DebugSnapshot().api.is_dormant, false);
assert.equal(config.SurvivalTowerRanks.DebugSnapshot().lastError, '');
sandbox.Entities.IsDormant = dormantAPI; sandbox.Entities.GetHealthBarOffset = offsetAPI;
entities[1].origin[0] = 2500; tick(); assert.equal(bar.style.visibility, 'collapse');
assert.equal(config.SurvivalTowerRanks.DebugSnapshot().hidden_reasons.outside_viewport, 1);
entities[1].origin[0] = 600; entities[1].dormant = true; tick(); assert.equal(bar.style.visibility, 'collapse');
entities[1].dormant = false; entities[1].throws = true; tick(); assert.equal(bar.style.visibility, 'collapse');
assert(config.SurvivalTowerRanks.DebugSnapshot().lastError.includes('removed during frame'));
entities[1].throws = false; tick(); assert.equal(bar.style.visibility, 'visible');
config.SurvivalWorldOverlayVisibility = { Capture: () => ({}), Overlaps: () => true };
tick(); assert.equal(bar.style.visibility, 'collapse');
assert.equal(config.SurvivalTowerRanks.DebugSnapshot().hidden_reasons.hud_occlusion, 1);
config.SurvivalWorldOverlayVisibility.Capture = () => { throw Error('optional HUD capture failure'); };
tick(); assert.equal(config.SurvivalTowerRanks.DebugSnapshot().hidden_reasons.frame_exception, 1);
delete config.SurvivalWorldOverlayVisibility;
root.actualuiscale_x = root.actualuiscale_y = 0.75; tick();
assert.equal(bar.style.position, '749.00px 486.33px 0px', 'world pixels convert to UI scale');
entities[1].alive = false; tick(); assert.equal(bar.style.visibility, 'collapse');
update('unit_1', { removed: 1, session: 'one' }); assert.equal(bars().length, 0);
entities[1].alive = true;
update('unit_1', { entindex: 1, unit_name: 'tower', rarity: 'R', stars: 3, session: 'one' }); tick();
assert.equal(bars().length, 1);
update('_session', { id: 'two' }); tick(); assert.equal(bars().length, 0, 'old session records stay hidden');
update('unit_1', { entindex: 1, unit_name: 'tower', rarity: 'UR', stars: 1, session: 'two' }); tick();
assert(bars()[0].classes.has('RankUR'));
assert.equal(bars()[0].__ultimate.text, 'UR');
assert.equal(bars()[0].__ultimate.style.visibility, 'visible');
update('unit_1', { entindex: 1, unit_name: 'tower', rarity: 'R', stars: 1, session: 'two' }); tick();
assert.equal(bars()[0].__ultimate.style.visibility, 'collapse');
update('unit_1', { entindex: 1, unit_name: 'tower', rarity: 'UR', stars: 1, session: 'two' }); tick();
assert.equal(config.SurvivalTowerRanks.DebugSnapshot().units[0].ultimate_label.text, 'UR');
vm.runInNewContext(source, sandbox); tick();
assert.equal(listeners.size, 1, 'hot reload has only one listener');
assert.equal(debugListeners.size, 1, 'hot reload has only one read-only diagnostic listener');
assert.equal(tasks.size, 1, 'hot reload has only one animation loop');
assert.equal(bars().length, 1);
[...debugListeners.values()][0]();
assert(messages[0].startsWith('[TowerRankDebug] '));
assert.equal(JSON.parse(messages[0].slice('[TowerRankDebug] '.length)).state_count, 1);
delete entities[1]; tick(); assert.equal(bars().length, 0);
config.SurvivalTowerRanks.Stop(); assert.equal(tasks.size, 0); assert.equal(listeners.size, 0);
assert.equal(debugListeners.size, 0);
console.log('TOWER_RANK_UI_SIMULATION_PASS: actual empty XML/CSS, lifecycle, viewport, occlusion, scale, hot reload');
