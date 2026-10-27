'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {harness} = require('../shop_catalog_20261016/harness.cjs');

const points = {sku:'result_points_fixture',title:'积分商品',category_id:'item',product_type:'single',
    currency:'shop_points',price:100,purchase_method:'wallet',enabled:1,purchase_limit:0,
    reward_lines:[{kind:'stat',id:'initial_wood',label:'木材',quantity:1}]};
function current(h, id) { return h.root.FindChildTraverse(id); }
function result(h) { return h.cfg.SurvivalUI.ModalManager.Get('commerce_result'); }
function requestCount(h, action) {
    return h.requests.filter(row => row.name === 'survival_commerce_request' && row.payload.action === action).length;
}
function failedExchange(h) {
    h.cfg.SurvivalCommerceView.Open();
    h.walletSnapshot([points], {shop_points:0,u_coin:100,shop_gold:0});
    assert.equal(h.cfg.SurvivalCommerceWallet.Checkout(points.sku), false);
    assert.equal(h.cfg.SurvivalCommerceWallet.Inspect().result, 'failure');
    assert.equal(h.cfg.SurvivalUILayers.Top(), 'commerce_result');
    return current(h, 'CommerceResultDialog');
}
function scale(panel) {
    const match = /^scale3d\(([^,]+),([^,]+),1\)$/.exec(panel.style.transform);
    assert(match, 'the actual shared fit supplies a uniform transform');
    assert.equal(match[1], match[2]);
    return Number(match[1]);
}
function visibleMarket(h) {
    const menu = h.store(), modal = h.cfg.SurvivalUI.ModalManager.Get('commerce');
    assert.equal(h.cfg.SurvivalCommerceWallet.Inspect().opened, false);
    assert.equal(result(h).IsOpen(), false);
    assert.equal(current(h, 'CommerceResultDialog').visible, false);
    assert.equal(h.cfg.SurvivalCommerceView.IsOpen(), true);
    assert.equal(menu.IsOpen(), true);
    assert.equal(menu.panel.visible, true);
    assert.equal(menu.panel.hittest, true);
    assert.equal(menu.panel.hittestchildren, true);
    assert.equal(menu.panel.BHasClass('UIClosed'), false);
    assert.equal(modal.IsOpen(), true);
    const backdrop = h.descendants(h.root, 'BLMarketBackdrop')[0];
    assert.equal(backdrop.visible, true);
    assert.equal(backdrop.hittest, true);
    assert.equal(h.cfg.SurvivalUILayers.Top(), 'commerce');
    assert.equal(h.paidCheckouts.length, 0, 'return navigation cannot create a cash checkout');
}

for (const [width,height] of [[1600,900],[3200,1800]]) {
    test(`result remains 560x346 at ${width}x${height}, with no viewport upscaling`, () => {
        const h = harness();
        h.root.actuallayoutwidth=width; h.root.actuallayoutheight=height;
        const dialog = failedExchange(h);
        assert.equal(dialog.style.width,'560px'); assert.equal(dialog.style.height,'346px');
        assert.equal(scale(dialog),1);
        h.advanceTimers(.25);
        assert.equal(scale(dialog),1, 'periodic native fit must preserve the same maximum');
        assert.equal(requestCount(h,'purchase'),0);
    });
}

test('result still scales down to fit a smaller viewport and restores to at most one', () => {
    const h=harness(); h.root.actuallayoutwidth=400; h.root.actuallayoutheight=240;
    const dialog=failedExchange(h), reduced=scale(dialog);
    assert(reduced>0 && reduced<1);
    assert(560*reduced<=400*.94 && 346*reduced<=240*.88+.000001);
    h.root.actuallayoutwidth=1600; h.root.actuallayoutheight=900; h.advanceTimers(.25);
    assert.equal(scale(dialog),1);
});

test('return reopens the real market shell when its controller still reports open', () => {
    const h=harness(); failedExchange(h);
    h.cfg.SurvivalCommerceView.SelectCategory('all');
    h.cfg.SurvivalCommerceView.SelectPurchaseType('shop_points');
    // A separate layer owner can close the physical shell without invoking the
    // view controller's Close. Reproduce that public-API state, not a mocked flag.
    h.store().Close();
    assert.equal(h.cfg.SurvivalCommerceView.IsOpen(),true);
    assert.equal(h.store().IsOpen(),false); assert.equal(h.store().panel.visible,false);
    const purchases=requestCount(h,'purchase'), reads=h.requests.length;
    current(h,'CommerceResultBack').events.onactivate();
    visibleMarket(h);
    assert.equal(h.cfg.SurvivalCommerceView.Inspect().category,'all');
    assert.equal(h.cfg.SurvivalCommerceView.Inspect().purchaseType,'shop_points');
    assert.equal(requestCount(h,'purchase'),purchases);
    assert.equal(h.requests.length,reads,'restoring an initialized shell cannot refresh or replace its catalog');
});

test('return restores a hidden native panel and its missing layer even with an open shell', () => {
    const h=harness(); failedExchange(h);
    const panel=h.store().panel;
    h.cfg.SurvivalUILayers.Close('commerce');
    panel.visible=false; panel.hittest=false; panel.hittestchildren=false;
    assert.equal(h.cfg.SurvivalCommerceView.IsOpen(),true); assert.equal(h.store().IsOpen(),true);
    const reads=h.requests.length;
    current(h,'CommerceResultBack').events.onactivate();
    visibleMarket(h);
    assert.equal(requestCount(h,'purchase'),0);
    assert.equal(h.requests.length,reads,'repairing a hidden native panel only reasserts the modal/layer');
});

test('return with an uncertain transaction preserves its identity and never submits it again', () => {
    const h=harness(); h.cfg.SurvivalCommerceView.Open();
    h.walletSnapshot([points],{shop_points:1000,u_coin:100,shop_gold:0});
    assert.equal(h.cfg.SurvivalCommerceWallet.Checkout(points.sku),true);
    const purchase=h.requests.findLast(row=>row.payload.action==='purchase').payload;
    h.emit('survival_commerce_result',{action:'purchase',request_id:purchase.request_id,ok:0,terminal:0,error:'archive_pending'});
    assert.equal(h.cfg.SurvivalCommerceWallet.Inspect().result,'unknown');
    const durable=h.cfg.SurvivalCommercePending;
    h.store().Close(); current(h,'CommerceResultBack').events.onactivate();
    visibleMarket(h);
    assert.equal(h.cfg.SurvivalCommercePending,durable);
    assert.equal(h.cfg.SurvivalCommerceWallet.Inspect().pending.request_id,purchase.request_id);
    assert.equal(requestCount(h,'purchase'),1);
});

test('a refused shop-gold offer returns to the visible market without attempting an exchange', () => {
    const h=harness(), gold={...points,sku:'result_gold_fixture',currency:'shop_gold',enabled:0,disabled_reason:'shop_gold_not_open'};
    h.cfg.SurvivalCommerceView.Open(); h.walletSnapshot([gold],{shop_points:0,u_coin:100,shop_gold:0});
    assert.equal(h.cfg.SurvivalCommerceWallet.Checkout(gold.sku),false);
    assert.match(current(h,'CommerceResultStatus').text,/商城金币暂未开放/);
    h.store().Close(); current(h,'CommerceResultBack').events.onactivate();
    visibleMarket(h); assert.equal(requestCount(h,'purchase'),0);
});

test('return leaves the existing authenticated cash controller and its product action intact', () => {
    const h=harness(), payments=h.cfg.SurvivalPayments;
    failedExchange(h); h.store().Close(); current(h,'CommerceResultBack').events.onactivate();
    visibleMarket(h); assert.equal(h.cfg.SurvivalPayments,payments);
    h.cfg.SurvivalCommerceView.SelectCategory('all');
    const cash=h.cardList().find(row=>h.descendants(row,'BLMarketName').some(name=>name.text==='真实商品'));
    assert(cash,'the actual cash row remains in the restored marketplace');
    h.descendants(cash,'BLMarketBuy')[0].events.onactivate();
    assert.deepEqual(h.paidCheckouts,['paid_1']);
    assert.equal(requestCount(h,'purchase'),0,'cash still uses its existing controller rather than wallet purchase');
});

test('a retired result button cannot reopen the market after a wallet controller reload', () => {
    const h=harness(); failedExchange(h);
    const staleBack=current(h,'CommerceResultBack');
    h.load('commerce_wallet.js');
    h.cfg.SurvivalCommerceView.Close();
    staleBack.events.onactivate();
    assert.equal(h.cfg.SurvivalCommerceView.IsOpen(),false);
    assert.equal(h.store().IsOpen(),false);
    assert.equal(requestCount(h,'purchase'),0); assert.equal(h.paidCheckouts.length,0);
});
