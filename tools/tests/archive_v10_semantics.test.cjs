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
for (const category of ['shadow', 'pet', 'points', 'shop', 'friend', 'ex', 'beast', 'fishing']) {
    assert.equal(S.Quantity({count: 4}, category), '4');
    assert.equal(S.Quantity({count: 4, target: 0}, category), '4');
    assert.equal(S.Quantity({count: 4, target: 30}, category), '4/30');
    assert.equal(S.Quantity({count: 4, count_known: 0}, category), '—');
    assert.equal(S.State({count: 4, count_known: 0, unlocked: 0}, category), null);
}
assert.equal(S.Quantity({unlocked: 1, count: 1}, 'titles'), '');
assert.equal(S.State({unlocked: 1}, 'titles'), true);
assert.equal(S.State({unlocked: 0}, 'titles'), false);
console.log('PASS: V10 official catalog joining; zero/unknown/caps; more-than-preview capacity; achievement overrun; independent level/activation; map and endless metrics; read-only normalization.');
