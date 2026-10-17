'use strict';

// Exercise the real presentation consumers with frozen legacy server snapshots.
// No account, payment gateway, purchase, server, or generated bundle is changed.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const ROOT = path.resolve(__dirname, '../..');
const SCRIPTS = path.join(ROOT, 'panorama/src/scripts/custom_game');
const readJSON = file => JSON.parse(fs.readFileSync(path.join(ROOT, file), 'utf8'));

function freeze(value) {
    if (value && typeof value === 'object' && !Object.isFrozen(value)) {
        Object.values(value).forEach(freeze);
        Object.freeze(value);
    }
    return value;
}

function readCSV(file) {
    const input = fs.readFileSync(path.join(ROOT, file), 'utf8').replace(/^\uFEFF/, '');
    const lines = []; let fields = [], value = '', quoted = false;
    for (let i = 0; i <= input.length; i++) {
        const c = input[i];
        if (c === '"') {
            if (quoted && input[i + 1] === '"') { value += '"'; i++; }
            else quoted = !quoted;
        } else if (!quoted && (c === ',' || c === '\n' || c === undefined)) {
            fields.push(value.replace(/\r$/, '')); value = '';
            if (c !== ',') { if (fields.some(Boolean)) lines.push(fields); fields = []; }
        } else value += c;
    }
    const header = lines.shift();
    return lines.filter(row => !row[0].startsWith('#'))
        .map(row => Object.fromEntries(header.map((key, i) => [key, row[i] || ''])));
}

function harness() {
    const nodes = new Map(), panels = [], handlers = new Map(), requests = [], timers = [];
    class Panel {
        constructor(type, parent = null, id = '') {
            this.paneltype = type; this.id = id; this.parent = parent;
            this.children = []; this.classes = new Set(); this.events = {};
            this.style = {}; this.enabled = true; this.visible = true; this.text = '';
            panels.push(this); if (id) nodes.set(id, this); if (parent) parent.children.push(this);
        }
        IsValid() { return !this.deleted; }
        AddClass(value) { value.split(/\s+/).forEach(v => this.classes.add(v)); }
        RemoveClass(value) { this.classes.delete(value); }
        BHasClass(value) { return this.classes.has(value); }
        SetHasClass(value, on) { on ? this.AddClass(value) : this.RemoveClass(value); }
        Children() { return this.children; }
        GetParent() { return this.parent; }
        SetParent(parent) {
            if (this.parent) this.parent.children = this.parent.children.filter(c => c !== this);
            this.parent = parent; if (parent) parent.children.push(this);
        }
        SetPanelEvent(name, fn) { this.events[name] = fn; }
        SetImage(value) { this.image = value; }
        SetScaling() {}
        SetFocus() {}
        SetAcceptsFocus() {}
        RemoveAndDeleteChildren() { this.children.slice().forEach(c => c.DeleteAsync()); }
        DeleteAsync() { this.RemoveAndDeleteChildren(); this.deleted = true; this.SetParent(null); }
    }
    const root = new Panel('Panel', null, 'Root');
    function $(selector) {
        const id = selector.replace(/^#/, '');
        return nodes.get(id) || new Panel('Panel', root, id);
    }
    $.GetContextPanel = () => root;
    $.CreatePanel = (type, parent, id) => new Panel(type, parent, id);
    $.Schedule = (delay, fn) => { timers.push({delay, fn}); return timers.length; };
    $.CancelScheduled = $.DispatchEvent = $.Msg = () => {};
    const cfg = {RemainingHandoff: {}};
    const modal = () => ({Open() {}, Close() {}, Dispose() {}});
    cfg.SurvivalUI = {
        ModalShell: {Adopt: modal},
        ActionButton(parent, props) {
            const button = new Panel('Button', parent);
            button.events.onactivate = props.action;
            return button;
        }
    };
    cfg.SurvivalMenuV10 = {
        Adopt(props) {
            return {...modal(), shell: {}, content: new Panel('Panel', props.panel),
                actions: new Panel('Panel', props.panel), SetSidebar() {}, SetResources() {}};
        }
    };
    const context = vm.createContext({$, GameUI: {CustomUIConfig: () => cfg},
        GameEvents: {
            Subscribe(name, fn) { const list = handlers.get(name) || []; list.push(fn); handlers.set(name, list); return fn; },
            Unsubscribe(fn) { for (const [name, list] of handlers) handlers.set(name, list.filter(f => f !== fn)); },
            SendCustomGameEventToServer(name, body) { requests.push({name, body}); }
        }});
    const load = file => vm.runInContext(fs.readFileSync(path.join(SCRIPTS, file), 'utf8'), context, {filename: file});
    load('common/commerce_components.js');
    const emit = (name, body) => { for (const fn of handlers.get(name) || []) fn(body); };
    return {cfg, $, nodes, panels, context, load, emit, requests, timers};
}

test('V1–V10 medals agree across canonical archive data, CSV, icons, and generated display catalogs', () => {
    const archive = readJSON('data/archive/vip_rewards_20261003.json').rewards;
    const csv = readCSV('data/csv/存档系统/archive_vip_rewards.csv');
    const icons = readJSON('data/ui/item_resources.json').items;
    const bundles = readJSON('data/ui/video_shop_bundles_20261015.json').products;
    const h = harness(); h.load('vip_catalog.js'); h.load('video_shop_bundles.js');
    const fields = ['tower_critical_chance_pct', 'tower_final_damage_bonus_pct', 'hero_final_damage_bonus_pct',
        'hero_critical_chance_pct', 'hero_attribute_bonus_pct'];
    const tiers = [1, 1.2, 1.4, 1.6, 1.8, 2, 2.5, 3, 4, 5];
    for (let level = 1; level <= 10; level++) {
        const suffix = String(level).padStart(2, '0'), id = 'vip_medal_' + suffix, name = '孤城V' + level + '勋章';
        for (const rows of [archive, h.cfg.VIPRewardCatalog.rewards]) {
            const medal = rows.find(row => row.reward_id === id);
            assert.equal(medal.display_name, name);
            assert.deepEqual(Array.from(medal.effect_ids), fields);
            assert.deepEqual(Array.from(medal.effect_values).map(Number), fields.map(() => tiers[level - 1]));
            assert.equal(rows.find(row => row.reward_id === 'vip_package_' + suffix).medal_id, id);
        }
        const row = csv.find(row => row.reward_id === id);
        assert.equal(row.display_name, name);
        assert.deepEqual(row.effect_ids.split('|'), fields);
        assert.deepEqual(row.effect_values.split('|').map(Number), fields.map(() => tiers[level - 1]));
        assert.equal(icons.find(row => row.id === id).name, name);
        for (const rows of [bundles, h.cfg.VideoShopBundleCatalog.products]) {
            const bundle = rows.find(row => row.sku === 'video_bundle_vip_' + suffix);
            assert.equal(bundle.reward_lines.find(row => row.id === id).label, name + '·永久');
            assert(bundle.description.includes(name + '·永久'));
            assert(!/僵尸岛V(?:10|[1-9])勋章/.test(bundle.description));
        }
    }
});

test('Shared display normalizer supports legacy V1–V10 while preserving unrelated names and stable identifiers', () => {
    const h = harness(), names = h.cfg.SurvivalCommerceComponents.RewardNameText;
    assert.equal(typeof names, 'function');
    for (let level = 1; level <= 10; level++) {
        assert.equal(names('僵尸岛V' + level + '勋章·永久 ×1'), '孤城V' + level + '勋章·永久 ×1');
        assert.equal(names('VIP' + level + '勋章'), '孤城V' + level + '勋章');
    }
    const retained = 'VIP11勋章 僵尸岛V11勋章 VIP100勋章 VIP1权限 V1特权礼包 vip_medal_01';
    assert.equal(names(retained), retained);
    assert.equal(names('孤城V1勋章；孤城V10勋章'), '孤城V1勋章；孤城V10勋章');
    assert.equal(names(null), ''); assert.equal(names(undefined), '');
});

function legacyProduct(level = 1) {
    const suffix = String(level).padStart(2, '0');
    return {sku: 'video_bundle_vip_' + suffix, title: 'V' + level + '专属特惠礼包',
        category_id: 'bundles', product_type: 'bundle', purchase_method: 'cash',
        amount_fen: 192, u_coin_price: 1920, u_coin_per_yuan: 1000, enabled: 1, owned: 0,
        purchase_limit: 1, description: '僵尸岛V' + level + '勋章·永久 ×1\n英雄最终伤害+1%',
        reward_lines: [{kind: 'vip_reward', id: 'vip_medal_' + suffix, quantity: 1, label: 'VIP' + level + '勋章'}]};
}

test('Actual payment quote and saved receipt render canonical names without mutating server prices, IDs, or description', () => {
    for (const level of [1, 10]) {
        const h = harness(); h.load('payment_test.js');
        const product = freeze(legacyProduct(level)), original = JSON.stringify(product);
        const payload = freeze({ok: true, action: 'catalog', wechat: 1, alipay: 1, products: [product]});
        h.emit('survival_payment_result', payload);
        h.cfg.SurvivalPayments.Checkout(product.sku);
        assert(h.$('#PaymentDescription').text.includes('孤城V' + level + '勋章'));
        assert(h.$('#PaymentValues').text.includes('孤城V' + level + '勋章'));
        assert.equal(h.$('#PaymentPrice').text, '合计 1920 U币 / ¥1.92');
        assert.equal(JSON.stringify(product), original);
        assert.equal(h.cfg.SurvivalPayments.GetCatalog().products[0], product);
        assert.equal(h.requests.filter(row => row.body.action === 'create').length, 0);
        const order = freeze({...product, ok: true, action: 'status', state: 'delivered',
            order_id: 'WX' + '1'.repeat(30), effects: {hero_final_damage_bonus_pct: 1},
            effect_changes: {hero_final_damage_bonus_pct: {before: 0, after: 1, delta: 1}}});
        const saved = JSON.stringify(order);
        h.emit('survival_payment_result', order);
        assert(h.$('#PaymentDescription').text.includes('孤城V' + level + '勋章'));
        assert(h.$('#PaymentValues').text.includes('孤城V' + level + '勋章'));
        assert.equal(h.$('#PaymentPrice').text, '合计 1920 U币 / ¥1.92');
        assert.equal(JSON.stringify(order), saved);
        assert.equal(JSON.stringify(product), original);
        assert.equal(h.requests.filter(row => row.body.action === 'create' || row.body.action === 'purchase').length, 0);
    }
});

test('Actual wallet confirmation normalizes legacy display text and retains HTML escaping and authoritative data', () => {
    const h = harness(); h.load('commerce_wallet.js');
    const product = freeze({...legacyProduct(1), sku: 'legacy_medal_points', currency: 'shop_points',
        purchase_method: 'wallet', price: 6800, description: '僵尸岛V1勋章 & <b>VIP10勋章</b>\n英雄最终伤害+1%'});
    const original = JSON.stringify(product);
    h.cfg.SurvivalCommerceWallet.Refresh();
    const request = h.requests.at(-1).body;
    const base = {ok: 1, action: 'catalog', request_id: request.request_id};
    h.emit('survival_commerce_result', {...base, part: 'begin', count: 1, balances: {shop_points: 10000}, categories: []});
    h.emit('survival_commerce_result', {...base, part: 'product', index: 1, product});
    h.emit('survival_commerce_result', {...base, part: 'end'});
    assert(h.cfg.SurvivalCommerceWallet.Checkout(product.sku));
    const copy = h.panels.find(row => row.BHasClass('CommerceConfirmCopy'));
    assert(copy.text.includes('孤城V1勋章 &amp; &lt;b&gt;孤城V10勋章&lt;/b&gt;<br>'));
    assert(copy.text.includes('售价：6800 商城积分'));
    assert(!copy.text.includes('僵尸岛'));
    assert.equal(h.cfg.SurvivalCommerceWallet.GetCatalog().products[0], product);
    assert.equal(JSON.stringify(product), original);
    assert.equal(h.requests.filter(row => row.body.action === 'purchase').length, 0);
});
