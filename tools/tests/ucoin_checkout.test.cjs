const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const test = require('node:test');

const addon = path.resolve(__dirname, '../..');
const scripts = path.join(addon, 'panorama/src/scripts/custom_game');
function harness() {
    const requests = [], subscriptions = new Map(), timers = [], urls = [];
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
    $.RegisterEventHandler = $.RegisterForUnhandledEvent = $.Msg = () => {};
    $.DispatchEvent = (name, url) => { if (name === 'ExternalBrowserGoToURL') urls.push(url); };
    const context = vm.createContext({$, GameUI: {CustomUIConfig: () => cfg},
        Game: {GetLocalPlayerID: () => 0, IsInToolsMode: () => false, GetGameTime: () => 1},
        GameEvents: {Subscribe(name, fn) { const list = subscriptions.get(name) || []; list.push(fn); subscriptions.set(name, list); return fn; },
            Unsubscribe(fn) { for (const [name, list] of subscriptions) subscriptions.set(name, list.filter(v => v !== fn)); },
            SendCustomGameEventToServer(name, payload) { requests.push({name, payload}); }},
        CustomNetTables: {GetTableValue: () => null}});
    // Use the actual confirmation controls and event wiring with the current V10 shell.
    const stack = [root], xml = fs.readFileSync(path.join(addon, 'panorama/src/layout/custom_game/payment_test.xml'), 'utf8');
    for (const tag of xml.matchAll(/<(\/?)(Panel|Button|Label|Image|TextEntry)\b([^>]*)>/g)) {
        if (tag[1]) { stack.pop(); continue; }
        const attrs = Object.fromEntries([...tag[3].matchAll(/([\w-]+)="([^"]*)"/g)].map(x => [x[1], x[2]]));
        const node = new Panel(tag[2], stack.at(-1), attrs.id);
        (attrs.class || '').split(/\s+/).filter(Boolean).forEach(c => node.AddClass(c));
        if (attrs.text) node.text = attrs.text;
        if (attrs.enabled) node.enabled = attrs.enabled !== 'false';
        if (attrs.onactivate) node.events.onactivate = () => vm.runInContext(attrs.onactivate, context);
        if (!tag[3].endsWith('/')) stack.push(node);
    }
    const load = file => vm.runInContext(fs.readFileSync(path.join(scripts, file), 'utf8'), context, {filename: file});
    ['common/ui_registry.js', 'common/ui_components.js', 'ui_layers.js', 'remaining_5d5c1152eb.js',
        'archive_v10_data.js', 'common/menu_v10.js', 'common/commerce_components.js',
        'commerce_wallet.js', 'payment_test.js', 'commerce_remaining_5d5c1152eb.js'].forEach(load);
    function emit(name, data) { for (const fn of subscriptions.get(name) || []) fn(JSON.parse(JSON.stringify(data))); }
    const lastRequest = name => requests.findLast(r => r.name === name);
    function paymentReply(data, request = lastRequest('survival_payment_request')) {
        assert(request);
        emit('survival_payment_result', {action: request.payload.action, request_id: request.payload.request_id, ...data});
    }
    const categories = [{id:'technology',label:'科技'},{id:'points',label:'积分商品'},{id:'gold',label:'金币商品'},{id:'legacy',label:'人民币商品'}];
    function paidSnapshot(products, extra = {}) {
        cfg.SurvivalPayments.RefreshCatalog(true);
        assert.equal(lastRequest('survival_payment_request').payload.action, 'catalog');
        paymentReply({ok:1,catalog_hash:'live-v1',wechat:1,alipay:1,categories,products,...extra});
    }
    function walletSnapshot(products) {
        if (!lastRequest('survival_commerce_request')) cfg.SurvivalCommerceWallet.Refresh();
        const request = lastRequest('survival_commerce_request');
        assert.equal(request.payload.action, 'catalog');
        const base = {request_id:request.payload.request_id,action:'catalog',ok:1};
        emit('survival_commerce_result', {...base,part:'begin',count:products.length,categories,balances:{u_coin:0,shop_points:500,shop_gold:90}});
        products.forEach((product, i) => emit('survival_commerce_result', {...base,part:'product',index:i+1,product}));
        emit('survival_commerce_result', {...base,part:'end'});
    }
    const descendants = (p, cls) => [p, ...p.Children().flatMap(c => descendants(c, cls))].filter(n => !cls || n.BHasClass(cls));
    const menu = cls => cfg.SurvivalMenuV10.Entries().find(m => m.panel.BHasClass(cls));
    const store = () => menu('MenuV10Commerce');
    const cards = () => descendants(store().content, 'RCProduct');
    const buyCard = card => descendants(card.__purpleDetail, 'CommercePurpleBuy')[0].events.onactivate();
    function category(id) { store().sidebar.Children().find(p => p.id.endsWith('Section_' + id)).events.onactivate(); }
    return {cfg, context, root, $, requests, timers, urls, emit, paidSnapshot, walletSnapshot, paymentReply, lastRequest, descendants, menu, store, cards, buyCard, category};
}
function walletItem(currency, sku = 'u_item') {
    return {sku,title:'测试道具',category_id:currency === 'shop_points'?'points':currency === 'shop_gold'?'gold':'technology',
        product_type:'single',icon:'custom_game/archive_items_v2/lottery_attribute_crystal.png',
        currency,currency_name:currency === 'u_coin'?'U币':currency === 'shop_points'?'积分':'金币',
        purchase_method:'wallet',price:1200,enabled:0,owned:99,disabled_reason:'commerce_balance_insufficient',
        description:'初始木材 +200',reward_lines:[{kind:'stat',id:'initial_wood',label:'初始木材',quantity:200}]};
}
function paidItem(extra = {}) {
    return {...walletItem('u_coin'),enabled:1,owned:0,disabled_reason:'',purchase_method:'cash',
        u_coin_price:1200,u_coin_per_yuan:1000,amount_fen:120,...extra};
}
function orderFrom(product, extra = {}) {
    return {...product,ok:1,provider:'wechat',state:'pending',order_id:'WX'+'1'.repeat(30),
        checkout_url:'https://pay.xiaofengnet.com/checkout?order=WX'+'1'.repeat(30)+'&token='+'a'.repeat(64),
        qr_matrix:Array(29).fill('0'.repeat(29)).join('|'),...extra};
}

test('U币 SKU is deduplicated and cash eligibility overrides an empty wallet balance', () => {
    const h = harness(); h.cfg.SurvivalCommerceView.Open();
    h.walletSnapshot([walletItem('u_coin')]); h.paidSnapshot([paidItem()]);
    assert.equal(h.cfg.SurvivalCommerceView.Inspect().productCount, 1);
    const card = h.cards()[0], labels = h.descendants(card.__purpleDetail).map(p => p.text);
    assert(labels.includes('1200 U币 / ¥1.20'));
    assert(labels.includes('1元=1000U币 · 直接购买道具'));
    assert(labels.includes('查看 / 购买'), 'The payment row overrides wallet insufficient funds and ownership');
    assert(!h.descendants(h.root).some(p => /充值暂未开放/.test(p.text || '')));
    h.buyCard(card);
    assert.equal(h.cfg.SurvivalCommerceView.IsOpen(), false);
    assert(h.cfg.SurvivalUI.ModalManager.Get('payment_shop').IsOpen());
    assert.equal(h.$('#PaymentPrice').text, '1200 U币 / ¥1.20，1元=1000U币');
    assert.equal(h.$('#PaymentBuyLabel').text, '微信购买 1200 U币');
    assert.equal(h.$('#PaymentBuy').enabled, true);
    assert.equal(h.requests.filter(r => r.payload.action === 'create' || r.payload.action === 'purchase').length, 0);
    h.context.PaymentBuy(); h.context.PaymentBuy();
    const create = h.lastRequest('survival_payment_request');
    assert.equal(create.payload.sku, 'u_item'); assert.equal(create.payload.provider, 'wechat');
    assert.deepEqual(Object.keys(create.payload).sort(), ['action','provider','request_id','sku']);
    assert.equal(h.requests.filter(r => r.payload.action === 'purchase').length, 0);
    assert.equal(h.requests.filter(r => r.payload.action === 'create').length, 1);
});

test('U币 products need an authenticated enabled payment row and valid U币 metadata', () => {
    const h = harness(); h.cfg.SurvivalCommerceView.Open(); h.walletSnapshot([walletItem('u_coin')]);
    let card = h.cards()[0];
    assert(h.descendants(card.__purpleDetail).some(p => p.text === '连接支付目录'));
    assert(h.descendants(card.__purpleDetail).some(p => p.text === '1200 U币 / 人民币金额待同步'));
    assert(!h.descendants(card.__purpleDetail).some(p => /¥/.test(p.text || '')), 'A wallet row cannot invent the payable RMB amount');
    h.buyCard(card); assert.equal(h.cfg.SurvivalCommerceView.IsOpen(), true);
    h.paidSnapshot([], {catalog_hash:'ready-empty'}); card = h.cards()[0];
    assert(h.descendants(card.__purpleDetail).some(p => p.text === '人民币购买尚未开放'));
    h.buyCard(card); assert.equal(h.cfg.SurvivalCommerceView.IsOpen(), true);
    h.paidSnapshot([paidItem({enabled:0,owned:1,disabled_reason:'already_owned'})]);
    card = h.cards()[0]; assert(h.descendants(card.__purpleDetail).some(p => p.text === '已拥有 · 查看'));
    h.buyCard(card); assert.equal(h.$('#PaymentBuy').enabled, false); h.context.PaymentBuy();
    assert.equal(h.requests.filter(r => r.payload.action === 'create').length, 0);
    h.paidSnapshot([paidItem({enabled:'0',owned:0})]); assert.equal(h.$('#PaymentBuy').enabled, false);
    h.paidSnapshot([paidItem({u_coin_per_yuan:undefined})]); assert.equal(h.$('#PaymentBuy').enabled, false);
    h.context.PaymentBuy(); assert.equal(h.requests.filter(r => r.payload.action === 'create').length, 0);
});

test('积分 and 商城金币 retain wallet confirmation while legacy cash retains RMB display', () => {
    const h = harness(); h.cfg.SurvivalCommerceView.Open();
    const points = {...walletItem('shop_points','points_item'),price:20,enabled:1,owned:0,disabled_reason:''};
    const gold = {...walletItem('shop_gold','gold_item'),price:10,enabled:1,owned:0,disabled_reason:''};
    h.walletSnapshot([points,gold]);
    h.paidSnapshot([{sku:'legacy_cash',title:'原人民币礼包',category_id:'legacy',product_type:'single',amount_fen:777,enabled:1,owned:0,reward_lines:[]}]);
    assert.equal(h.cfg.SurvivalCommerceView.Inspect().productCount, 3);
    for (const [category, sku] of [['points','points_item'],['gold','gold_item']]) {
        h.cfg.SurvivalCommerceView.Open(); h.walletSnapshot([points,gold]); h.category(category); h.buyCard(h.cards()[0]);
        const exchange = h.menu('MenuV10Exchange'); assert(exchange.IsOpen());
        h.descendants(exchange.actions, 'CommerceConfirmBuy')[0].events.onactivate();
        const request = h.lastRequest('survival_commerce_request');
        assert.equal(request.payload.sku, sku); assert.equal(request.payload.action, 'purchase');
        const currency = category === 'points'?'shop_points':'shop_gold';
        h.emit('survival_commerce_result', {request_id:request.payload.request_id,action:'purchase',ok:1,terminal:1,sku,currency,balance:400});
        assert.equal(h.cfg.SurvivalCommercePending, null);
    }
    h.cfg.SurvivalCommerceView.Open(); h.category('legacy'); h.buyCard(h.cards()[0]);
    assert.equal(h.$('#PaymentPrice').text, '¥7.77');
    assert.equal(h.$('#PaymentBuyLabel').text, '微信购买 ¥7.77');
    h.context.PaymentChannel('alipay'); assert.equal(h.$('#PaymentBuyLabel').text, '支付宝购买 ¥7.77');
    h.context.PaymentBuy();
    assert.equal(h.lastRequest('survival_payment_request').payload.sku, 'legacy_cash');
});

test('订单 retains authoritative U币 and RMB snapshot through catalog edits, delisting, cancellation, and delivery', () => {
    const h = harness(); h.cfg.SurvivalCommerceView.Open(); h.paidSnapshot([paidItem()]);
    h.buyCard(h.cards()[0]); h.context.PaymentBuy(); h.paymentReply(orderFrom(paidItem()));
    assert.equal(h.$('#PaymentQR').style.visibility, 'visible');
    h.paidSnapshot([paidItem({u_coin_price:2400,amount_fen:240,title:'新道具标题'})]);
    assert.equal(h.$('#PaymentPrice').text, '1200 U币 / ¥1.20，1元=1000U币');
    assert.equal(h.$('#PaymentBuyLabel').text, '微信购买 1200 U币');
    assert.equal(h.$('#PaymentTitle').text, '测试道具');
    h.paidSnapshot([]); assert.equal(h.$('#PaymentProducts').Children().length, 1);
    assert.equal(h.$('#PaymentPrice').text, '1200 U币 / ¥1.20，1元=1000U币');
    h.context.PaymentCancel(); assert.equal(h.lastRequest('survival_payment_request').payload.action, 'cancel');
    h.paymentReply(orderFrom(paidItem(), {state:'closed'}));
    h.paidSnapshot([paidItem({u_coin_price:2400,amount_fen:240})]);
    h.context.PaymentChannel('alipay'); h.context.PaymentBuy();
    assert.equal(h.lastRequest('survival_payment_request').payload.provider, 'alipay');
    assert.deepEqual(Object.keys(h.lastRequest('survival_payment_request').payload).sort(), ['action','provider','request_id','sku']);
    h.paymentReply(orderFrom(paidItem({u_coin_price:2400,amount_fen:240}), {provider:'alipay',state:'delivered'}));
    assert.equal(h.$('#PaymentPrice').text, '2400 U币 / ¥2.40，1元=1000U币');
    assert.match(h.$('#PaymentStatus').text, /支付成功/); assert.equal(h.$('#PaymentQR').style.visibility, 'collapse');
    assert.equal(h.cfg.SurvivalPayments.Inspect().dirty, true, 'Delivery refreshes catalog ownership through the original cache');
});

test('U币 purchase buttons stay short for both channels while the full RMB price remains above', () => {
    for (const [coin,fen,rmb] of [[1200,120,'1.20'],[29800,2980,'29.80']]) {
        const h = harness(), product = paidItem({u_coin_price:coin,amount_fen:fen});
        h.cfg.SurvivalCommerceView.Open(); h.paidSnapshot([product]); h.buyCard(h.cards()[0]);
        for (const [provider,label] of [['wechat','微信'],['alipay','支付宝']]) {
            h.context.PaymentChannel(provider);
            assert.equal(h.$('#PaymentBuyLabel').text, label+'购买 '+coin+' U币');
            assert(!/¥|1元=|\//.test(h.$('#PaymentBuyLabel').text));
            assert.equal(h.$('#PaymentPrice').text, coin+' U币 / ¥'+rmb+'，1元=1000U币');
            assert.equal(h.$('#PaymentBuy').enabled, true);
        }
        h.context.PaymentBuy(); h.paymentReply(orderFrom(product,{provider:'alipay'}));
        h.paidSnapshot([paidItem({u_coin_price:56000,amount_fen:5600})]);
        assert.equal(h.$('#PaymentBuyLabel').text, '支付宝购买 '+coin+' U币', 'A pending order retains its provider and U币 snapshot');
        assert.equal(h.$('#PaymentPrice').text, coin+' U币 / ¥'+rmb+'，1元=1000U币');
        h.context.PaymentCancel(); h.paymentReply(orderFrom(product,{provider:'alipay',state:'closed'}));
        h.context.PaymentChannel('wechat');
        assert.equal(h.$('#PaymentBuyLabel').text, '微信购买 56000 U币');
        assert.equal(h.$('#PaymentPrice').text, '56000 U币 / ¥56.00，1元=1000U币');
    }
});

test('A consistent U币 price refresh rebuilds product details and unknown checkout never selects another SKU', () => {
    const h = harness(); h.cfg.SurvivalCommerceView.Open(); h.paidSnapshot([paidItem()]);
    const first = h.cards()[0];
    h.paidSnapshot([paidItem({u_coin_price:2400,amount_fen:240})]);
    assert.notEqual(h.cards()[0], first);
    assert(h.descendants(h.cards()[0].__purpleDetail).some(p => p.text === '2400 U币 / ¥2.40'));
    h.cfg.SurvivalPayments.Checkout('u_item');
    assert.equal(h.$('#PaymentPrice').text, '2400 U币 / ¥2.40，1元=1000U币');
    assert.equal(h.$('#PaymentBuy').enabled, true);
    h.cfg.SurvivalPayments.Checkout('missing_sku'); h.paidSnapshot([paidItem()]);
    assert.equal(h.$('#PaymentBuy').enabled, false); h.context.PaymentBuy();
    assert.equal(h.requests.filter(r => r.payload.action === 'create').length, 0);
});

test('Inconsistent U币 metadata cannot quote a payable amount or create an order', () => {
    const invalid = [
        {u_coin_price:2400}, {u_coin_per_yuan:2000}, {u_coin_per_yuan:undefined},
        {u_coin_price:0}, {u_coin_price:-1200}, {u_coin_price:1200.5}, {u_coin_price:'1200'},
        {amount_fen:0}, {amount_fen:-120}, {amount_fen:120.5}, {amount_fen:'120'},
        {u_coin_price:10000010,amount_fen:1000001},
    ];
    for (const mergedWallet of [false,true]) for (const metadata of invalid) {
        const h = harness(); h.cfg.SurvivalCommerceView.Open();
        if (mergedWallet) h.walletSnapshot([walletItem('u_coin')]);
        h.paidSnapshot([paidItem(metadata)]);
        const card = h.cards()[0];
        assert(h.descendants(card.__purpleDetail).some(p => p.text === '人民币购买尚未开放'));
        assert(!h.descendants(card.__purpleDetail).some(p => /¥/.test(p.text || '')), JSON.stringify(metadata));
        h.buyCard(card); assert.equal(h.cfg.SurvivalCommerceView.IsOpen(), true);
        h.paidSnapshot([paidItem(metadata)]); // Finish the refresh requested by the disabled shop action.
        h.cfg.SurvivalPayments.Checkout('u_item');
        assert.equal(h.cfg.SurvivalPayments.Inspect().pending, '');
        assert.equal(h.$('#PaymentBuy').enabled, false);
        assert(!/¥/.test(h.$('#PaymentPrice').text)); assert(!/¥/.test(h.$('#PaymentBuyLabel').text));
        h.context.PaymentBuy();
        assert.equal(h.requests.filter(r => r.payload.action === 'create').length, 0);
    }
});

test('Wallet metadata cannot complete an incomplete authoritative payment row', () => {
    const h = harness(); h.cfg.SurvivalCommerceView.Open();
    h.walletSnapshot([{...walletItem('u_coin'),amount_fen:120,u_coin_price:1200,u_coin_per_yuan:1000}]);
    assert(h.descendants(h.cards()[0].__purpleDetail).some(p => p.text === '1200 U币 / 人民币金额待同步'));
    const incomplete = paidItem({currency:undefined,u_coin_price:undefined,u_coin_per_yuan:undefined});
    h.paidSnapshot([incomplete]);
    assert(!h.descendants(h.cards()[0].__purpleDetail).some(p => /¥/.test(p.text || '')));
    h.cfg.SurvivalPayments.Checkout('u_item');
    assert.equal(h.$('#PaymentPrice').text, 'U币价格及人民币金额待同步');
    assert.equal(h.$('#PaymentBuy').enabled, false); h.context.PaymentBuy();
    assert.equal(h.requests.filter(r => r.payload.action === 'create').length, 0);
});

test('Malformed U币 orders retain status polling and cancellation while payment entry points await valid metadata', () => {
    for (const state of ['created','pending']) {
        const h = harness(); h.cfg.SurvivalCommerceView.Open(); h.paidSnapshot([paidItem()]);
        h.buyCard(h.cards()[0]); h.context.PaymentBuy();
        const badOrder = orderFrom(paidItem({u_coin_price:2400}), {state});
        h.paymentReply(badOrder);
        assert.equal(h.$('#PaymentPrice').text, 'U币价格及人民币金额待同步');
        assert.match(h.$('#PaymentBuyLabel').text, /待同步/);
        assert(!/¥/.test(h.$('#PaymentBuyLabel').text)); assert.equal(h.$('#PaymentBuy').enabled, false);
        assert.equal(h.$('#PaymentQR').style.visibility, 'collapse');
        assert.equal(h.$('#PaymentOpen').style.visibility, 'collapse');
        h.context.PaymentOpen(); assert.equal(h.urls.length, 0);
        h.context.PaymentBuy(); assert.equal(h.requests.filter(r => r.payload.action === 'create').length, 1);
        h.timers.find(t => t.delay === 5).fn();
        assert.equal(h.lastRequest('survival_payment_request').payload.action, 'status');
        h.paymentReply(badOrder);
        h.context.PaymentRefresh(); assert.equal(h.lastRequest('survival_payment_request').payload.action, 'status');
        h.paymentReply(orderFrom(paidItem()));
        assert.equal(h.$('#PaymentPrice').text, '1200 U币 / ¥1.20，1元=1000U币');
        assert.equal(h.$('#PaymentQR').style.visibility, 'visible');
        h.context.PaymentOpen(); assert.equal(h.urls.length, 1);
        h.context.PaymentCancel(); assert.equal(h.lastRequest('survival_payment_request').payload.action, 'cancel');
        h.paymentReply(orderFrom(paidItem(), {state:'closed'}));
        h.context.PaymentBuy(); assert.equal(h.requests.filter(r => r.payload.action === 'create').length, 2);
        h.paymentReply(orderFrom(paidItem({u_coin_price:2400}), {state:'delivered'}));
        assert.equal(h.$('#PaymentPrice').text, 'U币价格及人民币金额待同步');
        assert.match(h.$('#PaymentStatus').text, /支付成功/);
    }
});
