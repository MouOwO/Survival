'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const {createRequire} = require('node:module');
const {harness, walletItem} = require('../shop_catalog_20261016/harness.cjs');
const root = path.resolve(__dirname, '../..');
const policy = 'fixed_quality_shop_points_20261021';
const points = (sku, price, extra = {}) => ({...walletItem(0), sku, title: sku, price, ...extra});
function fixture(items) {
    const skus = items.map(item => item.sku);
    const h = harness({presentation: {groups: {home: skus, promotions: skus, all: skus}}, paid: {products: [], categories: []}});
    h.cfg.SurvivalCommerceView.Open();
    h.walletSnapshot(items, {shop_points: 100000, u_coin: 120, shop_gold: 0});
    h.cfg.SurvivalCommerceView.SelectCategory('all');
    return h;
}
function card(h, sku) { return h.cardList().find(row => row.__menuCell && row.__menuCell.namePanel.text === sku); }
const label = (h, row, cls) => h.descendants(row, cls)[0];
const purchases = h => h.requests.filter(row => row.payload.action === 'purchase');
function confirmation(h, sku) {
    label(h, card(h, sku), 'BLMarketBuy').events.onactivate();
    const menu = h.menus().find(row => row.panel.BHasClass('MenuV10Exchange'));
    assert(menu && menu.IsOpen());
    return {menu, buy: label(h, menu.actions, 'CommerceConfirmBuy'), copy: label(h, menu.content, 'CommerceConfirmCopy'), status: label(h, menu.content, 'CommerceConfirmStatus')};
}

test('Fixed-quality points prices display authoritative amounts without historical or inferred discounts', () => {
    const grades = [['n', 200], ['r', 600], ['sr', 1500], ['ssr', 3000], ['ur', 8000]];
    const items = grades.map(([quality, price]) => points('quality_' + quality, price, {quality, price_policy: policy, original_price: 99999}));
    items.push(points('lottery_ember_of_legacy', 8000, {quality: 'ur', price_policy: policy, original_price: 29}));
    items.push(points('best_fishing_rod', 3000, {quality: 'ssr', price_policy: policy}));
    const original = JSON.stringify(items), h = fixture(items), model = h.cfg.SurvivalBlackLionMarketModel;
    for (const item of items) {
        const row = card(h, item.sku); assert(row);
        assert.equal(label(h, row, 'BLMarketPriceMain').text, item.price + ' 积分');
        assert.equal(h.descendants(row, 'BLMarketPriceReference').length, 0);
        assert.equal(model.ReferencePrice(item), null);
    }
    const ordinary = points('not_in_promotion', 200, {price_policy: policy, original_price: 1000});
    assert.equal(model.InGroup(ordinary, 'promotions'), false, 'An old reference field cannot advertise a fixed item as discounted');
    assert.notEqual(model.GroupFor(ordinary), 'promotions');
    assert.equal(JSON.stringify(items), original, 'No catalog field or charged price is rewritten');
});

test('Unpublished quality prices never replace an older server quote, and policy-only updates repaint references', () => {
    const old = points('legacy_ember', 29, {quality: 'ur'}), h = fixture([old]);
    assert.equal(label(h, card(h, old.sku), 'BLMarketPriceMain').text, '29 积分');
    assert.equal(label(h, card(h, old.sku), 'BLMarketPriceReference').text, '43.5 积分');
    const before = card(h, old.sku);
    h.walletSnapshot([{...old, price_policy: policy}]);
    const after = card(h, old.sku);
    assert.notEqual(after, before, 'A new server policy is part of the display revision');
    assert.equal(label(h, after, 'BLMarketPriceMain').text, '29 积分', 'The client never manufactures an 8000-point charge');
    assert.equal(h.descendants(after, 'BLMarketPriceReference').length, 0);
    h.walletSnapshot([{...old, price: 8000, price_policy: policy}]);
    assert.equal(label(h, card(h, old.sku), 'BLMarketPriceMain').text, '8000 积分');
    assert.equal(purchases(h).length, 0, 'Catalog reads never buy anything');
});

test('A terminal old-price rejection refreshes 94 to 200 and requires a new explicit confirmation', () => {
    const old = points('changed_equipment', 94), h = fixture([old]);
    const view = confirmation(h, old.sku);
    assert.match(view.copy.text, /售价：94 商城积分/);
    view.buy.events.onactivate(); const first = purchases(h).at(-1);
    h.emit('survival_commerce_result', {action: 'purchase', request_id: first.payload.request_id, ok: 0, terminal: 1, error: 'commerce_price_changed'});
    assert.equal(h.cfg.SurvivalCommercePending, null);
    assert.equal(h.requests.at(-1).payload.action, 'catalog', 'Only the catalog is requested after a changed quote');
    assert.equal(view.buy.enabled, false);
    assert.match(view.status.text, /商品价格已更新，请重新确认/);
    view.buy.events.onactivate(); assert.equal(purchases(h).length, 1, 'A stale native callback cannot buy the old quote');
    h.walletSnapshot([{...old, price: 200, price_policy: policy}], {shop_points: 1000, u_coin: 120, shop_gold: 0});
    assert.match(view.copy.text, /售价：200 商城积分/);
    assert.match(view.copy.text, /商城余额：1000 商城积分/);
    assert.equal(label(h, card(h, old.sku), 'BLMarketPriceMain').text, '200 积分');
    assert.equal(view.buy.enabled, true); assert.match(view.status.text, /请重新确认/);
    assert.equal(purchases(h).length, 1, 'Refreshing and reopening never retry the purchase');
    view.buy.events.onactivate(); const second = purchases(h).at(-1);
    assert.equal(purchases(h).length, 2); assert.notEqual(second.payload.request_id, first.payload.request_id);
    assert.equal(second.payload.sku, old.sku);
    for (const field of ['price', 'quality', 'price_policy', 'original_price', 'amount_fen']) assert(!Object.hasOwn(second.payload, field));
    h.emit('survival_commerce_result', {action: 'purchase', request_id: second.payload.request_id, ok: 1, terminal: 1, currency: 'shop_points', balance: 800});
    assert.equal(h.cfg.SurvivalCommerceWallet.GetCatalog().balances.shop_points, 800, 'Only the server receipt changes the displayed balance');
});

test('Changed-price goods missing from the refreshed catalog stay blocked without an automatic retry', () => {
    const item = points('removed_equipment', 94), h = fixture([item]), view = confirmation(h, item.sku);
    view.buy.events.onactivate(); const request = purchases(h).at(-1);
    h.emit('survival_commerce_result', {action: 'purchase', request_id: request.payload.request_id, ok: 0, terminal: true, error: 'commerce_price_changed'});
    h.walletSnapshot([]);
    assert.equal(view.buy.enabled, false); view.buy.events.onactivate();
    assert.equal(purchases(h).length, 1);
});

test('Nonterminal purchase failures retain the original idempotency token', () => {
    const item = points('uncertain_equipment', 200, {price_policy: policy}), h = fixture([item]), view = confirmation(h, item.sku);
    view.buy.events.onactivate(); const first = purchases(h).at(-1);
    h.emit('survival_commerce_result', {action: 'purchase', request_id: first.payload.request_id, ok: 0, terminal: 0, error: 'backend_unavailable'});
    assert.equal(h.cfg.SurvivalCommercePending.id, first.payload.request_id);
    view.buy.events.onactivate(); assert.equal(purchases(h).at(-1).payload.request_id, first.payload.request_id);
});

test('P147 and P151 share the confirmed UR display grade while their artwork and aliases remain intact', () => {
    const cfg = {};
    vm.runInNewContext(fs.readFileSync(path.join(root, 'panorama/src/scripts/custom_game/common/item_resources.js'), 'utf8'), {GameUI: {CustomUIConfig: () => cfg}});
    const registry = cfg.SurvivalItemResources;
    for (const id of ['commerce_p147', 'commerce_p151']) {
        const row = registry.Lookup(id); assert(row); assert.equal(row.quality, 'ur');
        assert.equal(registry.Grade({resource_id: id, product_type: 'single'}), 'UR');
        for (const alias of row.aliases) assert.equal(registry.Lookup(alias), row);
    }
    assert.equal(registry.Lookup('P147').uri, 's2r://panorama/images/custom_game/commerce_art_v1/lament_seed.vtex');
    assert.equal(registry.Lookup('P151').uri, 's2r://panorama/images/custom_game/commerce_art_v1/spirit_katana.vtex');
    const h = fixture([]); h.load('common/item_resources.js');
    h.walletSnapshot(['video_p147', 'video_p151'].map(sku => points(sku, 8000, {price_policy: policy})));
    const gradeLabels = h.descendants(h.root, 'RCPurpleDetailQuality');
    assert.equal(gradeLabels.length, 2);
    assert(gradeLabels.every(panel => panel.visible && panel.text === '品级：UR'), 'Both real commerce tooltips show the shared UR grade');
});

test('Starjoy stays cumulative with no exchange sender and uses the public disabled reason', () => {
    const loader = fs.readFileSync(path.join(root, 'tools/test_lottery_updates.cjs'), 'utf8').split('suite+=')[0];
    const checks = `
config.SurvivalPurpleLottery={Version:'lottery_current_20261018',Owns(owner){return owner===root;},IsAlive(){return true;},IsReady(){return true;},Open(){},Close(){},Apply(){},Fit(){return true;}};
ui.Open();events.ui_lottery_snapshot(snapshot());
events.ui_lottery_exchange_result({ok:0,error:'starjoy_exchange_disabled'});
assert(nodes.LotteryStatus.text.includes('星悦积分仅累计，不能兑换'));
assert(!requests.some(row=>row.n==='ui_lottery_exchange_request'));
`;
    vm.runInNewContext(loader + 'suite+=' + JSON.stringify(checks) + ';vm.runInNewContext(suite,{require:require("node:module").createRequire(require("path").resolve("tools/test_lottery_ui.js")),console});', {require: createRequire(__filename), console});
    for (const file of ['archive_v10.js', 'archive_180de7e38b_titles_compact_v6.js']) {
        const text = fs.readFileSync(path.join(root, 'panorama/src/scripts/custom_game', file), 'utf8');
        assert(text.includes('累计星悦积分')); assert(text.includes('仅累计，不可兑换'));
        assert(!text.includes('可用余额')); assert(!text.includes('兑换不降级'));
    }
});
