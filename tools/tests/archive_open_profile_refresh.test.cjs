const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const {csv} = require('../shop_ui_12h/catalog.cjs');

// Exercise the manifest's complete controllers, including the real delta and
// icon warm cache. Changing a server revision must not erase an opened view.
const project = path.resolve(__dirname, '../..');
const scriptDirectory = path.join(project, 'panorama/src/scripts/custom_game');
const manifest = fs.readFileSync(path.join(project, 'panorama/src/layout/custom_game/archive.xml'), 'utf8');
const scripts = ['ui_snapshot_cache.js', 'archive_purple.js', 'archive_v10_data.js', 'archive_parchment_data.js', 'common/tooltip_dismiss.js', 'common/menu_v10.js', 'archive_v10_semantics.js', 'common/archive_tooltip.js', 'archive_v10.js',
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
    SetParent(parent) {
        if (this.parent) this.parent.children = this.parent.children.filter(child => child !== this);
        this.parent = parent; parent.children.push(this);
    }
    MoveChildBefore(child, before) {
        this.children = this.children.filter(value => value !== child);
        this.children.splice(Math.max(0, this.children.indexOf(before)), 0, child);
    }
    GetPositionWithinWindow() {
        const own = String(this.style.position || '0px 0px 0px').split(/\s+/).map(parseFloat);
        const parent = this.parent ? this.parent.GetPositionWithinWindow() : {x: 0, y: 0};
        return {x: parent.x + (own[0] || 0), y: parent.y + (own[1] || 0)};
    }
    get actualuiscale_x() { return 1; }
    get actualuiscale_y() { return 1; }
    get actuallayoutwidth() { return parseFloat(this.style.width) || 1920; }
    get actuallayoutheight() { return parseFloat(this.style.height) || 160; }
    ScrollToTop() {}
}
const root = new Panel('Panel', null, 'ArchiveRoot');
['ArchiveWindow', 'ArchiveScrim', 'ArchiveHeader', 'ArchiveTitle', 'ArchiveClose',
    'ArchiveContent', 'ArchiveTabs', 'ArchiveGrid', 'ArchiveFilters', 'ArchiveFilter_all',
    'ArchiveFilter_unlocked', 'ArchiveFilter_locked', 'ArchiveFilterAllLabel', 'ArchiveTooltip',
    'ArchiveTooltipStateIcon', 'ArchiveDraw', 'ArchiveTickets', 'ArchiveDrawResult', 'ArchiveDrawBar',
    'ArchiveFaith', 'ArchiveCurrencySource', 'ArchiveEmpty', 'ArchivePageTitle', 'ArchiveSummary',
    'ArchiveContext', 'ArchiveHint', 'ArchiveStatus', 'ArchiveFooter', 'ArchiveBody', 'ArchivePageHeader',
    'ArchiveTooltipBody', 'ArchiveTooltipName', 'ArchiveTooltipStateText', 'ArchiveTooltipProgress',
    'ArchiveTooltipCondition', 'ArchiveTooltipProgressRow', 'EndlessStatus'].forEach(id => new Panel('Panel', root, id));
let shownTooltip = null, walletBalances = {}, walletRefreshes = 0;
const cfg = {
    SurvivalArchiveColors: {number: '#ffd800'},
    ArchiveHandoffAssets: {'icon_check_light.png': 'check', 'icon_lock_light.png': 'lock'},
    SurvivalCommerceWallet: {
        GetCatalog() { return {balances: walletBalances}; },
        Refresh() { walletRefreshes++; }
    },
    SurvivalUI: {
        Lifecycle() { let active=true,epoch=0; return {Later(delay,callback) { const expected=epoch; return context.$.Schedule(delay,()=>{if(active&&expected===epoch)callback();}); },Cancel(){epoch++;},Dispose(){active=false;epoch++;}}; },
        ModalShell: {Adopt() { return {Open() {}, Close() {}, Dispose() {}}; }},
        NavToggle: {Adopt() {}}, ActionButton: {Adopt() {}}, Tooltip: {Adopt() {}},
        Fit() { metrics.fits++; }
    },
    ArchiveHandoff: {
        Init() {}, HideCardText() {}, NavIcon() {}, Card() {}, Icon(parent) {
            const art = new Panel('Panel', parent); art.AddClass('ArchiveArt');
            const image = new Panel('Image', art); image.AddClass('ArchiveRewardIcon');
        },
        Hide() { metrics.hiddenTooltips++; shownTooltip = null; },
        Show(item, category, card) { shownTooltip = {item, category, card}; },
        ShowEffectOnly(item, card) { shownTooltip = {item, card}; },
        Observe(data) { this.snapshot = data; },
        Progress(item) { return String(item.count === undefined ? '—' : item.count) + ' / ' + String(item.target === undefined ? '—' : item.target); },
        Unlocked(item, category) {
            if (cfg.ArchiveV10Semantics) return cfg.ArchiveV10Semantics.State(item, category);
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
        Msg() {}, Schedule(delay, callback) {
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
const api = cfg.SurvivalArchive, view = cfg.SurvivalArchiveV10;
const categories = csv(path.join(project, 'data/csv/存档系统/archive_categories.csv')).map(row => ({
    id: row.category_id, name: row.display_name, disabled: row.enabled === '1' ? 0 : 1, renderer: row.renderer
}));
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
function voidCards() { return visibleCards().filter(card => card.__archiveCategory === 'shadow'); }
function itemCard(id) { return visibleCards().find(card => card.__archiveItem && card.__archiveItem.id === id); }
function tooltipText(id) { return nodes.get('ArchiveV10Tooltip' + id).text; }
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
snapshot('beast', [{id: 'beast_01', name: '散魂钟', count: 0, target: 50}],
{social: {currency_name: '福签', tickets: 2, draw_cost: 1, remaining: 1, total: 0}});
snapshot('fragment', [{id: 'fragment_01', name: '神兵-初阶', count: 20, level: 1,
    can_promote: 1, promotion_target: 'fragment_02', promotion_cost: 20},
{id: 'fragment_02', name: '神兵-高阶', count: 0, level: 0}]);
snapshot('work', [{id: 'work_01', name: '正式福利', count: 0, level: 0, target: 1,
    cost: 15, completed: 0, can_upgrade: 1, description: '已配置福利效果'}],
{upgrade_pending: 0, online: {coins: 30}});
snapshot('titles', [{id: 'title_test', name: '正式称号', unlocked: 1, equipped: 0,
    icon: 'file://{images}/custom_game/titles/peak_clean_letters.png', description: '纯外观称号'}]);
assert.equal(walletRefreshes, 0, 'Closed profile snapshots do not request a commerce catalog');
api.Open(); immediate();
assert.equal(walletRefreshes, 0, 'The independent archive does not request the removed commerce resource strip');
assert.equal(cfg.SurvivalMenuV10.Entries().length, 0, 'Opening the archive creates no global menu or commerce resource panels');
api.SelectCategory('shadow'); immediate();
assert.equal(walletRefreshes, 0, 'Category snapshots remain independent from the commerce catalog');
assert.equal(voidCards().length, cfg.ArchiveV10Data.catalog.length, 'the actual catalog is visible');
assert.equal(descendant(itemCard('shadow_01'), 'ArchiveV10Count').text, '3/430');
const originalCards = voidCards(), originalSidebar = nodes.get('ArchiveV10Sidebar').children.slice();
const firstCard = itemCard('shadow_01');
const firstCount = descendant(firstCard, 'ArchiveV10Count');
hover(firstCard); immediate();
assert.equal(tooltipText('MetricCaption'), '拥有数量', 'The tooltip metric caption is an independent text component');
assert.equal(tooltipText('Quantity'), '3/430', 'The tooltip quantity is independent text without alignment spaces');
assert.equal(nodes.get('ArchiveV10TooltipQuantity').style.textAlign, 'right', 'Independent quantity is actually right aligned');
const initialTooltip = nodes.get('ArchiveV10Tooltip'), initialEffect = tooltipText('Effect'), stable = {...metrics};
for (let revision = 1; revision <= 1000; revision++) {
    resend('shadow', {profile_revision: revision, server_time: revision,
        unrelated_endless_score: revision * 100});
}
noRebuildOrStyle(stable, '1000 accepted revisions with identical visible shadow data');
assert.equal(walletRefreshes, 0, 'One thousand accepted archive revisions require no commerce data');
assert.deepEqual(voidCards(), originalCards, 'revision changes retain the native card identities');
assert.deepEqual(nodes.get('ArchiveV10Sidebar').children, originalSidebar, 'revision changes retain the sidebar');
assert.equal(nodes.get('ArchiveV10Tooltip'), initialTooltip, 'unrelated revisions preserve the tooltip native identity');
assert.equal(initialTooltip.visible, true, 'unrelated revisions preserve the currently hovered tooltip');
assert.equal(tooltipText('Effect'), initialEffect);

delta('shadow', [{path: ['rows', 1, 'count'], value: 7},
    {path: ['rows', 1, 'description'], value: '木材+70'}]);
assert.equal(descendant(itemCard('shadow_01'), 'ArchiveV10Count').text, '7/430', 'a visible delta is not dropped after skipped revisions');
assert.equal(itemCard('shadow_01'), firstCard, 'changed quantities update the existing native card');
assert.equal(descendant(firstCard, 'ArchiveV10Count'), firstCount, 'changed quantities retain their native label');
assert.deepEqual(nodes.get('ArchiveV10Sidebar').children, originalSidebar, 'item changes do not rebuild unrelated navigation');
assert.equal(initialTooltip.visible, true, 'a changing hovered row keeps the tooltip visible on the same native card');
assert.equal(tooltipText('Quantity'), '7/430', 'an already visible tooltip refreshes without another mouse event');
assert.equal(tooltipText('Effect'), '木材+70');
hover(firstCard);
assert.equal(tooltipText('Effect'), '木材+70', 'hover uses the latest delta row');
assert.equal(tooltipText('Quantity'), '7/430');
emit('survival_archive_snapshot', {ok: 1, category_id: 'shadow', sequence: versions.shadow - 1,
    chunks: 1, chunk: 1, categories, rows: [{...shadowRows[0], count: 999}]});
assert.equal(descendant(firstCard, 'ArchiveV10Count').text, '7/430', 'an older snapshot cannot roll back the accepted cache');
resend('shadow', {has_pass: 1});
assert(nodes.get('ArchiveHint').text.includes('3'), 'pass benefits remain live even when rows are unchanged');
const rows = JSON.parse(JSON.stringify(dataByCategory.shadow.rows));
rows[0].description = '仅说明更新';
snapshot('shadow', rows, {has_pass: 1});
hover(itemCard('shadow_01'));
assert.equal(tooltipText('Effect'), '仅说明更新', 'tooltip-only changes replace stale hover closures');
api.Filter('unlocked');
assert.equal(voidCards().length, 1, 'ownership filtering still uses actual counts');
rows[1].count = 2;
snapshot('shadow', rows, {has_pass: 1});
assert.equal(voidCards().length, 2, 'a newly owned item enters the active filter immediately');
rows[1].count_known = 0;
snapshot('shadow', rows, {has_pass: 1});
assert.equal(voidCards().length, 1, 'unknown inventory never appears as unlocked');
api.Filter('all');
assert.equal(descendant(itemCard('shadow_02'), 'ArchiveV10Count').text, '—/430');
hover(itemCard('shadow_02'));
assert(tooltipText('State').includes('状态待同步'), 'unknown ownership hides a misleading owned/locked status');
hover(itemCard('shadow_01'));
assert(tooltipText('State').includes('已拥有'), 'known ownership restores the correct state');
const renamedCategories = JSON.parse(JSON.stringify(categories));
Object.assign(renamedCategories.find(category => category.id === 'clear'), {name: '通关进度', disabled: 1});
resend('shadow', {categories: renamedCategories});
const clearSidebar = nodes.get('ArchiveV10Category_clear');
const requestsBeforeDisabled = requests.length;
activate(clearSidebar);
assert.equal(view.Inspect().category, 'clear', 'a disabled category reaches the approved fixed shell empty view');
assert.equal(visibleCards().length, 0, 'disabled categories cannot reuse stale content');
assert.equal(requests.length, requestsBeforeDisabled, 'a disabled category must not submit an invalid server request');
api.SelectCategory('shadow');
resend('shadow', {categories});

walletBalances = {u_coin: 41, shop_points: 52, shop_gold: 63};
const walletBefore = {...metrics}, walletCards = voidCards();
emit('survival_commerce_result', {ok: 1}); immediate();
assert.equal(cfg.SurvivalMenuV10.Entries().length, 0, 'An unrelated commerce result cannot recreate the removed resource strip');
noRebuildOrStyle(walletBefore, 'an unrelated commerce result cannot paint archive cards');
assert.deepEqual(voidCards(), walletCards);
assert.equal(walletRefreshes, 0, 'A commerce result cannot make the independent archive request a catalog');

api.SelectCategory('building');
let building = visibleCards()[0];
hover(building); assert.equal(tooltipText('Quantity'), 'LV0/5');
assert.equal(tooltipText('MetricCaption'), '建筑等级');
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
assert.equal(tooltipText('Quantity'), 'LV2/5', 'artifact levels are refreshed');
assert.equal(tooltipText('Effect'), '当前Lv2');
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
const approvedCountColor = descendant(visibleCards()[0], 'ArchiveV10Count').style.color;
const approvedNameColor = descendant(visibleCards()[0], 'ArchiveV10Name').style.color;
const approvedFrame = visibleCards()[0].__v10.normal.style.backgroundImage;
assert(approvedFrame.includes('archive_parchment_v1'), 'The row frame is the actual approved parchment component');
cfg.SurvivalArchiveColors.number = '#abcdef';
resend('building', {upgrade_pending: 0});
assert.equal(metrics.palettes, themeBefore, 'Legacy palette changes cannot repaint the confirmed V10 components');
assert.equal(descendant(visibleCards()[0], 'ArchiveV10Count').style.color, approvedCountColor, 'Independent V10 quantity text retains its confirmed color');
assert.equal(descendant(visibleCards()[0], 'ArchiveV10Name').style.color, approvedNameColor, 'Independent V10 name text retains its confirmed color');
assert.equal(visibleCards()[0].__v10.normal.style.backgroundImage, approvedFrame, 'A legacy theme change cannot swap the approved original frame asset');

const collectionCalls=[];cfg.SurvivalCollection={Open:id=>collectionCalls.push(id)};
for (const category of ['friend', 'ex', 'beast']) {
    api.Open();
    const beforeForward = requests.length;
    api.SelectCategory(category);
    assert(!api.IsOpen(), 'Forwarding a collection link closes the archive: ' + category);
    assert.equal(requests.length, beforeForward, 'The retired archive entry delegates its request to the collection controller: ' + category);
}
assert.deepEqual(collectionCalls,['friend','ex','beast'],'Legacy social and blessing links open their matching independent collection');
resend('beast', {pending: 1});
assert(!api.IsOpen(), 'A background blessing snapshot cannot reopen its retired archive page');
api.Open();

api.SelectCategory('fragment');
let fragment = visibleCards()[0], promotion = descendant(fragment, 'ArchivePromote');
hover(promotion);
assert(tooltipText('Effect').includes('高阶'), 'promotion help still resolves the actual target name');
activate(promotion);
const promotionRequests = requests.length; activate(promotion);
assert.equal(requests.length, promotionRequests, 'promotion requests retain their local duplicate guard');
assert.equal(requests.at(-1).name, 'survival_archive_promote');

api.SelectCategory('work');
const workCard = visibleCards()[0], beforeWork = requests.length;
assert.equal(workCard.paneltype, 'Button', 'The original clickable welfare card remains the horizontal row');
assert.equal(workCard.__v10.host.hittest, false, 'Decorative row components cannot intercept welfare clicks');
assert.equal(nodes.get('ArchiveV10Context').text, '软妹币：30', 'The actual archive snapshot supplies the welfare balance');
activate(workCard); activate(workCard);
assert.equal(requests.length, beforeWork + 1, 'Welfare row clicks retain the single submission gate');
assert.equal(requests.at(-1).name, 'survival_archive_work_upgrade');
assert.equal(requests.at(-1).payload.item_id, 'work_01');
assert.equal(nodes.get('ArchiveFooter').visible, true, 'The save acknowledgement is visible in the independent shell');
resend('work'); activate(visibleCards()[0]);
assert.equal(requests.length, beforeWork + 2, 'A rejected welfare activation can be retried from the same row');

api.SelectCategory('titles');
const beforeTitle = requests.length;
activate(visibleCards()[0]); activate(visibleCards()[0]);
assert.equal(requests.length, beforeTitle + 1, 'Title rows retain their equip double-click guard');
assert.equal(requests.at(-1).name, 'survival_archive_title_equip');
assert.equal(requests.at(-1).payload.title_id, 'title_test');
emit('survival_archive_title_result', {ok: 1});
snapshot('titles', [{...dataByCategory.titles.rows[0], equipped: 1}]);
assert.equal(visibleCards()[0].__v10.count.text, '已穿戴', 'The row displays the authoritative equipped state');
assert.equal(visibleCards()[0].__v10.track.visible, false, 'Titles do not invent numerical progress bars');
activate(visibleCards()[0]);
assert.equal(requests.at(-1).payload.title_id, '', 'Clicking the equipped title still unequips it');

assert.equal(walletRefreshes, 0, 'Upgrade, draw, promotion, filter and category updates use their existing archive snapshots');
api.SelectCategory('shadow'); api.Close();
const closed = {...metrics};
for (let revision = 101; revision <= 200; revision++) {
    snapshot('shadow', [{...rows[0], count: revision}, rows[1]], {has_pass: 1, profile_revision: revision});
}
assert.deepEqual(metrics, closed, 'closed profile updates remain data-only, including the custom void view');
assert.equal(walletRefreshes, 0, 'Closed profile updates do not request a wallet refresh');
api.Open();
assert.equal(walletRefreshes, 0, 'Reopening reads archive snapshots without requesting the removed resource strip');
assert.equal(descendant(itemCard('shadow_01'), 'ArchiveV10Count').text, '200/430', 'reopening renders the latest cache immediately');
assert.equal(cfg.SurvivalMenuV10.Entries().length, 0, 'Reopening preserves the independent shell');
api.SelectCategory('clear');
snapshot('clear', [{id: 'clear_01', name: '第一阶', count: 1, target: 1, completed: 1}]);
assert(nodes.get('ArchiveSummary').text.includes('已完成 1 / 1'), 'generic page completion remains live after leaving void');
api.SelectCategory('shadow');
assert.equal(descendant(itemCard('shadow_01'), 'ArchiveV10Count').text, '200/430', 'switching back uses the latest shadow cache');

// archive_service.enabled_categories() omits disabled CSV categories entirely.
// A complete screenshot fixture that includes `shop, disabled:1` would conceal
// the missing native ArchiveTab_shop that occurs with a real server snapshot.
const serverEnabledCategories = categories.filter(category => Number(category.disabled) !== 1);
assert(!serverEnabledCategories.some(category => category.id === 'shop'), 'The real server category list excludes the disabled shop');
resend('shadow', {categories: serverEnabledCategories});
assert.equal(nodes.get('ArchiveTab_shop'), undefined, 'The test exercises absence of a legacy native shop tab');
assert(nodes.get('ArchiveV10Category_shop'), 'The approved fixed V10 sidebar still exposes the shop category');
const shellBeforeUnavailableShop = nodes.get('ArchiveV10Canvas');
const shopRequestCount = requests.length;
activate(nodes.get('ArchiveV10Category_shop'));
assert.equal(view.Inspect().category, 'shop', 'An omitted disabled shop still switches the fixed shell to its local category view');
assert.equal(nodes.get('ArchiveV10_page_title').text, '商城道具');
assert(nodes.get('ArchiveEmpty').text.includes('未启用'), 'Disabled shop presents the explicit unavailable empty state');
assert.equal(visibleCards().length, 0, 'The local disabled shop view has no stale cards from another category');
assert.equal(requests.length, shopRequestCount, 'Selecting an omitted disabled shop submits no invalid server request');
assert.equal(nodes.get('ArchiveV10Canvas'), shellBeforeUnavailableShop, 'The unavailable category retains the same shell');
api.Close(); api.Open(); immediate();
assert.equal(walletRefreshes, 0, 'Reopening a disabled local category does not request commerce data');
assert.equal(view.Inspect().category, 'shop', 'Reopening a locally unavailable category restores its empty directory');
assert(nodes.get('ArchiveEmpty').text.includes('未启用'), 'Reopening retains the explicit unavailable state');
assert.equal(requests.length, shopRequestCount, 'Reopening the local disabled directory cannot start an invalid snapshot request or retry');
api.Refresh(true); immediate();
assert.equal(walletRefreshes, 0, 'An explicit archive refresh is independent of commerce catalog refresh');
assert.equal(requests.length, shopRequestCount, 'Explicit refresh of the disabled local directory does not request server data');
assert.equal(nodes.get('ArchiveV10Canvas'), shellBeforeUnavailableShop, 'Reopening the local directory reuses the fixed shell');
activate(nodes.get('ArchiveV10Category_shadow'));
assert.equal(view.Inspect().category, 'shadow', 'The player can return from the local empty directory');
assert.equal(descendant(itemCard('shadow_01'), 'ArchiveV10Count').text, '200/430', 'Returning restores the unchanged authoritative shadow cache');

console.log('ARCHIVE_OPEN_PROFILE_REFRESH_PASS: manifest full-source controllers, 1000 stable revisions, delta baseline, native card/sidebar reuse, live counts/ownership/pass/tooltips, independent archive without commerce resource requests, upgrade rejection and pending guards, social/blessing collection routing, promotion duplicate guard, theme, filters, tabs and 100 closed updates');
