'use strict';

// Render the actual marketplace/controller with the reviewed homepage candidate.
// VM file mapping keeps pre-existing untracked UI files and the main workspace intact.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '../..'), args = process.argv.slice(2);
function option(name, fallback) { const at = args.indexOf(name); return at < 0 ? fallback : args[at + 1]; }
const dataRoot = path.resolve(option('--data-root', root));
const candidates = path.resolve(option('--candidates', path.join(dataRoot, 'panorama/src/scripts/custom_game')));
const read = file => fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '');
const json = file => JSON.parse(read(file));
const clone = value => JSON.parse(JSON.stringify(value));
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const loaded = {};
const reviewed = json(path.join(root, 'data/ui/shop_home_video_review_20261016.json')).home.items;
const presentation = json(path.join(dataRoot, 'data/ui/shop_catalog_presentation_20261016.json'));
const bundleHash = json(path.join(dataRoot, 'server/bundles/current.json')).hash;
const bundleFile = path.join(dataRoot, 'server/bundles', bundleHash, 'bundle.json');
assert.equal(hash(bundleFile), bundleHash, 'The formal SKU inventory comes from the published bundle');
const formal = json(bundleFile).configs.commerce_catalog.rows;
assert.equal(formal.length, 129);
assert.equal(reviewed.length, 20);
const expectedIds = reviewed.filter(item => item.project_sku).map(item => item.project_sku);
assert.equal(reviewed.filter(item => item.project_sku).length, 15);

// Deliberately all-authorized server state, so all 129 actual identities are
// available in their respective tabs. This fixture tests presentation, not live
// account ownership, pricing or the currently paused currencies.
const products = formal.map(item => ({sku: item.sku, source_id: item.source_id, title: item.title,
    description: item.description, category_id: item.category_id, product_type: item.product_type,
    icon: item.icon, sort_order: item.sort_order, reward_lines: clone(item.grants && item.grants.lines || []),
    original_price: item.original_price,
    required_vip_level: item.required_vip_level === undefined ? item.grants && item.grants.required_vip_level : item.required_vip_level,
    enabled: true, owned: 0, purchase_limit: 1, purchase_method: 'wallet', currency: 'shop_points',
    currency_name: '商城积分', price: typeof item.price === 'number' ? item.price : 10}));
const originalProducts = JSON.stringify(products);
const scriptRoot = path.join(dataRoot, 'panorama/src/scripts/custom_game');
const candidateNames = new Set(['black_lion_market_model.js', 'black_lion_market.js', 'commerce_remaining_5d5c1152eb.js']);
function sourceFor(relative) {
    if (candidateNames.has(relative)) return path.join(candidates, relative);
    if (relative === 'common/commerce_components.js') {
        const candidate = path.join(candidates, 'commerce_components.js');
        return fs.existsSync(candidate) ? candidate : path.join(scriptRoot, relative);
    }
    return path.join(scriptRoot, relative);
}
function makeHarness(options = {}) {
    const harnessFile = path.join(dataRoot, 'tools/shop_catalog_20261016/harness.cjs');
    const fsProxy = Object.create(fs);
    fsProxy.readFileSync = function(file, encoding) {
        const absolute = path.resolve(String(file));
        if (absolute.startsWith(scriptRoot + path.sep)) {
            const relative = path.relative(scriptRoot, absolute).split(path.sep).join('/');
            const chosen = sourceFor(relative);
            loaded[relative] = {file: chosen, sha256: hash(chosen)};
            let contents = read(chosen);
            if (options.missingHome && relative === 'common/commerce_components.js')
                contents += '\ndelete GameUI.CustomUIConfig().SurvivalShopHomeCatalog;\n';
            return encoding ? contents : Buffer.from(contents);
        }
        return fs.readFileSync(file, encoding);
    };
    const module = {exports: {}};
    vm.runInNewContext(read(harnessFile), {module, exports: module.exports, __dirname: path.dirname(harnessFile),
        require(name) { return name === 'node:fs' || name === 'fs' ? fsProxy : require(name); }}, {filename: harnessFile});
    const h = module.exports.harness({homeCatalogFixture: false, presentation: clone(presentation), paid: {catalog_hash: 'NO_CASH_FIXTURE', products: [], categories: []}});
    const actualRow = h.cfg.SurvivalBlackLionMarket.Row;
    h.cfg.SurvivalBlackLionMarket.Row = function(parent, item, props) {
        const panel = actualRow(parent, item, props); panel.__observedProduct = item; return panel;
    };
    return h;
}
function select(h, id) {
    h.cfg.SurvivalCommerceView.Open();
    const tab = h.store().panel.FindChildTraverse('BLMarketSection_' + id);
    assert(tab, 'The real market contains the ' + id + ' tab'); tab.events.onactivate();
}
const identity = item => item.sku || item.home_display_id;
const cards = h => Array.from(h.cardList()).filter(panel => panel.__observedProduct);
const displayIds = h => cards(h).map(panel => identity(panel.__observedProduct));
const purchaseRequests = h => h.requests.filter(row => row.payload.action === 'purchase');
const allDescendants = panel => [panel, ...panel.Children().flatMap(allDescendants)];
function allRows(h) {
    assert.equal(h.descendants(h.store().actions, 'CJPageAction').length, 0, 'Every market category is a single scrolling list');
    assert.equal(h.descendants(h.store().actions, 'CJPageLabel').length, 0);
    h.loadAllBatches();
    return {ids: displayIds(h), count: cards(h).length};
}
// Expectations come from the reviewed identities and presentation order, never
// from the previous model whose broad All/discount aliases admitted packages.
const singleSkus = new Set(formal.filter(item => item.product_type === 'single').map(item => item.sku));
const ordinaryBundles = Array.from({length: 5}, (_, i) => 'video_bundle_b' + String(i + 1).padStart(3, '0'));
const vipBundles = Array.from({length: 10}, (_, i) => 'video_bundle_vip_' + String(i + 1).padStart(2, '0'));
assert.equal(singleSkus.size, 114);
assert.deepEqual(formal.filter(item => item.product_type === 'bundle').map(item => item.sku).sort(), [...ordinaryBundles, ...vipBundles].sort());
assert(vipBundles.every(sku => products.find(item => item.sku === sku).required_vip_level > 0),
    'Project the actual VIP level from the published grant into its server wire field');
const expectedGroups = {
    all: presentation.groups.all.filter(sku => singleSkus.has(sku)),
    bundles: ordinaryBundles,
    vip: vipBundles,
    promotions: presentation.groups.promotions.filter(sku => singleSkus.has(sku))
};
assert.equal(expectedGroups.all.length, 114); assert.equal(expectedGroups.promotions.length, 25);
function expectedGroup(id, excluded = []) { return expectedGroups[id].filter(sku => !excluded.includes(sku)); }
function assertExclusiveGroups(h, message) {
    for (const group of ['all', 'bundles', 'promotions', 'vip']) {
        select(h, group); const actual = allRows(h);
        assert.deepEqual(actual.ids, expectedGroups[group], message + ': ' + group + ' has exactly its reviewed membership and order');
        assert.equal(h.cfg.SurvivalCommerceView.Inspect().groups.find(entry => entry.id === group).count, expectedGroups[group].length,
            message + ': ' + group + ' count matches its own rows');
        assert.equal(actual.count, expectedGroups[group].length, 'Every category can load through its final batch');
    }
    assert.equal(h.cfg.SurvivalCommerceView.Inspect().catalogProductCount, 129, 'Tab separation never changes the formal catalog');
}

const h = makeHarness();
h.walletSnapshot(products);
select(h, 'home');
assert.deepEqual(displayIds(h), expectedIds, 'The rendered home follows the reviewed video: left to right, top to bottom');
assert.equal(h.cfg.SurvivalCommerceView.Inspect().catalogProductCount, 129, 'Preview rows never enter the authenticated catalog');
assert.equal(h.cfg.SurvivalCommerceView.Inspect().groups.find(group => group.id === 'home').count, 15);
const previewCards = cards(h).filter(card => card.__observedProduct.home_unavailable);
assert.equal(previewCards.length, 0, 'Every unopened video placeholder is absent from the live storefront');
for (const card of previewCards) {
    const item = card.__observedProduct;
    assert.equal(card.__menuCell.namePanel.text, reviewed.find(entry => entry.source_id === item.source_id).name,
        'The unavailable item keeps its reviewed video name');
    for (const key of ['sku', 'price', 'amount_fen', 'u_coin_price', 'currency', 'purchase_method', 'reward_lines', 'grants'])
        assert(!Object.hasOwn(item, key), item.source_id + ' unavailable preview has no ' + key);
    assert.equal(item.enabled, false);
    assert.equal(h.descendants(card, 'BLMarketBuy').length, 0, 'Unavailable previews have no buy control');
    assert.equal(h.descendants(card, 'BLMarketRowPrice').length, 0, 'Unavailable previews have no price control');
    assert(allDescendants(card).some(panel => panel.text === '未开放'), 'Unavailable status is visible');
    assert(allDescendants(card).every(panel => panel.paneltype !== 'Button'), 'Unavailable previews cannot expose a hidden purchase button');
    for (const panel of allDescendants(card)) for (const event of ['onactivate', 'onmouseover', 'onmouseout'])
        if (panel.events[event]) panel.events[event]();
}
assert.equal(purchaseRequests(h).length, 0); assert.equal(h.paidCheckouts.length, 0);
assert.equal(JSON.stringify(products), originalProducts, 'Home assembly does not mutate formal product data');

// The old importer may still overwrite its own home list with all products.
const polluted = clone(presentation); polluted.groups.home = products.map(item => item.sku).reverse();
h.cfg.SurvivalShopPresentation = polluted; h.cfg.SurvivalBlackLionMarketModel.SetPresentation(polluted);
select(h, 'all'); select(h, 'home');
assert.deepEqual(displayIds(h), expectedIds, 'Legacy home=all cannot expand or reorder the independent home');
assertExclusiveGroups(h, 'Formal catalog');

// Presentation imports can be stale or wrong. Aliases and discounts cannot
// override product_type or the server's VIP requirement/category.
const aliases = clone(presentation), aliasedSingle = expectedIds.find(id => singleSkus.has(id));
aliases.groups.home = [...ordinaryBundles, ...vipBundles, ...aliases.groups.home];
aliases.groups.promotions = [...ordinaryBundles, ...vipBundles, ...aliases.groups.promotions];
aliases.groups.all = [...ordinaryBundles, ...vipBundles, ...aliases.groups.all];
aliases.groups.vip = [aliasedSingle, ...ordinaryBundles, ...aliases.groups.vip];
aliases.groups.bundles = [aliasedSingle, ...vipBundles, ...aliases.groups.bundles];
const aliasProducts = products.map(item => {
    if (item.sku === aliasedSingle) return {...item, category_id: 'vip', required_vip_level: 9};
    if (item.sku === vipBundles[0]) return {...item, category_id: 'vip', required_vip_level: 0, original_price: item.price * 10};
    if (item.product_type === 'bundle') return {...item, original_price: item.price * 10};
    return item;
});
const aliasHarness = makeHarness(); aliasHarness.walletSnapshot(aliasProducts);
aliasHarness.cfg.SurvivalShopPresentation = aliases;
aliasHarness.cfg.SurvivalBlackLionMarketModel.SetPresentation(aliases);
select(aliasHarness, 'home'); assert.deepEqual(displayIds(aliasHarness), expectedIds, 'Alias packages cannot leak into Home');
assertExclusiveGroups(aliasHarness, 'Polluted aliases and discounted packages');
const vipSingleGroup = aliasHarness.cfg.SurvivalBlackLionMarketModel.GroupFor(aliasProducts.find(item => item.sku === aliasedSingle));
assert(!['vip', 'bundles'].includes(vipSingleGroup), 'A single item with a VIP restriction still routes to a singles tab');
assert.equal(purchaseRequests(aliasHarness).length, 0); assert.equal(aliasHarness.paidCheckouts.length, 0);

// The homepage manifest identifies a SKU, not permission to override a later
// server type change. A formerly single homepage item becoming a package moves
// into Packages and disappears from both Home and All.
const changedSku = expectedIds.find(id => singleSkus.has(id));
const changedProducts = products.map(item => item.sku === changedSku ? {...item, product_type: 'bundle'} : item);
const changed = makeHarness(); changed.walletSnapshot(changedProducts); select(changed, 'home');
assert.deepEqual(displayIds(changed), expectedIds.filter(id => id !== changedSku));
assert.equal(changed.cfg.SurvivalCommerceView.Inspect().groups.find(group => group.id === 'home').count, 14);
select(changed, 'all'); assert.deepEqual(allRows(changed).ids, expectedGroup('all', [changedSku]));
select(changed, 'bundles'); assert.deepEqual(allRows(changed).ids, [...ordinaryBundles, changedSku]);

// A missing independent configuration must stay empty, never fall back to All.
const missing = makeHarness({missingHome: true}); missing.walletSnapshot(products); select(missing, 'home');
assert.deepEqual(displayIds(missing), []);
assert.equal(missing.cfg.SurvivalCommerceView.Inspect().groups.find(group => group.id === 'home').count, 0);
select(missing, 'all'); assert.equal(allRows(missing).ids.length, 114);
missing.cfg.SurvivalShopHomeCatalog = {List: () => products.map(item => item.sku)};
select(missing, 'home'); assert.deepEqual(displayIds(missing), [], 'An incomplete old List-only config also fails closed');

// Real inventory and delisting rules still apply to the fifteen formal cards.
const actualHome = reviewed.filter(item => item.project_sku).map(item => item.project_sku);
const ownedSku = actualHome[0], delistedSku = actualHome[1];
const restricted = products.map(item => item.sku === ownedSku ? {...item, owned: 1, disabled_reason: 'already_owned'}
    : item.sku === delistedSku ? {...item, enabled: false, disabled_reason: 'product_unavailable'} : item);
h.walletSnapshot(restricted); select(h, 'home');
assert.deepEqual(displayIds(h), expectedIds.filter(id => id !== ownedSku && id !== delistedSku));
assert.equal(cards(h).filter(card => card.__observedProduct.home_unavailable).length, 0);
select(h, 'all'); assert.deepEqual(allRows(h).ids, expectedGroup('all', [ownedSku, delistedSku]));

// The last real product in the full list can only open its existing checkout. An order still
// uses the explicit storefront exchange button and must carry that exact SKU.
const buyer = makeHarness();
buyer.walletSnapshot(products, {u_coin: 0, shop_points: Math.max(...products.map(item => item.price)) + 1, shop_gold: 0});
select(buyer, 'home');
buyer.walletSnapshot(products, {u_coin: 0, shop_points: Math.max(...products.map(item => item.price)) + 1, shop_gold: 0});
const homeTarget = cards(buyer).find(card => !card.__observedProduct.home_unavailable);
buyer.descendants(homeTarget, 'BLMarketBuy')[0].events.onactivate();
assert.equal(purchaseRequests(buyer).length, 1, 'The explicit homepage exchange submits that product once');
const firstPurchase = purchaseRequests(buyer)[0];
assert.equal(firstPurchase.payload.sku, homeTarget.__observedProduct.sku);
assert(buyer.root.FindChildTraverse('CommerceResultDialog').visible);
assert.equal(buyer.descendants(buyer.root, 'CommerceConfirmBuy').length, 0);
buyer.emit('survival_commerce_result', {action: 'purchase', request_id: firstPurchase.payload.request_id,
    ok: 1, terminal: 1, currency: 'shop_points', balance: 99999});
buyer.cfg.SurvivalCommerceWallet.CloseResult();
select(buyer, 'all');
// Reopening the market legitimately refreshes ownership; finish that real
// catalog request before exercising the next explicit exchange action.
buyer.walletSnapshot(products, {u_coin: 0, shop_points: Math.max(...products.map(item => item.price)) + 1, shop_gold: 0});
assert.equal(allRows(buyer).count, 114);
const target = cards(buyer).at(-1), sku = target.__observedProduct.sku;
assert.equal(sku, expectedGroups.all.at(-1), 'The final formal SKU is available beyond the old page boundary');
assert(products.some(item => item.sku === sku));
buyer.descendants(target, 'BLMarketBuy')[0].events.onactivate();
assert.equal(purchaseRequests(buyer).length, 2);
assert(buyer.root.FindChildTraverse('CommerceResultDialog').visible);
assert.equal(purchaseRequests(buyer)[1].payload.sku, sku);
assert.notEqual(purchaseRequests(buyer)[1].payload.request_id, firstPurchase.payload.request_id);
for (const request of purchaseRequests(buyer))
    assert.deepEqual(Object.keys(request.payload).sort(), ['action', 'request_id', 'sku'], 'Only server-owned SKU identity and idempotency enter the exchange request');
assert.equal(buyer.paidCheckouts.length, 0);
assert.equal(JSON.stringify(products), originalProducts);
const report = {status: 'PASS', reviewedOrder: expectedIds, homeCount: 15, unavailableCount: 0,
    formalCatalogCount: 129, allSingleCount: 114, ordinaryBundleCount: 5, vipBundleCount: 10, promotionSingleCount: 25,
    allRenderedRows: 114, paginated: false, batchSize: 20, exclusiveGroups: true, staleAliasesCannotOverrideType: true, homepageTypeChangeFiltered: true,
    existingRulesPreserved: true,
    legacyHomeOverwriteIgnored: true, missingConfigDoesNotShowAll: true, checkoutSku: sku, loaded};
const output = option('--output', null);
if (output) { fs.mkdirSync(path.dirname(path.resolve(output)), {recursive: true}); fs.writeFileSync(output, JSON.stringify(report, null, 2) + '\n'); }
console.log('SHOP_HOME_RENDER_PASS ' + JSON.stringify({home: 15, preview: 0, allSingles: 114, bundles: 5, vip: 10, promotions: 25,
    allRenderedRows: report.allRenderedRows, batchSize: report.batchSize, paginated: report.paginated, checkoutSku: sku}));
