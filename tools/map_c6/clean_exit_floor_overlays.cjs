// Remove the four non-colliding floor patches left by the old spawn assemblies.
// Input/output are text VMAPs; convert binary Hammer maps with dmxconvert first.
'use strict';

const fs = require('fs');
const assert = require('assert/strict');
const L = require('./lib.cjs');

function cleanExitFloorOverlays(text) {
    const groups = L.blocks(text, 'CMapGroup').filter(group =>
        /^valley_v3_spawn_reference_[0-3]$/.test(L.value(group.text, 'name') || ''));
    assert.equal(groups.length, 4, 'Expected the four cardinal spawn groups');
    const removed = [];
    const edits = [];
    for (const group of groups) {
        const name = L.value(group.text, 'name');
        const meshes = L.blocks(group.text, 'CMapMesh');
        assert.equal(meshes.length, 1, `${name}: expected one obsolete floor`);
        const mesh = meshes[0];
        assert.equal(L.value(mesh.text, 'physicsType'), 'none', `${name}: floor must not supply collision`);
        assert.deepEqual(L.array(mesh.text, 'materials'), ['maps/ti10_assets/blends/mod_radiant_ti10_angled_000.vmat']);
        const stream = L.blocks(mesh.text, 'CDmePolygonMeshDataStream').find(item =>
            L.value(item.text, 'semanticName') === 'position');
        assert(stream, `${name}: missing vertex positions`);
        const positions = L.array(stream.text, 'data').map(value => value.split(/\s+/).map(Number));
        const bounds = [0, 1, 2].map(axis => [
            Math.min(...positions.map(point => point[axis])),
            Math.max(...positions.map(point => point[axis])),
        ]);
        assert.equal(bounds[0][1] - bounds[0][0], 490, `${name}: unexpected floor width`);
        assert.equal(bounds[1][1] - bounds[1][0], 490, `${name}: unexpected floor depth`);
        assert.deepEqual(bounds[2], [131, 131], `${name}: unexpected floor elevation`);
        removed.push({group: name, nodeID: L.value(mesh.text, 'nodeID'), bounds});
        const start = group.start + mesh.start;
        let end = group.start + mesh.end;
        while (/\s/.test(text[end] || '')) end++;
        if (text[end] === ',') end++;
        edits.push({start, end});
    }
    let result = text;
    for (const edit of edits.sort((a, b) => b.start - a.start)) {
        result = result.slice(0, edit.start) + result.slice(edit.end);
    }
    result = result.replace(/,(\s*\])/g, '$1');

    // Native terrain includes navigation and heights. Retain every original
    // entity and every other mesh, including the continuous stone paths below.
    for (const type of ['CDmeDotaTileGrid', 'CMapEntity', 'CMapMesh']) {
        const after = new Map(L.blocks(result, type).map(block => [L.value(block.text, 'id') ||
            block.text.match(/"id" "elementid" "([^"]+)"/)[1], block.text]));
        for (const block of L.blocks(text, type)) {
            if (type === 'CMapMesh' && removed.some(item => item.nodeID === L.value(block.text, 'nodeID'))) continue;
            const id = block.text.match(/"id" "elementid" "([^"]+)"/)[1];
            assert.equal(after.get(id), block.text, `${type} ${id} changed unexpectedly`);
        }
    }
    assert.equal(L.blocks(text, 'CMapMesh').length - L.blocks(result, 'CMapMesh').length, 4);
    return {text: result, removed};
}

module.exports = {cleanExitFloorOverlays};
if (require.main === module) {
    const [input, output] = process.argv.slice(2);
    assert(input && output, 'Usage: node clean_exit_floor_overlays.cjs <text-vmap> <output-text-vmap>');
    const result = cleanExitFloorOverlays(fs.readFileSync(input, 'utf8'));
    fs.writeFileSync(output, result.text, 'utf8');
    console.log(JSON.stringify({removedExitFloors: result.removed, terrainNavigationAndEntitiesPreserved: true}));
}
