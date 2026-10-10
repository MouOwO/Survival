const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');

const project = path.resolve(__dirname, '../..');
const nodes = {}, events = {}, requests = [], timers = [], modules = [];
const counts = {created: 0, deleted: 0, text: 0, style: 0, tree: 0, grid: 0};
let toolsMode = true, profile = {vip_badge: false}, opened = false, tableListener;
let unnamed = 0;
class Panel {
    constructor(type, parent, id) {
        this.id = id; this.paneltype = type; this.children = []; this.classes = new Set();
        this.events = {}; this.enabled = true; this.parent = parent;
        this.style = new Proxy({}, {set(target, key, value) {
            counts.style++; target[key] = value; return true;
        }});
        counts.created++;
        if (parent) parent.children.push(this);
        nodes[id] = this;
    }
    get text() { return this._text; }
    set text(value) { counts.text++; this._text = value; }
    IsValid() { return !this.deleted; }
    AddClass(name) { this.classes.add(name); }
    RemoveClass(name) { this.classes.delete(name); }
    SetHasClass(name, value) { value ? this.AddClass(name) : this.RemoveClass(name); }
    BHasClass(name) { return this.classes.has(name); }
    SetPanelEvent(name, callback) { this.events[name] = callback; }
    SetImage(value) { this.image = value; }
    GetParent() { return this.parent; }
    Children() { counts.tree++; return this.children; }
    RemoveAndDeleteChildren() {
        if (this.id === 'VIPGrid') counts.grid++;
        this.children.forEach(child => {child.deleted = true; counts.deleted++;});
        this.children = [];
    }
}
const root = new Panel('Panel', null, 'Root');
root.FindChildTraverse = id => {
    counts.tree++;
    if (id === 'VIPTooltip' && !nodes[id]) return null;
    return nodes[id] || new Panel('Panel', root, id);
};
const cfg = {
    HandoffGeneration: 3,
    SurvivalUI: {ModalShell: {Adopt() {
        return {Open() { opened = true; }, Close() { opened = false; },
            IsOpen() { return opened; }, Dispose() {}};
    }}},
    SurvivalClientCallbackProbe: {RegisterModule(name, entries, generation) {
        modules.push({name, entries, generation}); return true;
    }}
};
const env = {
    GameUI: {CustomUIConfig: () => cfg},
    Game: {IsInToolsMode: () => toolsMode, GetLocalPlayerID: () => 0,
        GetPlayerInfo: () => ({player_steamid: '76561198000000000'}), AddCommand() {}},
    CustomNetTables: {GetTableValue: () => profile,
        SubscribeNetTableListener(name, callback) { tableListener = callback; return 1; },
        UnsubscribeNetTableListener() {}},
    GameEvents: {Subscribe(name, callback) { events[name] = callback; return name; },
        Unsubscribe() {}, SendCustomGameEventToServer(name, payload) { requests.push({name, payload}); }},
    $: {GetContextPanel: () => root, RegisterEventHandler() {}, Msg() {},
        CreatePanel(type, parent, id) { return new Panel(type, parent, id || 'auto_' + ++unnamed); },
        Schedule(delay, callback) { timers.push(callback); }}
};
for (const name of ['vip_catalog.js', 'vip_window.js']) {
    vm.runInNewContext(fs.readFileSync(path.join(project, 'panorama/src/scripts/custom_game', name), 'utf8'), env);
}
assert.equal(counts.grid, 0, 'initial closed view does not assemble its 12-card grid');
assert.equal(modules.length, 1);
assert.equal(modules[0].name, 'vip');
assert.equal(modules[0].generation, 3);
const probeCounts = {refresh: 0, render: 0};
// Use host-context wrappers to exercise the actual cross-context get/set
// registration that the HUD probe uses for private archive-context functions.
for (const entry of modules[0].entries) {
    const original = entry.get();
    entry.set(function () {
        probeCounts[entry.name]++;
        return original.apply(this, arguments);
    });
    entry.restore = () => entry.set(original);
}
const closed = {...counts};
for (let i = 0; i < 1000; i++) {
    profile = {vip_badge: i === 999, revision: i};
    tableListener('survival_player_public_profiles', '0', profile);
}
assert.deepEqual(counts, closed, '1000 closed public profile batches do not read or rewrite the UI tree');
assert.equal(probeCounts.refresh, 1000, 'rebinding the private function measures the registered live callback');
assert.equal(probeCounts.render, 0, 'closed public profile updates do not reach the renderer');
assert.equal(cfg.SurvivalVIP.IsAvailable(), true, 'latest public profile entitlement unlocks the entry');
assert.equal(requests.length, 0);

const snapshot = {ok: true, level: 2, balance: 19, recharge_total_fen: 10000, rows: {}};
cfg.VIPRewardCatalog.rewards.forEach((row, index) => {
    snapshot.rows[index] = {id: row.reward_id, owned: 0,
        eligible: row.group_id === 'privileges' && row.level <= 2 ? 1 : 0, affordable: 1};
});
for (let i = 0; i < 1000; i++) {
    events.survival_vip_snapshot({...snapshot, balance: i});
}
assert.deepEqual(counts, closed, 'closed action/account snapshots cache their newest wallet and rewards');
assert(cfg.SurvivalVIP.Open());
assert(opened);
assert.equal(nodes.VIPGrid.children.length, 12);
assert.equal(nodes.VIPWallet.text, '当前 VIP2    商城付费币 999');
assert.equal(nodes.VIPAction.enabled, true);
assert.equal(nodes.VIPActionText.text, '免费领取');
assert.equal(requests.at(-1).payload.action, 'view');
nodes.VIPAction.events.onactivate();
assert.equal(requests.at(-1).payload.action, 'claim');
assert.equal(nodes.VIPAction.enabled, false);
const pendingRequests = requests.length;
nodes.VIPAction.events.onactivate();
assert.equal(requests.length, pendingRequests, 'pending reward actions remain guarded');
cfg.SurvivalVIP.Close();
const hiddenPending = {...counts};
const completed = {...snapshot, balance: 40, rows: {...snapshot.rows,
    0: {...snapshot.rows[0], owned: 1}}};
events.survival_vip_snapshot(completed);
assert.deepEqual(counts, hiddenPending, 'a response after close commits ownership without rebuilding cards');
cfg.SurvivalVIP.Open();
assert.equal(nodes.VIPWallet.text, '当前 VIP2    商城付费币 40');
assert(nodes.VIPCard_vip_privilege_01.BHasClass('VIPOwned'));
assert.equal(nodes.VIPAction.enabled, false);

cfg.SurvivalVIP.Close();
const beforeError = {...counts};
events.survival_vip_snapshot({...completed, action_result: {ok: false, error: '保存失败，请稍后重试'}});
assert.deepEqual(counts, beforeError, 'closed result messages are cached without touching footer nodes');
cfg.SurvivalVIP.Open();
assert.equal(nodes.VIPStatus.text, '保存失败，请稍后重试', 'reopening preserves the latest action error');
events.survival_vip_snapshot({...completed, balance: 42});
assert.equal(nodes.VIPWallet.text, '当前 VIP2    商城付费币 42', 'an open view applies new wallet values immediately');
assert.equal(nodes.VIPStatus.text, '已获得的奖励点亮显示 · 永久生效', 'a confirmed response clears stale errors');
const beforeRevoke = counts.grid;
profile = {vip_badge: false};
tableListener('survival_player_public_profiles', '0', profile);
assert(!opened, 'an open view closes when its real entitlement is removed');
assert.equal(counts.grid, beforeRevoke, 'revocation closes the view without rebuilding its hidden grid');
assert.equal(cfg.SurvivalVIP.Open(), false);
modules[0].entries.forEach(entry => entry.restore());
toolsMode = false;
const registrations = modules.length;
assert.equal(cfg.SurvivalVIP.RegisterToolsProbe(), false);
assert.equal(modules.length, registrations, 'production mode does not install timing hooks');
console.log('VIP_CLOSED_REFRESH_PASS: 1000 profile/snapshot batches avoid closed DOM work, live entitlement/wallet/ownership/errors, busy gating, revoke-close and opt-in cross-context private probes');
