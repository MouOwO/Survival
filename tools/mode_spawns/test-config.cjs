'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const root = path.resolve(__dirname, '../..');
const layout = JSON.parse(fs.readFileSync(path.join(root, 'art/maps/mode_spawns/layout.json'), 'utf8'));
const out = fs.mkdtempSync(path.join(root, 'output/mode_spawn_config_test_'));
function generate(name, value) {
    const input = path.join(out, name + '.json'), output = path.join(out, name + '.lua');
    fs.writeFileSync(input, JSON.stringify(value));
    return {output, result: spawnSync(process.execPath, [path.join(__dirname, 'patch-map.cjs'),
        '--config-only', '--layout', input, '--config', output], {encoding: 'utf8'})};
}
const valid = generate('valid', layout);
assert.equal(valid.result.status, 0, valid.result.stderr);
assert.equal(fs.readFileSync(valid.output, 'utf8'),
    fs.readFileSync(path.join(root, 'scripts/vscripts/config/mode_spawn_config.lua'), 'utf8').replace(/\r\n/g, '\n'));
assert.equal(layout.modes.scourge.monster_bounds.length, 4);
for (const [name, mutate] of [
    ['build_court_outside_mode', data => { data.modes.cold.player_build_bounds[0][2] = 16384; }],
    ['build_court_overlap', data => { data.modes.cold.player_build_bounds[1][2] = 12800; }],
    ['missing_build_court', data => { data.modes.cold.player_build_bounds.pop(); }],
    ['build_height_missing', data => { delete data.modes.cold.build_ground_height; }],
    ['build_height_includes_road', data => { data.modes.cold.build_ground_height_tolerance = 128; }],
    ['build_court_loses_landing', data => { data.modes.cold.player_build_bounds[0][0] = 14592; }],
    ['outside_mode', data => { data.modes.scourge.monster_bounds[0][2] = 16384; }],
    ['player_court_overlap', data => { data.modes.scourge.monster_bounds[0][2] = -9984; }],
    ['scourge_height_invalid', data => { data.modes.scourge.build_ground_height = '768'; }],
    ['scourge_height_missing', data => { delete data.modes.scourge.build_ground_height; }],
    ['scourge_height_includes_terraces', data => { data.modes.scourge.build_ground_height_tolerance = 128; }],
    ['marker_outside_range', data => { data.modes.scourge.monster_bounds[0] = [-12288, 12672, -11520, 13440]; }],
    ['missing_owner_range', data => { data.modes.scourge.monster_bounds.pop(); }],
]) {
    const malformed = structuredClone(layout); mutate(malformed);
    const attempt = generate(name, malformed);
    assert.notEqual(attempt.result.status, 0, name + ' must be rejected');
    assert(!fs.existsSync(attempt.output), name + ' must not write an invalid runtime config');
}
console.log('MODE_SPAWN_CONFIG_PASS generated source matches; invalid ranges cannot escape mode, overlap courts or lose owners');
