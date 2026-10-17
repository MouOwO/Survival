const assert = require('node:assert/strict');
const test = require('node:test');
const {harness,walletItem}=require('../shop_catalog_20261016/harness.cjs');

test('Balance-side recharge opens the existing checkout without creating a payment or adding a goods row', () => {
    const h = harness();
    h.cfg.SurvivalCommerceView.Open();
    const before = h.cfg.SurvivalCommerceView.Inspect().productCount;
    const recharge = {sku:'u_coin_recharge',title:'U币充值',product_type:'recharge',enabled:1,
        amount_fen:100,max_quantity:999999,recharge_u_coin_per_unit:100,
        reward_lines:[{kind:'wallet',id:'u_coin',quantity:100,label:'U币'}]};
    h.updatePaid({...h.paid,products:[...h.paid.products,recharge]});
    assert.equal(h.cfg.SurvivalCommerceView.Inspect().productCount,before,'Recharge uses its own entry');
    const button = h.store().panel.FindChildTraverse('BlackLionMarketRecharge');
    assert(button && button.enabled && button.hittestchildren===false);
    assert.equal(button.Children().length,1);
    assert.equal(button.Children()[0].paneltype,'Image');
    assert.equal(button.Children()[0].image,'file://{images}/control_icons/24px/plus.svg');
    button.events.onactivate();
    assert.deepEqual(h.paidCheckouts,['u_coin_recharge']);
    assert.equal(h.cfg.SurvivalCommerceView.IsOpen(),false);
    assert.equal(h.requests.filter(r=>r.name==='survival_payment_request'&&r.payload.action==='create').length,0,
        'Opening recharge must still require confirmation before an order is created');
});

test('Real catalogs use the independent five-tab market, paginate 40 rows, and retain both purchase routes', () => {
    const h = harness();
    h.cfg.SurvivalCommerceView.Open();
    assert.equal(h.cfg.SurvivalCommerceView.Inspect().productCount, 1);
    const products = Array.from({length:50}, (_, i) => walletItem(i));
    const productData = JSON.stringify(products);
    h.walletSnapshot(products);
    const store = h.store();
    assert.equal(store.panel.style.width, h.cfg.SurvivalShopV10.width + 'px');
    assert.equal(store.panel.style.height, h.cfg.SurvivalShopV10.height + 'px');
    assert.equal(store.layout, 'black_lion_list');
    assert(!store.panel.BHasClass('MenuV10Page'));
    assert(!h.descendants(store.panel, 'MenuV10Sidebar').length, 'The independent market has no archive sidebar');
    const tabs = store.panel.FindChildTraverse('BlackLionMarketTabs');
    assert.deepEqual(tabs.Children().map(p => p.id), ['BLMarketSection_home','BLMarketSection_bundles','BLMarketSection_promotions','BLMarketSection_vip','BLMarketSection_all']);
    assert.deepEqual(tabs.Children().map(p => h.descendants(p, 'RCTabText')[0].text), ['首页','礼包','促销','VIP','全部商品']);
    assert.equal(h.cfg.SurvivalCommerceView.Inspect().productCount, 51);
    const walletTab = store.panel.FindChildTraverse('BLMarketSection_all');
    walletTab.events.onactivate();
    const firstCards = h.cardList();
    assert.equal(firstCards.length, 40);
    assert.equal(store.content.Children()[0].style.flowChildren, 'down', 'Goods are a scrolling vertical list');
    assert(firstCards.every(p => p.BHasClass('BLMarketRow')), 'Each displayed product uses the actual market row');
    assert.equal(firstCards[0].__menuCell.namePanel.text, '积分装备 0');
    const next = h.descendants(store.actions, 'CJPageAction')[1]; next.events.onactivate();
    assert.equal(h.cardList().length, 11, 'All goods includes the paid SKU after the fifty wallet products'); assert.equal(h.cardList()[0].__menuCell.namePanel.text, '积分装备 40');
    const card = h.cardList()[0]; card.events.onmouseover();
    const tip = card.__purpleDetail; assert(tip.BHasClass('Visible'));
    const detailBody = h.descendants(tip, 'MenuV10CommerceDetailBody')[0];
    assert.deepEqual(detailBody.Children().map(p => [...p.classes][0]), ['MenuV10CommerceDetailContent'],
        'The bounded scroll viewport owns one naturally sized content panel');
    const detailContent = detailBody.Children()[0];
    assert.deepEqual(detailContent.Children().map(p => [...p.classes][0]),
        ['RCPurpleDetailTitle','RCPurpleDetailQuality','RCProductEffect']);
    assert(detailContent.Children().every(p => p.paneltype === 'Label'), 'The content contains only the three information labels');
    assert.equal(detailContent.Children()[0].text, '积分装备 40');
    assert.equal(detailContent.Children()[1].text, '');
    assert.equal(detailContent.Children()[1].visible, false, 'An unknown grade is omitted');
    assert.equal(detailContent.Children()[2].text, '攻击力 +10');
    assert.equal(h.requests.filter(r => r.payload.action === 'purchase').length, 0, 'Hovering cannot purchase');
    assert.equal(h.descendants(card, 'BLMarketPriceMain')[0].text, '10 积分', 'The actual product row retains its authoritative price');
    const purchaseControl = h.descendants(card, 'BLMarketBuy')[0] || card;
    purchaseControl.events.onactivate();
    assert.equal(h.cfg.SurvivalCommerceView.IsOpen(), false);
    assert.equal(h.requests.filter(r => r.payload.action === 'purchase').length, 0, 'Inspecting the item only opens existing confirmation');
    const confirm = h.menus().find(m => m.panel.BHasClass('MenuV10Exchange'));
    assert(confirm && confirm.IsOpen(), 'Wallet checkout is inside the same V10 geometry');
    assert.match(h.descendants(confirm.content, 'CommerceConfirmCopy')[0].text, /售价：10 商城积分/);
    h.descendants(confirm.actions, 'CommerceConfirmBuy')[0].events.onactivate();
    const buy = h.requests.findLast(r => r.payload.action === 'purchase');
    assert.equal(buy.payload.sku, 'wallet_40');
    h.cfg.SurvivalCommerceView.Open();
    store.panel.FindChildTraverse('BLMarketSection_home').events.onactivate();
    const paidCard = h.cardList()[0];
    const stalePurchase = (h.descendants(paidCard, 'BLMarketBuy')[0] || paidCard).events.onactivate;
    stalePurchase();
    assert.deepEqual(h.paidCheckouts, ['paid_1']);
    assert.equal(JSON.stringify(products), productData, 'The new list never rewrites server prices, effects or categories');
    const originalPanel = store.panel;
    h.cfg.SurvivalCommerceView.Dispose();
    assert(!originalPanel.IsValid(), 'Disposal deletes the independent window');
    assert(!h.descendants(h.root, 'BLMarketWindow').length);
    assert.doesNotThrow(stalePurchase, 'A captured deleted product purchase callback is inert');
    for (const timer of h.timers.slice()) if (!timer.cancelled) assert.doesNotThrow(timer.fn);
    assert.deepEqual(h.paidCheckouts, ['paid_1'], 'Late callbacks cannot create another checkout');
});
