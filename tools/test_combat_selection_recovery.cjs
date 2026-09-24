// Exercise the real combat HUD functions with delayed/rebuilt native panels.
// The seam suppresses unrelated startup timers; production functions stay intact.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync(process.argv[2] || 'panorama/src/scripts/custom_game/combat_stats.js', 'utf8');
const seam = '    // NetTable is the single regular synchronization path.';
assert(source.includes(seam));
const instrumented = source.replace(seam, `    __test({
        select: onUnitSelectionEvent,
        refresh: refreshAbilityHotkeysIfChanged,
        refreshAbilities: refreshAbilities,
        vitals: refreshHeroVitalsTick,
        entries: visibleAbilityEntries,
        shutdown: shutdownCombatContext
    });
    return;
` + seam);

function setup() {
    let api, now = 0, nextJob = 0, selected = 10;
    const jobs = new Map(), definitions = new Map(), runtimes = new Map();
    const metrics = { searches: 0, labelWrites: 0, labelsCreated: 0 };
    const messages = [], requests = [];
    class Panel {
        constructor(id, parent, type = 'Panel') {
            this.id = id;
            this.parent = parent;
            this.paneltype = type;
            this.children = [];
            this.alive = true;
            this.visible = true;
            this.hittest = true;
            this.hittestchildren = true;
            this.classes = new Set();
            this.style = {};
            this.actualuiscale_x = this.actualuiscale_y = 1;
            this.actuallayoutwidth = this.actuallayoutheight = 64;
            this.x = this.y = 0;
            if (parent) parent.children.push(this);
        }
        set text(value) {
            assert(this.alive, 'must not write a destroyed label');
            if (this.id === 'SurvivalAbilityHotkey') metrics.labelWrites++;
            this.value = value;
        }
        get text() { return this.value || ''; }
        IsValid() { return this.alive; }
        GetParent() { return this.parent; }
        GetChildCount() { return this.children.length; }
        GetChild(index) { return this.children[index]; }
        GetPositionWithinWindow() { return { x: this.x, y: this.y }; }
        SetPanelEvent() {}
        AddClass(name) { this.classes.add(name); }
        RemoveClass(name) { this.classes.delete(name); }
        SetHasClass(name, value) { value ? this.AddClass(name) : this.RemoveClass(name); }
        BHasClass(name) { return this.classes.has(name); }
        FindChildTraverse(id) {
            if (this.id === 'abilities' && /^Ability\d+$/.test(id)) metrics.searches++;
            return this.find(id);
        }
        find(id) {
            if (!this.alive) return null;
            if (this.id === id) return this;
            for (const child of this.children) {
                const found = child.find(id);
                if (found) return found;
            }
            return null;
        }
        destroy() {
            this.alive = false;
            this.children.forEach(child => child.destroy());
        }
    }
    const root = new Panel('Hud'), context = new Panel('Context', root);
    let abilities = new Panel('abilities', root);
    const cfg = {
        SurvivalSelectionResolver: { Resolve: () => selected, ResolveDisplayUnit: () => selected },
    };
    const $ = id => context.FindChildTraverse(id.slice(1));
    $.GetContextPanel = () => context;
    $.Localize = text => text;
    $.Msg = $.Warning = (...parts) => messages.push(parts.join(''));
    $.CreatePanel = (type, parent, id) => {
        if (id === 'SurvivalAbilityHotkey') metrics.labelsCreated++;
        return new Panel(id, parent, type);
    };
    $.Schedule = (delay, fn) => {
        const id = ++nextJob;
        jobs.set(id, { at: now + delay, fn });
        return id;
    };
    $.CancelScheduled = id => jobs.delete(id);
    const getDefinition = unit => definitions.get(unit) || { name: 'npc_dota_hero_test', skills: [] };
    const getAbility = id => {
        for (const unit of definitions.values()) {
            const skill = unit.skills.find(entry => entry.id === id);
            if (skill) return skill;
        }
        return {};
    };
    vm.runInNewContext(instrumented, {
        $, GameUI: { CustomUIConfig: () => cfg },
        Game: { GetLocalPlayerID: () => 0 },
        Players: { GetPlayerHeroEntityIndex: () => selected },
        Entities: {
            GetUnitName: unit => getDefinition(unit).name,
            GetAbility: (unit, slot) => getDefinition(unit).skills[slot]?.id ?? -1,
            GetLevel: () => 1, GetHealth: () => 100, GetMaxHealth: () => 100,
            GetMana: () => 50, GetMaxMana: () => 50,
        },
        Abilities: {
            GetAbilityName: id => getAbility(id).name || '',
            GetBehavior: id => getAbility(id).behavior || 0,
            IsHidden: id => !!getAbility(id).hidden,
        },
        CustomNetTables: {
            GetTableValue(table, key) {
                if (table !== 'survival_ability_runtime') return null;
                if (String(key).startsWith('unit:')) {
                    const unit = Number(key.slice(5));
                    return { owner_entindex: unit, ability_count: getDefinition(unit).skills.length };
                }
                return runtimes.get(Number(key)) || null;
            },
        },
        GameEvents: { SendCustomGameEventToServer: (name, data) => requests.push({ name, data }) },
        __test: value => { api = value; },
    }, { filename: 'combat_stats.js' });
    function define(unit, name, skills) {
        definitions.set(unit, { name, skills });
        for (const skill of skills) runtimes.set(skill.id, {
            owner_entindex: unit, ability_entindex: skill.id, ...skill.runtime,
        });
    }
    function mount(count, replaceContainer = false) {
        if (replaceContainer) {
            abilities.destroy();
            abilities = new Panel('abilities', root);
        } else {
            abilities.children.forEach(child => child.destroy());
            abilities.children = [];
        }
        for (let index = 0; index < count; index++) {
            const panel = new Panel('Ability' + index, abilities);
            const anchor = new Panel('AbilityButton', panel);
            anchor.x = 200 + index * 70;
            anchor.y = 900;
            new Panel('HotkeyContainer', anchor);
        }
    }
    function runUntil(time) {
        for (;;) {
            const pending = [...jobs.entries()].sort((a, b) => a[1].at - b[1].at || a[0] - b[0]);
            if (!pending.length || pending[0][1].at > time) break;
            const [id, job] = pending[0];
            jobs.delete(id);
            now = job.at;
            job.fn();
        }
        now = time;
    }
    function key(index) { return abilities.FindChildTraverse('Ability' + index)?.FindChildTraverse('SurvivalAbilityHotkey'); }
    function native(index) { return abilities.FindChildTraverse('Ability' + index)?.FindChildTraverse('HotkeyContainer'); }
    function assertKeys(expected) {
        expected.forEach((text, index) => {
            const label = key(index);
            if (!text) {
                assert(!label || label.text === '' || label.style.visibility === 'collapse');
                assert.notEqual(native(index)?.style.opacity, '0');
                return;
            }
            assert(label, `missing shortcut ${text} for Ability${index}`);
            assert.equal(label.text, text);
            assert.equal(label.style.visibility, 'visible');
            assert.equal(native(index).style.opacity, '0');
            assert.equal(native(index).hittest, false);
        });
    }
    define(10, 'npc_dota_hero_test', [{ id: 101, name: 'test_spell' }]);
    mount(1);
    return {
        api, cfg, jobs, metrics, messages, requests, define, mount, runUntil, key, native, assertKeys,
        select: unit => { selected = unit; },
        panel: index => abilities.FindChildTraverse('Ability' + index),
        runtime: (id, value) => Object.assign(runtimes.get(id), value),
    };
}

// Repeated notifications before the first selection check preserve the first paint
// without clearing/recreating the labels on the remaining late-HUD checks.
{
    const t = setup();
    t.api.select('selected_unit_event', { PlayerID: 0 });
    const pending = t.jobs.size;
    t.api.select('query_unit_event', { PlayerID: 0 });
    t.api.select('selected_unit_event', { PlayerID: 0 });
    assert.equal(t.jobs.size, pending, 'duplicate selection notifications should share recovery jobs');
    t.runUntil(0);
    t.assertKeys(['Q']);
    const label = t.key(0), writes = t.metrics.labelWrites;
    t.runUntil(0.25);
    t.assertKeys(['Q']);
    assert.equal(t.key(0), label);
    assert.equal(t.metrics.labelWrites, writes, 'stable later checks must not clear/rewrite shortcuts');
    assert.equal(t.requests.length, 1, 'duplicate notifications must not duplicate the stats request');
    assert.equal(t.jobs.size, 0);
}

// A refresh with a known mapping performs a single discovery plus the existing
// stale-label cleanup. Incomplete discovery also must not trigger a second scan.
for (const method of ['refresh', 'refreshAbilities']) {
    const t = setup();
    t.api[method](false);
    assert.equal(t.metrics.searches, 128, `${method}: duplicate mapping scan`);
    t.assertKeys(['Q']);
}
{
    const t = setup();
    t.mount(0);
    t.api.refresh(false);
    assert.equal(t.metrics.searches, 128, 'incomplete mapping should be reused until the next check');
}

// Native nodes can arrive after selection or be destroyed and replaced after
// the first successful refresh, even when the entity/ability IDs stay the same.
for (const replaceContainer of [false, true]) {
    const t = setup();
    t.mount(0);
    t.api.select('selected_unit_event', { PlayerID: 0 });
    t.runUntil(0.016);
    t.mount(1);
    t.runUntil(0.05);
    t.assertKeys(['Q']);
    const old = t.key(0);
    t.mount(1, replaceContainer);
    t.runUntil(0.1);
    t.assertKeys(['Q']);
    assert.notEqual(t.key(0), old);
    assert.equal(old.IsValid(), false);
    // Valve may also reuse the same node and restore its native label opacity.
    t.native(0).style.opacity = '1';
    t.runUntil(0.2);
    t.assertKeys(['Q']);
}

// Delays beyond the bounded selection window still recover through the existing
// periodic check. A later selection event starts a new recovery window as well.
{
    const t = setup();
    t.mount(0);
    t.api.select('selected_unit_event', { PlayerID: 0 });
    t.runUntil(0.21);
    t.mount(1);
    t.api.vitals();
    t.assertKeys(['Q']);
    t.key(0).text = '';
    t.api.select('selected_unit_event', { PlayerID: 0 });
    t.runUntil(0.22);
    t.assertKeys(['Q']);
}

// An event arriving after the first check must retain a full late-HUD window;
// coalescing must not truncate its recovery at the previous event's deadline.
{
    const t = setup();
    t.mount(0);
    t.api.select('selected_unit_event', { PlayerID: 0 });
    t.runUntil(0.19);
    t.api.select('query_unit_event', { PlayerID: 0 });
    t.runUntil(0.3);
    t.mount(1);
    t.runUntil(0.4);
    t.assertKeys(['Q']);
    assert.equal(t.jobs.size, 0);
}

// A different unit must supersede a pending window, including invalid selection.
// Non-local events must leave this client's shortcuts untouched.
{
    const t = setup();
    t.define(20, 'npc_dota_hero_other', [{ id: 201, name: 'ability_survival_return_home' }]);
    t.api.select('selected_unit_event', { PlayerID: 9 });
    assert.equal(t.jobs.size, 0);
    t.api.select('selected_unit_event', { PlayerID: 0 });
    t.runUntil(0);
    t.select(20);
    t.api.select('selected_unit_event', { PlayerID: 0 });
    t.runUntil(0.01);
    t.assertKeys(['F2']);
    t.runUntil(0.21);
    t.assertKeys(['F2']);
    assert.deepEqual(t.requests.map(request => request.data.entindex), [10, 20]);
    t.select(-1);
    t.api.select('selected_unit_event', { PlayerID: 0 });
    t.runUntil(0.22);
    t.assertKeys(['']);
}

// The match check must use the same key assignment as rendering: passive
// abilities consume no key, and research/builder abilities use runtime slots.
for (const example of [
    {
        name: 'npc_dota_hero_test',
        skills: [{ id: 101, name: 'test_passive', behavior: 2 }, { id: 102, name: 'test_active' }],
        keys: ['', 'Q'],
    },
    {
        name: 'building_advanced_research_lab',
        skills: [{ id: 101, name: 'ability_research_test', runtime: { research_slot_order: 6, research_building_id: 'building_advanced_research_lab' } }],
        keys: ['S'],
    },
    {
        name: 'npc_survival_builder_proxy',
        skills: [{ id: 101, name: 'ability_build_test', runtime: { builder_slot_order: 6 } }],
        keys: ['A'],
    },
]) {
    const t = setup();
    t.define(10, example.name, example.skills);
    t.mount(example.skills.length);
    t.api.refresh(false);
    t.assertKeys(example.keys);
    const writes = t.metrics.labelWrites;
    t.api.refresh(false);
    t.assertKeys(example.keys);
    assert.equal(t.metrics.labelWrites, writes, 'correct nonstandard bindings should remain stable');
}

// Runtime key/behavior changes can leave entity, ability and panel IDs unchanged.
// Existing labels must update or disappear even when the mapping signature matches.
{
    const t = setup();
    t.define(10, 'building_advanced_research_lab', [{
        id: 101, name: 'ability_research_test',
        runtime: { research_slot_order: 6, research_building_id: 'building_advanced_research_lab' },
    }]);
    t.api.refresh(false);
    t.assertKeys(['S']);
    t.runtime(101, { research_slot_order: 7 });
    t.api.refresh(false);
    t.assertKeys(['D']);
    t.define(10, 'building_advanced_research_lab', [{ id: 101, name: 'ability_research_test', behavior: 2 }]);
    t.api.refresh(false);
    t.assertKeys(['']);
}

// Native reuse can overwrite runtime disabled state independently of shortcuts.
// Skipping a stable shortcut write must still reconcile authoritative runtime.
{
    const t = setup();
    t.runtime(101, { available: 0 });
    t.api.refresh(false);
    assert(t.panel(0).BHasClass('DOTADisabled'));
    t.panel(0).RemoveClass('DOTADisabled');
    const writes = t.metrics.labelWrites;
    t.api.refresh(false);
    assert(t.panel(0).BHasClass('DOTADisabled'));
    assert.equal(t.metrics.labelWrites, writes);
}

// Shutdown invalidates all pending recovery work through the existing lifecycle.
{
    const t = setup();
    t.api.select('selected_unit_event', { PlayerID: 0 });
    const stale = [...t.jobs.values()].map(job => job.fn);
    t.api.shutdown('test_replacement');
    assert.equal(t.jobs.size, 0);
    stale.forEach(callback => callback());
    assert.equal(t.metrics.labelsCreated, 0);
}

console.log('COMBAT_SELECTION_RECOVERY_PASS: merged events, single mapping discovery, stable shortcuts, late/rebuilt HUD, runtime reconciliation, key assignments and shutdown');
