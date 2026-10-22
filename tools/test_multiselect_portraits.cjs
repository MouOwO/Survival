// Exercise the production module against Valve's sibling HUD structure. Native
// frame/canvas/click handlers remain intact; these tests do not simulate pixels.
const fs = require('fs'), vm = require('vm'), assert = require('assert');
const source = fs.readFileSync('panorama/src/scripts/custom_game/multiselect_portraits.js', 'utf8');

function setup() {
    let selected = [1], selectedThrows = false;
    const config = {}, commands = {}, messages = [], nativeClicks = [], listeners = [];
    class Panel {
        constructor(id, parent, type = 'Panel') {
            this.id = id; this.parent = parent; this.paneltype = type;
            this.children = []; this.classes = new Set(); this.style = {};
            this.hittest = true; this.hittestchildren = true; this.visible = true;
            this.alive = true; this.actualuiscale_x = this.actualuiscale_y = 0.5;
            this.actuallayoutwidth = this.actuallayoutheight = 132;
            this.location = [200, 400, 0];
            if (parent) parent.children.push(this);
        }
        IsValid() { return this.alive; }
        GetParent() { return this.parent; }
        GetPositionWithinWindow() { return this.location; }
        GetChildCount() { return this.children.length; }
        GetChild(index) { return this.children[index]; }
        BHasClass(name) { return this.classes.has(name); }
        FindChildTraverse(id) {
            if (this.id === id) return this;
            for (const child of this.children) {
                const result = child.FindChildTraverse(id);
                if (result && result.alive) return result;
            }
            return null;
        }
    }
    const hud = new Panel('Hud'), block = new Panel('center_block', hud);
    block.location = [100, 300, 0];
    const group = new Panel('PortraitGroup', block);
    const container = new Panel('PortraitContainer', group);
    container.style.opacity = '0.8'; container.hittestchildren = false;
    const scene = new Panel('portraitHUD', container, 'DOTAPortrait');
    scene.style.opacity = '0.35';

    function nativeMulti() {
        const multi = new Panel('multiunit', block, 'DOTAMultiUnit');
        multi.style.width = '159px'; multi.style.height = '140px';
        multi.style.transform = 'none'; multi.style.margin = '0px 0px 0px 52px';
        multi.classes.add('ShowMultiUnit'); multi.classes.add('TwoColumns');
        const canvas = new Panel('canvas', multi, 'DOTAMultiUnitCanvas');
        canvas.style.width = '150px'; canvas.style.height = '180px';
        canvas.hittest = false;
        const frames = new Panel('UnitFrames', multi);
        const slots = [];
        for (let i = 0; i < 12; i++) {
            const frame = new Panel('Unit' + i, frames, 'DOTAMultiUnitFrame');
            frame.nativeActivate = () => nativeClicks.push(i);
            if (i >= 4) frame.classes.add('Hidden');
            if (i === 0) frame.classes.add('ActiveGroup');
            new Panel('HealthBar', frame, 'ProgressBar');
            new Panel('ManaBar', frame, 'ProgressBar');
            new Panel('ActiveGroupFrame', frame);
            slots.push(frame);
        }
        const pages = new Panel('PageButtons', multi);
        for (let i = 0; i < 5; i++) {
            const button = new Panel('PageButton' + i, pages, 'Button');
            button.nativeActivate = () => nativeClicks.push('page:' + i);
        }
        return {multi, canvas, frames, slots, pages};
    }
    const native = nativeMulti();
    vm.runInNewContext(source, {
        GameUI: {CustomUIConfig: () => config},
        Game: {GetLocalPlayerID: () => 0, AddCommand: (name, callback) => { commands[name] = callback; }},
        Players: {GetSelectedEntities: player => {
            assert.equal(player, 0);
            if (selectedThrows) throw Error('HUD transition');
            return selected;
        }},
        Entities: {IsValidEntity: id => id !== 999},
        GameEvents: {Subscribe: (name, callback) => { listeners.push({name, callback}); }},
        $: {Msg: value => messages.push(value)},
    }, {filename: 'multiselect_portraits.js'});
    return {api: config.SurvivalMultiSelectionPortraits, config, commands, messages, listeners,
        nativeClicks, Panel, hud, block, group, container, scene, native, nativeMulti,
        select: value => { selected = value; }, throwSelection: value => { selectedThrows = value; }};
}

// Real selections may be indexed objects. Filter duplicate/invalid entries and
// never turn a failed engine query into a fabricated multi-selection.
const a = setup();
assert.equal(a.api.IsActive(), false);
a.select({'0': 4, '1': '4', '2': -1, '3': null, '4': '', '5': 999});
assert.equal(a.api.IsActive(), false);
a.select({'0': 4, '1': '7', '2': 4});
assert.equal(a.api.IsActive(), true);
assert.equal(a.api.Inspect().selectedCount, 2);
assert.equal(a.api.Inspect().mounted, false);
a.throwSelection(true); assert.equal(a.api.IsActive(), false); a.throwSelection(false);

// Enemy queries preserve the commanded multi-selection. The displayed enemy
// must keep its single portrait and combat stats, then recover the grid when
// the player returns to a selected unit, including a second enemy query.
const query = setup();
query.select([1, 2]);
let displayed = 1;
query.config.SurvivalSelectionResolver = {ResolveDisplayUnit: () => displayed};
const queryCanvas = {...query.native.canvas.style};
const queryHandlers = query.native.slots.map(slot => slot.nativeActivate);
for (const [unit, active] of [[1, true], [77, false], [2, true], [88, false], ['1', true]]) {
    displayed = unit;
    assert.equal(query.api.IsActive(), active, 'query identity controls all portrait/stat consumers');
    assert.equal(query.api.Apply(query.group, 264), active, 'Apply uses the same predicate as IsActive');
    const report = query.api.Inspect();
    assert.equal(report.selectedCount, 2, 'querying does not change the command selection');
    assert.equal(report.active, active);
    assert.equal(report.mounted, active);
    assert.equal(query.container.style.opacity, active ? '0' : '0.8', 'enemy queries restore single-portrait pixels');
    assert.equal(query.container.hittest, !active);
    assert.equal(query.container.hittestchildren, false);
    assert.equal(query.scene.style.opacity, '0.35', 'the native portrait leaf retains its opacity');
    assert.deepEqual(query.native.canvas.style, queryCanvas);
    query.native.slots.forEach((slot, index) => assert.equal(slot.nativeActivate, queryHandlers[index]));
}
for (const invalid of [undefined, null, '', -1, NaN]) {
    displayed = invalid;
    assert.equal(query.api.IsActive(), false);
    assert.equal(query.api.Apply(query.group, 264), false);
    assert.equal(query.container.style.opacity, '0.8');
}
query.config.SurvivalSelectionResolver.ResolveDisplayUnit = () => { throw Error('query transition'); };
assert.equal(query.api.IsActive(), false);
assert.equal(query.api.Apply(query.group, 264), false);
assert.equal(query.api.Inspect().lastRestore.failed.length, 0);

// #multiunit is a SIBLING of PortraitGroup. Fit its native common parent into
// the portrait rect; preserve canvas pixels/frame dimensions and native events.
a.select([1, 2, 3, 4]);
const originalMulti = {...a.native.multi.style};
const frameHandlers = a.native.slots.map(slot => slot.nativeActivate);
const canvasStyle = {...a.native.canvas.style};
assert.equal(a.api.Apply(a.group, 264), true);
let report = a.api.Inspect();
assert.equal(report.mounted, true);
assert.equal(report.nativeFound, true);
assert.equal(report.layout.columns, 2);
assert.equal(report.layout.rows, 2);
assert(report.layout.nativeWidth * report.layout.fit <= 264);
assert(report.layout.nativeHeight * report.layout.fit <= 264);
assert(report.layout.nativeHeight > 140, 'unclip the second native portrait row');
assert.equal(a.container.style.opacity, '0');
assert.equal(a.container.hittest, false);
assert.equal(a.scene.style.opacity, '0.35', 'do not overwrite combat_stats leaf opacity');
assert.deepEqual(a.native.canvas.style, canvasStyle);
assert.equal(a.native.canvas.hittest, false);
assert.equal(a.native.multi.parent, a.block, 'native panels must not be reparented');
for (let i = 0; i < 12; i++) {
    assert.equal(a.native.slots[i].nativeActivate, frameHandlers[i]);
    assert.equal(a.native.slots[i].style.width, undefined);
    assert.equal(a.native.slots[i].classes.has('Hidden'), i >= 4);
}
assert(a.native.slots[0].classes.has('ActiveGroup'));
assert.equal(a.native.slots[0].FindChildTraverse('ActiveGroupFrame').style.border, undefined);
a.native.slots[2].nativeActivate();
a.native.pages.children[1].nativeActivate();
assert.deepEqual(a.nativeClicks, [2, 'page:1']);

// Selection grows through native 3/4-column modes. Paging is retained, does not
// force all hidden page buttons/frames visible, and fits within the same square.
for (const [count, columns] of [[9, 3], [12, 4], [25, 4]]) {
    a.select(Array.from({length: count}, (_, i) => i + 1));
    a.native.multi.classes.delete('TwoColumns');
    a.native.multi.classes.delete('ThreeColumns');
    if (columns === 3) a.native.multi.classes.add('ThreeColumns');
    if (count > 12) a.native.pages.children[0].classes.add('ShowButton');
    assert.equal(a.api.Apply(a.group, 264), true);
    report = a.api.Inspect();
    assert.equal(report.layout.columns, columns);
    assert.equal(report.layout.paged, count > 12);
    assert(report.layout.nativeWidth * report.layout.fit <= 264);
    assert(report.layout.nativeHeight * report.layout.fit <= 264);
    for (const page of a.native.pages.children) assert.equal(page.style.visibility, undefined);
}

// Workers own a compact, fixed outer viewport. Native content fits its actual
// rows within that rectangle; two selected workers do not reserve another row
// or display disproportionately large portraits. The root background stays
// transparent so the full custom backplate is visible in unused space.
// Canvas/frame sizes, native selection classes, health bars and input remain
// Valve-owned throughout this optional mode.
const worker = setup();
const workerOriginalMulti = {...worker.native.multi.style};
const workerOriginalCanvas = {...worker.native.canvas.style};
const workerOriginalFrames = worker.native.slots.map(slot => ({
    style: {...slot.style}, classes: [...slot.classes], activate: slot.nativeActivate,
    bars: ['HealthBar', 'ManaBar', 'ActiveGroupFrame'].map(id => ({
        panel: slot.FindChildTraverse(id), style: {...slot.FindChildTraverse(id).style},
    })),
}));
const workerPageHandlers = worker.native.pages.children.map(button => button.nativeActivate);
function assertWorkerFit(layout, origin = {x: 200, y: 200}, ratio = {x: 1, y: 1}) {
    const width = 264 * ratio.x, height = 237 * ratio.y;
    const padding = Math.min(width, height) * 0.025;
    const cap = (layout.columns === 2 ? 1.25 : layout.columns === 3 ? 1.5 : 1.6) * width / 264;
    assert.equal(layout.width, width, 'selection count must not resize the outer viewport');
    assert.equal(layout.height, height, 'selection count must not raise the outer viewport');
    assert(layout.fit <= cap + 1e-9, 'native large-column portraits respect their scale cap');
    assert(layout.nativeWidth * layout.fit <= width - padding * 2 + 1e-9);
    assert(layout.nativeHeight * layout.fit <= height - padding * 2 + 1e-9,
        'rows and any visible page controls remain inside the padded viewport');
    assert(Math.abs(layout.x + layout.nativeWidth * layout.fit / 2 - (origin.x + width / 2)) < 1e-9,
        'native content is horizontally centered in the fixed outer viewport');
    assert(Math.abs(layout.y + layout.nativeHeight * layout.fit / 2 - (origin.y + height / 2)) < 1e-9,
        'actual rows, without empty row reservations, are vertically centered');
}
let twoWorkerLayout;
for (const [count, columns] of [[2, 2], [3, 2], [4, 2], [5, 3], [6, 3], [9, 3], [12, 4], [13, 4], [25, 4]]) {
    worker.select(Array.from({length: count}, (_, index) => index + 1));
    worker.native.multi.classes.delete('TwoColumns');
    worker.native.multi.classes.delete('ThreeColumns');
    if (columns === 2) worker.native.multi.classes.add('TwoColumns');
    if (columns === 3) worker.native.multi.classes.add('ThreeColumns');
    worker.native.pages.children[0].classes.delete('ShowButton');
    if (count > 12) worker.native.pages.children[0].classes.add('ShowButton');
    const nativeClasses = [...worker.native.multi.classes];
    assert.equal(worker.api.Apply(worker.group, 264, 237), true);
    const layout = worker.api.Inspect().layout;
    assert.equal(layout.columns, columns);
    assert.equal(layout.rows, Math.ceil(Math.min(12, count) / columns));
    assert.equal(layout.paged, count > 12);
    assert.equal(layout.nativeWidth, 159);
    const cellHeight = columns === 2 ? 93 : columns === 3 ? 59 : 41;
    assert.equal(layout.nativeHeight, layout.rows * cellHeight + (columns < 4 ? 3 : 0) + (count > 12 ? 25 : 0),
        'only actual native rows and paging contribute to content height');
    assertWorkerFit(layout);
    assert.equal(worker.native.multi.style.backgroundColor, '#00000000');
    if (count === 2) {
        twoWorkerLayout = layout;
        assert.equal(layout.nativeHeight, 96, 'two workers have one native row, with no second-row reservation');
        assert.equal(layout.fit, 1.25, 'the two-column mode does not expand portraits to fill the full panel width');
    }
    assert.deepEqual(worker.native.canvas.style, workerOriginalCanvas);
    assert.deepEqual([...worker.native.multi.classes], nativeClasses);
    assert.equal(worker.native.multi.parent, worker.block);
    worker.native.slots.forEach((slot, index) => {
        const before = workerOriginalFrames[index];
        assert.deepEqual(slot.style, before.style);
        assert.deepEqual([...slot.classes], before.classes);
        assert.equal(slot.nativeActivate, before.activate);
        before.bars.forEach(bar => {
            assert.equal(slot.FindChildTraverse(bar.panel.id), bar.panel);
            assert.deepEqual(bar.panel.style, bar.style);
        });
    });
    worker.native.pages.children.forEach((button, index) => {
        assert.equal(button.nativeActivate, workerPageHandlers[index]);
        assert.equal(button.style.visibility, undefined);
    });
}

// Selection notifications can precede Valve's column-class update. Preserve
// every native row during that transition; the outer viewport stays fixed while
// native fitting catches up, instead of clipping rows or moving the bottom HUD.
worker.select(Array.from({length: 12}, (_, index) => index + 1));
worker.native.multi.classes.add('TwoColumns');
worker.native.pages.children[0].classes.delete('ShowButton');
assert.equal(worker.api.Apply(worker.group, 264, 237), true);
let delayedColumns = worker.api.Inspect().layout;
assert.equal(delayedColumns.columns, 2);
assert.equal(delayedColumns.rows, 6);
assert.equal(delayedColumns.nativeHeight, 6 * 93 + 3);
assertWorkerFit(delayedColumns);
assert.deepEqual(worker.native.canvas.style, workerOriginalCanvas);
worker.native.multi.classes.delete('TwoColumns');
assert.equal(worker.api.Apply(worker.group, 264, 237), true);
delayedColumns = worker.api.Inspect().layout;
assert.equal(delayedColumns.nativeHeight, 123);
assertWorkerFit(delayedColumns);
worker.native.slots[2].nativeActivate();
worker.native.pages.children[1].nativeActivate();
assert.deepEqual(worker.nativeClicks, [2, 'page:1']);

// Parent and portrait coordinate scales can differ after HUD rebuilds. Scale
// the cap with the actual viewport width while retaining the native pixel grid.
worker.group.actualuiscale_x = 0.75;
worker.group.actualuiscale_y = 0.6;
worker.select([1, 2]);
worker.native.multi.classes.add('TwoColumns');
assert.equal(worker.api.Apply(worker.group, 264, 237), true);
assertWorkerFit(worker.api.Inspect().layout, {x: 200, y: 200}, {x: 1.5, y: 1.2});
assert.equal(worker.api.Inspect().layout.fit, twoWorkerLayout.fit * 1.5,
    'two-column scale cap follows the portrait-to-parent coordinate scale');
assert.deepEqual(worker.native.canvas.style, workerOriginalCanvas);
worker.group.actualuiscale_x = worker.group.actualuiscale_y = 0.5;

// Leaving worker presentation must immediately use the original square and
// content-dependent fitting again; the optional rectangle must not leak into
// hero/other-unit portraits or survive a subsequent single selection.
worker.select([1, 2, 3, 4]);
worker.native.multi.classes.add('TwoColumns');
worker.native.pages.children[0].classes.delete('ShowButton');
assert.equal(worker.api.Apply(worker.group, 264), true);
let ordinaryLayout = worker.api.Inspect().layout;
assert.equal(ordinaryLayout.width, 264);
assert.equal(ordinaryLayout.height, 264);
assert.equal(ordinaryLayout.nativeHeight, 189);
assert(ordinaryLayout.fit > 1.25, 'ordinary square does not retain the compact worker scale cap');
function nativeBackground(value) { return String(value).replace(/\s+/g, ''); }
const defaultNativeBackground = 'gradient( linear, 0% 0%, 0% 100%, from( #222629 ), to( #0e1011 ) )';
assert.equal(nativeBackground(worker.native.multi.style.backgroundColor), nativeBackground(defaultNativeBackground),
    'ordinary portraits regain the original native background immediately');
worker.select([1, 2]);
assert.equal(worker.api.Apply(worker.group, 264), true);
ordinaryLayout = worker.api.Inspect().layout;
assert.equal(ordinaryLayout.nativeHeight, 96, 'ordinary mode remains content adaptive');
assert.equal(worker.api.Apply(worker.group, 264, 237), true);
worker.select([1]);
assert.equal(worker.api.Apply(worker.group, 264, 237), false);
assert.equal(worker.api.Inspect().mounted, false);
assert.equal(worker.container.style.opacity, '0.8');
assert.equal(worker.container.hittest, true);
assert.equal(worker.container.hittestchildren, false);
for (const key of Object.keys(workerOriginalMulti)) {
    assert.equal(worker.native.multi.style[key], workerOriginalMulti[key]);
}
assert.equal(worker.native.multi.style.position, '');
assert.equal(worker.native.pages.style.marginBottom, '-8px');
assert.equal(nativeBackground(worker.native.multi.style.backgroundColor), nativeBackground(defaultNativeBackground));
assert.deepEqual(worker.native.canvas.style, workerOriginalCanvas);

// Restore custom backgrounds exactly for both ordinary multi-selection and a
// later single selection. Empty background resets are rejected by Panorama, so
// the CSS default is an explicit gradient rather than an empty inline value.
for (const original of [undefined, '#12345688', 'gradient( linear, 0% 0%, 100% 0%, from( #112233 ), to( #445566 ) )']) {
    const t = setup();
    if (original !== undefined) t.native.multi.style.backgroundColor = original;
    let invalidBackgroundWrites = 0;
    t.native.multi.style = new Proxy(t.native.multi.style, {set(target, property, value) {
        if (property === 'backgroundColor' && (value === '' || value === null || value === undefined)) {
            invalidBackgroundWrites++;
            throw Error('native background requires an explicit color or gradient');
        }
        target[property] = value;
        return true;
    }});
    t.select([1, 2]);
    assert.equal(t.api.Apply(t.group, 264, 237), true);
    assert.equal(t.native.multi.style.backgroundColor, '#00000000');
    assert.equal(t.api.Apply(t.group, 264), true);
    assert.equal(nativeBackground(t.native.multi.style.backgroundColor), nativeBackground(original || defaultNativeBackground));
    assert.equal(t.api.Apply(t.group, 264, 237), true);
    t.select([1]);
    assert.equal(t.api.Apply(t.group, 264, 237), false);
    assert.equal(nativeBackground(t.native.multi.style.backgroundColor), nativeBackground(original || defaultNativeBackground));
    assert.equal(invalidBackgroundWrites, 0);
    assert.equal(t.api.Inspect().lastRestore.failed.length, 0);
}

// Going back to one unit restores all original inline styling and interaction,
// including nondefault values. No stale multi-grid survives portrait selection.
a.select([1]);
assert.equal(a.api.Apply(a.group, 264), false);
assert.equal(a.api.Inspect().mounted, false);
assert.equal(a.container.style.opacity, '0.8');
assert.equal(a.container.hittest, true);
assert.equal(a.container.hittestchildren, false);
for (const key of Object.keys(originalMulti)) assert.equal(a.native.multi.style[key], originalMulti[key]);
assert.equal(a.native.multi.style.position, '');
assert.equal(a.native.pages.style.marginBottom, '-8px');

// Restore native alignment/animation/margin defaults, retaining explicit values.
// Active-unit borders remain untouched, including native shorthand values.
for (const explicit of [false, true]) {
    const t = setup();
    const multiDefaults = {horizontalAlign: 'left', verticalAlign: 'bottom',
        transitionProperty: 'none', animationName: 'none'};
    const multiCustom = {horizontalAlign: 'right', verticalAlign: 'top',
        transitionProperty: 'blur', animationName: 'StunPortrait'};
    const custom = explicit ? multiCustom : {};
    Object.assign(t.native.multi.style, custom);
    if (explicit) t.native.pages.style.marginBottom = '-2px';
    for (const slot of t.native.slots) {
        if (explicit) slot.FindChildTraverse('ActiveGroupFrame').style.border = '2px solid #123456';
    }
    let invalidWrites = 0;
    function strict(panel, keys) {
        panel.style = new Proxy(panel.style, {set(target, property, value) {
            if (keys.includes(property) && (value === '' || value === null || value === undefined)) {
                invalidWrites++;
                throw Error('native style requires an explicit value: ' + property);
            }
            target[property] = value;
            return true;
        }});
    }
    strict(t.native.multi, Object.keys(multiDefaults));
    strict(t.native.pages, ['marginBottom']);
    for (const slot of t.native.slots) strict(slot.FindChildTraverse('ActiveGroupFrame'), ['border']);
    t.select([1, 2, 3]);
    assert.equal(t.api.Apply(t.group, 264), true);
    t.select([1]);
    t.api.Apply(t.group, 264);
    for (const key of Object.keys(multiDefaults)) {
        assert.equal(t.native.multi.style[key], explicit ? multiCustom[key] : multiDefaults[key]);
    }
    assert.equal(t.native.pages.style.marginBottom, explicit ? '-2px' : '-8px');
    for (const slot of t.native.slots) {
        assert.equal(slot.FindChildTraverse('ActiveGroupFrame').style.border,
            explicit ? '2px solid #123456' : undefined);
    }
    assert.equal(invalidWrites, 0);
    assert.equal(t.api.Inspect().lastRestore.failed.length, 0);
}

// Native numeric opacity setters can reject an empty-string reset. A default
// inline opacity must recover to 1 while explicit zero/nondefault values remain
// exact. A strict setter makes the previous swallowed-error regression visible.
for (const original of [undefined, '', '0', 0, '0.25']) {
    const t = setup();
    const values = {opacity: original};
    let invalidOpacityWrites = 0;
    t.container.style = new Proxy(values, {set(target, property, value) {
        if (property === 'opacity' && (value === '' || value === null || value === undefined)) {
            invalidOpacityWrites++;
            throw Error('native opacity requires a number');
        }
        target[property] = value;
        return true;
    }});
    t.select([1, 2]);
    assert.equal(t.api.Apply(t.group, 264), true);
    assert.equal(values.opacity, '0');
    t.select([1]);
    t.api.Apply(t.group, 264);
    const expected = original === undefined || original === '' ? '1' : String(original);
    assert.equal(values.opacity, expected);
    assert.equal(invalidOpacityWrites, 0);
    const restored = t.api.Inspect();
    assert.equal(restored.singlePortrait.container.opacity, expected);
    assert.equal(restored.singlePortrait.portrait.opacity, '0.35');
    assert.equal(restored.lastRestore.opacity[0].applied, expected);
    assert.equal(restored.lastRestore.failed.length, 0);
    // Normal single-selection refresh must not erase the last restore result.
    t.api.Apply(t.group, 264);
    assert.equal(t.api.Inspect().lastRestore.opacity[0].applied, expected);
}

// An engine HUD rebuild replaces children without a selection event. A fresh
// Apply finds the new native tree, never writing to released panel handles.
a.select([1, 2]); a.api.Apply(a.group, 264);
a.native.multi.alive = false;
a.block.children = a.block.children.filter(child => child !== a.native.multi);
const fresh = a.nativeMulti();
assert.equal(a.api.Apply(a.group, 264), true);
assert.notEqual(fresh.multi.style.height, '140px');
assert.equal(fresh.multi.children.filter(child => child.paneltype === 'DOTAScenePanel').length, 0);

// A mounted grid must release its single-portrait mask if only a native child
// or layout metric disappears. It can then reacquire the SAME parent safely.
for (const failure of ['canvas', 'frames', 'geometry', 'scale', 'size']) {
    const t = setup();
    t.select([1, 2, 3]);
    assert.equal(t.api.Apply(t.group, 264), true);
    assert.equal(t.container.style.opacity, '0');
    if (failure === 'canvas') t.native.canvas.alive = false;
    if (failure === 'frames') t.native.frames.alive = false;
    if (failure === 'geometry') t.group.location = [NaN, 400];
    if (failure === 'scale') t.group.actualuiscale_x = 0;
    assert.equal(t.api.Apply(t.group, failure === 'size' ? NaN : 264), false);
    assert.equal(t.api.IsActive(), true, 'the actual selection remains unchanged');
    assert.equal(t.api.Inspect().mounted, false);
    assert.equal(t.container.style.opacity, '0.8', failure + ' must restore the single portrait');
    assert.equal(t.container.hittest, true);
    assert.equal(t.native.multi.style.height, '140px');
    t.native.canvas.alive = t.native.frames.alive = true;
    t.group.location = [200, 400, 0];
    t.group.actualuiscale_x = 0.5;
    assert.equal(t.api.Apply(t.group, 264), true);
    assert.equal(t.api.Inspect().mounted, true);
    assert.equal(t.container.style.opacity, '0');
    t.select([1]); t.api.Apply(t.group, 264);
    assert.equal(t.container.style.opacity, '0.8', 'reacquisition must remember the restored value');
}

// Ancestor guard: tolerate a future native layout embedding multiunit under
// PortraitContainer. The containing branch must never be hidden as a whole.
const b = setup();
b.block.children = b.block.children.filter(child => child !== b.native.multi);
b.native.multi.parent = b.container; b.container.children.push(b.native.multi);
b.select([1, 2]);
assert.equal(b.api.Apply(b.group, 264), true);
assert.equal(b.container.style.opacity, '0.8');
assert.equal(b.scene.style.opacity, '0');
b.api.Restore();
assert.equal(b.scene.style.opacity, '0.35');

// Missing geometry stays unmounted and leaves the single portrait alone. The
// next complete layout can recover; the console probe exposes both conditions.
const c = setup(); c.select([1, 2]); c.group.location = [NaN, 400];
assert.equal(c.api.Apply(c.group, 264), false);
assert.equal(c.container.style.opacity, '0.8');
assert.equal(c.api.Inspect().active, true);
assert.equal(c.api.Inspect().mounted, false);
c.group.location = {x: 200, y: 400};
assert.equal(c.api.Apply(c.group, 264), true);
c.commands.survival_multiselect_inspect();
const probe = JSON.parse(c.messages[c.messages.length - 1].replace('[MULTI_PORTRAIT] ', ''));
assert.equal(probe.selectedCount, 2);
assert.equal(probe.frames.length, 12);
assert.equal(probe.mounted, true);
assert(!JSON.stringify(probe).includes('steam'));

// The debug event reports without depending on a registered console command,
// and old generation callbacks cannot report a stale HUD after hot reload.
const debug = c.listeners.find(item => item.name === 'survival_multiselect_debug_request');
assert(debug);
const beforeDebug = c.messages.length;
debug.callback({});
assert.equal(c.messages.length, beforeDebug + 1);
c.config.SurvivalMultiSelectionPortraits = {Inspect: () => ({build: 'replacement_context'})};
debug.callback({});
assert.equal(c.messages.length, beforeDebug + 1);
c.commands.survival_multiselect_inspect();
assert(c.messages[c.messages.length - 1].includes('replacement_context'));

console.log('MULTISELECT_PORTRAITS_PASS: native 2/3/4-column grid; compact 264x237 worker viewport for 2/3/4/5/6/9/12/13/25 selections; centered content, scale caps, transparent background restoration, shared canvas, paging/click preservation, HUD rebuild and diagnostic');
