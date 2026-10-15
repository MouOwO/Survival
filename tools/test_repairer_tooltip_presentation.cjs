'use strict';
// Exercise the real tooltip module and pooled rows; CSS/layout contracts below
// supplement the engine mock, which does not render Panorama pixels.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const harnessSource = fs.readFileSync(path.join(__dirname, 'test_ability_tooltip_recovery.cjs'), 'utf8');
const end = harnessSource.indexOf('// An identical deterministic workload');
assert(end > 0, 'reuse the existing real-module tooltip harness');
const env = {require, __dirname, process, console};
vm.runInNewContext(harnessSource.slice(0, end) + '\nthis.createHarness = createHarness;', env);

const fields = [
    {label:'当前数量', value:'1/5'}, {label:'人口消耗', value:1},
    {label:'木材消耗', value:100}, {label:'金币消耗', value:0},
    {label:'修复效率', value:'1.7%最大生命/秒'},
    {label:'修理范围', value:600}, {label:'修复范围', value:600},
    {label:'训练上限', value:5},
];
const base = {owner_entindex:827, ability_entindex:828, available:1, prerequisite_met:1,
    can_afford:1, resource_check_on_cast:1, population:1, cost_wood:100, cost_gold:0,
    upgrade_description:'训练一名修理工，自动修复受损城墙。', status_text:'当前修理工数量 1/5', fields};
function node(h, id) {return assertNode(h.tooltip.FindChildTraverse(id), id);}
function assertNode(panel, id) {assert(panel, 'missing real tooltip component ' + id); return panel;}
function hover(h) {
    const binding = h.inspect().bindings[0];assert(binding, 'the managed ability remains hoverable');
    const xy = binding.proxy.GetPositionWithinWindow();h.setCursor([xy.x + 10, xy.y + 10]);
    binding.proxy.events.onmouseover();assert(!h.tooltip.BHasClass('Hidden'));
}
function show(name, runtime = base) {
    const h = env.createHarness({unitName:'building_main_city', abilityNames:[name], panelCount:1});
    h.setTable('survival_ability_runtime', 828, runtime);h.runUntil(1.2);hover(h);return h;
}
function labels(h) {
    return Array.from(h.fieldContainer().__fieldRows).filter(row => row.visible).map(row => row.__left.text);
}
function hidden(h, id) {return node(h, id).BHasClass('Hidden');}

for (const name of ['ability_train_repairer', 'ability_train_advanced_repairer']) {
    const h = show(name);
    assert(h.tooltip.BHasClass('RepairerTraining'), name + ' uses the compact training presentation');
    assert.deepEqual(labels(h), ['修复效率'], 'hide only duplicate training metadata');
    const row = h.fieldContainer().__fieldRows.find(row => row.visible);
    assert.equal(row.__right.text, '1.7%最大生命/秒');
    assert.equal(node(h, 'CustomAbilityDescription').text, base.upgrade_description);
    assert.equal(node(h, 'CustomAbilityStatus').text, base.status_text, 'keep the useful bottom training status');
    assert.equal(hidden(h, 'CustomAbilityCostRow'), false);
    assert.equal(hidden(h, 'CustomAbilityWoodCostBlock'), false);
    assert.equal(hidden(h, 'CustomAbilityGoldCostBlock'), true);
    assert.equal(hidden(h, 'CustomAbilityPopulationCostBlock'), false);
    assert.equal(node(h, 'CustomAbilityWoodCost').text, '100');
    assert.equal(node(h, 'CustomAbilityPopulationCost').text, '1');
    h.setTable('survival_ability_runtime', 828, {...base, available:0, prerequisite_met:0, status_text:'修理工数量已达上限'}, true);
    assert(h.tooltip.BHasClass('Unavailable'));assert.equal(node(h, 'CustomAbilityStatus').text, '修理工数量已达上限');
    assert.deepEqual(labels(h), ['修复效率'], 'capacity status remains readable without duplicate capacity fields');

    // NetTable refreshes repaint the current hover without stale cost blocks.
    h.setTable('survival_ability_runtime', 828, {...base, population:0}, true);
    assert.equal(hidden(h, 'CustomAbilityPopulationCostBlock'), true);
    assert.equal(hidden(h, 'CustomAbilityWoodCostBlock'), false);
    assert.equal(hidden(h, 'CustomAbilityCostRow'), false);
    assert.strictEqual(h.fieldContainer().__fieldRows.find(row => row.visible), row, 'keep the existing field row pool');
    h.setTable('survival_ability_runtime', 828, {...base, population:0, cost_wood:0, cost_gold:0}, true);
    assert.equal(hidden(h, 'CustomAbilityCostRow'), true);
    h.setTable('survival_ability_runtime', 828, {...base, population:1, cost_wood:0, cost_gold:0}, true);
    assert.equal(hidden(h, 'CustomAbilityCostRow'), false, 'a population-only action still has a visible cost row');
    assert.equal(hidden(h, 'CustomAbilityPopulationCostBlock'), false);
    assert.equal(hidden(h, 'CustomAbilityWoodCostBlock'), true);assert.equal(hidden(h, 'CustomAbilityGoldCostBlock'), true);

    // The same tooltip instance must restore ordinary fields and its CSS scope.
    h.replaceFirstAbility(9001, 'ability_train_lumberjack');
    h.setTable('survival_ability_runtime', 9001, {...base, ability_entindex:9001});h.runUntil(2.6);hover(h);
    assert(!h.tooltip.BHasClass('RepairerTraining'));
    assert.deepEqual(labels(h), fields.map(field => field.label), 'ordinary training retains all its runtime fields');
    assert.equal(hidden(h, 'CustomAbilityPopulationCostBlock'), false, 'population costs also work outside repairer training');
}
for (const name of ['ability_upgrade_city', 'ability_train_lumberjack']) {
    const h = show(name, {...base, cost_wood:0, cost_gold:0});
    assert(!h.tooltip.BHasClass('RepairerTraining'));
    assert.deepEqual(labels(h), fields.map(field => field.label));
    assert.equal(hidden(h, 'CustomAbilityCostRow'), false);
    assert.equal(hidden(h, 'CustomAbilityPopulationCostBlock'), false);
}

// Both resources must be siblings in the actual horizontal cost row, not
// additional key/value field rows that happen to contain the same numbers.
const xml = fs.readFileSync(path.join(__dirname, '../panorama/src/layout/custom_game/survival_hud.xml'), 'utf8');
const rowStart = xml.indexOf('<Panel id="CustomAbilityCostRow"');
const rowEnd = xml.indexOf('<Panel id="CustomAbilityFields"', rowStart);
assert(rowStart >= 0 && rowEnd > rowStart);
const costMarkup = xml.slice(rowStart, rowEnd), children = [];
let depth = 0;
for (const tag of costMarkup.matchAll(/<(\/?)Panel\b([^>]*)>/g)) {
    if (tag[1]) {depth--;continue;}
    if (depth === 1) {const id = /\bid="([^"]+)"/.exec(tag[2]);if (id) children.push(id[1]);}
    if (!/\/\s*$/.test(tag[2])) depth++;
}
assert(children.includes('CustomAbilityWoodCostBlock'));assert(children.includes('CustomAbilityPopulationCostBlock'));
assert(/id="CustomAbilityPopulationCost"/.test(costMarkup), 'the XML includes the live population value');
const css = fs.readFileSync(path.join(__dirname, '../panorama/src/styles/custom_game/ability_tooltip.css'), 'utf8');
const rules = Array.from(css.matchAll(/([^{}]+)\{([^{}]*)\}/g), match => ({selectors:match[1].split(',').map(value => value.trim()), body:match[2]}));
function scopedRule(target, property, value) {
    return rules.some(rule => rule.selectors.some(selector => selector.includes('.RepairerTraining')
        && (selector.includes(target) || /\.RepairerTraining\s+Label$/.test(selector)))
        && new RegExp('(?:^|;)\\s*' + property + '\\s*:\\s*' + value + '\\s*(?:;|$)').test(rule.body));
}
assert(rules.some(rule => rule.selectors.includes('#CustomAbilityCostRow') && /flow-children:\s*right\s*;/.test(rule.body)));
assert(scopedRule('.AbilityFieldIcon', 'visibility', 'collapse'), 'repairer fields remove the empty icon gutter');
for (const target of ['#CustomAbilityDescription', '.AbilityFieldLabel', '.AbilityFieldValue']) {
    // Labels start with Panorama's normal left alignment. Relevant explicit
    // rules must preserve it; removing the icon gutter aligns their origins.
    let alignment = 'left';
    for (const rule of rules) {
        const applies = rule.selectors.some(selector => selector === target || selector === '#CustomAbilityTooltip Label'
            || (selector.includes('.RepairerTraining') && (selector.includes(target) || /\.RepairerTraining\s+Label$/.test(selector))));
        const declaration = /(?:^|;)\s*text-align\s*:\s*(\w+)\s*(?:;|$)/.exec(rule.body);
        if (applies && declaration) alignment = declaration[1];
    }
    assert.equal(alignment, 'left', target + ' retains left-aligned training text');
}
assert(!rules.some(rule => rule.selectors.includes('.AbilityFieldIcon') && /visibility:\s*collapse\s*;/.test(rule.body)),
    'other skill tooltips keep their established icon column');
console.log('REPAIRER_TOOLTIP_PRESENTATION_PASS: both exact training abilities, filtered duplicate metadata, retained efficiency/status, population/wood cost row, zero-cost refresh and population-only actions, ordinary fields and scoped left alignment; pixels not simulated');
