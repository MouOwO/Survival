// Run the real bootstrap and combat hotkey dispatcher with engine boundaries mocked.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const bootstrap = fs.readFileSync('panorama/src/scripts/custom_game/ui_bootstrap.js', 'utf8');
const combat = fs.readFileSync('panorama/src/scripts/custom_game/combat_stats.js', 'utf8');
const seam = '    // NetTable is the single regular synchronization path.';
assert(combat.includes(seam));
const combatTest = combat.replace(seam, '    __test({ bindHotkeys: bindHotkeys }); return;\n' + seam);
let now = 10000, hero = 10, selected = 10, focused = null, api, nativeKey, gameTime = 0;
const cfg = {}, tables = new Map(), units = new Map(), abilities = new Map();
const selectedCalls = [], cameras = [], requests = [], binds = new Map(), commands = new Map(), jobs = [];
class Panel {
    constructor(id, parent, type = 'Panel') {
        this.id = id; this.parent = parent; this.paneltype = type;
        this.children = []; this.style = {}; this.visible = true;
        if (parent) parent.children.push(this);
    }
    IsValid() { return true; }
    GetParent() { return this.parent; }
    BHasClass(name) { return name === "Hidden" && this.hidden === true; }
    GetChildCount() { return this.children.length; }
    GetChild(i) { return this.children[i]; }
    BHasKeyFocus() { return focused === this; }
    BHasDescendantKeyFocus() { return this.children.some(c => c.BHasKeyFocus() || c.BHasDescendantKeyFocus()); }
    FindChildTraverse(id) {
        if (this.id === id) return this;
        for (const child of this.children) { const match = child.FindChildTraverse(id); if (match) return match; }
        return null;
    }
}
const root = new Panel('Hud'), ctx = new Panel('Context', root);
const chat = new Panel('HudChat', root), chatInput = new Panel('ChatInput', chat, 'TextEntry');
const search = new Panel('SearchEntry', new Panel('Dialog', ctx), 'TextEntry');
const button = new Panel('SomeButton', ctx, 'Button');
const destroy = new Panel('ArrowTowerDestroyConfirm', ctx); destroy.hidden = true;
let modal = null;
cfg.SurvivalUILayers = { Top: () => modal };
const $ = id => ctx.FindChildTraverse(id.slice(1));
$.GetContextPanel = () => ctx;
$.Msg = $.Warning = () => {};
$.Localize = s => s;
$.Schedule = (delay, fn) => { jobs.push({ delay, fn }); return jobs.length; };
$.CancelScheduled = () => {};
const tableKey = (t, k) => t + ':' + k;
function table(t, k, v) { tables.set(tableKey(t, k), v); }
function advance() { now += 250; }
units.set(10, { name: 'npc_dota_hero_undying', owner: 0, alive: true, skills: [] });
units.set(20, { name: 'npc_survival_builder_proxy', owner: 0, alive: true, skills: [] });
units.set(30, { name: 'npc_dota_hero_juggernaut', owner: 0, alive: true, skills: [70] });
units.set(40, { name: 'building_main_city', owner: 0, alive: true, skills: [] });
abilities.set(70, { name: 'ability_survival_return_home', level: 1, cooldown: 0 });
table('survival_builder_identity', 'player_0', { entindex: 20 });
const sandbox = {
    $, Date: { now: () => now },
    Game: {
        GetLocalPlayerID: () => 0, GetGameTime: () => gameTime,
        AddCommand: (name, fn) => commands.set(name, fn),
        CreateCustomKeyBind: (key, cmd) => binds.set(key, cmd),
    },
    GameUI: {
        CustomUIConfig: () => cfg,
        SetKeyPressedCallback: fn => { nativeKey = fn; }, SetMouseCallback: () => {},
        SetDefaultUIEnabled: () => {},
        SelectUnit: unit => { selected = unit; selectedCalls.push(unit); },
        MoveCameraToEntity: unit => cameras.push(unit),
    },
    Players: {
        GetPlayerHeroEntityIndex: () => hero,
        GetSelectedEntities: () => [selected], GetLocalPlayerPortraitUnit: () => selected,
    },
    Entities: {
        IsValidEntity: id => units.has(id), IsAlive: id => !!units.get(id)?.alive,
        GetPlayerOwnerID: id => units.get(id)?.owner ?? -1,
        GetUnitName: id => units.get(id)?.name || '',
        GetAbsOrigin: id => [id, 1, 2],
        GetAbility: (id, slot) => units.get(id)?.skills[slot] ?? -1,
    },
    Abilities: {
        GetAbilityName: id => abilities.get(id)?.name || '',
        GetLevel: id => abilities.get(id)?.level || 0,
        GetCooldownTimeRemaining: id => abilities.get(id)?.cooldown || 0,
    },
    CustomNetTables: { GetTableValue: (t, k) => tables.get(tableKey(t, k)) || null },
    GameEvents: { SendCustomGameEventToServer: (name, payload) => requests.push({ name, payload }) },
    __test: value => { api = value; },
};
const context = vm.createContext(sandbox);
vm.runInContext(bootstrap, context, { filename: 'ui_bootstrap.js' });
vm.runInContext(combatTest, context, { filename: 'combat_stats.js' });
api.bindHotkeys();
const dispatch = (key, down = true) => cfg.SurvivalInputDispatcher.DispatchKey(key, down);
const homeRequests = () => requests.filter(r => r.name === 'ui_return_home_request');
assert(cfg.SurvivalBuilderSelection.CanSelect());
assert(!cfg.SurvivalReturnHomeInput.CanRequest(), 'placeholder hero cannot return');
assert(dispatch('SPACE')); assert.equal(selected, 20); assert.equal(cameras.at(-1), 20);
// Summoning a combat hero never changes Space into hero selection.
hero = 30; selected = 30; advance();
assert(dispatch('SPACE')); assert.equal(selected, 20);
assert.equal(cfg.SurvivalSelectionResolver.ResolveDisplayUnit(), 20);
advance(); selected = 40;
assert(cfg.SurvivalBuilderSelection.Select('minimap_shortcut'));
assert.equal(selected, 20);
assert.equal(selectedCalls.length, 3);
// Simultaneous native + fallback events select/move the camera only once.
advance(); nativeKey('SPACE', true); commands.get(binds.get('SPACE'))();
assert.equal(selectedCalls.length, 4); assert.equal(cameras.length, 4);
advance(); selected = 40;
assert(cfg.SurvivalReturnHomeInput.CanRequest());
assert(dispatch('F2')); commands.get(binds.get('F2'))();
assert.equal(homeRequests().length, 1); assert.equal(selected, 40);
assert.equal(JSON.stringify(homeRequests()[0].payload), '{}', 'server owns actor and destination');
advance(); assert(cfg.SurvivalReturnHomeInput.Request('minimap_shortcut'));
assert.equal(homeRequests().length, 2);
// A paused game clock cannot permanently lock the wall-clock request throttle.
advance(); assert(cfg.SurvivalReturnHomeInput.Request('minimap_shortcut'));
assert.equal(gameTime, 0); assert.equal(homeRequests().length, 3);
for (const entry of [chatInput, chat, search]) {
    focused = entry; advance();
    assert(cfg.SurvivalShortcutGuard.IsBlocked());
    assert.equal(dispatch('SPACE'), false); assert.equal(dispatch('F2'), false);
    assert.equal(cfg.SurvivalBuilderSelection.Select('button'), false);
    assert.equal(cfg.SurvivalReturnHomeInput.Request('button'), false);
}
focused = button;
assert.equal(cfg.SurvivalShortcutGuard.IsBlocked(), false, 'ordinary focused HUD button is not a text input');
focused = null;
modal = 'treasures'; advance();
assert(dispatch('SPACE')); assert(dispatch('F2'));
assert(!cfg.SurvivalBuilderSelection.CanSelect()); assert(!cfg.SurvivalReturnHomeInput.CanRequest());
modal = null;
destroy.hidden = false; advance();
assert(cfg.SurvivalShortcutGuard.IsBlocked()); dispatch('SPACE'); dispatch('F2');
assert(!cfg.SurvivalBuilderSelection.CanSelect()); assert(!cfg.SurvivalReturnHomeInput.CanRequest());
destroy.hidden = true;
table('survival_loading', 'state', { admission_complete: 0 });
assert(!cfg.SurvivalBuilderSelection.CanSelect()); assert(!cfg.SurvivalReturnHomeInput.CanRequest());
table('survival_loading', 'state', { admission_complete: 1 });
table('survival_ui_state', 'player_0', { wave: { player_defeated: 1 } });
assert(!cfg.SurvivalBuilderSelection.CanSelect()); assert(!cfg.SurvivalReturnHomeInput.CanRequest());
table('survival_ui_state', 'player_0', { wave: { player_defeated: 0 } });
assert(cfg.SurvivalBuilderSelection.CanSelect()); assert(cfg.SurvivalReturnHomeInput.CanRequest());
assert.equal(selectedCalls.length, 4); assert.equal(homeRequests().length, 3);
// Missing/dead builder never falls back to a hero. Its server identity wins over creature owner getters.
for (const identity of [{}, { entindex: null }, { entindex: 999 }]) {
    table('survival_builder_identity', 'player_0', identity); advance();
    assert(!cfg.SurvivalBuilderSelection.CanSelect()); assert(dispatch('SPACE'));
}
table('survival_builder_identity', 'player_0', { entindex: 20 });
units.get(20).alive = false; assert(!cfg.SurvivalBuilderSelection.CanSelect());
units.get(20).alive = true; units.get(20).owner = 1;
assert(cfg.SurvivalBuilderSelection.CanSelect(), 'per-player server identity overrides unreliable creature getter');
units.get(20).owner = 0;
for (const property of ['alive', 'owner']) {
    const old = units.get(30)[property]; units.get(30)[property] = property === 'alive' ? false : 1;
    assert(!cfg.SurvivalReturnHomeInput.CanRequest()); advance(); assert(dispatch('F2'));
    units.get(30)[property] = old;
}
abilities.get(70).cooldown = 0.5; assert(!cfg.SurvivalReturnHomeInput.CanRequest());
advance(); dispatch('F2'); abilities.get(70).cooldown = 0;
abilities.get(70).level = 0; assert(!cfg.SurvivalReturnHomeInput.CanRequest()); abilities.get(70).level = 1;
units.get(30).skills = []; assert(!cfg.SurvivalReturnHomeInput.CanRequest()); units.get(30).skills = [70];
assert.equal(homeRequests().length, 3); assert.equal(selectedCalls.length, 4);
assert.equal(dispatch('SPACE', false), false); assert.equal(dispatch('F2', false), false);
// On Workshop reload, old UI closures cannot act, while fallback commands route to the new dispatcher.
const oldSelection = cfg.SurvivalBuilderSelection, oldReturn = cfg.SurvivalReturnHomeInput;
const oldSpaceCommand = commands.get(binds.get('SPACE'));
advance(); vm.runInContext(bootstrap, context, { filename: 'ui_bootstrap_reload.js' });
assert(!oldSelection.Select('stale')); assert(!oldReturn.Request('stale'));
assert(oldSpaceCommand()); assert.equal(selectedCalls.length, 5);
// F1 always selects the current local formal hero, independent of the selected unit.
assert(binds.has('F1'));
const f1Start = selectedCalls.length, f1CameraStart = cameras.length;
// A real-name hero left behind by a failed summon is not a playable identity.
advance(); assert(dispatch('F1')); assert.equal(selectedCalls.length, f1Start);
table('survival_hero_skills', 'player_0', { hero_ready: 0, unit_entindex: 30, hero_id: 'hero_blademaster' });
advance(); assert(dispatch('F1')); assert.equal(selectedCalls.length, f1Start);
table('survival_hero_skills', 'player_0', { hero_ready: 1, unit_entindex: 30, hero_id: 'hero_blademaster' });
advance(); selected = 40;
assert(dispatch('F1')); assert.equal(selected, 30); assert.equal(cameras.at(-1), 30);
commands.get(binds.get('F1'))();
assert.equal(selectedCalls.length, f1Start + 1, 'native/fallback duplicate F1 is consumed once');
assert.equal(cameras.length, f1CameraStart + 1);
assert.equal(cfg.SurvivalSelectionResolver.ResolveDisplayUnit(), 30);
for (const unavailable of [-1, 10, 20, 999]) {
    hero = unavailable; advance(); assert(dispatch('F1'));
    assert(!cfg.SurvivalHeroSelection.CanSelect());
}
hero = 30; units.get(30).owner = 1; advance(); assert(dispatch('F1'));
units.get(30).owner = 0;
for (const entry of [chatInput, search]) {
    focused = entry; advance(); assert.equal(dispatch('F1'), false);
}
focused = null; modal = 'treasures'; advance(); assert(dispatch('F1')); modal = null;
destroy.hidden = false; advance(); assert(dispatch('F1')); destroy.hidden = true;
table('survival_loading', 'state', { admission_complete: 0 }); advance(); assert(dispatch('F1'));
table('survival_loading', 'state', { admission_complete: 1 });
table('survival_ui_state', 'player_0', { wave: { player_defeated: 1 } }); advance(); assert(dispatch('F1'));
table('survival_ui_state', 'player_0', { wave: { player_defeated: 0 } });
assert.equal(selectedCalls.length, f1Start + 1, 'unavailable/blocked F1 must not select');
assert.equal(cameras.length, f1CameraStart + 1);
// Selection remains available for a dead hero, without moving to a death/hidden location.
units.get(30).alive = false; advance(); selected = 40;
assert(dispatch('F1')); assert.equal(selected, 30); assert.equal(cameras.length, f1CameraStart + 1);
units.get(30).alive = true;
// Hero replacement is resolved live, rather than cached from the first summon.
units.set(31, { name: 'npc_dota_hero_axe', owner: 0, alive: true, skills: [70] });
hero = 31; advance(); assert(dispatch('F1')); assert.equal(selected, 30, 'stale identity cannot select a replacement');
table('survival_hero_skills', 'player_0', { hero_ready: 1, unit_entindex: 31, hero_id: 'hero_axe' });
advance(); assert(dispatch('F1')); assert.equal(selected, 31); assert.equal(cameras.at(-1), 31);
const oldHeroSelect = cfg.SurvivalHeroSelection, oldF1Command = commands.get(binds.get('F1'));
advance(); vm.runInContext(bootstrap, context, { filename: 'ui_bootstrap_f1_reload.js' });
assert(!oldHeroSelect.Select('stale')); assert(oldF1Command()); assert.equal(selected, 31);
assert.equal(dispatch('F1', false), false);
advance(); dispatch('SPACE'); assert.equal(selected, 20, 'Space still selects builder after F1');
assert.equal(homeRequests().length, 3, 'F1 never casts return-home');
console.log('MINIMAP_SHORTCUT_INPUT_PASS: shared button/key actions, builder identity, F1 current hero selection, F2 sender-only request, focus/modal/startup/defeat gates, cooldown, duplicate callbacks, reload');
