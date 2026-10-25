const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const assert = require('node:assert/strict');
const {csv} = require('../shop_ui_12h/catalog.cjs');
const repo = path.resolve(__dirname, '../..');
const sourceRoot = path.join(repo, 'panorama/src/scripts/custom_game');
const graph = ['ui_snapshot_cache.js', 'archive_purple.js', 'archive_v10_data.js', 'archive_parchment_data.js', 'common/tooltip_dismiss.js', 'common/menu_v10.js', 'archive_v10_semantics.js', 'common/archive_tooltip.js', 'common/archive_font_v36.js', 'archive_v10.js', 'archive_180de7e38b_titles_compact_v6.js'];
const manifest = fs.readFileSync(path.join(repo, 'panorama/src/layout/custom_game/archive.xml'), 'utf8');
graph.forEach(name => assert(manifest.includes('/' + name + '"'), 'Exercise the active production graph: ' + name));
const sources = Object.fromEntries(graph.map(name => [name, fs.readFileSync(path.join(sourceRoot, name), 'utf8')]));
const categories = csv(path.join(repo, 'data/csv/存档系统/archive_categories.csv')).map(row => ({id: row.category_id, name: row.display_name, renderer: row.renderer, disabled: row.enabled === '1' ? 0 : 1}));
const nodes = new Map(), listeners = [], timers = [], requests = [], allPanels = [];
let root, time = 0, serial = 0;
class Panel {
    constructor(type, parent, id = '') {
        this.paneltype = type; this.parent = parent; this.id = id; this.classes = new Set(); this.children = []; this.events = {};
        this.visible = true; this.enabled = true; this.style = {}; this.text = ''; allPanels.push(this);
        if (parent) { parent.check(); parent.children.push(this); }
        if (id) nodes.set(id, this);
    }
    check() { assert(!this.deleted, 'Accessed retired native panel: ' + this.id); }
    IsValid() { return !this.deleted; }
    AddClass(value) { this.check(); this.classes.add(value); }
    RemoveClass(value) { this.check(); this.classes.delete(value); }
    SetHasClass(value, enabled) { enabled ? this.AddClass(value) : this.RemoveClass(value); }
    BHasClass(value) { this.check(); return this.classes.has(value); }
    Children() { this.check(); return this.children; }
    GetParent() { this.check(); return this.parent; }
    FindChildTraverse(id) { this.check(); if (this.id === id) return this; for (const child of this.children) { const found = child.FindChildTraverse(id); if (found) return found; } return null; }
    SetParent(parent) { this.check(); parent.check(); if (this.parent) this.parent.children = this.parent.children.filter(child => child !== this); this.parent = parent; parent.children.push(this); }
    MoveChildBefore(child, before) { this.check(); this.children = this.children.filter(value => value !== child); this.children.splice(Math.max(0, this.children.indexOf(before)), 0, child); }
    RemoveAndDeleteChildren() { this.check(); this.children.slice().forEach(child => child.DeleteAsync()); }
    DeleteAsync() { if (this.deleted) return; this.children.slice().forEach(child => child.DeleteAsync()); this.deleted = true; if (this.parent) this.parent.children = this.parent.children.filter(child => child !== this); if (nodes.get(this.id) === this) nodes.delete(this.id); }
    SetPanelEvent(name, callback) { this.check(); this.events[name] = callback; }
    SetImage(value) { this.check(); this.image = value; }
    SetScaling(value) { this.check(); this.scaling = value; }
    ScrollToTop() { this.check(); }
    GetPositionWithinWindow() { this.check(); const a = String(this.style.position || '0px 0px 0px').split(/\s+/).map(parseFloat), b = this.parent ? this.parent.GetPositionWithinWindow() : {x: 0, y: 0}; return {x: (a[0] || 0) + b.x, y: (a[1] || 0) + b.y}; }
    get actualuiscale_x() { this.check(); return 1; }
    get actualuiscale_y() { this.check(); return 1; }
    get actuallayoutwidth() { this.check(); return parseFloat(this.style.width) || 1920; }
    get actuallayoutheight() { this.check(); return this.layoutHeightOverride === undefined ? parseFloat(this.style.height) || 160 : this.layoutHeightOverride; }
}
function fixture(keepRoot) {
    if (!keepRoot) root = new Panel('Panel', null, 'ArchiveRoot');
    const win = new Panel('Panel', root, 'ArchiveWindow');
    for (const id of ['ArchiveHeader', 'ArchiveTitle', 'ArchiveClose', 'ArchiveContent', 'ArchiveTabs', 'ArchiveGrid', 'ArchiveFilters', 'ArchiveFilter_all', 'ArchiveFilter_unlocked', 'ArchiveFilter_locked', 'ArchiveFilterAllLabel', 'ArchiveTooltip', 'ArchiveTooltipStateIcon', 'ArchiveDraw', 'ArchiveTickets', 'ArchiveDrawResult', 'ArchiveDrawBar', 'ArchiveFaith', 'ArchiveCurrencySource', 'ArchiveEmpty', 'ArchivePageTitle', 'ArchiveSummary', 'ArchiveContext', 'ArchiveHint', 'ArchiveStatus', 'ArchiveFooter', 'ArchiveBody', 'ArchivePageHeader', 'ArchiveTooltipBody', 'ArchiveTooltipName', 'ArchiveTooltipStateText', 'ArchiveTooltipProgress', 'ArchiveTooltipCondition', 'ArchiveTooltipProgressRow']) new Panel('Panel', win, id);
    new Panel('Panel', root, 'ArchiveScrim'); new Panel('Panel', root, 'EndlessStatus');
}
fixture();
const cfg = {
    SurvivalArchiveColors: {number: '#ffd800'}, ArchiveHandoffAssets: {'icon_check_light.png': 'check', 'icon_lock_light.png': 'lock'},
    SurvivalCommerceWallet: {GetCatalog: () => ({balances: {u_coin: 2, shop_points: 3, shop_gold: 4}})},
    SurvivalUI: {
        Lifecycle() { let active=true,epoch=0; return {Later(delay,callback) { const expected=epoch; return context.$.Schedule(delay,()=>{if(active&&expected===epoch)callback();}); },Cancel(){epoch++;},Dispose(){active=false;epoch++;}}; },ModalShell: {Adopt: () => ({Open() {}, Close() {}, Dispose() {}})}, NavToggle: {Adopt() {}}, ActionButton: {Adopt() {}}, Tooltip: {Adopt() {}}, Fit() {}},
    ArchiveHandoff: {
        Init() {}, Hide() {}, HideCardText() {}, NavIcon() {}, Card() {}, ApplyPalette() {}, Show() {}, ShowEffectOnly() {},
        Observe(value) { this.snapshot = value; }, Unlocked: (item, category) => cfg.ArchiveV10Semantics.State(item, category),
        Progress(item) { return String(item.count === undefined ? '—' : item.count) + ' / ' + String(item.target === undefined ? '—' : item.target); },
        Icon(parent) { const art = new Panel('Panel', parent); art.AddClass('ArchiveArt'); const image = new Panel('Image', art); image.AddClass('ArchiveRewardIcon'); }
    }
};
const context = vm.createContext({
    $: {GetContextPanel: () => root, CreatePanel: (type, parent, id) => new Panel(type, parent, id), Msg() {}, RegisterEventHandler() {}, DispatchEvent() {},
        Schedule(delay, callback) { const timer = {id: ++serial, at: time + delay, delay, callback}; timers.push(timer); return timer; }, CancelScheduled(timer) { timer.cancelled = true; }},
    CustomNetTables:{GetTableValue(){return null;}}, GameUI: {CustomUIConfig: () => cfg}, Game: {IsInToolsMode: () => false, GetLocalPlayerID: () => 0},
    GameEvents: {Subscribe(name, callback) { const listener = {name, callback}; listeners.push(listener); return listener; }, Unsubscribe(listener) { listener.cancelled = true; }, SendCustomGameEventToServer(name, payload) { requests.push({name, payload}); }}
});
function load(names = graph) { for (const name of names) vm.runInContext(sources[name], context, {filename: name}); return cfg.SurvivalArchive; }
function emit(name, data) { for (const listener of listeners.slice()) if (!listener.cancelled && listener.name === name) listener.callback(data); }
function advance(seconds) { const target = time + seconds; for (let i = 0; i < 1000; i++) { const timer = timers.filter(row => !row.cancelled && !row.ran && row.at <= target).sort((a, b) => a.at - b.at)[0]; if (!timer) { time = target; return; } time = timer.at; timer.ran = true; timer.callback(); } throw Error('Unexpected continuing timer loop'); }
function snapshot(category, sequence, rows, extra = {}) { emit('survival_archive_snapshot', {ok: 1, category_id: category, sequence, chunks: 1, chunk: 1, categories, rows, pending: 0, ...extra}); advance(0); }
function cards() { return nodes.get('ArchiveGrid').Children().filter(card => card.BHasClass('ArchiveCard') && card.visible); }
function canvases() { return allPanels.filter(panel => panel.IsValid() && panel.id === 'ArchiveV10Canvas'); }
function native(panel, cls) { if (panel.BHasClass(cls)) return panel; for (const child of panel.Children()) { const found = native(child, cls); if (found) return found; } return null; }
function liveSubscriptions() { return listeners.filter(listener => !listener.cancelled).map(listener => listener.name).sort(); }
const sidebarDelta = 326 / 3, compactWidth = 1200 - sidebarDelta;
function near(actual, expected, message, tolerance = 0.001) { assert(Math.abs(actual - expected) <= tolerance, message + ': ' + actual + ' ≈ ' + expected); }
function bounds(panel) { const at = panel.GetPositionWithinWindow(), width = parseFloat(panel.style.width), height = parseFloat(panel.style.height); return {...at, width, height, right: at.x + width, bottom: at.y + height}; }
function contains(parent, child) {
    const outer = bounds(parent), inner = bounds(child);
    assert(inner.x >= outer.x - .51 && inner.y >= outer.y - .51 && inner.right <= outer.right + .51 && inner.bottom <= outer.bottom + .51,
        (child.id || child.paneltype) + ' stays inside ' + parent.id);
}
function selectedCategory(expected) {
    const selected = nodes.get('ArchiveV10Sidebar').Children().filter(panel => panel.BHasClass('ArchiveV10Selected'));
    assert.deepEqual(selected.map(panel => panel.id), ['ArchiveV10Category_' + expected], 'Exactly the current category keeps its selected state');
}
function compactSidebar() {
    near(parseFloat(nodes.get('ArchiveWindow').style.width), compactWidth, 'Window gives back the removed sidebar width');
    near(parseFloat(nodes.get('ArchiveV10Canvas').style.width), compactWidth, 'Canvas matches the compact window');
    const shell = nodes.get('ArchiveV10Shell_Sidebar');
    near(parseFloat(shell.style.width), 326 * 2 / 3, 'Stone sidebar is two thirds of its former width');
    for (const [id, originalWidth] of [['ArchiveV10OverviewTitle', 285], ['ArchiveV10Overview', 292],
        ['ArchiveV10FilterToggle', 290], ['ArchiveV10SidebarStrip', 310],
        ['ArchiveV10Sidebar', 302], ['ArchiveV10FilterMenu', 290]]) {
        const panel = nodes.get(id);
        near(parseFloat(panel.style.width), originalWidth - sidebarDelta, id + ' uses the compact width');
        contains(shell, panel);
    }
    contains(nodes.get('ArchiveV10FilterToggle'), nodes.get('ArchiveV10FilterText'));
    for (const id of ['ArchiveV10Search', 'ArchiveV10SearchHint', 'ArchiveV10SearchEmpty']) assert(!nodes.has(id), 'Removed category search never creates a panel');
    assert.equal(bounds(nodes.get('ArchiveV10SidebarStrip')).y, 234, 'Category heading takes the former search position');
    assert.equal(bounds(nodes.get('ArchiveV10Sidebar')).y, 270, 'Category list moves up with its heading');
    assert.equal(bounds(nodes.get('ArchiveV10Sidebar')).bottom, 845, 'The taller category list keeps its bottom edge');
    for (const mode of ['all', 'unlocked', 'locked']) {
        const option = nodes.get('ArchiveV10Filter_' + mode);
        near(parseFloat(option.style.width), 288 - sidebarDelta, 'Dropdown option width');
        contains(nodes.get('ArchiveV10FilterMenu'), option);
        option.Children().forEach(child => contains(option, child));
    }
    for (const button of nodes.get('ArchiveV10Sidebar').Children()) {
        near(parseFloat(button.style.width), 285 - sidebarDelta, 'Category button width');
        // The complete category list scrolls vertically after purchased goods
        // was added; each row still stays within the compact horizontal rail.
        const rail = bounds(nodes.get('ArchiveV10Sidebar')), row = bounds(button);
        assert(row.x >= rail.x - .51 && row.right <= rail.right + .51, 'Category stays within sidebar width');
        const name = button.Children().find(child => child.paneltype === 'Label');
        const badge = button.Children().find(child => child.BHasClass('ArchiveParchmentCategoryBadge'));
        const icon = badge.Children().find(child => child.BHasClass('ArchiveV10Icon'));
        near(parseFloat(name.style.width), 231 - sidebarDelta, 'Category name shrinks without changing its font');
        assert.equal(name.style.fontSize, '21px');
        assert.equal(icon.style.width, '28px'); assert.equal(icon.style.height, '28px');
        badge.Children().forEach(child => contains(badge, child));
        button.Children().forEach(child => contains(button, child));
    }
    near(bounds(nodes.get('ArchiveV10Shell_Content')).x, 356 - sidebarDelta, 'Content follows the compact sidebar', .51);
    assert.equal(nodes.get('ArchiveV10Shell_Content').style.width, '808px', 'Right content keeps its width');
    near(bounds(nodes.get('ArchiveV10GridHost')).x, 385 - sidebarDelta, 'Grid shifts left with the content', .51);
    assert.equal(nodes.get('ArchiveGrid').style.width, '767px', 'The row viewport keeps its authored width');
    contains(nodes.get('ArchiveV10Canvas'), nodes.get('ArchiveV10Shell_Content'));
}
const shadowRows = [{id: 'shadow_01', count: 3, target: 430, description: '真实测试效果'}, {id: 'shadow_02', count: 0, target: 430}, {id: 'shadow_03', count: 3, count_known: 0, target: 430}];
const api = load();
snapshot('clear', 1, [{id: 'clear_01', name: '通关', count: 2, target: 1, completed: 1}]);
snapshot('shadow', 2, shadowRows);
api.Open(); api.SelectCategory('shadow'); advance(.1);
assert.equal(canvases().length, 1, 'Exactly one archive shell is constructed');
assert.equal(cfg.SurvivalMenuV10.Entries().length, 0, 'The independent archive never adopts the global menu or its resource strip');
assert.equal(cfg.SurvivalArchiveV10.Inspect().categories.length, 16, 'Archive retains its categories including purchased goods while social and blessing pools use the independent collection window');
for (const category of ['ex', 'friend', 'wife', 'beast']) {
    assert(!nodes.has('ArchiveV10Category_' + category), 'Migrated collection pool is absent from the fixed archive sidebar: ' + category);
    assert(!nodes.has('ArchiveTab_' + category), 'Migrated collection pool is absent from legacy archive navigation: ' + category);
}
compactSidebar(); selectedCategory('shadow');
assert.equal(nodes.get('ArchiveWindow').style.height, '900px');
assert.equal(nodes.get('ArchiveV10Shell_Background').style.backgroundColor, 'transparent', 'PNG edge alpha is never flattened by a CSS backing rectangle');
assert.equal(nodes.get('ArchiveV10CategoryIcon').image, 'file://{images}/custom_game/archive_polish_v2/nav/shadow.svg', 'Header uses the centered vector also used by its category');
assert.equal(nodes.get('ArchiveFooter').visible, true, 'Gameplay save/rejection feedback remains visible');
assert.equal(nodes.get('ArchiveStatus').style.marginTop, '0px', 'The retained status label cannot inherit the old 12px top margin');
near(bounds(nodes.get('ArchiveFooter')).x, 390 - sidebarDelta, 'Footer shifts with the unchanged content', .51);
assert.equal(bounds(nodes.get('ArchiveFooter')).y, 815);
assert(parseFloat(nodes.get('ArchiveFooter').style.position.split(' ')[1]) + parseFloat(nodes.get('ArchiveFooter').style.height) < 840, 'The complete footer stays above the textured bottom edge and its transparent margin');
nodes.get('ArchiveV10FilterToggle').events.onactivate();
assert.equal(nodes.get('ArchiveV10FilterMenu').visible, true);
nodes.get('ArchiveV10Filter_all').events.onactivate();
assert.equal(nodes.get('ArchiveV10FilterMenu').visible, false);
selectedCategory('shadow');
assert.equal(nodes.get('ArchiveV10Sidebar').Children().filter(node => node.visible).length, 16, 'Every category remains available without search');
selectedCategory('shadow'); compactSidebar();
assert.equal(cards()[0].style.width, '745px', 'The controller cards are complete horizontal rows');
assert.equal(cards()[1].style.position, '0px 82px 0px', 'Rows occupy a single vertical column');
assert.equal(cards().find(card => card.__archiveItem.id === 'shadow_03').__v10.track.visible, false, 'Unknown inventory is never painted as zero progress');
assert.equal(cards().find(card => card.__archiveItem.id === 'shadow_02').__v10.track.visible, true, 'Known zero keeps the empty progress track');
assert.equal(cards().find(card => card.__archiveItem.id === 'shadow_02').__v10.fill.visible, false);
const canvas = canvases()[0], rails = canvas.Children().filter(panel => panel.id.startsWith('ArchiveV10Shell_'));
const shellBounds = JSON.stringify(canvas.style);
const shadowCard = cards().find(card => card.__archiveItem.id === 'shadow_01');
const oldHost = shadowCard.__v10.host;
const approvedCellGeometry = JSON.stringify(shadowCard.style);
const approvedHostGeometry = JSON.stringify(oldHost.style);
cfg.SurvivalArchivePurple.Decorate(shadowCard);
cfg.SurvivalArchivePurple.Apply();
cfg.ArchiveHandoff.Hide();
assert.equal(JSON.stringify(shadowCard.style), approvedCellGeometry, 'Legacy card decoration/tooltip hiding cannot overwrite the approved V10 cell geometry');
assert.equal(JSON.stringify(oldHost.style), approvedHostGeometry, 'Legacy decoration cannot resize or crop the V10 icon host');
assert.equal(JSON.stringify(canvas.style), shellBounds, 'Legacy page palette cannot change the approved fixed shell');
api.Filter('unlocked');
assert.deepEqual(cards().map(card => card.__archiveItem.id), ['shadow_01'], 'Unknown ownership is excluded from owned filtering');
selectedCategory('shadow'); assert(nodes.get('ArchiveV10Filter_unlocked').BHasClass('ArchiveV10Selected'));
api.Filter('locked');
assert(cards().every(card => card.__archiveItem.count_known === 1 && card.__archiveItem.count === 0), 'Unknown inventory never enters locked filtering');
selectedCategory('shadow'); assert(nodes.get('ArchiveV10Filter_locked').BHasClass('ArchiveV10Selected'));
assert(!nodes.get('ArchiveV10Filter_unlocked').BHasClass('ArchiveV10Selected'));
api.Filter('all');
selectedCategory('shadow'); assert(nodes.get('ArchiveV10Filter_all').BHasClass('ArchiveV10Selected'));
nodes.get('ArchiveV10Category_clear').events.onactivate();
selectedCategory('clear'); assert(!nodes.get('ArchiveV10Category_shadow').BHasClass('ArchiveV10Selected'));
assert.equal(canvases()[0], canvas, 'Category switching retains native shell identity');
assert.deepEqual(canvas.Children().filter(panel => panel.id.startsWith('ArchiveV10Shell_')), rails, 'Background, navigation and metal rails remain the same native components');
assert.equal(JSON.stringify(canvas.style), shellBounds, 'Category switching does not change shell geometry');
api.SelectCategory('shadow');
selectedCategory('shadow'); assert(!nodes.get('ArchiveV10Category_clear').BHasClass('ArchiveV10Selected'));
const liveCard = cards().find(card => card.__archiveItem.id === 'shadow_01');
// The real legacy controller deletes its decorative children on a fingerprint
// change. V10 must recognize that cached .__v10 references have become invalid.
snapshot('shadow', 3, [{...shadowRows[0], icon_style: 'crystal'}, shadowRows[1], shadowRows[2]]);
assert.equal(cards().find(card => card.__archiveItem.id === 'shadow_01'), liveCard, 'Gameplay card identity survives visual rebuilding');
assert.equal(oldHost.IsValid(), false, 'Obsolete V10 children are disposed');
assert.equal(liveCard.__v10.host.IsValid(), true, 'A deleted cached visual host is rebuilt');
assert.equal(native(liveCard, 'ArchiveV10Count').text, '3/430');
// Native labels may report zero height in the first display frame. Later layout
// must resize the whole background and constrain long text in a separate viewport.
cfg.ArchiveHandoff.Show(liveCard.__archiveItem, 'shadow', liveCard);
const tooltipBody = nodes.get('ArchiveV10TooltipBody');
tooltipBody.Children().forEach(child => { child.layoutHeightOverride = 0; });
advance(.05);
assert.equal(nodes.get('ArchiveV10Tooltip').style.height, '246px');
nodes.get('ArchiveV10TooltipEffect').layoutHeightOverride = 1100;
advance(.4);
assert.equal(nodes.get('ArchiveV10Tooltip').style.height, '778px', 'Delayed native text metrics grow the background to the long-text cap');
assert.equal(nodes.get('ArchiveV10TooltipViewport').style.height, '689px', 'The viewport keeps long text inside the background');
assert.equal(tooltipBody.GetParent(), nodes.get('ArchiveV10TooltipViewport'));
assert.equal(tooltipBody.style.height, 'fit-children', 'Natural text measurement is separate from the clipped scrolling viewport');
cfg.ArchiveHandoff.Hide();
const subscriptionsBefore = liveSubscriptions();
api.Close(); assert.equal(canvas.visible, false);
api.Open(); advance(.1);
assert.equal(canvases().length, 1, 'Reopening does not append another canvas');
assert.equal(canvases()[0], canvas, 'Reopening preserves the existing fixed shell');
assert.deepEqual(liveSubscriptions(), subscriptionsBefore, 'Reopening does not register repeated handlers');
selectedCategory('shadow'); compactSidebar();
const oldApi = api, oldView = cfg.SurvivalArchiveV10, oldSidebar = nodes.get('ArchiveV10Category_clear');
const retiredFilter = nodes.get('ArchiveV10Filter_locked').events.onactivate;
const retiredClose = nodes.get('ArchiveV10Close').events.onactivate;
const oldSnapshot = listeners.find(listener => !listener.cancelled && listener.name === 'survival_archive_snapshot').callback;
const retiredHover = liveCard.events.onmouseover, retiredSidebar = oldSidebar.events.onactivate;
const retainedGrid = nodes.get('ArchiveGrid');
load(['archive_180de7e38b_titles_compact_v6.js']);
assert.equal(oldApi.IsOpen(), false, 'Reload disposes the preceding controller');
assert.equal(nodes.get('ArchiveGrid'), retainedGrid, 'Controller reload retains the actual native grid');
assert.equal(retainedGrid.style.width, '1000px', 'Legacy initialization really overwrites the retained grid between V10 views');
cfg.SurvivalArchive.Open(); snapshot('clear', 20, [{id: 'fresh', name: '新记录', count: 1, target: 1, completed: 1}]);
selectedCategory('clear');
cfg.SurvivalArchive.SelectCategory('shadow'); snapshot('shadow', 21, shadowRows);
selectedCategory('shadow'); compactSidebar();
assert.equal(retainedGrid.style.position, '0px 0px 0px', 'V10 restores actual grid origin after legacy initialization');
assert.equal(retainedGrid.style.width, '767px', 'Stale visual cache cannot resize the retained row viewport');
assert.equal(retainedGrid.style.height, '577px', 'The independent archive restores the retained viewport height');
assert.equal(retainedGrid.style.flowChildren, 'none', 'V10 restores its positioned grid after legacy right-wrap layout');
assert.equal(canvases().length, 1, 'Controller-only reload rebuilds one working shell');
assert.deepEqual(liveSubscriptions(), subscriptionsBefore, 'Controller-only reload replaces handlers without leaks');
const activeView = cfg.SurvivalArchiveV10, activeCanvas = canvases()[0], requestsBefore = requests.length;
oldSnapshot({ok: 1, category_id: 'shadow', sequence: 999, chunks: 1, chunk: 1, categories, rows: []});
assert.doesNotThrow(() => { oldApi.Refresh(true); retiredHover(); retiredSidebar(); retiredFilter(); retiredClose(); advance(.1); }, 'Retired controls must ignore queued callbacks without accessing replacement/deleted nodes');
assert.equal(requests.length, requestsBefore, 'Retired APIs/events/timers cannot emit requests');
assert.equal(activeView.Inspect().category, 'shadow', 'A retired sidebar callback cannot switch the replacement controller');
assert.equal(cfg.SurvivalArchive.IsOpen(), true, 'A retired close callback cannot close the replacement controller');
assert.equal(canvases()[0], activeCanvas, 'Dead callbacks cannot recreate another shell');
assert.equal(native(cards().find(card => card.__archiveItem.id === 'shadow_01'), 'ArchiveV10Count').text, '3/430', 'A retired snapshot cannot replace active data');

// After explicit disposal, queued callbacks and public APIs must be quiescent.
const currentApi = cfg.SurvivalArchive, currentView = cfg.SurvivalArchiveV10;
currentApi.Dispose(); currentApi.Dispose();
assert.equal(canvases().length, 0);
assert.equal(liveSubscriptions().length, 0, 'All controller and shell listeners are unsubscribed');
const disposedRequests = requests.length;
assert.doesNotThrow(() => { currentView.Render({ok: 1, rows: shadowRows}, 'shadow', 'all', categories); currentView.Fit(); currentView.Leave(); advance(5); });
assert.equal(canvases().length, 0, 'Disposed renderer cannot resurrect its former shell');
assert.equal(requests.length, disposedRequests, 'No retired retry loop continues after disposal');

load(); cfg.SurvivalArchive.Open(); snapshot('clear', 30, [{id: 'reload', name: '重载', count: 0, target: 1, completed: 0}]);
selectedCategory('clear'); compactSidebar();
const childApi = cfg.SurvivalArchive, childHandler = listeners.find(listener => !listener.cancelled && listener.name === 'survival_archive_snapshot').callback;
root.RemoveAndDeleteChildren(); fixture(true);
const beforeChildReload = requests.length;
assert.doesNotThrow(() => { childHandler({ok: 1, category_id: 'clear', sequence: 999, rows: []}); childApi.Refresh(true); advance(.1); });
assert.equal(requests.length, beforeChildReload, 'A surviving root cannot revive its deleted lifetime marker');
load(); cfg.SurvivalArchive.Open(); snapshot('clear', 40, [{id: 'replacement', name: '替换', count: 0, target: 1, completed: 0}]);
assert.equal(cards().length, 1, 'Replacing children and reloading the active graph restores real data');
assert.equal(canvases().length, 1);
selectedCategory('clear'); compactSidebar();
const pointsRows = [
    {id: 'points_unique_owned', name: '唯一已解锁', count: 1, max_owned: 1, duplicate_points: 400, duplicate_currency: 'shop_points'},
    {id: 'points_unique_locked', name: '唯一未解锁', count: 0, target: 1},
    {id: 'points_unique_unknown', name: '唯一待同步', count: 7, count_known: 0, max_owned: 1},
    {id: 'points_unique_legacy', name: '历史重复', count: 7, target: 1},
    {id: 'daily_growth_gem', name: '成长宝石', description: '英雄每秒攻击+1', count: 3, target: 999999, duplicate_points: 25, duplicate_currency: 'shop_points'},
    {id: 'points_uncapped', name: '旧版无上限', count: 4},
    {id: 'daily_health_gem', name: '生命宝石', count: 0, target: 999999},
    {id: 'daily_regen_shard', name: '回血碎片', count: 9, target: 999999, count_known: 0}
].map(row => Object.freeze(row));
const pointsBefore = JSON.stringify(pointsRows), pointsApi = cfg.SurvivalArchive;
pointsApi.SelectCategory('points'); snapshot('points', 41, pointsRows);
selectedCategory('points');
assert(nodes.get('ArchiveV10Overview').text.startsWith('已解锁 4 / 8 项'), 'All points entries count unique unlocks while unknown data remains pending');
assert.equal(cfg.SurvivalArchiveV10.Inspect().layout, 'points_grid');
for (const id of pointsRows.map(row => row.id)) {
    const row = cards().find(card => card.__archiveItem.id === id);
    assert.equal(row.__v10.count.text, '');
    assert.equal(row.__v10.track, undefined, 'Unique points use the goods grid without a completion track');
    assert.equal(row.__v10.countHost.visible, false, 'Points show no ownership text or quantity badge');
    assert.equal(row.__v10.name.style.textAlign, 'center');
    assert(row.BHasClass('ArchiveCommerceCell'), 'Points reuse the commerce icon/name renderer');
    assert.equal(row.style.width, '104px'); assert.equal(row.style.height, '112px');
    assert.equal(row.__v10.normal.style.width, '80px'); assert.equal(row.__v10.normal.style.height, '80px');
    contains(row, row.__v10.countHost); contains(row.__v10.countHost, row.__v10.count);
}
assert.equal(cards().find(card => card.__archiveItem.id === 'points_unique_legacy').__archiveItem.count, 1, 'A legacy excess count is represented by one entitlement in the view');
assert.equal(cards().find(card => card.__archiveItem.id === 'points_unique_unknown').__archiveItem.count, undefined, 'An unknown inventory never becomes a known one or zero');
const dailyPointsCard = cards().find(card => card.__archiveItem.id === 'daily_growth_gem');
assert.equal(dailyPointsCard.__v10.count.text, '', 'The legacy daily_growth_gem 3/999999 shows no quantity or status text');
assert.equal(dailyPointsCard.__archiveItem.count, 1);
assert.equal(dailyPointsCard.__archiveItem.max_owned, 1);
assert.equal(dailyPointsCard.__archiveItem.target, 1);
assert.equal(dailyPointsCard.__v10.countHost.visible, false, 'Daily points use icon brightness alone');
assert.equal(cards().find(card => card.__archiveItem.id === 'points_uncapped').__v10.count.text, '');
const pointCard = cards().find(card => card.__archiveItem.id === 'points_unique_owned');
cfg.ArchiveHandoff.Show(pointCard.__archiveItem, 'points', pointCard); advance(0);
assert.equal(nodes.get('ArchiveV10TooltipState').text, '积分道具');
assert.equal(nodes.get('ArchiveV10TooltipMetricCaption').text, '');
assert.equal(nodes.get('ArchiveV10TooltipQuantity').text, '');
assert.equal(nodes.get('ArchiveV10TooltipMetric').visible, false);
assert(nodes.get('ArchiveV10TooltipCondition').text.includes('唯一持有 · 重复获得转化为 400 商城积分'));
cfg.ArchiveHandoff.Show(dailyPointsCard.__archiveItem, 'points', dailyPointsCard); advance(0);
assert.equal(nodes.get('ArchiveV10TooltipTitle').text, '成长宝石');
assert.equal(nodes.get('ArchiveV10TooltipState').text, '积分道具');
assert.equal(nodes.get('ArchiveV10TooltipMetricCaption').text, '');
assert.equal(nodes.get('ArchiveV10TooltipQuantity').text, '');
assert.equal(nodes.get('ArchiveV10TooltipMetric').visible, false);
assert.equal(nodes.get('ArchiveV10TooltipEffect').text, '英雄每秒攻击+1');
assert(nodes.get('ArchiveV10TooltipCondition').text.includes('唯一持有 · 重复获得转化为 25 商城积分'));
assert(!['State','Quantity','Condition'].map(role => nodes.get('ArchiveV10Tooltip'+role).text).join('\n').includes('999999'), 'Legacy holding caps never leak into the daily item tooltip');
pointsApi.Filter('unlocked');
assert.equal(nodes.get('ArchiveV10FilterText').text, '已解锁');
assert.deepEqual(cards().map(card => card.__archiveItem.id), ['points_unique_owned', 'points_unique_legacy', 'daily_growth_gem', 'points_uncapped']);
pointsApi.Filter('locked');
assert.equal(nodes.get('ArchiveV10FilterText').text, '未解锁');
assert.deepEqual(cards().map(card => card.__archiveItem.id), ['points_unique_locked','daily_health_gem'], 'Unknown points and daily inventory never appear as locked');
assert.equal(JSON.stringify(pointsRows), pointsBefore, 'Rendering and filtering only normalize a view copy, leaving authoritative rows intact');
const lockedBeforeUpdate = cards().find(card => card.__archiveItem.id === 'points_unique_locked');
const dailyLockedBeforeUpdate = cards().find(card => card.__archiveItem.id === 'daily_health_gem');
snapshot('points', 42, pointsRows.map(row => ['points_unique_locked','daily_health_gem'].includes(row.id) ? {...row, count: 1, unlocked: 1} : row.id === 'daily_growth_gem' ? {...row, count: 9} : row));
assert.equal(cards().length, 0, 'A receipt removes both newly unlocked item types from the active locked filter immediately');
pointsApi.Filter('unlocked');
const unlockedAfterUpdate = cards().find(card => card.__archiveItem.id === 'points_unique_locked');
assert.equal(unlockedAfterUpdate, lockedBeforeUpdate, 'Unlocking updates the retained native item card');
assert.equal(unlockedAfterUpdate.__v10.count.text, '', 'A successful update lights the icon without restoring a status label');
assert.equal(unlockedAfterUpdate.__v10.countHost.visible, false);
assert(unlockedAfterUpdate.BHasClass('ArchiveCommerceOwned'));
assert.equal(unlockedAfterUpdate.__v10.art.style.brightness, '1');
const dailyUnlockedAfterUpdate = cards().find(card => card.__archiveItem.id === 'daily_health_gem');
assert.equal(dailyUnlockedAfterUpdate, dailyLockedBeforeUpdate, 'A daily receipt reuses the retained native item card');
assert.equal(dailyUnlockedAfterUpdate.__v10.count.text, '');
assert.equal(dailyUnlockedAfterUpdate.__v10.countHost.visible, false);
assert.equal(dailyUnlockedAfterUpdate.__archiveItem.count, 1);
assert(dailyUnlockedAfterUpdate.BHasClass('ArchiveCommerceOwned'));
assert.equal(cards().find(card => card.__archiveItem.id === 'daily_growth_gem'), dailyPointsCard, 'Repeated daily receipt data does not replace the card');
assert.equal(dailyPointsCard.__archiveItem.count, 1, 'A legacy duplicate count remains one visual item after refresh');
assert.equal(dailyPointsCard.__v10.count.text, '');
pointsApi.Filter('all');
const pointsCatalog = csv(path.join(repo, 'data/csv/抽奖系统/lottery_item_definitions.csv'))
    .filter(row => row.enabled === '1' && row.item_type === '积分道具')
    .map((row, index) => ({id: row.item_id, name: row.display_name, icon: row.icon, icon_type: row.icon_type,
        count: index === 0 ? 1 : 0, max_owned: Number(row.max_owned)}));
snapshot('points', 43, pointsCatalog);
assert.equal(cards().length, pointsCatalog.length, 'The entire configured points catalog remains scrollable');
assert(pointsCatalog.length > 90, 'Exercise the complete production catalog rather than a preview-size fixture');
cards().forEach((card, index) => {
    assert.equal(card.style.position, `${index % 7 * 106}px ${Math.floor(index / 7) * 116}px 0px`, 'Points reuse the compact goods grid after removing the status line');
    contains(card, card.__v10.normal); contains(card, card.__v10.name); contains(card, card.__v10.countHost);
});
assert(parseFloat(cards().at(-1).style.position.split(' ')[1]) > parseFloat(nodes.get('ArchiveGrid').style.height), 'Configured items continue below the visible viewport');
// The active production grid, tooltip and refresh agree on actual stack counts.
for (const [index,count] of [0,1,2,1501].entries()) {
    const zongzi=Math.min(count,150),live=Object.freeze([
        Object.freeze({id:'lottery_ember_of_legacy',name:'薪火余烬',count,max_owned:0,source_kind:'benefit'}),
        Object.freeze({id:'welfare_zongzi',name:'粽子',count:zongzi,max_owned:150,source_kind:'benefit'}),
        Object.freeze({id:'daily_growth_gem',name:'成长宝石',count:3,target:999999})
    ]),before=JSON.stringify(live);
    snapshot('points',44+index,live);
    const ember=cards().find(card=>card.__archiveItem.id==='lottery_ember_of_legacy');
    const rice=cards().find(card=>card.__archiveItem.id==='welfare_zongzi');
    const unique=cards().find(card=>card.__archiveItem.id==='daily_growth_gem');
    assert.equal(ember.__archiveItem.count,count);assert.equal(ember.__v10.count.text,String(count));assert(ember.__v10.countHost.visible);
    assert.equal(rice.__v10.count.text,zongzi+'/150');assert(rice.__v10.countHost.visible);
    assert.equal(unique.__v10.count.text,'');assert.equal(unique.__v10.countHost.visible,false);
    cfg.ArchiveHandoff.Show(ember.__archiveItem,'points',ember);advance(0);
    assert.equal(nodes.get('ArchiveV10TooltipQuantity').text,String(count));assert(nodes.get('ArchiveV10TooltipMetric').visible);
    assert(nodes.get('ArchiveV10TooltipCondition').text.includes('无持有上限'));
    assert(!nodes.get('ArchiveV10TooltipCondition').text.includes('唯一持有'));
    cfg.ArchiveHandoff.Show(rice.__archiveItem,'points',rice);advance(0);
    assert.equal(nodes.get('ArchiveV10TooltipQuantity').text,zongzi+'/150');
    assert(nodes.get('ArchiveV10TooltipCondition').text.includes('上限 150'));
    assert(nodes.get('ArchiveV10Context').text.includes('可叠加道具按各自规则累计'));
    assert(!nodes.get('ArchiveStatus').text.includes('自动解锁'));
    assert.equal(JSON.stringify(live),before,'Grid/tooltip/refresh never edits live inventory');
}
// Switching away keeps the existing purchased-goods geometry and labels.
pointsApi.SelectCategory('commerce_goods'); snapshot('commerce_goods', 48, [
    {id: 'goods_unique', name: '商城唯一商品', count: 1, max_owned: 1},
    {id: 'goods_locked', name: '商城未拥有', count: 0, max_owned: 1}
]);
assert.equal(cfg.SurvivalArchiveV10.Inspect().layout, 'commerce_goods_grid');
assert.equal(cards()[0].style.height, '112px'); assert.equal(cards()[1].style.position, '106px 0px 0px');
assert.equal(cards()[0].__v10.countHost.visible, false, 'Purchased unique goods keep their existing uncluttered cell');
assert.equal(JSON.stringify(pointsRows), pointsBefore, 'Rendering and filtering never clamp historical counts or alter authoritative rows');
// Monthly copy is applied after authoritative business rendering, on every refresh.
for (const [category, note] of Object.entries({shadow:'月卡玩家掉落+1',map_level:'月卡玩家双倍在线时长',work:'月卡玩家双倍效果',fragment:'每日上限20个，月卡玩家40个',pet:'每日上限30个，月卡玩家90个'})) {
    cfg.SurvivalArchive.SelectCategory(category);
    snapshot(category, 50000, []);
    assert(nodes.get('ArchiveStatus').text.includes(note));
    snapshot(category, 50001, []);
    assert.equal(nodes.get('ArchiveStatus').text.split(note).length - 1, 1, 'Refresh never duplicates the monthly note');
}
cfg.SurvivalArchive.SelectCategory('titles');snapshot('titles',50002,[]);
assert.equal(nodes.get('ArchiveStatus').text,'','Title explanation removed');
assert.equal(nodes.get('ArchiveV10WindowTitle').style.fontFamily,'"Source Han Sans SC"');
assert.equal(nodes.get('ArchiveV10WindowTitle').style.fontWeight,'bold');
const rootApi = cfg.SurvivalArchive; root.DeleteAsync();
assert.doesNotThrow(() => { rootApi.Close(); rootApi.Dispose(); rootApi.Dispose(); advance(5); });
cfg.SurvivalMenuV10.Dispose(); assert.equal(liveSubscriptions().length, 0);
console.log('ARCHIVE_V10_LIFECYCLE_PASS: active graph; one fixed shell; unknown filters; native visual cache rebuild; reopen; controller-only/full/child reload; retired event/API/timer isolation; terminal disposal.');
