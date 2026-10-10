// Run the real native/fallback paint and input functions against panel doubles.
// This verifies runtime stability and hover access, not Dota's rendered pixels.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {setup} = require('./test_combat_stats_callbacks.cjs');
const directory = 'panorama/src/scripts/custom_game/';
const tooltipSource = fs.readFileSync(directory + 'ability_tooltip.js', 'utf8');
const takeoverSource = fs.readFileSync(directory + 'hud_takeover.js', 'utf8');

function productionFunction(source, name) {
    const start = source.indexOf('    function ' + name + '(');
    const end = source.indexOf('\n    function ', start + 1);
    assert(start >= 0 && end > start, 'missing production function ' + name);
    return source.slice(start, end);
}

for (const hero of ['monkey_king', 'blademaster']) {
    const serverSource = fs.readFileSync('scripts/vscripts/systems/' + hero + '_exclusive_service.lua', 'utf8');
    const name = serverSource.match(/local Q_ABILITY = "([^"]+)"/)[1];
    const ability = 100, clone = 7;
    let behavior = 2, enginePassive = true, casts = 0;
    const names = new Map([[ability, name], [200, 'mock_active_reuse']]);
    const slots = new Map([[clone, [ability]], [8, [200]]]);
    const abilities = {
        GetBehavior: index => index === ability ? behavior : 4,
        IsPassive: index => index === ability && enginePassive,
        GetAbilityName: index => names.get(index) || '',
        IsHidden: () => false,
        ExecuteAbility: () => { casts++; },
    };
    const entities = {
        GetAbility: (unit, index) => (slots.get(Number(unit)) || [])[index] ?? -1,
    };
    const hud = setup({portrait: true, abilities, entities,
        events: {SendCustomGameEventToServer: () => { casts++; }}});
    hud.select(clone, 'npc_dota_hero_' + (hero === 'blademaster' ? 'juggernaut' : hero));
    const list = new hud.Panel('abilities', hud.root);
    const panel = new hud.Panel('Ability0', list);
    const anchor = new hud.Panel('AbilityButton', panel);
    let colorWrites = 0;
    function visual(id, parent, original) {
        const node = new hud.Panel(id, parent);
        Object.assign(node.values, original);
        node.style = new Proxy(node.values, {
            get(target, key) { return target[key]; },
            set(target, key, value) {
                if (['saturation', 'brightness', 'washColor'].includes(key)) colorWrites++;
                target[key] = key === 'saturation' || key === 'brightness'
                    ? Number(value).toFixed(3)
                    : key === 'washColor' && value === '#ffffffff' ? 'rgba(255,255,255,1)'
                    : key === 'washColor' && value === '#00000000' ? 'rgba(0,0,0,0)' : value;
                return true;
            },
        });
        return node;
    }
    const icon = visual('AbilityImage', anchor,
        {saturation: '0.000', brightness: '0.450', washColor: '#666666'});
    const bevel = visual('AbilityBevel', panel, {washColor: '#000000bb'});
    const border = visual('ActiveAbilityBorder', panel, {brightness: '0.200'});
    const cooldown = new hud.Panel('CooldownOverlay', panel);
    cooldown.values.opacity = '0.65';
    const hotkey = new hud.Panel('HotkeyContainer', panel);
    hotkey.values.opacity = '0.35';
    panel.classes = {no_level: true};
    panel.BHasClass = value => !!panel.classes[value];
    hud.runtime['unit:' + clone] = {owner_entindex: clone, ability_count: 1};
    const complete = {ability_name: name, ability_entindex: ability, owner_entindex: clone,
        available: 1, prerequisite_met: 1, can_afford: 1, passive: 1};
    hud.runtime[ability] = {...complete};
    const entry = {ability, name, slot: 0};
    const mapping = [{entry, panel, anchor, nodeIndex: 0}];
    const mirroredKeys = {};
    hud.cfg.HandoffStyleHotkey = (label, slot) => { mirroredKeys[slot.id] = label.text; };
    const skin = hero === 'monkey_king' ? 'topnav_remaining_5d5c1152eb.js' : 'handoff_hud.js';
    const skinSource = fs.readFileSync(directory + skin, 'utf8');
    const clearHook = skinSource.match(/    cfg\.HandoffClearHotkey=function\(slot\)\{[^\n]+/)[0];
    vm.runInNewContext(clearHook, {cfg: hud.cfg, keyBindings: mirroredKeys});
    // Start with an active skill in the reused slot, including its floating key.
    const active = {ability: 200, name: names.get(200), slot: 0, standardHotkeyIndex: 0};
    const activeMapping = [{entry: active, panel, anchor, nodeIndex: 0}];
    hud.select(8, 'npc_dota_hero_test');
    assert.equal(hud.api.refreshOfficialUtilityHotkeys([active], activeMapping), true);
    assert.equal(mirroredKeys.Ability0, 'Q');
    hud.select(clone);

    // Handoff/topnav call ApplyRuntime directly. The hotkey writer separately
    // decides whether the selected unit owns the complete runtime identity.
    const skinEnvironment = {cfg: {HandoffCombat: {
        NativeEntries: () => [entry], ApplyRuntime: hud.api.applyAbilityRuntime,
        IsCompleted: index => Number((hud.runtime[index] || {}).completed) === 1,
    }}, native: () => list, valid: node => !!node && node.IsValid(),
        selectedUnit: () => clone, currentEntries: [entry], skillPanels: [],
        ctx: {actualuiscale_x: 1}, geometry: {scale: 1},
        // Unrelated slot positioning is outside this color/input regression.
        square() {}, style(node, values) { Object.assign(node.style, values); }};
    vm.runInNewContext(productionFunction(skinSource, 'fitNativeSkills'), skinEnvironment);
    function directPaint() { skinEnvironment.fitNativeSkills({scale: 1}); }
    function nativePaint() {
        assert.equal(hud.api.refreshOfficialUtilityHotkeys([entry], mapping), true);
    }
    function colored(saturation = 1, brightness = 1) {
        assert.equal(Number(icon.style.saturation), saturation, name + ': saturation');
        assert.equal(Number(icon.style.brightness), brightness, name + ': brightness');
        assert.equal(icon.style.washColor, 'rgba(255,255,255,1)');
        assert.equal(bevel.style.washColor, 'rgba(0,0,0,0)');
        assert.equal(Number(border.style.brightness), 1);
        assert.equal(panel.BHasClass('DOTADisabled'), false);
        assert.equal(panel.hittest, true, 'passive keeps native tooltip access');
        assert.equal(cooldown.style.opacity, '0.65', 'actual native overlays are preserved');
    }
    directPaint(); nativePaint(); colored();
    assert.equal(hotkey.style.opacity, '0');
    assert.equal(panel.FindChildTraverse('SurvivalAbilityHotkey').style.visibility, 'collapse');
    assert.equal(mirroredKeys.Ability0, undefined, 'clone passive clears the prior floating hotkey');
    assert.equal(hud.api.officialAbilityHotkeysMatch(mapping), true,
        'passive suppression is an accepted cached native binding');
    colorWrites = 0;
    for (let frame = 0; frame < 80; frame++) {
        if (frame % 2) { directPaint(); nativePaint(); }
        else { nativePaint(); directPaint(); }
        colored();
    }
    assert.equal(colorWrites, 0, 'complete clone identity prevents competing color writers');

    const shared = {
        selectedUnit: () => clone,
        readTooltipTable: (_, key) => hud.runtime[key] || {},
        unitOwnsAbility: (owner, index) => (slots.get(Number(owner)) || []).includes(index),
        Abilities: abilities,
        GameUI: {CustomUIConfig: () => hud.cfg},
        GameEvents: {SendCustomGameEventToServer: () => { casts++; }},
        selectedEntindexesForRequest: () => [clone],
        $: {Msg() {}},
        tooltipError: (_, error) => { throw error; },
    };
    for (const fn of ['managedRuntime', 'isPassiveAbility', 'executeAbility',
        'externalAbilityHighlightTarget', 'externalAbilityUnavailable',
        'externalAbilityRuntime', 'setExternalProxyHighlight']) {
        vm.runInNewContext(productionFunction(tooltipSource, fn), shared);
    }
    assert.equal(shared.managedRuntime(ability), true);
    for (const invalid of [{owner_entindex: 8}, {ability_entindex: 999}, {removed: 1}]) {
        hud.runtime[ability] = {...complete, ...invalid};
        assert.equal(shared.managedRuntime(ability), false, 'invalid clone runtime cannot retain ownership');
    }
    hud.runtime[ability] = {...complete};

    const fallbackEnvironment = {
        runtimeFor: index => hud.runtime[index] || {},
        selectedUnit: () => clone,
        selectedUnitName: () => 'npc_dota_hero_' + hero,
        unitAbilityCount: () => 1,
        Abilities: abilities, Entities: entities,
        utilityHotkeys: {}, utilityDisplayOrder: {}, hotkeys: ['Q', 'W', 'E'],
        abilityLevel: () => 1, manaCost: () => 0,
        cooldownRemaining: () => 0, cooldownLength: () => 0,
        config: {SurvivalAbilityInput: {ExecuteAbility: () => { casts++; }}},
    };
    for (const fn of ['isPassiveAbility', 'hotkeyForEntry', 'visibleAbilities', 'activate', 'updateSlot']) {
        vm.runInNewContext(productionFunction(takeoverSource, fn), fallbackEnvironment);
    }
    const fallback = {panel: {style: {}, classes: {},
        SetHasClass(key, value) { this.classes[key] = value; }},
        image: {style: {}}, hotkey: {}, level: {}, mana: {}, cooldown: {}, shade: {style: {}}};

    // Server passive metadata also protects the interval where the native
    // behavior query temporarily looks active. An empty wallet has no effect.
    for (const nativeReady of [true, false, true]) {
        behavior = nativeReady ? 2 : 4;
        enginePassive = nativeReady;
        hud.runtime[ability].can_afford = 0;
        const ordered = hud.api.orderVisibleAbilities([{...entry}]);
        assert.equal(ordered[0].standardHotkeyIndex, -1);
        assert.equal(hud.api.hotkeyForAbilityEntry(ordered[0], ''), '');
        assert.equal(hud.api.executeAbility(ability), false);
        assert.equal(shared.executeAbility(ability), false);
        assert.equal(fallbackEnvironment.hotkeyForEntry(entry), '');
        assert.equal(fallbackEnvironment.visibleAbilities()[0].standardHotkeyIndex, -1);
        fallbackEnvironment.activate(entry);
        fallbackEnvironment.updateSlot(fallback, entry, 0);
        assert.equal(fallback.panel.classes.Passive, true);
        assert.equal(fallback.panel.classes.Unavailable, false);
        assert.equal(fallback.panel.enabled, true, 'fallback passive remains hoverable');
        directPaint(); nativePaint(); colored();
        assert.equal(hud.api.officialAbilityHotkeysMatch(mapping), true);
    }
    assert.equal(casts, 0, 'all passive input paths reject without dispatching');

    // Exercise the shared highlight owner and paint ordering. Native hover is
    // retained even when this clone uses Valve's tooltip rather than a proxy.
    const proxy = new hud.Panel('HoverProxy', hud.root);
    proxy.__survivalVisualAnchor = anchor;
    proxy.__survivalAbilityIndex = ability;
    shared.setExternalProxyHighlight(proxy, true);
    directPaint(); nativePaint(); colored(1.35, 1.25);
    colorWrites = 0;
    for (let frame = 0; frame < 40; frame++) { directPaint(); nativePaint(); colored(1.35, 1.25); }
    assert.equal(colorWrites, 0, 'matching hover survives both paint paths without repeated writes');
    shared.setExternalProxyHighlight(proxy, false);
    directPaint(); nativePaint(); colored();

    // Death/removal invalidates the clone row. Valve can then reuse Ability0
    // for an ordinary active ability on a different unit; no clone art or
    // passive hotkey suppression may remain on that slot.
    hud.runtime[ability] = {removed: 1};
    hud.runtime['unit:' + clone] = {owner_entindex: clone, ability_count: 0, removed: 1};
    hud.select(8, 'npc_dota_hero_test');
    hud.runtime['unit:8'] = {owner_entindex: 8, ability_count: 1};
    hud.api.applyAbilityRuntime(panel, 200);
    assert.equal(hud.api.refreshOfficialUtilityHotkeys([active], activeMapping), true);
    assert.equal(Number(icon.style.saturation), 0);
    assert.equal(Number(icon.style.brightness), 0.45);
    assert.equal(icon.style.washColor, '#666666');
    assert.equal(bevel.style.washColor, '#000000bb');
    assert.equal(Number(border.style.brightness), 0.2);
    assert.equal(panel.BHasClass('DOTADisabled'), false);
    assert.equal(panel.FindChildTraverse('SurvivalAbilityHotkey').text, 'Q');
    assert.equal(mirroredKeys.Ability0, 'Q');
    assert.equal(hud.api.officialAbilityHotkeysMatch(activeMapping), true);
    colorWrites = 0;
    for (let frame = 0; frame < 40; frame++) {
        hud.api.applyAbilityRuntime(panel, 200);
        hud.api.refreshOfficialUtilityHotkeys([active], activeMapping);
    }
    assert.equal(colorWrites, 0, 'cleared clone leaves native slot colors stable');
    assert.equal(hud.api.executeAbility(200), true, 'active slot reuse restores normal input');
    assert.equal(casts, 1);
}
console.log('CLONE_PASSIVE_UI_PASS: both real clone Q identities, native gray/bevel restoration, 80 alternating zero-write paints, passive keys/input, native-query recovery, hover, removal and active slot reuse');
