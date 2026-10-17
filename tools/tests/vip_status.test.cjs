'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const project = path.resolve(__dirname, '../..');
const scripts = path.join(project, 'panorama/src/scripts/custom_game');

// Both complete production scripts run here. Only native Panorama/entity APIs
// are simulated; navigation callbacks, subscriptions and status rendering are real.
function harness() {
    const panels = [], sent = [], warnings = [], dispatched = [];
    const listeners = new Map(), timers = new Map();
    const counts = {created: 0, deleted: 0, style: 0, text: 0, image: 0, schedules: 0};
    let serial = 0, now = 1000, topLayer = null;
    class Panel {
        constructor(type, parent, id = '') {
            this.paneltype = type; this.id = id; this.parent = null; this.children = [];
            this.classes = new Set(); this.events = {}; this.visible = this.enabled = true;
            this.hittest = this.hittestchildren = true; this.actualuiscale_x = this.actualuiscale_y = 1;
            this.actuallayoutwidth = 1920; this.actuallayoutheight = 1080;
            this.style = new Proxy({}, {set: (target, key, value) => {
                this.check(); counts.style++; target[key] = value; return true;
            }});
            this._text = ''; panels.push(this); counts.created++; this.SetParent(parent);
        }
        check() { assert(!this.deleted, 'native operations cannot access a deleted panel'); }
        IsValid() { return !this.deleted; }
        GetParent() { this.check(); return this.parent; }
        SetParent(parent) { this.check(); if (this.parent) this.parent.children = this.parent.children.filter(p => p !== this); this.parent = parent; if (parent) parent.children.push(this); }
        Children() { this.check(); return this.children.slice(); }
        GetChildCount() { this.check(); return this.children.length; }
        GetChild(index) { this.check(); return this.children[index]; }
        FindChildTraverse(id) { this.check(); if (this.id === id) return this; for (const child of this.children) { const found = child.FindChildTraverse(id); if (found) return found; } return null; }
        AddClass(value) { this.check(); value.split(/\s+/).filter(Boolean).forEach(c => this.classes.add(c)); }
        RemoveClass(value) { this.check(); this.classes.delete(value); }
        BHasClass(value) { this.check(); return this.classes.has(value); }
        SetHasClass(value, active) { active ? this.AddClass(value) : this.RemoveClass(value); }
        SetPanelEvent(name, fn) { this.check(); this.events[name] = fn; }
        SetImage(value) { this.check(); this.image = value; counts.image++; }
        SetScaling(value) { this.check(); this.scaling = value; }
        SetAcceptsFocus(value) { this.check(); this.acceptsFocus = value; }
        SetFocus() {}
        GetAttributeString(name, fallback) { this.check(); return this[name] || fallback; }
        SetAttributeString(name, value) { this.check(); this[name] = value; }
        GetPositionWithinWindow() { this.check(); return {x: 0, y: 0}; }
        DeleteAsync() { this.check(); this.children.slice().forEach(p => p.DeleteAsync()); this.SetParent(null); this.deleted = true; counts.deleted++; }
        RemoveAndDeleteChildren() { this.check(); this.children.slice().forEach(p => p.DeleteAsync()); }
        set text(value) { this.check(); this._text = String(value); counts.text++; }
        get text() { this.check(); return this._text; }
    }
    const root = new Panel('Panel', null, 'Root'), ctx = new Panel('Panel', root, 'Context');
    const make = (id, parent = root, type = 'Panel') => new Panel(type, parent, id);
    make('HandoffHUD', ctx);
    const lower = make('lower_hud'), outer = make('center_with_stats', lower), block = make('center_block', outer);
    const portrait = make('PortraitGroup', block);
    ['PortraitContainer', 'portraitHUD', 'portraitHUDOverlay'].forEach(id => make(id, portrait));
    const branch = make('AbilitiesAndStatBranch', block), abilities = make('abilities', branch), inventory = make('inventory', block);
    make('StatBranch', branch);
    const minimap = make('minimap_container'), minimapBlock = make('minimap_block', minimap); make('minimap', minimapBlock);
    ['inventory_composition_layer_container', 'buffs', 'debuffs', 'DashboardButton'].forEach(id => make(id));
    const slotParts = ['ButtonAndLevel', 'ButtonWithLevelUpTab', 'ButtonWell', 'ButtonSize', 'AbilityButton', 'AbilityImage', 'Cooldown', 'CooldownOverlay', 'HotkeyContainer', 'Hotkey', 'HotkeyText', 'AbilityBevel', 'ShineContainer', 'PassiveAbilityBorder', 'AbilityLevelContainer'];
    for (let i = 0; i < 8; i++) { const slot = make('Ability' + i, abilities); slotParts.forEach(id => make(id, slot)); }
    for (let i = 0; i < 9; i++) { const slot = make('inventory_slot_' + i, inventory); slotParts.forEach(id => make(id, slot)); make('ItemImage', slot, 'Image'); }
    for (const [id, value] of [['SurvivalHeroHealthText', '80 / 100'], ['SurvivalHeroManaText', '20 / 100'], ['SurvivalHeroName', 'Axe'], ['SurvivalHeroLevel', '5'], ['CombatAttackValue', '20'], ['CombatArmorValue', '3'], ['CombatAttackSpeedValue', '100%'], ['CombatStrengthValue', '10'], ['CombatAgilityValue', '10'], ['CombatIntellectValue', '10']]) make(id, ctx, 'Label').text = value;
    make('SurvivalHeroHealthFill', ctx).style.width = '80%'; make('SurvivalHeroManaFill', ctx).style.width = '20%';
    // Legacy markup is deliberately present: the new controller must not adopt
    // a menu or create reward cells merely to display a membership grade.
    const archiveRoot = make('ArchiveRoot', ctx), legacy = make('VIPWindow', archiveRoot);
    make('VIPScrim', archiveRoot); make('VIPGrid', legacy); legacy.visible = false;
    let payments = 0, treasures = 0;
    const cfg = {
        HandoffAssets: new Proxy({}, {get: (_, key) => ({file: String(key) + '.png'})}),
        HandoffGeometry: require(path.join(scripts, 'geometry_remaining_5d5c1152eb.js')),
        HandoffCombat: {Entries: () => [], NativeEntries: () => [], Snapshot: () => ({}), RefreshSelection() {}, ApplyRuntime() {}},
        SurvivalSelectionResolver: {ResolveDisplayUnit: () => 7},
        SurvivalNumberFormatter: {Compact: value => String(value ?? '—')},
        SurvivalProductionHUD: {Refresh: () => 0}, SurvivalUILayers: {Top: () => topLayer},
        SurvivalPayments: {Open() { payments++; }}, SurvivalTreasure: {Toggle() { treasures++; }}
    };
    const initial = {sequence: 1, resources: {wood: 100, gold: 50, population: 1, max_population: 20}, wave: {alive: 0, alive_limit: 90, current_wave: 1, total_waves: 30, timer: 10, status: 'countdown', countdown_deadline: 100}};
    const env = vm.createContext({
        GameUI: {CustomUIConfig: () => cfg}, Players: {GetLocalPlayerPortraitUnit: () => 7},
        Game: {GetLocalPlayerID: () => 0, GetGameTime: () => now / 1000, IsInToolsMode: () => false},
        Entities: {GetUnitName: () => 'npc_dota_hero_axe', IsHero: () => true, IsBuilding: () => false, GetAbility: () => -1, GetItemInSlot: () => -1},
        Abilities: {GetAbilityName: () => '', IsHidden: () => false},
        CustomNetTables: {GetTableValue: table => table === 'survival_ui_state' ? initial : null},
        GameEvents: {
            Subscribe(name, fn) { const id = ++serial; listeners.set(id, {name, fn}); return id; },
            Unsubscribe(id) { listeners.delete(id); },
            SendCustomGameEventToServer(name, payload) { sent.push({name, payload: JSON.parse(JSON.stringify(payload))}); }
        },
        Date: {now: () => now},
        $: {GetContextPanel: () => ctx, CreatePanel: (type, parent, id) => new Panel(type, parent, id),
            Schedule(delay, fn) { counts.schedules++; const id = ++serial; timers.set(id, {at: now + delay * 1000, fn}); return id; },
            CancelScheduled(id) { timers.delete(id); }, RegisterEventHandler() {}, Msg() {},
            Warning(message) { warnings.push(String(message)); }, DispatchEvent(...args) { dispatched.push(args); }, Localize: value => value}
    });
    function load(name) { vm.runInContext(fs.readFileSync(path.join(scripts, name), 'utf8'), env, {filename: name}); }
    function advance(ms) {
        const until = now + ms; let work = 0;
        while (true) {
            const next = [...timers].sort((a, b) => a[1].at - b[1].at)[0];
            if (!next || next[1].at > until) break;
            assert(++work < 20000, 'scheduler must remain bounded'); timers.delete(next[0]); now = next[1].at; next[1].fn();
        }
        now = until;
    }
    function callbacks(name) { return [...listeners.values()].filter(item => item.name === name).map(item => item.fn); }
    function emit(name, value) { callbacks(name).forEach(fn => fn(value)); }
    // A full HUD script reload allocates replacement panels. Inspect the newest
    // actual instance so a stale badge cannot make the reload assertions pass.
    function node(id) { const found = panels.findLast(panel => panel.id === id && panel.IsValid()); assert(found, 'real production panel ' + id + ' exists'); return found; }
    return {cfg, env, root, ctx, panels, counts, sent, warnings, dispatched, timers, load, advance, callbacks, emit, node,
        make, layer(value) { topLayer = value; }, neighbors: () => ({payments, treasures})};
}

function json(value) { return JSON.parse(JSON.stringify(value)); }
function rgb(value) {
    const hex = /^#([0-9a-f]{6})(?:[0-9a-f]{2})?$/i.exec(value);
    if (hex) return [0, 2, 4].map(i => parseInt(hex[1].slice(i, i + 2), 16));
    const functional = /^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,[^)]+)?\s*\)$/i.exec(value);
    assert(functional, 'appearance exposes a concrete RGB color: ' + value);
    return functional.slice(1, 4).map(Number);
}
function hue(value) {
    const [r, g, b] = rgb(value).map(n => n / 255), max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min;
    assert(d > 0, 'member colors are chromatic');
    return (60 * (max === r ? ((g - b) / d) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4) + 360) % 360;
}
function descendants(panel) { return panel.children.flatMap(child => [child, ...descendants(child)]); }
function statusLabels(button) { return descendants(button).filter(p => p.paneltype === 'Label').map(p => p.text); }
function vipRequests(h) { return h.sent.filter(event => event.name === 'survival_vip_request'); }
function assertReadOnly(h) { assert(vipRequests(h).every(event => event.payload.action === 'view'), 'VIP status can only request a read-only snapshot'); }
function actualBadge(button) {
    const children = descendants(button), hosts = children.filter(p => p.BHasClass('VIPStatusBadge'));
    assert.equal(hosts.length, 1, 'each navigation entry has exactly one actual badge');
    const host = hosts[0], motes = descendants(host).filter(p => p.BHasClass('VIPStatusMote'));
    assert.equal(motes.length, 14, 'one bounded particle allocation serves all twelve grades');
    return {host, motes, number: host.FindChildTraverse('HandoffVIPLevel'), word: host.FindChildTraverse('HandoffVIPWord'), aura: host.FindChildTraverse('HandoffVIPAura')};
}

function vip() {
    const h = harness();
    h.load('vip_window.js');
    const status = h.cfg.SurvivalVIPStatus;
    assert(status && status.Appearance && status.Inspect && status.Render, 'production status API is available without a menu shell');
    assert.equal(vipRequests(h).length, 1, 'cold startup subscribes once even before any VIP window was opened');
    assert.equal(vipRequests(h)[0].payload.action, 'view');
    assert.equal(status.Inspect().known, false);
    assert.equal(h.timers.size, 0, 'the status module does not create its own polling or particle timer');
    for (const method of ['IsAvailable', 'IsOpen', 'Open', 'Toggle']) assert.equal(h.cfg.SurvivalVIP[method](), false, method + ' cannot expose the retired VIP UI');
    assert.equal(vipRequests(h).length, 1, 'compatibility entry points never send claim/purchase/view requests');
    assert.equal(h.node('VIPGrid').GetChildCount(), 0);

    h.load('topnav_remaining_5d5c1152eb.js'); h.advance(1500);
    assert.deepEqual(h.warnings, [], 'complete HUD starts without swallowed native errors');
    let button = h.node('HandoffNav_vip');
    assert(statusLabels(button).includes('—'), 'unknown membership is visibly unknown, not fabricated VIP1');
    assert.equal(button.enabled, false); assert.equal(button.hittest, false); assert.equal(button.hittestchildren, false);
    const click = button.events.onactivate;
    const calls = h.sent.length;
    if (click) click();
    assert.equal(h.sent.length, calls, 'even direct activation of the captured callback is inert');
    assert.equal(h.node('VIPWindow').visible, false);
    h.node('HandoffNav_shop').events.onactivate(); h.node('HandoffNav_treasure').events.onactivate();
    assert.deepEqual(h.neighbors(), {payments: 1, treasures: 1}, 'neighboring real navigation actions still work');
    h.layer('vip'); h.advance(200);
    assert.equal(button.BHasClass('HandoffNavActive'), false, 'VIP is not an active-window navigation target'); h.layer(null);

    const looks = Array.from({length: 12}, (_, i) => json(status.Appearance(i + 1)));
    assert(Math.abs(hue(looks[0].color) - 120) < 0.6, 'VIP1 starts green');
    assert(Math.min(hue(looks[11].color), 360 - hue(looks[11].color)) < 0.6, 'VIP12 ends red');
    for (let i = 0; i < looks.length; i++) {
        const look = looks[i]; assert.equal(look.level, i + 1); assert.equal(look.particleCount, i + 3);
        assert(Number.isFinite(look.intensity) && look.intensity > 0); assert(Number.isFinite(look.duration) && look.duration > 0);
        if (i) { assert(look.intensity > looks[i - 1].intensity, 'each higher grade has stronger light'); assert(Math.abs((hue(looks[i - 1].color) - hue(look.color)) - 120 / 11) < 1.2, 'the twelve grades have equal hue steps'); }
    }
    assert.equal(status.Appearance(0).particleCount, 0);
    const gradeZero = rgb(status.Appearance(0).color); assert(Math.max(...gradeZero) - Math.min(...gradeZero) <= 32, 'non-member styling is a muted gray');
    const panelCount = h.counts.created;
    const badge = actualBadge(button);
    let lastOpacity = 0;
    for (let level = 0; level <= 12; level++) {
        h.emit('survival_vip_snapshot', {ok: true, level});
        const inspected = status.Inspect(); assert.equal(inspected.known, true); assert.equal(inspected.level, level);
        assert.equal(inspected.color, status.Appearance(level).color); assert.equal(inspected.particleCount, level ? level + 2 : 0);
        assert(statusLabels(button).includes(String(level)), 'the actual top badge displays authoritative VIP' + level);
        assert.equal(badge.number.style.color, inspected.color); assert.equal(badge.word.style.color, inspected.color);
        assert.equal(badge.motes.filter(mote => mote.visible).length, inspected.particleCount, 'the actual rendered particle count follows membership');
        assert.equal(badge.aura.visible, level > 0);
        for (const mote of badge.motes.filter(mote => mote.visible)) {
            assert.equal(mote.style.washColor, inspected.color);
            assert(Math.abs(Number(mote.style.opacity) - status.Appearance(level).intensity) < 0.001);
            assert(Number.parseFloat(mote.style.animationDuration) > 0);
            assert.equal(mote.hittest, false); assert.equal(mote.hittestchildren, false);
        }
        if (level) { const opacity = Number(badge.aura.style.opacity); assert(opacity > lastOpacity, 'the actual aura becomes stronger at every grade'); lastOpacity = opacity; }
        assert.equal(h.counts.created, panelCount, 'level changes reuse a bounded set of light panels');
    }
    const originalWidth=button.style.width;
    for(const width of [36,60,90]){
        button.style.width=width+'px';status.Render(button);
        assert.equal(parseFloat(badge.host.style.width),width,'the status canvas follows the real navigation width');
        const numberX=parseFloat(badge.number.style.position),numberWidth=parseFloat(badge.number.style.width);
        assert(numberX+numberWidth<=width,'two-digit membership remains inside the scaled button');
        assert.equal(parseFloat(badge.number.style.fontSize),Math.round(20*width/60),'text is laid out at native pixel size');
        assert.equal(h.counts.created,panelCount,'resolution changes reuse the same particles');
    }
    button.style.width=originalWidth;status.Render(button);
    const same = {...h.counts}, sameTimers = h.timers.size;
    for (let i = 0; i < 1000; i++) {
        h.emit('survival_vip_snapshot', {ok: true, level: 12, balance: i, rows: {}});
        status.Render(button, {icon: h.node('HandoffNavIcon_vip'), caption: h.node('HandoffNavCaption_vip'), glow: h.node('HandoffNavGlow_vip')});
    }
    assert.deepEqual(h.counts, same, 'unchanged grade events/render calls perform zero allocation, style, text, image or timer writes');
    assert.equal(h.timers.size, sameTimers);
    for (const level of [null, undefined, '', '01', '2.0', ' 2', '2\n', true, false, -1, 1.5, 13, NaN, Infinity]) {
        h.emit('survival_vip_snapshot', {ok: true, level}); assert.equal(status.Inspect().level, 12, 'malformed grade does not replace the last authoritative value');
    }
    h.emit('survival_vip_snapshot', {ok: false, level: 1}); assert.equal(status.Inspect().level, 12);
    h.emit('survival_vip_snapshot', {ok: true, level: '1'}); assert.equal(status.Inspect().level, 1); assert(statusLabels(button).includes('1'));
    h.emit('survival_vip_snapshot', {ok: true, level: 0}); assert.equal(status.Inspect().particleCount, 0);
    assert.equal(badge.motes.filter(mote => mote.visible).length, 0); assert.equal(badge.aura.visible, false, 'membership reset removes every active light');

    const retired = h.callbacks('survival_vip_snapshot').slice(), oldStatus = status, oldVIP = h.cfg.SurvivalVIP;
    h.load('vip_window.js'); h.advance(200);
    const replacement = h.cfg.SurvivalVIPStatus;
    assert.notStrictEqual(replacement, oldStatus); assert.equal(h.callbacks('survival_vip_snapshot').length, 1, 'reload owns exactly one membership listener');
    h.emit('survival_vip_snapshot', {ok: true, level: 7});
    const afterReload = {...h.counts}, requests = h.sent.length;
    retired.forEach(fn => fn({ok: true, level: 12})); oldVIP.Open(); oldVIP.Toggle();
    oldStatus.Render(button, {icon: h.node('HandoffNavIcon_vip'), caption: h.node('HandoffNavCaption_vip'), glow: h.node('HandoffNavGlow_vip')});
    assert.equal(replacement.Inspect().level, 7); assert.deepEqual(h.counts, afterReload, 'retired callbacks cannot mutate replacement status panels'); assert.equal(h.sent.length, requests);
    const previousBadgeHost=actualBadge(button).host;
    h.load('topnav_remaining_5d5c1152eb.js'); h.advance(1500); button = h.node('HandoffNav_vip');
    assert.equal(previousBadgeHost.IsValid(),false,'HUD reload removes the retired particle layer');
    assert.equal(h.panels.filter(panel=>panel.IsValid()&&panel.BHasClass('VIPStatusMote')).length,14,'reload retains one bounded particle layer');
    assert(statusLabels(button).includes('7'), 'HUD reload renders cached membership without opening a menu');
    assert.equal(button.enabled, false); assert.equal(button.hittest, false); assert.equal(button.hittestchildren, false);
    if (button.events.onactivate) button.events.onactivate();
    assertReadOnly(h); assert.deepEqual(h.warnings, []);
    // The top entry must remain inert even before the new status module loads,
    // when a stale or third-party window controller claims the VIP page exists.
    const late = harness(); let legacyOpened = 0;
    late.cfg.SurvivalVIP = {IsAvailable: () => true, Toggle() { legacyOpened++; }, Open() { legacyOpened++; }};
    late.load('topnav_remaining_5d5c1152eb.js'); late.advance(1000);
    const lateButton = late.node('HandoffNav_vip'), lateCounts = {...late.counts}, lateSent = late.sent.length;
    assert.equal(lateButton.enabled, false); assert.equal(lateButton.hittest, false);
    if (lateButton.events.onactivate) lateButton.events.onactivate();
    assert.equal(legacyOpened, 0); assert.equal(late.sent.length, lateSent);
    assert.deepEqual(late.counts, lateCounts, 'a disabled VIP callback does not display unavailable notices or schedule work');
    late.load('vip_window.js'); late.emit('survival_vip_snapshot', {ok: true, level: 4}); late.advance(200);
    assert.equal(actualBadge(lateButton).number.text, '4', 'a late status module attaches through the real HUD refresh');
    assert.equal(vipRequests(late).length, 1); assertReadOnly(late); assert.deepEqual(late.warnings, []);
    console.log('VIP_STATUS_PASS: full HUD cold boot; passive entry; 12 equal hue steps; increasing bounded particles; cached updates; no purchase/claim; reload retirement; neighboring navigation.');
    return {levels: 12, viewRequests: vipRequests(h).length, particlePanels: 14};
}

module.exports = {vip};
if (require.main === module) vip();
