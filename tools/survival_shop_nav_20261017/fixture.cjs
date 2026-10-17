'use strict';
// Run the complete production HUD and collection module with the existing
// native/entity fixture. These are behavior tests, not a rendering screenshot.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const fixturePath = path.join(root, 'tools/test_topnav_refresh_context.cjs');
let prefix = fs.readFileSync(fixturePath, 'utf8').split('\nfunction run(code) {')[0];
// Only its native fixture is reused; this task does not depend on the old,
// ignored performance-baseline artifact read by that standalone comparison.
const baselineRead = "const before = fs.readFileSync(path.join(root, process.argv[3] || baseline), 'utf8');";
assert.equal(prefix.split(baselineRead).length, 2);
prefix = prefix.replace(baselineRead, "const before = '';");
const exportPoint = 'return {state,counters,cfg,map,ctx,Panel,skill,health';
assert.equal(prefix.split(exportPoint).length, 2, 'existing complete-HUD fixture export remains identifiable');
prefix = prefix.replace(exportPoint,
    'return {env,timers,loadCode: extra => vm.runInContext(extra,env),state,counters,cfg,map,ctx,Panel,skill,health');
// The real corner shortcut exists before topnav initializes. Create it at the
// same point in the native fixture, rather than adding it after first layout.
const snapshotPoint = '    const initial = {sequence: 1,';
assert.equal(prefix.split(snapshotPoint).length, 2);
prefix = prefix.replace(snapshotPoint,
    "    const cornerPortrait = new Panel('Button','SurvivalLocalHeroPortrait',ctx); cornerPortrait.style.width=cornerPortrait.style.height='64px';\n" + snapshotPoint);
const fixtureModule = {exports: {}};
new Function('require', '__dirname', 'process', 'module', prefix + '\nmodule.exports = {fixture};')(
    require, path.dirname(fixturePath), {argv: ['node', __filename], env: {}}, fixtureModule);
const hudCode = fs.readFileSync(path.join(root, 'panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js'), 'utf8');
const read = name => fs.readFileSync(path.join(root, 'panorama/src/scripts/custom_game', name), 'utf8');
function makeFixture() {
    const f = fixtureModule.exports.fixture(hudCode), actions = [], stack = [];
    const portrait = f.ctx.FindChildTraverse('SurvivalLocalHeroPortrait');
    const addNative = id => new f.Panel('Button', id, f.ctx.GetParent());
    addNative('DashboardButton'); addNative('SettingsButton');
    Object.assign(f.cfg, {
        SurvivalShopUnlocks: {shop: false},
        SurvivalShop: {ToggleShop() {actions.push('survival_shop');}},
        SurvivalTreasure: {Toggle() {actions.push('treasure');}},
        SurvivalArchive: {Toggle() {actions.push('archive');}},
        SurvivalLottery: {Open() {actions.push('lottery');}},
        SurvivalDaily: {Open() {actions.push('benefit');}},
        SurvivalPayments: {Open() {actions.push('shop');}},
        SurvivalUILayers: {Top: () => stack.at(-1) || null},
        SurvivalCollection: {Open() {actions.push('collection');}, Close() {}},
        SurvivalPurpleShell: {Navigate(id) {actions.push(id);}},
        SurvivalUIRegistry: {tokens: {}, assets: {}, pending: {}, aliases: {}, projectPaths: {}}
    });
    f.loadCode(read('common/ui_components.js'));
    f.loadCode(read('collection_nav.js'));
    f.advance(1200);
    function currentTop() {
        return f.ctx.FindChildTraverse('HandoffHUD').children.filter(p => p.id === 'HandoffTop' && p.IsValid()).at(-1);
    }
    const entry = key => currentTop().FindChildTraverse('HandoffNav_' + key);
    function rect(panel) {
        const [x, y] = String(panel.style.position).split(/\s+/).map(parseFloat);
        return {x, y, width: parseFloat(panel.style.width), height: parseFloat(panel.style.height)};
    }
    function visible(panel) { return panel.visible !== false && panel.style.visibility !== 'collapse'; }
    function click(panel) { if (visible(panel) && panel.enabled !== false && panel.hittest !== false) panel.events.onactivate(); }
    return Object.assign(f, {actions, stack, portrait, currentTop, entry, rect, visible, click,
        collection: () => f.ctx.FindChildTraverse('HandoffNav_collection'),
        unlock(value) {f.cfg.SurvivalShopUnlocks = {shop: value}; f.advance(300);},
        refreshCollection() {f.cfg.SurvivalCollectionNav.Refresh();}});
}

module.exports={makeFixture,read};
