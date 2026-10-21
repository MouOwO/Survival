'use strict';
const assert = require('node:assert/strict');
const {cleanWaterDecor, OBJECT_DEFAULTS} = require('./mode_spawns/clean-water-decor.cjs');
const L = require('./map_c6/lib.cjs');

function fixture() {
    const width = 4, objectWidth = 17, paintWidth = 33;
    const array = (key, type, values) => '"' + key + '" "' + type + '_array" [\n  '
        + values.map(value => '"' + value + '"').join(',\n  ') + '\n]\n';
    const water = Array(25).fill('1');
    for (const index of [2 * 5 + 2, 2 * 5 + 3, 3 * 5 + 2, 3 * 5 + 3]) water[index] = '0';
    const sea = 2 * objectWidth + 2;
    const coast = 6 * objectWidth + 6;
    const dry = 10 * objectWidth + 10;
    const boundary = 4 * objectWidth + 4;
    const size = objectWidth ** 2;
    let grid = '"gridWidth" "int" "4" "gridHeight" "int" "4"\n'
        + array('verticesWater', 'bool', water);
    for (const [key, fallback] of Object.entries(OBJECT_DEFAULTS)) {
        const values = Array(size).fill(fallback);
        values[sea] = values[coast] = values[dry] = values[boundary] = key === 'objectsVariationId' ? '7' : '3';
        grid += array(key, 'int', values);
    }
    for (const key of ['objectConfiguration', 'objectConfigurationByName']) {
        const records = Array.from({length: size}, (_, i) =>
            [sea, coast, dry, boundary].includes(i) ? ['7', '-1', String(i)] : []);
        grid += array(key, 'int', records.flatMap(record => [String(record.length), ...record]));
    }
    const grass = Array(paintWidth ** 2).fill('0');
    grass[4 * paintWidth + 4] = '99'; // pure water
    grass[12 * paintWidth + 12] = '87'; // mixed coast cell
    grass[20 * paintWidth + 20] = '73'; // entirely dry cell
    grass[8 * paintWidth + 8] = '65'; // shared edge touches mixed coast
    grid += array('grassOpacity', 'uint8', grass);
    grid += array('gridnavFlags', 'uint8', ['1', '0', '1', '0']);
    grid += array('verticesHeight', 'int', ['0', '128', '256', '0']);
    grid += array('blendColor', 'color', ['12 34 56 78']);
    const source = '<!-- dmx encoding keyvalues2 1 format vmap 40 -->\n'
        + '"CMapDotaTileGrid" { "nodeID" "int" "16" "layerData" "element_array" ['
        + '"CDmeDotaTileGrid" {' + grid + '}] }\n'
        + '"CMapEntity" { "nodeID" "int" "88" "targetname" "string" "model_room_over_water"'
        + ' "model" "string" "models/wood_training_room/room_earth_base.vmdl" "origin" "vector3" "-384 -384 128" }\n';
    return {source, sea, coast, dry, boundary};
}

const {source, sea, coast, dry, boundary} = fixture();
const result = cleanWaterDecor(source), output = result.output;
const before = L.blocks(source, 'CDmeDotaTileGrid')[0].text;
const after = L.blocks(output, 'CDmeDotaTileGrid')[0].text;
for (const [key, fallback] of Object.entries(OBJECT_DEFAULTS)) {
    const old = L.array(before, key), next = L.array(after, key);
    assert.equal(next[sea], fallback, key + ' sea sample cleared');
    assert.equal(next[coast], old[coast], key + ' coast sample retained');
    assert.equal(next[dry], old[dry], key + ' land sample retained');
    assert.equal(next[boundary], old[boundary], key + ' shared boundary retained');
}
for (const key of ['objectConfiguration', 'objectConfigurationByName']) {
    const old = L.records(L.array(before, key)), next = L.records(L.array(after, key));
    assert.equal(next.length, old.length, 'Count-prefixed record lattice retained');
    assert.deepEqual(next[sea], []);
    assert.deepEqual(next[coast], old[coast]);
    assert.deepEqual(next[dry], old[dry]);
    assert.deepEqual(next[boundary], old[boundary]);
}
const grass = L.array(after, 'grassOpacity');
assert.equal(grass[4 * 33 + 4], '0');
assert.equal(grass[12 * 33 + 12], '87');
assert.equal(grass[20 * 33 + 20], '73');
assert.equal(grass[8 * 33 + 8], '65');
for (const key of ['verticesWater', 'verticesHeight', 'gridnavFlags', 'blendColor']) {
    assert.deepEqual(L.array(after, key), L.array(before, key), key + ' unchanged');
}
assert.deepEqual(L.blocks(output, 'CMapEntity').map(entity => entity.text),
    L.blocks(source, 'CMapEntity').map(entity => entity.text), 'Model-based room over water preserved byte for byte');
assert.equal(cleanWaterDecor(output).output, output, 'Cleanup must be byte-idempotent');
assert.equal(cleanWaterDecor(output).report.token_edits, 0);
assert.equal(result.report.changed_object_sites, 1);
assert.throws(() => cleanWaterDecor(source.replace('"3",\n  "7",\n  "-1",\n  "36"', '"999999"')));
console.log('PASS: water decoration cleared; coast, entities, navigation and other arrays preserved; idempotent.');
