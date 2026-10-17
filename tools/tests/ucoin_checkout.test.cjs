const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const test = require('node:test');

const addon = path.resolve(__dirname, '../..');
const scripts = path.join(addon, 'panorama/src/scripts/custom_game');
function harness({legacyXML = false} = {}) {
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
    const stack = [root], rawXML = fs.readFileSync(path.join(addon, 'panorama/src/layout/custom_game/payment_test.xml'), 'utf8');
    const xml = legacyXML ? rawXML.replace(/\s*<Label id="PaymentConsumptionNotice"[^>]*\/>/, '') : rawXML;
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
    ['common/item_resources.js', 'common/vip_badges.js', 'reward_presentation.js', 'common/ui_registry.js', 'common/ui_components.js', 'ui_layers.js', 'remaining_5d5c1152eb.js',
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
    const buyCard = card => {
        const button = descendants(card, 'BLMarketBuy')[0];
        return (button || card).events.onactivate();
    };
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
        u_coin_price:1200,u_coin_per_yuan:100,amount_fen:1200,...extra};
}
function orderFrom(product, extra = {}) {
    return {...product,ok:1,provider:'wechat',state:'pending',order_id:'WX'+'1'.repeat(30),
        checkout_url:'https://pay.xiaofengnet.com/checkout?order=WX'+'1'.repeat(30)+'&token='+'a'.repeat(64),
        qr_matrix:Array(29).fill('0'.repeat(29)).join('|'),...extra};
}
function rechargeItem(extra = {}) {
    return {sku:'u_coin_recharge',title:'U币充值',product_type:'recharge',purchase_method:'cash',
        amount_fen:100,unit_amount_fen:100,max_quantity:999999,recharge_u_coin_per_unit:100,enabled:1,
        reward_lines:[{kind:'wallet',id:'u_coin',label:'U币',quantity:100}],...extra};
}
function simpleDetail(h, card, title = '测试道具') {
    const nodes = h.descendants(card.__purpleDetail), labels = nodes.filter(p => p.paneltype === 'Label');
    assert.equal(labels.length, 3, 'The tooltip contains only name, quality, and effect');
    for (const cls of ['RCPurpleDetailTitle','RCPurpleDetailQuality','RCProductEffect'])
        assert.equal(labels.filter(p => p.BHasClass(cls)).length, 1, cls);
    assert.equal(labels.find(p => p.BHasClass('RCPurpleDetailTitle')).text, title);
    assert.equal(labels.find(p => p.BHasClass('RCPurpleDetailQuality')).text, '');
    assert.equal(labels.find(p => p.BHasClass('RCPurpleDetailQuality')).visible, false, 'Unknown quality remains hidden');
    assert.equal(labels.find(p => p.BHasClass('RCProductEffect')).text, walletItem('u_coin').description);
    assert(!nodes.some(p => p.paneltype === 'Button' || p.BHasClass('CJPrice') || p.BHasClass('CommercePurpleBuy')),
        'Price and purchase controls belong to the row or payment confirmation');
    assert(!labels.some(p => /¥|U币|人民币金额|1元=|查看.*购买|已拥有.*查看/.test(p.text || '')));
}

test('U币 SKU is deduplicated and cash eligibility overrides an empty wallet balance', () => {
    const h = harness(); h.cfg.SurvivalCommerceView.Open();
    h.walletSnapshot([walletItem('u_coin')]); h.paidSnapshot([paidItem()]);
    assert.equal(h.cfg.SurvivalCommerceView.Inspect().productCount, 1);
    const card = h.cards()[0];
    simpleDetail(h, card);
    assert(!h.descendants(h.root).some(p => /充值暂未开放/.test(p.text || '')));
    h.buyCard(card);
    assert.equal(h.cfg.SurvivalCommerceView.IsOpen(), false);
    assert(h.cfg.SurvivalUI.ModalManager.Get('payment_shop').IsOpen());
    assert.equal(h.$('#PaymentPrice').text, '合计 1200 U币 / ¥12.00');
    assert.equal(h.$('#PaymentBuyLabel').text, '微信购买 1200 U币');
    assert.equal(h.$('#PaymentBuy').enabled, true);
    assert.match(h.$('#PaymentStatus').text, /直接购买此道具/,
        'The authenticated payment row overrides wallet insufficient funds and ownership');
    assert.equal(h.requests.filter(r => r.payload.action === 'create' || r.payload.action === 'purchase').length, 0);
    h.context.PaymentBuy(); h.context.PaymentBuy();
    const create = h.lastRequest('survival_payment_request');
    assert.equal(create.payload.sku, 'u_item'); assert.equal(create.payload.provider, 'wechat');
    assert.deepEqual(Object.keys(create.payload).sort(), ['action','provider','quantity','request_id','sku']);
    assert.equal(h.requests.filter(r => r.payload.action === 'purchase').length, 0);
    assert.equal(h.requests.filter(r => r.payload.action === 'create').length, 1);
});

test('U币 products need an authenticated enabled payment row and valid U币 metadata', () => {
    const h = harness(); h.cfg.SurvivalCommerceView.Open(); h.walletSnapshot([walletItem('u_coin')]);
    let card = h.cards()[0];
    simpleDetail(h, card);
    h.buyCard(card); assert.equal(h.cfg.SurvivalCommerceView.IsOpen(), true);
    assert(h.descendants(h.store().canvas).some(p => p.text === '人民币支付目录正在连接，请稍后重试。'));
    h.cfg.SurvivalPayments.Checkout('u_item');
    assert.equal(h.$('#PaymentPrice').text, '合计 ', 'A wallet row cannot invent a payable quote');
    assert.equal(h.$('#PaymentBuy').enabled, false);
    assert.match(h.$('#PaymentStatus').text, /商品支付目录尚未同步/);
    h.paidSnapshot([], {catalog_hash:'ready-empty'}); card = h.cards()[0];
    simpleDetail(h, card);
    h.buyCard(card); assert.equal(h.cfg.SurvivalCommerceView.IsOpen(), true);
    assert(h.descendants(h.store().canvas).some(p => p.text === '此商品的人民币购买尚未开放，请稍后重试。'));
    assert.equal(h.$('#PaymentBuy').enabled, false);
    h.paidSnapshot([paidItem({enabled:0,owned:1,disabled_reason:'already_owned'})]);
    card = h.cards()[0]; simpleDetail(h, card);
    h.buyCard(card); assert.equal(h.$('#PaymentBuy').enabled, false);
    assert.equal(h.$('#PaymentStatus').text, '你已经拥有此商品。'); h.context.PaymentBuy();
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
    assert.equal(h.$('#PaymentPrice').text, '合计 ¥7.77');
    assert.equal(h.$('#PaymentBuyLabel').text, '微信购买 ¥7.77');
    h.context.PaymentChannel('alipay'); assert.equal(h.$('#PaymentBuyLabel').text, '支付宝购买 ¥7.77');
    h.context.PaymentBuy();
    assert.equal(h.lastRequest('survival_payment_request').payload.sku, 'legacy_cash');
});

test('订单 retains authoritative U币 and RMB snapshot through catalog edits, delisting, cancellation, and delivery', () => {
    const h = harness(); h.cfg.SurvivalCommerceView.Open(); h.paidSnapshot([paidItem()]);
    h.buyCard(h.cards()[0]); h.context.PaymentBuy(); h.paymentReply(orderFrom(paidItem()));
    assert.equal(h.$('#PaymentQR').style.visibility, 'visible');
    h.paidSnapshot([paidItem({u_coin_price:2400,amount_fen:2400,title:'新道具标题'})]);
    assert.equal(h.$('#PaymentPrice').text, '合计 1200 U币 / ¥12.00');
    assert.equal(h.$('#PaymentBuyLabel').text, '微信购买 1200 U币');
    assert.equal(h.$('#PaymentTitle').text, '测试道具');
    h.paidSnapshot([]); assert.equal(h.$('#PaymentProducts').Children().length, 1);
    assert.equal(h.$('#PaymentPrice').text, '合计 1200 U币 / ¥12.00');
    h.context.PaymentCancel(); assert.equal(h.lastRequest('survival_payment_request').payload.action, 'cancel');
    h.paymentReply(orderFrom(paidItem(), {state:'closed'}));
    h.paidSnapshot([paidItem({u_coin_price:2400,amount_fen:2400})]);
    h.context.PaymentChannel('alipay'); h.context.PaymentBuy();
    assert.equal(h.lastRequest('survival_payment_request').payload.provider, 'alipay');
    assert.deepEqual(Object.keys(h.lastRequest('survival_payment_request').payload).sort(), ['action','provider','quantity','request_id','sku']);
    h.paymentReply(orderFrom(paidItem({u_coin_price:2400,amount_fen:2400}), {provider:'alipay',state:'delivered'}));
    assert.equal(h.$('#PaymentPrice').text, '合计 2400 U币 / ¥24.00');
    assert.match(h.$('#PaymentStatus').text, /支付成功/); assert.equal(h.$('#PaymentQR').style.visibility, 'collapse');
    assert.equal(h.cfg.SurvivalPayments.Inspect().dirty, true, 'Delivery refreshes catalog ownership through the original cache');
});

test('U币 purchase buttons stay short for both channels while the full RMB price remains above', () => {
    for (const [coin,fen,rmb] of [[1200,1200,'12.00'],[29800,29800,'298.00']]) {
        const h = harness(), product = paidItem({u_coin_price:coin,amount_fen:fen});
        h.cfg.SurvivalCommerceView.Open(); h.paidSnapshot([product]); h.buyCard(h.cards()[0]);
        for (const [provider,label] of [['wechat','微信'],['alipay','支付宝']]) {
            h.context.PaymentChannel(provider);
            assert.equal(h.$('#PaymentBuyLabel').text, label+'购买 '+coin+' U币');
            assert(!/¥|1元=|\//.test(h.$('#PaymentBuyLabel').text));
            assert.equal(h.$('#PaymentPrice').text, '合计 '+coin+' U币 / ¥'+rmb);
            assert.equal(h.$('#PaymentBuy').enabled, true);
        }
        h.context.PaymentBuy(); h.paymentReply(orderFrom(product,{provider:'alipay'}));
        h.paidSnapshot([paidItem({u_coin_price:56000,amount_fen:56000})]);
        assert.equal(h.$('#PaymentBuyLabel').text, '支付宝购买 '+coin+' U币', 'A pending order retains its provider and U币 snapshot');
        assert.equal(h.$('#PaymentPrice').text, '合计 '+coin+' U币 / ¥'+rmb);
        h.context.PaymentCancel(); h.paymentReply(orderFrom(product,{provider:'alipay',state:'closed'}));
        h.context.PaymentChannel('wechat');
        assert.equal(h.$('#PaymentBuyLabel').text, '微信购买 56000 U币');
        assert.equal(h.$('#PaymentPrice').text, '合计 56000 U币 / ¥560.00');
    }
});

test('A consistent U币 price refresh rebuilds product details and unknown checkout never selects another SKU', () => {
    const h = harness(); h.cfg.SurvivalCommerceView.Open(); h.paidSnapshot([paidItem()]);
    const first = h.cards()[0];
    h.paidSnapshot([paidItem({u_coin_price:2400,amount_fen:2400})]);
    assert.notEqual(h.cards()[0], first);
    simpleDetail(h, h.cards()[0]);
    h.cfg.SurvivalPayments.Checkout('u_item');
    assert.equal(h.$('#PaymentPrice').text, '合计 2400 U币 / ¥24.00');
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
        simpleDetail(h, card);
        h.buyCard(card); assert.equal(h.cfg.SurvivalCommerceView.IsOpen(), true);
        assert(h.descendants(h.store().canvas).some(p => p.text === '此商品的人民币购买尚未开放，请稍后重试。'));
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
    h.walletSnapshot([{...walletItem('u_coin'),amount_fen:1200,u_coin_price:1200,u_coin_per_yuan:100}]);
    simpleDetail(h, h.cards()[0]);
    h.cfg.SurvivalPayments.Checkout('u_item');
    assert.equal(h.$('#PaymentPrice').text, '合计 ');
    assert.equal(h.$('#PaymentBuy').enabled, false);
    const incomplete = paidItem({currency:undefined,u_coin_price:undefined,u_coin_per_yuan:undefined});
    h.paidSnapshot([incomplete]);
    simpleDetail(h, h.cards()[0]);
    h.cfg.SurvivalPayments.Checkout('u_item');
    assert.equal(h.$('#PaymentPrice').text, '合计 U币价格及人民币金额待同步');
    assert.equal(h.$('#PaymentBuy').enabled, false); h.context.PaymentBuy();
    assert.equal(h.requests.filter(r => r.payload.action === 'create').length, 0);
});

test('Malformed U币 orders retain status polling and cancellation while payment entry points await valid metadata', () => {
    for (const state of ['created','pending']) {
        const h = harness(); h.cfg.SurvivalCommerceView.Open(); h.paidSnapshot([paidItem()]);
        h.buyCard(h.cards()[0]); h.context.PaymentBuy();
        const badOrder = orderFrom(paidItem({u_coin_price:2400}), {state});
        h.paymentReply(badOrder);
        assert.equal(h.$('#PaymentPrice').text, '合计 U币价格及人民币金额待同步');
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
        assert.equal(h.$('#PaymentPrice').text, '合计 1200 U币 / ¥12.00');
        assert.equal(h.$('#PaymentQR').style.visibility, 'visible');
        h.context.PaymentOpen(); assert.equal(h.urls.length, 1);
        h.context.PaymentCancel(); assert.equal(h.lastRequest('survival_payment_request').payload.action, 'cancel');
        h.paymentReply(orderFrom(paidItem(), {state:'closed'}));
        h.context.PaymentBuy(); assert.equal(h.requests.filter(r => r.payload.action === 'create').length, 2);
        h.paymentReply(orderFrom(paidItem({u_coin_price:2400}), {state:'delivered'}));
        assert.equal(h.$('#PaymentPrice').text, '合计 U币价格及人民币金额待同步');
        assert.match(h.$('#PaymentStatus').text, /支付成功/);
    }
});

test('Recharge uses RMB payment with 1–999999 editable units and the ordinary product limit stays 100', () => {
    const h = harness(), product = rechargeItem();
    h.paidSnapshot([product,paidItem({max_quantity:999999})]);
    h.cfg.SurvivalPayments.Checkout(product.sku);
    assert.equal(h.cfg.SurvivalPayments.Inspect().maxQuantity, 999999);
    assert.equal(h.$('#PaymentQuantityInput').text, '1');
    assert.equal(h.$('#PaymentQuantityInput').style.width, '108px');
    assert.equal(h.$('#PaymentQuantityHint').style.width, '148px');
    assert.equal(h.$('#PaymentQuantityMinus').enabled, false);
    assert.equal(h.$('#PaymentQuantityPlus').enabled, true);
    assert.equal(h.$('#PaymentPrice').text, '合计 ¥1.00');
    assert.equal(h.$('#PaymentBuyLabel').text, '微信充值 ¥1.00');
    assert.match(h.$('#PaymentUnitPrice').text, /每份 1 元 = 100 U币\n到账 100 U币（1 份）/);
    assert.equal(h.$('#PaymentUnitPrice').visible, true);
    h.context.PaymentQuantityChange(-1); assert.equal(h.$('#PaymentQuantityInput').text, '1');
    h.context.PaymentQuantityChange(1); assert.equal(h.$('#PaymentQuantityInput').text, '2');
    h.$('#PaymentQuantityInput').text = '999999'; h.context.PaymentQuantityInputChanged();
    assert.equal(h.cfg.SurvivalPayments.Inspect().quantity, 999999);
    assert.equal(h.$('#PaymentQuantityPlus').enabled, false);
    assert.equal(h.$('#PaymentPrice').text, '合计 ¥999999.00');
    assert.match(h.$('#PaymentUnitPrice').text, /到账 99999900 U币（999999 份）/);
    for (const [provider,label] of [['wechat','微信'],['alipay','支付宝']]) {
        h.context.PaymentChannel(provider);
        assert.equal(h.$('#PaymentBuyLabel').text, label+'充值 ¥999999.00');
        assert.equal(h.$('#PaymentBuy').enabled, true);
    }
    h.context.PaymentQuantityChange(1); assert.equal(h.cfg.SurvivalPayments.Inspect().quantity, 999999);
    h.context.PaymentBuy();
    assert.equal(h.lastRequest('survival_payment_request').payload.quantity, 999999);
    assert.equal(h.lastRequest('survival_payment_request').payload.provider, 'alipay');
    h.paymentReply(orderFrom(product,{provider:'alipay',quantity:999999,amount_fen:99999900,
        reward_lines:[{kind:'wallet',id:'u_coin',label:'U币',quantity:99999900}]}));
    assert.equal(h.$('#PaymentPrice').text, '合计 ¥999999.00');
    assert.equal(h.$('#PaymentQuantityInput').enabled, false);
    assert.equal(h.$('#PaymentQR').style.visibility, 'visible');
    assert.equal(h.$('#PaymentConsumptionNotice').text, '请适度娱乐，理性消费');
    h.cfg.SurvivalPayments.Checkout('u_item');
    assert.equal(h.cfg.SurvivalPayments.Inspect().maxQuantity, 100);
    assert.equal(h.$('#PaymentUnitPrice').visible, false);
    assert.equal(h.$('#PaymentQuantityInput').style.width, '84px');
    assert.equal(h.$('#PaymentQuantityHint').style.width, '180px');
    assert.equal(h.$('#PaymentBuyLabel').text, '支付宝购买 1200 U币');
});

test('Recharge rejects mismatched rate, price, identity and reward snapshots instead of treating them as legacy cash', () => {
    const malformed = [{recharge_u_coin_per_unit:1000},{amount_fen:99},{unit_amount_fen:200},
        {product_type:'single'},{sku:'other_recharge'},
        {reward_lines:[{kind:'wallet',id:'u_coin',label:'U币',quantity:99}]}];
    for (const bad of malformed) {
        const h=harness(),product=rechargeItem(bad);h.paidSnapshot([product]);h.cfg.SurvivalPayments.Checkout(product.sku);
        assert.equal(h.$('#PaymentBuy').enabled, false);
        h.context.PaymentBuy();assert.equal(h.requests.filter(r=>r.payload.action==='create').length,0);
    }
    const h=harness(),product=rechargeItem();h.paidSnapshot([product]);h.cfg.SurvivalPayments.Checkout(product.sku);
    h.$('#PaymentQuantityInput').text='invalid';h.context.PaymentQuantityInputChanged();
    assert.equal(h.$('#PaymentBuy').enabled,false);
    h.$('#PaymentQuantityInput').text='0';h.context.PaymentQuantityInputChanged();assert.equal(h.$('#PaymentQuantityInput').text,'1');
    h.$('#PaymentQuantityInput').text='999999999';h.context.PaymentQuantityInputChanged();assert.equal(h.$('#PaymentQuantityInput').text,'999999');
    h.context.PaymentBuy();
    h.paymentReply(orderFrom(product,{quantity:999999,amount_fen:99999900})); // Reward snapshot still contains only one unit.
    assert.equal(h.$('#PaymentQR').style.visibility,'collapse');
    assert.equal(h.$('#PaymentOpen').style.visibility,'collapse');
    assert.match(h.$('#PaymentPrice').text,/充值金额及到账数量待同步/);
});

test('The consumption notice survives old XML and remains visible in confirmation, pending and receipt states', () => {
    const h=harness({legacyXML:true}),product=rechargeItem();
    h.paidSnapshot([product]);h.cfg.SurvivalPayments.Checkout(product.sku);
    const checkNotice=()=>{
        assert.equal(h.$('#PaymentConsumptionNotice').text,'请适度娱乐，理性消费');
        assert.equal(h.$('#PaymentConsumptionNotice').visible,true);
        assert.equal(h.descendants(h.root).filter(p=>p.id==='PaymentConsumptionNotice').length,1);
    };
    checkNotice();h.context.PaymentBuy();h.paymentReply(orderFrom(product));checkNotice();
    h.context.PaymentRefresh();h.paymentReply(orderFrom(product,{state:'delivered'}));checkNotice();
    assert.match(h.$('#PaymentStatus').text,/充值成功：100 U币已到账/);
    h.context.PaymentRefresh();h.paymentReply(orderFrom(product,{state:'paid_review'}));checkNotice();
    assert.equal(h.$('#PaymentStatus').text,'已收到付款，奖励暂未到账，请保留订单号联系处理，请勿重复付款。');
});

test('A recharge delivery invalidates an older wallet read before it can publish and refreshes the new balance once', () => {
    const h=harness(),product=rechargeItem();
    h.walletSnapshot([]);
    const api=h.cfg.SurvivalCommerceWallet,originalInvalidate=api.Invalidate;
    let invalidations=0;
    api.Invalidate=()=>{invalidations++;return originalInvalidate();};
    assert.equal(api.Refresh(),true);
    const stale=h.lastRequest('survival_commerce_request');
    h.paidSnapshot([product]);h.cfg.SurvivalPayments.Checkout(product.sku);h.context.PaymentBuy();
    h.paymentReply(orderFrom(product,{state:'delivered'}));
    assert.equal(invalidations,1,'Delivery invalidates synchronously before any scheduled work');
    const staleBase={request_id:stale.payload.request_id,action:'catalog',ok:1};
    h.emit('survival_commerce_result',{...staleBase,part:'begin',count:0,categories:[],balances:{u_coin:0}});
    h.emit('survival_commerce_result',{...staleBase,part:'end'});
    assert.equal(api.GetCatalog().balances.shop_points,500,'The pre-payment result is discarded in full');
    const zero=h.timers.findLast(t=>t.delay===0);assert(zero);zero.fn();
    const fresh=h.lastRequest('survival_commerce_request');
    assert.notEqual(fresh.payload.request_id,stale.payload.request_id);
    const freshBase={request_id:fresh.payload.request_id,action:'catalog',ok:1};
    h.emit('survival_commerce_result',{...freshBase,part:'begin',count:0,categories:[],balances:{u_coin:100}});
    h.emit('survival_commerce_result',{...freshBase,part:'end'});
    assert.equal(api.GetCatalog().balances.u_coin,100);
    h.context.PaymentRefresh();h.paymentReply(orderFrom(product,{state:'delivered'}));
    assert.equal(invalidations,1,'Repeated status for the same delivered order does not invalidate again');
});


test('New catalog quotes use 100 U-coins/yuan and remain buyable without a second client discount', () => {
    const h=harness(),product=paidItem({u_coin_price:100,amount_fen:100,price:100});
    h.paidSnapshot([product]);h.cfg.SurvivalCommerceView.Open();h.cfg.SurvivalCommerceView.SelectCategory('all');
    const card=h.cards()[0];assert(card);
    // This integration harness uses the existing fallback card controls. The
    // V10 shell's native price geometry is exercised by its own asset suite.
    h.buyCard(card);assert.equal(h.$('#PaymentPrice').text,'合计 100 U币 / ¥1.00');
    assert.match(h.$('#PaymentHint').text,/1元=100U币/);assert.equal(h.$('#PaymentBuy').enabled,true);
    h.context.PaymentBuy();const payload=h.lastRequest('survival_payment_request').payload;
    assert.deepEqual(Object.keys(payload).sort(),['action','provider','quantity','request_id','sku']);
    assert.equal(product.u_coin_price,100,'The browser cannot halve a server-owned price a second time');
});

test('A historical 1000-U rate in a catalog never authorizes a new order', () => {
    const h=harness(),legacy=paidItem({u_coin_price:100,amount_fen:10,u_coin_per_yuan:1000});
    h.paidSnapshot([legacy]);h.cfg.SurvivalCommerceView.Open();h.cfg.SurvivalCommerceView.SelectCategory('all');
    // The current view may keep an unavailable row visible. Neither that row
    // nor direct checkout may authorize an order using the historical rate.
    for(const card of h.cards())h.buyCard(card);
    h.cfg.SurvivalPayments.Checkout(legacy.sku);assert.equal(h.$('#PaymentBuy').enabled,false);
    h.context.PaymentBuy();assert.equal(h.requests.filter(r=>r.payload.action==='create').length,0);
});

test('Historical created, pending and delivered orders retain their frozen 1000-U rate through new 100-U catalog updates', () => {
    for(const state of ['created','pending','delivered']){
        const h=harness(),product=paidItem({u_coin_price:500,amount_fen:500});
        h.paidSnapshot([product]);h.cfg.SurvivalPayments.Checkout(product.sku);h.context.PaymentBuy();
        const legacy=orderFrom(paidItem({u_coin_price:1000,amount_fen:100,u_coin_per_yuan:1000}),{state});
        h.paymentReply(legacy);
        assert.equal(h.$('#PaymentPrice').text,'合计 1000 U币 / ¥1.00');
        assert.equal(h.$('#PaymentQR').style.visibility,state==='pending'?'visible':'collapse');
        h.paidSnapshot([paidItem({u_coin_price:250,amount_fen:250})]);
        assert.equal(h.$('#PaymentPrice').text,'合计 1000 U币 / ¥1.00');
        assert(!/待同步/.test(h.$('#PaymentPrice').text));
        assert.equal(h.requests.filter(r=>r.payload.action==='create').length,1);
    }
});

test('A copied historical order id cannot make a stale 1000-U catalog row buyable', () => {
    const h=harness(),product=paidItem({u_coin_price:500,amount_fen:500});
    h.paidSnapshot([product]);h.cfg.SurvivalPayments.Checkout(product.sku);h.context.PaymentBuy();
    const old=orderFrom(paidItem({u_coin_price:1000,amount_fen:100,u_coin_per_yuan:1000}),{state:'delivered'});
    h.paymentReply(old);h.paidSnapshot([{...old,enabled:1}]);
    assert.equal(h.$('#PaymentPrice').text,'合计 1000 U币 / ¥1.00','The receipt is still readable');
    assert.equal(h.$('#PaymentBuy').enabled,false,'Catalog validation never opts into frozen order compatibility');
    h.context.PaymentBuy();assert.equal(h.requests.filter(r=>r.payload.action==='create').length,1);
});
