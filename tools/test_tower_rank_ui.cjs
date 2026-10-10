// SIMULATION: execute production JS against a panel/engine double. Static checks
// inspect the real XML/CSS; this intentionally does not claim Workshop rendering.
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const sourceArg = process.argv.indexOf('--source');
const sourcePath = sourceArg >= 0 ? process.argv[sourceArg + 1] : 'panorama/src/scripts/custom_game/tower_rank_ui.js';
const source = fs.readFileSync(sourcePath, 'utf8');
const anchorSource = fs.readFileSync('panorama/src/scripts/custom_game/world_health_bar_anchor.js', 'utf8');
const xml = fs.readFileSync('panorama/src/layout/custom_game/tower_rank_ui.xml', 'utf8');
const css = fs.readFileSync('panorama/src/styles/custom_game/tower_rank_ui.css', 'utf8');
assert(!/<(?:Image|Label)\b/.test(xml), 'empty initial layout must contain no display assets');
assert(/\.TowerRank\s*\{[^}]*visibility:\s*collapse/.test(css));
let nextTask = 0, nextListener = 0, nextPanel = 0;
let styleWrites = 0, originReads = 0, projectionReads = 0;
let nameWidthReads = 0, captionWidthReads = 0;
let healthBarOffset = 190, offsetThrows = false, projectedHeight;
const tasks = new Map(), listeners = new Map(), table = {}, config = {}, entities = {};
const debugListeners = new Map(), messages = [];
function stylesheetGeometry(className) {
    const rule = new RegExp('\\.' + className + '\\s*\\{([^}]*)\\}').exec(css);
    if (!rule) return {};
    const values = {};
    for (const match of rule[1].matchAll(/(?:^|;)\s*(position|width|height|max-width|horizontal-align|vertical-align|font-size|font-weight|text-align)\s*:\s*([^;]+)/g)) {
        values[match[1]] = match[2].trim();
    }
    return values;
}
function declaredNameColor(rarity) {
    let color;
    for (const rule of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
        const selectors = rule[1].split(',').map(value => value.trim());
        if (selectors.includes('.TowerRankName') || selectors.includes('.Rank' + rarity + ' .TowerRankName')) {
            const declaration = /(?:^|;)\s*color\s*:\s*([^;]+)/.exec(rule[2]);
            if (declaration) color = declaration[1].trim();
        }
    }
    return color;
}
function panel(id = '') {
    return { id, children: [], style: new Proxy({}, { set(target, key, value) {
            styleWrites++; target[key] = value; return true;
        } }), classes: new Set(), deleted: false,
        actualuiscale_x: 1, actualuiscale_y: 1,
        get actuallayoutwidth() {
            // Preserve the original viewport model. Only descendants acquire
            // measured dimensions from CSS/content and physical UI scaling.
            if (!this.parent) return this.viewportWidth === undefined ? 1920 : this.viewportWidth;
            if (this.classes.has('TowerRankName')) nameWidthReads++;
            if (this.classes.has('TowerRankCaption')) captionWidthReads++;
            if (this.layoutWidthOverride !== undefined) return this.layoutWidthOverride;
            return layoutSize(this, 'width') * root.actualuiscale_x;
        },
        set actuallayoutwidth(value) { this.viewportWidth = value; },
        get actuallayoutheight() {
            if (!this.parent) return this.viewportHeight === undefined ? 1080 : this.viewportHeight;
            return layoutSize(this, 'height') * root.actualuiscale_y;
        },
        set actuallayoutheight(value) { this.viewportHeight = value; },
        IsValid() { return !this.deleted; }, AddClass(c) {
            this.classes.add(c);
            Object.assign(this.style, stylesheetGeometry(c));
        },
        SetHasClass(c, on) { on ? this.classes.add(c) : this.classes.delete(c); },
        SetImage(uri) { this.image = uri; this.imageWrites = (this.imageWrites || 0) + 1; },
        GetPositionWithinWindow() { return this.windowOffset || { x: 0, y: 0 }; },
        DeleteAsync() { this.deleted = true; }
    };
}
const root = panel('root');
const $ = id => id === '#SurvivalTowerRanks' ? root : null;
$.GetContextPanel = () => root;
$.CreatePanel = (type, parent, id) => { const p = panel(id || ++nextPanel); p.type = type; p.parent = parent; parent.children.push(p); return p; };
$.Schedule = (_, callback) => { const id = ++nextTask; tasks.set(id, callback); return id; };
$.CancelScheduled = id => tasks.delete(id);
$.Msg = message => messages.push(message);
const sandbox = { $, GameUI: { CustomUIConfig: () => config },
    GameEvents: { Subscribe: (_, fn) => { const id = ++nextListener; debugListeners.set(id, fn); return id; },
        Unsubscribe: id => debugListeners.delete(id) },
    CustomNetTables: {
        GetTableValue: (_, key) => table[key],
        GetAllTableValues: () => Object.keys(table).map(key => ({ key, value: table[key] })),
        SubscribeNetTableListener: (_, fn) => { const id = ++nextListener; listeners.set(id, fn); return id; },
        UnsubscribeNetTableListener: id => listeners.delete(id)
    },
    Entities: {
        IsValidEntity: id => !!entities[id], IsAlive: id => entities[id].alive,
        IsDormant: id => entities[id].dormant, GetUnitName: id => entities[id].name,
        GetAbsOrigin: id => { originReads++; if (entities[id].throws) throw Error('removed during frame'); return entities[id].origin; },
        GetHealthBarOffset: () => { if (offsetThrows) throw Error('offset temporarily unavailable'); return healthBarOffset; }
    },
    Game: { WorldToScreenX: x => { projectionReads++; return x; },
        WorldToScreenY: (_, y, z) => { projectionReads++; projectedHeight = z; return y + z - 190; } }
};
function tick() { const due = [...tasks.values()]; tasks.clear(); due.forEach(fn => fn()); }
function settleNameLayout() { for (let frame = 0; frame < 4; frame++) tick(); }
function update(key, value) { table[key] = value; [...listeners.values()].forEach(fn => fn('survival_tower_rank', key, value)); }
function bars() { return root.children.filter(p => !p.deleted); }
function descendants(parent) { return parent.children.flatMap(child => [child, ...descendants(child)]); }
function layoutSize(child, dimension) {
    const value = child.style[dimension];
    // Supplied natural widths model different Label content sizes. They do
    // not measure Chinese fonts, shaping or visible pixels in the game.
    let size = value === 'fit-children'
        ? Number(child.intrinsicWidth === undefined ? 56 : child.intrinsicWidth)
        : parseFloat(value);
    if (dimension === 'width' && child.style['max-width']) size = Math.min(size, parseFloat(child.style['max-width']));
    return size;
}
function uiRect(child) {
    let x = 0, y = 0;
    for (let current = child; current && current !== root; current = current.parent) {
        const position = String(current.style.position || '0px 0px 0px').split(/\s+/);
        x += parseFloat(position[0]) || 0; y += parseFloat(position[1]) || 0;
        if (current.style['vertical-align'] === 'center') {
            y += (layoutSize(current.parent, 'height') - layoutSize(current, 'height')) / 2;
        }
    }
    return { x, y, width: layoutSize(child, 'width'), height: layoutSize(child, 'height') };
}
function close(actual, expected, message) {
    assert(Math.abs(actual - expected) <= 0.011, message + ': ' + actual + ' != ' + expected);
}
function assertPlacement(row, health) {
    // Apply geometry from the real stylesheet and assert the requested spatial
    // relationships, rather than duplicating the production layout algorithm.
    const name = uiRect(row.__name), image = uiRect(row.__letter), stars = uiRect(row.__starRow);
    close(image.x + image.width + 2, health.left, 'rarity image is two UI pixels left of the health bar');
    close(image.y + image.height / 2, health.top + health.height / 2, 'rarity and health bar centers align vertically');
    close(name.y + name.height, health.top, 'name lower edge touches the health bar upper edge');
    close(name.width, Math.min(108, Number(row.__name.intrinsicWidth === undefined ? 56 : row.__name.intrinsicWidth)),
        'name uses measured content width capped at the caption width');
    close(name.height, 20, 'name reserves the enlarged text line');
    assert.equal(row.__name.style['font-size'], '18px', 'tower name is enlarged to the agreed reference proportion');
    assert.equal(row.__name.style['font-weight'], 'bold', 'tower name has the agreed bold weight');
    assert.equal(row.__name.style['text-align'], 'center', 'glyph alignment is explicitly centered within the measured name box');
    assert.equal(row.__name.style.width, 'fit-children');
    assert.equal(row.__name.style['max-width'], '108px');
    assert.equal(row.__name.style['horizontal-align'], undefined, 'centering must not depend on a mocked CSS horizontal-align rule');
    close(name.x + name.width / 2, health.left + health.width / 2, 'name centers over the health bar');
    close(stars.x + stars.width / 2, health.left + health.width / 2, 'stars center over the health bar');
    close(stars.y + stars.height, name.y, 'stars sit directly above the name');
    close(stars.height, 12, 'star row now fits the unchanged sprite height');
    const sprite = uiRect(row.__stars[0]);
    close(sprite.height, 12, 'star art keeps its prior size');
    close(sprite.y - stars.y, 0, '12px star sprite fills the 12px row without extra vertical padding');
    close(name.y - (sprite.y + sprite.height), 0, 'star sprite lower edge directly touches the name box without overlap');
    const box = uiRect(row);
    // Screen/occlusion bounds reserve the same fixed text rectangle for every
    // name. Short content cannot move or narrow the caption coverage.
    close(box.width, 108, 'caption keeps the maximum name coverage');
    close(box.x + box.width / 2, health.left + health.width / 2, 'coverage centers over the same health bar');
    for (const child of [name, image, stars, sprite,
        { x: health.left, y: health.top, width: health.width, height: health.height }]) {
        assert(box.x <= child.x + 0.011 && box.y <= child.y + 0.011
            && box.x + box.width >= child.x + child.width - 0.011
            && box.y + box.height >= child.y + child.height - 0.011,
            'screen/occlusion bounds include every complete caption component');
    }
    close(stars.y - box.y, 2, 'caption preserves conservative top coverage above the lowered star row');
    close(box.y + box.height, Math.max(name.y + name.height, image.y + image.height,
        stars.y + stars.height, health.top + health.height), 'screen bounds include the image extending below the health bar');
}
function assertNoLevelBadge(row) {
    const labels = descendants(row).filter(p => p.type === 'Label');
    assert.equal(labels.length, 2, 'caption contains only the rarity fallback and unit name labels');
    assert(labels.includes(row.__name) && labels.includes(row.__ultimate));
    assert(!descendants(row).some(p => [...p.classes].some(c => /Level/i.test(c))),
        'caption must not create a right-side level badge');
}
vm.runInNewContext(anchorSource, sandbox);
if (process.argv.includes('--measure')) {
    // Count production code paths, not elapsed CPU/GPU time. This exact harness
    // also accepts --source <baseline.js> for an identical before/after load.
    const counts = { native: 0, capture: 0, findPanel: 0 };
    delete sandbox.Entities.IsDormant; // Current Workshop API does not expose it.
    Object.keys(sandbox.Entities).forEach(name => {
        const call = sandbox.Entities[name];
        sandbox.Entities[name] = (...args) => { counts.native++; return call(...args); };
    });
    const blockers = {};
    root.FindChildTraverse = id => {
        counts.findPanel++;
        if (!blockers[id]) { blockers[id] = panel(id); blockers[id].visible = false; }
        return blockers[id];
    };
    let blocked = false;
    config.SurvivalUILayers = { Top: () => blocked };
    vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/world_overlay_visibility.js', 'utf8'), sandbox);
    const capture = config.SurvivalWorldOverlayVisibility.Capture;
    config.SurvivalWorldOverlayVisibility.Capture = () => { counts.capture++; return capture(); };
    table._session = { id: 'measure' };
    for (let id = 1; id <= 40; id++) {
        entities[id] = { alive: true, name: 'tower', origin: [600, 400, 0] };
        table['unit_' + id] = { entindex: id, unit_name: 'tower', display_name: '神秘之塔', rarity: 'R', stars: 1, session: 'measure' };
    }
    vm.runInNewContext(source, sandbox); settleNameLayout();
    function captureFrames() {
        counts.native = counts.capture = counts.findPanel = 0;
        styleWrites = projectionReads = nameWidthReads = captionWidthReads = 0;
        for (let index = 0; index < 300; index++) tick();
        return { native_calls: counts.native, projection_calls: projectionReads,
            style_writes: styleWrites, overlay_captures: counts.capture, panel_searches: counts.findPanel,
            name_width_reads: nameWidthReads, caption_width_reads: captionWidthReads };
    }
    const stable = captureFrames();
    blocked = true;
    const beforeHide = styleWrites; tick();
    const blockTransitionWrites = styleWrites - beforeHide;
    const fullScreenBlocked = captureFrames();
    for (let id = 1; id <= 40; id++) update('unit_' + id, { removed: 1, session: 'measure' });
    blocked = false; tick();
    const noTowers = captureFrames();
    assert.equal(stable.style_writes, 0, 'stable captions must not rewrite geometry or style during 300 frames');
    assert.equal(stable.name_width_reads, 0, 'settled names must not reread layout width during 300 frames');
    assert.equal(stable.caption_width_reads, 0, 'settled captions must not reread parent layout width during 300 frames');
    assert.equal(fullScreenBlocked.native_calls, 0, 'covered captions skip entity queries');
    assert.equal(fullScreenBlocked.projection_calls, 0, 'covered captions skip world projection');
    assert.equal(fullScreenBlocked.style_writes, 0, 'fully hidden stable frames do not repeat visibility writes');
    assert.equal(fullScreenBlocked.name_width_reads, 0, 'covered names do not force text layout');
    assert.equal(noTowers.native_calls, 0, 'empty sessions do not query entities');
    assert.equal(noTowers.overlay_captures, 0, 'empty sessions skip HUD capture');
    console.log(JSON.stringify({ kind: 'offline_production_js_call_counts', source: sourcePath,
        towers: 40, frames_per_scenario: 300, stable, full_screen_blocked: fullScreenBlocked,
        block_transition_style_writes: blockTransitionWrites, no_towers: noTowers,
        caveat: 'Call counts only; not FPS, CPU/GPU frame time or measured Dota speedup.' }));
    process.exit(0);
}
vm.runInNewContext(source, sandbox);
assert.equal(bars().length, 0, 'no units = no image panels');
let emptyCaptures = 0;
config.SurvivalWorldOverlayVisibility = { Capture: () => { emptyCaptures++; return {}; } };
tick(); assert.equal(emptyCaptures, 0, 'zero tower state must skip HUD capture');
delete config.SurvivalWorldOverlayVisibility;
entities[1] = { alive: true, dormant: false, name: 'tower', origin: [600, 400, 0] };
const firstState = { entindex: 1, unit_name: 'tower', display_name: '神秘之塔', rarity: 'SSR', stars: 5,
    red_stars: 1, level: 2, constructing: 0, session: 'one' };
update('unit_1', firstState);
tick(); assert.equal(bars().length, 0, 'records cannot display before session metadata');
update('_session', { id: 'one' }); tick();
assert.equal(bars().length, 1);
let bar = bars()[0];
assert.equal(bar.style.visibility, 'visible');
assert(bar.classes.has('RankSSR'));
assert.equal(declaredNameColor('SSR'), '#ffdc75', 'SSR names use the agreed gold declaration');
assert.equal(bar.__letter.type, 'Image', 'rarity uses an explicit native Image panel');
assert.equal(bar.__letter.image, 's2r://panorama/images/custom_game/survival_tower_rank/rareicon_ssr_png.vtex');
assert.equal(bar.__stars.filter(s => s.classes.has('ActiveStar')).length, 5);
assert.equal(bar.__stars.filter(s => s.classes.has('RedStar')).length, 1);
assert.equal(bar.__starRow.style.width, '70px');
assert.equal(bar.__starRow.style.position, '19px 2px 0px', 'five stars center over the health bar at the lowered row position');
assert.equal(bar.__name.text, '神秘之塔', 'unit name is visible immediately above the health bar');
assert.equal(bar.style.position, '546.00px 340.00px 0px', 'enlarged name line stays immediately above the unchanged shared health bar anchor');
let anchor = config.SurvivalWorldHealthBarAnchor.Project(1, entities[1].origin, root);
assert.equal(anchor.left, 569); assert.equal(anchor.top, 374);
assert.equal(anchor.width, 62); assert.equal(anchor.height, 11);
settleNameLayout();
assertPlacement(bar, anchor);
for (const [displayName, naturalWidth] of [
    ['塔', 32], ['噬魂术士', 56], ['见习守望', 72.5], ['进阶噬魂术士', 84], ['很长的终极死亡路线防御塔名称', 168]
]) {
    bar.__name.intrinsicWidth = naturalWidth;
    nameWidthReads = captionWidthReads = 0;
    update('unit_1', { ...firstState, display_name: displayName }); settleNameLayout();
    assert.equal(bar.__name.text, displayName, 'content changes preserve the full name value');
    const name = uiRect(bar.__name);
    close(name.width, Math.min(108, naturalWidth), 'short text uses its own width; long text is capped');
    close(name.x + name.width / 2, anchor.left + anchor.width / 2,
        'production JS centers the measured name bounds without CSS horizontal-align');
    assert(nameWidthReads > 0 && nameWidthReads <= 3, 'name changes measure layout only during three bounded frames');
    assert(captionWidthReads > 0 && captionWidthReads <= 3, 'caption scale normalization has the same bounded work');
    assert.equal(tasks.size, 1, 'name measurement reuses the existing frame loop without adding timers');
    assertPlacement(bar, anchor);
}
// A Label can expose its old width immediately after changing its text. The
// next layout passes must repair that measurement without another net update.
bar.__name.layoutWidthOverride = 108;
bar.__name.intrinsicWidth = 46;
update('unit_1', { ...firstState, display_name: '短名' }); tick();
delete bar.__name.layoutWidthOverride;
settleNameLayout();
assertPlacement(bar, anchor);
close(parseFloat(bar.__name.style.position),31,'a stale prior text width is corrected on later frames');

// Simulate children appearing before their first measured layout: neither a
// zero text width nor a zero parent width may settle the name off center.
bar.__name.intrinsicWidth = 78;
bar.__name.layoutWidthOverride = 0;
bar.__caption.layoutWidthOverride = 0;
update('unit_1', { ...firstState, display_name: '延迟排版测试' }); tick();
delete bar.__caption.layoutWidthOverride; tick();
delete bar.__name.layoutWidthOverride; settleNameLayout();
assertPlacement(bar, anchor);
close(parseFloat(bar.__name.style.position),15,'late nonzero layout restores centered text');

bar.__name.intrinsicWidth = 74;
bar.__name.layoutWidthOverride = 3.402823466e38;
bar.__caption.layoutWidthOverride = 3.402823466e38;
update('unit_1', { ...firstState, display_name: '布局尚未就绪' }); settleNameLayout();
assert(!/e\+|NaN|Infinity/.test(bar.__name.style.position),'invalid native layout never reaches the position style');
delete bar.__name.layoutWidthOverride;delete bar.__caption.layoutWidthOverride;settleNameLayout();
assertPlacement(bar,anchor);
close(parseFloat(bar.__name.style.position),17,'FLT_MAX layout is retried once native dimensions arrive');

nameWidthReads = captionWidthReads = 0;
const settledWrites = styleWrites;
for (let frame = 0; frame < 100; frame++) tick();
assert.equal(nameWidthReads,0,'stable frames do not poll Label width');
assert.equal(captionWidthReads,0,'stable frames do not poll caption width');
assert.equal(styleWrites,settledWrites,'stable measured positions are not rewritten');
delete bar.__name.intrinsicWidth;
update('unit_1', firstState); settleNameLayout();
assert.equal(config.SurvivalTowerRanks.DebugSnapshot().units[0].display_name, '神秘之塔');
assert.equal(config.SurvivalTowerRanks.DebugSnapshot().units[0].name_label.text, '神秘之塔');
assert.equal(config.SurvivalTowerRanks.DebugSnapshot().units[0].health_anchor.top, anchor.top);
assertNoLevelBadge(bar);
assert.equal(config.SurvivalTowerRanks.DebugSnapshot().visible_count, 1);
let priorWrites = styleWrites;
const initialImageWrites = bar.__letter.imageWrites;
tick(); assert.equal(styleWrites, priorWrites, 'stable row position and visibility must not be rewritten');
assert.equal(bar.__letter.imageWrites, initialImageWrites, 'stable frames keep the already loaded rarity image');
const expectedNameColors = { N: '#f4f3e9', R: '#9cdbff', SR: '#cd9bff', SSR: '#ffdc75', UR: '#ffdc75' };
for (const rarity of ['N', 'R', 'SR', 'SSR']) {
    update('unit_1', { ...firstState, rarity });
    assert.equal(declaredNameColor(rarity), expectedNameColors[rarity], 'rarity maps to the declared name color');
    for (const candidate of ['N', 'R', 'SR', 'SSR', 'UR']) {
        assert.equal(bar.classes.has('Rank' + candidate), candidate === rarity,
            'rarity updates immediately select exactly one name-color class');
    }
    assert.equal(bar.__letter.image, 's2r://panorama/images/custom_game/survival_tower_rank/rareicon_'
        + rarity.toLowerCase() + '_png.vtex', 'every rarity transition loads its own native texture');
    assert.equal(bar.__ultimate.style.visibility, 'collapse');
    assert.equal(bars().length, 1, 'upgrades reuse the same caption');
}
update('unit_1', { ...firstState, display_name: '灵能尖塔', rarity: 'SR', stars: 3, red_stars: 0 });
assert.equal(bar.__name.text, '灵能尖塔', 'name updates in place when the tower advances');
assert(bar.classes.has('RankSR')); assert.equal(bars().length, 1);
assert.equal(bar.__letter.image, 's2r://panorama/images/custom_game/survival_tower_rank/rareicon_sr_png.vtex');
assert.equal(bar.__stars.filter(s => s.classes.has('ActiveStar')).length, 3);
assert.equal(bar.__stars.filter(s => s.classes.has('RedStar')).length, 0);
assert.equal(bar.__starRow.style.width, '42px');
assert.equal(bar.__starRow.style.position, '33px 2px 0px', 'fewer stars remain centered after upgrade at the lowered row position');
settleNameLayout();
assertPlacement(bar, anchor);
update('unit_1', { ...firstState, constructing: 1 });
assert.equal(bar.style.visibility, 'collapse', 'construction hides an existing caption as soon as its state arrives');
const constructionProjections = projectionReads;
tick(); assert.equal(bar.style.visibility, 'collapse');
assert.equal(projectionReads, constructionProjections, 'constructing towers do not project captions');
update('unit_1', firstState); tick();
assert.equal(bar.style.visibility, 'visible', 'completion restores the caption on the next frame');
entities[2] = { alive: true, name: 'tower', origin: [900, 500, 0] };
update('unit_2', { ...firstState, entindex: 2, constructing: 1 }); tick();
assert.equal(bars().length, 1, 'a new construction must not instantiate display assets');
update('unit_2', { ...firstState, entindex: 2, constructing: 0 }); tick();
assert.equal(bars().length, 2, 'a completed building creates its caption');
update('unit_2', { removed: 1, session: 'one' });
assert.equal(bars().length, 1); delete entities[2];
const priorOriginReads = originReads, priorProjectionReads = projectionReads;
config.SurvivalWorldOverlayVisibility = { Capture: () => ({ blocked: true }),
    Overlaps: () => { throw Error('full-screen block should bypass per-row overlap checks'); } };
tick(); assert.equal(bar.style.visibility, 'collapse', 'new full-screen block hides an existing row');
assert.equal(originReads, priorOriginReads); assert.equal(projectionReads, priorProjectionReads);
priorWrites = styleWrites;
entities[1].origin[0] = 640; tick();
assert.equal(styleWrites, priorWrites, 'hidden rows are not repeatedly rewritten');
assert.equal(originReads, priorOriginReads, 'movement under a full-screen UI does not trigger entity reads');
delete config.SurvivalWorldOverlayVisibility;
tick();
assert.equal(bar.style.visibility, 'visible', 'closing full-screen UI restores the next-frame row');
assert.equal(bar.style.position, '586.00px 340.00px 0px', 'movement while covered is read on resume');
entities[1].origin[0] = 600; tick();
const dormantAPI = sandbox.Entities.IsDormant, offsetAPI = sandbox.Entities.GetHealthBarOffset;
delete sandbox.Entities.IsDormant; delete sandbox.Entities.GetHealthBarOffset;
tick(); assert.equal(bar.style.visibility, 'visible', 'optional missing engine APIs must not hide all towers');
assert.equal(projectedHeight, 190, 'missing health-bar offset uses the same 190-unit fallback');
assert.equal(config.SurvivalTowerRanks.DebugSnapshot().api.is_dormant, false);
assert.equal(config.SurvivalTowerRanks.DebugSnapshot().lastError, '');
sandbox.Entities.IsDormant = dormantAPI; sandbox.Entities.GetHealthBarOffset = offsetAPI;
for (const offset of [-1, 0, NaN]) {
    healthBarOffset = offset; tick();
    assert.equal(projectedHeight, 190, 'hidden/invalid native offsets must not shift the caption');
    assert.equal(bar.style.position, '546.00px 340.00px 0px');
}
offsetThrows = true; tick(); assert.equal(projectedHeight, 190);
assert.equal(bar.style.visibility, 'visible', 'temporary offset errors use the shared fallback');
offsetThrows = false; healthBarOffset = 330; tick();
assert.equal(projectedHeight, 330);
assert.equal(bar.style.position, '546.00px 480.00px 0px', 'caption follows the native model health-bar height');
healthBarOffset = 190; tick();
entities[1].origin[0] = 2500; tick(); assert.equal(bar.style.visibility, 'collapse');
assert.equal(config.SurvivalTowerRanks.DebugSnapshot().hidden_reasons.invalid_projection, 1);
for (const [x, y, expected, reason] of [
    [53, 400, 'collapse', 'partially clipped name at the left edge'],
    [54, 400, 'visible', 'name touching the left edge'],
    [1867, 400, 'collapse', 'partially clipped name at the right edge'],
    [1866, 400, 'visible', 'name touching the right edge'],
    [600, 59, 'collapse', 'enlarged caption above the upper screen edge'],
    [600, 60, 'visible', 'enlarged caption touching the upper screen edge'],
    [600, 1091, 'collapse', 'rarity image below the screen despite an in-bounds health bar'],
    [600, 1090.5, 'visible', 'rarity image touching the lower screen edge']
]) {
    entities[1].origin = [x, y, 0]; tick();
    assert.equal(bar.style.visibility, expected, reason);
}
entities[1].origin = [600, 400, 0];
entities[1].origin[0] = 600; entities[1].dormant = true; tick(); assert.equal(bar.style.visibility, 'collapse');
entities[1].dormant = false; entities[1].throws = true; tick(); assert.equal(bar.style.visibility, 'collapse');
assert(config.SurvivalTowerRanks.DebugSnapshot().lastError.includes('removed during frame'));
entities[1].throws = false; tick(); assert.equal(bar.style.visibility, 'visible');
config.SurvivalWorldOverlayVisibility = { Capture: () => ({}), Overlaps: () => true };
tick(); assert.equal(bar.style.visibility, 'collapse');
assert.equal(config.SurvivalTowerRanks.DebugSnapshot().hidden_reasons.hud_occlusion, 1);
config.SurvivalWorldOverlayVisibility.Capture = () => { throw Error('optional HUD capture failure'); };
tick(); assert.equal(config.SurvivalTowerRanks.DebugSnapshot().hidden_reasons.frame_exception, 1);
delete config.SurvivalWorldOverlayVisibility;
nameWidthReads = captionWidthReads = 0;
root.actualuiscale_x = root.actualuiscale_y = 0.75; settleNameLayout();
assert.equal(bar.style.position, '746.00px 473.33px 0px', 'world pixels convert to UI scale');
assert(nameWidthReads > 0 && nameWidthReads <= 3,'viewport scale invalidates the bounded name measurement');
assert.equal(bar.__name.actuallayoutwidth,42,'56px text is measured in scaled physical pixels');
assert.equal(bar.__caption.actuallayoutwidth,81,'108px parent is measured in the same physical pixels');
assertPlacement(bar, config.SurvivalWorldHealthBarAnchor.Project(1, entities[1].origin, root));
// Some native layouts report logical widths even under a scaled viewport.
// Normalizing against the caption must work in either measurement convention.
bar.__name.layoutWidthOverride = 56;bar.__caption.layoutWidthOverride = 108;
update('unit_1', { ...firstState, display_name: '逻辑像素名称' });settleNameLayout();
assertPlacement(bar,config.SurvivalWorldHealthBarAnchor.Project(1,entities[1].origin,root));
close(parseFloat(bar.__name.style.position),26,'logical width APIs are not divided by viewport scale again');
delete bar.__name.layoutWidthOverride;delete bar.__caption.layoutWidthOverride;
root.actualuiscale_x = 0.75; root.actualuiscale_y = 0.5;
root.windowOffset = { x: 90, y: 45 }; tick();
assert.equal(bar.style.position, '626.00px 650.00px 0px', 'caption supports unequal scales and a shifted container');
anchor = config.SurvivalWorldHealthBarAnchor.Project(1, entities[1].origin, root);
assert.equal(anchor.left, 649); assert.equal(anchor.top, 684);
assert.equal(anchor.scale_x, 0.75); assert.equal(anchor.scale_y, 0.5);
assert.equal(anchor.screen_left, 576.75); assert.equal(anchor.screen_top, 387);
assertPlacement(bar, anchor);
let captionBounds;
let occludingRect = { x: 639, y: 380, width: 1, height: 1 };
config.SurvivalWorldOverlayVisibility = {
    Capture: () => ({ rects: [occludingRect] }),
    Overlaps: (capture, x, y, width, height) => {
        captionBounds = { x, y, width, height };
        return capture.rects.some(r => x < r.x + r.width && x + width > r.x
            && y < r.y + r.height && y + height > r.y);
    }
};
tick();
assert.deepEqual(captionBounds, { x: 559.5, y: 370, width: 81, height: 24.75 },
    'occlusion uses the full name, stars, left rarity image and health-bar region');
assert.equal(bar.style.visibility, 'collapse', 'a HUD overlap beyond the health bar still hides the full name caption');
occludingRect = { x: 600, y: 371, width: 1, height: 1 }; tick();
assert.equal(bar.style.visibility, 'collapse', 'occlusion covers the upper star row too');
occludingRect = { x: 562, y: 394, width: 1, height: 1 }; tick();
assert.equal(bar.style.visibility, 'collapse', 'occlusion includes the rarity image below the health-bar lower edge');
occludingRect = { x: 660, y: 370, width: 1, height: 1 }; tick();
assert.equal(bar.style.visibility, 'visible', 'moving a blocker outside the caption restores it');
delete config.SurvivalWorldOverlayVisibility;
root.actualuiscale_x = root.actualuiscale_y = 1;
root.windowOffset = { x: 0, y: 0 }; tick();
entities[1].alive = false; tick(); assert.equal(bar.style.visibility, 'collapse');
update('unit_1', { removed: 1, session: 'one' }); assert.equal(bars().length, 0);
entities[1].alive = true;
update('unit_1', { ...firstState, rarity: 'R', stars: 3, red_stars: 0 }); tick();
assert.equal(bars().length, 1);
update('_session', { id: 'two' }); tick(); assert.equal(bars().length, 0, 'old session records stay hidden');
update('unit_1', { ...firstState, display_name: '终极之塔', rarity: 'UR', stars: 1, session: 'two' }); tick();
assert(bars()[0].classes.has('RankUR'));
assert.equal(declaredNameColor('UR'), expectedNameColors.UR, 'UR keeps the agreed gold name declaration');
assert.equal(bars()[0].__ultimate.text, 'UR');
assert.equal(bars()[0].__ultimate.style.visibility, 'visible');
assert.equal(bars()[0].__letter.image, '', 'UR clears the prior texture and uses its native label');
assert.equal(bars()[0].__name.text, '终极之塔'); assertNoLevelBadge(bars()[0]);
update('unit_1', { ...firstState, display_name: '神秘之塔', rarity: 'R', stars: 1, session: 'two' }); tick();
assert.equal(bars()[0].__ultimate.style.visibility, 'collapse');
assert.equal(bars()[0].__letter.image, 's2r://panorama/images/custom_game/survival_tower_rank/rareicon_r_png.vtex',
    'leaving UR restores the rarity texture');
assert.equal(bars()[0].__name.text, '神秘之塔');
update('unit_1', { ...firstState, display_name: '终极之塔', rarity: 'UR', stars: 1, session: 'two' }); tick();
assert.equal(config.SurvivalTowerRanks.DebugSnapshot().units[0].ultimate_label.text, 'UR');
assert.equal(bars()[0].__letter.image, '');
vm.runInNewContext(source, sandbox); tick();
assert.equal(listeners.size, 1, 'hot reload has only one listener');
assert.equal(debugListeners.size, 1, 'hot reload has only one read-only diagnostic listener');
assert.equal(tasks.size, 1, 'hot reload has only one animation loop');
assert.equal(bars().length, 1);
assert.equal(bars()[0].__name.text, '终极之塔'); assertNoLevelBadge(bars()[0]);
assert.equal(bars()[0].__letter.type, 'Image'); assert.equal(bars()[0].__letter.image, '');
[...debugListeners.values()][0]();
assert(messages[0].startsWith('[TowerRankDebug] '));
assert.equal(JSON.parse(messages[0].slice('[TowerRankDebug] '.length)).state_count, 1);
delete entities[1]; tick(); assert.equal(bars().length, 0);
config.SurvivalTowerRanks.Stop(); assert.equal(tasks.size, 0); assert.equal(listeners.size, 0);
assert.equal(debugListeners.size, 0);
console.log('TOWER_RANK_UI_SIMULATION_PASS: measured name centering, bounded layout retry, stale/zero widths, capped long text, no stable width reads, 18px bold text, rarity colors, stars/health anchors, screen/occlusion bounds, construction, native images, scale, lifecycle, hot reload; font pixels not validated');
