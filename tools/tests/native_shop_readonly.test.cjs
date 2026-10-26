"use strict";
const test = require('node:test');
const assert = require('node:assert/strict');
const {harness, walletItem} = require('../shop_catalog_20261016/harness.cjs');

const clone = value => JSON.parse(JSON.stringify(value));
function deepFreeze(value) {
    if (value && typeof value === 'object') {
        Object.values(value).forEach(deepFreeze);
        Object.freeze(value);
    }
    return value;
}
function setup(options = {}) {
    const h = harness({developmentPayments:false, homeCatalogFixture:false, ...options});
    h.load('arcade_shop_catalog.js');
    const snapshot = clone(h.cfg.SurvivalArcadeShopCatalog);
    const view = h.cfg.SurvivalCommerceView;
    const calls = {paidRefresh:0, walletRefresh:0, walletCheckout:0, rows:[]};
    h.cfg.SurvivalPayments.RefreshCatalog = () => { calls.paidRefresh++; };
    h.cfg.SurvivalCommerceWallet.Refresh = () => { calls.walletRefresh++; return false; };
    h.cfg.SurvivalCommerceWallet.Checkout = () => { calls.walletCheckout++; return false; };
    const nativeRow = h.cfg.SurvivalBlackLionMarket.Row;
    h.cfg.SurvivalBlackLionMarket.Row = function(parent, item, props) {
        const row = nativeRow(parent, item, props);
        calls.rows.push({row, item, props});
        return row;
    };
    const requestCount = h.requests.length;
    const owner = {};
    return {...h, view, calls, snapshot, owner, requestCount};
}
function rowRecord(h, row) {
    const found = h.calls.rows.findLast(record => record.row === row);
    assert(found, 'Visible row was built by the original black lion Row');
    return found;
}
function rowText(h, row, cls) {
    const node = h.descendants(row, cls)[0];
    assert(node, 'Original row exposes ' + cls);
    return node.text;
}
function noFinancialWork(h) {
    assert.equal(h.calls.paidRefresh, 0, 'Public browsing does not request an authenticated cash catalog');
    assert.equal(h.calls.walletRefresh, 0, 'Public browsing does not request account wallet state');
    assert.equal(h.calls.walletCheckout, 0, 'Public browsing cannot enter wallet checkout');
    assert.equal(h.paidCheckouts.length, 0, 'Public browsing cannot enter payment checkout');
    assert.equal(h.requests.length, h.requestCount, 'Public browsing sends no game request');
}
function openAll(h, snapshot = h.snapshot, owner = h.owner) {
    assert.equal(h.view.OpenReadonly(snapshot, owner), true);
    assert.equal(h.view.SelectCategory('all'), true);
    return h.loadAllBatches();
}

test('The public catalog uses the existing black lion window, skin, five sections and incremental rows', () => {
    const h = setup();
    assert.equal(h.snapshot.products.length, 173, 'Use the actual compiler output');
    assert.equal(h.view.OpenReadonly(h.snapshot, h.owner), true);
    assert.equal(h.view.IsReadonlyOpen(h.owner), true);
    assert.equal(h.store().panel.id, 'BlackLionMarketWindow');
    assert(h.store().panel.BHasClass('BLMarketWindow'));
    assert(h.store().panel.BHasClass('BLMarketV10'));
    assert.equal(h.store().layout, 'black_lion_list');
    assert.equal(h.store().skinVersion, 10);
    assert.deepEqual(h.store().sidebar.Children().map(panel => panel.id),
        ['home', 'bundles', 'promotions', 'vip', 'all'].map(id => 'BLMarketSection_' + id));
    assert.equal(h.view.SelectCategory('all'), true);
    assert.equal(h.cardList().length, 20, 'The original first batch remains bounded');
    assert.equal(h.view.Inspect().hasMoreProducts, true);
    const first = h.cardList().slice();
    h.loadNextBatch();
    assert.equal(h.cardList().length, 40);
    first.forEach((row, index) => assert.equal(h.cardList()[index], row, 'Scrolling appends without replacing existing hovered rows'));
    const all = h.loadAllBatches();
    assert.equal(all.length, 173);
    assert(all.every(row => row.BHasClass('BLMarketRow')));
    assert.equal(h.view.Inspect().hasMoreProducts, false);
    noFinancialWork(h);
});

test('Every formal offer survives including separate cash and wallet prices for the same SKU', () => {
    const h = setup(), before = JSON.stringify(h.snapshot);
    deepFreeze(h.snapshot);
    const rows = openAll(h), records = rows.map(row => rowRecord(h, row));
    assert.deepEqual(records.map(record => record.item.offer_id).sort(), h.snapshot.products.map(item => item.offer_id).sort());
    assert.equal(new Set(records.map(record => record.item.offer_id)).size, 173);
    const cash = h.snapshot.products.find(item => item.currency === 'CNY' && h.snapshot.products.some(other => other.sku === item.sku && other.currency !== 'CNY'));
    assert(cash, 'Formal data includes both payment methods for one SKU');
    const wallet = h.snapshot.products.find(item => item.sku === cash.sku && item.currency !== 'CNY');
    for (const product of [cash, wallet]) {
        const record = records.find(record => record.item.offer_id === product.offer_id);
        assert(record);
        assert.equal(record.item.sku, product.sku);
        assert.equal(record.item.price, product.price);
        assert.equal(record.item.currency, product.currency);
        assert.deepEqual(clone(record.item.reward_lines), product.reward_lines);
        const price = rowText(h, record.row, 'BLMarketPriceMain');
        if (product.currency === 'CNY') assert.equal(price, '¥' + (product.price / 100).toFixed(2));
        else assert(price.includes(String(product.price)) && price.includes({u_coin:'G币', shop_points:'商城积分', shop_gold:'商城金币'}[product.currency]));
    }
    for (const sku of ['archive_pass_monthly', 'special_lottery_ticket_single', 'u_coin_recharge']) {
        const product = h.snapshot.products.find(item => item.sku === sku && item.currency === 'CNY');
        assert(product);
        const record = records.find(record => record.item.offer_id === product.offer_id);
        assert.equal(rowText(h, record.row, 'BLMarketPriceMain'), '¥' + (product.price / 100).toFixed(2));
    }
    assert.equal(JSON.stringify(h.snapshot), before, 'The public catalog is never mutated or converted into an authenticated receipt');
    noFinancialWork(h);
});

test('Readonly rows show unknown account values and disable every cash and exchange action', () => {
    const h = setup({developmentPayments:true});
    const rows = openAll(h);
    const balances = h.descendants(h.store().panel, 'BLMarketBalanceText');
    assert.equal(balances.length, 2);
    balances.forEach(label => assert.match(label.text, /—/));
    for (const row of rows) {
        const {item} = rowRecord(h, row), buy = h.descendants(row, 'BLMarketBuy')[0];
        assert.equal(Object.hasOwn(item, 'owned'), false, 'Unknown inventory is not rewritten to zero');
        assert.equal(Object.hasOwn(item, 'enabled'), false, 'A public offer is never authorized as purchasable');
        assert.equal(buy.enabled, false);
        assert.match(rowText(h, row, 'BLMarketOwned'), /—/);
        if (buy.events.onactivate) buy.events.onactivate();
        if (row.events.onactivate) row.events.onactivate();
        if (row.__menuCell.iconPanel.events.onactivate) row.__menuCell.iconPanel.events.onactivate();
    }
    assert.equal(h.view.OpenRecharge(), false);
    assert.equal(h.view.OpenTicketPurchase('special'), false);
    const recharge = h.store().panel.FindChildTraverse('BlackLionMarketRecharge');
    assert(recharge);
    assert(recharge.visible === false || recharge.enabled === false, 'Existing recharge control is unavailable in read-only mode');
    if (recharge.events.onactivate) recharge.events.onactivate();
    noFinancialWork(h);
});

test('Original product details display formal limits and distinguish them from unknown account eligibility', () => {
    const h = setup(), rows = openAll(h);
    const limited = rows.find(row => {
        const item = rowRecord(h, row).item;
        return item.purchase_limit > 0 && item.required_vip_level > 0;
    });
    assert(limited, 'Formal catalog has a limited VIP product');
    const item = rowRecord(h, limited).item;
    assert(limited.__purpleDetail, 'The original tooltip is retained');
    const copy = h.descendants(limited.__purpleDetail, 'RCProductEffect').map(label => label.text).join('\n');
    assert.match(copy, /配置限购/);
    assert(copy.includes(String(item.purchase_limit)));
    assert.match(copy, /VIP/);
    assert(copy.includes(String(item.required_vip_level)));
    assert.match(copy, /未知/);
    assert.match(copy, /余额|持有|资格|剩余/);
    assert.match(h.descendants(h.store().panel, 'BLMarketNotice')[0].text, /收款.*兑换.*未开放/);
    noFinancialWork(h);
});

test('The existing currency and section controls filter public offers without issuing account requests', () => {
    const h = setup();
    openAll(h);
    for (const type of ['u_coin', 'shop_points', 'all']) {
        assert.equal(h.view.SelectPurchaseType(type), true);
        const rows = h.loadAllBatches();
        const actual = rows.filter(row => row.BHasClass('BLMarketRow')).map(row => rowRecord(h, row).item);
        assert.equal(actual.length, h.snapshot.products.filter(item => type === 'all' || item.currency === type).length);
        assert(actual.every(item => type === 'all' || item.currency === type));
    }
    for (const group of ['home', 'bundles', 'promotions', 'vip', 'all']) {
        assert.equal(h.view.SelectCategory(group), true, 'Original section is still selectable: ' + group);
        h.loadAllBatches();
    }
    assert.equal(h.cardList().length, 173);
    noFinancialWork(h);
});

test('Owner handoff, close and stale row callbacks cannot operate a newer read-only window', () => {
    const h = setup();
    openAll(h);
    const oldRow = h.cardList()[0], oldBuy = h.descendants(oldRow, 'BLMarketBuy')[0].events.onactivate;
    const nextOwner = {};
    assert.equal(h.view.OpenReadonly(h.snapshot, nextOwner), true);
    assert.equal(h.view.IsReadonlyOpen(h.owner), false);
    assert.equal(h.view.IsReadonlyOpen(nextOwner), true);
    assert.equal(h.view.CloseReadonly(h.owner), false);
    assert.equal(h.view.IsReadonlyOpen(nextOwner), true, 'Old controller disposal cannot close the replacement window');
    oldBuy();
    assert.equal(h.view.IsReadonlyOpen(nextOwner), true);
    assert.equal(h.view.CloseReadonly(nextOwner), true);
    assert.equal(h.view.IsOpen(), false);
    assert.equal(h.view.IsReadonlyOpen(nextOwner), false);
    assert.equal(h.view.CloseReadonly(nextOwner), false);
    assert.equal(h.pendingTimers().length, 0, 'Closing cancels incremental loading');
    noFinancialWork(h);
});

test('Authenticated catalog updates are buffered while browsing and restored when normal shopping resumes', () => {
    const h = setup({developmentPayments:true});
    openAll(h);
    const currentRows = h.cardList().slice(), currentBalances = h.descendants(h.store().panel, 'BLMarketBalanceText').map(label => label.text);
    const cash = {sku:'authenticated_cash',title:'已认证现金商品',category_id:'item',product_type:'single',enabled:true,owned:0,purchase_limit:0,
        amount_fen:900,currency:'u_coin',u_coin_price:900,u_coin_per_yuan:100,reward_lines:[]};
    const points = {...walletItem('authenticated'),title:'已认证积分商品',owned:2,purchase_limit:0};
    const paid = {catalog_hash:'AUTHENTICATED_NEW',products:[cash],categories:[{id:'item',label:'道具与材料'}]};
    const wallet = {products:[points],categories:[{id:'item',label:'道具与材料'}],balances:{u_coin:123,shop_points:456,shop_gold:0}};
    const beforePaid = JSON.stringify(paid), beforeWallet = JSON.stringify(wallet);
    h.updatePaid(paid);
    h.view.UpdateWalletCatalog(wallet);
    assert.equal(h.view.IsReadonlyOpen(h.owner), true);
    assert.deepEqual(h.cardList(), currentRows, 'A late authenticated response cannot replace the visible public list');
    assert.deepEqual(h.descendants(h.store().panel, 'BLMarketBalanceText').map(label => label.text), currentBalances, 'Late balances remain unknown in public browsing');
    noFinancialWork(h);
    h.view.CloseReadonly(h.owner);
    h.view.Open();
    assert.equal(h.view.IsReadonlyOpen(h.owner), false);
    assert.equal(h.view.SelectCategory('all'), true);
    h.loadAllBatches();
    assert.deepEqual(h.cardList().map(row => rowRecord(h, row).item.sku).sort(), [cash.sku, points.sku].sort());
    for (const row of h.cardList()) {
        const record = rowRecord(h, row);
        assert.equal(record.item.enabled, record.item.sku === cash.sku ? cash.enabled : points.enabled,
            'Read-only browsing did not overwrite authenticated eligibility');
        assert.equal(h.descendants(row, 'BLMarketBuy')[0].enabled, true, 'Returning to authenticated shopping restores the real row action');
    }
    const labels = h.descendants(h.store().panel, 'BLMarketBalanceText').map(label => label.text).join('\n');
    assert.match(labels, /123/);
    assert.match(labels, /456/);
    assert.equal(h.calls.paidRefresh, 1, 'Normal shopping retains its authenticated refresh');
    assert.equal(h.calls.walletRefresh, 1);
    assert.equal(JSON.stringify(paid), beforePaid);
    assert.equal(JSON.stringify(wallet), beforeWallet);
    assert.equal(h.paidCheckouts.length, 0);
    assert.equal(h.calls.walletCheckout, 0);
});

test('Invalid snapshots fail closed without replacing a valid owner or sending a request', () => {
    const h = setup();
    openAll(h);
    for (const mutation of [
        data => { data.schema_version = 2; },
        data => { data.checkout_enabled = true; },
        data => { data.catalog_sha256 = 'not-a-catalog-digest'; },
        data => { data.products[0].price = -1; },
        data => { data.products[0].price = 1.5; },
        data => { data.products[0].currency = 'USD'; },
        data => { data.products[0].offer_id = 'wallet:' + data.products[0].sku; },
        data => { data.products.push(clone(data.products[0])); }
    ]) {
        const bad = clone(h.snapshot); mutation(bad);
        assert.equal(h.view.OpenReadonly(bad, {}), false);
        assert.equal(h.view.IsReadonlyOpen(h.owner), true, 'Invalid input cannot displace the active valid snapshot');
    }
    assert.equal(h.view.OpenReadonly(h.snapshot, null), false);
    noFinancialWork(h);
});

test('Returning through the ordinary Open action restores authenticated mode and closes its old read-only lease', () => {
    const h = setup({developmentPayments:true});
    openAll(h);
    h.view.Open();
    assert.equal(h.view.IsReadonlyOpen(h.owner), false);
    assert.equal(h.view.IsOpen(), true);
    assert.equal(h.view.CloseReadonly(h.owner), false, 'A retired lease cannot close normal shopping');
    assert.equal(h.view.IsOpen(), true);
    assert.equal(h.calls.paidRefresh, 1);
    assert.equal(h.calls.walletRefresh, 1);
    assert.equal(h.paidCheckouts.length, 0);
    assert.equal(h.calls.walletCheckout, 0);
});

test('The normal menu action delegates to an available Arcade controller before reading authenticated services', () => {
    const h = setup({developmentPayments:true});
    let opens = 0;
    const controller = {
        IsAvailable() { return true; },
        Open() { opens++; return h.view.OpenReadonly(h.snapshot, controller); }
    };
    h.cfg.SurvivalArcadeReadOnlyShop = controller;
    assert.equal(h.view.Open(), true);
    assert.equal(opens, 1);
    assert.equal(h.view.IsReadonlyOpen(controller), true);
    assert.equal(h.view.OpenRecharge(), false);
    assert.equal(h.view.OpenTicketPurchase('special'), false);
    assert.equal(h.view.Open(), true);
    assert.equal(opens, 2, 'Repeated native menu actions remain owned by the active Arcade controller');
    assert.equal(h.view.CloseReadonly(controller), true);
    assert.equal(h.view.OpenRecharge(), false, 'Available Arcade state blocks alternate cash entry even with its list closed');
    assert.equal(h.view.OpenTicketPurchase('special'), false);
    noFinancialWork(h);
});

test('Reload retires incremental work and stale owners without disturbing the replacement native window', () => {
    const h = setup();
    assert.equal(h.view.OpenReadonly(h.snapshot, h.owner), true);
    const retired = h.view, oldBuy = h.descendants(h.cardList()[0], 'BLMarketBuy')[0].events.onactivate;
    assert(h.pendingTimers().length > 0, 'The old list has a pending incremental observer');
    h.load('commerce_remaining_5d5c1152eb.js');
    assert.equal(h.pendingTimers().length, 0, 'Reload disposal cancels the old observer');
    const replacement = h.cfg.SurvivalCommerceView, nextOwner = {};
    assert.notEqual(replacement, retired);
    assert.equal(replacement.OpenReadonly(h.snapshot, nextOwner), true);
    assert.equal(retired.IsReadonlyOpen(h.owner), false);
    assert.equal(retired.CloseReadonly(h.owner), false);
    assert.equal(retired.OpenReadonly(h.snapshot, h.owner), false);
    oldBuy();
    assert.equal(replacement.IsReadonlyOpen(nextOwner), true);
    replacement.Dispose();
    assert.equal(h.pendingTimers().length, 0);
    assert.equal(replacement.IsReadonlyOpen(nextOwner), false);
    noFinancialWork(h);
});
