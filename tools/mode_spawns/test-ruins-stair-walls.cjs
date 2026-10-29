'use strict';
// Recorded engine geometry exercises real placement and construction modules.
const fs = require('node:fs'), path = require('node:path'), zlib = require('node:zlib');
const assert = require('node:assert/strict'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../..');
const capture = JSON.parse(zlib.gunzipSync(fs.readFileSync(path.join(root,
    'docs/knowledge_base/validation/20261029/ruins_stair_geometry.json.gz'))));
assert.equal(capture.schema_version, 1);
assert.equal(capture.native_wall_paths.length, 4);
assert(capture.native_wall_paths.every(route => route.reachable));
fs.mkdirSync(path.join(root, 'output'), {recursive: true});
const out = fs.mkdtempSync(path.join(root, 'output/ruins_stair_walls_'));
const terrain = path.join(out, 'terrain.lua'), native = path.join(out, 'native.lua');
fs.writeFileSync(terrain, capture.source_terrain_fixture);
fs.writeFileSync(native, capture.native_fixture);
const result = cp.spawnSync(process.env.LUA || 'C:/Program Files/lua/bin/lua5.1.exe',
    ['tools/test_ruins_spawns.lua', terrain, native], {cwd: root, encoding: 'utf8', windowsHide: true});
assert.equal(result.status, 0, result.stdout + result.stderr);
assert(result.stdout.includes('RUINS_STAIR_WALLS_PASS'));
console.log(result.stdout.trim());
