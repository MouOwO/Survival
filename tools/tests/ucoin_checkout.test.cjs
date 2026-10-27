const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const test = require('node:test');

const addon = path.resolve(__dirname, '../..');
const scripts = path.join(addon, 'panorama/src/scripts/custom_game');
function harness({legacyXML = false, market = false} = {}) {
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
    const cfg = {SurvivalDevelopmentPayments:true};
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
        'commerce_wallet.js', 'payment_test.js'].forEach(load);
    if(market)['shop_v10_assets.js','black_lion_market_model.js','black_lion_market.js'].forEach(load);
    load('commerce_remaining_5d5c1152eb.js');
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
        const started = cfg.SurvivalCommerceWallet.Refresh();
        function respond(request) {
            assert.equal(request.payload.action, 'catalog', 'The fixture only completes a live wallet catalog request');
            const base = {request_id:request.payload.request_id,action:'catalog',ok:1};
            emit('survival_commerce_result', {...base,part:'begin',count:products.length,categories,balances:{u_coin:0,shop_points:500,shop_gold:90}});
            products.forEach((product, i) => emit('survival_commerce_result', {...base,part:'product',index:i+1,product}));
            emit('survival_commerce_result', {...base,part:'end'});
        }
        const request = lastRequest('survival_commerce_request'); respond(request);
        if (!started) {
            for (const delay of [1.1, 3]) for (const timer of timers.slice())
                if (!timer.ran && !timer.cancelled && timer.delay === delay) { timer.ran = true; timer.fn(); }
            const followup = lastRequest('survival_commerce_request');
            assert.notEqual(followup.payload.request_id, request.payload.request_id, 'Invalidated reads require the queued fresh catalog');
            respond(followup);
        }
    }
    const descendants = (p, cls) => [p, ...p.Children().flatMap(c => descendants(c, cls))].filter(n => !cls || n.BHasClass(cls));
    const menu = cls => cfg.SurvivalMenuV10.Entries().find(m => m.panel.BHasClass(cls));
    const store = () => market ? cfg.SurvivalBlackLionMarket.GetWindow() : menu('MenuV10Commerce');
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
    assert(!labels.some(p => /¥|G币|人民币金额|1元=|查看.*购买|已拥有.*查看/.test(p.text || '')));
}

test('G币 SKU is deduplicated and cash eligibility overrides an empty wallet balance', () => {
    const h = harness(); h.cfg.SurvivalCommerceView.Open();
    h.walletSnapshot([walletItem('u_coin')]); h.paidSnapshot([paidItem()]);
    assert.equal(h.cfg.SurvivalCommerceView.Inspect().productCount, 1);
    const card = h.cards()[0];
    simpleDetail(h, card);
    assert(!h.descendants(h.root).some(p => /充值暂未开放/.test(p.text || '')));
    h.buyCard(card);
    assert.equal(h.cfg.SurvivalCommerceView.IsOpen(), true,'The store stays behind purchase confirmation');
    assert(h.cfg.SurvivalUI.ModalManager.Get('payment_shop').IsOpen());
    assert.equal(h.$('#PaymentPrice').text, '合计 1200 G币 / ¥12.00');
    assert.equal(h.$('#PaymentBuyLabel').text, '微信购买 1200 G币');
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

test('Purchase dismissal reveals the same loaded market list without reopening, refreshing, or destroying tooltips', () => {
    for(const dismissal of ['back','close','scrim','escape']){
        const h=harness({market:true});
        h.paidSnapshot(Array.from({length:45},(_,i)=>paidItem({sku:'overlay_'+i,title:'商品 '+i})));
        h.cfg.SurvivalCommerceView.Open();
        h.cfg.SurvivalCommerceView.SelectCategory('all');h.cfg.SurvivalCommerceView.SelectPurchaseType('u_coin');
        const store=h.store();store.content.actuallayoutheight=500;store.content.contentheight=1000;store.content.scrolloffset_y=500;
        h.timers.findLast(t=>t.delay===.2&&!t.cancelled).fn();store.content.scrolloffset_y=600;
        const view=h.cfg.SurvivalCommerceView,card=h.cards()[20],tip=card.__purpleDetail,before=view.Inspect();
        assert.equal(before.loadedProductCount,40);card.__purpleShow();assert(tip.BHasClass('Visible'));
        h.buyCard(card);
        assert(view.IsOpen());assert(store.panel.visible);assert(!tip.BHasClass('Visible'));assert(tip.IsValid());
        assert.equal(h.cfg.SurvivalUILayers.Top(),'payment_shop');
        let reopen=0;const open=view.Open;view.Open=function(){reopen++;return open.apply(view,arguments);};
        const reads=h.requests.length;
        if(dismissal==='escape')h.cfg.SurvivalUILayers.CloseTop();
        else h.$('#'+({back:'PaymentBack',close:'PaymentClose',scrim:'PaymentScrim'}[dismissal])).events.onactivate();
        assert(!h.cfg.SurvivalUI.ModalManager.Get('payment_shop').IsOpen());
        assert.equal(h.cfg.SurvivalUILayers.Top(),'commerce');assert(view.IsOpen());assert(store.panel.visible);
        assert.equal(reopen,0,'Returning only removes the top popup');assert.equal(h.requests.length,reads,'Returning submits no catalog or order request');
        const after=view.Inspect();for(const key of ['page','category','purchaseType','loadedProductCount'])assert.equal(after[key],before[key]);
        assert.equal(store.content.scrolloffset_y,600);assert.equal(h.cards()[20],card);assert.equal(card.__purpleDetail,tip);card.__purpleShow();assert(tip.BHasClass('Visible'),'Hover continues working after return');
    }
});

test('Returning from a standalone checkout still opens the market when no store was underneath',()=>{
    const h=harness({market:true});h.paidSnapshot([paidItem()]);
    assert(!h.cfg.SurvivalCommerceView.IsOpen());h.cfg.SurvivalPayments.Checkout('u_item');
    h.$('#PaymentBack').events.onactivate();
    assert(h.cfg.SurvivalCommerceView.IsOpen());assert.equal(h.cfg.SurvivalUILayers.Top(),'commerce');
    assert(!h.cfg.SurvivalPayments.Inspect().opened);assert.equal(h.requests.filter(r=>r.payload.action==='create'||r.payload.action==='purchase').length,0);
});

test('Wallet result back and escape leave the existing market intact, and a rejected checkout keeps it visible',()=>{
    const h=harness({market:true}),product={...walletItem('shop_points','overlay_points'),enabled:1,owned:0,price:10,disabled_reason:''};
    h.paidSnapshot([]);h.walletSnapshot([product]);h.cfg.SurvivalCommerceView.Open();h.walletSnapshot([product]);h.cfg.SurvivalCommerceView.SelectCategory('all');h.cfg.SurvivalCommerceView.SelectPurchaseType('shop_points');
    const view=h.cfg.SurvivalCommerceView,card=h.cards()[0];let reopen=0;const open=view.Open;view.Open=function(){reopen++;return open.apply(view,arguments);};
    for(const action of ['footer','escape']){
        h.buyCard(card);const result=h.$('#CommerceResultDialog');assert(result.visible);assert(view.IsOpen());
        const reads=h.requests.length;
        if(action==='footer')h.$('#CommerceResultBack').events.onactivate();
        else h.cfg.SurvivalUILayers.CloseTop();
        assert(!result.visible);assert.equal(h.cfg.SurvivalUILayers.Top(),'commerce');assert.equal(reopen,0);assert.equal(h.requests.length,reads);assert.equal(h.cards()[0],card);
    }
    assert.equal(h.requests.filter(row=>row.payload.action==='purchase').length,1,'Reopening an inflight result cannot duplicate its exchange');
    h.cfg.SurvivalCommerceWallet.Checkout=()=>false;h.buyCard(card);assert(view.IsOpen());assert.equal(h.cards()[0],card);
});

test('G币 products need an authenticated enabled payment row and valid G币 metadata', () => {
    const h = harness(); h.cfg.SurvivalCommerceView.Open(); h.walletSnapshot([walletItem('u_coin')]);
    let card = h.cards()[0];
    simpleDetail(h, card);
    h.buyCard(card); assert.equal(h.cfg.SurvivalCommerceView.IsOpen(), true);
    assert(h.descendants(h.store().canvas).some(p => p.text === '商品目录正在连接，请稍后重试。'));
    h.cfg.SurvivalPayments.Checkout('u_item');
    assert.equal(h.$('#PaymentPrice').text, '合计 ', 'A wallet row cannot invent a payable quote');
    assert.equal(h.$('#PaymentBuy').enabled, false);
    assert.match(h.$('#PaymentStatus').text, /商品支付目录尚未同步/);
    h.paidSnapshot([], {catalog_hash:'ready-empty'}); card = h.cards()[0];
    simpleDetail(h, card);
    h.buyCard(card); assert.equal(h.cfg.SurvivalCommerceView.IsOpen(), true);
    assert(h.descendants(h.store().canvas).some(p => p.text === '此商品暂未开放，请稍后重试。'));
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

test('积分 and 商城金币 exchange directly while legacy cash retains RMB confirmation', () => {
    const h = harness(); h.cfg.SurvivalCommerceView.Open();
    const points = {...walletItem('shop_points','points_item'),price:20,enabled:1,owned:0,disabled_reason:''};
    const gold = {...walletItem('shop_gold','gold_item'),price:10,enabled:1,owned:0,disabled_reason:''};
    h.walletSnapshot([points,gold]);
    h.paidSnapshot([{sku:'legacy_cash',title:'原人民币礼包',category_id:'legacy',product_type:'single',amount_fen:777,enabled:1,owned:0,reward_lines:[]}]);
    assert.equal(h.cfg.SurvivalCommerceView.Inspect().productCount, 3);
    for (const [category, sku] of [['points','points_item'],['gold','gold_item']]) {
        h.cfg.SurvivalCommerceView.Open(); h.walletSnapshot([points,gold]); h.category(category); h.buyCard(h.cards()[0]);
        assert(h.$('#CommerceResultDialog').visible);
        assert.equal(h.descendants(h.root, 'CommerceConfirmBuy').length, 0);
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

test('订单 retains authoritative G币 and RMB snapshot through catalog edits, delisting, cancellation, and delivery', () => {
    const h = harness(); h.cfg.SurvivalCommerceView.Open(); h.paidSnapshot([paidItem()]);
    h.buyCard(h.cards()[0]); h.context.PaymentBuy(); h.paymentReply(orderFrom(paidItem()));
    assert.equal(h.$('#PaymentQR').style.visibility, 'visible');
    h.paidSnapshot([paidItem({u_coin_price:2400,amount_fen:2400,title:'新道具标题'})]);
    assert.equal(h.$('#PaymentPrice').text, '合计 1200 G币 / ¥12.00');
    assert.equal(h.$('#PaymentBuyLabel').text, '微信购买 1200 G币');
    assert.equal(h.$('#PaymentTitle').text, '测试道具');
    h.paidSnapshot([]); assert.equal(h.$('#PaymentProducts').Children().length, 1);
    assert.equal(h.$('#PaymentPrice').text, '合计 1200 G币 / ¥12.00');
    h.context.PaymentCancel(); assert.equal(h.lastRequest('survival_payment_request').payload.action, 'cancel');
    h.paymentReply(orderFrom(paidItem(), {state:'closed'}));
    h.paidSnapshot([paidItem({u_coin_price:2400,amount_fen:2400})]);
    h.context.PaymentChannel('alipay'); h.context.PaymentBuy();
    assert.equal(h.lastRequest('survival_payment_request').payload.provider, 'alipay');
    assert.deepEqual(Object.keys(h.lastRequest('survival_payment_request').payload).sort(), ['action','provider','quantity','request_id','sku']);
    h.paymentReply(orderFrom(paidItem({u_coin_price:2400,amount_fen:2400}), {provider:'alipay',state:'delivered'}));
    assert.equal(h.$('#PaymentPrice').text, '合计 2400 G币 / ¥24.00');
    assert.match(h.$('#PaymentStatus').text, /支付成功/); assert.equal(h.$('#PaymentQR').style.visibility, 'collapse');
    assert.equal(h.cfg.SurvivalPayments.Inspect().dirty, true, 'Delivery refreshes catalog ownership through the original cache');
});

test('G币 purchase buttons stay short for both channels while the full RMB price remains above', () => {
    for (const [coin,fen,rmb] of [[1200,1200,'12.00'],[29800,29800,'298.00']]) {
        const h = harness(), product = paidItem({u_coin_price:coin,amount_fen:fen});
        h.cfg.SurvivalCommerceView.Open(); h.paidSnapshot([product]); h.buyCard(h.cards()[0]);
        for (const [provider,label] of [['wechat','微信'],['alipay','支付宝']]) {
            h.context.PaymentChannel(provider);
            assert.equal(h.$('#PaymentBuyLabel').text, label+'购买 '+coin+' G币');
            assert(!/¥|1元=|\//.test(h.$('#PaymentBuyLabel').text));
            assert.equal(h.$('#PaymentPrice').text, '合计 '+coin+' G币 / ¥'+rmb);
            assert.equal(h.$('#PaymentBuy').enabled, true);
        }
        h.context.PaymentBuy(); h.paymentReply(orderFrom(product,{provider:'alipay'}));
        h.paidSnapshot([paidItem({u_coin_price:56000,amount_fen:56000})]);
        assert.equal(h.$('#PaymentBuyLabel').text, '支付宝购买 '+coin+' G币', 'A pending order retains its provider and G币 snapshot');
        assert.equal(h.$('#PaymentPrice').text, '合计 '+coin+' G币 / ¥'+rmb);
        h.context.PaymentCancel(); h.paymentReply(orderFrom(product,{provider:'alipay',state:'closed'}));
        h.context.PaymentChannel('wechat');
        assert.equal(h.$('#PaymentBuyLabel').text, '微信购买 56000 G币');
        assert.equal(h.$('#PaymentPrice').text, '合计 56000 G币 / ¥560.00');
    }
});

test('A consistent G币 price refresh rebuilds product details and unknown checkout never selects another SKU', () => {
    const h = harness(); h.cfg.SurvivalCommerceView.Open(); h.paidSnapshot([paidItem()]);
    const first = h.cards()[0];
    h.paidSnapshot([paidItem({u_coin_price:2400,amount_fen:2400})]);
    assert.notEqual(h.cards()[0], first);
    simpleDetail(h, h.cards()[0]);
    h.cfg.SurvivalPayments.Checkout('u_item');
    assert.equal(h.$('#PaymentPrice').text, '合计 2400 G币 / ¥24.00');
    assert.equal(h.$('#PaymentBuy').enabled, true);
    h.cfg.SurvivalPayments.Checkout('missing_sku'); h.paidSnapshot([paidItem()]);
    assert.equal(h.$('#PaymentBuy').enabled, false); h.context.PaymentBuy();
    assert.equal(h.requests.filter(r => r.payload.action === 'create').length, 0);
});

test('Inconsistent G币 metadata cannot quote a payable amount or create an order', () => {
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
        assert(h.descendants(h.store().canvas).some(p => p.text === '此商品暂未开放，请稍后重试。'));
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
    assert.equal(h.$('#PaymentPrice').text, '合计 G币价格及人民币金额待同步');
    assert.equal(h.$('#PaymentBuy').enabled, false); h.context.PaymentBuy();
    assert.equal(h.requests.filter(r => r.payload.action === 'create').length, 0);
});

test('Malformed G币 orders retain status polling and cancellation while payment entry points await valid metadata', () => {
    for (const state of ['created','pending']) {
        const h = harness(); h.cfg.SurvivalCommerceView.Open(); h.paidSnapshot([paidItem()]);
        h.buyCard(h.cards()[0]); h.context.PaymentBuy();
        const badOrder = orderFrom(paidItem({u_coin_price:2400}), {state});
        h.paymentReply(badOrder);
        assert.equal(h.$('#PaymentPrice').text, '合计 G币价格及人民币金额待同步');
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
        assert.equal(h.$('#PaymentPrice').text, '合计 1200 G币 / ¥12.00');
        assert.equal(h.$('#PaymentQR').style.visibility, 'visible');
        h.context.PaymentOpen(); assert.equal(h.urls.length, 1);
        h.context.PaymentCancel(); assert.equal(h.lastRequest('survival_payment_request').payload.action, 'cancel');
        h.paymentReply(orderFrom(paidItem(), {state:'closed'}));
        h.context.PaymentBuy(); assert.equal(h.requests.filter(r => r.payload.action === 'create').length, 2);
        h.paymentReply(orderFrom(paidItem({u_coin_price:2400}), {state:'delivered'}));
        assert.equal(h.$('#PaymentPrice').text, '合计 G币价格及人民币金额待同步');
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
    assert.match(h.$('#PaymentUnitPrice').text, /每份 1 元 = 100 G币\n到账 100 G币（1 份）/);
    assert.equal(h.$('#PaymentUnitPrice').visible, true);
    h.context.PaymentQuantityChange(-1); assert.equal(h.$('#PaymentQuantityInput').text, '1');
    h.context.PaymentQuantityChange(1); assert.equal(h.$('#PaymentQuantityInput').text, '2');
    h.$('#PaymentQuantityInput').text = '999999'; h.context.PaymentQuantityInputChanged();
    assert.equal(h.cfg.SurvivalPayments.Inspect().quantity, 999999);
    assert.equal(h.$('#PaymentQuantityPlus').enabled, false);
    assert.equal(h.$('#PaymentPrice').text, '合计 ¥999999.00');
    assert.match(h.$('#PaymentUnitPrice').text, /到账 99999900 G币（999999 份）/);
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
    assert.equal(h.$('#PaymentBuyLabel').text, '支付宝购买 1200 G币');
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
    assert.match(h.$('#PaymentStatus').text,/充值成功：100 G币已到账/);
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
    h.buyCard(card);assert.equal(h.$('#PaymentPrice').text,'合计 100 G币 / ¥1.00');
    assert.match(h.$('#PaymentHint').text,/1元=100G币/);assert.equal(h.$('#PaymentBuy').enabled,true);
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
        assert.equal(h.$('#PaymentPrice').text,'合计 1000 G币 / ¥1.00');
        assert.equal(h.$('#PaymentQR').style.visibility,state==='pending'?'visible':'collapse');
        h.paidSnapshot([paidItem({u_coin_price:250,amount_fen:250})]);
        assert.equal(h.$('#PaymentPrice').text,'合计 1000 G币 / ¥1.00');
        assert(!/待同步/.test(h.$('#PaymentPrice').text));
        assert.equal(h.requests.filter(r=>r.payload.action==='create').length,1);
    }
});

test('A copied historical order id cannot make a stale 1000-U catalog row buyable', () => {
    const h=harness(),product=paidItem({u_coin_price:500,amount_fen:500});
    h.paidSnapshot([product]);h.cfg.SurvivalPayments.Checkout(product.sku);h.context.PaymentBuy();
    const old=orderFrom(paidItem({u_coin_price:1000,amount_fen:100,u_coin_per_yuan:1000}),{state:'delivered'});
    h.paymentReply(old);h.paidSnapshot([{...old,enabled:1}]);
    assert.equal(h.$('#PaymentPrice').text,'合计 1000 G币 / ¥1.00','The receipt is still readable');
    assert.equal(h.$('#PaymentBuy').enabled,false,'Catalog validation never opts into frozen order compatibility');
    h.context.PaymentBuy();assert.equal(h.requests.filter(r=>r.payload.action==='create').length,1);
});


test('Monthly pass lists 5800 U-coins, confirms RMB 58, and freezes older RMB 10/20 order quotes', () => {
    const product=paidItem({sku:'archive_pass_monthly',title:'签到月卡（30天）',category_id:'legacy',
        amount_fen:5800,u_coin_price:5800,price:5800,max_quantity:1,
        reward_lines:[{kind:'entitlement',id:'archive_pass',duration_days:30,quantity:1,label:'签到月卡'}]});
    const open=()=>{
        const h=harness();h.cfg.SurvivalCommerceView.Open();h.paidSnapshot([product]);
        h.cfg.SurvivalCommerceView.SelectCategory('legacy');return h;
    };
    const h=open(),card=h.cards()[0];assert(card,'The real catalog includes the monthly pass');
    const quote=h.cfg.SurvivalPayments.GetCatalog().products.find(item=>item.sku===product.sku);
    assert.equal(quote.u_coin_price,5800);assert.equal(quote.u_coin_per_yuan,100);assert.equal(quote.amount_fen,5800);
    // The fallback harness keeps prices out of its grid cards. Exercise the
    // production price formatter separately with that authenticated quote.
    const price=h.cfg.SurvivalCommerceComponents.Price(h.root,{...quote,purchase_method:'cash',currency:'u_coin'},0,0,272);
    assert(h.descendants(price).some(panel=>panel.text==='5800 G币'),'The catalog quote remains the row token price');
    h.buyCard(card);
    assert.equal(h.$('#PaymentPrice').text,'合计 ¥58.00');
    assert.equal(h.$('#PaymentBuyLabel').text,'微信购买 ¥58.00');
    assert.equal(h.$('#PaymentBuy').enabled,true);
    assert.equal(h.requests.filter(request=>request.payload.action==='create').length,0,'Opening confirmation creates no order');
    for(const yuan of [10,20])for(const rate of [100,1000])for(const state of ['pending','delivered']){
        const old=open();old.buyCard(old.cards()[0]);old.context.PaymentBuy();
        old.paymentReply(orderFrom({...product,amount_fen:yuan*100,u_coin_price:yuan*rate,u_coin_per_yuan:rate},{state}));
        old.paidSnapshot([product]);
        assert.equal(old.$('#PaymentPrice').text,'合计 ¥'+yuan.toFixed(2),'A changed catalog cannot reprice the stored pass order');
        assert.equal(old.$('#PaymentQR').style.visibility,state==='pending'?'visible':'collapse');
        assert.equal(old.requests.filter(request=>request.payload.action==='create').length,1,'Catalog refresh never replaces an existing order');
    }
});


test('Legacy U-coin recharge text renders G-coins without mutating catalog, receipts, or protocol fields', () => {
    const h=harness(),product=rechargeItem({title:'U币充值',description:'每份1元=100U币；奖励U币。',
        reward_lines:[{kind:'wallet',id:'u_coin',label:'U币',quantity:100}]}),original=JSON.stringify(product);
    h.paidSnapshot([product]);h.cfg.SurvivalPayments.Checkout(product.sku);
    assert.equal(h.$('#PaymentTitle').text,'G币充值');
    assert.match(h.$('#PaymentDescription').text,/100G币/);
    assert.match(h.$('#PaymentUnitPrice').text,/100 G币/);
    assert(![h.$('#PaymentTitle'),h.$('#PaymentDescription'),h.$('#PaymentUnitPrice'),h.$('#PaymentValues')]
        .some(panel=>/U币/.test(panel.text)));
    assert.equal(h.cfg.SurvivalPayments.GetCatalog().products[0].title,'U币充值','Display normalization cannot rewrite the server snapshot');
    assert.equal(JSON.stringify(product),original);
    h.context.PaymentBuy();const payload=h.lastRequest('survival_payment_request').payload;
    assert.equal(payload.sku,'u_coin_recharge');
    assert.deepEqual(Object.keys(payload).sort(),['action','provider','quantity','request_id','sku']);
    h.paymentReply(orderFrom(product,{state:'delivered'}));
    assert.equal(h.$('#PaymentTitle').text,'G币充值');
    assert.match(h.$('#PaymentStatus').text,/充值成功：100 G币已到账/);
    assert.equal(JSON.stringify(product),original,'A legacy receipt remains immutable after delivery');
});
