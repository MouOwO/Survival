'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const project = path.resolve(__dirname, '../..');
const tools = path.join(project, 'tools');
const scriptDirectory = path.join(project, 'panorama/src/scripts/custom_game');

// Reuse the complete selective-owner fixture. Its instrumentation observes
// binding work/state; production rendering, hover and update logic stay intact.
const recovery = fs.readFileSync(path.join(tools, 'test_ability_tooltip_recovery.cjs'), 'utf8');
const recoveryEnd = recovery.indexOf('// An identical deterministic workload');
assert(recoveryEnd > 0);
const recoveryReturn = '        config, counters, logs, work, abilityReads, executions, queue, tooltip, layer, setTable,';
assert(recovery.includes(recoveryReturn));
const selectiveEnv = {require, __dirname: tools, process, console};
vm.runInNewContext(recovery.slice(0, recoveryEnd).replace(recoveryReturn, recoveryReturn.replace('config,', 'environment, config,'))
    + '\nthis.makeHarness = createHarness;', selectiveEnv);

const localization = new Map(Array.from(fs.readFileSync(path.join(project, 'resource/addon_schinese.txt'), 'utf8')
    .matchAll(/"([^"\r\n]+)"\s+"([^"\r\n]*)"/g), match => [match[1], match[2]]));
function localize(token) { return localization.get(String(token).replace(/^#/, '')) || token; }

// This resolves only the simple selector/property subset used by the actual
// tooltip stylesheet. It verifies native layout contracts, not rendered pixels.
const css = fs.readFileSync(path.join(project, 'panorama/src/styles/custom_game/ability_tooltip.css'), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
const rules = Array.from(css.matchAll(/([^{}]+)\{([^{}]*)\}/g), match => ({selectors: match[1].split(',').map(s => s.trim()), body: match[2]}));
function atom(panel, selector) {
    if (!panel || !/^[#.\w-]+$/.test(selector)) return false;
    const tag = /^[\w-]+/.exec(selector), id = /#([\w-]+)/.exec(selector);
    if (tag && panel.paneltype !== tag[0]) return false;
    if (id && panel.id !== id[1]) return false;
    return Array.from(selector.matchAll(/\.([\w-]+)/g)).every(match => panel.BHasClass(match[1]));
}
function matches(panel, selector) {
    const parts = selector.split(/\s+/); let current = panel;
    if (!atom(current, parts.pop())) return false;
    while (parts.length) {
        const part = parts.pop(); current = current.GetParent();
        while (current && !atom(current, part)) current = current.GetParent();
        if (!current) return false;
    }
    return true;
}
function resolved(panel, property) {
    let result, weight = -1;
    for (const rule of rules) for (const selector of rule.selectors) {
        if (!matches(panel, selector)) continue;
        const declaration = new RegExp('(?:^|;)\\s*' + property + '\\s*:\\s*([^;]+)').exec(rule.body);
        if (!declaration) continue;
        const specificity = (selector.match(/#/g) || []).length * 100 + (selector.match(/\./g) || []).length * 10;
        if (specificity >= weight) { weight = specificity; result = declaration[1].trim(); }
    }
    const inline = panel.style[property.replace(/-([a-z])/g, (_, char) => char.toUpperCase())];
    return inline === undefined ? result : String(inline);
}
function node(h, id) { const panel = h.tooltip.FindChildTraverse(id); assert(panel, id + ' exists'); return panel; }
function rows(h) { return Array.from(h.fieldContainer().__fieldRows).filter(row => row.visible); }
function noUnlockRows(h) { assert(rows(h).every(row => row.__left.text.trim() !== '解锁条件'), 'all selective-owner paths omit the standalone unlock row'); }
function statusPreserved(tooltip, text, locked) {
    const status = tooltip.FindChildTraverse('CustomAbilityStatus');
    assert.equal(status.text, text); assert.equal(tooltip.BHasClass('Unavailable'), locked);
    assert.notEqual(resolved(status, 'visibility'), 'collapse');
    assert.equal(resolved(status, 'color'), locked ? '#d28f8f' : '#8fd28f', 'the bottom status keeps its actual red/green presentation');
}
function hover(h) {
    const binding = h.inspect().bindings[0]; assert(binding, 'the real managed ability has a hover binding');
    const xy = binding.proxy.GetPositionWithinWindow(); h.setCursor([xy.x + 10, xy.y + 10]);
    binding.proxy.events.onmouseover(); assert(!h.tooltip.BHasClass('Hidden')); noUnlockRows(h);
}
function leftAligned(h, row) {
    assert.equal(resolved(node(h, 'CustomAbilityCostRow'), 'horizontal-align'), 'left');
    assert.equal(resolved(row.__left, 'text-align'), 'left');
    assert.equal(resolved(row.__right, 'text-align'), 'left');
}

const fields = [{label: '木材消耗', value: '100'}, {label: '解锁条件', value: '主城等级≥2'}, {label: '生命', value: '1000'}];
const base = {owner_entindex: 827, ability_entindex: 828, available: 1, prerequisite_met: 1,
    current_level: 1, can_afford: 1, cost_gold: 0, cost_wood: 100, fields};
const unitNames = {827: 'npc_survival_builder_proxy', 900: 'npc_dota_hero_doom_bringer'};
let nativeLevel = 1;
const h = selectiveEnv.makeHarness({unitNames, unitAbilityNames: {
    827: ['ability_build_wall'], 900: ['ability_survival_earth_line']}, panelCount: 1,
    abilities: {GetLevel: () => nativeLevel}});
h.environment.$.Localize = localize;
h.setTable('survival_hero_skills', 'player_0', {unit_entindex: 900});
h.setTable('survival_ability_runtime', 828, base); h.runUntil(1.2); hover(h);
assert(h.tooltip.BHasClass('BuildAbility'));
assert.equal(node(h, 'CustomAbilityLevel').text, '');
assert.equal(resolved(node(h, 'CustomAbilityLevel'), 'visibility'), 'collapse', 'construction does not retain an empty level label margin');
assert.equal(node(h, 'CustomAbilityType').text, '', 'the normal ready state does not display the localized 可升级 badge');
assert.equal(node(h, 'CustomAbilityWoodCost').text, '100');
assert(node(h, 'CustomAbilityGoldCostBlock').BHasClass('Hidden'), 'zero gold stays absent');
const originalRows = rows(h);
assert.equal(originalRows.length, 2, 'the independent unlock field is removed without deleting wood or health');
for (const row of originalRows.slice(0, 1)) {
    assert(row.BHasClass('AbilityFieldTextRow')); assert.equal(resolved(row.__iconHost, 'visibility'), 'collapse', 'text-only construction requirements have no 26px placeholder gutter');
    leftAligned(h, row);
}
assert(!originalRows[1].BHasClass('AbilityFieldTextRow'));
assert.notEqual(resolved(originalRows[1].__iconHost, 'visibility'), 'collapse');
assert.equal(originalRows[1].__iconHost.visible, true, 'real construction property artwork remains visible');
assert.notEqual(originalRows[1].__iconHost.style.opacity, '0');
for (const [locked, text] of [[true, '需要主城等级2'], [false, '可建造'], [true, '需要先建造主城']]) {
    h.setTable('survival_ability_runtime', 828, {...base, available: locked ? 0 : 1, prerequisite_met: locked ? 0 : 1, status_text: text}, true);
    statusPreserved(h.tooltip, text, locked); noUnlockRows(h); assert.equal(rows(h).length, 2);
}

// NetTable refreshes reuse each pooled row, including when a former text-only
// row acquires real artwork and when that artwork is replaced by text again.
const reordered = [fields[2], fields[1], fields[0]];
h.setTable('survival_ability_runtime', 828, {...base, fields: reordered}, true);
assert.strictEqual(rows(h)[0], originalRows[0]); assert(!rows(h)[0].BHasClass('AbilityFieldTextRow'));
assert.notEqual(resolved(rows(h)[0].__iconHost, 'visibility'), 'collapse');
assert(rows(h)[1].BHasClass('AbilityFieldTextRow')); assert.equal(resolved(rows(h)[1].__iconHost, 'visibility'), 'collapse'); noUnlockRows(h);
const allocated = h.counters.created;
for (let i = 0; i < 20; i++) h.setTable('survival_ability_runtime', 828, {...base, fields: reordered}, true);
assert.equal(h.counters.created, allocated, 'compact presentation does not recreate field panels during stable hover');

let ability = 9001;
function replace(name, runtime) {
    h.replaceFirstAbility(ability, name);
    h.setTable('survival_ability_runtime', ability, {...base, ability_entindex: ability, ...runtime});
    h.runUntil(h.now() + 1.3); hover(h); return ability++;
}
unitNames[827] = 'building_city';
const upgrade = replace('ability_upgrade_city', {current_level: 3});
assert(!h.tooltip.BHasClass('BuildAbility')); assert(node(h, 'CustomAbilityLevel').text.endsWith(' 3'));
assert.notEqual(resolved(node(h, 'CustomAbilityLevel'), 'visibility'), 'collapse', 'ordinary upgrade level is restored after construction');
assert.equal(node(h, 'CustomAbilityType').text, '');
assert.strictEqual(rows(h)[0], originalRows[0]);
assert.notEqual(resolved(rows(h)[0].__iconHost, 'visibility'), 'collapse', 'construction-only CSS cannot override ordinary upgrade gutter behavior');
for (const [extra, token] of [
    [{upgrade_in_progress: 1}, 'Survival_UpgradeTooltip_InProgress'],
    [{prerequisite_met: 0}, 'Survival_UpgradeTooltip_Unavailable'],
    [{can_afford: 0}, 'Survival_UpgradeTooltip_ResourceLow'],
    [{}, null]
]) {
    h.setTable('survival_ability_runtime', upgrade, {...base, ability_entindex: upgrade, current_level: 3, ...extra}, true);
    assert.equal(node(h, 'CustomAbilityType').text, token ? localization.get(token) : '', 'only the generic ready/可升级 type is removed');
}
unitNames[827] = 'building_research_lab';
replace('ability_research_lumberjack_speed', {research_upgrade: 1, current_level: 2, research_status_code: 'available'});
assert(!h.tooltip.BHasClass('BuildAbility')); assert(node(h, 'CustomAbilityLevel').text.endsWith(' 2'));
assert.notEqual(resolved(node(h, 'CustomAbilityLevel'), 'visibility'), 'collapse'); assert.equal(node(h, 'CustomAbilityType').text, '');
nativeLevel = 3;
h.setTable('survival_ability_runtime', 901, {owner_entindex: 900, ability_entindex: 901, available: 1,
    fields: [{label: 'LV1', value: '初级效果'}, {label: ' \t解锁条件 ', value: '英雄达到3级'}, {label: 'LV3', value: '当前效果'}]});
h.select(900); h.runUntil(h.now() + 1.3); hover(h);
assert(!h.tooltip.BHasClass('BuildAbility')); assert(node(h, 'CustomAbilityLevel').text.endsWith(' 3'));
assert.equal(rows(h).filter(row => row.BHasClass('AbilitySkillLevelCurrent')).length, 1, 'real hero levels retain their current-grade highlighting');
nativeLevel = 1; h.select(827); unitNames[827] = 'npc_survival_builder_proxy';
replace('ability_build_farm', {current_level: 1}); assert(h.tooltip.BHasClass('BuildAbility')); assert.equal(node(h, 'CustomAbilityLevel').text, '');
replace('ability_building_blink', {current_level: 1});
assert(!h.tooltip.BHasClass('BuildAbility'), 'building blink is an action, not a construction ability');
assert(node(h, 'CustomAbilityLevel').text.endsWith(' 1')); assert.equal(node(h, 'CustomAbilityType').text, '主动');

// The takeover fixture exposes the real owner before unrelated HUD survey loops.
// Reuse that seam; no show/render function body is replaced or reimplemented.
const takeoverFixture = fs.readFileSync(path.join(__dirname, 'hud_tooltip_dismiss.test.cjs'), 'utf8').replace(/\r\n/g, '\n');
const takeoverEnd = takeoverFixture.indexOf('\n{\n const h=harness();');
assert(takeoverEnd > 0);
const takeoverEnv = {require, console};
vm.runInNewContext(takeoverFixture.slice(0, takeoverEnd).replace("const dir='panorama/src/scripts/custom_game/';", 'const dir=' + JSON.stringify(scriptDirectory + path.sep) + ';')
    + '\nthis.makeHarness = harness;', takeoverEnv);
const t = takeoverEnv.makeHarness();
const ids = ['CustomAbilityTooltip', 'CustomAbilityFields', 'CustomAbilityExtensionLabel', 'CustomAbilityTitle', 'CustomAbilityLevel',
    'CustomAbilityDescription', 'CustomAbilityCostRow', 'CustomAbilityGoldCost', 'CustomAbilityWoodCost', 'CustomAbilityType', 'CustomAbilityStatus'];
ids.forEach(id => t.make(id));
const tip = t.nodes.CustomAbilityTooltip;
for (const id of ids.slice(1)) { const p = t.nodes[id]; p.parent.children = p.parent.children.filter(child => child !== p); p.parent = tip; tip.children.push(p); }
tip.position = {x: 300, y: 100}; tip.actuallayoutwidth = 337; tip.actuallayoutheight = 200;
let runtime = {}, takeoverLevel = 1, api;
t.env.$.Localize = localize;
t.env.Abilities.GetLevel = () => takeoverLevel;
t.env.CustomNetTables.GetTableValue = table => table === 'survival_ability_runtime' ? runtime : {};
t.env.__takeoverTooltip = value => { api = value; };
const takeoverSource = fs.readFileSync(path.join(scriptDirectory, 'hud_takeover.js'), 'utf8');
const seam = '    config.SurvivalAbilityTakeover = tooltipApi = {'; assert(takeoverSource.includes(seam));
t.load('hud_takeover.js', takeoverSource.replace(seam, '    __takeoverTooltip({Show:showTooltip,Hide:hideTooltip});return;\n' + seam));
const card = t.make('CompactTooltipAbility'); t.setCursor([110, 510]);
function showTakeover(name, extra = {}) {
    runtime = {...base, owner_entindex: 1, ability_entindex: 10, ...extra};
    api.Show({ability: 10, name}, card); assert(!tip.BHasClass('Hidden'));
    assert.equal(tip.__survivalTooltipOwner, 'full_takeover');
    assert.notEqual(t.nodes.CustomAbilityType.text, '可升级');
    assert(t.nodes.CustomAbilityFields.children.every(row => row.children[0].text.trim() !== '解锁条件'), name + ' omits the independent unlock field in full takeover');
}
showTakeover('ability_build_main_city');
assert(tip.BHasClass('BuildAbility')); assert.equal(t.nodes.CustomAbilityLevel.text, '');
assert.equal(resolved(t.nodes.CustomAbilityLevel, 'visibility'), 'collapse');
assert.equal(t.nodes.CustomAbilityWoodCost.text, '100'); assert.equal(resolved(t.nodes.CustomAbilityCostRow, 'horizontal-align'), 'left');
const woodRow = t.nodes.CustomAbilityFields.children.find(row => row.children[0].text === '木材消耗');
assert(woodRow); assert.equal(woodRow.children[1].text, '100');
assert.equal(woodRow.children.length, 2, 'full takeover has no invented icon gutter');
woodRow.children.forEach(p => assert.equal(resolved(p, 'text-align'), 'left'));
for (const [name, level] of [['ability_upgrade_city', 3], ['ability_research_lumberjack_speed', 2], ['ability_survival_earth_line', 4], ['ability_building_blink', 1]]) {
    takeoverLevel = level; showTakeover(name, {current_level: level});
    assert(!tip.BHasClass('BuildAbility'), name + ' clears stale construction styling');
    assert(t.nodes.CustomAbilityLevel.text.endsWith(' ' + level)); assert.notEqual(resolved(t.nodes.CustomAbilityLevel, 'visibility'), 'collapse');
}
showTakeover('ability_build_gold_mine', {available: 0, prerequisite_met: 0, status_text: '需要主城等级2'});
assert(tip.BHasClass('BuildAbility')); assert.equal(t.nodes.CustomAbilityLevel.text, '');
statusPreserved(tip, '需要主城等级2', true);
showTakeover('ability_build_gold_mine', {available: 1, prerequisite_met: 1, status_text: '可建造', fields: [fields[0], {...fields[1], label: ' 解锁条件\t'}, fields[2]]});
statusPreserved(tip, '可建造', false);
showTakeover('ability_build_gold_mine', {available: 0, prerequisite_met: 0, status_text: '需要先建造主城'});
statusPreserved(tip, '需要先建造主城', true);
assert.equal(t.requests.length, 0, 'presentation tests never cast or buy');

console.log('ABILITY_TOOLTIP_COMPACT_PASS: both real owners; no standalone unlock rows; red/green status preserved; no generic ready badge; construction-only level/gutter suppression; retained icons/costs; upgrade/hero/research reuse; pooled refresh; scoped left alignment (no pixel simulation).');
