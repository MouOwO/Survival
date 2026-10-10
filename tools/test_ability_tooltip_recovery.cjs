const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const sourcePath = process.env.SURVIVAL_TOOLTIP_TEST_SOURCE
    || path.join(__dirname, '../panorama/src/scripts/custom_game/ability_tooltip.js');
const source = fs.readFileSync(sourcePath, 'utf8');

// Run the real module. The injected hooks only observe work or expose state;
// selection, recovery, ownership checks, binding and hover code stay intact.
function instrumentSource() {
    let code = source;
    for (const name of ['bindOfficialAbilities', 'collectOfficialAbilityPanels']) {
        const pattern = new RegExp('(function ' + name + '\\([^)]*\\) \\{)');
        assert(pattern.test(code), 'Missing production function: ' + name);
        code = code.replace(pattern, '$1\n        __testHooks.work("' + name + '");');
    }
    const end = code.lastIndexOf('})();');
    assert(end >= 0, 'Expected module closure');
    return code.slice(0, end) + `
    __testHooks.inspect = function () {
        return {
            unit: Number(observedSelectedUnit),
            activeAbility: Number(activeAbilityIndex),
            pendingHover: !!pendingHoverRestore,
            bindings: officialBindings.map(function (binding) {
                return {
                    ability: Number(binding.abilityIndex),
                    slot: Number(binding.engineSlot),
                    x: Number(binding.x),
                    y: Number(binding.y),
                    proxy: binding.proxy
                };
            }),
            proxies: externalProxies.slice()
        };
    };
` + code.slice(end);
}

function createHarness(options = {}) {
    let time = 0;
    let serial = 0;
    let task = 'module';
    let selectedUnit = 827;
    let readyAt = options.readyAt || 0;
    let cursor = [0, 0];
    const queue = new Map();
    const logs = [];
    const work = [];
    const abilityReads = [];
    const executions = [];
    const eventListeners = new Map();
    const tableListeners = new Map();
    const tables = new Map();
    const units = new Map();
    const abilityData = new Map();
    const counters = { abilityReads: 0, unitMetadataReads: 0, treeQueries: 0, created: 0 };
    const hooks = { work(name) { work.push({ name, time, task, unit: selectedUnit }); } };

    function schedule(delay, callback) {
        const id = ++serial;
        queue.set(id, { id, at: time + Math.max(0, Number(delay) || 0), callback });
        return id;
    }
    function runUntil(until) {
        let callbacks = 0;
        while (true) {
            const next = [...queue.values()].sort((a, b) => a.at - b.at || a.id - b.id)[0];
            if (!next || next.at > until + 1e-9) break;
            assert(++callbacks < 5000, 'Unbounded callback scheduling');
            queue.delete(next.id);
            time = next.at;
            task = 'schedule:' + next.id;
            executions.push({ time, task });
            next.callback();
        }
        time = until;
        task = 'external:' + (++serial);
        const errors = logs.filter(line => line.includes('[SURVIVAL_TOOLTIP_ERROR]'));
        assert.deepEqual(errors, [], 'Production callbacks must not swallow errors');
    }

    class Panel {
        constructor(type, parent, id, rect = {}) {
            this.paneltype = type;
            this.id = id;
            this.parent = null;
            this.children = [];
            this.events = {};
            this.classes = new Set();
            this.style = {};
            this.valid = true;
            this.visible = true;
            this.actualuiscale_x = 1;
            this.actualuiscale_y = 1;
            this.rect = { x: 0, y: 0, width: 1920, height: 1080, ...rect };
            if (parent) this.SetParent(parent);
        }
        IsValid() { return this.valid; }
        get visible() { return this._visible; }
        set visible(value) { assert(this.valid, 'Underlying panel is deleted!'); this._visible=value; }
        RemoveAndDeleteChildren() {
            const invalidate = panel => { panel.valid=false; panel.children.forEach(invalidate); };
            this.children.forEach(invalidate); this.children=[];
        }
        GetParent() { return this.parent; }
        SetParent(parent) {
            if (this.parent) this.parent.children = this.parent.children.filter(child => child !== this);
            this.parent = parent;
            parent.children.push(this);
        }
        GetChildCount() { return this.children.length; }
        GetChild(index) { return this.children[index]; }
        FindChildTraverse(id) {
            counters.treeQueries++;
            const visit = panel => {
                for (const child of panel.children) {
                    if (child.id === id) return child;
                    const nested = visit(child);
                    if (nested) return nested;
                }
                return null;
            };
            return visit(this);
        }
        MoveChildAfter(child, after) {
            this.children = this.children.filter(item => item !== child);
            this.children.splice(this.children.indexOf(after) + 1, 0, child);
        }
        GetPositionWithinWindow() {
            const position = this.style.position;
            const parentPosition = this.parent ? this.parent.GetPositionWithinWindow() : { x: 0, y: 0 };
            const coordinates = position ? position.split(/\s+/).map(parseFloat) : [this.rect.x, this.rect.y];
            return { x: parentPosition.x + coordinates[0], y: parentPosition.y + coordinates[1] };
        }
        get actuallayoutwidth() { return this.dimension('width'); }
        get actuallayoutheight() { return this.dimension('height'); }
        dimension(axis) {
            const value = this.style[axis];
            if (!value) return this.rect[axis];
            if (String(value).endsWith('%')) {
                return (this.parent ? this.parent.dimension(axis) : this.rect[axis]) * parseFloat(value) / 100;
            }
            return parseFloat(value);
        }
        AddClass(name) { this.classes.add(name); }
        RemoveClass(name) { this.classes.delete(name); }
        BHasClass(name) { return this.classes.has(name); }
        SetHasClass(name, value) { if (value) this.AddClass(name); else this.RemoveClass(name); }
        SetPanelEvent(name, callback) { this.events[name] = callback; }
        SetImage(value) { this.image = value; }
        DeleteAsync() {
            this.valid = false;
            if (this.parent) this.parent.children = this.parent.children.filter(child => child !== this);
        }
    }

    const root = new Panel('Panel', null, 'Hud');
    const context = new Panel('Panel', root, 'SurvivalHud');
    const tooltip = new Panel('Panel', context, 'CustomAbilityTooltip', { width: 337, height: 200 });
    tooltip.AddClass('Hidden');
    for (const id of ['CustomAbilityFields', 'CustomAbilityIcon', 'CustomAbilityTitle',
        'CustomAbilityLevel', 'CustomAbilityDescription', 'CustomAbilityExtensionLabel',
        'CustomAbilityCostRow', 'CustomAbilityGoldCostBlock', 'CustomAbilityWoodCostBlock',
        'CustomAbilityGoldCost', 'CustomAbilityWoodCost', 'CustomAbilityType', 'CustomAbilityStatus']) {
        new Panel('Panel', tooltip, id);
    }
    const layer = new Panel('Panel', context, 'SurvivalManagedAbilityProxyLayer');
    new Panel('Panel', context, 'SurvivalAbilityTakeoverLayer');
    new Panel('Panel', context, 'SurvivalHeroAbilitySlots');
    const official = new Panel('Panel', root, 'abilities');
    function rebuildPanels(offset = 0) {
        function invalidate(panel) {
            panel.valid = false;
            panel.children.forEach(invalidate);
        }
        official.children.forEach(invalidate);
        official.children = [];
        for (let index = 0; index < (options.panelCount ?? 4); index++) {
            const panel = new Panel('Panel', official, 'Ability' + index, {
                x: 700 + offset + index * 70, y: 900, width: 64, height: 64
            });
            Object.defineProperty(panel, 'visible', { get() { return time >= readyAt; }, configurable: true });
            const anchor = new Panel('Button', panel, 'AbilityButton', { width: 64, height: 64 });
            new Panel('Image', anchor, 'AbilityImage', { width: 64, height: 64 });
        }
    }
    rebuildPanels();

    function setTable(name, key, value, notify = false) {
        tables.set(name + ':' + key, value);
        if (notify) {
            task = 'nettable:' + (++serial);
            for (const callback of tableListeners.get(name) || []) callback(name, String(key), value);
        }
    }
    function setUnit(unit, firstAbility) {
        const names = options.unitAbilityNames?.[unit] || options.abilityNames || ['ability_upgrade_city', 'ability_train_lumberjack',
            'ability_train_repairer', 'ability_train_advanced_repairer'];
        const list = names.map((name, index) => ({ id: firstAbility + index, name }));
        units.set(unit, list);
        setTable('survival_ability_runtime', 'unit:' + unit, { owner_entindex: unit, ability_count: list.length });
        for (const ability of list) {
            abilityData.set(ability.id, ability);
            setTable('survival_ability_runtime', ability.id, {
                owner_entindex: unit, ability_entindex: ability.id, available: 1, fields: options.fields || []
            });
            setTable('survival_ability_data', ability.name, { abilityid: ability.name });
        }
        return list;
    }
    setUnit(827, 828);
    setUnit(900, 901);
    if (options.hero) setTable('survival_hero_skills', 'player_0', {unit_entindex:827});
    if (options.runtimeIndexes) {
        units.get(827).forEach((ability, index) => {
            if (!options.runtimeIndexes.includes(index)) tables.delete('survival_ability_runtime:' + ability.id);
        });
    }
    if (options.noAbilities) {
        units.set(827, []);
        setTable('survival_ability_runtime', 'unit:827', { owner_entindex: 827, ability_count: 0 });
    }
    const config = {
        SurvivalInputLifecycleGeneration: 1,
        SurvivalSelectionResolver: {
            Resolve: () => selectedUnit,
            BuilderEntity: () => -1,
            Snapshot: () => ({ resolved: selectedUnit })
        },
        SurvivalUI: { Asset: value => value }
    };
    const dollar = selector => root.FindChildTraverse(selector.replace(/^#/, ''));
    Object.assign(dollar, {
        GetContextPanel: () => context,
        Schedule: schedule,
        CancelScheduled: id => queue.delete(id),
        Msg: (...parts) => logs.push(parts.join('')),
        Localize: value => value,
        DispatchEvent: () => {},
        CreatePanel: (type, parent, id) => { counters.created++; return new Panel(type, parent, id); }
    });
    const environment = {
        __testHooks: hooks,
        $: dollar,
        Date: class extends Date { static now() { return time * 1000; } },
        GameUI: { CustomUIConfig: () => config, GetCursorPosition: () => cursor },
        Game: { GetLocalPlayerID: () => 0, Time: () => time, GetGameTime: () => time },
        Players: { GetPlayerHeroEntityIndex: () => -1, GetSelectedEntities: () => [selectedUnit] },
        Entities: {
            GetAbility: (unit, slot) => {
                counters.abilityReads++;
                abilityReads.push({ task, unit, slot });
                return units.get(unit)?.[slot]?.id ?? -1;
            },
            IsValidEntity: unit => units.has(unit),
            GetUnitName: unit => units.has(unit) ? (options.unitNames?.[unit] || options.unitName
                || (options.native ? 'npc_dota_neutral_test' : 'building_city')) : '',
            GetAbilityCount: unit => units.get(unit)?.length || 0
        },
        Abilities: {
            GetAbilityName: id => abilityData.get(id)?.name || '',
            IsHidden: () => false,
            GetLevel: () => 1,
            GetBehavior: () => 0,
            ...options.abilities
        },
        CustomNetTables: {
            GetTableValue(name, key) {
                if (name === 'survival_ability_runtime' && String(key).startsWith('unit:')) counters.unitMetadataReads++;
                return tables.get(name + ':' + key) || null;
            },
            SubscribeNetTableListener(name, callback) {
                if (!tableListeners.has(name)) tableListeners.set(name, []);
                tableListeners.get(name).push(callback);
                return ++serial;
            }
        },
        GameEvents: {
            Subscribe(name, callback) {
                if (!eventListeners.has(name)) eventListeners.set(name, []);
                eventListeners.get(name).push(callback);
                return ++serial;
            }
        }
    };
    vm.runInNewContext(instrumentSource(), environment, { filename: sourcePath });
    return {
        config, counters, logs, work, abilityReads, executions, queue, tooltip, layer, setTable,
        inspect: () => hooks.inspect(),
        runUntil,
        now: () => time,
        setCursor: value => { cursor = value; },
        fieldContainer: () => tooltip.FindChildTraverse('CustomAbilityFields'),
        rebuildPanels,
        setReadyAt: value => { readyAt = value; },
        select(unit, event = 'dota_player_update_selected_unit') {
            selectedUnit = unit;
            this.emit(event);
        },
        emit(event = 'dota_player_update_selected_unit') {
            task = 'event:' + (++serial);
            for (const callback of eventListeners.get(event) || []) callback({ PlayerID: 0 });
        },
        publishRuntime(index, owner = selectedUnit) {
            const ability = units.get(owner)[index];
            setTable('survival_ability_runtime', ability.id, {
                owner_entindex: owner, ability_entindex: ability.id, available: 1, fields: []
            }, true);
        },
        replaceFirstAbility(id, name = 'ability_upgrade_city') {
            const list = units.get(selectedUnit);
            const old = list[0];
            list[0] = { id, name };
            abilityData.set(id, list[0]);
            setTable('survival_ability_runtime', old.id, { removed: 1, owner_entindex: selectedUnit });
            setTable('survival_ability_runtime', id, {
                owner_entindex: selectedUnit, ability_entindex: id, available: 1, fields: []
            }, true);
        }
    };
}

function count(harness, name) { return harness.work.filter(item => item.name === name).length; }
function assertBound(harness, firstAbility) {
    const state = harness.inspect();
    assert.deepEqual(Array.from(state.bindings, binding => binding.ability),
        [firstAbility, firstAbility + 1, firstAbility + 2, firstAbility + 3]);
    for (const binding of state.bindings) {
        assert(binding.proxy.IsValid());
        assert.equal(binding.proxy.hittest, true);
        assert.equal(binding.proxy.style.visibility, 'visible');
    }
}
// An identical deterministic workload can also measure a saved pre-change file.
// These are call counts in the mock engine, not a real-game FPS benchmark.
if (process.argv.includes('--measure')) {
    const h = createHarness();
    h.runUntil(11); // Exclude startup recovery; measure an actual unit switch.
    h.work.length = 0;
    h.abilityReads.length = 0;
    h.executions.length = 0;
    h.logs.length = 0;
    Object.keys(h.counters).forEach(key => { h.counters[key] = 0; });
    h.select(900);
    h.runUntil(22);
    assertBound(h, 901);
    console.log(JSON.stringify({
        source: sourcePath, simulationSeconds: 11,
        fullBinds: count(h, 'bindOfficialAbilities'),
        panelScans: count(h, 'collectOfficialAbilityPanels'),
        abilityReads: h.counters.abilityReads,
        unitMetadataReads: h.counters.unitMetadataReads,
        scheduledCallbacks: h.executions.length,
        logLines: h.logs.length
    }, null, 2));
    process.exit(0);
}

let failures = 0;
function test(name, callback) {
    try {
        callback();
        console.log('PASS ' + name);
    } catch (error) {
        failures++;
        console.error('FAIL ' + name + '\n' + error.stack);
    }
}

test('stable four-ability selection stops full recovery and avoids duplicate scans', () => {
    const h = createHarness();
    h.select(900);
    h.runUntil(1.2);
    assertBound(h, 901);
    const fullBinds = count(h, 'bindOfficialAbilities');
    assert(fullBinds > 0 && fullBinds <= 4, 'Stable selection should need at most four full binds, got ' + fullBinds);
    const scansByTask = new Map();
    for (const entry of h.work.filter(item => item.name === 'collectOfficialAbilityPanels')) {
        scansByTask.set(entry.task, (scansByTask.get(entry.task) || 0) + 1);
    }
    assert([...scansByTask.values()].every(value => value <= 1), 'A callback must not scan once for logs and again for binding');
    for (const entry of h.work.filter(item => item.name === 'bindOfficialAbilities')) {
        const reads = h.abilityReads.filter(read => read.task === entry.task && read.unit === entry.unit);
        assert.equal(reads.length, 4, 'A full bind should share one four-slot snapshot across ownership, mapping and diagnostics');
    }
    const before = h.work.length;
    h.runUntil(11);
    assert.equal(h.work.length, before, 'Completed recovery must stay idle');
    assert(h.executions.length < 40, 'Default diagnostics must not create the 200-callback cursor probe');
    assert(!h.logs.some(line => /\[SURVIVAL_TOOLTIP_(?:BIND|MAP|PROXY|HITBOX|CURSOR|LAYER)\]/.test(line)),
        'Detailed binding/geometry diagnostics should be disabled by default');
    assert(!h.logs.some(line => line.includes('action=attempt')), 'Per-attempt diagnostics should be disabled by default');
    console.log('  full binds=' + fullBinds + ', scans=' + count(h, 'collectOfficialAbilityPanels')
        + ', ability reads=' + h.counters.abilityReads + ', unit metadata reads=' + h.counters.unitMetadataReads);
});

for (const delay of [0.35, 0.6]) {
    test('HUD panels arriving at ' + delay + 's still recover', () => {
        const h = createHarness({ readyAt: delay });
        h.runUntil(delay - 0.001);
        assert.equal(h.inspect().bindings.length, 0);
        h.runUntil(1.3);
        assertBound(h, 828);
    });
}

test('late native HUD replacement refreshes stable proxy geometry', () => {
    const h = createHarness();
    h.runUntil(0.5);
    const initialX = h.inspect().bindings[0].x;
    h.rebuildPanels(40);
    h.runUntil(1.3);
    assertBound(h, 828);
    assert.equal(h.inspect().bindings[0].x, initialX + 40);
});

test('same-unit ability replacement updates bindings and restores a real hover', () => {
    const h = createHarness();
    h.runUntil(1.2);
    const first = h.inspect().bindings[0];
    const position = first.proxy.GetPositionWithinWindow();
    h.setCursor([position.x + 10, position.y + 10]);
    first.proxy.events.onmouseover();
    assert.equal(h.inspect().activeAbility, 828);
    h.replaceFirstAbility(1200);
    h.runUntil(2.4);
    assert.equal(h.inspect().bindings[0].ability, 1200);
    assert.equal(h.inspect().activeAbility, 1200, 'Recovery must preserve actual hover restoration with diagnostics disabled');
    assert(!h.tooltip.BHasClass('Hidden'));
});

test('rapid selection switches cannot bind stale unit data', () => {
    const h = createHarness();
    h.runUntil(0);
    h.select(900);
    h.runUntil(0.01);
    h.select(827);
    h.runUntil(0.02);
    h.select(900);
    h.runUntil(1.4);
    assert.equal(h.inspect().unit, 900);
    assertBound(h, 901);
    const wrong = h.work.filter(entry => entry.time > 0.02 && entry.unit !== 900);
    assert.equal(wrong.length, 0);
});

test('duplicate same-unit selection events coalesce', () => {
    const h = createHarness();
    h.runUntil(1.2);
    const before = count(h, 'bindOfficialAbilities');
    for (let index = 0; index < 20; index++) {
        h.emit(index % 2 ? 'dota_player_update_query_unit' : 'dota_player_update_selected_unit');
    }
    h.runUntil(2.5);
    assertBound(h, 828);
    const additional = count(h, 'bindOfficialAbilities') - before;
    assert(additional <= 3, 'Duplicate event burst should coalesce, got ' + additional + ' full binds');
});

test('shutdown cancels pending recovery and prevents future work', () => {
    const h = createHarness({ readyAt: 0.6 });
    h.runUntil(0.02);
    const controller = h.config.SurvivalTooltipBindings;
    controller.Shutdown('test');
    const before = h.work.length;
    h.select(900);
    h.replaceFirstAbility(1300);
    controller.Recover('after_shutdown');
    h.runUntil(12);
    assert.equal(h.work.length, before);
    assert.equal(h.inspect().bindings.length, 0);
    for (const proxy of h.inspect().proxies) assert.equal(proxy.hittest, false);
});

test('late per-ability runtime arrives without changing the unit slot signature', () => {
    const h = createHarness({ runtimeIndexes: [0] });
    h.runUntil(0.3);
    assert.equal(h.inspect().bindings.length, 1, 'Only the first ability is initially managed');
    h.publishRuntime(1);
    h.publishRuntime(2);
    h.publishRuntime(3);
    h.runUntil(1.4);
    assertBound(h, 828);
});

test('diagnostics can be enabled and disabled without a lingering cursor probe', () => {
    const h = createHarness();
    h.config.SurvivalTooltipPerformance.SetDiagnostics(true);
    h.runUntil(0.1);
    assert(h.logs.some(line => line.includes('[SURVIVAL_TOOLTIP_BIND]')));
    assert(h.logs.some(line => line.includes('[SURVIVAL_TOOLTIP_HITBOX]')));
    assert.equal(h.config.SurvivalTooltipPerformance.Inspect().diagnostics, true);
    h.config.SurvivalTooltipPerformance.SetDiagnostics(false);
    const before = h.executions.length;
    h.runUntil(12);
    assert(h.executions.length - before < 10, 'Disabling diagnostics must stop the 10-second probe');
    assert.equal(h.config.SurvivalTooltipPerformance.Inspect().diagnostics, false);
    assertBound(h, 828);
});

test('native unit with no visible abilities settles without creating proxies', () => {
    const h = createHarness({ native: true, noAbilities: true, panelCount: 0 });
    h.runUntil(1.2);
    assert.equal(h.inspect().bindings.length, 0);
    assert.equal(h.counters.created, 0);
    assert(count(h, 'bindOfficialAbilities') <= 3);
    const before = h.executions.length;
    h.runUntil(12);
    assert.equal(h.executions.length, before);
});

for (const [unitName, abilityName, hero] of [
    ['building_city','ability_upgrade_city',false],
    ['building_farm','ability_upgrade_farm',false],
    ['building_gold_mine','ability_upgrade_gold_mine_efficiency',false],
    ['building_research_lab','ability_research_lumberjack_speed',false],
    ['building_advanced_research_lab','ability_research_ars_01',false],
    ['building_arrow_tower','ability_upgrade_tower_lv01',false],
    ['building_wall','ability_upgrade_wall',false],
    ['building_hero_altar','ability_summon_hero_doom',false],
    ['npc_survival_builder_proxy','ability_build_arrow_tower',false],
    ['npc_dota_hero_doom_bringer','ability_survival_doom_infernal',true]
]) {
    test(unitName + ' restores tooltip after cached rows are deleted', () => {
        const h=createHarness({unitName,hero,abilityNames:[abilityName],panelCount:1,
            fields:[{label:'attack',value:'25'}]});
        h.runUntil(1.2);
        const binding=h.inspect().bindings[0];
        assert(binding,'Expected a managed tooltip binding');
        const xy=binding.proxy.GetPositionWithinWindow();
        h.setCursor([xy.x+10,xy.y+10]);
        binding.proxy.events.onmouseover();
        assert(!h.tooltip.BHasClass('Hidden'));
        const fields=h.fieldContainer();
        assert(fields.__fieldRows.length>0);
        const old=fields.__fieldRows[0];
        fields.RemoveAndDeleteChildren(); // Engine reload retains the JS property.
        assert(!old.IsValid());
        binding.proxy.events.onmouseover();
        assert(!h.tooltip.BHasClass('Hidden'));
        assert(fields.__fieldRows[0].IsValid());
        assert.notStrictEqual(fields.__fieldRows[0],old);
        assert.equal(fields.__fieldRows[0].__right.text,'25');
        assert.deepEqual(h.logs.filter(line=>line.includes('[SURVIVAL_TOOLTIP_ERROR]')),[]);
    });
}

test('worker fusion mouse proxy uses project dispatcher instead of native order',()=>{
 const h=createHarness({unitName:'npc_survival_lumberjack',abilityNames:['ability_fuse_lumberjack_06'],panelCount:1});
 let requests=0;
 h.config.SurvivalAbilityInput={ExecuteAbility:()=>{requests++;}};
 h.runUntil(1.2);
 const binding=h.inspect().bindings[0];assert(binding);
 const before=h.executions.length;
 binding.proxy.events.onactivate();
 assert.equal(requests,1);assert.equal(h.executions.length,before);
});

for (const signal of ['behavior', 'server', 'engine']) {
    for (const hero of [false, true]) {
        test((hero ? 'hero native' : 'tower managed') + ' proxy rejects passive ' + signal + ' without disabling tooltip', () => {
            let nativeCasts = 0, projectCasts = 0, passive = true;
            const h = createHarness({
                unitName: hero ? 'npc_dota_hero_drow_ranger' : 'building_arrow_tower', hero,
                abilityNames: ['piercing_ballista_lv04'], panelCount: 1,
                abilities: {
                    GetBehavior: () => passive && signal === 'behavior' ? 2 : 4,
                    IsPassive: () => passive && signal === 'engine',
                    ExecuteAbility: () => { nativeCasts++; }
                }
            });
            if (signal === 'server') h.setTable('survival_ability_runtime', 828, {
                owner_entindex: 827, ability_entindex: 828, available: 1, passive: 1
            });
            h.config.SurvivalAbilityInput = {ExecuteAbility: () => { projectCasts++; }};
            h.runUntil(1.2);
            const binding = h.inspect().bindings[0];
            assert(binding, 'passive must retain its tooltip binding');
            assert.equal(binding.proxy.hittest, true);
            binding.proxy.events.onactivate();
            assert.equal(nativeCasts + projectCasts, 0, 'passive must reach neither native nor server dispatcher');
            passive = false;
            h.setTable('survival_ability_runtime', 828, {
                owner_entindex: 827, ability_entindex: 828, available: 1, passive: 0
            });
            binding.proxy.events.onactivate();
            assert.equal(hero ? nativeCasts : projectCasts, 1, 'active reuse still reaches its proper dispatcher');
            assert.deepEqual(h.logs.filter(line => line.includes('[SURVIVAL_TOOLTIP_ERROR]')), []);
        });
    }
}

test('ultimate tower binds all seven real project tooltips, retains passive input protection and follows native row recovery', () => {
    const names = Array.from({length: 5}, (_, index) => 'ultimate_tower_passive_' + (index + 1))
        .concat(['ability_building_blink', 'ability_destroy_arrow_tower']);
    const h = createHarness({unitName:'npc_dota_unit_ultimate_tower', abilityNames:names,
        panelCount:7, runtimeIndexes:[5,6],
        abilities:{GetBehavior:id => id >= 828 && id < 833 ? 2 : 4}});
    const casts=[];
    h.config.SurvivalAbilityInput={ExecuteAbility:id => casts.push(id)};
    h.runUntil(1.2);
    assert.equal(h.inspect().bindings.length, 2, 'initial tool metadata is managed before passive metadata arrives');
    for (let index=0; index<5; index++) h.publishRuntime(index);
    h.runUntil(1.6);
    assert.equal(h.inspect().bindings.length, 7, 'late aggregate metadata binds five project passive tooltips');
    for (const binding of h.inspect().bindings) {
        h.setTable('survival_ability_runtime',binding.ability,{owner_entindex:827,
            ability_entindex:binding.ability,available:1,passive:binding.ability < 833 ? 1 : 0,
            display_name:'聚合技能 '+binding.ability,status_text:'可施法',
            fields:[{label:'聚合效果',value:'当前合成塔效果 '+binding.ability}]});
        const xy=binding.proxy.GetPositionWithinWindow();h.setCursor([xy.x+10,xy.y+10]);
        binding.proxy.events.onmouseover();
        assert(!h.tooltip.BHasClass('Hidden'), 'project tooltip opens for '+binding.ability);
        assert.equal(h.tooltip.FindChildTraverse('CustomAbilityTitle').text,'聚合技能 '+binding.ability);
        assert(h.fieldContainer().__fieldRows.some(row => row.__right.text === '当前合成塔效果 '+binding.ability));
        const passive=binding.ability<833;
        assert.equal(h.tooltip.FindChildTraverse('CustomAbilityExtensionLabel').text,
            passive?'生存防守 · 被动技能':'生存防守 · 防御塔技能','project ownership is independent from upgrade presentation');
        assert.equal(h.tooltip.FindChildTraverse('CustomAbilityType').text,passive?'被动':'主动');
        assert.equal(h.tooltip.FindChildTraverse('CustomAbilityStatus').text,
            passive?'自动生效 · 无需施放':'可施法','passive ignores a generic server cast-status string');
        binding.proxy.events.onactivate();
    }
    assert.deepEqual(casts,[833,834], 'only D/G tools may reach the project dispatcher');
    h.rebuildPanels(30);h.config.SurvivalTooltipBindings.Recover('native_ability_row_reflow');h.runUntil(2.1);
    assert.equal(h.inspect().bindings.length,7);
    assert.equal(h.inspect().bindings[0].x,730,'tooltip proxies follow a replaced native row');
    assert.deepEqual(h.logs.filter(line => line.includes('[SURVIVAL_TOOLTIP_ERROR]')), []);
});

test('real building upgrades retain their upgrade category, progress and fields',()=>{
    const h=createHarness({unitName:'building_city',abilityNames:['ability_upgrade_city'],panelCount:1});
    h.setTable('survival_ability_runtime',828,{owner_entindex:827,ability_entindex:828,
        available:1,prerequisite_met:1,upgrade_in_progress:1,
        fields:[{label:'升级收益',value:'主城等级提高'}]});
    h.runUntil(1.2);const binding=h.inspect().bindings[0];assert(binding);
    const xy=binding.proxy.GetPositionWithinWindow();h.setCursor([xy.x+10,xy.y+10]);binding.proxy.events.onmouseover();
    assert.equal(h.tooltip.FindChildTraverse('CustomAbilityExtensionLabel').text,'SURVIVAL · UPGRADE');
    assert.equal(h.tooltip.FindChildTraverse('CustomAbilityType').text,'UPGRADING');
    assert.equal(h.tooltip.FindChildTraverse('CustomAbilityStatus').text,'Upgrade completes in 1 second');
    assert(h.fieldContainer().__fieldRows.some(row=>row.__right.text==='主城等级提高'));
});

function earthLineLevelFields() {
    // Use the actual skill's long LV1 and LV5 descriptions as runtime payloads.
    // The tests exercise the real renderer and its panel pool, not CSS pixels.
    const definitions = fs.readFileSync(path.join(__dirname,
        '../scripts/vscripts/config/hero_passive_skill_definitions.lua'), 'utf8');
    const block = /skill_id\s*=\s*"proto_earth_line"[\s\S]*?level_text\s*=\s*\{([\s\S]*?)\}/.exec(definitions);
    assert(block, 'Expected the actual earth-line passive level descriptions');
    const values = Array.from(block[1].matchAll(/"(?:[^"\\]|\\.)*"/g), match => JSON.parse(match[0]));
    assert.equal(values.length, 5, 'Earth-line passive must provide all five level descriptions');
    assert(values[0].length > 100, 'LV1 fixture must retain the real long description');
    return values.map((value, index) => ({label: 'LV' + (index + 1), value}));
}

function hoverFirstAbility(h) {
    const binding = h.inspect().bindings[0];
    assert(binding, 'Expected a managed tooltip binding');
    const xy = binding.proxy.GetPositionWithinWindow();
    h.setCursor([xy.x + 10, xy.y + 10]);
    binding.proxy.events.onmouseover();
    assert(!h.tooltip.BHasClass('Hidden'));
    return binding;
}

function assertSkillLevelRows(h, fields, currentLevel) {
    const rows = h.fieldContainer().__fieldRows.filter(row => row.visible);
    assert.equal(rows.length, fields.length, 'All descriptions must remain visible');
    rows.forEach((row, index) => {
        assert.equal(row.__left.text, fields[index].label);
        assert.equal(row.__right.text, fields[index].value, 'Long level text must remain intact');
        assert.equal(row.BHasClass('AbilitySkillLevelRow'), true,
            fields[index].label + ' must use the compact level-description layout');
        assert.equal(row.BHasClass('AbilitySkillLevelCurrent'), index + 1 === currentLevel,
            fields[index].label + ' must be current only at its own native ability level');
    });
    assert.equal(rows.filter(row => row.BHasClass('AbilitySkillLevelCurrent')).length, 1,
        'Exactly the current level description receives the gold presentation');
}

test('hero level descriptions highlight LV1 and refresh to LV3 during the same hover without growing panels', () => {
    let level = 1;
    const fields = earthLineLevelFields();
    const h = createHarness({hero: true, unitName: 'npc_dota_hero_doom_bringer',
        abilityNames: ['ability_survival_earth_line'], panelCount: 1, fields,
        abilities: {GetLevel: () => level}});
    h.runUntil(1.2);
    hoverFirstAbility(h);
    assert.equal(h.inspect().activeAbility, 828);
    assert.equal(h.tooltip.FindChildTraverse('CustomAbilityExtensionLabel').text, 'SURVIVAL · HERO');
    assertSkillLevelRows(h, fields, 1);
    const firstRow = h.fieldContainer().__fieldRows[0];
    const created = h.counters.created;
    level = 3;
    const runtime = {owner_entindex: 827, ability_entindex: 828, available: 1, fields};
    h.setTable('survival_ability_runtime', 828, runtime, true);
    assert.equal(h.inspect().activeAbility, 828, 'An upgrade must preserve the active hover');
    assert(!h.tooltip.BHasClass('Hidden'), 'An upgrade refresh must preserve the visible tooltip');
    assertSkillLevelRows(h, fields, 3);
    assert.strictEqual(h.fieldContainer().__fieldRows[0], firstRow, 'Refresh must reuse the live row pool');
    assert(h.tooltip.FindChildTraverse('CustomAbilityLevel').text.endsWith(' 3'));
    for (let index = 0; index < 20; index++) {
        h.setTable('survival_ability_runtime', 828, runtime, true);
    }
    h.runUntil(2.4);
    assertSkillLevelRows(h, fields, 3);
    assert.equal(h.counters.created, created, 'Stable level refreshes must not create more panels');
});

test('reused hero and building field rows clear current-level styling and only exact LV labels qualify', () => {
    const fields = earthLineLevelFields();
    const h = createHarness({hero: true,
        unitNames: {827: 'npc_dota_hero_doom_bringer', 900: 'building_city'},
        unitAbilityNames: {827: ['ability_survival_earth_line'], 900: ['ability_upgrade_city']},
        panelCount: 1, fields});
    h.runUntil(1.2);
    hoverFirstAbility(h);
    assertSkillLevelRows(h, fields, 1);
    const firstRow = h.fieldContainer().__fieldRows[0];
    const ordinaryFields = [
        {label: '触发概率', value: '12%'},
        {label: 'LV1效果', value: '普通描述，非等级标题'},
        {label: 'LV0', value: '普通描述，非可升级等级'}
    ];
    h.setTable('survival_ability_runtime', 828, {owner_entindex: 827, ability_entindex: 828,
        available: 1, fields: ordinaryFields}, true);
    assert.strictEqual(h.fieldContainer().__fieldRows[0], firstRow);
    const rows = h.fieldContainer().__fieldRows.filter(row => row.visible);
    assert.equal(rows.length, ordinaryFields.length);
    rows.forEach((row, index) => {
        assert.equal(row.__right.text, ordinaryFields[index].value);
        assert.equal(row.BHasClass('AbilitySkillLevelRow'), false, 'Non-level hero fields keep their ordinary layout');
        assert.equal(row.BHasClass('AbilitySkillLevelCurrent'), false, 'Reusing the LV1 row must clear its gold styling');
    });
    h.setTable('survival_ability_runtime', 828, {owner_entindex: 827, ability_entindex: 828,
        available: 1, fields}, true);
    assertSkillLevelRows(h, fields, 1);
    h.select(900);
    h.runUntil(2.4);
    hoverFirstAbility(h);
    assert.equal(h.tooltip.FindChildTraverse('CustomAbilityExtensionLabel').text, 'SURVIVAL · UPGRADE');
    assert.strictEqual(h.fieldContainer().__fieldRows[0], firstRow, 'Changing units reuses the same tooltip row pool');
    const buildingRows = h.fieldContainer().__fieldRows.filter(row => row.visible);
    assert.equal(buildingRows.length, fields.length);
    buildingRows.forEach((row, index) => {
        assert.equal(row.__left.text, fields[index].label);
        assert.equal(row.__right.text, fields[index].value);
        assert.equal(row.BHasClass('AbilitySkillLevelRow'), false, 'Building LV-like fields must not adopt hero level layout');
        assert.equal(row.BHasClass('AbilitySkillLevelCurrent'), false, 'Building rows must not inherit hero gold styling');
    });
});

if (failures) {
    process.exitCode = 1;
    console.error('ABILITY_TOOLTIP_RECOVERY_FAILED: ' + failures);
} else {
    console.log('ABILITY_TOOLTIP_RECOVERY_PASS');
}
