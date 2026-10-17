const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const {harness, walletItem} = require('../shop_catalog_20261016/harness.cjs');

const root = path.resolve(__dirname, '../..');
function walk(panel) { return [panel, ...panel.Children().flatMap(walk)]; }
function strings(value) {
    if (typeof value === 'string') return [value];
    if (!value || typeof value !== 'object') return [];
    return Object.values(value).flatMap(strings);
}
function images(panel) {
    return walk(panel).flatMap(p => [p.image, p.style.backgroundImage].filter(v => typeof v === 'string'));
}
function labels(panel) { return walk(panel).filter(p => p.paneltype === 'Label'); }
function tab(h, id) { h.store().panel.FindChildTraverse('BLMarketSection_' + id).events.onactivate(); }
function noCheckout(h) {
    assert.deepEqual(h.paidCheckouts, []);
    assert.equal(h.requests.filter(r => ['purchase', 'create'].includes(r.payload.action)).length, 0);
}
function fixture() {
    const paid = {catalog_hash:'v10-live-1', categories:[{id:'item',label:'道具'}], products:[
        {sku:'v10_cash',title:'动态现金商品',category_id:'item',product_type:'single',enabled:1,
            amount_fen:345,u_coin_price:3450,u_coin_per_yuan:1000,currency:'u_coin',
            icon:'items/rapier.png',reward_lines:[]},
        {sku:'v10_vip',title:'动态 VIP 礼包',category_id:'vip',product_type:'bundle',enabled:0,
            amount_fen:678,required_vip_level:4,disabled_reason:'vip_level_insufficient',
            disabled_message:'需要 VIP 4 才可购买',icon:'items/rapier.png',reward_lines:[]}]};
    const points = {...walletItem('v10'),title:'动态积分商品',price:37,owned:2};
    const h = harness({paid,presentation:{groups:{home:['v10_cash']}}});
    h.cfg.SurvivalCommerceView.Open();
    h.walletSnapshot([points], {u_coin:123,shop_points:4567,shop_gold:89});
    return {h,points,paid};
}

test('V10 uses 48 explicit texture resources backed by component PNGs and excludes flattened text images', () => {
    const {h} = fixture();
    assert(h.cfg.SurvivalShopV10, 'The actual asset module is loaded before constructing the window');
    const paths = [...new Set(strings(h.cfg.SurvivalShopV10).filter(value => /\.vtex$/i.test(value)))];
    assert.equal(paths.length, 48, 'The runtime manifest contains exactly the approved component textures');
    assert(!strings(h.cfg.SurvivalShopV10).some(value => /\.png$/i.test(value)),
        'Runtime paths use explicit textures rather than auto-generated PNG resources');
    const layers = Object.values(h.cfg.SurvivalShopV10.layers);
    assert.equal(layers.filter(layer => layer.kind === 'raster_text').length, 47);
    assert(layers.filter(layer => layer.kind === 'raster_text').every(layer => !layer.path),
        'Raster text remains geometry/reference metadata without a renderable path');
    assert(!layers.some(layer => layer.kind === 'game_context'));
    for (const asset of paths) {
        assert(!/game_context|reference|(?:^|\/)(?:text|labels?)[_.\/-]/i.test(asset),
            'Reference screenshots and rasterized text are excluded: ' + asset);
        assert.match(asset, /^s2r:\/\/panorama\/images\/custom_game\/shop_v10_v1\/[a-z0-9_]+_v10\.vtex$/,
            'Each component uses the separate V10 resource namespace');
        const relative = asset.replace(/^s2r:\/\/panorama\/images\//, '').replace(/_v10\.vtex$/, '.png');
        const filename = path.resolve(root, 'panorama/src/images', relative);
        assert(filename.startsWith(path.join(root, 'panorama/src/images') + path.sep));
        const bytes = fs.readFileSync(filename);
        assert.equal(bytes.subarray(0, 8).toString('hex'), '89504e470d0a1a0a', 'A material is a real PNG: ' + asset);
        assert(bytes.readUInt32BE(16) > 0 && bytes.readUInt32BE(20) > 0);
    }
    noCheckout(h);
});

test('The live V10 window composes explicit texture materials around separate dynamic labels and controls', () => {
    const {h} = fixture(), market = h.store();
    assert.equal(market.panel.style.width, '1380px');
    assert.equal(market.panel.style.height, '946px');
    assert.equal(market.layout, 'black_lion_list', 'The existing controller layout contract remains stable');
    assert.equal(market.skinVersion, 10, 'The assembled window identifies its V10 skin');
    assert.equal(market.listWidth, 1357);
    const assetPaths = strings(h.cfg.SurvivalShopV10).filter(value => /\.vtex$/i.test(value));
    const materialImages = images(market.panel).filter(uri => assetPaths.includes(uri));
    assert(materialImages.length >= 12, 'The actual tree uses component materials, not one composite screenshot');
    for (const cls of ['BLMarketTexture','BLMarketHeaderTexture','BLMarketFooterTexture','BLMarketFrameTexture'])
        assert(h.descendants(market.panel, cls).some(p => p.paneltype === 'Image' && p.image), 'A separate material forms ' + cls);
    const tabs = market.panel.FindChildTraverse('BlackLionMarketTabs');
    assert.deepEqual(tabs.Children().map(p => p.id),
        ['home','bundles','promotions','vip','all'].map(id => 'BLMarketSection_' + id));
    for (const button of tabs.Children()) {
        assert(images(button).some(uri => materialImages.includes(uri)), 'Each tab uses a V10 material');
        assert(labels(button).some(p => p.BHasClass('RCTabText')), 'Tab names remain labels');
        assert.equal(typeof button.events.onactivate, 'function');
    }
    tab(h, 'all');
    const row = h.cardList().find(p => p.BHasClass('RCProduct'));
    assert(row && row.__menuCell.namePanel.paneltype === 'Label');
    assert.equal(row.style.width, '1357px');
    assert(h.descendants(row, 'BLMarketRowWash').length);
    assert(h.descendants(row, 'BLMarketArt').length);
    assert(images(row).some(uri => assetPaths.some(asset => uri.endsWith(asset))), 'A live product row uses V10 materials');
    const button = h.descendants(row, 'BLMarketBuy')[0];
    assert(button && button.BHasClass('ButtonPrimary') && button.BHasClass('Large'), 'The action uses the native Dota2 primary button');
    assert.equal(images(button).length, 0, 'The old V10 image cannot cover the native button background');
    assert(h.descendants(button, 'BLMarketBuyText').every(p => p.paneltype === 'Label'));
    assert(!images(market.panel).some(uri => /game_context|reference|(?:^|\/)(?:text|labels?)[_.\/-]/i.test(uri)));
    noCheckout(h);
});

test('Catalog changes update V10 names, prices, balances, ownership, VIP state and selected tabs as text', () => {
    const {h,points,paid} = fixture(), view = h.cfg.SurvivalCommerceView;
    tab(h, 'all');
    assert(labels(h.store().panel).some(p => p.text === '动态积分商品'));
    assert(labels(h.store().panel).some(p => p.text === '37 积分'));
    assert(labels(h.store().panel).some(p => p.text === '已拥有 2'));
    for (const number of ['123','4567']) assert(labels(h.store().panel).some(p => p.text.includes(number)));
    const fresh = {...points,title:'服务端更新后的名称',price:73,owned:3};
    h.walletSnapshot([fresh], {u_coin:321,shop_points:7654,shop_gold:98});
    const nextPaid = {...paid,catalog_hash:'v10-live-2',products:paid.products.map(p => p.sku==='v10_cash'
        ? {...p,title:'服务端现金新名称',amount_fen:901,u_coin_price:9010} : p)};
    h.updatePaid(nextPaid);
    const updated = labels(h.store().panel);
    for (const text of ['服务端更新后的名称','73 积分','已拥有 3','服务端现金新名称','9010 U币'])
        assert(updated.some(p => p.text === text), 'A real Label refreshes to ' + text);
    for (const number of ['321','7654']) assert(updated.some(p => p.text.includes(number)));
    assert(!updated.some(p => p.text === '动态积分商品' || p.text === '37 积分'));
    tab(h, 'vip');
    const vip = h.cardList().find(p => p.BHasClass('RCProduct'));
    assert(vip);
    assert.equal(h.descendants(vip, 'BLMarketBuy')[0].enabled, false);
    assert(labels(vip).some(p => p.text === '需要 VIP 4 才可购买'));
    const tabs = h.store().panel.FindChildTraverse('BlackLionMarketTabs').Children();
    assert.deepEqual(tabs.filter(p => p.BHasClass('UISelected')).map(p => p.id), ['BLMarketSection_vip']);
    assert.equal(view.Inspect().category, 'vip');
    noCheckout(h);
});
