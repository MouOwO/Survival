const assert = require('node:assert/strict');
const test = require('node:test');
const {harness, walletItem} = require('../shop_catalog_20261016/harness.cjs');

const types = ['u_coin', 'shop_points', 'all'];
const captions = ['G币', '积分', '全部'];

function makeFixture() {
    const points = sku => ({...walletItem(sku), sku, title:sku});
    const cash = (sku, extra = {}) => ({sku, title:sku, category_id:'item', product_type:'single',
        icon:'items/rapier.png', enabled:1, owned:0, purchase_limit:0, amount_fen:250,
        reward_lines:[{id:'initial_gold', kind:'stat', label:'初始金币', quantity:10}], ...extra});
    const wallet = [points('points_a'), points('points_b'),
        {...points('gold_closed'), currency:'shop_gold', currency_name:'商城金币', enabled:0,
            disabled_reason:'shop_gold_not_open'},
        {...points('points_bundle'), product_type:'bundle', category_id:'bundles'}];
    const paid = {catalog_hash:'filter-fixture-1', categories:[{id:'item', label:'道具'}], products:[
        cash('legacy_cash'), cash('u_coin_cash', {currency:'u_coin', amount_fen:2500, u_coin_price:2500, u_coin_per_yuan:100}),
        cash('vip_bundle', {product_type:'bundle', category_id:'vip', required_vip_level:2,
            enabled:0, disabled_reason:'vip_level_insufficient'})]};
    const h = harness({paid, presentation:{groups:{
        home:['legacy_cash', 'points_a', 'u_coin_cash', 'points_b'],
        all:['points_b', 'u_coin_cash', 'points_a', 'legacy_cash']}}});
    h.cfg.SurvivalCommerceView.Open();
    h.walletSnapshot(wallet);
    return {h, view:h.cfg.SurvivalCommerceView, wallet, paid};
}

function find(h, id) { return h.store().panel.FindChildTraverse(id); }
function allNodes(panel) { return [panel, ...panel.Children().flatMap(allNodes)]; }
function choose(h, id) {
    find(h, 'BLMarketPurchaseType_' + id).events.onactivate();
    const selected = find(h, 'BLMarketPurchaseType').Children().filter(p => p.BHasClass('UISelected'));
    assert.deepEqual(selected.map(p => p.id), ['BLMarketPurchaseType_' + id], 'Exactly one type is selected');
}
function tab(h, id) { find(h, 'BLMarketSection_' + id).events.onactivate(); }
function cardNames(h) {
    return h.cardList().filter(p => p.BHasClass('RCProduct')).map(p => p.__menuCell.namePanel.text);
}
function visibleSkus(view) { return Array.from(view.Inspect().visibleSkus); }
function assertNoPurchase(h) {
    assert.equal(h.requests.filter(r => ['purchase', 'create'].includes(r.payload.action)).length, 0,
        'Filtering, changing tabs and catalog updates never submit an order');
    assert.deepEqual(h.paidCheckouts, []);
}
function buyRow(h, sku) {
    const card = h.cardList().find(p => p.BHasClass('RCProduct') && p.__menuCell.namePanel.text === sku);
    assert(card, 'Expected a real product row for ' + sku);
    const button = h.descendants(card, 'BLMarketBuy')[0];
    assert(button && button.enabled, 'The original buy control is actionable');
    button.events.onactivate();
}

test('The three-option control defaults to all and filters actual rows without changing their order', () => {
    const {h, view, wallet, paid} = makeFixture();
    const original = JSON.stringify({wallet, paid});
    assert.equal(view.Inspect().purchaseType, 'all');
    const control = find(h, 'BLMarketPurchaseType');
    assert(control && control.paneltype === 'Panel');
    assert(allNodes(control).some(p => p.paneltype === 'Label' && p.text === '全部'));
    const options = control.Children().filter(p => p.paneltype === 'Button');
    assert.deepEqual(options.map(p => p.id), types.map(id => 'BLMarketPurchaseType_' + id));
    assert.deepEqual(options.map(p => allNodes(p).find(n => n.paneltype === 'Label').text), captions);
    assert.equal(find(h, 'BLMarketPurchaseTypeMenu'), undefined);
    const balances = h.descendants(h.store().panel, 'BLMarketBalance')[0];
    assert.deepEqual(h.descendants(balances, 'BLMarketBalanceText').map(p => p.text), ['G币 12', '积分 500']);
    choose(h, 'all');
    tab(h, 'all');
    assert.deepEqual(cardNames(h), ['points_b', 'u_coin_cash', 'points_a', 'legacy_cash']);
    choose(h, 'shop_points');
    assert.equal(view.Inspect().purchaseType, 'shop_points');
    assert.deepEqual(cardNames(h), ['points_b', 'points_a']);
    assert.deepEqual(visibleSkus(view), ['points_b', 'points_a']);
    choose(h, 'u_coin');
    assert.deepEqual(cardNames(h), ['u_coin_cash', 'legacy_cash'], 'Legacy RMB cash uses the cash/U-coin filter');
    choose(h, 'all');
    assert.deepEqual(cardNames(h), ['points_b', 'u_coin_cash', 'points_a', 'legacy_cash']);
    for (const bad of ['', 'cash', 'shop_gold', '__proto__', null, {}]) {
        assert.equal(view.SelectPurchaseType(bad), false);
        assert.equal(view.Inspect().purchaseType, 'all');
    }
    assert.equal(JSON.stringify({wallet, paid}), original, 'Presentation never rewrites server product data');
    assertNoPurchase(h);
});

test('Filtering resets incremental loading and appends every matching product in order without pagination', () => {
    const products = Array.from({length:45}, (_, i) => ({...walletItem(i), sort_order:i * 2 + 1}));
    const paid = {categories:[], products:Array.from({length:5}, (_, i) => ({
        sku:'cash_' + i, title:'cash_' + i, category_id:'item', product_type:'single',
        enabled:1, amount_fen:100, sort_order:i * 2, reward_lines:[]}))};
    const h = harness({paid});
    const view = h.cfg.SurvivalCommerceView;
    view.Open(); h.walletSnapshot(products); tab(h, 'all');
    const expectedAll = [...products, ...paid.products].sort((a, b) => a.sort_order - b.sort_order);
    assert.deepEqual(cardNames(h), expectedAll.slice(0, 20).map(p => p.title));
    assert.equal(h.loadNextBatch(), 40);
    assert.equal(h.loadNextBatch(), 50);
    assert.deepEqual(cardNames(h), expectedAll.map(p => p.title));
    assert.equal(cardNames(h).length, 50, 'Mixed catalogs are fully reachable after the old forty-row boundary');
    assert.equal(h.descendants(h.store().actions, 'CJPageAction').length, 0);
    assert.equal(h.descendants(h.store().actions, 'CJPageLabel').length, 0);
    choose(h, 'shop_points');
    assert.equal(view.Inspect().page, 0);
    assert.equal(cardNames(h).length, 20, 'Changing the type resets the loaded batch');
    assert.deepEqual(visibleSkus(view), products.map(p => p.sku), 'Semantic filtering includes products not yet rendered');
    assert.equal(h.loadNextBatch(), 40);
    assert.equal(h.loadNextBatch(), 45);
    assert.deepEqual(cardNames(h), products.map(p => p.title));
    assert.deepEqual(visibleSkus(view), products.map(p => p.sku));
    choose(h, 'u_coin');
    assert.equal(view.Inspect().page, 0);
    assert.deepEqual(cardNames(h), paid.products.map(p => p.title));
    assert.equal(h.descendants(h.store().actions, 'CJPageAction').length, 0);
    assertNoPurchase(h);
});

test('Incremental scroll polling runs only while open and stale callbacks cannot append after category, filter or disposal changes', () => {
    const products = Array.from({length:55}, (_, i) => ({...walletItem(i), sort_order:i}));
    const h = harness({paid:{categories:[], products:[]}}), view = h.cfg.SurvivalCommerceView;
    h.walletSnapshot(products);
    assert.equal(h.pendingTimers().length, 0, 'An unopened market never starts a scroll poll');
    view.Open(); tab(h, 'all');
    assert.equal(cardNames(h).length, 20);
    assert.equal(h.pendingTimers().length, 1);
    const first = h.cardList()[0];
    h.advanceTimers();
    assert.equal(h.cardList().length, 20, 'A normal top-of-list poll does not load a batch');
    assert.equal(h.cardList()[0], first);
    const beforeClose = h.pendingTimers()[0].fn;
    view.Close();
    assert.equal(h.pendingTimers().length, 0, 'Closing cancels the scroll timer');
    assert.doesNotThrow(beforeClose);
    assert.equal(h.cardList().length, 20);
    view.Open();
    const beforeFilter = h.pendingTimers()[0].fn;
    choose(h, 'u_coin');
    assert.equal(cardNames(h).length, 0);
    assert.doesNotThrow(beforeFilter);
    assert.equal(cardNames(h).length, 0, 'A stale callback cannot append into a different purchase type');
    choose(h, 'shop_points');
    const beforeCategory = h.pendingTimers()[0].fn;
    tab(h, 'bundles');
    assert.equal(cardNames(h).length, 0);
    assert.doesNotThrow(beforeCategory);
    assert.equal(cardNames(h).length, 0, 'A stale callback cannot append into a different category');
    tab(h, 'all');
    const beforeRefresh = h.pendingTimers()[0].fn;
    h.walletSnapshot(products.slice(0, 12));
    assert.equal(cardNames(h).length, 12);
    assert.doesNotThrow(beforeRefresh);
    assert.equal(cardNames(h).length, 12, 'A stale callback cannot restore items removed by an authoritative refresh');
    h.walletSnapshot(products);
    const beforeDispose = h.pendingTimers()[0].fn;
    view.Dispose();
    assert.equal(h.pendingTimers().length, 0);
    assert.doesNotThrow(beforeDispose);
    assertNoPurchase(h);
});

test('Purchase type survives independent tabs, authenticated catalog refreshes and reopening', () => {
    const {h, view, wallet, paid} = makeFixture();
    choose(h, 'shop_points');
    tab(h, 'bundles');
    assert.deepEqual(cardNames(h), ['points_bundle']);
    tab(h, 'vip');
    assert.equal(view.Inspect().purchaseType, 'shop_points');
    assert.deepEqual(cardNames(h), []);
    choose(h, 'u_coin');
    assert.deepEqual(cardNames(h), ['vip_bundle']);
    const vipBuy = h.descendants(h.cardList()[0], 'BLMarketBuy')[0];
    assert.equal(vipBuy.enabled, false, 'The display filter cannot bypass a VIP purchase restriction');
    vipBuy.events.onactivate();
    tab(h, 'all');
    assert.deepEqual(cardNames(h), ['u_coin_cash', 'legacy_cash']);
    h.walletSnapshot([...wallet, {...walletItem('new'), title:'new_points'}]);
    assert.equal(view.Inspect().purchaseType, 'u_coin');
    assert.deepEqual(cardNames(h), ['u_coin_cash', 'legacy_cash']);
    const freshCash = {...paid.products[0], sku:'fresh_cash', title:'fresh_cash'};
    const updatedPaid = {...paid, catalog_hash:'filter-fixture-2', products:[...paid.products, freshCash]};
    h.updatePaid(updatedPaid);
    assert.equal(view.Inspect().purchaseType, 'u_coin');
    assert.deepEqual(cardNames(h), ['u_coin_cash', 'legacy_cash', 'fresh_cash']);
    view.Close(); view.Open();
    assert.equal(view.Inspect().purchaseType, 'u_coin');
    assert.equal(view.Inspect().category, 'all');
    assert.deepEqual(cardNames(h), ['u_coin_cash', 'legacy_cash', 'fresh_cash']);
    tab(h, 'home');
    assert.equal(view.Inspect().purchaseType, 'u_coin');
    assert.deepEqual(cardNames(h), ['legacy_cash', 'u_coin_cash'], 'The home catalog retains its own reviewed ordering');
    assertNoPurchase(h);
});

test('Inline selection survives reopening and disposed controls cannot change the view', () => {
    const {h, view} = makeFixture();
    choose(h, 'shop_points');
    assert(allNodes(find(h, 'BLMarketPurchaseType')).some(p => p.text === '积分'));
    view.Close();
    view.Open();
    assert.equal(view.Inspect().purchaseType, 'shop_points');
    const control = find(h, 'BLMarketPurchaseType');
    const lateSelection = find(h, 'BLMarketPurchaseType_u_coin').events.onactivate;
    view.Dispose();
    assert(!control.IsValid());
    assert.equal(h.root.FindChildTraverse('BLMarketPurchaseType'), undefined);
    assert.doesNotThrow(lateSelection);
    assertNoPurchase(h);
});

test('Filtered product buttons keep the loaded market open through wallet confirmation and both original cash checkout callbacks', () => {
    const {h, view} = makeFixture();
    tab(h, 'all'); choose(h, 'shop_points');
    assertNoPurchase(h);
    const pointsRows = h.cardList().slice();
    buyRow(h, 'points_b');
    assert.equal(view.IsOpen(), true, 'Wallet confirmation keeps the market underneath open');
    assert.equal(view.Inspect().purchaseType, 'shop_points');
    assert.equal(h.cardList().length, pointsRows.length);
    pointsRows.forEach((row, index) => assert.equal(h.cardList()[index], row, 'Confirmation retains the loaded filtered rows'));
    assertNoPurchase(h);
    const confirm = h.menus().find(menu => menu.panel.BHasClass('MenuV10Exchange'));
    assert(confirm && confirm.IsOpen());
    assert.match(h.descendants(confirm.content, 'CommerceConfirmCopy')[0].text, /售价：10 (?:商城)?积分/);
    const confirmBuy = h.descendants(confirm.actions, 'CommerceConfirmBuy')[0];
    confirmBuy.events.onactivate(); confirmBuy.events.onactivate();
    const purchases = h.requests.filter(r => r.payload.action === 'purchase');
    assert.equal(purchases.length, 1);
    assert.equal(purchases[0].payload.sku, 'points_b');
    for (const key of ['price', 'balance', 'provider']) assert(!(key in purchases[0].payload));
    choose(h, 'u_coin');
    const cashRows = h.cardList().slice();
    buyRow(h, 'u_coin_cash');
    assert.deepEqual(h.paidCheckouts, ['u_coin_cash']);
    assert.equal(view.IsOpen(), true, 'G-coin checkout keeps the market underneath open');
    assert.equal(h.cardList().length, cashRows.length);
    cashRows.forEach((row, index) => assert.equal(h.cardList()[index], row, 'Cash checkout retains the loaded filtered rows'));
    assert.equal(view.Inspect().purchaseType, 'u_coin');
    buyRow(h, 'legacy_cash');
    assert.deepEqual(h.paidCheckouts, ['u_coin_cash', 'legacy_cash']);
    assert.equal(view.IsOpen(), true, 'Legacy cash checkout also preserves the underlying market');
    cashRows.forEach((row, index) => assert.equal(h.cardList()[index], row));
    assert.equal(h.requests.filter(r => r.payload.action === 'purchase').length, 1);
});
