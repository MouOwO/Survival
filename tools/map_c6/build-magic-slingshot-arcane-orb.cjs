'use strict';
// Preserve base Outworld Destroyer's Q projectile. Its native hit endcap is
// removed so Lua can emit exactly one impact on an actual, valid target hit.
const fs = require('fs'), path = require('path'), cp = require('child_process');
const assert = require('assert'), crypto = require('crypto');
const { Vpk, endOf } = require('./lib.cjs');
const repo = path.resolve(__dirname, '../..'), engine = path.resolve(repo, '../../..');
const game = path.join(engine, 'game/dota');
const nativeRoot = 'particles/units/heroes/hero_obsidian_destroyer/obsidian_destroyer_arcane_orb.vpcf';
const nativeHit = 'particles/units/heroes/hero_obsidian_destroyer/obsidian_destroyer_arcane_orb_hit.vpcf';
const targetRoot = 'particles/survival/skills/magic_slingshot_arcane_orb.vpcf';
const output = path.join(repo, 'art/effects/magic_slingshot_arcane_orb');
const header = '<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->\n';
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
function data(resource) {
  const raw = cp.execFileSync(path.join(engine, 'game/bin/win64/resourceinfo.exe'),
    ['-game', game, '-i', resource, '-all'], { encoding: 'utf8', windowsHide: true, maxBuffer: 16 * 1024 * 1024 });
  const marker = raw.indexOf('--- vpcf block DATA'), open = raw.indexOf('{', marker);
  assert(marker >= 0 && open >= 0, 'Missing particle DATA: ' + resource);
  return raw.slice(open, endOf(raw, open));
}
function parse(text) {
  const tokens = text.match(/resource:"(?:\\.|[^"\\])*"|"(?:\\.|[^"\\])*"|[{}\[\]=,]|[^\s{}\[\]=,]+/g); let i = 0;
  function value() {
    const token = tokens[i++];
    if (token === '{') { const result = {}; while (tokens[i] !== '}') { const key = tokens[i++]; assert.equal(tokens[i++], '='); result[key] = value(); if (tokens[i] === ',') i++; } i++; return result; }
    if (token === '[') { const result = []; while (tokens[i] !== ']') { result.push(value()); if (tokens[i] === ',') i++; } i++; return result; }
    if (token.startsWith('resource:')) return { resource: JSON.parse(token.slice(9)) };
    if (token.startsWith('"')) return JSON.parse(token);
    if (token === 'true' || token === 'false') return token === 'true';
    if (token === 'null') return null;
    assert(Number.isFinite(Number(token)), 'Unexpected native KV3 token ' + token); return Number(token);
  }
  const result = value(); assert.equal(i, tokens.length); return result;
}
const nativeData = data(nativeRoot + '_c'), expected = parse(nativeData);
assert.equal(expected.m_Children.length, 3, 'Native Q child graph changed');
const removed = expected.m_Children.filter(child => child.m_bEndCap);
assert.deepStrictEqual(removed, [{ m_bEndCap: true, m_ChildRef: { resource: nativeHit } }]);
expected.m_Children = expected.m_Children.filter(child => !child.m_bEndCap);
// Preserve the installed DATA text, including numeric types and all operators.
// Removing one balanced child block is the only source transformation.
const childKey = nativeData.indexOf('m_Children ='), childOpen = nativeData.indexOf('[', childKey);
const childEnd = endOf(nativeData, childOpen, '[', ']');
const childArray = nativeData.slice(childOpen, childEnd);
let cursor = 0, removedBlock = null;
while ((cursor = childArray.indexOf('{', cursor)) >= 0) {
  const end = endOf(childArray, cursor), block = childArray.slice(cursor, end);
  if (block.includes('m_bEndCap = true')) { assert.equal(removedBlock, null); removedBlock = [cursor, end]; }
  cursor = end;
}
assert(removedBlock, 'Native hit endcap block missing');
const [start, end] = removedBlock;
const strippedArray = childArray.slice(0, start) + childArray.slice(end).replace(/^\s*,/, '');
const sourceData = nativeData.slice(0, childOpen) + strippedArray + nativeData.slice(childEnd);
assert.deepStrictEqual(parse(sourceData), expected, 'Unrelated native source field changed');

if (process.argv.includes('--verify')) {
  const runtime = path.join(repo, targetRoot + '_c');
  assert(fs.existsSync(runtime), 'Derived runtime particle missing');
  const compiledData = data(runtime), actual = parse(compiledData);
  // The current compiler upgrades precisely these three legacy native fields.
  // Compare against explicit, verified modern equivalents rather than masking
  // whole operator blocks or accepting any other change to the native graph.
  const modernExpected = structuredClone(expected), migrations = [];
  assert.deepStrictEqual(modernExpected.m_Initializers[0], { _class: 'C_INIT_CreateWithinSphere' });
  modernExpected.m_Initializers[0]._class = 'C_INIT_CreateWithinSphereTransform';
  migrations.push('Default CP0 sphere initializer becomes CreateWithinSphereTransform');
  assert.deepStrictEqual(modernExpected.m_Operators[1], { _class: 'C_OP_MaxVelocity', m_nOverrideCP: 2 });
  modernExpected.m_Operators[1] = { _class: 'C_OP_MaxVelocity', m_flMaxVelocity: {
    m_nType: 'PF_TYPE_CONTROL_POINT_COMPONENT', m_nControlPoint: 2, m_nVectorComponent: 0,
  } };
  migrations.push('Legacy maximum-velocity override CP2 becomes typed CP2.x input');
  const attraction = modernExpected.m_ForceGenerators[0];
  assert.equal(attraction._class, 'C_OP_AttractToControlPoint'); assert.equal(attraction.m_nControlPointNumber, 1);
  delete attraction.m_nControlPointNumber;
  attraction.m_TransformInput = { m_nControlPoint: 1, m_bUseOrientation: false };
  migrations.push('Legacy attraction CP1 becomes TransformInput CP1 with orientation disabled');
  assert.deepStrictEqual(actual, modernExpected, 'Compiled root differs beyond the removed endcap and three exact schema migrations');
  const verification = {
    status: 'PASS', root: targetRoot, native_root: nativeRoot,
    native_data_sha256: hash(nativeData), expected_data_sha256: hash(sourceData),
    compiled_data_sha256: hash(compiledData), compiled_resource_sha256: hash(fs.readFileSync(runtime)),
    retained_native_children: expected.m_Children.map(child => child.m_ChildRef.resource),
    removed_native_hit_endcap: nativeHit, exact_native_source_equivalence_except_removed_child: true,
    compiled_semantic_equivalence_after_exact_schema_migrations: true, verified_schema_migrations: migrations,
    control_contract: { 0: 'tracking projectile launch', 1: 'tracking target, including victim model entity', 2: 'tracking speed override', 3: 'written by native SetChildControlPoints for moving orb children', 9: 'tracking launch frame' },
    validation_limit: 'Compiled DATA equality and native dependency availability; actual appearance requires in-game inspection',
  };
  const reportDir = path.join(repo, 'output/magic_slingshot_arcane_orb');
  fs.mkdirSync(reportDir, { recursive: true });
  fs.writeFileSync(path.join(reportDir, 'compiled_verification.json'), JSON.stringify(verification, null, 2) + '\n');
  fs.writeFileSync(path.join(reportDir, 'compiled_root.data.txt'), compiledData + '\n');
  console.log('MAGIC_SLINGSHOT_ARCANE_ORB_COMPILED_PASS exact_native_source=true verified_schema_migrations=3 native_children=2');
} else {
  const source = header + sourceData + '\n', destination = path.join(output, 'source', targetRoot);
  fs.mkdirSync(path.dirname(destination), { recursive: true }); fs.writeFileSync(destination, source);
  const vpk = new Vpk(path.join(game, 'pak01_dir.vpk'));
  const roots = [expected.m_Children[0].m_ChildRef.resource, expected.m_Children[1].m_ChildRef.resource, nativeHit];
  const graph = new Map(), refs = new Set();
  function walk(resource) {
    if (graph.has(resource)) return;
    const raw = data(resource + '_c'), tree = parse(raw); graph.set(resource, tree);
    for (const ref of raw.matchAll(/resource:"([^"]+)"/g)) refs.add(ref[1]);
    for (const child of tree.m_Children || []) walk(child.m_ChildRef.resource);
  }
  roots.forEach(walk);
  for (const ref of sourceData.matchAll(/resource:"([^"]+)"/g)) refs.add(ref[1]);
  const missing = [...refs].filter(resource => !vpk.entries.has(resource + '_c') && !vpk.entries.has(resource));
  assert.deepStrictEqual(missing, [], 'Native dependency missing');
  fs.writeFileSync(path.join(output, 'manifest.json'), JSON.stringify({
    root: targetRoot, native_root: nativeRoot, native_ability: 'obsidian_destroyer_arcane_orb', chinese: '奥术天球',
    transformation: 'Only remove native hit endcap child; preserve every remaining native compiled DATA field verbatim',
    native_data_sha256: hash(nativeData), source_sha256: hash(source),
    retained_native_children: expected.m_Children.map(child => child.m_ChildRef.resource), removed_native_hit_endcap: nativeHit,
    controls: { 0: 'tracking launch', 1: 'tracking target and target entity', 2: 'tracking speed override', 3: 'native moving child frame', 9: 'native launch frame' },
    projectile_lifecycle: 'CreateTrackingProjectile owns native projectile controls, movement and termination; no native hit endcap remains',
    manual_hit: { resource: nativeHit, controls: { 0: 'hit position', 1: 'actual victim entity via SetParticleControlEnt', 3: 'hit position' }, entity_requirement: 'hit_sparks and hit_energy use CreateOnModel CP1; sparks also LockToBone CP1', lifetime_seconds: [0.1, 1.25], cleanup: 'Native instantaneous emitters and ordinary decay; release particle index after control setup' },
    dependencies: { native_particle_nodes: graph.size, native_resource_refs: refs.size, missing },
    native_dependencies: [...refs].sort(), outputs: [targetRoot],
    gameplay: 'Lua retains targeting, speed, damage, stun and existing level5 rubble field; this asset changes visuals only',
    validation_limit: 'Installed native DATA and dependencies verified; caller hit integration and in-game appearance are separate checks',
  }, null, 2) + '\n');
  console.log('MAGIC_SLINGSHOT_ARCANE_ORB_SOURCE_PASS particles=1 native_children=2 removed_hit_endcap=1');
}
