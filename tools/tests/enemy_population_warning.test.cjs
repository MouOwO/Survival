'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const project = path.resolve(__dirname, '../..');
const scripts = path.join(project, 'panorama/src/scripts/custom_game');
const warningSource = fs.readFileSync(process.env.SURVIVAL_ENEMY_WARNING_SOURCE || path.join(scripts, 'enemy_population_warning.js'), 'utf8');

// Run the complete renderer. Native panel operations are counted to distinguish
// a steady CSS pulse from restarting it on every unrelated resource snapshot.
function harness() {
    const panels = [], cfg = {}, calls = {created: 0, deleted: 0, classes: 0, text: 0, visibility: 0};
    class Panel {
        constructor(type, parent, id) {
            this.type = type; this.id = id; this.parent = parent; this.children = []; this.classes = new Set();
            this.hittest = this.hittestchildren = true; this._visible = true; this._text = '';
            if (parent) parent.children.push(this);
            panels.push(this); calls.created++;
        }
        IsValid() { return !this.deleted; }
        AddClass(name) { assert(this.IsValid()); calls.classes++; this.classes.add(name); }
        SetHasClass(name, enabled) { assert(this.IsValid()); calls.classes++; enabled ? this.classes.add(name) : this.classes.delete(name); }
        DeleteAsync() {
            assert(this.IsValid()); this.children.slice().forEach(child => child.DeleteAsync());
            this.deleted = true; calls.deleted++;
            if (this.parent) this.parent.children = this.parent.children.filter(child => child !== this);
        }
        set text(value) { assert(this.IsValid()); calls.text++; this._text = String(value); }
        get text() { return this._text; }
        set visible(value) { assert(this.IsValid()); calls.visibility++; this._visible = value; }
        get visible() { return this._visible; }
    }
    const ctx = new Panel('Panel', null, 'Context');
    const forbidden = name => () => assert.fail('population warning must not call ' + name);
    const environment = vm.createContext({
        GameUI: {CustomUIConfig: () => cfg},
        GameEvents: {Subscribe: forbidden('Subscribe'), SendCustomGameEventToServer: forbidden('server event')},
        Entities: new Proxy({}, {get: (_, name) => forbidden('Entities.' + String(name))}),
        $: {GetContextPanel: () => ctx, CreatePanel: (type, parent, id) => new Panel(type, parent, id),
            Schedule: forbidden('Schedule'), CancelScheduled: forbidden('CancelScheduled')}
    });
    function load() { vm.runInContext(warningSource, environment, {filename: 'enemy_population_warning.js'}); }
    function panel() {
        const current = panels.filter(p => p.id === 'HandoffEnemyPopulationWarning' && p.IsValid());
        assert.equal(current.length, 1, 'exactly one live warning overlay');
        return current[0];
    }
    load();
    return {cfg, ctx, calls, panels, environment, load, panel,
        render(wave) { cfg.SurvivalEnemyPopulationWarning.Render({alive_limit: 90, game_mode: 'survival', ...wave}); },
        active() { const p = panel(); return p.visible && p.classes.has('Active'); }};
}

test('threshold is strictly greater than 85, including native numeric strings', () => {
    const h = harness();
    for (const alive of [0, 84, 85, '85']) { h.render({alive}); assert.equal(h.active(), false, String(alive)); }
    for (const alive of [86, 90, 91, '86']) { h.render({alive}); assert.equal(h.active(), true, String(alive)); }
    h.render({alive: 85}); assert.equal(h.active(), false, 'kill back to 85 immediately stops warning');
    h.render({alive: 86}); assert.equal(h.active(), true, 'a later crossing can start another pulse');
});

test('steady snapshots do not restart animation, rebuild panels, rewrite text, or schedule work', () => {
    const h = harness(), panel = h.panel();
    const caption = panel.children.find(p => p.type === 'Label');
    assert.equal(caption.text, '即将超过怪物存在的上限');
    assert.equal(panel.children.length, 5, 'four screen edges and one warning caption');
    for (const p of [panel, ...panel.children]) {
        assert.equal(p.hittest, false); assert.equal(p.hittestchildren, false, 'overlay cannot intercept gameplay input');
    }
    h.render({alive: 86});
    const activeCalls = {...h.calls};
    for (let i = 0; i < 1000; i++) h.render({alive: 86 + i % 7});
    assert.deepEqual(h.calls, activeCalls, 'remaining above threshold leaves the single CSS pulse untouched');
    assert.strictEqual(h.panel(), panel); assert.strictEqual(panel.children.find(p => p.type === 'Label'), caption);
    h.render({alive: 85});
    const hiddenCalls = {...h.calls};
    for (let i = 0; i < 1000; i++) h.render({alive: i % 86});
    assert.deepEqual(h.calls, hiddenCalls, 'remaining below threshold performs no native UI writes');
});

test('fishing and all settled or eliminated states clear an already active warning', () => {
    const h = harness();
    const excluded = [{game_mode: 'fishing'}, {status: 'fishing'}];
    for (const field of ['player_defeated', 'defeat_settled', 'victory_settled', 'post_clear_frozen']) {
        for (const value of [true, 1, '1']) excluded.push({[field]: value});
    }
    for (const wave of excluded) {
        h.render({alive: 86}); assert(h.active());
        h.render({alive: 86, ...wave}); assert.equal(h.active(), false, JSON.stringify(wave));
    }
    h.render({alive: 86, status: 'dev_spawn', player_defeated: 0});
    assert(h.active(), 'tools wave state follows the same threshold for real-game validation');
});

test('missing or invalid count/limit cannot leave a stale warning', () => {
    const h = harness();
    for (const alive of [undefined, null, '', 'invalid', NaN, Infinity, -1]) {
        h.render({alive: 86}); h.render({alive}); assert.equal(h.active(), false, String(alive));
    }
    for (const alive_limit of [undefined, null, '', 'invalid', NaN, Infinity, 0, -1]) {
        h.render({alive: 86}); h.render({alive: 86, alive_limit}); assert.equal(h.active(), false, String(alive_limit));
    }
    h.render({alive: 86}); h.cfg.SurvivalEnemyPopulationWarning.Render(null);
    assert.equal(h.active(), false, 'an empty wave clears a previous visible warning');
});

test('dispose and source reload retire old panels and old API callbacks', () => {
    const h = harness(); h.render({alive: 86});
    const oldApi = h.cfg.SurvivalEnemyPopulationWarning, oldPanel = h.panel();
    h.load();
    assert.equal(oldPanel.IsValid(), false, 'reload deletes the old overlay and every edge/caption');
    assert.equal(h.calls.deleted, 6); assert.notStrictEqual(h.panel(), oldPanel); assert.equal(h.active(), false);
    const afterReload = {...h.calls}; oldApi.Render({alive: 100, alive_limit: 90}); oldApi.Dispose();
    assert.deepEqual(h.calls, afterReload, 'old render/dispose cannot mutate the replacement overlay');
    h.render({alive: 86}); assert(h.active());
    const api = h.cfg.SurvivalEnemyPopulationWarning;
    api.Dispose(); const afterDispose = {...h.calls}; api.Dispose(); api.Render({alive: 86, alive_limit: 90});
    assert.deepEqual(h.calls, afterDispose, 'dispose is idempotent and prevents use of deleted native panels');
    assert.equal(h.ctx.children.length, 0, 'no warning resources survive explicit cleanup');
});

test('actual HUD snapshot callback rejects stale sequence, generation, and destroyed context', () => {
    const h = harness(), source = fs.readFileSync(path.join(scripts, 'topnav_remaining_5d5c1152eb.js'), 'utf8');
    const match = source.match(/    function data\(next\) \{[\s\S]*?\n    \}(?=\r?\n    function refreshNow)/);
    assert(match, 'actual subscribed HUD callback is present');
    h.cfg.HandoffGeneration = 7;
    Object.assign(h.environment, {
        cfg: h.cfg, ctx: h.ctx, valid: panel => panel && panel.IsValid(), text() {}, compact: String,
        fishingWave: wave => wave.game_mode === 'fishing' || wave.status === 'fishing',
        renderCountdowns() {}, remaining: () => 0,
        enemyCounter: {SetHasClass() {}}, enemyCountdown: {}, countdownWave: null
    });
    const bind = vm.runInContext('(function(generation){var sequence=-1;' + match[0] + ';return data;})', h.environment);
    const callback = bind(7);
    callback({sequence: 1, wave: {alive: 86, alive_limit: 90}}); assert(h.active());
    callback({sequence: 1, wave: {alive: 0, alive_limit: 90}}); assert(h.active(), 'duplicate snapshot cannot hide current warning');
    callback({sequence: 0, wave: {alive: 0, alive_limit: 90}}); assert(h.active(), 'older snapshot cannot hide current warning');
    callback({sequence: 2, wave: {alive: 85, alive_limit: 90}}); assert.equal(h.active(), false);
    h.cfg.HandoffGeneration = 8;
    callback({sequence: 100, wave: {alive: 86, alive_limit: 90}}); assert.equal(h.active(), false, 'old HUD subscription cannot affect replacement renderer');
    const current = bind(8);
    current({sequence: 1, wave: {alive: 86, alive_limit: 90}}); assert(h.active(), 'replacement HUD owns a fresh sequence stream');
    const before = {...h.calls}; h.ctx.deleted = true;
    current({sequence: 2, wave: {alive: 0, alive_limit: 90}});
    assert.deepEqual(h.calls, before, 'destroyed context cannot perform UI work');
});

test('HUD loads renderer before snapshot consumer and one parent animation drives text plus four edges', () => {
    const xml = fs.readFileSync(path.join(project, 'panorama/src/layout/custom_game/survival_hud.xml'), 'utf8');
    assert(xml.indexOf('/enemy_population_warning.js') >= 0);
    assert(xml.indexOf('/enemy_population_warning.js') < xml.indexOf('/topnav_remaining_5d5c1152eb.js'));
    assert.match(xml, /styles\/custom_game\/enemy_population_warning\.css/);
    const css = fs.readFileSync(path.join(project, 'panorama/src/styles/custom_game/enemy_population_warning.css'), 'utf8');
    assert.equal((css.match(/animation-name\s*:/g) || []).length, 1, 'children inherit their parent opacity rather than running independent pulses');
    assert.match(css, /\.EnemyPopulationWarning\.Active\s*\{[^}]*animation-name:\s*EnemyPopulationWarningBreathe\s*;/);
    assert.match(css, /animation-duration:\s*1\.6s\s*;/);
    assert.match(css, /animation-iteration-count:\s*infinite\s*;/);
    for (const edge of ['Top', 'Bottom', 'Left', 'Right']) assert.match(css, new RegExp('\\.EnemyWarning' + edge + '\\s*\\{[^}]*gradient\\('));
    assert.match(css, /@keyframes\s+'EnemyPopulationWarningBreathe'\s*\{\s*0%\s*\{\s*opacity:\s*0\.2;\s*\}\s*50%\s*\{\s*opacity:\s*1;\s*\}\s*100%\s*\{\s*opacity:\s*0\.2;/);
});
