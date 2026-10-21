'use strict';

// Exercise production icon resolution, both commerce renderers and the actual
// payment controller. --data-root permits a sparse checkout to read real catalogs
// and unchanged assets without replacing them with synthetic products.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const {spawnSync} = require('node:child_process');
const root = path.resolve(__dirname, '../..');
const args = process.argv.slice(2);
function option(name, fallback) { const i = args.indexOf(name); return i < 0 ? fallback : args[i + 1]; }
const dataRoot = path.resolve(option('--data-root', root));
const requireCompiled = args.includes('--require-compiled');
const read = file => fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '');
const json = file => JSON.parse(read(file));
const sha = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
function source(relative) {
    const local = path.join(root, relative);
    return fs.existsSync(local) ? local : path.join(dataRoot, relative);
}
const loaded = {};
function harness(options = {}) {
    const ids = {}, requests = [], handlers = new Map(), timers = new Map(); let serial = 0;
    class Panel {
        constructor(type, parent, id = '') {
            this.type = this.paneltype = type; this.id = id; this.parent = null;
            this.children = []; this.classes = new Set(); this.events = {}; this.style = {}; this.attrs = {};
            this.visible = this.enabled = this.hittest = this.hittestchildren = true; this.text = '';
            this.actualuiscale_x = this.actualuiscale_y = 1; this.images = [];
            this.SetParent(parent); if (id) ids[id] = this;
        }
        IsValid() { return !this.deleted; }
        AddClass(c) { c.split(/\s+/).forEach(v => this.classes.add(v)); }
        RemoveClass(c) { this.classes.delete(c); }
        BHasClass(c) { return this.classes.has(c); }
        SetHasClass(c, on) { on ? this.AddClass(c) : this.RemoveClass(c); }
        SetPanelEvent(n, fn) { this.events[n] = fn; }
        SetParent(p) { if (this.parent) this.parent.children = this.parent.children.filter(c => c !== this); this.parent = p; if (p) p.children.push(this); }
        GetParent() { return this.parent; }
        Children() { return this.children; }
        GetChildCount() { return this.children.length; }
        GetChild(i) { return this.children[i]; }
        FindChildTraverse(id) { return this.id === id ? this : this.children.map(c => c.FindChildTraverse(id)).find(Boolean); }
        SetImage(uri) { this.image = uri; this.images.push(uri); }
        SetScaling() {} SetFocus() {} SetAcceptsFocus() {}
        SetAttributeString(k, v) { this.attrs[k] = v; }
        GetAttributeString(k, fallback) { return this.attrs[k] === undefined ? fallback : this.attrs[k]; }
        GetPositionWithinWindow() { return {x: 0, y: 0}; }
        RemoveAndDeleteChildren() { this.children.slice().forEach(c => c.DeleteAsync()); }
        DeleteAsync() { this.RemoveAndDeleteChildren(); this.deleted = true; this.SetParent(null); }
    }
    const panel = new Panel('Panel', null, 'CommerceIconTest');
    panel.actuallayoutwidth = 1920; panel.actuallayoutheight = 1080;
    function $(id) { return ids[String(id).replace(/^#/, '')] || null; }
    $.CreatePanel = (type, parent, id) => new Panel(type, parent, id);
    $.GetContextPanel = () => panel;
    $.Schedule = (delay, fn) => { timers.set(++serial, {delay, fn}); return serial; };
    $.CancelScheduled = id => timers.delete(id);
    $.Msg = $.DispatchEvent = $.RegisterEventHandler = $.RegisterForUnhandledEvent = () => {};
    const cfg = {SurvivalDevelopmentPayments:true};
    const env = vm.createContext({$, GameUI: {CustomUIConfig: () => cfg}, Game: {GetLocalPlayerID: () => 0, GetGameTime: () => 0},
        GameEvents: {Subscribe(name, fn) { const list = handlers.get(name) || []; list.push(fn); handlers.set(name, list); return fn; },
            Unsubscribe(fn) { for (const [key, list] of handlers) handlers.set(key, list.filter(v => v !== fn)); },
            SendCustomGameEventToServer(name, payload) { requests.push({name, ...payload}); }},
        CustomNetTables: {GetTableValue: () => null, SubscribeNetTableListener: () => ++serial, UnsubscribeNetTableListener() {}}});
    function load(name) {
        const relative = 'panorama/src/scripts/custom_game/' + name, file = source(relative);
        loaded[relative] = {file, sha256: sha(file)};
        vm.runInContext(read(file), env, {filename: file});
    }
    if (!options.independentPayment) ['common/item_resources.js', 'common/vip_badges.js', 'reward_presentation.js', 'common/ui_registry.js', 'common/ui_components.js', 'common/tooltip_dismiss.js', 'ui_layers.js',
        'archive_v10_data.js', 'shop_v10_assets.js', 'common/menu_v10.js', 'item_art_remaining_5d5c1152eb.js',
        'common/commerce_components.js', 'black_lion_market_model.js', 'black_lion_market.js'].forEach(load);
    function payment() {
        const xml = read(source('panorama/src/layout/custom_game/payment_test.xml')), stack = [panel];
        for (const tag of xml.matchAll(/<(\/?)(Panel|Button|Label|Image|TextEntry)\b([^>]*)>/g)) {
            if (tag[1]) { stack.pop(); continue; }
            const attrs = Object.fromEntries([...tag[3].matchAll(/([\w-]+)="([^"]*)"/g)].map(m => [m[1], m[2]]));
            const node = new Panel(tag[2], stack.at(-1), attrs.id);
            if (attrs.class) node.AddClass(attrs.class);
            if (attrs.text) node.text = attrs.text;
            for (const key of ['visible', 'enabled', 'hittest', 'hittestchildren']) if (attrs[key]) node[key] = attrs[key] !== 'false';
            if (attrs.onactivate) node.events.onactivate = () => vm.runInContext(attrs.onactivate, env);
            if (!/\/\s*$/.test(tag[3])) stack.push(node);
        }
        if (options.independentPayment) {
            assert.equal(cfg.SurvivalCommerceComponents, undefined, 'No component was injected before independent payment startup');
            assert.equal(cfg.SurvivalItemArt, undefined, 'No ItemArt was injected before independent payment startup');
            const includes = [...xml.matchAll(/<include\s+src="file:\/\/\{resources\}\/scripts\/custom_game\/([^"]+)"\s*\/>/g)].map(m => m[1]);
            assert(includes.length > 0, 'Read the actual payment XML script dependencies');
            includes.forEach(load);
            assert.equal(cfg.SurvivalItemArt, undefined, 'Independent payment works without the separate lottery ItemArt module');
        } else load('payment_test.js');
    }
    function respond(value) {
        const request = requests.at(-1); assert(request);
        for (const fn of handlers.get('survival_payment_result') || []) fn({request_id: request.request_id, action: request.action, ...value});
    }
    return {cfg, panel, ids, requests, payment, respond, env};
}
const descendants = panel => [panel, ...panel.Children().flatMap(descendants)];
const classNode = (panel, cls) => descendants(panel).find(p => p.BHasClass(cls));
// Historical art receipts remain useful for pixel/quantity regressions. Runtime
// artwork selection and all expected URIs come only from the shared registry.
const receiptsManifest = json(path.join(root, 'data/ui/commerce_product_art_v1.json'));
const resourcesManifest = json(path.join(root, 'data/ui/item_resources.json'));
assert.equal(resourcesManifest.schema_version, 1);
const bundleHash = json(path.join(dataRoot, 'server/bundles/current.json')).hash;
const bundleFile = path.join(dataRoot, 'server/bundles', bundleHash, 'bundle.json');
assert.equal(sha(bundleFile), bundleHash, 'Use the actual published bundle');
const bundle = json(bundleFile);
const wallet = bundle.configs.commerce_catalog.rows;
const paymentFile = path.join(dataRoot, 'design_refs/shop_functional_20261016/release_v2/payment_catalog.json');
const cash = json(paymentFile).products;
const unique = new Map([...wallet, ...cash].map(row => [row.sku, row]));
// The release file is the database import shape. These are the existing wire
// field names, preserving the imported amounts and grant quantities verbatim.
const paymentProducts = cash.map(item => ({...item, amount_fen: item.amount_fen === undefined ? item.amount : item.amount_fen,
    reward_lines: item.reward_lines || item.grants && item.grants.lines || []}));
assert.equal(wallet.length, 129, 'The complete reviewed commerce catalog is exercised');
assert.equal(unique.size, 137, 'The eight additional payment SKUs are included');
const originalData = JSON.stringify({wallet, cash});
const h = harness(), J = h.cfg.SurvivalCommerceComponents;
const resources = h.cfg.SurvivalItemResources;
const mappings = new Map([...unique.values()].map(item => {
    const row = resources.Lookup(item);
    assert(row, item.sku + ' exists in the shared resource table');
    const receipt = receiptsManifest.products.find(entry => entry.sku === item.sku) || {};
    return [item.sku, {...receipt, sku: item.sku, item_id: row.id, runtime_uri: row.uri, kind: row.kind, vip_level: row.vip_level}];
}));
const manifest = {products: [...mappings.values()]};
assert.deepEqual([...mappings.keys()].sort(), [...unique.keys()].sort(), 'No product is silently omitted from the shared art table');
assert.equal(typeof J.NormalizeIconURI, 'function');
function assertRenderedIcon(icon, row, message) {
    if (row.kind === 'vip') {
        assert(icon.__survivalVIPBadge, message + ' includes the composed VIP badge');
        assert.equal(icon.__survivalVIPBadge.image.image, row.runtime_uri, message + ' uses the table artwork');
        assert.equal(icon.__survivalVIPBadge.number.text, String(row.vip_level), message + ' displays its VIP number');
    } else assert.deepEqual(icon.images, [row.runtime_uri], message);
}
function assertPaymentIcon(state, item, message) {
    const row = mappings.get(item.sku), art = state.ids.PaymentProductArt;
    if (row.kind === 'vip') {
        assert.equal(art.image, '', message + ' clears the incomplete base glyph');
        assertRenderedIcon(art.__paymentResourceIcon, row, message);
    } else assert.equal(art.image, row.runtime_uri, message);
}
const rendered = [];
for (const item of unique.values()) {
    const expected = J.NormalizeIconURI(mappings.get(item.sku).runtime_uri);
    assert(expected, item.sku + ' has a safe explicit mapping');
    assert.equal(J.NormalizeIconURI(J.ProductIcon(item)), expected, item.sku + ' resolves formal source data');
    const rewards = item.reward_lines || item.grants && item.grants.lines || [];
    const props = {index: 0, catalog: {categories: []}, rewards, action() { throw new Error('Rendering must not order'); }};
    const row = h.cfg.SurvivalBlackLionMarket.Row(h.panel, item, props);
    // The shipped renderer uses the registered original art for every product,
    // including bundles. A captured gift layer must never replace that identity.
    const image = classNode(row, 'BLMarketItemIcon');
    assert(image, item.sku + ' market retains its real product icon');
    assertRenderedIcon(image, mappings.get(item.sku), item.sku + ' market loads exactly the selected icon');
    assert.equal(classNode(row, 'BLMarketGiftIcon'), undefined, item.sku + ' is not replaced by screenshot gift art');
    const card = J[item.product_type === 'bundle' ? 'Bundle' : 'Product'](h.panel, item, {rewards});
    assertRenderedIcon(classNode(card, 'RCProductArt'), mappings.get(item.sku), item.sku + ' shared card uses the same art');
    if (item.product_type === 'bundle') {
        const effect = classNode(card.__purpleDetail, 'RCProductEffect').text;
        for (const reward of rewards) assert(effect.includes(J.RewardNameText(reward.label || reward.id)), item.sku + ' retains every normalized bundle reward label');
    }
    rendered.push({sku: item.sku, uri: expected, classification: mappings.get(item.sku).classification});
    if (card.__purpleDispose) card.__purpleDispose(); card.DeleteAsync();
    if (row.__purpleDispose) row.__purpleDispose(); row.DeleteAsync();
}
const summer = {video_p042: 'lottery_muramasa', video_p043: 'lottery_kings_treasure', video_p045: 'lottery_raven_eye',
    video_p046: 'lottery_magic_book', video_p048: 'lottery_spear_of_longinus', video_p049: 'lottery_withered_branch_lantern', video_p050: 'lottery_echo_compass'};
for (const [sku, id] of Object.entries(summer)) {
    const expected = 's2r://panorama/images/custom_game/reward_art_v5/' + id + '.vtex';
    assert.equal(J.NormalizeIconURI(J.ProductIcon(unique.get(sku))), expected, sku + ' uses its named existing lottery art');
    assert.equal(h.cfg.SurvivalItemArt.Lookup({item_id: id}).runtime_uri, expected, 'Lottery keeps the same exact resource');
}
assert.equal(new Set(Object.keys(summer).map(sku => J.ProductIcon(unique.get(sku)))).size, 7);
assert.match(J.ProductIcon(unique.get('video_p125')), /lottery_attribute_crystal\.(vtex|png)$/, 'The real crystal remains a crystal');
const dedicatedNames = ['spirit_katana', 'titan_shield', 'master_foreman', 'lament_seed', 'swift_winch'];
const dedicatedRows = manifest.products.filter(row => /\/commerce_art_v1\//.test(row.runtime_uri));
assert.deepEqual(dedicatedRows.map(row => path.posix.basename(row.runtime_uri, '.vtex')).sort(), dedicatedNames.slice().sort());
const custom = 'custom_game/reward_art_v5/lottery_muramasa.png';
assert.equal(J.NormalizeIconURI(J.ProductIcon({sku: 'future_unknown_product', icon: custom})), 'file://{images}/' + custom);
assert.equal(J.NormalizeIconURI(J.ProductIcon({sku: 'video_p043', icon: custom})), resources.Resolve('video_p043'), 'A registered item cannot be redirected by a stale or dedicated server icon');
for (const bad of ['https://example.invalid/x.png', 'custom_game/../items/x.png', 'custom_game//x.png', 'custom_game/%2e%2e/x.png',
    'custom_game\\x.png', 'file://{images}/custom_game/./x.png', 's2r://panorama/images/custom_game/../x.vtex',
    's2r://panorama/images/custom_game//x.vtex', 's2r://panorama/images/custom_game/x.vtex?x=1',
    'custom_game/example.png\n', 'file://{images}/items/blink.png\r\n', 's2r://panorama/images/custom_game/example.vtex\n']) {
    assert.equal(J.NormalizeIconURI(bad), '', 'Reject unsafe URI: ' + bad);
}
for (const value of ['items/blink.png', 'spellicons/juggernaut_blade_fury.png', 'file://{images}/custom_game/reward_art_v5/lottery_muramasa.png',
    's2r://panorama/images/custom_game/reward_art_v5/lottery_muramasa.vtex']) assert(J.NormalizeIconURI(value), value);

// Pixel sources already used by lottery must remain byte-for-byte consistent
// with their reviewed art receipts, not merely retain a plausible filename.
const rewardArt = json(source('data/ui/reward_art_v5.json'));
const summerArt = json(source('data/ui/summer_item_art_v1.json'));
const receipts = new Map([...Object.values(rewardArt), ...summerArt].map(row => [row.id, row]));
let unchangedLotteryArt = 0;
for (const row of manifest.products) {
    const receipt = receipts.get(row.item_id);
    if (!receipt || !row.runtime_uri.includes('/reward_art_v5/')) continue;
    const png = source('panorama/src/images/' + receipt.icon_path);
    assert.equal(sha(png), receipt.sha256, row.item_id + ' retains the reviewed lottery pixels');
    unchangedLotteryArt++;
}
assert(unchangedLotteryArt >= 7);

h.payment();
h.cfg.SurvivalPayments.Checkout(paymentProducts[0].sku);
h.respond({ok: true, products: paymentProducts, categories: [], wechat: 1, alipay: 1});
let checkoutCount = 0;
for (const item of paymentProducts) {
    if (!(item.amount_fen > 0 && item.amount_fen <= 1000000 && item.amount_fen % 1 === 0)) continue;
    h.cfg.SurvivalPayments.Checkout(item.sku);
    assertPaymentIcon(h, item, item.sku + ' checkout matches market');
    const quantity = classNode(h.ids.PaymentDialog, 'PaymentQuantityValue');
    if (quantity) assert.equal(quantity.text, '1', 'Changing the visual source preserves checkout quantity');
    checkoutCount++;
}
assert(checkoutCount >= 8);
assert.equal(h.requests.filter(r => r.action === 'create').length, 0, 'Viewing every icon cannot place an order');
assert.equal(JSON.stringify({wallet, cash}), originalData, 'Art selection never mutates prices, rewards, quantity caps or authoritative catalogs');
const cold = harness({independentPayment: true});
cold.payment();
assert.equal(typeof cold.cfg.SurvivalCommerceComponents.NormalizeIconURI, 'function', 'Actual XML establishes the cold-start dependency');
cold.cfg.SurvivalPayments.Checkout(paymentProducts[0].sku);
cold.respond({ok: true, products: paymentProducts, categories: [], wechat: 1, alipay: 1});
for (const item of paymentProducts) {
    if (!(item.amount_fen > 0 && item.amount_fen <= 1000000 && item.amount_fen % 1 === 0)) continue;
    cold.cfg.SurvivalPayments.Checkout(item.sku);
    assertPaymentIcon(cold, item, item.sku + ' XML-only cold checkout matches market');
}
assert.equal(cold.requests.filter(r => r.action === 'create').length, 0);
const quantityRows = manifest.products.filter(row => row.classification === 'quantity_same_item');
for (const row of quantityRows) {
    const sameItem = manifest.products.filter(other => other.item_id === row.item_id);
    assert(sameItem.length > 1, row.sku + ' is a true quantity variant');
    assert(sameItem.every(other => other.runtime_uri === row.runtime_uri), row.sku + ' retains the same item art across quantities');
}

const dedicatedHashes = [];
for (const row of dedicatedRows) {
    const relative = row.runtime_uri.replace(/^s2r:\/\//, '');
    const png = source('panorama/src/' + relative.slice('panorama/'.length).replace(/\.vtex$/, '.png'));
    const bytes = fs.readFileSync(png);
    assert.equal(bytes.subarray(0, 8).toString('hex'), '89504e470d0a1a0a');
    assert(bytes.readUInt32BE(16) >= 128 && bytes.readUInt32BE(20) >= 128, 'Dedicated artwork is a real image');
    dedicatedHashes.push(sha(png));
    if (requireCompiled) assert(fs.existsSync(source(relative + '_c')), row.sku + ' has its compiled runtime texture');
}
assert.equal(new Set(dedicatedHashes).size, 5, 'Five missing themes have five distinct source artworks');
let compiledTextures = 0;
if (requireCompiled) {
    const {textureInfo} = require(source('tools/test_construction_grid_resources.cjs'));
    const dedicatedUris = new Set(dedicatedRows.map(row => row.runtime_uri)), payloadHashes = new Set();
    for (const uri of new Set(manifest.products.map(row => row.runtime_uri).filter(uri => uri.startsWith('s2r://')))) {
        const file = source(uri.slice('s2r://'.length) + '_c');
        const info = textureInfo(fs.readFileSync(file));
        assert(info.width > 0 && info.height > 0 && info.payload.length > 0, uri + ' contains actual texture DATA and pixels');
        if (dedicatedUris.has(uri)) {
            assert.deepEqual([info.width, info.height, info.depth, info.format, info.flags & 8, info.mipLevels, info.payload.length],
                [128, 128, 1, 28, 8, 8, 87380], uri + ' ships complete BGRA8888 NO_LOD mip data');
            payloadHashes.add(crypto.createHash('sha256').update(info.payload).digest('hex'));
        }
        compiledTextures++;
    }
    assert.equal(payloadHashes.size, 5, 'Five compiled textures contain distinct GPU pixels');
}

const offline = path.join(root, 'tools/archive_goods_20261016/resolve_icons.cjs');
if (fs.existsSync(offline)) {
    const result = spawnSync(process.execPath, [offline, bundleFile, paymentFile, root], {encoding: 'utf8'});
    assert.equal(result.status, 0, result.stderr);
    const icons = JSON.parse(result.stdout).icons;
    for (const item of unique.values()) assert.equal(J.NormalizeIconURI(icons[item.sku]), J.NormalizeIconURI(J.ProductIcon(item)), item.sku + ' offline/live consistency');
}
const report = {status: 'PASS',commerceProducts: wallet.length,uniqueProducts: unique.size,checkoutProducts: checkoutCount,
    independentCheckoutProducts: checkoutCount,distinctSummerIcons: 7,dedicatedIcons: dedicatedRows.length,
    unchangedLotteryArt,requireCompiled,compiledTextures,loaded,rendered};
const output = option('--output', null);
if (output) { fs.mkdirSync(path.dirname(path.resolve(output)), {recursive: true}); fs.writeFileSync(output, JSON.stringify(report, null, 2) + '\n'); }
console.log('COMMERCE_PRODUCT_ICONS_PASS ' + JSON.stringify({products: unique.size, checkoutProducts: checkoutCount, unchangedLotteryArt, requireCompiled}));
