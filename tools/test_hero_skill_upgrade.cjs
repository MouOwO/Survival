const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const code = fs.readFileSync('panorama/src/scripts/custom_game/hero_skill_upgrade.js', 'utf8');
const config = {}, jobs = [], events = {}, net = [], sent = [];
class Panel {
    constructor(parent, id) {
        this.parent = parent; this.id = id; this.alive = true; this.children = [];
        this.handlers = {}; this.classes = new Set();
        this.style = new Proxy({}, {set: (obj, name, value) => {
            assert(this.alive); assert(!/NaN|Infinity/.test(value)); obj[name] = value; return true;
        }});
        if (parent) parent.children.push(this);
    }
    IsValid() { return this.alive; }
    GetParent() { return this.parent; }
    AddClass(c) { this.classes.add(c); }
    SetHasClass(c, value) { if (value) this.classes.add(c); else this.classes.delete(c); }
    SetPanelEvent(name, fn) { this.handlers[name] = fn; }
    DeleteAsync() { this.alive = false; this.parent.children = this.parent.children.filter(p => p !== this); }
}
const context = new Panel(null, 'Context'), host = new Panel(context, 'Host');
let selected = 21;
let data = {
    hero_ready: 1, unit_entindex: 21, skill_points: 2, version: 1,
    skills: {
        1: {skill_id: 'public', ability_name: 'public_ability', display_name: '随机被动', level: 1, max_level: 3, can_upgrade: 1},
        2: {skill_id: 'exclusive', ability_name: 'exclusive_ability', level: 0, max_level: 1, locked: 1, can_upgrade: 0}
    }
};
const $ = {GetContextPanel: () => context, CreatePanel: (_, parent, id) => new Panel(parent, id),
    Schedule: (delay, fn) => jobs.push({delay, fn}), DispatchEvent: () => {}};
const sandbox = {$, GameUI: {CustomUIConfig: () => config}, Game: {GetLocalPlayerID: () => 0},
    GameEvents: {Subscribe: (name, fn) => (events[name] ||= []).push(fn),
        SendCustomGameEventToServer: (name, payload) => sent.push({name, payload})},
    CustomNetTables: {GetTableValue: () => data, SubscribeNetTableListener: (_, fn) => net.push(fn)}};
function load() { vm.runInNewContext(code, sandbox); }
function event(payload) { events.ui_hero_skill_upgrade_result.forEach(fn => fn(payload)); }
function changed() { net.forEach(fn => fn('survival_hero_skills', 'player_0', data)); }
const bindings = [
    {abilityName: 'exclusive_ability', x: 100, y: 800, width: 44, height: 44},
    {abilityName: 'public_ability', x: 150, y: 800, width: 44, height: 44},
    {abilityName: 'ability_survival_return_home', x: 200, y: 800, width: 44, height: 44}
];
function update() { config.SurvivalHeroSkillUpgrade.Update(host, bindings, () => selected); }
function visible() { return host.children.filter(p => p.alive && p.style.visibility === 'visible'); }
function click(button = visible()[0]) { button.handlers.onactivate(); }
load(); update();
assert.equal(visible().length, 1, 'only an owned upgradable public passive gets a plus');
let button = visible()[0];
assert.equal(button.style.position, '150px 780px 0px', 'plus is above the real native ability rectangle');
update(); assert.equal(visible()[0], button, 'same binding reuses the button');
selected = 99; update(); assert.equal(visible().length, 0, 'another player/unit cannot upgrade');
selected = 21; update(); click(); click();
assert.equal(sent.length, 1, 'double click cannot enqueue two requests');
assert.deepEqual({...sent[0].payload, request_id: '<id>'}, {
    request_id: '<id>', skill_id: 'public', unit_entindex: 21, expected_level: 1
});
event({ok: true, request_id: sent[0].payload.request_id}); click();
assert.equal(sent.length, 1, 'success before NetTable stays locked');
config.SurvivalHeroSkillUpgrade.Hide(); assert.equal(visible().length, 0);
update(); click(); assert.equal(sent.length, 1, 'selection hide/show preserves the in-flight lock');
data.skills[1].level = 2; data.skill_points = 1; data.version++; changed();
assert.equal(visible()[0], button); assert.equal(button.enabled, true);
click(); assert.equal(sent.length, 2);
event({ok: false, error: 'skill_points_insufficient', request_id: 'old_response'});
assert.equal(button.enabled, false, 'out-of-order response cannot unlock a newer request');
event({ok: false, error: 'skill_points_insufficient', request_id: sent[1].payload.request_id});
assert.equal(button.enabled, true, 'failed request permits retry without rebuilding slots');
click(); const retry = sent[2].payload;
jobs.filter(job => job.delay === 5).forEach(job => job.fn());
assert.equal(button.enabled, true, 'lost response has a bounded retry wait');
click(); assert.equal(sent[3].payload.expected_level, retry.expected_level, 'retry stays tied to the original level');
data.skills[1].level = 3; data.skills[1].can_upgrade = 0; data.skill_points = 0; changed();
assert.equal(visible().length, 0, 'max level / no points removes the plus');
event({ok: true, request_id: sent[3].payload.request_id});
assert.equal(visible().length, 0, 'late response cannot resurrect a max-level button');
data.skills[1].level = 2; data.skills[1].can_upgrade = 1; data.skill_points = 1; changed();
const old = visible()[0]; load();
assert.equal(old.alive, false, 'hot reload removes old native-overlay nodes');
update(); assert.equal(visible().length, 1); assert.equal(host.children.length, 1);
const beforeHiddenClick = sent.length;
selected = 99; click(); assert.equal(sent.length, beforeHiddenClick, 'click revalidates current selection before sending');
selected = 21; bindings[1].x = NaN; update(); assert.equal(visible().length, 0, 'invalid geometry is hidden safely');
bindings[1].x = 150; update(); context.alive = false;
assert.doesNotThrow(() => jobs.forEach(job => job.fn()), 'dead HUD callbacks stop');
const xml = fs.readFileSync('panorama/src/layout/custom_game/hero_skill_ui.xml','utf8');
const choice = fs.readFileSync('panorama/src/scripts/custom_game/hero_skill_ui.js','utf8');
assert(!/HeroSkillManage|HeroSkillOwned|HeroSkillTooltip/.test(xml + choice));
assert(choice.includes('ui_hero_skill_choice_select') && xml.includes('HeroSkillChoicePanel'));
assert(!choice.includes('ui_hero_skill_state_request'));
console.log('HERO_SKILL_UPGRADE_PASS: native slot placement, ownership, points, response ordering, duplicate clicks, retry, selection and reload; old management removed, reward choice retained');
