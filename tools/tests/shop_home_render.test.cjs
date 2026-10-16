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
const candidates = path.resolve(option('--candidates', path.join(dataRoot, 'tmp/home_catalog_20261016/ui_candidates')));
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
const expectedIds = reviewed.map(item => item.project_sku || 'home_unavailable_' + item.source_id);
assert.equal(reviewed.filter(item => item.project_sku).length, 15);

// Deliberately all-authorized server state, so all 129 actual identities are
// visible. This fixture tests presentation and authorization boundaries, not live
// account ownership, pricing or the currently paused currencies.
const products = formal.map(item => ({sku: item.sku, source_id: item.source_id, title: item.title,
    description: item.description, category_id: item.category_id, product_type: item.product_type,
    icon: item.icon, sort_order: item.sort_order, reward_lines: clone(item.grants && item.grants.lines || []),
    original_price: item.original_price, required_vip_level: item.required_vip_level,
    enabled: true, owned: 0, purchase_limit: 1, purchase_method: 'wallet', currency: 'shop_points',
    currency_name: '商城积分', price: typeof item.price === 'number' ? item.price : 10}));
const originalProducts = JSON.stringify(products);
const scriptRoot = path.join(dataRoot, 'panorama/src/scripts/custom_game');
const candidateNames = new Set(['black_lion_market_model.js', 'black_lion_market.js', 'commerce_remaining_5d5c1152eb.js']);
function sourceFor(relative) {
    if (candidateNames.has(relative)) return path.join(candidates, relative);
    if (relative === 'common/commerce_components.js') {
        const candidate = path.join(candidates, 'commerce_components.js');
        return fs.existsSync(candidate) ? candidate : path.join(root, 'panorama/src/scripts/custom_game', relative);
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
function allPages(h) {
    const result = [], sizes = []; let iterations = 0;
    while (true) {
        assert(++iterations < 20, 'Pagination terminates');
        result.push(...displayIds(h)); sizes.push(cards(h).length);
        const next = h.descendants(h.store().actions, 'CJPageAction')[1];
        if (!next || !next.enabled) break;
        next.events.onactivate();
    }
    return {ids: result, sizes};
}
const baselineCfg = {SurvivalShopPresentation: clone(presentation)};
vm.runInNewContext(read(path.join(scriptRoot, 'black_lion_market_model.js')), {GameUI: {CustomUIConfig: () => baselineCfg}});
const baselineModel = baselineCfg.SurvivalBlackLionMarketModel;
function expectedGroup(id, items = products) {
    return Array.from(baselineModel.SortProducts(items.filter(item => baselineModel.InGroup(item, id)), id), item => item.sku);
}

const h = makeHarness();
h.walletSnapshot(products);
select(h, 'home');
assert.deepEqual(displayIds(h), expectedIds, 'The rendered home follows the reviewed video: left to right, top to bottom');
assert.equal(h.cfg.SurvivalCommerceView.Inspect().catalogProductCount, 129, 'Preview rows never enter the authenticated catalog');
assert.equal(h.cfg.SurvivalCommerceView.Inspect().groups.find(group => group.id === 'home').count, 20);
const previewCards = cards(h).filter(card => card.__observedProduct.home_unavailable);
assert.equal(previewCards.length, 5);
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
for (const group of ['all', 'bundles', 'promotions', 'vip']) {
    select(h, group); const actual = allPages(h);
    assert.deepEqual(actual.ids, expectedGroup(group), group + ' keeps its original membership, order and paging');
    assert(actual.ids.every(id => products.some(product => product.sku === id)), group + ' contains formal SKUs only');
    if (group === 'all') { assert.equal(actual.ids.length, 129); assert.deepEqual(actual.sizes, [40, 40, 40, 9]); }
}

// A missing independent configuration must stay empty, never fall back to All.
const missing = makeHarness({missingHome: true}); missing.walletSnapshot(products); select(missing, 'home');
assert.deepEqual(displayIds(missing), []);
assert.equal(missing.cfg.SurvivalCommerceView.Inspect().groups.find(group => group.id === 'home').count, 0);
select(missing, 'all'); assert.equal(allPages(missing).ids.length, 129);
missing.cfg.SurvivalShopHomeCatalog = {List: () => products.map(item => item.sku)};
select(missing, 'home'); assert.deepEqual(displayIds(missing), [], 'An incomplete old List-only config also fails closed');

// Real inventory and delisting rules still apply to the fifteen formal cards.
const actualHome = reviewed.filter(item => item.project_sku).map(item => item.project_sku);
const ownedSku = actualHome[0], delistedSku = actualHome[1];
const restricted = products.map(item => item.sku === ownedSku ? {...item, owned: 1, disabled_reason: 'already_owned'}
    : item.sku === delistedSku ? {...item, enabled: false, disabled_reason: 'product_unavailable'} : item);
h.walletSnapshot(restricted); select(h, 'home');
assert.deepEqual(displayIds(h), expectedIds.filter(id => id !== ownedSku && id !== delistedSku));
assert.equal(cards(h).filter(card => card.__observedProduct.home_unavailable).length, 5);
select(h, 'all'); assert.deepEqual(allPages(h).ids, expectedGroup('all', restricted));

// Paging to a real product can only open its existing checkout. An order still
// requires the explicit confirmation button and must carry that exact SKU.
const buyer = makeHarness();
buyer.walletSnapshot(products, {u_coin: 0, shop_points: Math.max(...products.map(item => item.price)) + 1, shop_gold: 0});
select(buyer, 'home');
const homeTarget = cards(buyer).find(card => !card.__observedProduct.home_unavailable);
buyer.descendants(homeTarget, 'BLMarketBuy')[0].events.onactivate();
assert.equal(purchaseRequests(buyer).length, 0, 'A real homepage product opens confirmation without ordering');
let homeConfirmation = buyer.menus().find(menu => menu.panel.BHasClass('MenuV10Exchange'));
assert(homeConfirmation && homeConfirmation.IsOpen()); homeConfirmation.Close();
select(buyer, 'all');
// Reopening the market legitimately refreshes ownership; finish that real
// catalog request before exercising the confirmation's purchase action.
buyer.walletSnapshot(products, {u_coin: 0, shop_points: Math.max(...products.map(item => item.price)) + 1, shop_gold: 0});
buyer.descendants(buyer.store().actions, 'CJPageAction')[1].events.onactivate();
const target = cards(buyer)[0], sku = target.__observedProduct.sku;
assert(products.some(item => item.sku === sku));
buyer.descendants(target, 'BLMarketBuy')[0].events.onactivate();
assert.equal(purchaseRequests(buyer).length, 0);
const confirmation = buyer.menus().find(menu => menu.panel.BHasClass('MenuV10Exchange'));
assert(confirmation && confirmation.IsOpen());
buyer.descendants(confirmation.actions, 'CommerceConfirmBuy')[0].events.onactivate();
assert.equal(purchaseRequests(buyer).length, 1);
assert.equal(purchaseRequests(buyer)[0].payload.sku, sku);
assert.equal(buyer.paidCheckouts.length, 0);
assert.equal(JSON.stringify(products), originalProducts);
const report = {status: 'PASS', reviewedOrder: expectedIds, homeCount: 20, unavailableCount: 5,
    formalCatalogCount: 129, allPageSizes: [40, 40, 40, 9], existingRulesPreserved: true,
    legacyHomeOverwriteIgnored: true, missingConfigDoesNotShowAll: true, checkoutSku: sku, loaded};
const output = option('--output', null);
if (output) { fs.mkdirSync(path.dirname(path.resolve(output)), {recursive: true}); fs.writeFileSync(output, JSON.stringify(report, null, 2) + '\n'); }
console.log('SHOP_HOME_RENDER_PASS ' + JSON.stringify({home: 20, preview: 5, all: 129, pages: report.allPageSizes, checkoutSku: sku}));
