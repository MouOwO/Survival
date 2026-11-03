'use strict';
// Real receiver + delta cache, synthetic Lua catalogue. No Dota/SDK/UI/network.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const vm = require('node:vm');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '..');
const ui = path.join(root, 'panorama/src/scripts/custom_game');
const receiverSource = fs.readFileSync(path.join(ui, 'archive_180de7e38b_titles_compact_v6.js'), 'utf8');
const cacheSource = fs.readFileSync(path.join(ui, 'ui_snapshot_cache.js'), 'utf8');
const start = receiverSource.indexOf('    function onArchiveSnapshot(data) {');
const end = receiverSource.indexOf('\n    subscribe("survival_archive_snapshot"', start);
const arrayStart = receiverSource.indexOf('    function array(value) {');
const arrayEnd = receiverSource.indexOf('\n    function ', arrayStart + 10);
assert(start >= 0 && end > start && arrayStart >= 0 && arrayEnd > arrayStart);
const receiver = receiverSource.slice(arrayStart, arrayEnd) + '\n' + receiverSource.slice(start, end) + '\nonArchiveSnapshot;';
const lua = process.env.ARCHIVE_WIRE_LUA || (process.platform === 'win32' ? 'C:/Program Files/lua/bin/lua5.1.exe' : 'lua5.1');
const result = cp.spawnSync(lua, ['scripts/vscripts/tests/test_archive_ui_wire_budget.lua', 'emit'], {
    cwd: root, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024, windowsHide: true
});
assert.equal(result.status, 0, result.stderr || result.error?.message);
const payload = JSON.parse(result.stdout.trim().split(/\r?\n/).at(-1));
assert.equal(payload.rows, 945);
assert(payload.max_json_packet_bytes <= 6144);
assert.equal(payload.unchanged_json_encode_calls, 0);

function environment() {
    const config = {SurvivalArchiveV10: false};
    const context = {pageVersions: {}, pageAssemblies: {}, pageCache: {}, resyncPages: {},
        opened: false, current: 'clear', resyncs: [],
        GameUI: {CustomUIConfig: () => config}, render: () => {},
        beginArchiveLoad:()=>{},endArchiveLoad:()=>{},compactEnabled:()=>false,
        queueFullSync: category => context.resyncs.push(category)};
    vm.createContext(context);
    vm.runInContext(cacheSource, context, {timeout: 1000});
    const receive = vm.runInContext(receiver, context, {timeout: 1000});
    return {context, receive};
}
function business(value) {
    const result = JSON.parse(JSON.stringify(value));
    for (const key of ['sequence', 'chunk', 'chunks', 'delta', 'base_sequence']) delete result[key];
    return result;
}
function compare(cache, expected) {
    assert.deepEqual(Object.keys(cache).sort(), Object.keys(expected).sort());
    for (const [category, page] of Object.entries(expected)) {
        assert.deepEqual(business(cache[category]), page, 'receiver business mismatch: ' + category);
        assert(!Object.hasOwn(cache[category], 'daily_limits'));
    }
}
for (const reverse of [false, true]) {
    const {context, receive} = environment();
    const packets = structuredClone(payload.initial_packets);
    if (reverse) packets.reverse();
    for (const packet of packets) receive(packet);
    compare(context.pageCache, payload.initial_expected);
    const changes = structuredClone(payload.delta_packets);
    if (reverse) changes.reverse();
    for (const packet of changes) receive(packet);
    compare(context.pageCache, payload.changed_expected);
    assert.equal(context.resyncs.length, 0, 'valid baseline must accept its real deltas');
}
// Missing full-baseline chunks must trigger resync rather than accepting a
// later patch as complete data; use the real receiver's baseline-version guard.
const missing = environment();
const category = payload.initial_packets.find(p => p.chunks > 1).category_id;
for (const packet of structuredClone(payload.initial_packets)) {
    if (packet.category_id !== category || packet.chunk !== 1) missing.receive(packet);
}
assert(!Object.hasOwn(missing.context.pageCache, category));
for (const packet of structuredClone(payload.delta_packets)) missing.receive(packet);
assert(missing.context.resyncs.includes(category));
console.log(JSON.stringify({status: 'PASS_REAL_ARCHIVE_RECEIVER_FULL_DELTA_BUDGET',
    synthetic_only: true, native_calls: 0, ui_calls: 0, http_calls: 0,
    categories: Object.keys(payload.initial_expected).length, retained_rows: payload.rows,
    packets: payload.packets, max_lua_json_packet_bytes: payload.max_json_packet_bytes,
    full_and_delta_forward_and_reverse_equal: true, missing_baseline_requires_resync: true,
    server_quota_preserved: payload.server_quota_preserved,
    receiver_function_sha256: crypto.createHash('sha256').update(receiverSource.slice(start, end)).digest('hex'),
    cache_source_sha256: crypto.createHash('sha256').update(cacheSource).digest('hex')}));
