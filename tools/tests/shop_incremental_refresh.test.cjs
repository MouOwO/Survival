const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const test = require('node:test');

// Load complete production controllers, never extracted private functions.
// Counters count every setter call, including writes of the existing value.
const project = path.resolve(__dirname, '../..');
const scriptDirectory = path.join(project, 'panorama/src/scripts/custom_game');
const hud = fs.readFileSync(path.join(project, 'panorama/src/layout/custom_game/survival_hud.xml'), 'utf8');
const manifest = fs.readFileSync(path.join(project, 'panorama/src/layout/custom_game/custom_ui_manifest.xml'), 'utf8');
const shopScript = 'shop_remaining_5d5c1152eb.js';
assert(manifest.includes('/survival_hud.xml"'), 'the root manifest must load this HUD');
assert(hud.includes('/' + shopScript + '"'), 'test the shop controller used by the real HUD');
const scripts = ['common/ui_registry.js', 'common/ui_components.js', 'ui_layers.js',
    'remaining_5d5c1152eb.js', 'shop_tooltip_remaining_5d5c1152eb.js', shopScript];
const sources = new Map(scripts.map(name => [name, fs.readFileSync(path.join(scriptDirectory, name), 'utf8')]));

function harness() {
    const counts = {created: 0, deleted: 0, cleared: 0, text: 0, style: 0, classes: 0,
        properties: 0, images: 0, events: 0, priceUpdates: 0, tooltipUpdates: 0, tooltipHides: 0};
    const nodes = new Map(), subscriptions = new Map(), timers = new Map(), requests = [];
    const netTables = new Map(), netListeners = new Map();
    let timerSerial = 0, now = 100, latest = 0, current = null;
    class Panel {
        constructor(type, parent, id = '') {
            this.paneltype = type; this.id = id; this.parent = parent;
            this.children = []; this.classes = new Set(); this.events = {}; this.attrs = {};
            this.deleted = false;
            this.style = new Proxy({}, {set(target, key, value) {
                counts.style++; target[key] = value; return true;
            }});
            for (const key of ['visible', 'enabled', 'hittest', 'hittestchildren', 'itemname', 'abilityname']) {
                let value = ['visible', 'enabled'].includes(key) ? true : undefined;
                Object.defineProperty(this, key, {get: () => value, set(next) {
                    counts.properties++; value = next;
                }});
            }
            counts.created++;
            if (parent) parent.children.push(this);
            if (id) nodes.set(id, this);
        }
        get text() { return this._text || ''; }
        set text(value) { counts.text++; this._text = value; }
        IsValid() { return !this.deleted; }
        AddClass(name) { counts.classes++; this.classes.add(name); }
        RemoveClass(name) { counts.classes++; this.classes.delete(name); }
        SetHasClass(name, value) { value ? this.AddClass(name) : this.RemoveClass(name); }
        BHasClass(name) { return this.classes.has(name); }
        GetParent() { return this.parent; }
        GetChildCount() { return this.children.length; }
        GetChild(index) { return this.children[index]; }
        Children() { return this.children; }
        FindChildTraverse(id) {
            if (this.id === id) return this;
            for (const child of this.children) {
                const found = child.FindChildTraverse(id);
                if (found) return found;
            }
            return null;
        }
        SetPanelEvent(name, callback) { counts.events++; this.events[name] = callback; }
        SetAttributeString(key, value) { this.attrs[key] = value; }
        GetAttributeString(key, fallback) { return this.attrs[key] === undefined ? fallback : this.attrs[key]; }
        SetImage(value) { counts.images++; this.image = value; }
        SetScaling(value) { this.scaling = value; }
        SetAcceptsFocus() {}
        SetFocus() {}
        GetPositionWithinWindow() { return {x: 16, y: 240}; }
        RemoveAndDeleteChildren() {
            counts.cleared++;
            this.children.slice().forEach(child => child.DeleteAsync());
        }
        DeleteAsync() {
            if (this.deleted) return;
            this.children.slice().forEach(child => child.DeleteAsync());
            this.deleted = true; counts.deleted++;
            if (this.parent) this.parent.children = this.parent.children.filter(child => child !== this);
            if (nodes.get(this.id) === this) nodes.delete(this.id);
        }
    }
    const root = new Panel('Panel', null, 'TestHUD');
    root.actuallayoutwidth = 1920; root.actuallayoutheight = 1080;
    // Preserve the actual XML hierarchy, including each cost label's wrapper.
    const stack = [root];
    for (const token of hud.replace(/<!--[\s\S]*?-->/g, '').matchAll(/<\/?([\w]+)\b([^>]*?)(\/?)>/g)) {
        if (token[0].startsWith('</')) { if (stack.length > 1) stack.pop(); continue; }
        const attributes = Object.fromEntries([...token[2].matchAll(/([\w]+)="([^"]*)"/g)].map(match => [match[1], match[2]]));
        const panel = new Panel(token[1], stack.at(-1), attributes.id || '');
        if (attributes.class) attributes.class.split(/\s+/).forEach(name => panel.classes.add(name));
        if (attributes.text !== undefined) panel.text = attributes.text;
        if (!token[3]) stack.push(panel);
    }
    const cfg = {};
    function $(id) { return nodes.get(id.slice(1)); }
    $.GetContextPanel = () => root;
    $.CreatePanel = (type, parent, id) => new Panel(type, parent, id);
    $.DispatchEvent = () => {};
    $.Msg = () => {};
    $.RegisterEventHandler = () => {};
    $.RegisterForUnhandledEvent = () => {};
    $.Schedule = (delay, callback) => { const id = ++timerSerial; timers.set(id, {delay, callback}); return id; };
    $.CancelScheduled = id => timers.delete(id);
    const env = vm.createContext({$, GameUI: {CustomUIConfig: () => cfg},
        Game: {GetGameTime: () => now, GetLocalPlayerID: () => 0},
        GameEvents: {Subscribe(name, callback) {
            const listeners = subscriptions.get(name) || [];
            listeners.push(callback); subscriptions.set(name, listeners); return callback;
        }, Unsubscribe() {}, SendCustomGameEventToServer(name, payload) { requests.push({name, payload}); }},
        CustomNetTables: {GetTableValue: (table, key) => netTables.get(table + ':' + key) || {},
            SubscribeNetTableListener(table, callback) {
                const listeners = netListeners.get(table) || [];
                listeners.push(callback); netListeners.set(table, listeners); return callback;
            }, UnsubscribeNetTableListener() {}}
    });
    for (const name of scripts) vm.runInContext(sources.get(name), env, {filename: name});
    for (const [object, key, counter] of [[cfg.RemainingHandoff, 'UpdateShopPrices', 'priceUpdates'],
        [cfg.SurvivalShopTooltip, 'UpdateEntry', 'tooltipUpdates'], [cfg.SurvivalShopTooltip, 'Hide', 'tooltipHides']]) {
        const original = object[key];
        object[key] = function (...args) { counts[counter]++; return original.apply(this, args); };
    }
    const clone = value => JSON.parse(JSON.stringify(value));
    function emit(name, payload) { for (const listener of subscriptions.get(name) || []) listener(clone(payload)); }
    function full(overrides = {}) {
        current = {...(current || {ui_mode: 'shop', entries: [], categories: [], resources: {wood: 1000, gold: 1000}}),
            ...overrides, sequence: ++latest, full: 1};
        emit('ui_shop_snapshot', current);
        return latest;
    }
    function delta(overrides = {}) {
        const payload = {...overrides, ui_mode: overrides.ui_mode || current.ui_mode,
            sequence: ++latest, base_sequence: latest - 1, full: 0};
        const entries = new Map(current.entries.map(row => [row.entry_id, row]));
        for (const id of overrides.removed_entry_ids || []) entries.delete(id);
        for (const row of overrides.changed_entries || []) entries.set(row.entry_id, row);
        current = {...current, ...payload, entries: [...entries.values()]};
        emit('ui_shop_snapshot', payload);
        return latest;
    }
    function reset() { for (const key of Object.keys(counts)) counts[key] = 0; }
    function cards() { return nodes.get('ShopItemList').children.filter(panel => panel.BHasClass('ShopShelfSlot')); }
    function card(id) { return cards().find(panel => panel.GetAttributeString('entry_id', '') === id); }
    function runTimers(delay) {
        for (const [id, timer] of [...timers]) if (timer.delay === delay) { timers.delete(id); timer.callback(); }
    }
    function setTable(table, key, value) {
        netTables.set(table + ':' + key, clone(value));
        for (const callback of netListeners.get(table) || []) callback(table, key, clone(value));
    }
    cfg.SurvivalShop.SetUnlocks({shop: true, research: true});
    runTimers(0.29);
    reset();
    return {cfg, nodes, counts, requests, emit, full, delta, reset, cards, card, runTimers, setTable,
        timerCount(delay) { return [...timers.values()].filter(timer => timer.delay === delay).length; },
        setTime(value) { now = value; }, get sequence() { return latest; }, get data() { return current; }};
}

function item(overrides = {}) {
    return {entry_id: 'sword', visible: 1, purchasable: 1, content_type: 'weapon',
        content_id: 'weapon_growth_sword_01', shop_id: 'equipment', sort_order: 1,
        name: '成长之剑', description: '攻击力 +10', icon: 'item_broadsword', gold_cost: 200,
        wood_cost: 0, stock: 3, stock_max: 5, ...overrides};
}
function technology(overrides = {}) {
    return item({entry_id: 'attack', content_type: 'technology', content_id: 'attack_1',
        technology_group: 'attack', technology_level: 1, level_text: 'Lv.1',
        purchase_entry_id: 'attack_2', prerequisite_met: 1, resource_check_on_cast: 1,
        name: '攻击科技', stock: 0, stock_max: 0, ...overrides});
}
function assertNoDOM(h, message) {
    assert.deepEqual(h.counts, Object.fromEntries(Object.keys(h.counts).map(key => [key, 0])), message);
}
function assertNoRebuild(h, message) {
    for (const key of ['created', 'deleted', 'cleared', 'images', 'tooltipHides']) assert.equal(h.counts[key], 0, message + ': ' + key);
}
function purchaseRequests(h) { return h.requests.filter(request => request.name === 'ui_shop_purchase_request'); }

test('1000 advancing closed snapshots cache data without building or warming hidden DOM', () => {
    const h = harness();
    for (let index = 0; index < 1000; index++) h.full({entries: [item({name: '最新商品 ' + index})], resources: {wood: index, gold: index * 2}});
    assertNoDOM(h, 'closed snapshots must not write labels, styles, classes, images, tooltips or cards');
    assert.equal(h.cards().length, 0);
    h.cfg.SurvivalShop.Open();
    assert.equal(h.requests.at(-1).payload.known_sequence, 1000);
    assert.equal(h.cards().length, 1, 'Open immediately paints the last cached snapshot before a server reply');
    h.card('sword').events.onmouseover();
    assert.equal(h.nodes.get('ShopTooltipTitle').text, '最新商品 999');
    assert.match(h.nodes.get('ShopResourceSummary').text, /999.*1998/);
});

test('1000 advancing identical open snapshots retain cards and the active tooltip with zero repeated DOM setters', () => {
    const h = harness(); h.cfg.SurvivalShop.Open();
    const row = item(); h.full({entries: [row], categories: [{shopid: 'equipment', shopname: '装备', order: 1}]});
    const original = h.card('sword'); original.events.onmouseover();
    h.runTimers(0); h.runTimers(0.03); h.reset();
    for (let index = 0; index < 1000; index++) h.full({entries: [{...row}], reason: 'periodic_' + index});
    assert(h.card('sword') === original, 'identical snapshots retain the original card');
    assert.equal(h.cfg.SurvivalShopTooltip.Inspect().entry, 'sword');
    assertNoDOM(h, 'fresh sequences and transport reasons do not invalidate unchanged presentation');
    // A transport serializer may produce the same row with another key order.
    h.full({entries: [Object.fromEntries(Object.entries(row).reverse())]});
    assertNoDOM(h, 'object property order is not a visible change');
});

test('wallet-only full and delta snapshots update the resource text without rebuilding cards or redrawing tooltips', () => {
    const h = harness(); h.cfg.SurvivalShop.Open(); h.full({entries: [item()]});
    const original = h.card('sword'); original.events.onmouseover(); h.reset();
    h.full({resources: {wood: 7, gold: 8}});
    assert.match(h.nodes.get('ShopResourceSummary').text, /7.*8/);
    assertNoRebuild(h, 'wallet-only full snapshot');
    assert.equal(h.counts.tooltipUpdates, 0, 'an unchanged tooltip row is not redrawn for wallet values');
    h.reset(); h.delta({resources: {wood: 9, gold: 10}});
    assert.match(h.nodes.get('ShopResourceSummary').text, /9.*10/);
    assert(h.card('sword') === original, 'wallet-only delta keeps the original card'); assertNoRebuild(h, 'wallet-only delta');
    assert.equal(h.counts.tooltipUpdates, 0);
    h.full({entries: [item({purchasable: 0, disabled_reason_code: 'insufficient_gold', disabled_reason: '金币不足'})]});
    assert(h.card('sword') === original, 'affordability changes keep the original card');
    assert(original.BHasClass('Unavailable')); assert(original.BHasClass('ResourceLocked'));
    assert.equal(h.cfg.SurvivalShopTooltip.Inspect().purchaseEnabled, false, 'server affordability changes reach the open tooltip');
    const before = purchaseRequests(h).length; h.cfg.SurvivalShop.PurchaseEntry('sword');
    assert.equal(purchaseRequests(h).length, before);
    assert.match(h.nodes.get('ShopStatus').text, /金币不足/);
});

test('stock and repeat-purchase availability update existing cards in full and delta snapshots', () => {
    const h = harness(); h.cfg.SurvivalShop.Open(); h.full({entries: [item()]});
    const original = h.card('sword'); h.reset();
    h.full({entries: [item({stock: 0, purchasable: 0, disabled_reason_code: 'stock_empty'})]});
    assert(h.card('sword') === original, 'stock is state, so changing it keeps the tile');
    assert(original.BHasClass('StockEmpty')); assert.equal(original.__survivalStockLabel.text, '0/5');
    assert.equal(original.__survivalStockLabel.visible, false); assertNoRebuild(h, 'stock update');
    h.delta({changed_entries: [item({stock: 1})]});
    assert(h.card('sword') === original, 'stock delta keeps the original card'); assert(!original.BHasClass('StockEmpty'));
    assert.equal(original.__survivalStockLabel.text, '1/5');
    h.full({entries: [item({stock: 0, stock_max: 0, purchase_limit: 5, owned_count: 5,
        purchasable: 0, disabled_reason_code: 'purchase_limit_reached'})]});
    assert(h.card('sword').BHasClass('StockEmpty'));
    h.delta({changed_entries: [item({stock: 0, stock_max: 0, purchase_limit: 5, owned_count: 4})]});
    assert(!h.card('sword').BHasClass('StockEmpty')); assert.equal(h.card('sword').__survivalStockLabel.text, '1/5');
});

test('name, technology level and tooltip costs/effects update without discarding the same card', () => {
    const h = harness(); h.cfg.SurvivalShop.OpenResearch(123);
    h.full({ui_mode: 'research', research_source_entindex: 123, entries: [technology()]});
    const original = h.card('attack'); original.events.onmouseover();
    h.full({entries: [technology({name: '攻击科技 Lv.2', technology_level: 2, level_text: 'Lv.2',
        description: '攻击力 +20', gold_cost: 300, wood_cost: 40, purchase_entry_id: 'attack_3'})]});
    assert(h.card('attack') === original, 'changing a display name or level keeps the card');
    const byClass = name => {
        function search(panel) {
            if (panel.BHasClass(name)) return panel;
            for (const child of panel.children) { const found = search(child); if (found) return found; }
            return null;
        }
        return search(original);
    };
    assert.equal(byClass('ShopTechnologyLevel').text, 'Lv.2');
    assert.equal(byClass('ShopCardName').text, '攻击科技 Lv.2');
    assert.equal(h.nodes.get('ShopTooltipTitle').text, '攻击科技 Lv.2');
    assert.equal(h.nodes.get('ShopTooltipDescription').text, '攻击力 +20');
    assert.equal(h.nodes.get('ShopTooltipGoldCost').text, '300');
    assert.equal(h.nodes.get('ShopTooltipWoodCost').text, '40');
    h.delta({changed_entries: [technology({name: '攻击科技 Lv.3', technology_level: 3, level_text: 'Lv.3',
        description: '攻击力 +30', gold_cost: 400, wood_cost: 50, purchase_entry_id: 'attack_4'})]});
    assert(h.card('attack') === original, 'the same dynamic changes work through delta snapshots');
    assert.equal(byClass('ShopTechnologyLevel').text, 'Lv.3');
    assert.equal(h.nodes.get('ShopTooltipDescription').text, '攻击力 +30');
    h.nodes.get('ShopTooltipPurchase').events.onactivate();
    assert.equal(purchaseRequests(h).at(-1).payload.entry_id, 'attack_4', 'the retained tooltip purchases the latest row');
});

test('visibility, added/removed rows and category changes are immediately reflected', () => {
    const h = harness(); h.cfg.SurvivalShop.Open(); h.full({entries: [item()]});
    h.delta({changed_entries: [item({visible: 0})]});
    assert.equal(h.cards().length, 0, 'a delta can hide a row without changing its name or icon');
    h.delta({changed_entries: [item(), item({entry_id: 'shield', name: '护甲', sort_order: 2})]});
    assert.deepEqual(h.cards().map(card => card.GetAttributeString('entry_id', '')), ['sword', 'shield']);
    h.delta({removed_entry_ids: ['sword']}); assert.equal(h.cards().length, 1);
    h.full({entries: [item({entry_id: 'shield', shop_id: 'item', category_id: 'item', name: '护甲'})],
        categories: [{shopid: 'item', shopname: '其他', order: 1}]});
    assert.equal(h.cards().length, 0, 'a changed category removes the item from equipment');
    h.cfg.SurvivalShop.SelectOther(); assert.equal(h.cards().length, 1);
    assert.equal(h.card('shield').GetAttributeString('entry_id', ''), 'shield');
    h.full({entries: []}); assert.equal(h.cards().length, 0, 'an empty full snapshot removes existing rows');
});

test('prerequisites, research queue routing and purchase rejection remain live', () => {
    const h = harness(); h.cfg.SurvivalShop.OpenResearch(123);
    h.full({ui_mode: 'research', research_source_entindex: 123, entries: [technology({prerequisite_met: 0,
        purchasable: 0, disabled_reason_code: 'prerequisite_not_met', prerequisite_required_level: 2})]});
    const original = h.card('attack'); original.events.onmouseover();
    assert(original.BHasClass('PrerequisiteLocked')); assert.equal(original.__survivalLockBadge.text, '前置 Lv.2');
    assert.equal(h.cfg.SurvivalShopTooltip.Inspect().purchaseEnabled, false);
    h.cfg.SurvivalShop.PurchaseEntry('attack'); assert.equal(purchaseRequests(h).length, 0);
    h.delta({changed_entries: [technology({purchasable: 0, disabled_reason_code: 'research_queue_full',
        purchase_entry_id: 'attack_3', research_queue_count: 4, auto_research_available: 1, auto_research_enabled: 1})],
        technology_cooldown_remaining: 30, technology_cooldown_total: 30,
        technology_cooldown_until: 130, technology_cooldown_source_group: 'attack'});
    assert(h.card('attack') === original, 'prerequisite/queue changes keep the research card'); assert(!original.BHasClass('PrerequisiteLocked'));
    assert(!original.BHasClass('ResourceLocked')); assert(!original.BHasClass('PurchaseCooldownLocked'));
    assert(original.BHasClass('AutoResearchActive')); assert(original.__survivalCooldownMask.visible);
    assert.equal(h.cfg.SurvivalShopTooltip.Inspect().purchaseEnabled, true);
    h.cfg.SurvivalShop.PurchaseEntry('attack');
    assert.equal(purchaseRequests(h).at(-1).payload.entry_id, 'attack_3');
    assert.equal(purchaseRequests(h).at(-1).payload.source_entindex, 123);
    h.cfg.SurvivalShop.PurchaseEntry('attack'); assert.equal(purchaseRequests(h).length, 1, 'duplicate in-flight research stays blocked');
    h.emit('ui_operation_result', {operation: 'shop_purchase', success: 0, error: '队列已满'});
    assert.match(h.nodes.get('ShopStatus').text, /队列已满/); assert(h.nodes.get('ShopStatus').BHasClass('error'));
    h.cfg.SurvivalShop.PurchaseEntry('attack'); assert.equal(purchaseRequests(h).length, 2, 'a rejection releases the pending guard immediately');
    h.emit('ui_operation_result', {operation: 'shop_purchase', success: 1});
    h.cfg.SurvivalShop.OpenResearch(456);
    h.full({research_source_entindex: 456, entries: [technology({purchase_entry_id: 'attack_4'})]});
    h.cfg.SurvivalShop.PurchaseEntry('attack');
    assert.equal(purchaseRequests(h).at(-1).payload.entry_id, 'attack_4');
    assert.equal(purchaseRequests(h).at(-1).payload.source_entindex, 456, 'the latest authoritative research source is retained');
    h.delta({changed_entries: [technology({completed: 1})]});
    assert.equal(h.cards().length, 0, 'completed technologies disappear immediately');
});

test('early-final cooldown keeps its card, animates, blocks purchases and refreshes once at expiry', () => {
    const h = harness(); h.cfg.SurvivalShop.SelectOther();
    const early = item({entry_id: 'early', content_type: 'service', content_id: 'service_early_final_boss',
        shop_id: 'item', stock: 0, stock_max: 0, early_final_cooldown_remaining: 60,
        early_final_cooldown_total: 60, early_final_cooldown_until: 160});
    h.full({entries: [early]}); const original = h.card('early'), mask = original.__survivalCooldownMask;
    assert(mask.visible); assert.match(mask.style.clip, /360\.00deg/);
    h.cfg.SurvivalShop.PurchaseEntry('early'); assert.equal(purchaseRequests(h).length, 0);
    h.setTime(130); h.runTimers(0.05); assert.match(mask.style.clip, /180\.00deg/);
    h.delta({changed_entries: [{...early, early_final_cooldown_remaining: 20, early_final_cooldown_until: 150}]});
    assert(h.card('early') === original, 'a changed cooldown keeps its card'); assert(mask.visible);
    assert.match(mask.style.clip, /120\.00deg/, 'a changed cooldown uses the latest deadline immediately');
    const before = h.requests.length;
    h.setTime(150); h.runTimers(0.05); assert.equal(mask.visible, false);
    assert.equal(h.requests.length, before + 1); assert.equal(h.requests.at(-1).name, 'ui_shop_open_request');
    h.runTimers(0.05); assert.equal(h.requests.length, before + 1, 'expiry does not repeatedly request a snapshot');
    h.cfg.SurvivalShop.PurchaseEntry('early'); assert.equal(purchaseRequests(h).length, 1);
});

test('closed deltas render their latest cache on reopen, and stale/base-mismatched messages cannot overwrite it', () => {
    const h = harness(); h.cfg.SurvivalShop.Open(); h.full({entries: [item()]});
    h.cfg.SurvivalShop.Close(); h.runTimers(0.29); h.reset();
    h.delta({changed_entries: [item({name: '闭窗更新', stock: 1})], resources: {wood: 111, gold: 222}});
    assertNoDOM(h, 'closed deltas are cached without rendering the old hidden cards');
    const latest = h.sequence;
    h.emit('ui_shop_snapshot', {sequence: latest - 1, full: 1, ui_mode: 'research',
        research_source_entindex: 999, entries: [], resources: {gold: 9999}});
    assertNoDOM(h, 'a stale sequence causes no DOM work or mode/source changes');
    h.cfg.SurvivalShop.Open(); assert.equal(h.requests.at(-1).payload.known_sequence, latest);
    assert.equal(h.requests.at(-1).payload.mode, 'shop');
    assert.equal(h.requests.at(-1).payload.source_entindex, -1);
    assert.equal(h.card('sword').__survivalStockLabel.text, '1/5');
    assert.match(h.nodes.get('ShopResourceSummary').text, /111.*222/);
    h.card('sword').events.onmouseover(); assert.equal(h.nodes.get('ShopTooltipTitle').text, '闭窗更新');
    const original = h.card('sword'), before = h.requests.length;
    h.emit('ui_shop_snapshot', {sequence: latest + 1, base_sequence: latest - 1, full: 0,
        ui_mode: 'shop', removed_entry_ids: ['sword'], resources: {gold: 9999}});
    assert(h.card('sword') === original, 'a mismatched delta base keeps existing cards'); assert.match(h.nodes.get('ShopResourceSummary').text, /222/);
    assert.equal(h.requests.length, before + 1, 'a missing delta base requests an authoritative snapshot');
    assert.equal(h.requests.at(-1).payload.known_sequence, latest, 'a rejected delta does not advance the sequence');
});

test('closed Refresh is idle, repeated Open merges an in-flight request, and a rejected open can retry', () => {
    const h = harness();
    h.cfg.SurvivalShop.Refresh(); assert.equal(h.requests.length, 0, 'Refresh cannot wake the closed shop');
    assertNoDOM(h, 'closed Refresh leaves DOM alone');
    h.cfg.SurvivalShop.Open(); assert.equal(h.requests.length, 1);
    h.reset();
    for (let index = 0; index < 1000; index++) h.cfg.SurvivalShop.Open();
    assert.equal(h.requests.length, 1, 'repeated opens share the unresolved request');
    assertNoDOM(h, 'repeated opens do not reset the drawer or status');
    h.emit('ui_operation_result', {operation: 'shop_open', success: 0, error: '来源无效'});
    assert.match(h.nodes.get('ShopStatus').text, /来源无效/);
    h.cfg.SurvivalShop.Open(); assert.equal(h.requests.length, 2, 'a rejected open releases its request guard');
    h.full({entries: [item()]}); assert.equal(h.cards().length, 1);
    assert(!h.nodes.get('ShopStatus').BHasClass('error'), 'the successful reply clears an open error');
});

test('an old mode or research-source response cannot replace the currently requested context', () => {
    const h = harness(); h.cfg.SurvivalShop.OpenResearch(123); h.cfg.SurvivalShop.OpenResearch(456); h.reset();
    h.emit('ui_shop_snapshot', {sequence: 500, full: 1, ui_mode: 'research', research_source_entindex: 123,
        entries: [technology({name: '过时研究所'})], categories: [], resources: {gold: 9999}});
    assertNoDOM(h, 'a delayed response from the previous research source cannot paint the active drawer');
    h.full({ui_mode: 'research', research_source_entindex: 456, entries: [technology()], resources: {gold: 22}});
    assert.equal(h.cards().length, 1, 'an ignored foreign-context response must not advance the active sequence');
    h.cfg.SurvivalShop.PurchaseEntry('attack'); assert.equal(purchaseRequests(h).at(-1).payload.source_entindex, 456);
    h.cfg.SurvivalShop.OpenChallenge(); h.reset();
    h.emit('ui_shop_snapshot', {sequence: 501, full: 1, ui_mode: 'research', research_source_entindex: 456,
        entries: [technology()], categories: [], resources: {gold: 9999}});
    assertNoDOM(h, 'an old research response cannot switch an opened challenge drawer back to research');
    h.full({ui_mode: 'challenge', entries: [item({entry_id: 'challenge', content_type: 'challenge'})], resources: {gold: 33}});
    assert.equal(h.cfg.SurvivalShop.Inspect().mode, 'challenge'); assert(h.card('challenge'));
});

test('research cooldown fields survive a resource-only delta and resume after Close/Open with the same snapshot', () => {
    const h = harness(); h.cfg.SurvivalShop.OpenResearch(123);
    h.full({ui_mode: 'research', research_source_entindex: 123, entries: [technology()],
        technology_cooldown_remaining: 60, technology_cooldown_total: 60,
        technology_cooldown_until: 160, technology_cooldown_source_group: 'attack'});
    const original = h.card('attack');
    h.delta({resources: {wood: 4, gold: 5}});
    assert(original.__survivalCooldownMask.visible, 'omitted cooldown fields in a delta preserve the active cooldown');
    h.cfg.SurvivalShop.Close(); h.runTimers(0.29); h.reset(); h.runTimers(0.05);
    assertNoDOM(h, 'a cancelled cooldown callback cannot update the closed drawer');
    h.cfg.SurvivalShop.OpenResearch(123); h.full();
    h.setTime(130); h.runTimers(0.05);
    assert(h.card('attack') === original, 'reopen retains the cached research card');
    assert.match(original.__survivalCooldownMask.style.clip, /180\.00deg/, 'reopening restarts one animation for the cached cooldown');
});

test('an empty shelf is stable through repeated snapshots, Close and reopen', () => {
    const h = harness(); h.cfg.SurvivalShop.Open(); h.full({entries: []});
    const list = h.nodes.get('ShopItemList');
    assert.equal(list.children.length, 1); assert(list.children[0].BHasClass('ShopEmptyLabel'));
    const label = list.children[0]; h.reset();
    for (let index = 0; index < 1000; index++) h.full({entries: []});
    assertNoDOM(h, 'identical empty snapshots do not reconstruct the placeholder');
    h.cfg.SurvivalShop.Close(); h.runTimers(0.29); h.full({entries: []}); h.cfg.SurvivalShop.Open();
    assert.equal(list.children.length, 1); assert(list.children[0] === label, 'reopen retains the empty placeholder');
    h.full({entries: [item()]}); assert.equal(h.cards().length, 1);
    assert(!list.children.some(panel => panel.BHasClass('ShopEmptyLabel')));
});

test('reported cooldown remainders do not redraw unchanged cards; a changed deadline updates only its mask', () => {
    const h = harness(); h.cfg.SurvivalShop.OpenResearch(123);
    h.full({ui_mode: 'research', research_source_entindex: 123, entries: [technology()],
        technology_cooldown_remaining: 60, technology_cooldown_total: 60,
        technology_cooldown_until: 160, technology_cooldown_source_group: 'attack'});
    const original = h.card('attack'); original.events.onmouseover();
    const activeTimers = h.timerCount(0.05); h.reset();
    for (let index = 0; index < 1000; index++) h.full({technology_cooldown_remaining: 60 - index / 1000});
    assertNoDOM(h, 'the same absolute deadline owns the local countdown');
    assert.equal(h.timerCount(0.05), activeTimers, 'unchanged deadlines do not spawn extra animation callbacks');
    h.delta({technology_cooldown_remaining: 30, technology_cooldown_until: 130});
    assert(h.card('attack') === original); assert.match(original.__survivalCooldownMask.style.clip, /180\.00deg/);
    assertNoRebuild(h, 'a deadline-only delta'); assert.equal(h.counts.tooltipUpdates, 0);
    h.delta({technology_cooldown_remaining: 0, technology_cooldown_until: 0, technology_cooldown_source_group: ''});
    assert.equal(original.__survivalCooldownMask.visible, false, 'an authoritative cooldown clear applies immediately');
});

test('repeated automatic book nettable messages do no DOM work, and closed changes apply on reopen', () => {
    const h = harness(); h.cfg.SurvivalShop.SelectOther();
    h.full({entries: [item({entry_id: 'shop_item_knowledge_book', content_type: 'item',
        content_id: 'item_knowledge_book', shop_id: 'item'})]});
    const original = h.card('shop_item_knowledge_book'); original.events.onmouseover();
    const button = original.children.find(panel => panel.BHasClass('AutoBookButton'));
    assert(button); assert(!button.BHasClass('AutoBookEnabled'));
    h.setTable('survival_shop_config', 'auto_purchase_0', {shop_item_knowledge_book: 1});
    assert(button.BHasClass('AutoBookEnabled')); assert.equal(button.GetChild(0).text, '自动 ✓');
    assert(h.nodes.get('ShopTooltipAutoPurchase').BHasClass('AutoBookEnabled'));
    h.reset();
    for (let index = 0; index < 1000; index++) h.setTable('survival_shop_config', 'auto_purchase_0', {shop_item_knowledge_book: 1});
    assertNoDOM(h, 'the same automatic-purchase state does not redraw either button or tooltip');
    h.setTable('survival_shop_config', 'auto_purchase_1', {shop_item_knowledge_book: 0});
    assertNoDOM(h, 'another player\'s automatic-purchase state is ignored');
    h.cfg.SurvivalShop.Close(); h.runTimers(0.29); h.reset();
    h.setTable('survival_shop_config', 'auto_purchase_0', {shop_item_knowledge_book: 0});
    assertNoDOM(h, 'closed nettable changes do not update hidden book buttons');
    h.cfg.SurvivalShop.SelectOther();
    assert(h.card('shop_item_knowledge_book') === original); assert(!button.BHasClass('AutoBookEnabled'));
    assert.equal(button.GetChild(0).text, '自动');
    original.events.onmouseover(); assert(!h.nodes.get('ShopTooltipAutoPurchase').BHasClass('AutoBookEnabled'));
    h.nodes.get('ShopTooltipAutoPurchase').events.onactivate();
    assert.equal(h.requests.at(-1).name, 'ui_shop_auto_purchase_toggle_request');
    assert.equal(h.requests.at(-1).payload.entry_id, 'shop_item_knowledge_book');
});

test('a stale open rejection cannot overwrite either a newer in-flight request or its successful response', () => {
    const h = harness(); h.cfg.SurvivalShop.OpenResearch(123);
    const oldRequest = h.requests.at(-1).payload.request_id;
    h.cfg.SurvivalShop.OpenResearch(456);
    const newRequest = h.requests.at(-1).payload.request_id;
    assert.notEqual(oldRequest, newRequest); h.reset();
    h.emit('ui_operation_result', {operation: 'shop_open', request_id: oldRequest, success: 0, error: '过期失败'});
    assertNoDOM(h, 'the previous request cannot reject the current in-flight open');
    h.cfg.SurvivalShop.OpenResearch(456); assert.equal(h.requests.length, 2);
    h.full({ui_mode: 'research', research_source_entindex: 456, entries: [technology()]}); h.reset();
    h.emit('ui_operation_result', {operation: 'shop_open', request_id: oldRequest, success: 0, error: '过期失败'});
    assertNoDOM(h, 'a late rejection cannot replace the success status after the current snapshot arrives');
    assert(!h.nodes.get('ShopStatus').BHasClass('error'));
    h.cfg.SurvivalShop.OpenResearch(456); assert.equal(h.requests.length, 2, 'a stale failure does not enable an unnecessary retry');
});
