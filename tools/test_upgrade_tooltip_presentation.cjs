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
    const h = env.createHarness({abilityNames:['ability_upgrade_tower_lv01'], panelCount:1, fields, ...options});
    h.runUntil(1.2);
    const binding = h.inspect().bindings[0], xy = binding.proxy.GetPositionWithinWindow();
    h.setCursor([xy.x + 10, xy.y + 10]);
    binding.proxy.events.onmouseover();
    assert(!h.tooltip.BHasClass('Hidden'));
    return {h, rows:() => Array.from(h.fieldContainer().__fieldRows).filter(row => row.visible)};
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
console.log('UPGRADE_TOOLTIP_PRESENTATION_PASS: endpoint comparisons, zero-cost hiding, compact w units, aligned pooled fields');
