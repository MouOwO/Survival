// Remove stale native terrain decoration only where every touching terrain
// cell is water. Model-based rooms over water and all map entities stay intact.
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const L = require('../map_c6/lib.cjs');

const OBJECT_DEFAULTS = {
    objectsTileSet: '0', objectsPropType: '0', objectsPlantType: '0',
    objectsTreeType: '0', objectsTreeSize: '0', objectsRotation: '0',
    objectsPitch: '0', objectsVariationId: '255',
};
const RECORD_FIELDS = ['objectConfiguration', 'objectConfigurationByName'];
const ALLOWED_FIELDS = [...Object.keys(OBJECT_DEFAULTS), ...RECORD_FIELDS, 'grassOpacity'];
const sha = value => crypto.createHash('sha256').update(value).digest('hex');

function arraySpan(text, key, offset = 0) {
    const match = new RegExp('"' + key + '" "\\w+_array"\\s*\\[([^\\]]*)\\]').exec(text);
    assert(match, 'Missing array ' + key);
    const start = match.index + match[0].indexOf('[') + 1;
    return {key, body: match[1], start: offset + start, end: offset + start + match[1].length};
}

// Records are count-prefixed, including empty records. Keep source token spans
// for nonempty entries instead of reserializing their unchanged neighbours.
function recordSpans(array, expectedCount) {
    const tokens = array.body.matchAll(/"([^"\r\n]*)"/g);
    const nonempty = new Map();
    let record = 0;
    for (let token = tokens.next(); !token.done; token = tokens.next()) {
        const head = token.value, count = Number(head[1]);
        assert(Number.isSafeInteger(count) && count >= 0, 'Invalid record count in ' + array.key);
        let end = head.index + head[0].length;
        for (let n = 0; n < count; n++) {
            const item = tokens.next();
            assert(!item.done, 'Truncated record in ' + array.key);
            end = item.value.index + item.value[0].length;
        }
        if (count) nonempty.set(record, {start: array.start + head.index, end: array.start + end});
        record++;
    }
    assert.equal(record, expectedCount, 'Unexpected record count in ' + array.key);
    return nonempty;
}

function applyEdits(text, edits) {
    const parts = [];
    let cursor = 0;
    for (const edit of edits.slice().sort((a, b) => a.start - b.start)) {
        assert(edit.start >= cursor, 'Overlapping cleanup edits');
        parts.push(text.slice(cursor, edit.start), edit.value);
        cursor = edit.end;
    }
    parts.push(text.slice(cursor));
    return parts.join('');
}

function maskAllowedArrays(text) {
    const grid = L.blocks(text, 'CDmeDotaTileGrid');
    assert.equal(grid.length, 1, 'Expected one native terrain layer');
    return applyEdits(text, ALLOWED_FIELDS.map(key => ({
        ...arraySpan(grid[0].text, key, grid[0].start), value: '',
    })));
}

function cleanWaterDecor(source) {
    assert(source.slice(0, 100).includes('encoding keyvalues2'), 'Convert the current VMAP to keyvalues2 first');
    const layers = L.blocks(source, 'CDmeDotaTileGrid');
    assert.equal(layers.length, 1, 'Expected one native terrain layer');
    const grid = layers[0], width = Number(L.value(grid.text, 'gridWidth'));
    const height = Number(L.value(grid.text, 'gridHeight'));
    assert(Number.isSafeInteger(width) && width > 0 && Number.isSafeInteger(height) && height > 0,
        'Invalid terrain dimensions');
    const water = L.array(grid.text, 'verticesWater');
    assert.equal(water.length, (width + 1) * (height + 1), 'Unexpected water lattice');
    assert(water.every(value => value === '0' || value === '1'), 'Invalid water flags');
    const objectWidth = width * 4 + 1, objectHeight = height * 4 + 1;
    const paintWidth = width * 8 + 1, paintHeight = height * 8 + 1;
    const pureCell = (x, y) => [y * (width + 1) + x, y * (width + 1) + x + 1,
        (y + 1) * (width + 1) + x, (y + 1) * (width + 1) + x + 1]
        .every(index => water[index] === '1');
    // A sample on a tile boundary belongs to both neighbours. Protect it if
    // either neighbour touches land; this retains shoreline vegetation.
    function seaSample(x, y, subdivision) {
        const xs = [Math.floor(x / subdivision)], ys = [Math.floor(y / subdivision)];
        if (x % subdivision === 0) xs.push(x / subdivision - 1);
        if (y % subdivision === 0) ys.push(y / subdivision - 1);
        return xs.filter(a => a >= 0 && a < width).every(a =>
            ys.filter(b => b >= 0 && b < height).every(b => pureCell(a, b)));
    }
    const objectMask = new Uint8Array(objectWidth * objectHeight);
    for (let index = 0; index < objectMask.length; index++) {
        objectMask[index] = seaSample(index % objectWidth, Math.floor(index / objectWidth), 4) ? 1 : 0;
    }
    const edits = [], changes = {}, objectSites = new Set();
    function clearFixed(key, fallback, expected, mask) {
        const span = arraySpan(grid.text, key, grid.start);
        let index = 0, changed = 0;
        for (const token of span.body.matchAll(/"([^"\r\n]*)"/g)) {
            if (mask(index) && token[1] !== fallback) {
                edits.push({start: span.start + token.index, end: span.start + token.index + token[0].length,
                    value: '"' + fallback + '"'});
                changed++;
                if (key !== 'grassOpacity') objectSites.add(index);
            }
            index++;
        }
        assert.equal(index, expected, 'Unexpected lattice in ' + key);
        changes[key] = changed;
    }
    for (const [key, fallback] of Object.entries(OBJECT_DEFAULTS)) {
        clearFixed(key, fallback, objectMask.length, index => objectMask[index]);
    }
    for (const key of RECORD_FIELDS) {
        const records = recordSpans(arraySpan(grid.text, key, grid.start), objectMask.length);
        let changed = 0;
        for (const [index, span] of records) if (objectMask[index]) {
            edits.push({...span, value: '"0"'});
            objectSites.add(index); changed++;
        }
        changes[key] = changed;
    }
    clearFixed('grassOpacity', '0', paintWidth * paintHeight, index =>
        seaSample(index % paintWidth, Math.floor(index / paintWidth), 8));
    const output = applyEdits(source, edits);
    assert.equal(maskAllowedArrays(output), maskAllowedArrays(source),
        'Cleanup changed entities, terrain geometry, navigation or unrelated data');
    return {output, report: {
        schema: 1, operation: 'clear_native_decoration_on_pure_water',
        source_sha256: sha(source), output_sha256: sha(output),
        terrain_dimensions: [width, height], changed_values: changes,
        changed_object_sites: objectSites.size, token_edits: edits.length,
        shoreline_shared_boundaries_protected: true,
        preserved_entities_geometry_navigation_and_other_bytes: true,
    }};
}

if (require.main === module) {
    const [input, output, report] = process.argv.slice(2);
    assert(input && output, 'Usage: node clean-water-decor.cjs <current-text.vmap> <cleaned-text.vmap> [report.json]');
    assert.notEqual(path.resolve(input), path.resolve(output), 'Input snapshot must not be overwritten');
    const result = cleanWaterDecor(fs.readFileSync(input, 'utf8'));
    fs.mkdirSync(path.dirname(output), {recursive: true});
    fs.writeFileSync(output, result.output);
    fs.writeFileSync(report || output + '.json', JSON.stringify(result.report, null, 2) + '\n');
    console.log(JSON.stringify(result.report));
}

module.exports = {cleanWaterDecor, OBJECT_DEFAULTS};
