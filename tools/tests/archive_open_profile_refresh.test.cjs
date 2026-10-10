const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');

// Exercise the manifest's complete controllers, including the real delta and
// icon warm cache. Changing a server revision must not erase an opened view.
const project = path.resolve(__dirname, '../..');
const scriptDirectory = path.join(project, 'panorama/src/scripts/custom_game');
const manifest = fs.readFileSync(path.join(project, 'panorama/src/layout/custom_game/archive.xml'), 'utf8');
const scripts = ['ui_snapshot_cache.js', 'archive_void_v1_data.js', 'archive_void_v1.js',
    'archive_180de7e38b_titles_compact_v6.js'];
for (const name of scripts) assert(manifest.includes('/' + name + '"'), 'test the active manifest source: ' + name);

const metrics = {created: 0, deleted: 0, style: 0, classes: 0, tree: 0,
    text: 0, images: 0, fits: 0, palettes: 0, hiddenTooltips: 0};
const nodes = new Map(), subscriptions = new Map(), requests = [], scheduled = [];
class Panel {
    constructor(type, parent, id = '') {
        this.paneltype = type; this.parent = parent; this.id = id;
        this.children = []; this.classes = new Set(); this.events = {};
        this.visible = true; this.enabled = true;
        this.style = new Proxy({}, {set(target, key, value) {
            metrics.style++; target[key] = value; return true;
        }});
        metrics.created++;
        if (parent) parent.children.push(this);
        if (id) nodes.set(id, this);
    }
    get text() { return this._text || ''; }
    set text(value) { metrics.text++; this._text = value; }
    IsValid() { return !this.deleted; }
    AddClass(name) { metrics.classes++; this.classes.add(name); }
    RemoveClass(name) { metrics.classes++; this.classes.delete(name); }
    SetHasClass(name, value) { value ? this.AddClass(name) : this.RemoveClass(name); }
    BHasClass(name) { return this.classes.has(name); }
    Children() { metrics.tree++; return this.children; }
    GetParent() { return this.parent; }
    FindChildTraverse(id) {
        metrics.tree++;
        if (this.id === id) return this;
        for (const child of this.children) {
            if (!child.IsValid()) continue;
            const found = child.FindChildTraverse(id);
            if (found) return found;
        }
        return null;
    }
    RemoveAndDeleteChildren() { this.children.slice().forEach(child => child.DeleteAsync()); }
    DeleteAsync() {
        if (this.deleted) return;
        this.children.slice().forEach(child => child.DeleteAsync());
        this.deleted = true; metrics.deleted++;
        if (this.parent) this.parent.children = this.parent.children.filter(child => child !== this);
        if (nodes.get(this.id) === this) nodes.delete(this.id);
    }
    SetPanelEvent(name, callback) { this.events[name] = callback; }
    SetImage(value) { metrics.images++; this.image = value; }
    SetScaling(value) { this.scaling = value; }
    ScrollToTop() {}
}
const root = new Panel('Panel', null, 'ArchiveRoot');
['ArchiveWindow', 'ArchiveScrim', 'ArchiveHeader', 'ArchiveTitle', 'ArchiveClose',
    'ArchiveContent', 'ArchiveTabs', 'ArchiveGrid', 'ArchiveFilters', 'ArchiveFilter_all',
    'ArchiveFilter_unlocked', 'ArchiveFilter_locked', 'ArchiveFilterAllLabel', 'ArchiveTooltip',
    'ArchiveTooltipStateIcon', 'ArchiveDraw', 'ArchiveTickets', 'ArchiveDrawResult', 'ArchiveDrawBar',
    'ArchiveFaith', 'ArchiveCurrencySource', 'ArchiveEmpty', 'ArchivePageTitle', 'ArchiveSummary',
    'ArchiveContext', 'ArchiveHint', 'ArchiveStatus', 'EndlessStatus'].forEach(id => new Panel('Panel', root, id));
let shownTooltip = null, walletBalances = {u_coin: 10, shop_points: 20, shop_gold: 30};
const cfg = {
    SurvivalArchiveColors: {number: '#ffd800'},
    ArchiveHandoffAssets: {'icon_check_light.png': 'check', 'icon_lock_light.png': 'lock'},
    SurvivalCommerceWallet: {GetCatalog() { return {balances: walletBalances}; }},
    SurvivalUI: {
        ModalShell: {Adopt() { return {Open() {}, Close() {}, Dispose() {}}; }},
        NavToggle: {Adopt() {}}, ActionButton: {Adopt() {}}, Tooltip: {Adopt() {}},
        Fit() { metrics.fits++; }
    },
    ArchiveHandoff: {
        Init() {}, HideCardText() {}, NavIcon() {}, Card() {}, Icon() {},
        Hide() { metrics.hiddenTooltips++; shownTooltip = null; },
        Show(item, category, card) { shownTooltip = {item, category, card}; },
        ShowEffectOnly(item, card) { shownTooltip = {item, card}; },
        Observe(data) { this.snapshot = data; },
        Unlocked(item, category) {
            if (Number(item.count_known) === 0) return null;
            if (['building', 'work', 'fragment'].includes(category)) return Number(item.level) > 0;
            if (['clear', 'endless', 'boss', 'map_level'].includes(category)) return Number(item.completed) === 1;
            return Number(item.count) > 0;
        },
        ApplyPalette() {
            metrics.palettes++;
            function paint(panel) {
                panel.style.color = cfg.SurvivalArchiveColors.number;
                panel.Children().forEach(paint);
            }
            paint(nodes.get('ArchiveGrid'));
        }
    }
};
let nextTimer = 0;
const context = vm.createContext({
    $: {
        GetContextPanel: () => root,
        CreatePanel: (type, parent, id) => new Panel(type, parent, id),
        Schedule(delay, callback) {
            const timer = {id: ++nextTimer, delay, callback}; scheduled.push(timer); return timer;
        },
        CancelScheduled(timer) { timer.cancelled = true; },
        RegisterEventHandler() {}, DispatchEvent() {}
    },
    GameUI: {CustomUIConfig: () => cfg},
    Game: {GetLocalPlayerID: () => 0, IsInToolsMode: () => false},
    GameEvents: {
        Subscribe(name, callback) {
            const listener = {name, callback};
            const listeners = subscriptions.get(name) || [];
            listeners.push(listener); subscriptions.set(name, listeners); return listener;
        },
        Unsubscribe(listener) { listener.cancelled = true; },
        SendCustomGameEventToServer(name, payload) { requests.push({name, payload}); }
    }
});
for (const name of scripts) vm.runInContext(fs.readFileSync(path.join(scriptDirectory, name), 'utf8'), context, {filename: name});
const api = cfg.SurvivalArchive, voidView = cfg.SurvivalArchiveVoidV1;
const categories = JSON.parse(JSON.stringify(cfg.ArchiveVoidV1Data.categories));
const versions = {}, dataByCategory = {};
function emit(name, payload) {
    for (const listener of (subscriptions.get(name) || []).slice()) {
        if (!listener.cancelled) listener.callback(payload);
    }
}
function immediate() {
    for (let executions = 0; executions < 100; executions++) {
        const index = scheduled.findIndex(timer => !timer.cancelled && timer.delay === 0);
        if (index < 0) return;
        const timer = scheduled.splice(index, 1)[0]; timer.callback();
    }
    throw new Error('unexpected zero-delay timer loop');
}
function snapshot(category, rows, extra = {}) {
    const data = {ok: 1, category_id: category, sequence: (versions[category] || 0) + 1,
        chunks: 1, chunk: 1, categories, rows, pending: 0, profile_revision: Date.now(), ...extra};
    versions[category] = data.sequence;
    dataByCategory[category] = JSON.parse(JSON.stringify(data));
    emit('survival_archive_snapshot', JSON.parse(JSON.stringify(data)));
    immediate();
    return data;
}
function resend(category, extra = {}) {
    const {rows, ...metadata} = dataByCategory[category];
    delete metadata.sequence;
    return snapshot(category, rows, {...metadata, ...extra});
}
function delta(category, changes) {
    const base = versions[category];
    const latest = ++versions[category];
    const previous = dataByCategory[category];
    dataByCategory[category] = JSON.parse(JSON.stringify(cfg.SurvivalSnapshotCache.Apply(previous, changes)));
    dataByCategory[category].sequence = latest;
    emit('survival_archive_snapshot', {ok: 1, category_id: category, sequence: latest,
        base_sequence: base, delta: 1, chunks: 1, chunk: 1, rows: changes});
    immediate();
}
function descendant(panel, className) {
    if (panel.classes.has(className)) return panel;
    for (const child of panel.children) {
        const found = descendant(child, className); if (found) return found;
    }
    return null;
}
function visibleCards() { return nodes.get('ArchiveGrid').children.filter(card => card.visible && card.classes.has('ArchiveCard')); }
function voidCards() { return nodes.get('VoidShadowGrid').children.filter(card => card.visible); }
function activate(panel) { assert(panel && panel.events.onactivate, 'an active control exists'); panel.events.onactivate(); }
function hover(panel) { assert(panel && panel.events.onmouseover, 'a hover target exists'); panel.events.onmouseover(); }
function noRebuildOrStyle(before, label) {
    for (const key of ['created', 'deleted', 'style', 'palettes', 'fits']) {
        assert.equal(metrics[key], before[key], label + ': ' + key);
    }
}

const shadowRows = [
    {id: 'shadow_01', name: '幻象树枝', count: 3, count_known: 1, target: 430, description: '木材+10'},
    {id: 'shadow_02', name: '贪婪金币', count: 0, count_known: 1, target: 430, description: '金币+1'}
];
snapshot('clear', [{id: 'clear_01', name: '第一阶', count: 0, target: 1, completed: 0}]);
snapshot('shadow', shadowRows);
snapshot('building', [{id: 'building_01', name: '神器', count: 0, level: 0,
    target: 5, cost: 20, completed: 0, can_upgrade: 1, description: '当前Lv0'}],
{upgrade_pending: 0, buildings: {faith: 100, earned_today: 1, daily_cap: 10, per_clear: 1}});
snapshot('friend', [{id: 'friend_01', name: '好友', count: 0, target: 100}],
{social: {currency_name: '友情券', tickets: 2, draw_cost: 1, remaining: 1, total: 0}});
snapshot('fragment', [{id: 'fragment_01', name: '神兵-初阶', count: 20, level: 1,
    can_promote: 1, promotion_target: 'fragment_02', promotion_cost: 20},
{id: 'fragment_02', name: '神兵-高阶', count: 0, level: 0}]);
api.Open(); api.SelectCategory('shadow'); immediate();
assert.equal(voidCards().length, cfg.ArchiveVoidV1Data.catalog.length, 'the actual catalog is visible');
assert.equal(descendant(nodes.get('VoidShadowItem_shadow_01'), 'VoidShadowCount').text, '3/430');
const originalCards = voidCards(), originalSidebar = nodes.get('VoidShadowSidebar').children.slice();
const firstCard = nodes.get('VoidShadowItem_shadow_01');
const firstCount = descendant(firstCard, 'VoidShadowCount');
hover(nodes.get('VoidShadowItem_shadow_01'));
const initialTooltip = shownTooltip, stable = {...metrics};
for (let revision = 1; revision <= 1000; revision++) {
    resend('shadow', {profile_revision: revision, server_time: revision,
        unrelated_endless_score: revision * 100});
}
noRebuildOrStyle(stable, '1000 accepted revisions with identical visible shadow data');
assert.deepEqual(voidCards(), originalCards, 'revision changes retain the native card identities');
assert.deepEqual(nodes.get('VoidShadowSidebar').children, originalSidebar, 'revision changes retain the sidebar');
assert.equal(shownTooltip, initialTooltip, 'unrelated revisions preserve the currently hovered tooltip');

delta('shadow', [{path: ['rows', 1, 'count'], value: 7},
    {path: ['rows', 1, 'description'], value: '木材+70'}]);
assert.equal(descendant(nodes.get('VoidShadowItem_shadow_01'), 'VoidShadowCount').text, '7/430', 'a visible delta is not dropped after skipped revisions');
assert.equal(nodes.get('VoidShadowItem_shadow_01'), firstCard, 'changed quantities update the existing native card');
assert.equal(descendant(firstCard, 'VoidShadowCount'), firstCount, 'changed quantities retain their native label');
assert.deepEqual(nodes.get('VoidShadowSidebar').children, originalSidebar, 'item changes do not rebuild unrelated navigation');
assert.equal(shownTooltip.card, firstCard, 'a changing hovered row keeps the tooltip on the same native card');
assert.equal(shownTooltip.item.count, 7, 'an already visible tooltip refreshes without another mouse event');
assert.equal(shownTooltip.item.description, '木材+70');
hover(nodes.get('VoidShadowItem_shadow_01'));
assert.equal(shownTooltip.item.description, '木材+70', 'hover uses the latest delta row');
assert.equal(shownTooltip.item.count, 7);
emit('survival_archive_snapshot', {ok: 1, category_id: 'shadow', sequence: versions.shadow - 1,
    chunks: 1, chunk: 1, categories, rows: [{...shadowRows[0], count: 999}]});
assert.equal(descendant(firstCard, 'VoidShadowCount').text, '7/430', 'an older snapshot cannot roll back the accepted cache');
resend('shadow', {has_pass: 1});
assert(nodes.get('ArchiveHint').text.includes('3次'), 'pass benefits remain live even when rows are unchanged');
const rows = JSON.parse(JSON.stringify(dataByCategory.shadow.rows));
rows[0].description = '仅说明更新';
snapshot('shadow', rows, {has_pass: 1});
hover(nodes.get('VoidShadowItem_shadow_01'));
assert.equal(shownTooltip.item.description, '仅说明更新', 'tooltip-only changes replace stale hover closures');
api.Filter('unlocked');
assert.equal(voidCards().length, 1, 'ownership filtering still uses actual counts');
rows[1].count = 2;
snapshot('shadow', rows, {has_pass: 1});
assert.equal(voidCards().length, 2, 'a newly owned item enters the active filter immediately');
rows[1].count_known = 0;
snapshot('shadow', rows, {has_pass: 1});
assert.equal(voidCards().length, 1, 'unknown inventory never appears as unlocked');
api.Filter('all');
assert.equal(descendant(nodes.get('VoidShadowItem_shadow_02'), 'VoidShadowCount').text, '—/430');
hover(nodes.get('VoidShadowItem_shadow_02'));
assert.equal(nodes.get('ArchiveTooltipStateIcon').visible, false, 'unknown ownership hides the misleading state icon');
hover(nodes.get('VoidShadowItem_shadow_01'));
assert.equal(nodes.get('ArchiveTooltipStateIcon').visible, true, 'known ownership restores the state icon');
const renamedCategories = JSON.parse(JSON.stringify(categories));
Object.assign(renamedCategories.find(category => category.id === 'clear'), {name: '通关进度', disabled: 1});
resend('shadow', {categories: renamedCategories});
const clearSidebar = nodes.get('VoidShadowCategory_clear');
assert.equal(clearSidebar.enabled, false, 'updated category availability reaches the custom sidebar');
assert(clearSidebar.children.some(child => child.text === '通关进度'), 'updated category names reach the custom sidebar');
resend('shadow', {categories});

walletBalances = {u_coin: 41, shop_points: 52, shop_gold: 63};
const walletBefore = {...metrics}, walletCards = voidCards();
emit('survival_commerce_result', {ok: 1}); immediate();
assert.equal(nodes.get('VoidShadow_gold_text').text, '41');
assert.equal(nodes.get('VoidShadow_purple_gem_text').text, '52');
assert.equal(nodes.get('VoidShadow_ticket_text').text, '63');
noRebuildOrStyle(walletBefore, 'wallet-only result updates balances without painting cards');
assert.deepEqual(voidCards(), walletCards);

api.SelectCategory('building');
let building = visibleCards()[0];
hover(building); assert.equal(shownTooltip.item.level, 0);
const beforeUpgrade = requests.length;
activate(building); activate(building);
assert.equal(requests.length, beforeUpgrade + 1, 'double clicks submit one manual reward upgrade');
assert.equal(requests.at(-1).name, 'survival_archive_building_upgrade');
assert.equal(requests.at(-1).payload.expected_level, 0);
resend('building');
building = visibleCards()[0]; activate(building);
assert.equal(requests.length, beforeUpgrade + 2, 'an unchanged authoritative rejection re-enables the manual action');
const upgraded = {...dataByCategory.building.rows[0], level: 2, description: '当前Lv2', cost: 40};
snapshot('building', [upgraded], {upgrade_pending: 0,
    buildings: {faith: 60, earned_today: 2, daily_cap: 10, per_clear: 1}});
building = visibleCards()[0]; hover(building);
assert.equal(shownTooltip.item.level, 2, 'artifact levels are refreshed');
assert.equal(shownTooltip.item.description, '当前Lv2');
assert.equal(building.__archiveUnlocked, true, 'ownership shading follows the new level');
assert(nodes.get('ArchiveSummary').text.includes('信仰值：60'), 'a balance-only header is current');
activate(building);
assert.equal(requests.at(-1).payload.expected_level, 2, 'the manual action uses the new level');
resend('building', {upgrade_pending: 1});
const lockedRequests = requests.length;
activate(visibleCards()[0]);
assert.equal(requests.length, lockedRequests, 'pending saves block manual actions even if rows stay the same');
assert(nodes.get('ArchiveStatus').text.includes('保存'));
const themeBefore = metrics.palettes;
cfg.SurvivalArchiveColors.number = '#abcdef';
resend('building', {upgrade_pending: 0});
assert(metrics.palettes > themeBefore, 'a theme change still repaints existing native cards');

api.SelectCategory('friend');
assert.equal(nodes.get('ArchiveDraw').enabled, true);
activate(nodes.get('ArchiveDraw'));
const drawRequests = requests.length; activate(nodes.get('ArchiveDraw'));
assert.equal(requests.length, drawRequests, 'draw requests keep their local double-click gate');
resend('friend');
assert.equal(nodes.get('ArchiveDraw').enabled, true, 'an unchanged draw rejection releases the local gate');
resend('friend', {pending: 1});
assert.equal(nodes.get('ArchiveDraw').enabled, false, 'pending draw state invalidates the view independently of rows');
resend('friend', {pending: 0, social: {currency_name: '友情券', tickets: 0,
    draw_cost: 1, remaining: 1, total: 0}});
assert.equal(nodes.get('ArchiveDraw').enabled, false, 'a wallet-only change prevents an unaffordable draw');
assert(nodes.get('ArchiveTickets').text.includes('0'));

api.SelectCategory('fragment');
let fragment = visibleCards()[0], promotion = descendant(fragment, 'ArchivePromote');
hover(promotion);
assert(shownTooltip.item.description.includes('高阶'), 'promotion help still resolves the actual target name');
activate(promotion);
const promotionRequests = requests.length; activate(promotion);
assert.equal(requests.length, promotionRequests, 'promotion requests retain their local duplicate guard');
assert.equal(requests.at(-1).name, 'survival_archive_promote');

api.SelectCategory('shadow'); api.Close();
const closed = {...metrics};
for (let revision = 101; revision <= 200; revision++) {
    snapshot('shadow', [{...rows[0], count: revision}, rows[1]], {has_pass: 1, profile_revision: revision});
}
assert.deepEqual(metrics, closed, 'closed profile updates remain data-only, including the custom void view');
api.Open();
assert.equal(descendant(nodes.get('VoidShadowItem_shadow_01'), 'VoidShadowCount').text, '200/430', 'reopening renders the latest cache immediately');
assert.equal(nodes.get('VoidShadow_gold_text').text, '41', 'reopening preserves the current commerce wallet');
api.SelectCategory('clear');
snapshot('clear', [{id: 'clear_01', name: '第一阶', count: 1, target: 1, completed: 1}]);
assert(nodes.get('ArchiveSummary').text.includes('已完成 1 / 1'), 'generic page completion remains live after leaving void');
api.SelectCategory('shadow');
assert.equal(descendant(nodes.get('VoidShadowItem_shadow_01'), 'VoidShadowCount').text, '200/430', 'switching back uses the latest shadow cache');

console.log('ARCHIVE_OPEN_PROFILE_REFRESH_PASS: manifest full-source controllers, 1000 stable revisions, delta baseline, native card/sidebar reuse, live counts/ownership/pass/tooltips/wallet, upgrade/draw rejection and pending guards, promotion duplicate guard, theme, filters, tabs and 100 closed updates');
