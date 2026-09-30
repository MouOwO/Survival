// SIMULATION: execute production JS against a panel/engine double. Static checks
// inspect the real XML/CSS; this intentionally does not claim Workshop rendering.
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync('panorama/src/scripts/custom_game/tower_rank_ui.js', 'utf8');
const xml = fs.readFileSync('panorama/src/layout/custom_game/tower_rank_ui.xml', 'utf8');
const css = fs.readFileSync('panorama/src/styles/custom_game/tower_rank_ui.css', 'utf8');
assert(!/<(?:Image|Label)\b/.test(xml), 'empty initial layout must contain no display assets');
assert(/\.TowerRank\s*\{[^}]*visibility:\s*collapse/.test(css));
assert(/\.TowerRankUltimate\s*\{[^}]*width:\s*27px;[^}]*height:\s*27px;/.test(css),
    'UR native label has an explicit measured area after initial collapse');
let nextTask = 0, nextListener = 0, nextPanel = 0;
const tasks = new Map(), listeners = new Map(), table = {}, config = {}, entities = {};
const debugListeners = new Map(), messages = [];
function panel(id = '') {
    return { id, children: [], style: {}, classes: new Set(), deleted: false,
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
        GetAbsOrigin: id => { if (entities[id].throws) throw Error('removed during frame'); return entities[id].origin; },
        GetHealthBarOffset: () => 190
    },
    Game: { WorldToScreenX: x => x, WorldToScreenY: (_, y) => y }
};
function tick() { const due = [...tasks.values()]; tasks.clear(); due.forEach(fn => fn()); }
function update(key, value) { table[key] = value; [...listeners.values()].forEach(fn => fn('survival_tower_rank', key, value)); }
function bars() { return root.children.filter(p => !p.deleted); }
vm.runInNewContext(source, sandbox);
assert.equal(bars().length, 0, 'no units = no image panels');
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
