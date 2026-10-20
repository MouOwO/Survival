'use strict';
const fs = require('node:fs');
// dmxconvert synthesizes a fresh ID for the binary prefix element on each read.
// Exclude only that ID; every stored entity ID and all map data must still match.
const normalized = file => fs.readFileSync(file, 'utf8').replace(
    /^(<!-- dmx encoding keyvalues2[^\n]*\r?\n"\$prefix_element\$"\s*\{\s*"id" "elementid" ")[^"]+("\s*)/,
    '$1CONVERTER_PREFIX_ID$2');
if (normalized(process.argv[2]) !== normalized(process.argv[3])) {
    console.error('Hammer source data changed since the baseline.'); process.exitCode = 1;
} else console.log('HAMMER_SNAPSHOT_MATCH');
