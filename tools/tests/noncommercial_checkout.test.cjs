'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {harness,walletItem}=require('../shop_catalog_20261016/harness.cjs');
const {createHarness}=require('./fixtures/menus_v10_harness.cjs');

test('distributed checkout sends no cash events and keeps G-coin and points wallet settlement',()=>{
    const h=harness({developmentPayments:false,paid:{real_money_enabled:false,products:[],categories:[]},
        presentation:{groups:{home:['g_coin_item','points_item']}}});
    h.load('payment_test.js');
    const cash=h.cfg.SurvivalPayments;
    assert.equal(cash.IsRealMoneyEnabled(),false);
    cash.Open();cash.RefreshCatalog();assert.equal(cash.Checkout('u_coin_recharge'),false);
    assert.equal(h.cfg.SurvivalCommerceView.OpenRecharge(),false);
    const coin={...walletItem('coin'),sku:'g_coin_item',title:'G币道具',currency:'u_coin',currency_name:'G币',price:15};
    const points={...walletItem('points'),sku:'points_item',title:'积分道具'};
    h.walletSnapshot([coin,points],{u_coin:100,shop_points:100});
    const view=h.cfg.SurvivalCommerceView;view.SelectCategory('all');
    // A stale or injected paid snapshot cannot redirect a production wallet row.
    view.UpdateCatalog({real_money_enabled:true,products:[{...coin,title:'现金覆盖',amount_fen:99999,
        u_coin_price:99999,u_coin_per_yuan:100}],categories:[]});
    assert.deepEqual(Array.from(view.Inspect().visibleSkus),['g_coin_item','points_item']);
    view.SelectPurchaseType('u_coin');assert.deepEqual(Array.from(view.Inspect().visibleSkus),['g_coin_item']);
    const row=h.cardList()[0];assert.equal(h.descendants(row,'BLMarketPriceMain')[0].text,'15 G币');
    h.descendants(row,'BLMarketBuy')[0].events.onactivate();
    assert(h.root.FindChildTraverse('CommerceResultDialog'));
    assert.equal(h.descendants(h.root,'CommerceConfirmBuy').length,0);
    const request=h.requests.at(-1);assert.equal(request.name,'survival_commerce_request');
    assert.equal(request.payload.action,'purchase');assert.equal(request.payload.sku,'g_coin_item');
    assert(!('amount_fen' in request.payload)&&!('price' in request.payload));
    assert.equal(h.paidCheckouts.length,0);
    const recharge=h.root.FindChildTraverse('BlackLionMarketRecharge');assert.equal(recharge.visible,false);
    assert.equal(recharge.hittest,false);assert.equal(recharge.enabled,false);
    assert.equal(h.requests.filter(item=>item.name==='survival_payment_request').length,0);
});

test('cash-only month remains hidden while daily and existing pass rewards remain available',()=>{
    const h=createHarness();delete h.cfg.SurvivalDevelopmentPayments;
    for(const name of ['common/ui_registry.js','common/ui_components.js','ui_layers.js','archive_theme_tokens.js',
        'archive_parchment_data.js','archive_handoff_180de7e38b.js','archive_v10_semantics.js','common/archive_tooltip.js','daily_gw2_data.js'])h.load(name);
    h.load('daily_remaining_5d5c1152eb.js');h.cfg.SurvivalDaily.Open(false);
    h.emit('survival_daily_snapshot',{ok:true,sequence:1,today:25004,count:7,pending:0,has_pass:1,
        purchase_enabled:1,price:'58元',duration_days:30,ordinary_status:'claimed',premium:{status:'claimable'},calendar28:[],cycle:[],specials:[],missed:[]});
    assert.equal(h.nodes.PassPurchase.visible,false);assert.equal(h.nodes.PassPurchase.enabled,false);
    assert(!/58元|人民币|¥|￥/.test(h.nodes.PassPrice.text));
    h.click(h.nodes.PassPurchase);assert.equal(h.sent.filter(item=>item.name==='survival_pass_purchase').length,0);
    assert.equal(h.cfg.SurvivalDaily.Inspect().hasPass,true);
    h.click(h.nodes.DailyClaim);assert.equal(h.sent.at(-1).name,'survival_daily_claim');
    h.load('vip_window.js');assert(!/人民币|充值|元|¥|￥/.test(h.cfg.SurvivalVIPStatus.UnlockRules()));
});

test('missing and older payment APIs never redirect a wallet product to cash',()=>{
    for(const api of [null,{}, {IsRealMoneyEnabled:()=>false}]){
        const h=harness({paid:{products:[],categories:[]}});
        h.cfg.SurvivalPayments=api;
        const coin={...walletItem('startup'),sku:'startup_coin',currency:'u_coin',currency_name:'G币',price:12};
        h.walletSnapshot([coin],{u_coin:30,shop_points:0});
        h.cfg.SurvivalCommerceView.SelectCategory('all');
        assert.deepEqual(Array.from(h.cfg.SurvivalCommerceView.Inspect().visibleSkus),['startup_coin']);
        const row=h.cardList()[0];assert.equal(h.descendants(row,'BLMarketPriceMain')[0].text,'12 G币');
        h.descendants(row,'BLMarketBuy')[0].events.onactivate();
        assert(h.root.FindChildTraverse('CommerceResultDialog'));
        assert.equal(h.descendants(h.root,'CommerceConfirmBuy').length,0);
        const purchases=h.requests.filter(row=>row.payload.action==='purchase');
        assert.equal(purchases.length,1);assert.equal(purchases[0].payload.sku,'startup_coin');
        assert.equal(h.paidCheckouts.length,0);
    }
});
