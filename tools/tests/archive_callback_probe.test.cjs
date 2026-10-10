const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');

const project = path.resolve(__dirname, '../..');
const scripts = ['ui_snapshot_cache.js', 'archive_void_v1_data.js', 'archive_void_v1.js',
    'archive_180de7e38b_titles_compact_v6.js'];
const sources = scripts.map(name => ({name, source: fs.readFileSync(path.join(project,
    'panorama/src/scripts/custom_game', name), 'utf8')}));
const expected = ['archive.snapshot', 'archive.render', 'archive.tabs', 'archiveVoid.render',
    'archiveVoid.renderSidebar', 'archiveVoid.renderItems', 'archiveVoid.enter', 'archiveVoid.fit',
    'archiveVoid.wallet', 'archiveVoid.leave'].sort();

// Define the host and its wrappers in another JS realm, as the actual HUD host
// and archive layout do. RegisterModule only describes targets; Start opts in.
function probeHost() {
    return vm.runInNewContext(`(function () {
        var modules = {}, captures = [], calls = {}, getCalls = 0, setCalls = 0;
        return {
            RegisterModule: function (name, entries, generation) {
                modules[name] = {entries: entries, generation: generation}; return true;
            },
            Names: function () {
                var names = [];
                Object.keys(modules).forEach(function (prefix) {
                    modules[prefix].entries.forEach(function (entry) {names.push(prefix + '.' + entry.name);});
                });
                return names.sort();
            },
            Generations: function () {
                return Object.keys(modules).map(function (prefix) {return modules[prefix].generation;});
            },
            Start: function () {
                if (captures.length) throw new Error('capture already active');
                Object.keys(modules).forEach(function (prefix) {
                    modules[prefix].entries.forEach(function (entry) {
                        var name = prefix + '.' + entry.name, original = entry.get(); getCalls++;
                        if (typeof original !== 'function') throw new Error('missing function: ' + name);
                        var wrapper = function () {
                            calls[name] = (calls[name] || 0) + 1;
                            return original.apply(this, arguments);
                        };
                        entry.set(wrapper); setCalls++;
                        if (entry.get() !== wrapper) throw new Error('private binding was not replaced: ' + name);
                        captures.push({entry: entry, original: original, wrapper: wrapper});
                    });
                });
            },
            Stop: function () {
                captures.forEach(function (record) {
                    if (record.entry.get() === record.wrapper) record.entry.set(record.original);
                    if (record.entry.get() !== record.original) throw new Error('private binding was not restored');
                });
                captures = [];
            },
            Count: function (name) {return calls[name] || 0;},
            Stats: function () {return {getCalls: getCalls, setCalls: setCalls};}
        };
    })()`);
}

function fixture(toolsMode, host) {
    const nodes = new Map(), listeners = [], scheduled = [], requests = [], counts = {fits: 0, created: 0};
    class Panel {
        constructor(type, parent, id = '') {
            this.paneltype = type; this.parent = parent; this.id = id;
            this.children = []; this.classes = new Set(); this.events = {};
            this.style = {}; this.text = ''; this.visible = true; this.enabled = true;
            counts.created++;
            if (parent) parent.children.push(this);
            if (id) nodes.set(id, this);
        }
        IsValid() { return !this.deleted; }
        AddClass(name) { this.classes.add(name); }
        RemoveClass(name) { this.classes.delete(name); }
        SetHasClass(name, value) { value ? this.AddClass(name) : this.RemoveClass(name); }
        BHasClass(name) { return this.classes.has(name); }
        Children() { return this.children; }
        FindChildTraverse(id) {
            if (this.id === id) return this;
            for (const child of this.children) {
                if (!child.IsValid()) continue;
                const found = child.FindChildTraverse(id); if (found) return found;
            }
            return null;
        }
        RemoveAndDeleteChildren() { this.children.slice().forEach(child => child.DeleteAsync()); }
        DeleteAsync() {
            this.children.slice().forEach(child => child.DeleteAsync()); this.deleted = true;
            if (this.parent) this.parent.children = this.parent.children.filter(child => child !== this);
            if (nodes.get(this.id) === this) nodes.delete(this.id);
        }
        SetPanelEvent(name, callback) { this.events[name] = callback; }
        SetImage(value) { this.image = value; }
        SetScaling() {}
        ScrollToTop() {}
    }
    const root = new Panel('Panel', null, 'ArchiveRoot');
    ['ArchiveWindow', 'ArchiveScrim', 'ArchiveHeader', 'ArchiveTitle', 'ArchiveClose',
        'ArchiveContent', 'ArchiveTabs', 'ArchiveGrid', 'ArchiveFilters', 'ArchiveFilter_all',
        'ArchiveFilter_unlocked', 'ArchiveFilter_locked', 'ArchiveFilterAllLabel', 'ArchiveTooltip',
        'ArchiveTooltipStateIcon', 'ArchiveDraw', 'ArchiveTickets', 'ArchiveDrawResult', 'ArchiveDrawBar',
        'ArchiveFaith', 'ArchiveCurrencySource', 'ArchiveEmpty', 'ArchivePageTitle', 'ArchiveSummary',
        'ArchiveContext', 'ArchiveHint', 'ArchiveStatus', 'EndlessStatus'].forEach(id => new Panel('Panel', root, id));
    const cfg = {
        HandoffGeneration: 7, SurvivalClientCallbackProbe: host,
        SurvivalArchiveColors: {number: '#ffd800'},
        ArchiveHandoffAssets: {'icon_check_light.png': 'check', 'icon_lock_light.png': 'lock'},
        SurvivalCommerceWallet: {GetCatalog() { return {balances: {u_coin: 1, shop_points: 2, shop_gold: 3}}; }},
        SurvivalUI: {
            ModalShell: {Adopt() { return {Open() {}, Close() {}, Dispose() {}}; }},
            NavToggle: {Adopt() {}}, ActionButton: {Adopt() {}}, Tooltip: {Adopt() {}},
            Fit() { counts.fits++; }
        },
        ArchiveHandoff: {
            Init() {}, Hide() {}, HideCardText() {}, NavIcon() {}, Card() {}, Icon() {},
            Observe() {}, Show() {}, ApplyPalette() {},
            Unlocked(item) { return Number(item.completed) === 1; }
        }
    };
    const game = {GetLocalPlayerID: () => 0, AddCommand() {}};
    if (toolsMode !== undefined) game.IsInToolsMode = () => toolsMode;
    const context = vm.createContext({
        $: {
            GetContextPanel: () => root,
            CreatePanel: (type, parent, id) => new Panel(type, parent, id),
            Schedule(delay, callback) { const timer = {delay, callback}; scheduled.push(timer); return timer; },
            CancelScheduled(timer) { timer.cancelled = true; }, RegisterEventHandler() {}, DispatchEvent() {}, Msg() {}
        },
        GameUI: {CustomUIConfig: () => cfg}, Game: game,
        GameEvents: {
            Subscribe(name, callback) { const listener = {name, callback}; listeners.push(listener); return listener; },
            Unsubscribe(listener) { listener.cancelled = true; },
            SendCustomGameEventToServer(name, payload) { requests.push({name, payload}); }
        }
    });
    for (const {name, source} of sources) vm.runInContext(source, context, {filename: name});
    function emit(name, data) {
        listeners.filter(listener => listener.name === name && !listener.cancelled)
            .forEach(listener => listener.callback(data));
    }
    function immediate() {
        for (let executions = 0; executions < 100; executions++) {
            const index = scheduled.findIndex(timer => timer.delay === 0 && !timer.cancelled);
            if (index < 0) return;
            scheduled.splice(index, 1)[0].callback();
        }
        throw new Error('unexpected timer loop');
    }
    const versions = {};
    function snapshot(category, count = 0) {
        const data = {ok: 1, category_id: category, sequence: (versions[category] || 0) + 1,
            chunks: 1, chunk: 1, categories: cfg.ArchiveVoidV1Data.categories,
            rows: [{id: category === 'shadow' ? 'shadow_01' : 'clear_01',
                name: '实际条目', count, target: 430, completed: 0, count_known: 1}]};
        versions[category] = data.sequence; emit('survival_archive_snapshot', data); immediate(); return data;
    }
    return {cfg, nodes, scheduled, counts, emit, immediate, snapshot};
}

const firstHost = probeHost(), tools = fixture(true, firstHost);
assert.deepEqual(Array.from(firstHost.Names()), expected, 'Tools load registers all ten actual private targets');
assert(firstHost.Generations().every(generation => generation === 7), 'owner generations belong to the current HUD generation');
assert.deepEqual({...firstHost.Stats()}, {getCalls: 0, setCalls: 0}, 'passive registration installs no hooks');
tools.snapshot('clear'); tools.snapshot('shadow', 2);
for (const name of expected) assert.equal(firstHost.Count(name), 0, 'targets remain uninstrumented until Start: ' + name);
const archive = tools.cfg.SurvivalArchive, voidView = tools.cfg.SurvivalArchiveVoidV1;
firstHost.Start();
const beforeClosed = tools.counts.created;
tools.snapshot('clear');
assert.equal(firstHost.Count('archive.snapshot'), 1, 'the subscribed snapshot event reads the replaced private binding');
assert.equal(firstHost.Count('archive.render'), 1, 'snapshot dispatch uses the replaced render function');
assert.equal(tools.counts.created, beforeClosed, 'observing a closed snapshot preserves data-only behavior');
archive.Open(); archive.SelectCategory('shadow');
assert(firstHost.Count('archive.tabs') > 0, 'actual tab rendering calls its replaceable lexical entry');
tools.snapshot('shadow', 8);
assert.equal(tools.nodes.get('VoidShadowItem_shadow_01').__voidItem.count, 8, 'wrapped callbacks preserve normal snapshot state');
const walletCalls = firstHost.Count('archiveVoid.wallet');
tools.emit('survival_commerce_result', {ok: 1}); tools.immediate();
assert.equal(firstHost.Count('archiveVoid.wallet'), walletCalls + 1, 'the commerce event dynamically reads its wrapped callback');
const fitCalls = firstHost.Count('archiveVoid.fit'), nativeFits = tools.counts.fits;
voidView.Fit();
assert.equal(firstHost.Count('archiveVoid.fit'), fitCalls + 1, 'the public Fit API uses the replaceable private function');
assert.equal(tools.counts.fits, nativeFits + 1, 'the wrapped public API still performs its normal work');
const leaveCalls = firstHost.Count('archiveVoid.leave');
voidView.Leave();
assert.equal(firstHost.Count('archiveVoid.leave'), leaveCalls + 1, 'the public Leave API uses the replaceable private function');
const renderCalls = firstHost.Count('archiveVoid.render');
assert.equal(voidView.Render(null, 'shadow', 'all', tools.cfg.ArchiveVoidV1Data.categories,
    {reference: [1920, 1080]}), true, 'wrapped Render preserves its return value');
assert.equal(firstHost.Count('archiveVoid.render'), renderCalls + 1, 'the public Render API uses the replaceable private function');
assert.equal(voidView.Render(null, 'clear', 'all', [], {}), false, 'wrapped Render retains its non-void return value');
for (const name of expected) assert(firstHost.Count(name) > 0, 'real event/API paths observed the target: ' + name);
firstHost.Stop();
const stoppedSnapshotCalls = firstHost.Count('archive.snapshot');
tools.snapshot('shadow', 9);
assert.equal(firstHost.Count('archive.snapshot'), stoppedSnapshotCalls, 'Stop restores real event callbacks');

const secondHost = probeHost();
tools.cfg.SurvivalClientCallbackProbe = secondHost; tools.cfg.HandoffGeneration = 8;
assert.equal(archive.RegisterToolsProbe(), true, 'the controller can register into a replacement host');
assert.equal(voidView.RegisterToolsProbe(), true, 'the custom view can register into a replacement host');
assert.deepEqual(Array.from(secondHost.Names()), expected, 're-registration publishes complete targets to the current host');
assert(secondHost.Generations().every(generation => generation === 8), 'explicit registration uses the new owner generation');
assert.deepEqual({...secondHost.Stats()}, {getCalls: 0, setCalls: 0}, 're-registration stays passive');
secondHost.Start();
tools.snapshot('shadow', 10); voidView.Fit(); voidView.Leave();
assert.equal(secondHost.Count('archive.snapshot'), 1, 'a replacement host observes the already subscribed real event');
assert(secondHost.Count('archiveVoid.render') > 0);
assert(secondHost.Count('archiveVoid.fit') > 0);
assert(secondHost.Count('archiveVoid.leave') > 0);
assert.equal(firstHost.Count('archive.snapshot'), stoppedSnapshotCalls, 'the retired host does not receive replacement capture data');
secondHost.Stop();
const retiredHost = probeHost();
tools.cfg.SurvivalClientCallbackProbe = retiredHost;
archive.Dispose();
assert.equal(archive.RegisterToolsProbe(), false, 'a disposed controller cannot register callbacks into a new host');
assert.equal(voidView.RegisterToolsProbe(), false, 'a disposed custom view cannot register its retired callbacks');
assert.deepEqual(Array.from(retiredHost.Names()), [], 'retired layout functions never acquire new host authority');

for (const mode of [false, undefined]) {
    const disabledHost = probeHost(), plain = fixture(mode, disabledHost);
    assert.deepEqual(Array.from(disabledHost.Names()), [], 'non-Tools environments do not register modules');
    assert.equal(plain.cfg.SurvivalArchive.RegisterToolsProbe(), false);
    assert.equal(plain.cfg.SurvivalArchiveVoidV1.RegisterToolsProbe(), false);
    assert.deepEqual(Array.from(disabledHost.Names()), [], 'explicit registration cannot enable hooks outside Tools');
    assert.deepEqual({...disabledHost.Stats()}, {getCalls: 0, setCalls: 0});
    assert.equal(plain.scheduled.length, 1, 'only the existing archive sync timer exists outside Tools');
}
const passiveTools = fixture(true, probeHost());
assert.equal(passiveTools.scheduled.length, 1, 'Tools registration adds no timer to the archive startup baseline');
console.log('ARCHIVE_CALLBACK_PROBE_PASS: ten full-source private targets, passive Tools registration, cross-context lexical rebinding, live snapshot/commerce dispatch, dynamic Render/Leave/Fit APIs, restore, replacement host and non-Tools timer isolation');
