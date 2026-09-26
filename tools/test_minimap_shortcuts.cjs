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
const nodes = {}, calls = [];
let blocked = false, modal = null, builderAvailable = true, homeAvailable = true;
function panel(id, parent, type = 'Panel') {
    const p = {id, parent, type, style: {}, children: [], handlers: {}, visible: true, classes: new Set(),
        IsValid() { return true; }, GetParent() { return this.parent; }, FindChildTraverse(key) { return nodes[key] || null; },
        AddClass(c) { this.classes.add(c); }, BHasClass(c) { return this.classes.has(c); },
        SetHasClass(c, state) { state ? this.classes.add(c) : this.classes.delete(c); },
        RemoveAndDeleteChildren() { this.children = []; }, SetPanelEvent(name, fn) { this.handlers[name] = fn; }, SetImage(src) { this.src = src; },
        GetPositionWithinWindow() { const values=String(this.style.position || '0px 0px').split(/\s+/); return {x:parseFloat(values[0]) * (ctx.actualuiscale_x || 1), y:parseFloat(values[1]) * (ctx.actualuiscale_y || 1)}; }};
    if (parent) parent.children.push(p);
    if (id) nodes[id] = p;
    return p;
}
const root = panel('Hud'), ctx = panel('Context', root);
ctx.actuallayoutwidth = 1672; ctx.actuallayoutheight = 941; ctx.actualuiscale_x = 1; ctx.actualuiscale_y = 1;
const shortcuts = panel('SurvivalMinimapShortcuts', ctx), production = panel('SurvivalProductionPanel', ctx); production.visible = false;
const cfg = {SurvivalShortcutGuard: {IsBlocked: () => blocked}, SurvivalUILayers: {Top: () => modal}};
const $ = {GetContextPanel: () => ctx, CreatePanel: (type, parent, id) => panel(id, parent, type)};
const env = {$, GameUI: {CustomUIConfig: () => cfg}};
vm.runInNewContext(source, env);
const ui = cfg.SurvivalMinimapShortcuts;
const builder = nodes.SurvivalSelectBuilderShortcut, home = nodes.SurvivalReturnHomeShortcut;
const click = button => button.handlers.onactivate();
const refresh = (ready = true) => ui.Refresh(hudGeometry(ctx.actuallayoutwidth / ctx.actualuiscale_x, ctx.actuallayoutheight / ctx.actualuiscale_y, 10), ready);
refresh(); click(builder); click(home);
assert.equal(calls.length, 0); assert.equal(builder.enabled, false); assert.equal(home.enabled, false);
cfg.SurvivalBuilderSelection = {CanSelect: () => builderAvailable, Select: source => calls.push(['select',source])};
cfg.SurvivalReturnHomeInput = {CanRequest: () => homeAvailable, Request: source => calls.push(['return',source])};
refresh(); click(builder); click(home);
assert.deepEqual(calls, [['select','minimap_shortcut'],['return','minimap_shortcut']], 'each click invokes exactly one existing shared action');
assert.equal(builder.enabled, true); assert.equal(home.enabled, true);
assert.equal(nodes.SurvivalSelectBuilderShortcutTitle, undefined, 'compact builder button has no side title');
assert.equal(nodes.SurvivalSelectBuilderShortcutKey.text, '空格');
assert.equal(nodes.SurvivalReturnHomeShortcutTitle, undefined, 'compact return button has no side title');
assert.equal(nodes.SurvivalReturnHomeShortcutKey.text, 'F2');
assert.equal(nodes.SurvivalSelectBuilderShortcutIcon.type, 'DOTAHeroImage');
assert.equal(nodes.SurvivalReturnHomeShortcutIcon.type, 'Image');
assert.equal(nodes.SurvivalReturnHomeShortcutIcon.src, 'file://{images}/spellicons/survival/native/skill_return.png');
blocked = true; click(builder); click(home);
assert.equal(calls.length, 2, 'live text-input/bootstrap guard wins even before the next availability refresh');
refresh(); assert.equal(builder.enabled, false); assert.equal(home.enabled, false);
blocked = false; modal = 'treasure'; refresh(); click(builder); click(home);
assert.equal(calls.length, 2, 'open dialogs never trigger an action');
modal = null; builderAvailable = false; refresh(); click(builder); click(home);
assert.equal(calls.length, 3); assert.equal(builder.enabled, false); assert.equal(home.enabled, true);
builderAvailable = true; homeAvailable = false; refresh(); click(builder); click(home);
assert.equal(calls.length, 4); assert.equal(builder.enabled, true); assert.equal(home.enabled, false);
homeAvailable = true; refresh(false); click(builder); click(home);
assert.equal(shortcuts.visible, false); assert.equal(calls.length, 4, 'unready HUD does not emit input');
refresh(); const oldGuard = cfg.SurvivalShortcutGuard; delete cfg.SurvivalShortcutGuard; click(builder);
assert.equal(calls.length, 4, 'guard loading must finish before any shortcut works'); cfg.SurvivalShortcutGuard = oldGuard;
ctx.actuallayoutwidth = 3344; ctx.actuallayoutheight = 1882; ctx.actualuiscale_x = 2; ctx.actualuiscale_y = 2;
refresh(); assert.equal(shortcuts.__survivalWindowWidth, 128); assert.equal(shortcuts.__survivalWindowHeight, 316);
production.visible = true; production.style.position = (parseFloat(shortcuts.style.position) + 10) + 'px 600px 0px';
production.__survivalWindowWidth = 800; production.__survivalWindowHeight = 480;
refresh();
const localXY = shortcuts.style.position.split(/\s+/).map(parseFloat);
assert(localXY[1] + 158 <= 592, 'production avoidance converts physical window dimensions back to the local canvas');
production.visible = false;
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/world_overlay_visibility.js','utf8'), env);
const position = shortcuts.GetPositionWithinWindow(), visibility = cfg.SurvivalWorldOverlayVisibility;
const snapshot = visibility.Capture();
assert(visibility.Overlaps(snapshot, position.x + 2, position.y + 2, 4, 4), 'world health bars are hidden behind shortcut buttons');
assert(!visibility.Overlaps(snapshot, position.x + 130, position.y + 2, 4, 4), 'physical scaled bounds do not hide unrelated world health bars');
shortcuts.visible = false;
assert(!visibility.Overlaps(visibility.Capture(), position.x + 2, position.y + 2, 4, 4), 'hidden shortcuts release their world mask');
const xml = fs.readFileSync('panorama/src/layout/custom_game/survival_hud.xml', 'utf8');
assert(xml.includes('styles/custom_game/minimap_shortcuts.css'));
assert(xml.indexOf('scripts/custom_game/minimap_shortcuts.js') > xml.indexOf('scripts/custom_game/combat_stats.js'));
assert(xml.indexOf('scripts/custom_game/minimap_shortcuts.js') < xml.indexOf('scripts/custom_game/topnav_remaining_5d5c1152eb.js'));
assert(!/CreateCustomKeyBind|AddCommand|SendCustomGameEventToServer|GetFocus/.test(source), 'buttons reuse guarded inputs without secondary binds or direct requests');
console.log('MINIMAP_SHORTCUTS_PASS: two shared actions, missing APIs, live guards, modal/unavailable states, map/portrait/production avoidance, scaled world mask and HUD load order');