'use strict';
// Read-only factory check against the real backend catalog compiler export.
// Does not compile assets, talk to the game, or create purchases/account writes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {harness} = require('../shop_catalog_20261016/harness.cjs');
const repo = path.resolve(__dirname, '../..');
const file = process.argv[2] || 'output/shop_icon_quality_20261017/catalogs.json';
const catalogs = JSON.parse(fs.readFileSync(path.resolve(repo, file), 'utf8').replace(/^\uFEFF/, ''));
const h = harness({paid: {products: [], categories: []}});
['common/item_resources.js', 'common/vip_badges.js', 'reward_presentation.js'].forEach(h.load);
const cfg = h.cfg;
const descendants = panel => [panel, ...panel.Children().flatMap(descendants)];
const byClass = (panel, name) => descendants(panel).find(node => node.BHasClass(name));
const px = value => Number(String(value).replace(/px$/, ''));
const position = panel => String(panel.style.position || '0px 0px 0px').split(/\s+/).map(px);
const checked = [], unlisted = [];
for (const [channel, catalog] of Object.entries(catalogs)) {
    for (const raw of catalog.products) {
        const grants = raw.grants || {}, pricing = grants.pricing || {};
        const item = {...raw, owned: 0, amount_fen: raw.amount_fen ?? raw.amount,
            purchase_method: channel === 'payment' ? 'cash' : raw.purchase_method,
            u_coin_price: raw.u_coin_price ?? pricing.u_coin_price,
            u_coin_per_yuan: raw.u_coin_per_yuan ?? pricing.u_coin_per_yuan,
            required_vip_level: Number(grants.required_vip_level) || 0,
            reward_lines: grants.lines || raw.reward_lines || []};
        const resource = cfg.SurvivalItemResources.Lookup(item);
        assert(resource, channel + ':' + item.sku + ' resolves registered identity');
        assert.equal(cfg.SurvivalCommerceComponents.ProductIcon(item), resource.uri,
            channel + ':' + item.sku + ' resolves canonical art');
        if (!cfg.SurvivalBlackLionMarketModel.IsListed(item)) {
            unlisted.push({channel, sku: item.sku});
            continue;
        }
        const row = cfg.SurvivalBlackLionMarket.Row(h.root, item,
            {index: checked.length, rewards: item.reward_lines, catalog, action() { throw Error('No purchase'); }});
        const art = descendants(row).find(panel => panel.__itemResourceId === resource.id);
        assert(art, channel + ':' + item.sku + ' renders shared resource factory art');
        assert(px(art.style.width) >= 64 && px(art.style.height) >= 64,
            channel + ':' + item.sku + ' has at least 64px square art');
        if (resource.kind === 'image') {
            assert.equal(art.image, resource.uri, channel + ':' + item.sku + ' uses the registered image');
            assert.equal(art.scaling, 'stretch-to-cover-preserve-aspect',
                channel + ':' + item.sku + ' fills the icon without stretching');
        }
        assert(!descendants(row).some(panel => panel.image && /shop_v10_v1\/vip\d+_gift\.png$/.test(panel.image)),
            channel + ':' + item.sku + ' never uses captured low-resolution bundle art');
        const well = byClass(row, 'BLMarketArt'), name = byClass(row, 'BLMarketName');
        const [wellX, wellY] = position(well), [nameX] = position(name);
        assert(wellX + px(well.style.width) + 12 <= nameX, item.sku + ' leaves a text gap');
        assert(wellY >= 0 && wellY + px(well.style.height) <= px(row.style.height),
            item.sku + ' icon fits the actual row template');
        checked.push({channel, sku: item.sku, resourceId: resource.id, kind: resource.kind,
            width: px(art.style.width), height: px(art.style.height), rowHeight: px(row.style.height)});
        row.DeleteAsync(0);
    }
}
assert(checked.length > 0, 'Formal listed products were actually checked');
const sources = ['black_lion_market.js', 'common/commerce_components.js', 'reward_presentation.js', 'common/item_resources.js'];
const hashes = sources.map(relative => ({path: 'panorama/src/scripts/custom_game/' + relative,
    sha256: crypto.createHash('sha256').update(fs.readFileSync(path.join(repo, 'panorama/src/scripts/custom_game', relative))).digest('hex')}));
console.log(JSON.stringify({status: 'PASS', kind: 'production_factory_readonly_catalog_check',
    checked: checked.length, uniqueSkus: new Set(checked.map(row => row.sku)).size,
    bundles: checked.filter(row => /bundle/.test(row.sku)).length,
    channels: Object.fromEntries(Object.keys(catalogs).map(channel => [channel, checked.filter(row => row.channel === channel).length])),
    skippedUnlisted: unlisted.length, sourceHashes: hashes, rows: checked}, null, 2));
