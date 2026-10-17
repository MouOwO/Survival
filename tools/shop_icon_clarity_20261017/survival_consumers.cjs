'use strict';
// Exercise complete production shop controllers with all enabled formal rows.
// This uses the existing Panorama test host; no game, account or orders connect.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../..');
process.chdir(root);
const {csv} = require('../shop_ui_12h/catalog.cjs');
const {open} = require('../vpk_inspect.cjs');
const harnessPath = path.join(root, 'tools/tests/shop_incremental_refresh.test.cjs');
let host = fs.readFileSync(harnessPath, 'utf8');
host = host.slice(0, host.indexOf('\nfunction item(overrides = {})'));
// The incremental test host intentionally excludes artwork. Add the actual
// artwork modules used by survival_hud.xml before its complete controllers.
const artwork = ['common/item_resources.js', 'reward_presentation.js',
    'native_ui_icons.js', 'item_art_remaining_5d5c1152eb.js'];
host = host.replace('const scripts = [', 'const scripts = [' + artwork.map(JSON.stringify).join(',') + ',');
host += '\nmodule.exports = {harness};';
const moduleHost = {exports: {}};
vm.runInNewContext(host, {require, module: moduleHost, __dirname: path.dirname(harnessPath), console},
    {filename: harnessPath});
const h = moduleHost.exports.harness();
const rows = csv('data/csv/商店系统/shop_entries.csv').filter(row => row.enabled === '1');
assert(rows.length > 0);
const expected = new Set(rows.map(row => row.shop_entry_id));
const entries = rows.map((row, i) => ({entry_id: row.shop_entry_id, content_id: row.content_id,
    shop_id: row.category_id, category_id: row.category_id, name: row.display_name,
    content_type: row.category_id === 'weapon' ? 'weapon' : row.category_id === 'challenge' ? 'challenge'
        : row.category_id === 'rebirth' ? 'rebirth' : 'item',
    sort_order: i, visible: 1, purchasable: 1, gold_cost: Number(row.gold_cost), wood_cost: Number(row.wood_cost),
    // A stale borrowed icon must not override the formal identity.
    icon: 'item_branches', icon_type: 'item', description: row.notes,
    stock: Number(row.stock_max), stock_max: Number(row.stock_max),
    purchase_limit: Number(row.purchase_limit), owned_count: 0}));
const native = open(path.resolve(root, '../../dota/pak01_dir.vpk'));
const nativeKeys = new Set(native.entries.map(row => row.path));
const consumed = new Set(), coverage = [];
function descendants(panel, name) {
    return panel.children.flatMap(child => (child.BHasClass(name) ? [child] : []).concat(descendants(child, name)));
}
function verifyCurrent(tab) {
    for (const card of h.cards()) {
        const entryId = card.GetAttributeString('entry_id', '');
        const entry = entries.find(row => row.entry_id === entryId);
        assert(entry, 'Card must originate in the enabled formal table: ' + entryId);
        const resource = h.cfg.SurvivalItemResources.Lookup(entry);
        assert(resource && resource.kind === 'image', 'Registered image required: ' + entryId);
        const icons = descendants(card, 'ShopItemIcon');
        assert.equal(icons.length, 1, 'One actual product image per card: ' + entryId);
        const icon = icons[0];
        assert.equal(icon.image, resource.uri, 'Formal identity must win over the stale icon: ' + entryId);
        assert.equal(icon.scaling, 'stretch-to-cover-preserve-aspect');
        assert.equal(icon.hittest, false); assert.equal(icon.hittestchildren, false);
        card.events.onmouseover();
        const tooltipIcons = descendants(h.nodes.get('ShopTooltipIconHost'), 'ShopTooltipMainIcon');
        assert.equal(tooltipIcons.length, 1);
        assert.equal(tooltipIcons[0].image, resource.uri, 'Tooltip and card share artwork: ' + entryId);
        assert.equal(tooltipIcons[0].scaling, 'stretch-to-cover-preserve-aspect');
        const file = resource.uri.match(/^file:\/\/\{images\}\/([^?]+)\.png$/);
        if (file) assert(nativeKeys.has('panorama/images/' + file[1] + '_png.vtex_c')
            || fs.existsSync(path.join(root, 'panorama/images/' + file[1] + '_png.vtex_c')),
            'Shipped native or compiled addon resource must exist: ' + resource.uri);
        else {
            const local = resource.uri.match(/^s2r:\/\/(.+)\.vtex$/);
            assert(local && fs.existsSync(path.join(root, local[1] + '.vtex_c')),
                'Registered local runtime resource must exist: ' + resource.uri);
        }
        consumed.add(entryId);
        coverage.push({tab, entry_id: entryId, content_id: entry.content_id, uri: resource.uri,
            card_size: [Number.parseFloat(card.style.width), Number.parseFloat(card.style.height)],
            tooltip_size: [92, 92], fill: icon.scaling});
    }
}
h.cfg.SurvivalShop.Open();
h.full({ui_mode: 'shop', entries: entries.filter(row => !['challenge','rebirth'].includes(row.content_type))});
verifyCurrent('equipment');
h.cfg.SurvivalShop.SelectOther(); verifyCurrent('other');
h.cfg.SurvivalShop.OpenChallenge();
h.full({ui_mode: 'challenge', entries: entries.filter(row => ['challenge','rebirth'].includes(row.content_type))});
verifyCurrent('challenge');
assert.deepEqual([...consumed].sort(), [...expected].sort(), 'Every enabled product must render in its actual tab');
const css = fs.readFileSync('panorama/src/styles/custom_game/shop.css', 'utf8');
assert(css.includes('.ShopItemFrame { position:0px 0px 0px;width:100%;height:100%;'), 'Frame fills the card');
assert(css.includes('.ShopItemIcon { position:0px 0px 0px;width:100%;height:100%;'), 'Artwork fills the frame');
assert(coverage.every(row => row.card_size[0] >= 64 && row.card_size[1] >= 64),
    'Existing survival product cards already exceed the requested marketplace target size');
const report = {status:'pass', scope:'Complete production shop and tooltip controllers, formal enabled CSV rows',
    mode:'Offline Panorama test host; no live-game image judgement', products:consumed.size,
    resolution_judgement:'Source resolution and enlargement quality are audited separately; URI coverage alone does not prove visual sharpness.',
    source_hashes:Object.fromEntries(['panorama/src/scripts/custom_game/shop_remaining_5d5c1152eb.js',
        'panorama/src/scripts/custom_game/shop_tooltip_remaining_5d5c1152eb.js','panorama/src/styles/custom_game/shop.css',
        'data/ui/item_resources.json'].map(file => [file,crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')])),
    coverage};
const output = 'design_refs/shop_icon_clarity_20261017/survival_consumers.json';
fs.mkdirSync(path.dirname(output), {recursive:true});
fs.writeFileSync(output, JSON.stringify(report,null,2)+'\n');
console.log('SURVIVAL_SHOP_ICON_CONSUMERS_PASS '+consumed.size+' products, same formal artwork in cards and tooltips; '+output);
