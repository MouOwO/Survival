const assert = require('assert'), fs = require('fs'), vm = require('vm');
const sourcePath = 'panorama/src/scripts/custom_game/minimap_shortcuts.js';
const source = fs.readFileSync(sourcePath, 'utf8');
const model = require('../' + sourcePath);
const hudGeometry = require('../panorama/src/scripts/custom_game/geometry_remaining_5d5c1152eb.js');
for (const [width, height] of [[1920,1080],[1672,941],[1280,720],[1024,768],[800,600],[2560,1440]]) {
    for (const abilities of [4,10,19,32]) {
        const g = hudGeometry(width, height, abilities), bounds = model.Layout(width, height, g);
        assert(bounds.x >= g.minimapSize + 18, 'shortcuts never cover the native map');
        assert(bounds.x + bounds.width <= width && bounds.y >= 0 && bounds.y + bounds.height <= height);
        assert(!model.Overlaps(bounds, {x:g.x,y:g.y,width:g.width*g.scale,height:g.height*g.scale}), 'shortcuts avoid the complete portrait/skills/inventory HUD');
        const attachedPanel = {x: bounds.x + 10, y: bounds.y - 60, width: 420, height: 120};
        const moved = model.Layout(width, height, g, [attachedPanel]);
        assert(!model.Overlaps(moved, attachedPanel), 'open production panels move shortcuts higher instead of covering them');
        assert(moved.y < bounds.y);
        assert(bounds.scale * 20 >= 18, 'shortcut key retains a readable physical minimum');
    }
}
const nodes = {}, calls = [], sceneBindings = [];
let blocked = false, modal = null, builderAvailable = true;
function panel(id, parent, type = 'Panel') {
    const p = {id, parent, type, style: {}, children: [], handlers: {}, visible: true, classes: new Set(),
        IsValid() { return true; }, GetParent() { return this.parent; }, FindChildTraverse(key) { return nodes[key] || null; },
        AddClass(c) { this.classes.add(c); }, BHasClass(c) { return this.classes.has(c); },
        SetHasClass(c, state) { state ? this.classes.add(c) : this.classes.delete(c); },
        RemoveAndDeleteChildren() {
            const remove = child => { child.children.forEach(remove); if (child.id) delete nodes[child.id]; };
            this.children.forEach(remove); this.children = [];
        }, SetPanelEvent(name, fn) { this.handlers[name] = fn; }, SetImage(src) { this.src = src; },
        GetPositionWithinWindow() { const values=String(this.style.position || '0px 0px').split(/\s+/); return {x:parseFloat(values[0]) * (ctx.actualuiscale_x || 1), y:parseFloat(values[1]) * (ctx.actualuiscale_y || 1)}; }};
    if (parent) parent.children.push(p);
    if (id) nodes[id] = p;
    return p;
}
const root = panel('Hud'), ctx = panel('Context', root);
ctx.actuallayoutwidth = 1672; ctx.actuallayoutheight = 941; ctx.actualuiscale_x = 1; ctx.actualuiscale_y = 1;
const shortcuts = panel('SurvivalMinimapShortcuts', ctx), production = panel('SurvivalProductionPanel', ctx); production.visible = false;
// A previous HUD load may have left its F2 button behind. The new context must
// remove that node, including the descendants that could intercept input.
const previousHome = panel('SurvivalReturnHomeShortcut', shortcuts, 'Button');
panel('SurvivalReturnHomeShortcutIcon', previousHome, 'Image');
panel('SurvivalReturnHomeShortcutKey', previousHome, 'Label');
const cfg = {SurvivalShortcutGuard: {IsBlocked: () => blocked}, SurvivalUILayers: {Top: () => modal},
    SurvivalPortraitPresentation: {BindShortcutScene: (scene, key, hero, isHero) => {
        sceneBindings.push({scene, key, hero, isHero});
    }}};
const $ = {GetContextPanel: () => ctx, CreatePanel: (type, parent, id) => panel(id, parent, type)};
const env = {$, GameUI: {CustomUIConfig: () => cfg}};
vm.runInNewContext(source, env);
const ui = cfg.SurvivalMinimapShortcuts;
const builder = nodes.SurvivalSelectBuilderShortcut;
const click = button => button.handlers.onactivate();
const refresh = (ready = true) => ui.Refresh(hudGeometry(ctx.actuallayoutwidth / ctx.actualuiscale_x, ctx.actuallayoutheight / ctx.actualuiscale_y, 10), ready);
assert.equal(shortcuts.children.length, 1, 'only the builder button occupies the minimap shortcut column');
for (const id of ['SurvivalReturnHomeShortcut', 'SurvivalReturnHomeShortcutIcon', 'SurvivalReturnHomeShortcutKey']) {
    assert.equal(nodes[id], undefined, 'reload removes the old F2 node and its descendants');
}
const scene = nodes.SurvivalSelectBuilderShortcutIcon;
assert.equal(scene.type, 'DOTAScenePanel');
assert.equal(scene.hittest, false, 'the 3D scene leaves button input to its parent');
assert.equal(scene.hittestchildren, false);
assert.equal(sceneBindings.length, 1, 'builder scene is bound once when the button is assembled');
assert.equal(sceneBindings[0].scene, scene);
assert.equal(sceneBindings[0].key, 'builder_io');
assert.equal(sceneBindings[0].hero, 'npc_dota_hero_wisp');
assert.equal(sceneBindings[0].isHero, false);
refresh(); click(builder);
assert.equal(calls.length, 0); assert.equal(builder.enabled, false);
cfg.SurvivalBuilderSelection = {CanSelect: () => builderAvailable, Select: source => calls.push(['select',source])};
refresh(); click(builder);
assert.deepEqual(calls, [['select','minimap_shortcut']], 'a click invokes exactly one existing shared builder action');
assert.equal(builder.enabled, true);
assert.equal(nodes.SurvivalSelectBuilderShortcutTitle, undefined, 'compact builder button has no side title');
assert.equal(nodes.SurvivalSelectBuilderShortcutKey.text, '空格');
assert.equal(shortcuts.style.height, '76px', 'the removed F2 button leaves no empty slot');
blocked = true; click(builder);
assert.equal(calls.length, 1, 'live text-input/bootstrap guard wins even before the next availability refresh');
refresh(); assert.equal(builder.enabled, false);
blocked = false; modal = 'treasure'; refresh(); click(builder);
assert.equal(calls.length, 1, 'open dialogs never trigger an action');
modal = null; builderAvailable = false; refresh(); click(builder);
assert.equal(calls.length, 1); assert.equal(builder.enabled, false);
builderAvailable = true; refresh(); click(builder);
assert.equal(calls.length, 2); assert.equal(builder.enabled, true);
refresh(false); click(builder);
assert.equal(shortcuts.visible, false); assert.equal(calls.length, 2, 'unready HUD does not emit input');
refresh(); const oldGuard = cfg.SurvivalShortcutGuard; delete cfg.SurvivalShortcutGuard; click(builder);
assert.equal(calls.length, 2, 'guard loading must finish before any shortcut works'); cfg.SurvivalShortcutGuard = oldGuard;
ctx.actuallayoutwidth = 3344; ctx.actuallayoutheight = 1882; ctx.actualuiscale_x = 2; ctx.actualuiscale_y = 2;
refresh(); assert.equal(shortcuts.__survivalWindowWidth, 128); assert.equal(shortcuts.__survivalWindowHeight, 152);
const initialXY = shortcuts.style.position.split(/\s+/).map(parseFloat);
production.visible = true; production.style.position = (initialXY[0] + 10) + 'px ' + (initialXY[1] - 60) + 'px 0px';
production.__survivalWindowWidth = 800; production.__survivalWindowHeight = 480;
refresh();
const localXY = shortcuts.style.position.split(/\s+/).map(parseFloat);
assert(localXY[1] + 76 <= initialXY[1] - 68, 'production avoidance converts physical window dimensions back to the local canvas');
assert.equal(sceneBindings.length, 1, 'state and layout refreshes reuse the original scene without creating or rebinding it');
production.visible = false;
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/world_overlay_visibility.js','utf8'), env);
const position = shortcuts.GetPositionWithinWindow(), visibility = cfg.SurvivalWorldOverlayVisibility;
const snapshot = visibility.Capture();
assert(visibility.Overlaps(snapshot, position.x + 2, position.y + 2, 4, 4), 'world health bars are hidden behind shortcut buttons');
assert(!visibility.Overlaps(snapshot, position.x + 130, position.y + 2, 4, 4), 'physical scaled bounds do not hide unrelated world health bars');
assert(!visibility.Overlaps(snapshot, position.x + 2, position.y + 154, 4, 4), 'the removed F2 slot no longer masks world health bars');
shortcuts.visible = false;
assert(!visibility.Overlaps(visibility.Capture(), position.x + 2, position.y + 2, 4, 4), 'hidden shortcuts release their world mask');
const xml = fs.readFileSync('panorama/src/layout/custom_game/survival_hud.xml', 'utf8');
assert(xml.includes('styles/custom_game/minimap_shortcuts.css'));
assert(xml.indexOf('scripts/custom_game/minimap_shortcuts.js') > xml.indexOf('scripts/custom_game/combat_stats.js'));
assert(xml.indexOf('scripts/custom_game/minimap_shortcuts.js') < xml.indexOf('scripts/custom_game/topnav_remaining_5d5c1152eb.js'));
assert(!/CreateCustomKeyBind|AddCommand|SendCustomGameEventToServer|GetFocus/.test(source), 'buttons reuse guarded inputs without secondary binds or direct requests');
console.log('MINIMAP_SHORTCUTS_PASS: one Io scene button, old F2 node cleanup, single guarded action, cached scene binding, compact world mask, map/portrait/production avoidance and HUD load order');

// During a partial hot update the portrait controller can still expose its old
// API. Render the new shortcut against that actual missing-method boundary.
{
    const legacyNodes = {}, legacyUnits = [], legacySelections = [];
    function legacyPanel(id, parent, type = 'Panel') {
        const node = {id, type, children: [], style: {}, handlers: {}, visible: true,
            IsValid() { return true; }, FindChildTraverse(key) { return legacyNodes[key] || null; },
            AddClass() {}, SetHasClass() {}, SetPanelEvent(name, fn) { this.handlers[name] = fn; },
            RemoveAndDeleteChildren() {
                const remove = child => { child.children.forEach(remove); delete legacyNodes[child.id]; };
                this.children.forEach(remove); this.children = [];
            },
            SetUnit(...args) { legacyUnits.push({node: this, args}); }};
        if (parent) parent.children.push(node);
        legacyNodes[id] = node;
        return node;
    }
    const legacyContext = legacyPanel('LegacyContext');
    Object.assign(legacyContext, {actuallayoutwidth: 1672, actuallayoutheight: 941, actualuiscale_x: 1, actualuiscale_y: 1});
    const legacyShortcuts = legacyPanel('SurvivalMinimapShortcuts', legacyContext);
    const legacyCfg = {SurvivalPortraitPresentation: {Refresh() {}},
        SurvivalShortcutGuard: {IsBlocked: () => false}, SurvivalUILayers: {Top: () => null},
        SurvivalBuilderSelection: {CanSelect: () => true, Select: from => legacySelections.push(from)}};
    const legacyEnv = {$: {GetContextPanel: () => legacyContext,
        CreatePanel: (type, parent, id) => legacyPanel(id, parent, type)},
        GameUI: {CustomUIConfig: () => legacyCfg}};
    vm.runInNewContext(source, legacyEnv, {filename: 'minimap_shortcuts_legacy_portrait_api.js'});
    assert.equal(typeof legacyCfg.SurvivalMinimapShortcuts.Refresh, 'function', 'old portrait API does not abort shortcut initialization');
    assert.equal(legacyShortcuts.children.length, 1);
    const legacyScene = legacyNodes.SurvivalSelectBuilderShortcutIcon;
    assert.equal(legacyScene.type, 'DOTAScenePanel');
    assert.equal(legacyScene.hittest, false); assert.equal(legacyScene.hittestchildren, false);
    assert.equal(legacyUnits.length, 1, 'legacy controller fallback loads one Io scene');
    assert.equal(legacyUnits[0].node, legacyScene);
    assert.deepEqual(legacyUnits[0].args, ['npc_dota_hero_wisp', 'default', false]);
    for (let i = 0; i < 5; i++) legacyCfg.SurvivalMinimapShortcuts.Refresh(hudGeometry(1672, 941, 10), true);
    assert.equal(legacyUnits.length, 1, 'legacy fallback does not reload the model during availability refreshes');
    assert.equal(legacyShortcuts.style.height, '76px');
    assert.equal(legacyNodes.SurvivalReturnHomeShortcut, undefined);
    assert.equal(legacyNodes.SurvivalReturnHomeShortcutIcon, undefined);
    assert.equal(legacyNodes.SurvivalReturnHomeShortcutKey, undefined);
    legacyNodes.SurvivalSelectBuilderShortcut.handlers.onactivate();
    assert.deepEqual(legacySelections, ['minimap_shortcut'], 'old portrait API preserves the original guarded click action');
    console.log('MINIMAP_SHORTCUT_LEGACY_PORTRAIT_API_PASS: missing helper fallback, one Io load, live click API, no refresh reload and no F2 slot');
}
