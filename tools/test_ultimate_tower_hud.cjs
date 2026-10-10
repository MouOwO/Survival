'use strict';
// Exercise the real resolver/layout on a full scaled HUD with duplicate rows.
const assert = require('node:assert/strict'), fs = require('node:fs'), vm = require('node:vm');
const base = 'panorama/src/scripts/custom_game/';
const before = 'output/ultimate_tower_correction_20261009/before/' + base;
let optionalProofs = 0;
const config = fs.readFileSync('scripts/vscripts/config/generated/tower_fusion_runtime.lua', 'utf8');
const names = ['passive_slot_ability_ids', 'utility_ability_ids'].flatMap(key =>
    [...config.match(new RegExp(key + '\\s*=\\s*\\{([^}]*)\\}'))[1].matchAll(/"([^"]+)"/g)].map(m => m[1]));
assert.equal(names.length, 7);
function fn(source, name) {
    const start = source.indexOf('    function ' + name + '(');
    if (start < 0) return '';
    const end = source.indexOf('\n    function ', start + 1);
    return source.slice(start, end < 0 ? source.length : end);
}
function harness(source) {
    const writes = [], queries = [];
    class Panel {
        constructor(id, parent = null) {
            this.id = id; this.parent = null; this.children = []; this.alive = true; this.visible = true;
            this.values = {}; this.style = new Proxy(this.values, {
                set: (values, key, value) => { writes.push({panel: this, key, value}); values[key] = String(value); return true; }
            });
            this.SetParent(parent);
        }
        IsValid() { return this.alive; } GetParent() { return this.parent; }
        GetChildCount() { return this.children.length; } GetChild(index) { return this.children[index]; }
        BHasClass() { return false; }
        SetParent(parent) {
            if (this.parent) this.parent.children = this.parent.children.filter(child => child !== this);
            this.parent = parent; if (parent) parent.children.push(this);
        }
        FindChildTraverse(id) {
            queries.push(this.id + ':' + id);
            for (const child of this.children) {
                if (child.id === id) return child;
                const found = child.FindChildTraverse(id); if (found) return found;
            }
            return null;
        }
        windowBounds() {
            const parent = this.parent ? this.parent.windowBounds() : {x: 0, y: 0, scale: 1};
            const xy = String(this.style.position || '0px 0px 0px').split(/\s+/).map(parseFloat);
            let flow = 0;
            if (this.parent && this.parent.style.flowChildren === 'right') {
                for (const child of this.parent.children) {
                    if (child === this) break;
                    if (child.style.visibility !== 'collapse') flow += parseFloat(child.style.width || 0) + parseFloat(child.style.marginRight || 0);
                }
            }
            const transform = /scale3d\(([^,]+)/.exec(this.style.transform || '');
            return {x: parent.x + ((xy[0] || 0) + flow) * parent.scale,
                y: parent.y + (xy[1] || 0) * parent.scale,
                scale: parent.scale * (transform ? Number(transform[1]) : 1)};
        }
    }
    const root = new Panel('Hud'), query = new Panel('QueryUnit', root);
    const queryBranch = new Panel('AbilitiesAndStatBranch', query), queryList = new Panel('abilities', queryBranch);
    const lower = new Panel('lower_hud', root), outer = new Panel('center_with_stats', lower);
    const block = new Panel('center_block', outer), portrait = new Panel('PortraitGroup', block);
    new Panel('PortraitContainer', portrait); new Panel('portraitHUD', portrait);
    const inventory = new Panel('inventory', block);
    const map = new Panel('minimap_container', root), mapBlock = new Panel('minimap_block', map);
    new Panel('minimap', mapBlock);
    const ctx = new Panel('SurvivalHUDRoot', root), background = new Panel('background', ctx);
    function row(wrapperCount = 1, slotCount = 7) {
        const branch = new Panel('AbilitiesAndStatBranch', block);
        let parent = branch; const wrappers = [];
        for (let i = 0; i < wrapperCount; i++) { parent = new Panel('', parent); wrappers.push(parent); }
        const list = new Panel('abilities', parent), icons = [];
        for (let i = 0; i < slotCount; i++) {
            const slot = new Panel('Ability' + i, list), wrap = new Panel('ButtonAndLevel', slot);
            const well = new Panel('ButtonWell', wrap), button = new Panel('AbilityButton', well);
            icons.push(new Panel('AbilityImage', button)); new Panel('HotkeyContainer', button);
        }
        return {branch, wrappers, list, icons};
    }
    let current = row();
    const g = {x: 320, y: 600, width: 1700, height: 330, heroWidth: 453,
        centerWidth: 860, inventoryX: 1333, portraitSize: 264, minimapSize: 220, scale: 0.5};
    const env = {root, ctx, background, generation: 1, natives: {}, missing: [], geometry: g,
        cfg: {}, assets: {key_plate: {file: 'key.png'}}, currentEntries: [], skillPanels: [],
        selectedUnit: () => env.unit, unit: 100, Date: {now: () => 1000}, layoutMinimap() {}};
    ctx.actualuiscale_x = 1; ctx.actualuiscale_y = 1;
    env.cfg.HandoffCombat = {NativeEntries: () => env.currentEntries, ApplyRuntime() {}, IsCompleted: () => false};
    vm.createContext(env);
    vm.runInContext(source.slice(source.indexOf('    var scopes ='), source.indexOf('    var stats =')), env);
    vm.runInContext(source.slice(source.indexOf('    function valid('), source.indexOf('    function create(')), env);
    for (const name of ['fitNativeSkills', 'canvas', 'child', 'sameGeometryValue', 'styleAbilityLevelPips', 'square', 'nativeLayout']) {
        const code = fn(source, name); if (code) vm.runInContext(code, env);
    }
    function select(selectedNames, unit = 100) {
        env.unit = unit; env.currentEntries = selectedNames.map((name, slot) => ({name, slot, ability: unit * 100 + slot}));
        return env.nativeLayout(g);
    }
    return {env, root, query, queryBranch, queryList, lower, block, inventory, g, Panel, writes, queries, row, select,
        reset() { writes.length = 0; queries.length = 0; }, get current() { return current; },
        replace(wrapperCount = 1, slotCount = 7) { current.branch.SetParent(null); current = row(wrapperCount, slotCount); return current; }};
}
for (const file of ['topnav_remaining_5d5c1152eb.js', 'handoff_hud.js']) {
    const source = fs.readFileSync(base + file, 'utf8');
    assert(!source.includes('function fitNativeAbilityRow'), 'no recurring ancestor repair');
    const h = harness(source);
    assert.equal(h.root.FindChildTraverse('abilities'), h.queryList, 'query duplicate precedes real lower_hud');
    for (const [selectedNames, unit] of [
        [['ability_upgrade_tower', 'ability_upgrade_tower_max', 'ability_building_blink', 'ability_destroy_arrow_tower'], 1],
        [['ability_build_wall', 'ability_build_main_city', 'ability_build_arrow_tower', 'ability_build_research_lab', 'ability_build_hero_altar', 'ability_survival_builder_blink', 'ability_survival_rogue_reward'], 2],
        [names, 3]
    ]) {
        h.reset(); assert.equal(h.select(selectedNames, unit), true);
        assert.equal(h.env.native('abilities'), h.current.list, 'scoped resolver avoids query duplicate');
        assert.equal(h.env.skillPanels.length, selectedNames.length);
        assert.equal(h.lower.style.transform, 'scale3d(0.5,0.5,1)', 'existing lower_hud scale survives unit switches');
        assert(!h.writes.some(w => w.panel === h.root || w.panel === h.query || w.panel === h.queryBranch));
        assert(!h.writes.some(w => w.panel === h.current.branch && w.key === 'transform'), 'branch transform remains engine owned');
        for (let i = 0; i < selectedNames.length; i++) {
            const bounds = h.current.icons[i].windowBounds();
            assert.equal(bounds.x, h.g.x + 0.5 * (h.g.heroWidth + 16 + i * 120));
            assert.equal(bounds.y, h.g.y + 0.5 * 67);
        }
    }
    h.reset(); for (let i = 0; i < 20; i++) assert.equal(h.env.native('abilities'), h.current.list);
    assert.equal(h.queries.length, 0, 'stable cache checks parent ownership without repeated subtree search');
    const old = h.current; h.replace();
    assert(old.branch.IsValid() && old.list.IsValid());
    h.reset(); assert.equal(h.select(names), true);
    assert.equal(h.env.native('abilities'), h.current.list, 'live detached scope and row are reacquired');
    assert(!h.writes.some(w => w.panel === old.branch || w.panel === old.list));
    h.current.list.SetParent(h.queryBranch);
    const replacement = new h.Panel('abilities', h.current.wrappers[0]);
    assert.equal(h.env.native('abilities'), replacement, 'live cached row moved into a different scope is discarded');

    // Layout must defend itself too, even if an external resolver supplies stale
    // handles. No canvas write is allowed until the complete chain is proved.
    for (const kind of ['different_tree', 'outer_hud', 'unclosed', 'cycle', 'too_deep']) {
        const x = harness(source); assert.equal(x.select(names), true);
        let list;
        if (kind === 'different_tree') list = x.queryList;
        if (kind === 'outer_hud') list = new x.Panel('abilities', x.lower);
        if (kind === 'unclosed') list = new x.Panel('abilities', new x.Panel('detached'));
        if (kind === 'cycle') { const wrapper = new x.Panel('cycle'); list = new x.Panel('abilities', wrapper); wrapper.parent = wrapper; }
        if (kind === 'too_deep') { let parent = x.current.branch; for (let i = 0; i < 16; i++) parent = new x.Panel('', parent); list = new x.Panel('abilities', parent); }
        const native = x.env.native; x.env.native = id => id === 'abilities' ? list : native(id);
        const rootValues = {...x.root.values}, lowerValues = {...x.lower.values};
        x.reset(); assert.equal(x.env.nativeLayout(x.g), false, kind);
        assert.equal(x.writes.length, 0, kind + ': zero writes on unproven ancestry');
        assert.deepEqual(x.root.values, rootValues); assert.deepEqual(x.lower.values, lowerValues);
    }
    const boundary = harness(source); boundary.replace(15);
    assert.equal(boundary.select(names), true, 'fifteen wrappers ending at branch are within the bound');
    let deep = boundary.root; for (let i = 0; i < 33; i++) deep = new boundary.Panel('', deep);
    assert.equal(boundary.env.nativeWithin(deep, boundary.root), false, 'native cache ownership traversal is also bounded');

    // Optional local evidence only. A clean checkout has no ignored output;
    // every current-source behavior assertion above remains mandatory there.
    if (fs.existsSync(before + file)) {
        const legacy = harness(fs.readFileSync(before + file, 'utf8'));
        assert.equal(legacy.select(names), true);
        const oldList = legacy.current.list; legacy.replace();
        assert.equal(legacy.env.native('abilities'), oldList, 'old resolver retains valid detached row');
        const stray = new legacy.Panel('abilities', legacy.lower), oldNative = legacy.env.native;
        legacy.env.native = id => id === 'abilities' ? stray : oldNative(id);
        legacy.reset(); legacy.env.nativeLayout(legacy.g);
        assert(legacy.writes.some(w => w.panel === legacy.root && w.key === 'height' && w.value === '116px'));
        assert.equal(legacy.lower.style.transform, 'none', 'old unbounded ancestor writes erase real outer HUD scale');
        optionalProofs++;
    }
    if (file === 'topnav_remaining_5d5c1152eb.js') {
        const diagnostic = harness(source), logs = [];
        diagnostic.env.cfg.HandoffGeneration = 1;
        diagnostic.env.cfg.SurvivalMainHUD = {Inspect: () => ({unit: 100})};
        diagnostic.env.$ = {Msg: line => logs.push(line)};
        const start = source.indexOf('        function inspectNativeTree()');
        const end = source.indexOf('        Game.AddCommand(windowReview', start);
        assert(start >= 0 && end > start);
        vm.runInContext(source.slice(start, end), diagnostic.env);
        // Real failure: thousands of TopBarTPIcon AbilityImages exhaust a root
        // DFS before lower_hud. Current scoped inspection must never visit them.
        for (let i = 0; i < 4500; i++) new diagnostic.Panel('AbilityImage', new diagnostic.Panel('TopBarTPIcon', diagnostic.query));
        diagnostic.env.native('abilities');
        const stale = diagnostic.current; diagnostic.replace();
        const cacheBefore = {...diagnostic.env.natives};
        diagnostic.reset(); diagnostic.env.inspectNativeTree();
        const details = logs.filter(line => line.startsWith('[HUD_NATIVE_NODE]')).map(line => JSON.parse(line.slice('[HUD_NATIVE_NODE] '.length)));
        const header = JSON.parse(logs[0].slice('[HUD_NATIVE_INSPECT] '.length));
        assert.equal(header.mode, 'scoped_lower_hud');
        assert.equal(header.slots, 7); assert(header.visited < 100, 'visits only the current ability subtree');
        assert.equal(details.filter(row => row.id === 'abilities').length, 2, 'reports current and cached stale row, not root query duplicate');
        assert(details.some(row => row.id === 'abilities' && row.currentAs.includes('abilities') && row.inCurrentAbilityRow));
        assert(details.some(row => row.id === 'abilities' && row.staleAs.includes('abilities') && !row.inCurrentAbilityRow));
        assert(details.some(row => row.id === 'lower_hud' && row.currentAs.includes('lower_hud')));
        assert(details.filter(row => row.id === 'AbilityImage').every(row => row.inCurrentAbilityRow), 'TopBarTPIcon images cannot crowd out current slots');
        assert(details.some(row => row.id === 'AbilityImage' && Array.isArray(row.chain)));
        assert.equal(diagnostic.writes.length, 0, 'manual diagnostic never mutates native geometry');
        assert.deepEqual(diagnostic.env.natives, cacheBefore, 'manual inspection must not repair or mutate the caches being diagnosed');
        assert.equal(diagnostic.env.natives.abilities, stale.list);
        const fixedInspect = diagnostic.env.inspectNativeTree;
        const oldFile = 'output/ultimate_tower_correction_20261009/before_scoped_native/' + base + file;
        if (fs.existsSync(oldFile)) {
            const oldSource = fs.readFileSync(oldFile, 'utf8');
            const oldStart = oldSource.indexOf('        function inspectNativeTree()');
            const oldEnd = oldSource.indexOf('        Game.AddCommand(windowReview', oldStart);
            vm.runInContext(oldSource.slice(oldStart, oldEnd), diagnostic.env);
            logs.length = 0; diagnostic.env.inspectNativeTree();
            assert(logs.some(line => line.includes('"visited":4096')), 'saved root-DFS diagnostic reproduces scan exhaustion');
            assert(!logs.some(line => line.includes('"id":"lower_hud"')), 'saved diagnostic misses the real HUD');
            diagnostic.env.inspectNativeTree = fixedInspect;
            optionalProofs++;
        }
        for (const slotCount of [8, 7]) {
            diagnostic.replace(1, slotCount);
            for (const slot of diagnostic.current.list.children) {
                slot.paneltype = 'DOTAAbilityPanel';
                const tooltip = new diagnostic.Panel('Tooltip', slot);
                for (let i = 0; i < 96; i++) new diagnostic.Panel('LevelPip' + i, tooltip);
                slot.children = [tooltip, ...slot.children.filter(child => child !== tooltip)];
            }
            logs.length = 0; diagnostic.reset(); diagnostic.env.inspectNativeTree();
            const result = JSON.parse(logs[0].slice('[HUD_NATIVE_INSPECT] '.length));
            const rows = logs.slice(1).map(line => JSON.parse(line.slice('[HUD_NATIVE_NODE] '.length)));
            assert.equal(result.slots, slotCount, 'ordinary eight slots and ultimate seven slots are all discovered');
            assert.equal(result.visited, slotCount + 1, 'button tooltip/pip internals never consume row-discovery budget');
            assert(rows.some(row => row.id === 'Ability' + (slotCount - 2) && row.role === 'current_slot'), 'penultimate D slot remains present');
            assert(rows.some(row => row.id === 'Ability' + (slotCount - 1) && row.role === 'current_slot'), 'last G slot remains present');
            assert.equal(rows.filter(row => row.role === 'current_slot_image').length, slotCount, 'every discovered slot includes its actual image');
            assert.equal(diagnostic.writes.length, 0);
            const scanFile = 'output/ultimate_tower_correction_20261009/before_slot_scan/' + base + file;
            if (slotCount === 8 && fs.existsSync(scanFile)) {
                const oldSource = fs.readFileSync(scanFile, 'utf8'), oldStart = oldSource.indexOf('        function inspectNativeTree()');
                vm.runInContext(oldSource.slice(oldStart, oldSource.indexOf('        Game.AddCommand(windowReview', oldStart)), diagnostic.env);
                logs.length = 0; diagnostic.env.inspectNativeTree();
                const oldResult = JSON.parse(logs[0].slice('[HUD_NATIVE_INSPECT] '.length));
                assert.equal(oldResult.visited, 512); assert(oldResult.slots < slotCount, 'saved deep scan loses trailing utility slots');
                diagnostic.env.inspectNativeTree = fixedInspect;
                optionalProofs++;
            }
        }
        stale.wrappers[0].parent = stale.wrappers[0];
        for (let i = 100; i < 200; i++) new diagnostic.Panel('Ability' + i, diagnostic.current.list);
        logs.length = 0; diagnostic.env.inspectNativeTree();
        assert(logs.length <= 65, 'summary plus at most 64 detail lines');
        assert(logs.some(line => line.includes('"truncated":true')));
        assert(logs.some(line => line.includes('"cycle"')), 'parent-cycle inspection terminates and reports it');
        diagnostic.env.cfg.HandoffGeneration = 2; logs.length = 0;
        diagnostic.env.inspectNativeTree(); assert.equal(logs.length, 0, 'obsolete HUD generation cannot inspect a live tree');
    }
}
const {setup} = require('./test_combat_stats_callbacks.cjs');
const entries = names.map((name, slot) => ({name, slot, ability: 101 + slot}));
const t = setup({portrait: true, abilities: {GetBehavior: id => id < 106 ? 2 : 4, GetAbilityName: id => names[id - 101]}});
const ordered = t.api.orderVisibleAbilities(entries.map(entry => ({...entry})));
assert.deepEqual(Array.from(ordered, entry => t.api.hotkeyForAbilityEntry(entry, '')), ['', '', '', '', '', 'D', 'G']);
console.log('ULTIMATE_TOWER_HUD_PASS: scaled lower_hud; duplicate query row; tower/builder/ultimate switches; valid detached caches; bounded closed ancestor proof; invalid chains make zero writes; ordinary8/ultimate7 complete despite dense slot internals; passive/D/G keys; optional old-source proofs=' + optionalProofs);
