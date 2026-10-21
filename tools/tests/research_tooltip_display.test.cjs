'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const project = path.resolve(__dirname, '../..');
const tools = path.join(project, 'tools');

// Exercise the actual selective-owner render/refresh through its hover proxy.
// The shared fixture exposes observations without replacing rendering code.
const recovery = fs.readFileSync(path.join(tools, 'test_ability_tooltip_recovery.cjs'), 'utf8');
const end = recovery.indexOf('// An identical deterministic workload');
const returned = '        config, counters, logs, work, abilityReads, executions, queue, tooltip, layer, setTable,';
assert(end > 0 && recovery.includes(returned));
const fixture = {require, __dirname: tools, process, console};
vm.runInNewContext(recovery.slice(0, end).replace(returned, returned.replace('config,', 'environment, config,'))
    + '\nthis.makeHarness = createHarness;', fixture);

const detailFields = [
    {label: '等级上限', value: 10}, {label: '当前累计', value: '尚未生效'},
    {label: '升级后累计', value: '攻击速度+5%'}, {label: '前置条件', value: '无'}
];
const oldDescription = '所有伐木工：每级攻击速度+5%。当前Lv.0：尚未生效。升级至Lv.1：攻击速度+5%。'
    + '即时刷新当前与后续训练的伐木工。\n加入研究队列，开始研究时扣费。';
const base = {
    owner_entindex: 827, ability_entindex: 828, research_upgrade: 1,
    available: 1, prerequisite_met: 1, can_afford: 1, current_level: 0,
    cost_wood: 200, cost_gold: 0, resource_check_on_cast: 1,
    research_status_code: 'available', fields: detailFields,
    cost_timing_text: '开始研究时扣费，排队未扣费',
    auto_research_available: 1, auto_research_enabled: 1,
    upgrade_description: oldDescription
};

function makeHarness(overrides = {}) {
    const unitNames = {827: 'building_research_lab'};
    const h = fixture.makeHarness({unitNames, panelCount: 1,
        unitAbilityNames: {827: ['ability_research_lumberjack_speed']}});
    // Model a missing localization token, which caused the English footer.
    h.environment.$.Localize = token => token;
    h.setTable('survival_ability_runtime', 828, {...base, ...overrides});
    h.runUntil(1.2);
    const binding = h.inspect().bindings[0];
    const xy = binding.proxy.GetPositionWithinWindow();
    h.setCursor([xy.x + 10, xy.y + 10]); binding.proxy.events.onmouseover();
    assert(!h.tooltip.BHasClass('Hidden'));
    return {h, unitNames,
        node: id => h.tooltip.FindChildTraverse(id),
        update: change => h.setTable('survival_ability_runtime', 828, {...base, ...change}, true),
        rows: () => Array.from(h.fieldContainer().__fieldRows || []).filter(row => row.visible)};
}

function resolved(panel, property) {
    const css = fs.readFileSync(path.join(project, 'panorama/src/styles/custom_game/ability_tooltip.css'), 'utf8')
        .replace(/\/\*[\s\S]*?\*\//g, '');
    function atom(node, selector) {
        const id = /#([\w-]+)/.exec(selector);
        return node && (!id || node.id === id[1])
            && Array.from(selector.matchAll(/\.([\w-]+)/g)).every(match => node.BHasClass(match[1]));
    }
    function matches(node, selector) {
        const parts = selector.split(/\s+/);
        if (!atom(node, parts.pop())) return false;
        while (parts.length) {
            const part = parts.pop(); node = node.GetParent();
            while (node && !atom(node, part)) node = node.GetParent();
            if (!node) return false;
        }
        return true;
    }
    let result, specificity = -1;
    for (const rule of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
        const declaration = new RegExp('(?:^|;)\\s*' + property + '\\s*:\\s*([^;]+)').exec(rule[2]);
        if (!declaration) continue;
        for (const selector of rule[1].split(',').map(value => value.trim())) {
            if (!matches(panel, selector)) continue;
            const weight = (selector.match(/#/g) || []).length * 100 + (selector.match(/\./g) || []).length * 10;
            if (weight >= specificity) { specificity = weight; result = declaration[1].trim(); }
        }
    }
    return panel.style[property.replace(/-([a-z])/g, (_, char) => char.toUpperCase())] || result;
}

function onlyCurrentRow(f, expected) {
    const rows = f.rows(); assert.equal(rows.length, 1, 'research retains only its current total row');
    assert.equal(rows[0].__left.text, '当前累计');
    assert.equal(rows[0].__right.text, expected);
    assert(rows[0].BHasClass('AbilityResearchCurrentRow'));
    assert.equal(resolved(rows[0].__iconHost, 'visibility'), 'collapse', 'current total has no empty icon gutter');
    assert.equal(resolved(rows[0].__left, 'width'), 'fit-children', 'label has no fixed-width blank stat column');
    assert.equal(resolved(rows[0].__left, 'text-align'), 'left');
    assert.equal(resolved(rows[0].__right, 'text-align'), 'left');
    assert.equal(resolved(rows[0], 'horizontal-align'), 'left');
}

test('an old research snapshot is compact, split by effect state and fully Chinese', () => {
    const f = makeHarness();
    assert.equal(f.node('CustomAbilityDescription').text,
        '所有伐木工：每级攻击速度+5%。\n当前Lv.0：尚未生效。\n升级后Lv.1：攻击速度+5%。');
    onlyCurrentRow(f, '尚未生效');
    assert.equal(f.node('CustomAbilityWoodCost').text, '200');
    assert(!f.node('CustomAbilityWoodCostBlock').BHasClass('Hidden'));
    assert.equal(f.node('CustomAbilityLevel').text, '等级 0');
    assert.equal(f.node('CustomAbilityStatus').text, '可研究');
    assert.equal(f.node('CustomAbilityType').text, '');
    assert(!f.h.tooltip.BHasClass('Unavailable'));
});

test('new multiline snapshots keep useful gameplay rules and update while hovered', () => {
    const f = makeHarness();
    const description = '所有伐木工：每级攻击间隔缩短+0.02秒。攻击间隔最低为0.05秒。'
        + '\n当前Lv.2：攻击间隔缩短+0.04秒。\n升级后Lv.3：攻击间隔缩短+0.06秒。';
    f.update({upgrade_description: description, current_level: 2, cost_wood: 500, fields: []});
    assert.equal(f.node('CustomAbilityDescription').text, description);
    assert.equal(f.node('CustomAbilityLevel').text, '等级 2');
    assert.equal(f.node('CustomAbilityWoodCost').text, '500');
    onlyCurrentRow(f, '攻击间隔缩短+0.04秒');
    const created = f.h.counters.created;
    for (let i = 0; i < 10; i++) f.update({upgrade_description: description, fields: detailFields});
    assert.equal(f.h.counters.created, created, 'old detail snapshots cannot reallocate removed rows');
});

test('structured effect lines override old descriptions and max-level snapshots omit a duplicate next line', () => {
    const f = makeHarness({research_effect_description: '所有防御塔：每级攻击力+100。',
        current_effect_text: '当前Lv.2：攻击力+200。', next_effect_text: '升级后Lv.3：攻击力+300。'});
    assert.equal(f.node('CustomAbilityDescription').text,
        '所有防御塔：每级攻击力+100。\n当前Lv.2：攻击力+200。\n升级后Lv.3：攻击力+300。');
    onlyCurrentRow(f, '攻击力+200');
    f.update({research_effect_description: '所有防御塔：每级攻击力+100。',
        current_effect_text: '当前Lv.10：攻击力+1000。', next_effect_text: '',
        research_status_code: 'max_level', available: 0, current_level: 10});
    assert.equal(f.node('CustomAbilityDescription').text,
        '所有防御塔：每级攻击力+100。\n当前Lv.10：攻击力+1000。');
    onlyCurrentRow(f, '攻击力+1000');
    assert.equal(f.node('CustomAbilityStatus').text, '已达最高等级');
    f.update({upgrade_description: '所有防御塔：每级攻击力+100%。当前Lv.10：攻击力+1000。'
        + '升级至Lv.10：攻击力+1000。即时刷新当前与后续建造的防御塔。',
        research_status_code: 'max_level', available: 0, current_level: 10});
    assert.equal(f.node('CustomAbilityDescription').text,
        '所有防御塔：每级攻击力+100%。\n当前Lv.10：攻击力+1000。');
});

test('legacy implementation notes are removed while useful constraints stay on the first line', () => {
    const f = makeHarness({upgrade_description: '所有伐木工：每级攻击间隔缩短+0.02秒。'
        + '当前Lv.0：尚未生效。升级至Lv.1：攻击间隔缩短+0.02秒。攻击间隔最低为0.05秒。'
        + '\n加入研究队列，开始研究时扣费。'});
    assert.equal(f.node('CustomAbilityDescription').text,
        '所有伐木工：每级攻击间隔缩短+0.02秒。攻击间隔最低为0.05秒。'
        + '\n当前Lv.0：尚未生效。\n升级后Lv.1：攻击间隔缩短+0.02秒。');
    f.update({upgrade_description: '所有城墙：每级最大生命+5%。当前Lv.0：尚未生效。'
        + '升级至Lv.1：最大生命+5%。提升基础最大生命，刷新时保持当前生命比例。'});
    assert.equal(f.node('CustomAbilityDescription').text,
        '所有城墙：每级最大生命+5%。\n当前Lv.0：尚未生效。\n升级后Lv.1：最大生命+5%。');
});

test('research status codes never fall back to English and unavailable states remain red', () => {
    const f = makeHarness();
    const cases = [
        ['available', '可研究', 1], ['syncing', '正在同步科技信息', 0],
        ['max_level', '已达最高等级', 0], ['researching_current', '研究中', 0],
        ['researching_other', '此研究所已有科技正在研究', 0],
        ['prerequisite_not_met', '前置条件未满足', 0],
        ['queue_available', '可加入研究队列', 1],
        ['queue_waiting_prerequisite', '等待前置科技完成', 0],
        ['research_queue_full', '研究队列已满', 0], ['queued_max_level', '已排队至最高等级', 0],
        ['future_unavailable_status', '暂不能研究', 0]
    ];
    for (const [code, expected, available] of cases) {
        f.update({research_status_code: code, available, status_text: 'Available to research'});
        assert.equal(f.node('CustomAbilityStatus').text, expected, code);
        assert.equal(f.h.tooltip.BHasClass('Unavailable'), available === 0, code);
        assert.equal(f.node('CustomAbilityType').text, '', code);
    }
    f.update({can_afford: 0, resource_check_on_cast: 0});
    assert.equal(f.node('CustomAbilityStatus').text, '资源不足，暂不能研究');
    assert(f.h.tooltip.BHasClass('ResourceLow'));
});

test('research filtering does not remove descriptions or fields from other managed skills', () => {
    const f = makeHarness();
    f.unitNames[827] = 'building_city';
    f.h.replaceFirstAbility(9001, 'ability_upgrade_city');
    f.h.setTable('survival_ability_runtime', 9001, {
        owner_entindex: 827, ability_entindex: 9001, available: 1,
        prerequisite_met: 1, can_afford: 1, current_level: 1,
        upgrade_description: oldDescription, fields: detailFields,
        status_text: '可升级'
    });
    f.h.runUntil(f.h.now() + 1.3);
    const binding = f.h.inspect().bindings[0];
    const xy = binding.proxy.GetPositionWithinWindow();
    f.h.setCursor([xy.x + 10, xy.y + 10]); binding.proxy.events.onmouseover();
    assert.equal(f.node('CustomAbilityDescription').text, oldDescription);
    assert.deepEqual(f.rows().map(row => row.__left.text), detailFields.map(field => field.label));
    assert(f.rows().every(row => !row.BHasClass('AbilityResearchCurrentRow')),
        'pooled rows clear research-only formatting when another ability is hovered');
    assert.equal(f.node('CustomAbilityStatus').text, '可升级');
});
