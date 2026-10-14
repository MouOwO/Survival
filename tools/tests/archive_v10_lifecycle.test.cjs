const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const assert = require('node:assert/strict');
const {csv} = require('../shop_ui_12h/catalog.cjs');
const repo = path.resolve(__dirname, '../..');
const sourceRoot = path.join(repo, 'panorama/src/scripts/custom_game');
const graph = ['ui_snapshot_cache.js', 'archive_purple.js', 'archive_v10_data.js', 'archive_parchment_data.js', 'common/tooltip_dismiss.js', 'common/menu_v10.js', 'archive_v10_semantics.js', 'common/archive_tooltip.js', 'archive_v10.js', 'archive_180de7e38b_titles_compact_v6.js'];
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
const shadowRows = [{id: 'shadow_01', count: 3, target: 430, description: '真实测试效果'}, {id: 'shadow_02', count: 0, target: 430}, {id: 'shadow_03', count: 3, count_known: 0, target: 430}];
const api = load();
snapshot('clear', 1, [{id: 'clear_01', name: '通关', count: 2, target: 1, completed: 1}]);
snapshot('shadow', 2, shadowRows);
api.Open(); api.SelectCategory('shadow'); advance(.1);
assert.equal(canvases().length, 1, 'Exactly one archive shell is constructed');
assert.equal(cfg.SurvivalMenuV10.Entries().length, 0, 'The independent archive never adopts the global menu or its resource strip');
assert.equal(cfg.SurvivalArchiveV10.Inspect().categories.length, 16, 'Archive retains its categories while the two social collections move to their independent window');
assert(!nodes.has('ArchiveV10Category_ex')&&!nodes.has('ArchiveV10Category_friend'));
assert(nodes.has('ArchiveV10Category_beast'),'The real blessing pool remains in archive');
assert.equal(nodes.get('ArchiveWindow').style.width, '1200px');
assert.equal(nodes.get('ArchiveWindow').style.height, '900px');
assert.equal(nodes.get('ArchiveV10Shell_Background').style.backgroundColor, 'transparent', 'PNG edge alpha is never flattened by a CSS backing rectangle');
assert.equal(nodes.get('ArchiveV10CategoryIcon').image, cfg.ArchiveParchmentData.assets.archive_emblem.file, 'The large shadow header uses the full-resolution emblem');
assert.equal(nodes.get('ArchiveFooter').visible, true, 'Gameplay save/rejection feedback remains visible');
assert.equal(nodes.get('ArchiveStatus').style.marginTop, '0px', 'The retained status label cannot inherit the old 12px top margin');
assert.equal(nodes.get('ArchiveFooter').style.position, '390px 815px 0px');
assert(parseFloat(nodes.get('ArchiveFooter').style.position.split(' ')[1]) + parseFloat(nodes.get('ArchiveFooter').style.height) < 840, 'The complete footer stays above the textured bottom edge and its transparent margin');
nodes.get('ArchiveV10FilterToggle').events.onactivate();
assert.equal(nodes.get('ArchiveV10FilterMenu').visible, true);
nodes.get('ArchiveV10Filter_all').events.onactivate();
assert.equal(nodes.get('ArchiveV10FilterMenu').visible, false);
const categorySearch = nodes.get('ArchiveV10Search');
categorySearch.text = '星悦'; categorySearch.events.ontextentrychange();
assert.deepEqual(nodes.get('ArchiveV10Sidebar').Children().filter(node => node.visible).map(node => node.id), ['ArchiveV10Category_starjoy_points']);
categorySearch.text = '不存在的分类'; categorySearch.events.ontextentrychange();
assert.equal(nodes.get('ArchiveV10SearchEmpty').visible, true, 'Search provides a truthful empty state');
categorySearch.text = ''; categorySearch.events.ontextentrychange();
assert.equal(nodes.get('ArchiveV10Sidebar').Children().filter(node => node.visible).length, 16);
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
api.Filter('locked');
assert(cards().every(card => card.__archiveItem.count_known === 1 && card.__archiveItem.count === 0), 'Unknown inventory never enters locked filtering');
api.Filter('all');
api.SelectCategory('clear');
assert.equal(canvases()[0], canvas, 'Category switching retains native shell identity');
assert.deepEqual(canvas.Children().filter(panel => panel.id.startsWith('ArchiveV10Shell_')), rails, 'Background, navigation and metal rails remain the same native components');
assert.equal(JSON.stringify(canvas.style), shellBounds, 'Category switching does not change shell geometry');
api.SelectCategory('shadow');
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
cfg.SurvivalArchive.SelectCategory('shadow'); snapshot('shadow', 21, shadowRows);
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
const childApi = cfg.SurvivalArchive, childHandler = listeners.find(listener => !listener.cancelled && listener.name === 'survival_archive_snapshot').callback;
root.RemoveAndDeleteChildren(); fixture(true);
const beforeChildReload = requests.length;
assert.doesNotThrow(() => { childHandler({ok: 1, category_id: 'clear', sequence: 999, rows: []}); childApi.Refresh(true); advance(.1); });
assert.equal(requests.length, beforeChildReload, 'A surviving root cannot revive its deleted lifetime marker');
load(); cfg.SurvivalArchive.Open(); snapshot('clear', 40, [{id: 'replacement', name: '替换', count: 0, target: 1, completed: 0}]);
assert.equal(cards().length, 1, 'Replacing children and reloading the active graph restores real data');
assert.equal(canvases().length, 1);
const rootApi = cfg.SurvivalArchive; root.DeleteAsync();
assert.doesNotThrow(() => { rootApi.Close(); rootApi.Dispose(); rootApi.Dispose(); advance(5); });
cfg.SurvivalMenuV10.Dispose(); assert.equal(liveSubscriptions().length, 0);
console.log('ARCHIVE_V10_LIFECYCLE_PASS: active graph; one fixed shell; unknown filters; native visual cache rebuild; reopen; controller-only/full/child reload; retired event/API/timer isolation; terminal disposal.');
