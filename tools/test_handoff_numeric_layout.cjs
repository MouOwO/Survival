'use strict';

// Execute production layout/nativeLayout/refresh/reveal against Panorama-like
// style setters. In particular, Panorama rejects exponent notation in pixels.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');
const scripts = path.join(root, 'panorama/src/scripts/custom_game');
const loadedHud = 'topnav_remaining_5d5c1152eb.js';
const xml = fs.readFileSync(path.join(root, 'panorama/src/layout/custom_game/survival_hud.xml'), 'utf8');
assert(xml.includes('/scripts/custom_game/' + loadedHud), 'test must include the HUD actually loaded by XML');

function between(source, first, last) {
    const begin = source.indexOf(first);
    assert(begin >= 0, 'missing production seam: ' + first);
    const end = source.indexOf(last, begin + first.length);
    assert(end >= 0, 'missing production seam end: ' + last);
    return source.slice(begin, end);
}

const decimal = '-?(?:0|[1-9]\\d*)(?:\\.\\d+)?';
const pixel = new RegExp('^' + decimal + 'px$');
const position = new RegExp('^' + decimal + 'px ' + decimal + 'px ' + decimal + 'px$');
const transform = new RegExp('^scale3d\\(' + decimal + ',' + decimal + ',' + decimal + '\\)$');
const clip = new RegExp('^rect\\(' + decimal + '%, ' + decimal + '%, ' + decimal + '%, ' + decimal + '%\\)$');
function panel(id, parent = null) {
    const classes = new Set();
    const style = new Proxy({}, {
        set(target, name, value) {
            if (name === 'position' && !position.test(String(value))) {
                throw new Error('Invalid value for property position: ' + value);
            }
            if (/^(?:width|height|minWidth|minHeight|maxWidth|maxHeight)$/.test(name)
                && value!=='fit-children' && !/^\d+(?:\.\d+)?%$/.test(String(value)) && !pixel.test(String(value))) {
                throw new Error('Invalid pixel dimension ' + name + ': ' + value);
            }
            if (name === 'transform' && value !== 'none' && !transform.test(String(value))) {
                throw new Error('Invalid numeric transform: ' + value);
            }
            if (name === 'clip' && !clip.test(String(value))) {
                throw new Error('Invalid numeric clip: ' + value);
            }
            target[name] = value;
            return true;
        },
    });
    return {
        id, style, classes, parent, visible: true,alive:true,
        IsValid() { return this.alive; },
        GetParent() { return this.parent; },
        SetParent(next) { this.parent = next; },
        FindChildTraverse() { return null; },
        GetChildCount() { return 0; },
        BHasClass(value) { return classes.has(value); },
        AddClass(value) { classes.add(value); },
        RemoveClass(value) { classes.delete(value); },
        SetImage(value) { this.image=value; },
        GetPositionWithinWindow() { return {x: 0, y: 0}; },
    };
}

function harness(filename, oldPlace = false) {
    const source = fs.readFileSync(path.join(scripts, filename), 'utf8');
    const nativePanels = Object.fromEntries([
        'lower_hud', 'center_with_stats', 'center_block', 'PortraitGroup',
        'PortraitContainer', 'portraitHUD', 'portraitHUDOverlay',
        'AbilitiesAndStatBranch', 'abilities', 'inventory', 'StatBranch',
        'minimap', 'minimap_container', 'minimap_block',
        'inventory_composition_layer_container', 'buffs', 'debuffs',
    ].map(id => [id, panel(id)]));
    nativePanels.abilities.parent = nativePanels.AbilitiesAndStatBranch;
    const nodes = {};
    const navKeys=['return','treasure','archive','lottery','benefit','shop','survival_shop','vip'];
    for(const key of navKeys)for(const prefix of ['HandoffNavGlow_','HandoffNavIcon_','HandoffNavCaptionHost_','HandoffNavCaption_','HandoffNavUnderline_'])nodes[prefix+key]=panel(prefix+key);
    for(const id of ['HandoffName','HandoffNameBounds','HandoffBuildingTitle','HandoffBuildingTitleBounds','HandoffBuildingLevel','HandoffBuildingSummary','HandoffBuildingBonus','HandoffBuildingHealthBonus','HandoffBuildingPercent','HandoffBuildingHealthPercent'])nodes[id]=panel(id);
    for (const type of ['hp', 'mp']) {
        for (const suffix of ['track', 'fill', 'value', 'valueBounds']) {
            const id = 'Handoff_' + type + '_' + suffix;
            nodes[id] = panel(id);
        }
    }
    const ctx = panel('context');
    Object.assign(ctx, {actuallayoutwidth: 1679, actuallayoutheight: 1080, actualuiscale_x: 1, actualuiscale_y: 1});
    ctx.AddClass('HandoffBoot');
    const fills = {
        SurvivalHeroHealthFill: {style: {width: '1e-13%'}},
        SurvivalHeroManaFill: {style: {width: '0.000001%'}},
    };
    ctx.FindChildTraverse = id => fills[id] || null;
    const host = panel('host');
    host.style.opacity = '0';
    nativePanels.lower_hud.style.opacity = '0';
    const bottom = panel('bottom');
    const warnings = [], messages = [];
    let fitCalls = 0, mirrorCalls = 0,navCalls=0,nativeCalls=0;
    const cfg = {
        HandoffGeneration: 1,
        HandoffGeometry: require(path.join(scripts,
            filename === loadedHud ? 'geometry_remaining_5d5c1152eb.js' : 'handoff_geometry.js')),
        SurvivalProductionHUD: {Refresh() { return 22.125; }},
    };
    const context = vm.createContext({
        ctx, host, cfg, generation: 1, nodes,
        Entities:{GetUnitName:()=> 'npc_dota_hero_axe',IsBuilding:()=>false,IsHero:()=>true},
        root: panel('root'), top: panel('top'), topBackdrop: panel('topBackdrop'),
        topStatus:panel('topStatus'),nav:navKeys.map(key=>[key]),
        fxButton:panel('fxButton'),fxHalo:panel('fxHalo'),fxIcon:panel('fxIcon'),fxCaptionHost:panel('fxCaptionHost'),fxText:panel('fxText'),
        enemyCounter: panel('enemyCounter'), bottom, background: panel('background', bottom),
        center: panel('center'), inventory: panel('inventory-decoration'),
        natives: nativePanels, slotFrames: Array.from({length: 6}, (_, i) => panel('slot-frame-' + i)),
        ready: false, sequence: 1, geometry: null, lastSignature: '', missing: [],
        presented: false, stableFrames: 0, bootSignature: '',
        currentEntries: [{ability: 101}, {ability: 102}, {ability: 103}],
        native: id => nativePanels[id] || null,
        selectedForTest:7,selectedUnit: () => 7, abilityCount: () => 3,
        fitNativeSkills: () => { fitCalls++; },
        refreshInventoryPresentation() {}, square() {}, nine() {},layoutStats(){},
        stats: [], topButtons: Object.fromEntries(navKeys.map(key=>[key,panel(key)])), text() {}, available: () => false,syncActiveNav(){},
        buildingInlineIds:['HandoffBuildingSummary','HandoffBuildingBonus','HandoffBuildingPercent','HandoffBuildingHealthPercent'],buildingStatRow:panel('buildingStatRow'),slices:{},assets:{hp_fill:{file:'hp.png'}},
        __mirrorCalled: () => { mirrorCalls++; }, mirrorKeys() {},
        __navCalled:()=>{navCalls++;},__nativeCalled:()=>{nativeCalls++;},
        art(parent, id) { return (nodes[id] = panel(id, parent)); },
        centered() {},
        $: {Warning: message => warnings.push(String(message)), Msg: (...args) => messages.push(args.join(' '))},
    });
    context.selectedUnit=()=>context.selectedForTest;
    context.abilityCount=()=>context.currentEntries.length;
    context.natives={...nativePanels};
    context.native=id=>(context.natives[id]=nativePanels[id]||null);
    const helpers = between(source, '    function style(', '    function create(');
    let seam = [
        between(source, '    function valid(', '    function native('),
        source.includes('    function nativeAbilityWrappers(')?between(source,'    function nativeAbilityWrappers(',source.includes('    function findCached(')?'    function findCached(':'    function style('):'',
        helpers,
        source.includes('    function findCached(')?between(source,'    function findCached(','    function style('):'function findCached(p,id){return p.FindChildTraverse(id);}',
        source.includes('    function navBounds(')?between(source,'    function navBounds(','    // Navigation icons'): '',
        between(source, '    function canvas(', '    // Called synchronously'),
        between(source, '    function child(', '    function square('),
        source.includes('    function layoutMinimap(')?between(source, '    function layoutMinimap(', '    function nativeLayout('):'',
        between(source, '    function nativeLayout(', '    function mirror('),
        between(source, '    function mirror(', '    function compact('),
        between(source, '    function refreshNow(', '    function tick('),
        'var productionMirror=mirror; mirror=function(){__mirrorCalled(); return productionMirror();};',
        'var productionNativeLayout=nativeLayout;nativeLayout=function(g){__nativeCalled();return productionNativeLayout(g);};',
        'if(typeof layoutNavigation==="function"){var productionNav=layoutNavigation;layoutNavigation=function(a,b){__navCalled();return productionNav(a,b);};}',
    ].join('\n');
    if (oldPlace) {
        seam += '\nplace = function(p,x,y,w,h) {style(p,{position:x+"px "+y+"px 0px",width:w+"px",height:h+"px"});};';
    }
    vm.runInContext(seam, context, {filename});
    return {
        context, ctx, host, nativePanels, warnings, messages, fills,
        refresh: () => vm.runInContext('refreshNow()', context),
        place: (...args) => context.place(...args),
        fitCalls: () => fitCalls, mirrorCalls: () => mirrorCalls,
        navCalls:()=>navCalls,nativeCalls:()=>nativeCalls,
    };
}

for (const filename of [loadedHud, 'handoff_hud.js']) {
    // This is the exact floating point residue from the reported top position.
    const residue = (1679 - 1672 * (1679 / 1672)) / 2;
    assert.equal(residue, 1.1368683772161603e-13);
    const old = harness(filename, true);
    for (let i = 0; i < 6; i++) old.refresh();
    assert.equal(old.warnings.length, 6, filename + ': original bug must reproduce on every refresh');
    assert(old.warnings.every(message => message.includes('1.1368683772161603e-13px')));
    assert.equal(old.context.presented, false);
    assert.equal(old.host.style.opacity, '0');
    assert(old.ctx.classes.has('HandoffBoot'));
    assert.equal(old.mirrorCalls(), 0, 'invalid top position aborts refresh before reveal');
    assert.equal(old.fitCalls(), 0, 'invalid top position also aborts native HUD layout');

    const fixed = harness(filename);
    for (let i = 0; i < 3; i++) {
        fixed.refresh();
        assert.equal(fixed.context.presented, false, 'normal stable-frame gate must remain in effect');
    }
    fixed.refresh();
    assert.deepEqual(fixed.warnings,[],filename+': refresh must complete without hidden native errors');
    assert.equal(fixed.context.presented, true, filename + ': refresh must reach the existing reveal gate');
    assert.equal(fixed.context.top.style.position, filename===loadedHud?'8px 6px 0px':'0px 0px 0px');
    assert.equal(fixed.host.style.opacity, '1');
    assert.equal(fixed.nativePanels.lower_hud.style.opacity, '1');
    assert(!fixed.ctx.classes.has('HandoffBoot'));
    assert.equal(fixed.context.bottom.visible, true);
    assert.equal(fixed.context.nodes.Handoff_hp_fill.style.clip, 'rect(0%, 0%, 100%, 0%)');
    assert.equal(fixed.context.nodes.Handoff_mp_fill.style.clip, 'rect(0%, 0.000001%, 100%, 0%)');
    assert(fixed.fitCalls() >= 4, 'real nativeLayout and recurring refresh must both complete');
    assert.equal(fixed.warnings.length, 0);
    if(filename===loadedHud){
        const navBefore=fixed.navCalls(),nativeBefore=fixed.nativeCalls();
        for(let i=0;i<20;i++)fixed.refresh();
        assert.equal(fixed.navCalls(),navBefore,'stable viewport does not repeat navigation geometry');
        assert.equal(fixed.nativeCalls(),nativeBefore,'stable selected ability handles keep bottom geometry');
        fixed.context.selectedForTest=19;fixed.refresh();
        assert.equal(fixed.nativeCalls(),nativeBefore+1,'a real selection reflows immediately');
        fixed.context.currentEntries=[{ability:501},{ability:502},{ability:503}];fixed.refresh();
        assert.equal(fixed.nativeCalls(),nativeBefore+2,'same count with different ability handles reflows');
        fixed.context.currentEntries.push({ability:504});fixed.refresh();
        assert.equal(fixed.nativeCalls(),nativeBefore+3,'learning an ability reflows immediately');
        fixed.context.currentEntries.pop();fixed.refresh();
        assert.equal(fixed.nativeCalls(),nativeBefore+4,'removing an ability reflows immediately');
        const oldAbilities=fixed.nativePanels.abilities;oldAbilities.alive=false;
        fixed.nativePanels.abilities=panel('abilities',fixed.nativePanels.AbilitiesAndStatBranch);fixed.refresh();
        assert.equal(fixed.nativeCalls(),nativeBefore+5,'native ability row rebuild reflows even with unchanged handles');
        assert.equal(fixed.navCalls(),navBefore,'selection, skill and native row changes do not affect viewport-only navigation');
        const logicalWidth=fixed.ctx.actuallayoutwidth;
        fixed.ctx.actuallayoutwidth*=2;fixed.ctx.actuallayoutheight*=2;fixed.ctx.actualuiscale_x=2;fixed.ctx.actualuiscale_y=2;fixed.refresh();
        assert.equal(fixed.navCalls(),navBefore+1,'physical pixel snapping updates even when logical viewport size stays the same');
        fixed.ctx.actuallayoutwidth=logicalWidth;fixed.ctx.actuallayoutheight/=2;fixed.ctx.actualuiscale_x=1;fixed.ctx.actualuiscale_y=1;fixed.refresh();
        assert.equal(fixed.warnings.length,0);
    }

    // Exercise the real layout after window/UI-scale changes, including the
    // zero-sized initial engine layout that uses the production fallbacks.
    for (const [width, height, sx, sy] of [
        [1920, 1080, 1, 1], [2560, 1440, 1.25, 1.25],
        [3840, 2160, 2, 2], [1365, 768, 0.85, 0.85],
        [1679, 1080, 1, 1], [0, 0, 0, 0],
    ]) {
        Object.assign(fixed.ctx, {actuallayoutwidth: width, actuallayoutheight: height, actualuiscale_x: sx, actualuiscale_y: sy});
        fixed.refresh();
        assert.equal(fixed.context.presented, true);
        assert.equal(fixed.host.style.opacity, '1');
        assert.equal(fixed.warnings.length, 0, 'resizing cannot restart the exception loop');
    }
    assert.equal(fixed.messages.filter(message => message.startsWith('[HANDOFF_PRESENTED]')).length, 1);
    for (const [value, expected] of [
        ['1e-13%', '0'], ['0.000001%', '0.000001'], ['33.3333333%', '33.333333'],
        ['-5%', '0'], ['999%', '100'], ['bad', '0'],
    ]) {
        fixed.fills.SurvivalHeroHealthFill.style.width = value;
        fixed.fills.SurvivalHeroManaFill.style.width = value;
        fixed.refresh();
        for (const type of ['hp', 'mp']) {
            assert.equal(fixed.context.nodes['Handoff_' + type + '_fill'].style.clip,
                'rect(0%, ' + expected + '%, 100%, 0%)');
        }
        assert.equal(fixed.warnings.length, 0, 'real mirror cannot abort reveal on a tiny percentage');
    }
    const scaled = panel('tiny-scale');
    fixed.context.canvas(scaled, {x: residue, y: -residue, width: 100, height: 100, scale: 1e-13});
    assert.equal(scaled.style.transform, 'scale3d(0,0,1)');
    fixed.context.canvas(scaled, {x: 0, y: 0, width: 100, height: 100, scale: 0.000001});
    assert.equal(scaled.style.transform, 'scale3d(0.000001,0.000001,1)');

    // Test the actual placement entry point rather than a copied formatter.
    const sample = panel('numeric-edge-cases');
    fixed.place(sample, -24.125, -86.5, 116.125, 0);
    assert.equal(sample.style.position, '-24.125px -86.5px 0px', 'intentional negative offsets must survive');
    assert.equal(sample.style.width, '116.125px');
    assert.equal(sample.style.height, '0px');
    if (filename === loadedHud) {
        assert.equal(sample.style.minWidth, sample.style.width);
        assert.equal(sample.style.minHeight, sample.style.height);
    }
    for (const tiny of [residue, -residue, -0, 1e-100, -1e-100]) {
        fixed.place(sample, tiny, tiny, tiny, tiny);
        assert.equal(sample.style.position, '0px 0px 0px');
        assert.equal(sample.style.width, '0px');
        assert.equal(sample.style.height, '0px');
    }
    for (const value of [NaN, Infinity, -Infinity, undefined, null, 'bad-number']) {
        fixed.place(sample, value, value, value, value);
        assert.equal(sample.style.position, '0px 0px 0px');
        assert.equal(sample.style.width, '0px');
        assert.equal(sample.style.height, '0px');
    }
    fixed.place(sample, 1e100, -1e100, 1e100, 1e100);
    assert.equal(sample.style.position, '10000000px -10000000px 0px');
    assert.equal(sample.style.width, '10000000px');
    assert.equal(sample.style.height, '10000000px');
}

console.log('HANDOFF_NUMERIC_LAYOUT_PASS: both HUD scripts reproduce old exponent failure; real layout/nativeLayout/refresh/mirror/reveal recover; resize, UI scale, tiny clips/scales, negative offsets, zero, nonfinite and extreme dimensions');
