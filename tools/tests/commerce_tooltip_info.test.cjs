'use strict';

// Run the actual commerce renderer and shared dismissal policy. This models
// native UI scale separately from a menu's CSS Fit transform; no game runs.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const scripts = path.resolve(__dirname, '../../panorama/src/scripts/custom_game');

function harness({nativeScale = .75, fitScale = .6} = {}) {
    let cursor = [0, 0], time = 0, timerId = 0, checkouts = 0;
    const jobs = new Map(), scheduled = [], requests = [];
    class Panel {
        constructor(type, parent, id = '') {
            this.paneltype = type; this.id = id; this.parent = parent;
            this.children = []; this.style = {}; this.events = {}; this.classes = new Set();
            this.visible = true; this.enabled = true; this.hittest = true; this.hittestchildren = true;
            this.actualuiscale_x = this.actualuiscale_y = nativeScale;
            if (parent) parent.children.push(this);
        }
        check() { assert(!this.deleted, 'stale callbacks must not access deleted native panels'); }
        IsValid() { return !this.deleted; }
        GetParent() { this.check(); return this.parent; }
        Children() { this.check(); return this.children; }
        AddClass(value) { this.check(); value.split(/\s+/).forEach(v => this.classes.add(v)); }
        RemoveClass(value) { this.check(); this.classes.delete(value); }
        BHasClass(value) { this.check(); return this.classes.has(value); }
        SetHasClass(value, on) { on ? this.AddClass(value) : this.RemoveClass(value); }
        SetPanelEvent(name, fn) { this.check(); this.events[name] = fn; }
        SetImage(value) { this.check(); this.image = value; }
        SetScaling() { this.check(); }
        DeleteAsync() {
            this.check(); this.children.slice().forEach(child => child.DeleteAsync());
            this.deleted = true;
            if (this.parent) this.parent.children = this.parent.children.filter(child => child !== this);
        }
        get actuallayoutwidth() { this.check(); return this === root ? 1920 : (parseFloat(this.style.width) || 276) * nativeScale; }
        get actuallayoutheight() {
            this.check();
            if (this === root) return 1080;
            return (parseFloat(this.style.height) || (this.BHasClass('MenuV10CommerceDetailBody') ? 120 : 28)) * nativeScale;
        }
        GetPositionWithinWindow() {
            this.check();
            if (this === root) return {x: 0, y: 0};
            if (this === window) return {x: 100, y: 80};
            const at = this.parent.GetPositionWithinWindow();
            const local = String(this.style.position || '0px 0px').split(/\s+/);
            return {x: at.x + (parseFloat(local[0]) || 0) * nativeScale * fitScale,
                y: at.y + (parseFloat(local[1]) || 0) * nativeScale * fitScale};
        }
    }
    const root = new Panel('Panel', null, 'Root');
    const window = new Panel('Panel', root, 'MarketWindow');
    window.style.width = '1120px'; window.style.height = '790px';
    const layer = new Panel('Panel', window, 'Details');
    layer.style.width = '1120px'; layer.style.height = '790px';
    function skin(tip) {
        const surface = new Panel('Panel', tip);
        return {surface, Resize(width, height) {
            surface.style.width = width + 'px'; surface.style.height = height + 'px';
        }};
    }
    const cfg = {SurvivalUI: {}, SurvivalMenuV10: {SkinTooltip: skin}, SurvivalBlackLionMarket: {SkinTooltip: skin}};
    const $ = {GetContextPanel: () => root, CreatePanel: (type, parent, id) => new Panel(type, parent, id),
        Schedule(delay, fn) { const value = {id: ++timerId, delay, at: time + delay, fn}; scheduled.push(value); jobs.set(value.id, value); return value.id; },
        CancelScheduled(id) { jobs.delete(id); }};
    const context = vm.createContext({$, GameUI: {CustomUIConfig: () => cfg, GetCursorPosition: () => cursor},
        GameEvents: {SendCustomGameEventToServer: (...value) => requests.push(value)}});
    function load(file) { vm.runInContext(fs.readFileSync(path.join(scripts, file), 'utf8'), context, {filename: file}); }
    load('common/tooltip_dismiss.js');
    load('item_art_remaining_5d5c1152eb.js');
    load('common/commerce_components.js');
    function advance(duration) {
        const end = time + duration; let ticks = 0;
        while (true) {
            const next = [...jobs.values()].filter(value => value.at <= end).sort((a, b) => a.at - b.at || a.id - b.id)[0];
            if (!next) break;
            assert(++ticks < 1000, 'tooltip jobs must not spin');
            jobs.delete(next.id); time = next.at; next.fn();
        }
        time = end;
    }
    function bind(item = {}, {market = true, y = 40, rewards = [], effect = '攻击力 +10'} = {}) {
        const card = new Panel('Panel', window);
        card.style.position = '40px ' + y + 'px 0px'; card.style.width = '144px'; card.style.height = '64px';
        const buy = new Panel('Button', card); buy.events.onactivate = () => { if (buy.enabled) checkouts++; };
        const purchase = buy.events.onactivate;
        const props = {market, detailLayer: layer, menu: {Scale: () => fitScale}, sourceWidth: 144,
            windowWidth: 1120, windowHeight: 790, rewards, effect, action: () => checkouts++};
        const data = {sku: 'sample', title: '样例商品', product_type: 'single', description: '配置描述', ...item};
        const tip = cfg.SurvivalCommerceComponents.BindDetail(card, data, props, data.product_type === 'bundle');
        return {card, tip, buy, purchase, surface: tip.Children()[0], props};
    }
    function inside(node, dx = 4, dy = 4) { const at = node.GetPositionWithinWindow(); cursor = [at.x + dx, at.y + dy]; }
    function descendants(node) { return [node, ...node.Children().flatMap(descendants)]; }
    function find(node, cls) { return assertNode(descendants(node).find(value => value.BHasClass(cls)), cls); }
    function assertNode(node, cls) { assert(node, 'missing ' + cls); return node; }
    function hover(entry) { inside(entry.card); entry.card.events.onmouseover(); }
    function dispose(...entries) { entries.forEach(entry => { if (entry.tip.IsValid()) entry.card.__purpleDispose(); }); }
    return {cfg, bind, advance, inside, hover, dispose, descendants, find, jobs, scheduled, requests,
        checkoutCount: () => checkouts, setCursor: value => { cursor = value; }, fitScale};
}

test('Commerce hover is synchronous, informational, and has one cancellable layout follow-up', () => {
    const h = harness(), item = h.bind();
    assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().owners, 0, 'hidden cards do not register idle owners');
    const start = h.scheduled.length;
    h.hover(item);
    assert(item.tip.BHasClass('Visible'), 'onmouseover shows before the next frame');
    assert.equal(h.scheduled.slice(start).filter(value => value.delay === 0).length, 1);
    assert(h.scheduled.slice(start).every(value => value.delay === 0 || value.delay === .03),
        'only one layout task and the shared policy watcher may be scheduled');
    const labels = h.descendants(item.tip).filter(node => node.paneltype === 'Label');
    assert.equal(labels.length, 3);
    assert(labels[0].BHasClass('RCPurpleDetailTitle'));
    assert(labels[1].BHasClass('RCPurpleDetailQuality'));
    assert(labels[2].BHasClass('RCProductEffect'));
    assert.equal(labels[0].text, '样例商品');
    assert.equal(labels[1].text, '品级：未配置');
    assert.equal(labels[2].text, '攻击力 +10');
    assert(!h.descendants(item.tip).some(node => node.paneltype === 'Image' || node.paneltype === 'Button'),
        'the tooltip contains no icon, price control, purchase button, or bundle interaction');
    assert.equal(item.tip.hittest, false); assert.equal(item.tip.hittestchildren, false);
    assert.equal(item.surface.hittest, false); assert.equal(item.surface.hittestchildren, false);
    const staleLayout = h.scheduled.slice(start).find(value => value.delay === 0).fn;
    item.card.events.onmouseout();
    assert(!item.tip.BHasClass('Visible'), 'source leave hides synchronously');
    assert.equal([...h.jobs.values()].filter(value => value.delay === 0).length, 0);
    staleLayout(); h.advance(.5);
    assert(!item.tip.BHasClass('Visible'), 'a captured layout callback cannot revive a hidden tooltip');
    assert.equal(h.checkoutCount(), 0); assert.equal(h.requests.length, 0);
    h.dispose(item);
    staleLayout();
    assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().owners, 0);
    assert.equal(h.jobs.size, 0);
});

test('Entering a scaled tooltip dismisses, blocks redisplay, and rearms only after physical exit', () => {
    const h = harness({nativeScale: .75, fitScale: .5}), first = h.bind(), second = h.bind({}, {y: 400});
    h.hover(first); h.advance(0);
    const tipBounds = first.surface.GetPositionWithinWindow();
    h.setCursor([tipBounds.x + first.surface.actuallayoutwidth * h.fitScale + 8, tipBounds.y + 8]);
    h.advance(.031);
    assert(first.tip.BHasClass('Visible'), 'the unscaled layout envelope must not falsely count as tooltip pixels');
    h.setCursor([tipBounds.x + first.surface.actuallayoutwidth * h.fitScale - 2, tipBounds.y + 8]);
    h.advance(.031);
    assert(!first.tip.BHasClass('Visible'), 'passive geometry uses the CSS Fit-scaled surface');
    first.card.events.onmouseover(); second.card.events.onmouseover(); h.advance(.2);
    assert(!first.tip.BHasClass('Visible')); assert(!second.tip.BHasClass('Visible'));
    h.inside(first.card); first.card.events.onmouseover();
    assert(!first.tip.BHasClass('Visible'), 'returning directly to the source does not rearm');
    const source = first.card.GetPositionWithinWindow();
    const sourceRight = source.x + first.card.actuallayoutwidth * h.fitScale;
    assert(sourceRight < tipBounds.x, 'fixture leaves a physical gap between source and tooltip');
    h.setCursor([(sourceRight + tipBounds.x) / 2, source.y + 8]); h.advance(.04);
    assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().blocked, false);
    h.hover(first); assert(first.tip.BHasClass('Visible'));
    first.tip.events.onmouseover();
    assert(!first.tip.BHasClass('Visible'), 'tooltip input events use the same immediate dismissal');
    first.card.events.onmouseover(); h.advance(0);
    assert(!first.tip.BHasClass('Visible'));
    h.setCursor([1900, 1000]); h.advance(.04); h.hover(first);
    first.surface.events.onmouseover();
    assert(!first.tip.BHasClass('Visible'), 'the shared surface handler also dismisses immediately');
    h.dispose(first, second);
    assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().owners, 0); assert.equal(h.jobs.size, 0);
});

test('Switching cards leaves one tooltip and preserves the independent market purchase action', () => {
    const h = harness(), first = h.bind(), second = h.bind({}, {y: 400});
    h.hover(first);
    const staleLayout = h.scheduled.find(value => value.delay === 0).fn;
    h.hover(second);
    assert(!first.tip.BHasClass('Visible')); assert(second.tip.BHasClass('Visible'));
    assert.equal([...h.jobs.values()].filter(value => value.delay === 0).length, 1);
    staleLayout(); h.advance(0);
    assert(!first.tip.BHasClass('Visible')); assert(second.tip.BHasClass('Visible'));
    second.card.events.onactivate();
    assert.equal(h.checkoutCount(), 0, 'market row inspection never checks out');
    assert.strictEqual(second.buy.events.onactivate, second.purchase, 'binding info does not replace the row purchase callback');
    second.buy.events.onactivate(); assert.equal(h.checkoutCount(), 1);
    second.card.events.onmouseout(); assert(!second.tip.BHasClass('Visible'), 'clicking does not pin');
    h.dispose(first, second);
    assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().owners, 0); assert.equal(h.requests.length, 0);
});

test('Quality uses authoritative identity and rejects a shared placeholder or mixed bundle inference', () => {
    const h = harness();
    const id = 'lottery_heaven_reaching_tower_seal';
    assert.equal(h.cfg.SurvivalItemArt.Lookup({item_id: id}).quality.toLowerCase(), 'ur', 'the real catalog maps 通天塔印 to UR');
    const cases = [
        [{quality: 'ssr'}, [], 'SSR'],
        [{item_id: id}, [], 'UR'],
        [{}, [{kind: 'item', id}], 'UR'],
        [{title: '通天塔印 · 永久', icon: 'custom_game/archive_items_v2/' + id + '.png'}, [], 'UR'],
        [{title: '无关科技', icon: 'custom_game/archive_items_v2/lottery_attribute_crystal.png'}, [], '未配置'],
        [{title: '名字不一致', icon: 'custom_game/archive_items_v2/' + id + '.png'}, [], '未配置'],
        [{quality: 'legendary'}, [], '未配置'],
        [{product_type: 'bundle'}, [{kind: 'item', id}], '未配置'],
        [{product_type: 'bundle', quality: 'ur'}, [{kind: 'item', id}], 'UR']
    ];
    for (const [item, rewards, expected] of cases) {
        const entry = h.bind(item, {rewards});
        assert.equal(h.find(entry.tip, 'RCPurpleDetailQuality').text, '品级：' + expected);
        h.dispose(entry);
    }
    assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().owners, 0);
});

test('Bundles show plain text effects and the compact fallback keeps its existing card action', () => {
    const h = harness(), rewards = [{kind: 'item', id: 'a', label: '道具甲', description: '攻击力 +20'},
        {kind: 'item', id: 'b', label: '道具乙', quantity: 3}];
    const bundle = h.bind({product_type: 'bundle', bundle_reviewed: true}, {rewards});
    const effect = h.find(bundle.tip, 'RCProductEffect');
    assert.equal(effect.text, '道具甲：攻击力 +20\n道具乙 ×3');
    assert.equal(h.descendants(bundle.tip).filter(node => node.paneltype === 'Label').length, 3);
    assert(!h.descendants(bundle.tip).some(node => node.events.onactivate), 'bundle contents have no nested interaction');
    h.hover(bundle); assert.equal(h.checkoutCount(), 0);
    h.dispose(bundle);
    h.setCursor([1900, 1000]); h.advance(.04);
    const fallback = h.bind({}, {market: false});
    h.hover(fallback); assert.equal(h.checkoutCount(), 0, 'hover is informational on the fallback path too');
    fallback.card.events.onactivate(); assert.equal(h.checkoutCount(), 1);
    h.dispose(fallback); assert.equal(h.cfg.SurvivalTooltipDismiss.Inspect().owners, 0);
    assert.equal(h.requests.length, 0);
});
