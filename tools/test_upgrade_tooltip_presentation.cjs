const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

// Reuse the real-module HUD harness without executing its independent recovery suite.
const harnessSource = fs.readFileSync(path.join(__dirname, 'test_ability_tooltip_recovery.cjs'), 'utf8');
const env = {require, __dirname, process, console};
vm.runInNewContext(harnessSource.slice(0, harnessSource.indexOf('// An identical deterministic workload'))
    + '\nthis.createHarness = createHarness;', env);

function show(fields, options = {}) {
    const {runtime, ...harnessOptions} = options;
    const h = env.createHarness({abilityNames:['ability_upgrade_city'], panelCount:1, fields, ...harnessOptions});
    if (runtime) h.setTable('survival_ability_runtime', 828,
        {owner_entindex:827, ability_entindex:828, available:1, fields, ...runtime});
    h.runUntil(1.2);
    const binding = h.inspect().bindings[0], xy = binding.proxy.GetPositionWithinWindow();
    h.setCursor([xy.x + 10, xy.y + 10]);
    binding.proxy.events.onmouseover();
    assert(!h.tooltip.BHasClass('Hidden'));
    return {h, rows:() => Array.from(h.fieldContainer().__fieldRows).filter(row => row.visible)};
}

const legacyTowerFields = [
    {label:'目标等级', value:2}, {label:'升级目标', value:'【N】见习守望'},
    {label:'攻击提升', value:'+79'}, {label:'攻击速度', value:'1 → 1.2 (+0.2)'},
    {label:'生命', value:'1000 → 2000 (+1000)'}, {label:'人口消耗', value:'1（当前占有3）'},
    {label:'等级', value:'1 → 2'}, {label:'模型状态', value:'changed'},
    {label:'自动升级', value:'右键升级图标开启，每秒检查一次'},
    {label:'前置条件', value:'英雄0转'}, {label:'路线数量', value:'0/5'}
];
for (const abilityName of ['ability_upgrade_tower', 'ability_upgrade_tower_lv01',
    'ability_upgrade_tower_lv02', 'ability_upgrade_tower_max']) {
    const target = abilityName.endsWith('_max') ? 'lvmax' : 'lv2';
    const status = '升级至【N】见习守望 ' + target;
    const tower = show(legacyTowerFields, {abilityNames:[abilityName], runtime:{
        current_level:1, display_current_level:1, cost_wood:100,
        upgrade_description:'按当前路线升级至下一等级。', status_text:status
    }});
    assert.deepEqual(tower.rows().map(row => row.__left.text), ['自动升级','前置条件','路线数量'],
        abilityName + ' hides cached upgrade details while retaining controls and requirements');
    const panel = id => tower.h.tooltip.FindChildTraverse(id);
    assert.equal(panel('CustomAbilityStatus').text, status, 'The server owns the complete target footer');
    assert.equal(panel('CustomAbilityLevel').text, 'Level 1', 'The current level stays in the header');
    assert.equal(panel('CustomAbilityDescription').text, '按当前路线升级至下一等级。');
    assert.equal(panel('CustomAbilityWoodCost').text, '100');
    assert(!panel('CustomAbilityWoodCostBlock').BHasClass('Hidden'), 'Upgrade costs remain visible');

    tower.h.setTable('survival_ability_runtime', 828, {owner_entindex:827, ability_entindex:828,
        available:1, fields:legacyTowerFields, status_text:'升级至【N】见习守望 lvmax'}, true);
    assert.equal(panel('CustomAbilityStatus').text, '升级至【N】见习守望 lvmax',
        'A final target also keeps lvmax on the single-level upgrade button');
    tower.h.setTable('survival_ability_runtime', 828, {owner_entindex:827, ability_entindex:828,
        available:0, prerequisite_met:0, fields:legacyTowerFields, status_text:'请先选择一个转职方向'}, true);
    assert.equal(panel('CustomAbilityStatus').text, '请先选择一个转职方向', 'An unavailable upgrade keeps its actual error');
    tower.h.setTable('survival_ability_runtime', 828, {owner_entindex:827, ability_entindex:828,
        available:1, upgrade_in_progress:1, fields:legacyTowerFields, status_text:'升级中（1秒）'}, true);
    assert.equal(panel('CustomAbilityStatus').text, 'Upgrade completes in 1 second', 'Upgrade progress remains visible');
    tower.h.setTable('survival_ability_runtime', 828, {owner_entindex:827, ability_entindex:828,
        available:1, can_afford:0, fields:legacyTowerFields, status_text:status}, true);
    assert.equal(panel('CustomAbilityStatus').text, 'Not enough resources · server validates the final cost',
        'Existing resource errors take precedence over the target footer');
    assert.deepEqual(tower.rows().map(row => row.__left.text), ['自动升级','前置条件','路线数量']);
}

const sample = show([
    {label:'目标等级', value:2}, {label:'升级目标', value:'【N】见习守望'},
    {label:'攻击提升', value:'+79'}, {label:'攻击速度', value:'1 → 1 (+0)'},
    {label:'人口消耗', value:'0'}
]);
assert.deepEqual(sample.rows().map(row => row.__left.text), ['目标等级', '升级目标', '攻击提升'],
    'An unchanged attack rate and zero population cost do not describe an upgrade');

const changing = show([
    {label:'攻击速度', value:'1.000 → 1 (+999)'},
    {label:'生命', value:'2000 → 450000 (+448000)'},
    {label:'护甲', value:'10 → 180 (+170)'},
    {label:'人口上限', value:'10 → 10 (+0)'},
    {label:'攻击提升', value:'+0'},
    {label:'人口消耗', value:'0（当前占有3）'},
    {label:'等级', value:'1-1 → 9-1'},
    {label:'前置条件', value:'英雄0转'},
    {label:'路线数量', value:'0/5'},
    {label:'模型状态', value:'unchanged'}
]);
assert.deepEqual(changing.rows().map(row => row.__left.text), ['生命','护甲','等级','前置条件','路线数量','模型状态'],
    'Compare actual endpoints, and retain meaningful metadata even when it contains zero');
assert.equal(changing.rows()[0].__right.text, '2000 → 45.0w (+44.8w)');
assert.equal(changing.rows()[1].__right.text, '10 → 180 (+170)');
assert.equal(changing.rows()[2].__right.text, '1-1 → 9-1');
assert(changing.rows()[0].BHasClass('AbilityNumericFieldRow'));
assert(!changing.rows()[3].BHasClass('AbilityNumericFieldRow'));
assert(changing.rows().every(row => row.__iconHost.visible), 'A reserved icon gutter aligns every ordinary value column');
assert.equal(changing.rows()[0].__iconHost.style.opacity, '1');
assert.equal(changing.rows()[2].__iconHost.style.opacity, '0');

const decimals = show([
    {label:'攻击速度', value:'1 → 1.001 (+0)'},
    {label:'攻击间隔缩短', value:'0.03秒 → 0.03秒 (+0秒)'},
    {label:'暴击率', value:'20% → 23%'},
    {label:'护甲', value:'10 → -10 (-20)'},
    {label:'每秒金币', value:'1e5 → 2e5 (+1e5)'},
    {label:'人口消耗', value:'2'},
    {label:'升级目标', value:'100000号守望'}
]);
assert.deepEqual(decimals.rows().map(row => row.__right.text), [
    '1 → 1.001 (+0)', '20% → 23%', '10 → -10 (-20)', '10.0w → 20.0w (+10.0w)', '2', '100000号守望'
], 'Small real changes, decreases, percentages, nonzero costs and names keep their meaning');

changing.h.setTable('survival_ability_runtime', 828, {owner_entindex:827, ability_entindex:828,
    available:1, cost_gold:143860, cost_wood:946000, fields:[{label:'生命', value:'450000 → 450000 (+0)'}]}, true);
assert.equal(changing.rows().length, 0, 'Refreshing a tooltip hides formerly visible unchanged rows');
assert.equal(changing.h.tooltip.FindChildTraverse('CustomAbilityGoldCost').text, '14.4w');
assert.equal(changing.h.tooltip.FindChildTraverse('CustomAbilityWoodCost').text, '94.6w');

const css = fs.readFileSync('panorama/src/styles/custom_game/ability_tooltip.css', 'utf8');
assert(/\.AbilityFieldValue\s*\{[^}]*width:\s*fill-parent-flow/.test(css), 'Value column has a bounded remaining width');
assert(/\.AbilityNumericFieldRow\s+\.AbilityFieldValue\s*\{[^}]*white-space:\s*nowrap/.test(css),
    'Numeric comparisons cannot wrap their delta onto another line');
console.log('UPGRADE_TOOLTIP_PRESENTATION_PASS: tower target footer, cached detail hiding, preserved controls, building stat formatting');
