const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const test = require('node:test');

const scripts = path.resolve(__dirname, '../../panorama/src/scripts/custom_game');
function harness() {
    const requests = [], subscriptions = new Map(), timers = [], paidCheckouts = [];
    class Panel {
        constructor(type, parent, id = '') {
            this.paneltype = type; this.id = id; this.parent = null; this.children = [];
            this.style = {}; this.events = {}; this.classes = new Set(); this.attrs = {};
            this.visible = true; this.enabled = true; this.actualuiscale_x = this.actualuiscale_y = 1;
            this.SetParent(parent);
        }
        IsValid() { return !this.deleted; }
        AddClass(v) { this.classes.add(v); }
        RemoveClass(v) { this.classes.delete(v); }
        BHasClass(v) { return this.classes.has(v); }
        SetHasClass(v, on) { on ? this.AddClass(v) : this.RemoveClass(v); }
        GetParent() { return this.parent; }
        SetParent(parent) {
            if (this.parent) this.parent.children = this.parent.children.filter(c => c !== this);
            this.parent = parent; if (parent) parent.children.push(this);
        }
        Children() { return this.children; }
        GetChild(i) { return this.children[i]; }
        GetChildCount() { return this.children.length; }
        FindChildTraverse(id) { return this.id === id ? this : this.children.map(c => c.FindChildTraverse(id)).find(Boolean); }
        SetPanelEvent(name, fn) { this.events[name] = fn; }
        SetImage(uri) { this.image = uri; }
        SetScaling(v) { this.scaling = v; }
        SetFocus() {}
        SetAcceptsFocus() {}
        SetAttributeString(k, v) { this.attrs[k] = v; }
        GetAttributeString(k, fallback) { return this.attrs[k] === undefined ? fallback : this.attrs[k]; }
        GetPositionWithinWindow() { return {x: 450, y: 240}; }
        RemoveAndDeleteChildren() { this.children.slice().forEach(c => c.DeleteAsync()); }
        DeleteAsync() { this.children.slice().forEach(c => c.DeleteAsync()); this.deleted = true; this.SetParent(null); }
    }
    const root = new Panel('Panel', null, 'TestRoot');
    root.actuallayoutwidth = 1672; root.actuallayoutheight = 941;
    const cfg = {};
    function $(id) { return root.FindChildTraverse(id.replace(/^#/, '')); }
    $.GetContextPanel = () => root;
    $.CreatePanel = (type, parent, id) => new Panel(type, parent, id);
    $.Schedule = (delay, fn) => { const id = timers.length; timers.push({delay, fn}); return id; };
    $.CancelScheduled = id => { if (timers[id]) timers[id].cancelled = true; };
    $.RegisterEventHandler = $.RegisterForUnhandledEvent = $.DispatchEvent = $.Msg = () => {};
    const context = vm.createContext({$, GameUI: {CustomUIConfig: () => cfg},
        Game: {GetLocalPlayerID: () => 0, IsInToolsMode: () => false, GetGameTime: () => 1},
        GameEvents: {Subscribe(name, fn) { const list = subscriptions.get(name) || []; list.push(fn); subscriptions.set(name, list); return fn; },
            Unsubscribe(fn) { for (const [name, list] of subscriptions) subscriptions.set(name, list.filter(v => v !== fn)); },
            SendCustomGameEventToServer(name, payload) { requests.push({name, payload}); }},
        CustomNetTables: {GetTableValue: () => null}});
    const load = file => vm.runInContext(fs.readFileSync(path.join(scripts, file), 'utf8'), context, {filename: file});
    ['common/ui_registry.js', 'common/ui_components.js', 'ui_layers.js', 'remaining_5d5c1152eb.js',
        'archive_v10_data.js', 'common/menu_v10.js', 'common/commerce_components.js', 'commerce_wallet.js'].forEach(load);
    const paid = {products: [{sku:'paid_1',title:'真实商品',category_id:'paid',product_type:'single',icon:'items/rapier.png',
        enabled:true,amount_fen:900,reward_lines:[{id:'initial_gold',kind:'stat',label:'初始金币',quantity:10}]}],
        categories:[{id:'paid',label:'账号商品'}]};
    cfg.SurvivalPayments = {GetCatalog: () => paid, RefreshCatalog() {}, Checkout(sku) { paidCheckouts.push(sku); return true; }};
    load('commerce_remaining_5d5c1152eb.js');
    function emit(name, data) { for (const fn of subscriptions.get(name) || []) fn(JSON.parse(JSON.stringify(data))); }
    function walletSnapshot(products) {
        const request = requests.findLast(r => r.name === 'survival_commerce_request' && r.payload.action === 'catalog');
        assert(request, 'The existing catalog request must be used');
        const base = {request_id: request.payload.request_id, action:'catalog',ok:1};
        emit('survival_commerce_result', {...base,part:'begin',count:products.length,categories:[{id:'wallet',label:'积分商品'}],balances:{u_coin:12,shop_points:500,shop_gold:9}});
        products.forEach((product, i) => emit('survival_commerce_result', {...base,part:'product',index:i+1,product}));
        emit('survival_commerce_result', {...base,part:'end'});
    }
    const menus = () => cfg.SurvivalMenuV10.Entries();
    const store = () => menus().find(m => m.panel.BHasClass('MenuV10Commerce'));
    const cardList = () => store().content.Children()[0].Children();
    const descendants = (p, cls) => [p, ...p.Children().flatMap(c => descendants(c, cls))].filter(n => n.BHasClass(cls));
    return {cfg, root, requests, paidCheckouts, walletSnapshot, menus, store, cardList, descendants};
}
function walletItem(i) {
    return {sku:'wallet_'+i,title:'积分装备 '+i,category_id:'wallet',product_type:'single',icon:'items/rapier.png',
        enabled:1,owned:0,purchase_method:'wallet',currency:'shop_points',currency_name:'积分',price:10,
        purchase_limit:0,description:'攻击力 +10',reward_lines:[{id:'attack',kind:'stat',label:'攻击力',quantity:10}]};
}

test('Real catalogs share the V10 shell, paginate 24 units, and retain both purchase routes', () => {
    const h = harness();
    h.cfg.SurvivalCommerceView.Open();
    assert.equal(h.cfg.SurvivalCommerceView.Inspect().productCount, 1);
    h.walletSnapshot(Array.from({length:30}, (_, i) => walletItem(i)));
    const store = h.store();
    assert.equal(store.panel.style.width, '1672px');
    assert.equal(store.panel.style.height, '941px');
    assert.equal(h.cfg.SurvivalCommerceView.Inspect().productCount, 31);
    const walletTab = store.sidebar.Children().find(p => /Section_wallet$/.test(p.id));
    walletTab.events.onactivate();
    const firstCards = h.cardList();
    assert.equal(firstCards.length, 24);
    assert.notEqual(firstCards[0].style.position, firstCards[8].style.position, 'The ninth cell starts the second row');
    assert.equal(firstCards[0].__menuCell.namePanel.text, '积分装备 0');
    const next = h.descendants(store.actions, 'CJPageAction')[1]; next.events.onactivate();
    assert.equal(h.cardList().length, 6); assert.equal(h.cardList()[0].__menuCell.namePanel.text, '积分装备 24');
    const card = h.cardList()[0]; card.events.onmouseover();
    const tip = card.__purpleDetail; assert(tip.BHasClass('Visible'));
    const detailBody = h.descendants(tip, 'MenuV10CommerceDetailBody')[0];
    assert.deepEqual(detailBody.Children().map(p => [...p.classes][0]),
        ['RCPurpleDetailTitle','RCPurpleDetailQuality','RCProductEffect']);
    assert(detailBody.Children().every(p => p.paneltype === 'Label'), 'The tooltip contains only name, quality, and effect');
    assert.equal(detailBody.Children()[0].text, '积分装备 24');
    assert.equal(detailBody.Children()[1].text, '品级：未配置');
    assert.equal(detailBody.Children()[2].text, '攻击力 ×10');
    assert.equal(h.requests.filter(r => r.payload.action === 'purchase').length, 0, 'Hovering cannot purchase');
    (h.descendants(card, 'BLMarketBuy')[0] || card).events.onactivate();
    assert.equal(h.cfg.SurvivalCommerceView.IsOpen(), false);
    assert.equal(h.requests.filter(r => r.payload.action === 'purchase').length, 0, 'Inspecting the item only opens existing confirmation');
    const confirm = h.menus().find(m => m.panel.BHasClass('MenuV10Exchange'));
    assert(confirm && confirm.IsOpen(), 'Wallet checkout is inside the same V10 geometry');
    assert.match(h.descendants(confirm.content, 'CommerceConfirmCopy')[0].text, /售价：10 积分/);
    h.descendants(confirm.actions, 'CommerceConfirmBuy')[0].events.onactivate();
    const buy = h.requests.findLast(r => r.payload.action === 'purchase');
    assert.equal(buy.payload.sku, 'wallet_24');
    h.cfg.SurvivalCommerceView.Open();
    store.sidebar.Children().find(p => /Section_paid$/.test(p.id)).events.onactivate();
    const paidCard = h.cardList()[0];
    (h.descendants(paidCard, 'BLMarketBuy')[0] || paidCard).events.onactivate();
    assert.deepEqual(h.paidCheckouts, ['paid_1']);
    h.cfg.SurvivalCommerceView.Dispose();
    assert(!h.menus().some(m => m.panel.BHasClass('MenuV10Commerce')));
});
