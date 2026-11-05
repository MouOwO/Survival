const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');

const project = path.resolve(__dirname, '../..');
const source = fs.readFileSync(path.join(project,
    'panorama/src/scripts/custom_game/archive_180de7e38b_titles_compact_v6.js'), 'utf8');
const metrics = {style: 0, classes: 0, tree: 0, created: 0, deleted: 0, palette: 0, warmed: 0, text: 0};
const nodes = {}, subscriptions = {}, requests = [];
const scheduled = new Map();
class Panel {
    constructor(type, parent, id = '') {
        this.id = id; this.paneltype = type; this.parent = parent; this.children = [];
        this.classes = new Set(); this.events = {}; this.visible = true; this.enabled = true;
        this.style = new Proxy({}, {set(target, key, value) {
            metrics.style++; target[key] = value; return true;
        }});
        metrics.created++;
        if (parent) parent.children.push(this);
        if (id) nodes[id] = this;
    }
    get text() { return this._text; }
    set text(value) { metrics.text++; this._text = value; }
    IsValid() { return !this.deleted; }
    AddClass(name) { metrics.classes++; this.classes.add(name); }
    RemoveClass(name) { metrics.classes++; this.classes.delete(name); }
    SetHasClass(name, enabled) { enabled ? this.AddClass(name) : this.RemoveClass(name); }
    BHasClass(name) { return this.classes.has(name); }
    Children() { metrics.tree++; return this.children; }
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
        this.children.slice().forEach(child => child.DeleteAsync());
        this.deleted = true; metrics.deleted++;
        if (this.parent) this.parent.children = this.parent.children.filter(child => child !== this);
    }
    SetPanelEvent(name, callback) { this.events[name] = callback; }
    SetImage(value) { this.image = value; }
    ScrollToTop() {}
}
const root = new Panel('Panel', null, 'ArchiveRoot');
const ids = ['ArchiveWindow', 'ArchiveScrim', 'ArchiveHeader', 'ArchiveTitle', 'ArchiveClose',
    'ArchiveContent', 'ArchiveTabs', 'ArchiveGrid', 'ArchiveFilters', 'ArchiveFilter_all',
    'ArchiveFilter_unlocked', 'ArchiveFilter_locked', 'ArchiveFilterAllLabel', 'ArchiveTooltip',
    'ArchiveDraw', 'ArchiveTickets', 'ArchiveDrawResult', 'ArchiveDrawBar', 'ArchiveFaith',
    'ArchiveCurrencySource', 'ArchiveEmpty', 'ArchivePageTitle', 'ArchiveSummary',
    'ArchiveContext', 'ArchiveHint', 'ArchiveStatus', 'EndlessStatus'];
ids.forEach(id => new Panel('Panel', root, id));
nodes.EndlessStatus.AddClass('ArchiveHidden');
let gameClock=100,hudAlive=true,scope={active:true,ready:true,session:1,loading_identity:1};
const hudCallbacks=new Map(),retiredHUDCallbacks=[];let hudSerial=0;
const runtime={ScopeIdentity:()=>scope};
const hudSource={Runtime:runtime,IsAlive:()=>hudAlive,
    Subscribe(owner,sections,callback){assert.equal(sections.join(','),'wave');hudCallbacks.set(++hudSerial,callback);return hudSerial;},
    Unsubscribe(id){retiredHUDCallbacks.push(hudCallbacks.get(id));hudCallbacks.delete(id);}};
function waveState(wave){for(const callback of hudCallbacks.values())callback({wave});}
const cfg = {
    SurvivalCompactRuntime:runtime,SurvivalCompactHUDSource:hudSource,
    SurvivalArchiveColors: {number: '#ffd800'},
    ArchiveHandoffAssets: {'icon_check_light.png': 'check', 'icon_lock_light.png': 'lock'},
    SurvivalUI: {
        ModalShell: {Adopt() { return {Open() {}, Close() {}, Dispose() {}}; }},
        NavToggle: {Adopt() {}}, ActionButton: {Adopt() {}}, Tooltip: {Adopt() {}}
    },
    ArchiveHandoff: {
        Init() {}, Hide() {}, HideCardText() {}, NavIcon() {}, Card() {}, Icon() {}, Show() {},
        Observe(data) { this.snapshot = data; },
        Unlocked(item) { return Number(item.completed) === 1; },
        ApplyPalette() {
            metrics.palette++;
            function paint(panel) {
                panel.style.color = cfg.SurvivalArchiveColors.number;
                panel.Children().forEach(paint);
            }
            paint(nodes.ArchiveGrid);
        }
    },
    SurvivalSnapshotCache: {Warm() { metrics.warmed++; }}
};
const $ = {
    GetContextPanel: () => root,
    CreatePanel: (type, parent, id) => new Panel(type, parent, id),
    Schedule(delay, callback) { const id = {}; scheduled.set(id, {delay, callback}); return id; },
    CancelScheduled(id) { scheduled.delete(id); }, RegisterEventHandler() {}
};
vm.runInNewContext(source, {
    $, GameUI: {CustomUIConfig: () => cfg}, Game: {GetLocalPlayerID: () => 0,GetGameTime:()=>gameClock},
    GameEvents: {
        Subscribe(name, callback) { subscriptions[name] = callback; return name; },
        Unsubscribe() {},
        SendCustomGameEventToServer(name, payload) { requests.push({name, payload}); }
    }
});
const api = cfg.SurvivalArchive;
function snapshot(category, sequence, count) {
    subscriptions.survival_archive_snapshot({
        ok: 1, category_id: category, sequence, chunks: 1, chunk: 1,
        categories: [{id: 'clear', name: '通关存档'}, {id: 'endless', name: '无尽存档'}],
        rows: [{id: category + '_1', name: '第一阶', count, target: 1000, completed: count >= 1000 ? 1 : 0}]
    });
}
const cold = {...metrics};
snapshot('clear', 1, 0);
snapshot('endless', 1, 10);
assert.deepEqual(metrics, cold, 'closed snapshots cache data without painting, warming or traversing cards');

const running = {status: 'running', wave: 1, remaining: 5, seconds: 60, score: 0};
subscriptions.survival_endless_state(running);
assert(!nodes.EndlessStatus.BHasClass('ArchiveHidden'), 'the gameplay banner is live while the archive is closed');
const quiet = {...metrics};
for (let i = 0; i < 1000; i++) {
    subscriptions.survival_endless_state({...running, wave: i + 1, remaining: i % 5, score: i});
}
for (const key of ['style', 'classes', 'tree', 'created', 'deleted', 'palette', 'warmed']) {
    assert.equal(metrics[key], quiet[key], '1000 closed state packets cause no archive work: ' + key);
}
assert.equal(nodes.EndlessStatus.text, '无尽第1000波 · 剩余4只 · 60秒 · 本局999分');
assert.equal(requests.length, 0, 'closed state packets do not request archive snapshots');
const latestState = {...running, wave: 1000, remaining: 4, score: 999};
const duplicateText = metrics.text;
for (let i = 0; i < 1000; i++) subscriptions.survival_endless_state(latestState);
assert.equal(metrics.text, duplicateText, 'duplicate packets do not rewrite the banner text');

snapshot('endless', 2, 999);
api.Open();
assert.equal(cfg.ArchiveHandoff.snapshot.category_id, 'clear');
api.SelectCategory('endless');
assert.equal(cfg.ArchiveHandoff.snapshot.rows[0].count, 999, 'opening and switching tabs render the latest closed cache');
assert(nodes.ArchiveSummary.text.includes('累计积分 999'));
assert.equal(nodes.EndlessStatus.text, '无尽第1000波 · 剩余4只 · 60秒 · 本局999分');
const beforeCountdown = {...metrics};
for (let i = 0; i < 1000; i++) subscriptions.survival_endless_state({...latestState, seconds: 60 - i % 60});
for (const key of ['style', 'classes', 'tree', 'created', 'deleted', 'palette', 'warmed']) {
    assert.equal(metrics[key], beforeCountdown[key], 'opened countdown updates only the banner: ' + key);
}
const beforeZero = requests.length;
for (let i = 0; i < 1000; i++) subscriptions.survival_endless_state({...latestState, remaining: 0, cleared: 1000});
assert.equal(requests.length, beforeZero + 1, 'duplicate cleared packets request the active endless page once');

const stablePalette = metrics.palette, stableCreated = metrics.created;
snapshot('endless', 3, 999);
assert.equal(metrics.palette, stablePalette, 'unchanged page structure does not repaint the recursive palette');
assert.equal(metrics.created, stableCreated, 'unchanged categories and rows preserve their native panels');
cfg.SurvivalArchiveColors.number = '#abcdef';
snapshot('endless', 4, 999);
assert.equal(metrics.palette, stablePalette + 1, 'a changed theme still repaints existing cards');
snapshot('endless', 5, 1000);
assert.equal(metrics.palette, stablePalette + 2, 'unlocked/new card children still receive their correct palette');
assert(nodes.ArchiveSummary.text.includes('已完成 1 / 1'));
api.Close();
const closedAgain = {...metrics};
snapshot('endless', 6, 1005);
assert.deepEqual(metrics, closedAgain, 'closing the view resumes data-only snapshots');
api.Open();
assert.equal(cfg.ArchiveHandoff.snapshot.rows[0].count, 1005, 'reopening shows the latest score immediately');
subscriptions.survival_endless_state({status: 'finished', cleared: 1000, wave: 1000,
    remaining: 0, score: 1005, reason: '时间结束'});
assert.equal(nodes.EndlessStatus.text, '无尽结束 · 已通过1000波 · 1005分 · 时间结束');
subscriptions.survival_endless_state({status: 'idle', score: 0});
assert(nodes.EndlessStatus.BHasClass('ArchiveHidden'), 'idle still hides the gameplay banner');
const tipTimers = () => [...scheduled.values()].filter(timer => timer.delay === 3);
function fireTimer(timer) {
    for (const [id, entry] of scheduled) if (entry === timer) scheduled.delete(id);
    timer.callback();
}
subscriptions.ui_notification({kind:'endless_tip',player_id:1,message:'其他玩家的提示'});
assert(nodes.EndlessStatus.BHasClass('ArchiveHidden'), 'another player cannot display a local tip');
subscriptions.ui_notification({kind:'endless_tip',player_id:0,message:'还有20秒开启无尽挑战'});
assert.equal(nodes.EndlessStatus.text,'还有20秒开启无尽挑战');
assert.equal(tipTimers().length,1);
const staleHide=tipTimers()[0].callback;
subscriptions.ui_notification({kind:'endless_tip',player_id:0,message:'还有15秒开启无尽挑战'});
assert.equal(tipTimers().length,1,'only one transient tip timer survives replacement');
staleHide();assert(!nodes.EndlessStatus.BHasClass('ArchiveHidden'),'an old hide callback cannot hide the next reminder');
fireTimer(tipTimers()[0]);assert(nodes.EndlessStatus.BHasClass('ArchiveHidden'),'tips automatically hide after three seconds');
subscriptions.survival_endless_state({...latestState,wave:1001});
fireTimer(tipTimers().at(-1));
subscriptions.survival_endless_state({...latestState,wave:1001,seconds:59,remaining:3});
assert(nodes.EndlessStatus.BHasClass('ArchiveHidden'),'ordinary per-second state changes do not reopen the tip');
subscriptions.survival_endless_state({...latestState,wave:1002});
assert(!nodes.EndlessStatus.BHasClass('ArchiveHidden'),'a new wave gets a fresh brief tip');
const countdownTimers=()=>[...scheduled.values()].filter(timer=>timer.delay===0.25);
waveState({overflow_active:true,overflow_deadline:120,status:'spawning'});
assert.equal(hudCallbacks.size,1,'one owner subscription reuses the existing HUD view');
assert.equal(tipTimers().length,0,'starting overflow cancels an old transient hide');
assert.equal(countdownTimers().length,1);
const staleCountdown=countdownTimers()[0].callback;
for(let seconds=20;seconds>0;seconds--){
    gameClock=120-seconds;
    fireTimer(countdownTimers()[0]);
    assert.equal(nodes.EndlessStatus.text,'您需在'+seconds+'s内清理怪物');
    assert(!nodes.EndlessStatus.BHasClass('ArchiveHidden'));
    assert.equal(countdownTimers().length,1);
    const before={...metrics};
    for(let paused=0;paused<10;paused++)fireTimer(countdownTimers()[0]);
    assert.deepEqual(metrics,before,'paused game clock performs zero setters, tree walks or panel creation');
    waveState({overflow_active:true,overflow_deadline:120,status:'spawning',alive:91+seconds});
    assert.deepEqual(metrics,before,'unrelated real population deltas do not restart the same countdown');
}
const oldWarning=nodes.EndlessStatus.text;
subscriptions.ui_notification({kind:'wave_overflow_tip',player_id:0,message:'legacy重复'});
assert.equal(nodes.EndlessStatus.text,oldWarning,'old full-text event cannot duplicate an authoritative HUD warning');
subscriptions.ui_notification({kind:'endless_tip',player_id:0,message:'低优先级提示'});
assert.equal(nodes.EndlessStatus.text,oldWarning,'overflow warning has priority over a brief unrelated tip');
waveState({overflow_active:false,overflow_deadline:0,status:'spawning',alive:89});
assert.equal(nodes.EndlessStatus.text,'怪物数量已恢复，警报解除');
assert.equal(countdownTimers().length,0);assert.equal(tipTimers().length,1);
staleCountdown();assert.equal(nodes.EndlessStatus.text,'怪物数量已恢复，警报解除','old countdown cannot overwrite recovery');
gameClock=125;waveState({overflow_active:true,overflow_deadline:145,status:'spawning'});
assert.equal(nodes.EndlessStatus.text,'您需在20s内清理怪物','a second overload receives a fresh authoritative deadline');
assert.equal(tipTimers().length,0);
gameClock=145;fireTimer(countdownTimers()[0]);
assert(nodes.EndlessStatus.BHasClass('ArchiveHidden'),'expiry never renders a zero or negative warning');
assert.equal(countdownTimers().length,0);
waveState({overflow_active:false,overflow_deadline:0,status:'defeat',player_defeated:true});
assert.equal(tipTimers().length,0,'defeat does not masquerade as recovery');
scope={...scope,session:2};gameClock=150;
waveState({overflow_active:true,overflow_deadline:170,status:'spawning'});
const staleWorld=countdownTimers()[0].callback;
scope={...scope,session:3};fireTimer(countdownTimers()[0]);
assert(nodes.EndlessStatus.BHasClass('ArchiveHidden'),'scope replacement clears the old world warning');
assert.equal(countdownTimers().length,0);
waveState({overflow_active:true,overflow_deadline:180,status:'spawning'});
assert.equal(countdownTimers().length,1);
const staleDispose=countdownTimers()[0].callback;
api.Dispose();assert(nodes.EndlessStatus.BHasClass('ArchiveHidden'),'controller disposal hides its tip');
assert.equal(hudCallbacks.size,0);assert.equal(countdownTimers().length,0);
const afterDispose={...metrics};staleDispose();
for(const callback of retiredHUDCallbacks)callback({wave:{overflow_active:true,overflow_deadline:200}});
assert.deepEqual(metrics,afterDispose,'disposed callbacks cannot resurrect the old panel');
const css=fs.readFileSync(path.join(project,'panorama/src/styles/custom_game/archive.css'),'utf8');
const tipStyle=css.match(/#EndlessStatus\s*\{([^}]+)\}/)[1];
assert.match(tipStyle,/horizontal-align:\s*center/);assert.match(tipStyle,/vertical-align:\s*center/);
assert.match(tipStyle,/margin:\s*0px/);
const ui=fs.readFileSync(path.join(project,'panorama/src/scripts/custom_game/survival_ui.js'),'utf8');
const first=ui.indexOf('    function showNotification('),last=ui.indexOf('    function sendClientDiagnostic(',first);
vm.runInNewContext(ui.slice(first,last)+'\nshowNotification({kind:"endless_tip",message:"倒计时"});\nshowNotification({kind:"wave_overflow_tip",message:"您需在20s内清理怪物"});',{
    panel(){throw new Error('endless tips must not create an ordinary top notification');}
});
console.log('ARCHIVE_ENDLESS_REFRESH_PASS: cached snapshots, bounded center-tip timer, stale-hide guard, single-authority overflow deadlines/paused local countdown/recovery/restart/expiry/scope, wave/end dedup, no top duplicate, disposal and centered styling');
