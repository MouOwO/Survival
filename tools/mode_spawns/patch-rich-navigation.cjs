'use strict';
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const assert = require('node:assert/strict');
const L = require('../map_c6/lib.cjs');
const {openRichNavigation} = require('./rich-navigation.cjs');
const root = path.resolve(__dirname, '../..');
const [input, output] = process.argv.slice(2);
assert(input && output, 'Usage: node patch-rich-navigation.cjs <current-text.vmap> <patched-text.vmap>');
assert.notEqual(path.resolve(input), path.resolve(output), 'Keep the current snapshot intact');
const source = fs.readFileSync(input, 'utf8');
assert(source.slice(0, 100).includes('encoding keyvalues2'));
const grids = L.blocks(source, 'CMapDotaTileGrid');
assert.equal(grids.length, 1);
const grid = grids[0], nav = L.array(grid.text, 'gridnavFlags');
const water = L.array(grid.text, 'verticesWater'), heights = L.array(grid.text, 'verticesHeight');
const layout = JSON.parse(fs.readFileSync(path.join(root, 'art/maps/mode_spawns/layout.json'), 'utf8'));
const changed = openRichNavigation(layout, nav, water, heights);
// Replace only changed values, retaining the DMX array's original formatting.
const mask = /("gridnavFlags" "\w+_array"\s*\[)([^\]]*)(\])/;
const before = grid.text.match(mask); assert(before);
const changedSet = new Set(changed); let index = 0;
const body = before[2].replace(/"([^"\r\n]*)"/g, (text) => changedSet.has(index++) ? '"0"' : text);
assert.equal(index, nav.length);
const patchedGrid = grid.text.replace(mask, (_, head, values, end) => head + body + end);
const patched = source.slice(0, grid.start) + patchedGrid + source.slice(grid.end);
const erase = text => text.replace(mask, '$1$3');
assert.equal(erase(source), erase(patched), 'Unrelated map data changed');
const actual = L.array(patchedGrid, 'gridnavFlags');
assert.deepEqual(actual, nav);
fs.writeFileSync(output, patched);
const sha = value => crypto.createHash('sha256').update(value).digest('hex');
const report = {input: path.resolve(input), output: path.resolve(output),
    input_sha256: sha(source), output_sha256: sha(patched), changed_nav_cells: changed.length,
    changed_indices: changed, only_rich_navigation_changed: true,
    water_heights_terrain_entities_meshes_markers_preserved: true};
fs.writeFileSync(output + '.json', JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({...report, changed_indices: undefined}));
