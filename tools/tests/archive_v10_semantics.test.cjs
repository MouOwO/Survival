const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {csv} = require('../shop_ui_12h/catalog.cjs');
const repo = path.resolve(__dirname, '../..');
const source = fs.readFileSync(path.join(repo, 'panorama/src/scripts/custom_game/archive_v10_semantics.js'), 'utf8');
const catalog = csv(path.join(repo, 'data/csv/存档系统/archive_shadow_items.csv')).filter(row => row.enabled === '1').map(row => ({
    id: row.item_id, name: row.display_name, description: row.description, quality: row.quality,
    icon_style: row.icon_style, max_owned: Number(row.max_owned) > 0 ? Number(row.max_owned) : undefined
}));
assert.ok(catalog.length > 0, 'Tests must exercise the official project shadow catalog');
const cfg = {ArchiveV10Data: {catalog}};
const context = vm.createContext({GameUI: {CustomUIConfig: () => cfg}});
vm.runInContext(source, context);
const S = cfg.ArchiveV10Semantics;
const plain = value => JSON.parse(JSON.stringify(value));
const baseline = {ok: 1, rows: [{id: catalog[0].id, name: catalog[0].name, count: 2, unlocked: 0}]};
const before = JSON.stringify(baseline);
const joined = S.Normalize(baseline, 'shadow');
assert.equal(joined.length, catalog.length);
assert.equal(joined[0].unlocked, 1, 'One held shadow item is owned before reaching its holding cap');
assert.equal(joined[0].name, catalog[0].name);
assert.equal(joined[0].description, catalog[0].description);
assert.equal(joined[0].target, catalog[0].max_owned);
assert.equal(joined[1].count, 0, 'Complete sparse server snapshot omits zero-owned catalog items');
assert.equal(joined[1].unlocked, 0);
assert.equal(JSON.stringify(baseline), before, 'Normalization must not edit authoritative snapshots');
assert.equal(S.Quantity(joined[0], 'shadow'), '2/' + catalog[0].max_owned);
for (const data of [null, {}, {ok: 0, rows: []}, {ok: 1}, {ok: 1, rows: null}, {ok: 1, rows: [], delta: 1}]) {
    const loading = S.Normalize(data, 'shadow');
    assert.equal(loading[0].count_known, 0);
    assert.equal(loading[0].count, undefined);
    assert.equal(S.State(loading[0], 'shadow'), null, 'Unavailable or delta-only data is unknown, never zero');
    assert.ok(S.Quantity(loading[0], 'shadow').startsWith('—'));
}
for (const count of [undefined, null, '', ' ', '—', 'not-a-number', Infinity, NaN, -1, false]) {
    const row = S.Normalize({ok: 1, rows: [{id: catalog[0].id, count, unlocked: 0}]}, 'shadow')[0];
    assert.equal(row.count_known, 0);
    assert.equal(S.State(row, 'shadow'), null);
    assert.ok(S.Quantity(row, 'shadow').startsWith('—'));
}
for (const value of [0, '0', 1, '1', 9999]) {
    const row = S.Normalize({ok: true, rows: [{id: catalog[0].id, count: value, unlocked: value > 0 ? 0 : 1}]}, 'shadow')[0];
    assert.equal(row.count, Number(value));
    assert.equal(S.State(row, 'shadow'), Number(value) > 0);
}
const unavailable = S.Normalize({ok: 1, rows: [{id: catalog[0].id, count: 8, count_known: 0}]}, 'shadow')[0];
assert.equal(S.State(unavailable, 'shadow'), null);
const uncapped = S.Normalize({ok: 1, rows: [{id: catalog[0].id, count: 12, target: null}]}, 'shadow')[0];
assert.equal(S.Quantity(uncapped, 'shadow'), '12', 'Explicit runtime absence of cap overrides stale catalog cap');
const serverExtra = {id: 'official_future_shadow', name: '正式新增条目', count: 7, target: 100};
const more = S.Normalize({ok: 1, rows: baseline.rows.concat(serverExtra)}, 'shadow');
assert.equal(more.length, catalog.length + 1, 'Preview item count never limits real category capacity');
assert.equal(more.at(-1).id, serverExtra.id);

for (const category of ['clear', 'boss', 'gift', 'endless', 'starjoy_points']) {
    const row = {id: 'official-test', count: 25, target: 5, completed: 1, unlock_condition: '正式条件'};
    const normalized = S.Normalize({ok: 1, rows: [row]}, category);
    assert.deepEqual(plain(normalized), [row], 'Other full official rows stay unchanged: ' + category);
    assert.equal(S.Quantity(normalized[0], category), '25/5', 'Accumulated achievement count is never capped to target');
    assert.equal(S.State(normalized[0], category), true);
    assert.equal(S.State({...row, completed: 0}, category), false, 'Partial achievements do not activate merely from count > 0');
}
const mapInput = {ok: 1, online: {level: 2}, rows: [{id: 'map_05', rune: '5', count: 800, target: 1200, completed: 0}]};
const mapRow = S.Normalize(mapInput, 'map_level')[0];
assert.equal(mapRow.count, 800, 'Existing online-minute detail values remain untouched');
assert.equal(mapRow.target, 1200);
assert.equal(S.Quantity(mapRow, 'map_level'), 'LV2/5', 'Map milestone count uses actual current map level, not minutes');
assert.equal(S.State(mapRow, 'map_level'), false);
assert.equal(S.Quantity(S.Normalize({rows: [{rune: '5', count: 800, target: 1200}]}, 'map_level')[0], 'map_level'), 'LV—/5');
assert.equal(S.Metric({progress_kind: 'wave'}, 'endless'), '历史最高通关层数');
assert.equal(S.Metric({progress_kind: 'score'}, 'endless'), '累计无尽积分');
assert.equal(S.Metric({progress_kind: 'cooperative'}, 'gift'), '组队累计胜利次数');
assert.equal(S.Metric({}, 'boss'), '进攻BOSS击杀次数');

for (const category of ['building', 'work', 'fragment']) {
    assert.equal(S.State({count: 500, level: 0}, category), false, 'Remaining fragments/count is independent from effect level');
    assert.equal(S.State({count: 0, level: 1}, category), true, 'Activated effect can remain when holding count is zero');
    assert.equal(S.State({level: null}, category), null);
    assert.equal(S.State({level: 3, activated: 0}, category), false, 'Independent activation is authoritative');
}
assert.equal(S.Quantity({count: 500, level: 2, target: 5}, 'building'), 'LV2/5');
assert.equal(S.Quantity({level: 0, target: 1}, 'work'), '0/1', 'One-time work activation keeps its actual single target');
assert.equal(S.Quantity({level: 2, target: 10, activated: 1}, 'work'), 'LV2/10');
assert.equal(S.Quantity({count: 19, level: 4, target: 999}, 'fragment'), '19/999', 'Current fragment count is not derived from level');
for (const category of ['shadow', 'pet', 'shop', 'friend', 'ex', 'beast', 'fishing']) {
    assert.equal(S.Quantity({count: 4}, category), '4');
    assert.equal(S.Quantity({count: 4, target: 0}, category), '4');
    assert.equal(S.Quantity({count: 4, target: 30}, category), '4/30');
    assert.equal(S.Quantity({count: 4, count_known: 0}, category), '—');
    assert.equal(S.State({count: 4, count_known: 0, unlocked: 0}, category), null);
}
// Every points entry uses unique ownership, including legacy daily stacks.
assert.equal(typeof S.IsUnlockItem, 'function');
for (const [item, expected] of [
    [{max_owned: 1}, true], [{target: '1'}, true],
    [{max_owned: '1', target: 999999}, true],
    [{max_owned: 999999, target: 1}, true],
    [{max_owned: null, target: 1}, true], [{max_owned: 0, target: 1}, true],
    [{target: 999999}, true], [{count: 1}, true], [{}, true]
]) assert.equal(S.IsUnlockItem(item, 'points'), expected, 'The points category is unique even when an old snapshot carries a stack cap');
for (const category of ['shadow', 'pet', 'fragment', 'commerce_goods', 'titles']) {
    assert.equal(S.IsUnlockItem({max_owned: 1, target: 1}, category), false, 'Other categories retain their existing semantics');
}
for (const [item, expectedState, expectedText] of [
    [{count: 0, target: 1}, false, '未解锁'],
    [{count: 1, max_owned: 1}, true, '已解锁'],
    [{count: 7, target: 1}, true, '已解锁'],
    [{count: 7, max_owned: 1, unlocked: 0}, false, '未解锁'],
    [{count: 0, max_owned: 1, unlocked: 1}, true, '已解锁'],
    [{count: 7, max_owned: 1, count_known: 0, unlocked: 1}, null, '状态待同步'],
    [{count: 7, target: 1, quantity_unknown: 1}, null, '状态待同步'],
    [{max_owned: 1}, null, '状态待同步'],
    [{id: 'daily_growth_gem', count: 3, target: 999999}, true, '已解锁'],
    [{id: 'daily_growth_gem', count: 0, target: 999999}, false, '未解锁'],
    [{id: 'daily_growth_gem', count: 3, target: 999999, count_known: 0}, null, '状态待同步']
]) {
    const row = Object.freeze({...item}), original = JSON.stringify(row);
    assert.equal(S.IsUnlockItem(row, 'points'), true);
    assert.equal(S.State(row, 'points'), expectedState, 'Known quantity and existing explicit unlock state remain authoritative');
    assert.equal(S.Quantity(row, 'points'), expectedText);
    assert.equal(S.Metric(row, 'points'), '解锁状态');
    assert.deepEqual(plain(S.Progress(row, 'points')), {
        known: expectedState !== null, ratio: null, current: null, target: null, text: expectedText
    }, 'A unique item has an unlock state, never a quantity progress bar');
    assert.equal(JSON.stringify(row), original, 'Legacy excess counts are presented without changing the snapshot');
}
const dailyPoints = Object.freeze({id: 'daily_growth_gem', count: 3, target: 999999});
assert.equal(S.Quantity(dailyPoints, 'points'), '已解锁');
assert.equal(S.Metric(dailyPoints, 'points'), '解锁状态');
assert.deepEqual(plain(S.Progress(dailyPoints, 'points')), {
    known: true, ratio: null, current: null, target: null, text: '已解锁'
}, 'A legacy daily stack has an unlock state without numeric progress');
assert.equal(S.Quantity({count: 4}, 'points'), '已解锁', 'Legacy rows without a cap are unique on the points page');
assert.equal(S.Quantity({count: 4, max_owned: 30, target: 1}, 'points'), '已解锁', 'Old cap fields cannot restore stack presentation');
const mixedPoints = {ok: 1, rows: [
    {id: 'lottery_attribute_crystal', count: 7, target: 1},
    {id: 'explicitly_locked', count: 7, max_owned: 1, unlocked: 0},
    {id: 'explicitly_unlocked', count: 0, max_owned: 1, unlocked: 1},
    {id: 'unknown_with_old_count', count: 7, max_owned: 1, count_known: 0, unlocked: 1},
    {id: 'missing_count', target: 1},
    {...dailyPoints}
]};
const mixedPointsBefore = JSON.stringify(mixedPoints);
const normalizedPoints = plain(S.Normalize(mixedPoints, 'points'));
assert.deepEqual(normalizedPoints.slice(0, 3).map(row => [row.count, row.count_known, row.unlocked, row.max_owned, row.target]), [
    [1, 1, 1, 1, 1], [0, 1, 0, 1, 1], [1, 1, 1, 1, 1]
], 'The view contains one entitlement and follows explicit server unlock state');
for (const row of normalizedPoints.slice(3, 5)) {
    assert.equal(row.count_known, 0);
    assert.equal(row.count, undefined, 'An unknown entitlement cannot keep a stale visual count');
    assert.equal(row.unlocked, undefined, 'An unknown entitlement cannot inherit a stale unlock flag');
    assert.equal(S.State(row, 'points'), null);
    assert.equal(S.Quantity(row, 'points'), '状态待同步');
}
assert.deepEqual(normalizedPoints[5], {id: 'daily_growth_gem', count: 1, target: 1, max_owned: 1, count_known: 1, unlocked: 1}, 'The screenshot daily_growth_gem 3/999999 becomes one unlocked entitlement');
assert.equal(JSON.stringify(mixedPoints), mixedPointsBefore, 'Normalizing the view never modifies the original server snapshot');
assert.deepEqual(plain(S.Normalize({rows: normalizedPoints}, 'points')), normalizedPoints, 'View normalization is idempotent');
const dailyCatalog = csv(path.join(repo, 'data/csv/存档系统/archive_daily_items.csv')).filter(row => row.enabled === '1');
assert.equal(dailyCatalog.length, 12, 'Exercise every formal daily item on the points page');
const oldDailyRows = dailyCatalog.map((row, index) => Object.freeze({id: row.item_id, name: row.display_name,
    count: index % 3 === 0 ? 0 : 3, target: 999999, max_owned: 999999}));
const oldDailyBefore = JSON.stringify(oldDailyRows);
const dailyViews = S.Normalize({ok: 1, rows: oldDailyRows}, 'points');
dailyViews.forEach((row, index) => {
    assert.equal(row.count, index % 3 === 0 ? 0 : 1);
    assert.equal(row.target, 1); assert.equal(row.max_owned, 1);
    assert.equal(S.Quantity(row, 'points'), index % 3 === 0 ? '未解锁' : '已解锁');
    assert.equal(S.Progress(row, 'points').ratio, null);
});
assert.equal(JSON.stringify(oldDailyRows), oldDailyBefore, 'All twelve legacy daily snapshots remain unmodified');
assert.equal(S.Quantity({unlocked: 1, count: 1}, 'titles'), '');
assert.equal(S.State({unlocked: 1}, 'titles'), true);
assert.equal(S.State({unlocked: 0}, 'titles'), false);

// Progress drives presentation only; it must preserve the authoritative values
// even when the visual fill is bounded or no meaningful target exists.
assert.deepEqual(plain(S.Progress(joined[0], 'shadow')), {
    known: true, ratio: 2 / catalog[0].max_owned, current: 2, target: catalog[0].max_owned,
    text: '2/' + catalog[0].max_owned
});
assert.deepEqual(plain(S.Progress(unavailable, 'shadow')), {
    known: false, ratio: null, current: null, target: catalog[0].max_owned, text: '—/' + catalog[0].max_owned
});
for (const count of [undefined, null, '', ' ', '—', 'not-a-number', Infinity, NaN, -1, false]) {
    assert.deepEqual(plain(S.Progress({count, target: 100}, 'shadow')), {
        known: false, ratio: null, current: null, target: 100, text: '—/100'
    }, 'Unavailable inventory never becomes a zero progress bar');
}
for (const count of [0, '0']) {
    assert.deepEqual(plain(S.Progress({count, target: 100}, 'shadow')), {
        known: true, ratio: 0, current: 0, target: 100, text: '0/100'
    }, 'A real zero is known and has an empty fill');
}
assert.deepEqual(plain(S.Progress(null, 'shadow')), {
    known: false, ratio: null, current: null, target: null, text: '—'
});
for (const target of [undefined, null, 0, '0', -1, '', false, Infinity, 'invalid']) {
    assert.deepEqual(plain(S.Progress({count: 4, target}, 'shadow')), {
        known: true, ratio: null, current: 4, target: null, text: '4'
    }, 'No valid cap means no invented completion target');
}
assert.deepEqual(plain(S.Progress(uncapped, 'shadow')), {
    known: true, ratio: null, current: 12, target: null, text: '12'
}, 'Explicit server removal of a catalog cap also removes the visual fill');
assert.deepEqual(plain(S.Progress({count: 4, max_owned: null, target: 100}, 'shadow')), {
    known: true, ratio: null, current: 4, target: null, text: '4'
}, 'An explicit uncapped inventory is not replaced with a fallback target');
assert.deepEqual(plain(S.Progress({count: 4, max_owned: 20, target: 100}, 'shadow')), {
    known: true, ratio: 0.2, current: 4, target: 20, text: '4/20'
});
for (const category of ['clear', 'boss', 'gift', 'endless', 'starjoy_points']) {
    const achievement = Object.freeze({count: 25, target: 5, completed: 1});
    assert.deepEqual(plain(S.Progress(achievement, category)), {
        known: true, ratio: 1, current: 25, target: 5, text: '25/5'
    }, 'Only the fill is capped; accumulated achievement counts remain real: ' + category);
    assert.deepEqual(achievement, {count: 25, target: 5, completed: 1}, 'Progress never changes authoritative data');
}
assert.deepEqual(plain(S.Progress(mapRow, 'map_level')), {
    known: true, ratio: 0.4, current: 2, target: 5, text: 'LV2/5'
}, 'Map progress is a level milestone, not the online-minute detail');
assert.deepEqual(plain(S.Progress(S.Normalize({rows: [{rune: '5', count: 800, target: 1200}]}, 'map_level')[0], 'map_level')), {
    known: false, ratio: null, current: null, target: 5, text: 'LV—/5'
}, 'Missing map level never falls back to minutes');
assert.deepEqual(plain(S.Progress({__v10CurrentLevel: 0, __v10TargetLevel: 5, count: 800}, 'map_level')), {
    known: true, ratio: 0, current: 0, target: 5, text: 'LV0/5'
});
assert.deepEqual(plain(S.Progress({__v10CurrentLevel: 7, __v10TargetLevel: 5}, 'map_level')), {
    known: true, ratio: 1, current: 7, target: 5, text: 'LV7/5'
});
for (const category of ['building', 'work']) {
    assert.deepEqual(plain(S.Progress({level: 2, count: 500, target: 5, max_owned: 1000}, category)), {
        known: true, ratio: 0.4, current: 2, target: 5, text: 'LV2/5'
    }, 'Upgrade progress uses the actual level and its target');
    assert.deepEqual(plain(S.Progress({level: null, count: 500, target: 5}, category)), {
        known: false, ratio: null, current: null, target: 5, text: 'LV—/5'
    }, 'An explicitly unknown level cannot become an inventory count');
    assert.deepEqual(plain(S.Progress({count: 2, target: 5}, category)), {
        known: true, ratio: 0.4, current: 2, target: 5, text: 'LV2/5'
    }, 'Legacy server count-as-level rows retain their established meaning');
}
assert.deepEqual(plain(S.Progress({level: 0, target: 1}, 'work')), {
    known: true, ratio: 0, current: 0, target: 1, text: '0/1'
}, 'One-time welfare stays a single activation');
assert.deepEqual(plain(S.Progress({count: 19, level: 4, target: 100, max_owned: 999}, 'fragment')), {
    known: true, ratio: 0.19, current: 19, target: 100, text: '19/100'
}, 'Fragment holding progress is independent from its effect level and uses the server target');
assert.deepEqual(plain(S.Progress({count: 0, level: 4, target: 100}, 'fragment')), {
    known: true, ratio: 0, current: 0, target: 100, text: '0/100'
}, 'An activated fragment effect can coexist with zero remaining fragments');
assert.deepEqual(plain(S.Progress({count: 19, count_known: 0, level: 4, target: 100}, 'fragment')), {
    known: false, ratio: null, current: null, target: 100, text: '—/100'
}, 'Known effect level does not fill an unknown fragment inventory');
for (const [item, known, text] of [
    [{unlocked: 1, equipped: 1, count: 1, target: 1}, true, '已穿戴'],
    [{unlocked: 1, count: 1, target: 1}, true, '已解锁'],
    [{unlocked: 0, count: 0, target: 1}, true, '未解锁'],
    [{}, false, '状态待同步']
]) {
    assert.deepEqual(plain(S.Progress(item, 'titles')), {
        known, ratio: null, current: null, target: null, text
    }, 'Title state never masquerades as a quantitative completion bar');
}
console.log('PASS: V10 official catalog joining; zero/unknown/caps; more-than-preview capacity; achievement overrun; independent level/activation; map and endless metrics; read-only normalization and category-aware progress.');
