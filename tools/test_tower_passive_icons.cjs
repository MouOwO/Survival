// Real production render/input functions, with native panel state and Panorama
// color canonicalization simulated. Pixel appearance still needs game checking.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {setup} = require('./test_combat_stats_callbacks.cjs');
const dir = 'panorama/src/scripts/custom_game/';
const takeover = fs.readFileSync(dir + 'hud_takeover.js', 'utf8');
const tooltip = fs.readFileSync(dir + 'ability_tooltip.js', 'utf8');
const towerSource = fs.readFileSync('scripts/vscripts/config/generated/tower_class_multi.lua', 'utf8');
const towerRow = towerSource.split('\n').find(line => /tower_id\s*=\s*"piercing_ballista_lv04"/.test(line));
assert(towerRow, 'keep the screenshot tower fixture tied to real configuration');
const passiveNames = [...towerRow.match(/\bskill_ids\s*=\s*\{([^}]*)\}/)[1].matchAll(/"([^"]+)"/g)].map(match => match[1]);
const toolNames = [...towerRow.match(/\bactive_skill_ids\s*=\s*\{([^}]*)\}/)[1].matchAll(/"([^"]+)"/g)].map(match => match[1]);
assert.equal(passiveNames.length, 2); assert.equal(toolNames.length, 3);
const names = passiveNames.concat(toolNames);
let behavior = 4, enginePassive = false;
const t = setup({portrait: true, abilities: {
    GetBehavior: () => behavior, IsPassive: () => enginePassive,
    GetAbilityName: ability => names[ability - 100] || 'native_ability'
}});

function makePanel(id, parent, styles = {}) {
    const panel = new t.Panel(id, parent);
    panel.classes = {}; panel.BHasClass = name => !!panel.classes[name];
    let writes = 0;
    Object.assign(panel.values, styles);
    panel.style = new Proxy(panel.values, {
        get(target, property) { return target[property]; },
        set(target, property, value) {
            assert.notEqual(value, null); assert.notEqual(value, undefined);
            if (property === 'washColor' && !/^(?:#[\da-f]{6}(?:[\da-f]{2})?|rgba?\([\d.,\s]+\))$/i.test(String(value))) {
                throw Error('Failed to parse style value for washColor: ' + value);
            }
            if ((property === 'saturation' || property === 'brightness')
                && (!String(value).trim() || !Number.isFinite(Number(value)))) {
                throw Error('Failed to parse numeric style value for ' + property + ': ' + value);
            }
            writes++;
            target[property] = value === '#ffffffff' && property === 'washColor'
                ? 'rgba(255,255,255,1)' : value === '#00000000' && property === 'washColor'
                ? 'rgba(0,0,0,0)' : (property === 'saturation' || property === 'brightness') && value !== ''
                ? Number(value).toFixed(3) : value;
            return true;
        }
    });
    panel.resetWrites = () => { writes = 0; };
    panel.writes = () => writes;
    return panel;
}

// Reproduce the actual native parsing error with the saved production source.
// This used to throw inside fitNativeSkills -> ApplyRuntime, before later HUD
// geometry (including inventory/stat panels) could finish assembling.
const beforePath = 'output/ultimate_tower_correction_20261009/before/' + dir + 'combat_stats.js';
if (fs.existsSync(beforePath)) {
    const oldSource = fs.readFileSync(beforePath,'utf8');
    const oldEnv = {abilityRuntime:()=>({ability_entindex:100,available:1}),
        validPortraitPanel:panel=>!!panel,abilityPanelStyleValue:(panel,key)=>String(panel.style[key]||'')};
    vm.runInNewContext(oldSource.slice(oldSource.indexOf('    function setAbilityRuntimeDisabled('),
        oldSource.indexOf('    function officialAbilityButtonAnchor(')),oldEnv);
    const slot=makePanel('OldAbility',t.root);makePanel('AbilityImage',slot);
    let assembled=false;
    assert.throws(()=>{oldEnv.applyAbilityRuntime(slot,100);assembled=true;},/Failed to parse style value for washColor: none/);
    assert.equal(assembled,false,'old invalid color prevents remaining HUD assembly');
}

for (let index = 0; index < names.length; index++) {
    const ability = 100 + index;
    const slot = makePanel('Ability' + index, t.root);
    const icon = makePanel('AbilityImage', slot, {saturation:'0.000', brightness:'0.450', washColor:'#666666'});
    const bevel = makePanel('AbilityBevel', slot, {washColor:'#000000bb'});
    const border = makePanel('ActiveAbilityBorder', slot, {brightness:'0.200'});
    const cooldown = makePanel('CooldownOverlay', slot, {opacity:'0.65', clip:'radial(50% 50%,0deg,200deg)'});
    slot.classes.no_level = true; // Native engine owns this class, not our code.
    t.runtime[ability] = {ability_entindex:ability, ability_name:names[index], owner_entindex:7,
        available:1, prerequisite_met:1, can_afford:0, passive:index < 2 ? 1 : 0};
    t.api.applyAbilityRuntime(slot, ability);
    assert.equal(Number(icon.style.saturation), 1, names[index] + ' restores saturation');
    assert.equal(Number(icon.style.brightness), 1, names[index] + ' restores brightness');
    assert.equal(icon.style.washColor, 'rgba(255,255,255,1)', names[index] + ' clears native wash tint');
    assert.equal(bevel.style.washColor, 'rgba(0,0,0,0)', names[index] + ' clears unlearned dark bevel');
    assert.equal(Number(border.style.brightness), 1);
    assert.equal(cooldown.style.opacity, '0.65', 'real cooldown stays visible');
    assert.equal(slot.hittest, true, 'passives retain tooltip access');
    const nodes = [slot, icon, bevel, border, cooldown];
    nodes.forEach(node => node.resetWrites());
    for (let frame = 0; frame < 40; frame++) t.api.applyAbilityRuntime(slot, ability);
    assert.equal(nodes.reduce((sum,node) => sum + node.writes(), 0), 0,
        'canonical native color strings must not cause stable style writes');

    // Hover is independent from activation; keep its brightness while removing
    // native tint. An actual learning lock still wins over both.
    icon.__survivalRuntimeHoverAbility = ability;
    t.api.applyAbilityRuntime(slot, ability);
    assert.equal(Number(icon.style.saturation), 1.35);
    t.runtime[ability].prerequisite_met = 0;
    t.api.applyAbilityRuntime(slot, ability);
    assert.equal(Number(icon.style.saturation), 0);
    assert.equal(Number(icon.style.brightness), 0.45);
    assert.equal(bevel.style.washColor, '#000000bb', 'real prerequisite retains its unlearned bevel');
    assert.equal(slot.classes.DOTADisabled, true);

    // A reused slot without a matching runtime returns every owned property.
    t.runtime[ability] = {};
    t.api.applyAbilityRuntime(slot, ability);
    assert.equal(icon.style.washColor, '#666666');
    assert.equal(Number(icon.style.saturation), 0);
    assert.equal(Number(icon.style.brightness), 0.45);
    assert.equal(Number(border.style.brightness), 0.2);
    assert.equal(bevel.style.washColor, '#000000bb');
    assert.equal(slot.classes.DOTADisabled, false);
    nodes.forEach(node => node.resetWrites());
    for (let frame = 0; frame < 40; frame++) t.api.applyAbilityRuntime(slot, ability);
    assert.equal(nodes.reduce((sum,node) => sum + node.writes(), 0), 0);

    // Explicit cleanup must restore an unlocked managed image too, not just
    // the old disabled branch. This protects unknown/native ability reuse.
    t.runtime[ability] = {ability_entindex:ability, available:1};
    t.api.applyAbilityRuntime(slot, ability);
    t.api.restoreAbilityRuntime(slot);
    assert.equal(icon.style.washColor, '#666666');
    assert.equal(Number(border.style.brightness), 0.2);
}

// First-use getters may be empty; surviving panels may also carry the previous
// CSS-only "none" spelling. Both must restore safely through the native setter.
for (const original of ['', 'none', '#1569be', 'rgba(21,105,190,1)']) {
    const slot=makePanel('RestoreAbility',t.root);
    const icon=makePanel('AbilityImage',slot,{saturation:'',brightness:'',washColor:original});
    t.runtime[100]={ability_entindex:100,available:1};
    assert.doesNotThrow(()=>t.api.applyAbilityRuntime(slot,100));
    assert.equal(icon.style.washColor,'rgba(255,255,255,1)');
    assert.doesNotThrow(()=>t.api.restoreAbilityRuntime(slot));
    assert.equal(Number(icon.style.saturation),1);assert.equal(Number(icon.style.brightness),1);
    assert.equal(icon.style.washColor,original&&original!=='none'?original:'rgba(255,255,255,1)');
    // Once cleanup relinquishes ownership, another native refresh must not
    // keep writing either the default color or numeric properties.
    t.runtime[100]={};icon.resetWrites();t.api.applyAbilityRuntime(slot,100);
    assert.equal(icon.writes(),0);
}

function fn(source, name) {
    const start = source.indexOf('    function ' + name + '(');
    assert(start >= 0, 'missing production function ' + name);
    const end = source.indexOf('\n    function ', start + 1);
    return source.slice(start, end < 0 ? source.length : end);
}
let runtime = {}, casts = 0;
const abilities = {GetBehavior:() => behavior, IsPassive:() => enginePassive,
    GetAbilityName:() => names[0], IsHidden:() => false};
const inputEnv = {readTooltipTable:() => runtime, unitOwnsAbility:() => true, selectedUnit:() => 7,
    $:{Msg(){}}, Abilities:abilities, GameUI:{CustomUIConfig:() => ({})},
    selectedEntindexesForRequest:() => [7],
    GameEvents:{SendCustomGameEventToServer:() => { casts++; }}};
// Stop before registration so these are the actual fallback functions only.
vm.runInNewContext(tooltip.slice(tooltip.indexOf('    function isPassiveAbility('),
    tooltip.indexOf('    GameUI.CustomUIConfig().SurvivalAbilityInput =')), inputEnv);
const env = {
    runtimeFor:() => runtime, Abilities:abilities, selectedUnit:() => 7,
    selectedUnitName:() => 'building_arrow_tower', utilityHotkeys:{}, hotkeys:['Q','W','E'],
    unitAbilityCount:() => 1, Entities:{GetAbility:() => 100}, utilityDisplayOrder:{},
    config:{SurvivalAbilityInput:{ExecuteAbility:() => { casts++; }}},
    abilityLevel:() => 1, manaCost:() => 0, cooldownRemaining:() => 0, cooldownLength:() => 0
};
for (const name of ['isPassiveAbility', 'hotkeyForEntry', 'visibleAbilities', 'activate', 'updateSlot']) {
    vm.runInNewContext(fn(takeover, name), env);
}
const panel = {style:{}, classes:{}, SetHasClass(name,value){this.classes[name] = value;}};
const fallback = {panel, image:{style:{}}, hotkey:{}, level:{}, mana:{}, cooldown:{}, shade:{style:{}}};
const entry = {ability:100, name:names[0], standardHotkeyIndex:0};
for (const signal of ['behavior', 'server', 'engine']) {
    runtime = {ability_entindex:100, owner_entindex:7, available:1, prerequisite_met:1,
        passive:signal === 'server' ? 1 : 0};
    behavior = signal === 'behavior' ? 2 : 4;
    enginePassive = signal === 'engine';
    casts = 0;
    assert.equal(inputEnv.executeAbility(100), false, signal + ' blocks fallback dispatcher');
    env.activate(entry);
    assert.equal(casts, 0, signal + ' blocks custom slot click');
    assert.equal(env.hotkeyForEntry(entry), '', signal + ' has no fallback hotkey');
    assert.equal(env.visibleAbilities()[0].standardHotkeyIndex, -1, signal + ' consumes no Q/W slot');
    env.updateSlot(fallback, entry, 0);
    assert.equal(panel.classes.Passive, true);
    assert.equal(panel.classes.Unavailable, false, signal + ' remains colored');
    assert.equal(panel.enabled, true, 'tooltip remains enabled');
}
runtime.passive = 0; behavior = 4; enginePassive = false;
casts = 0;
assert.equal(inputEnv.executeAbility(100), true);
env.activate(entry);
assert.equal(casts, 2, 'active reuse still executes');
assert.equal(env.hotkeyForEntry(entry), 'Q');
console.log('TOWER_PASSIVE_ICONS_PASS: actual 2-passive/3-tool tower, wash/bevel/border restoration, prerequisite-only gray, hover, cooldown retention, native reuse, canonical zero-write refresh and all passive input signals');
