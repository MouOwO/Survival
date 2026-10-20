'use strict';

// Execute the production consumer functions against a small native-panel model.
// Private inventory/archive functions are read verbatim so the tests do not need
// a running Dota match, real inventory, checkout, or authenticated account.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const root = path.resolve(__dirname, '../..');
const script = file => fs.readFileSync(path.join(root, 'panorama/src/scripts/custom_game', file), 'utf8');
function productionPart(file, start, end) {
    const code = script(file), first = code.indexOf(start), last = code.indexOf(end, first + start.length);
    assert(first >= 0 && last > first, 'production function boundaries exist: ' + file);
    return code.slice(first, last);
}
class Panel {
    constructor(type = 'Panel', parent = null, id = '') {
        this.paneltype = type; this.id = id; this.children = []; this.style = {}; this.classes = new Set();
        this.visible = true; this.text = ''; this.SetParent(parent);
    }
    IsValid() { return !this.deleted; }
    GetParent() { return this.parent; }
    SetParent(parent) { if (this.parent) this.parent.children = this.parent.children.filter(child => child !== this); this.parent = parent; if (parent) parent.children.push(this); }
    Children() { return this.children; }
    AddClass(value) { String(value).split(/\s+/).forEach(cls => this.classes.add(cls)); }
    RemoveClass(value) { this.classes.delete(value); }
    SetHasClass(value, on) { on ? this.AddClass(value) : this.RemoveClass(value); }
    BHasClass(value) { return this.classes.has(value); }
    FindChildTraverse(id) { return this.id === id ? this : this.children.map(child => child.FindChildTraverse(id)).find(Boolean); }
    SetImage(uri) { this.uri = uri; }
    SetScaling(value) { this.scaling = value; }
    DeleteAsync() { this.deleted = true; this.SetParent(null); }
    SetPanelEvent() {}
}
function environment(extra = {}) {
    const cfg = {SurvivalUI: {}}, calls = [], ids = {};
    function $(id) { return ids[String(id).replace(/^#/, '')]; }
    $.CreatePanel = (type, parent, id) => new Panel(type, parent, id);
    const context = vm.createContext({$, GameUI: {CustomUIConfig: () => cfg}, ...extra});
    vm.runInContext(script('common/item_resources.js'), context);
    const resources = cfg.SurvivalItemResources;
    assert.equal(typeof resources.Grade, 'function', 'shared production grade resolver is loaded');
    cfg.SurvivalRewardPresentation = {
        CreateRegisteredIcon(parent, item, cls) {
            const row = cfg.SurvivalItemResources.Lookup(item); if (!row) return null;
            const icon = new Panel(row.kind === 'vip' ? 'Panel' : 'Image', parent);
            if (cls) icon.AddClass(cls); icon.uri = row.uri;
            return icon;
        },
        FillIcon(icon, item) {
            if (!icon) return;
            icon.testGrade = resources.Grade(item); calls.push({icon, item, grade: icon.testGrade}); return icon;
        }
    };
    return {cfg, calls, ids, context, resources, run: code => vm.runInContext(code, context)};
}
const noGradeID = 'commerce_p033';
const rewardID = 'lottery_heaven_reaching_tower_seal';

test('Commerce icon and detail use the same single reward grade without changing catalog objects', () => {
    const h = environment(); h.run(script('common/commerce_components.js'));
    const item = Object.freeze({sku: 'preview_without_resource', title: '样例', product_type: 'single'});
    const rewards = Object.freeze([Object.freeze({kind: 'item', id: rewardID, quantity: 1})]);
    const before = JSON.stringify({item, rewards});
    const icon = h.cfg.SurvivalCommerceComponents.ItemIcon(new Panel(), item, 'RCProductArt', {rewards});
    assert.equal(icon.testGrade, 'UR');
    assert.equal(h.calls.at(-1).item.sku, item.sku, 'product identity is retained beside projected rewards');
    assert.equal(JSON.stringify({item, rewards}), before, 'display projection does not mutate business objects');
    const bundle = Object.freeze({...item, product_type: 'bundle'});
    assert.equal(h.cfg.SurvivalCommerceComponents.ItemIcon(new Panel(), bundle, '', {rewards}).testGrade, '', 'member grade does not label a bundle');
    assert.equal(h.cfg.SurvivalCommerceComponents.ItemIcon(new Panel(), {...item, quality: 'r'}, '', {rewards}).testGrade, 'R', 'explicit product grade has priority');
    const {harness} = require('./helpers/commerce_tooltip_harness.cjs');
    const detail = harness(), entry = detail.bind(item, {rewards});
    assert.equal(detail.find(entry.tip, 'RCPurpleDetailQuality').text, '品级：UR');
    detail.dispose(entry);
});

test('Payment keeps explicit and projected grades across receipt display and unknown products', () => {
    const h = environment(); h.run(script('common/commerce_components.js'));
    const art = h.ids.PaymentProductArt = new Panel('Image');
    const block = productionPart('payment_test.js', '        var art=$("#PaymentProductArt"),artwork=', '        $("#PaymentPrice").text');
    h.context.cfg = h.cfg;
    h.run('function paymentArtwork(p,shown){' + block + '}');
    const product = Object.freeze({sku: 'video_p033', quality: 'ur', product_type: 'single', reward_lines: []});
    const receipt = Object.freeze({sku: 'video_p033'}), before = JSON.stringify({product, receipt});
    h.context.paymentArtwork(product, receipt);
    assert.equal(art.testGrade, 'UR', 'receipt without display fields inherits the current formal product grade');
    h.context.paymentArtwork({sku: 'video_p033', quality: 'n'}, {sku: 'video_p033', rarity: 'ur'});
    assert.equal(art.testGrade, 'UR', 'explicit receipt rarity is not overridden by fallback product quality');
    h.context.paymentArtwork({sku: 'video_p033'}, {sku: 'video_p033'});
    assert.equal(art.testGrade, '', 'reusing the same product art clears its old grade');
    h.context.paymentArtwork({sku: 'unregistered', product_type: 'single', reward_lines: [{kind: 'item', id: rewardID}]}, {sku: 'unregistered'});
    assert.equal(art.testGrade, 'UR', 'single reward identity survives the payment projection');
    assert.equal(JSON.stringify({product, receipt}), before);
    // The current catalog represents VIP medals as tier_badge, while this
    // payment branch also supports future composed VIP/hero resources.
    const vip = {id: 'grade_test_payment_vip', kind: 'vip', uri: 'file://{images}/items/recipe.png', vip_level: 1};
    const registry = h.cfg.SurvivalItemResources;
    h.cfg.SurvivalItemResources = {...registry,
        Lookup: item => item && item.sku === vip.id ? vip : registry.Lookup(item),
        Resolve: (item, fallback) => item && item.sku === vip.id ? vip.uri : registry.Resolve(item, fallback)};
    h.context.paymentArtwork({sku: vip.id, rarity: 'UR'}, {sku: vip.id});
    const first = art.__paymentResourceIcon; assert(first); assert.equal(first.testGrade, 'UR');
    h.context.paymentArtwork({sku: vip.id}, {sku: vip.id});
    assert.notEqual(art.__paymentResourceIcon, first, 'special composed icon grade changes invalidate its display cache');
    assert(first.deleted); assert.equal(art.__paymentResourceIcon.testGrade, '');
});

test('Inventory tooltip refreshes a reused icon using dynamic grade authority before static metadata', () => {
    const h = environment();
    h.run(productionPart('inventory_tooltip.js', '    function updateItemIcon(', '    function equipmentLevelText('));
    const icon = new Panel('DOTAItemImage');
    const metadata = Object.freeze({quality: 'SR'}), dynamic = Object.freeze({rarity: 'UR'});
    h.context.updateItemIcon(icon, noGradeID, 'item_branches', [dynamic, metadata]);
    const fitted = icon.FindChildTraverse('InventoryTooltipFittedIcon'); assert(fitted);
    assert.equal(fitted.testGrade, 'UR', 'a lower-priority static quality cannot override dynamic rarity');
    h.context.updateItemIcon(icon, noGradeID, 'item_branches', [{}]);
    assert.equal(fitted.testGrade, '', 'ungraded reuse clears a previously colored tooltip');
    h.context.updateItemIcon(icon, noGradeID, 'item_branches', [{quality: 'unknown'}]);
    assert.equal(fitted.testGrade, '', 'an unknown grade is not N');
    h.context.updateItemIcon(icon, noGradeID, 'item_branches', [{quality: 'n'}]);
    assert.equal(fitted.testGrade, 'N');
    assert.equal(icon.FindChildTraverse('InventoryTooltipFittedIcon'), fitted);
    assert.deepEqual(dynamic, {rarity: 'UR'}); assert.deepEqual(metadata, {quality: 'SR'});
});

test('Native inventory slot reapplies grade even when its item URI is unchanged', () => {
    const inv = new Panel(), slot = new Panel('Panel', inv, 'inventory_slot_0');
    new Panel('Panel', slot, 'ItemImage');
    let identity = {content_id: noGradeID, quality: 'UR'};
    const h = environment({
        native: () => inv, selectedUnit: () => 1, valid: node => node && node.IsValid(),
        style: (node, values) => Object.assign(node.style, values), findCached: (node, id) => node.FindChildTraverse(id),
        Entities: {GetItemInSlot: (unit, index) => index === 0 ? 100 : -1},
        Abilities: {GetAbilityName: () => 'item_branches'},
        CustomNetTables: {GetTableValue: () => identity}
    });
    h.context.cfg = h.cfg;
    h.cfg.SurvivalNativeIcons = {Resolve: id => h.resources.Lookup(id)};
    h.run(productionPart('topnav_remaining_5d5c1152eb.js', '    function refreshInventoryPresentation() {', '    function layoutMinimap('));
    h.context.refreshInventoryPresentation();
    const fitted = slot.FindChildTraverse('SurvivalInventoryFittedIcon'), firstURI = fitted.uri;
    assert.equal(fitted.testGrade, 'UR');
    identity = {content_id: noGradeID}; h.context.refreshInventoryPresentation();
    assert.equal(fitted.uri, firstURI); assert.equal(fitted.testGrade, '', 'same-art reuse restores ungraded state');
    identity = {content_id: noGradeID, rarity: 'r'}; h.context.refreshInventoryPresentation();
    assert.equal(fitted.testGrade, 'R');
    assert.equal(slot.FindChildTraverse('SurvivalInventoryFittedIcon'), fitted, 'grade update reuses the existing native child');
});

test('Archive cached commerce and ordinary rows refresh grade without rebuilding panels', () => {
    const h = environment({valid: node => node && node.IsValid(), pos() {}, style: (node, values) => Object.assign(node.style, values)});
    Object.assign(h.context, {cfg: h.cfg, current: 'commerce_goods', S: {State: () => true, Quantity: () => '1', Progress: () => ({text: '1/1', ratio: .5, known: true})}});
    h.run(productionPart('archive_v10.js', '    function findClass(', '    function render(data,'));
    for (const current of ['commerce_goods', 'shadow']) {
        h.context.current = current;
        const item = {id: noGradeID, name: '样例', quality: 'UR'}, resource = h.resources.Lookup(item);
        const card = new Panel(), host = new Panel('Panel', card), art = new Panel('Image', host);
        const key = current === 'commerce_goods'
            ? [current, item.id, item.icon, item.icon_type, item.icon_style, resource.id, resource.uri]
            : [current, item.id, item.icon, item.icon_type, item.icon_style, undefined, resource.id, resource.uri];
        card.__v10 = {host, art, artKey: JSON.stringify(key), name: new Panel(), count: new Panel(), countHost: new Panel(),
            track: new Panel(), fill: new Panel(), glint: new Panel(), state: new Panel()};
        h.context.decorate(card, item, 0); assert.equal(art.testGrade, 'UR');
        delete item.quality; h.context.decorate(card, item, 0); assert.equal(art.testGrade, '');
        item.rarity = 'SSR'; h.context.decorate(card, item, 0); assert.equal(art.testGrade, 'SSR');
        assert.equal(card.__v10.host, host); assert.equal(card.__v10.art, art);
    }
});

test('Archive points and goods remain borderless through the real shared icon repaint', () => {
    const h = environment({valid: node => node && node.IsValid()});
    // Use the complete production presentation path, including FillIcon's
    // repeated border/texture writes, rather than the grade-observer mock.
    h.run(script('reward_presentation.js'));
    // The native archive style helper caches its own writes. Loading it verbatim
    // also catches a border removal skipped after FillIcon changes inline style.
    h.run(productionPart('archive_v10.js', '    function style(', '    function specText('));
    Object.assign(h.context, {cfg: h.cfg, current: 'points',
        S: {State: item => item.count_known === 0 ? null : Number(item.count) > 0,
            Quantity: item => String(item.count)}});
    h.run(productionPart('archive_v10.js', '    function findClass(', '    function render(data,'));
    const item = Object.freeze({id: noGradeID, name: '样例', quality: 'UR', count: 1, max_owned: 1});
    const resource = h.resources.Lookup(item), resourceBefore = JSON.stringify(resource), itemBefore = JSON.stringify(item);
    assert(resource && resource.uri, 'exercise a real registered item URI');
    const reference = new Panel('Image');
    h.resources.FillIcon(reference, item);
    assert.match(reference.style.border, /^1px solid /, 'the shared API still frames other consumers');
    assert.notEqual(reference.style.backgroundImage, 'none', 'the shared texture remains available outside this archive grid');
    const sharedStyleBefore = JSON.stringify(reference.style);
    for (const category of ['points', 'commerce_goods']) {
        h.context.current = category;
        const card = new Panel();
        let host, art;
        for (const data of [item, {...item, count: 0, quality: 'SSR'}, {...item, count_known: 0, quality: 'R'}, item]) {
            const expected = new Panel('Image'); h.resources.FillIcon(expected, data);
            h.context.decorate(card, data, 0);
            const cell = card.__v10;
            if (!host) { host = cell.host; art = cell.art; }
            assert.equal(cell.host, host, category + ' receipt refresh retains its host');
            assert.equal(cell.art, art, category + ' receipt refresh retains its artwork');
            assert.equal(art.uri, resource.uri, category + ' retains the shared registered resource');
            assert.equal(art.style.border, '0px', category + ' does not restore a quality outline during repaint');
            assert.equal(art.style.backgroundImage, 'none', category + ' does not restore the texture bevel during repaint');
            assert.equal(art.style.backgroundColor, expected.style.backgroundColor, category + ' retains the current quality color');
            assert.equal(art.__survivalItemGrade, h.resources.Grade(data));
            assert.equal(art.scaling, expected.scaling, category + ' retains shared icon fitting');
            assert.equal(art.style.brightness, data.count_known === 0 ? '.62' : data.count > 0 ? '1' : '.38', category + ' still conveys ownership by brightness');
            assert.equal(card.BHasClass('ArchiveCommerceOwned'), data.count_known !== 0 && data.count > 0);
        }
    }
    assert.equal(JSON.stringify(item), itemBefore, 'archive presentation leaves authoritative item data unchanged');
    assert.equal(JSON.stringify(resource), resourceBefore, 'archive presentation does not alter the shared registry');
    assert.equal(JSON.stringify(reference.style), sharedStyleBefore, 'archive repaint does not change another consumer panel');
    const after = new Panel('Image'); h.resources.FillIcon(after, item);
    assert.equal(after.style.border, reference.style.border, 'archive repaint does not alter shared border policy');
    assert.equal(after.style.backgroundImage, reference.style.backgroundImage, 'archive repaint does not alter shared texture policy');
});

test('Void archive keeps geometry cache while changing recognized and missing grades', () => {
    const h = environment({valid: node => node && node.IsValid(), pos() {}, p: () => null,
        numberKnown: () => true, quantity: item => String(item.count), displayText: value => value});
    const item = {id: noGradeID, name: '样例', count: 1, quality: 'UR'}, card = new Panel(), art = new Panel('Image', card);
    const geometry = {id: noGradeID, icon_asset: 'test_icon', icon_bbox: [0, 0, 64, 64], quantity_bbox: [0, 0, 20, 20], name_bbox: [0, 0, 64, 20]};
    const cached = {panel: card, art, artKey: 'test_icon', plaque: new Panel(), count: new Panel(), name: new Panel()};
    Object.assign(h.context, {cfg: h.cfg, rowCards: {[noGradeID]: cached}, currentFilter: 'all', hoveredCard: null,
        D: {items: [geometry]}, itemGeometry: () => geometry,
        fillIcon: h.cfg.SurvivalRewardPresentation.FillIcon});
    h.run(productionPart('archive_void_v1.js', '    function renderItems(rows){', '    function inspectGeometry('));
    h.context.renderItems([item]); assert.equal(art.testGrade, 'UR');
    delete item.quality; h.context.renderItems([item]); assert.equal(art.testGrade, '');
    item.quality = 'N'; h.context.renderItems([item]); assert.equal(art.testGrade, 'N');
    assert.equal(h.context.rowCards[noGradeID], cached); assert.equal(cached.art, art);
});
