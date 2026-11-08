'use strict';
// Preserve Valve's light orb; only remove its slow visual acceleration ramp.
// Explicit authoring/verification only: two resources, no game loop or Lua IO.
const fs = require('node:fs'), path = require('node:path');
const cp = require('node:child_process'), crypto = require('node:crypto');
const assert = require('node:assert/strict');
const {endOf, Vpk} = require('./map_c6/lib.cjs');
const root = path.resolve(__dirname, '..'), game = path.resolve(root, '../../dota');
const exe = path.resolve(root, '../../bin/win64/resourceinfo.exe');
const sourceRoot = path.join(root, 'art/effects/keeper_attack');
const nativePrefix = 'particles/units/heroes/hero_keeper_of_the_light/';
const targetPrefix = 'particles/survival/heroes/keeper/';
const names = ['keeper_of_the_light_base_attack.vpcf', 'keeper_base_attack.vpcf'];
const header = '<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->\n';
const hash = b => crypto.createHash('sha256').update(b).digest('hex');
function data(resource) {
  const dump = cp.execFileSync(exe, ['-game', game, '-i', resource, '-all'],
    {encoding: 'utf8', windowsHide: true, maxBuffer: 1024 * 1024});
  const marker = dump.indexOf('--- vpcf block DATA');
  assert(marker >= 0, 'Missing particle DATA');
  const open = dump.indexOf('{', marker);
  return dump.slice(open, endOf(dump, open)).replace(/\r\n/g, '\n');
}
function parse(text) {
  const tokens = text.match(/resource:"(?:\\.|[^"\\])*"|"(?:\\.|[^"\\])*"|[{}\[\]=,]|[^\s{}\[\]=,]+/g);
  let i = 0;
  function value() {
    const token = tokens[i++];
    if (token === '{') { const v = {}; while (tokens[i] !== '}') { const k = tokens[i++]; assert.equal(tokens[i++], '='); v[k] = value(); if (tokens[i] === ',') i++; } i++; return v; }
    if (token === '[') { const v = []; while (tokens[i] !== ']') { v.push(value()); if (tokens[i] === ',') i++; } i++; return v; }
    if (token.startsWith('resource:')) return {resource: JSON.parse(token.slice(9))};
    if (token.startsWith('"')) return JSON.parse(token);
    if (token === 'true' || token === 'false') return token === 'true';
    assert(Number.isFinite(Number(token)), 'Unexpected KV3 token'); return Number(token);
  }
  const result = value(); assert.equal(i, tokens.length); return result;
}
function modern(tree) {
  const v = structuredClone(tree);
  if (!v.m_ForceGenerators) return v;
  assert.deepEqual(v.m_Operators[1], {_class: 'C_OP_MaxVelocity', m_nOverrideCP: 2});
  v.m_Operators[1] = {_class: 'C_OP_MaxVelocity', m_flMaxVelocity: {
    m_nType: 'PF_TYPE_CONTROL_POINT_COMPONENT', m_nControlPoint: 2, m_nVectorComponent: 0}};
  assert.deepEqual(v.m_Initializers[0], {_class: 'C_INIT_CreateWithinSphere'});
  v.m_Initializers[0]._class = 'C_INIT_CreateWithinSphereTransform';
  const force = v.m_ForceGenerators[0];
  assert.equal(force.m_nControlPointNumber, 1);
  delete force.m_nControlPointNumber;
  force.m_TransformInput = {m_nType: 'PT_TYPE_CONTROL_POINT', m_nControlPoint: 1, m_bUseOrientation: false};
  return v;
}
const mode = process.argv[2] || '--check';
assert(['--build', '--check', '--verify'].includes(mode) && process.argv.length <= 3);
const native = new Vpk(path.join(game, 'pak01_dir.vpk')), rows = [];
for (const [index, name] of names.entries()) {
  const original = data(nativePrefix + name + '_c');
  const expected = parse(original);
  let edited;
  if (index === 0) {
    assert.deepEqual(expected.m_Children, [{m_ChildRef: {resource: nativePrefix + names[1]}}]);
    expected.m_Children[0].m_ChildRef.resource = targetPrefix + names[1];
    edited = original.replace(nativePrefix + names[1], targetPrefix + names[1]);
  } else {
    const force = expected.m_ForceGenerators[0];
    assert.equal(force._class, 'C_OP_AttractToControlPoint');
    assert.equal(force.m_nControlPointNumber, 1);
    assert.equal(force.m_fForceAmount.m_flLiteralValue, 9999);
    force.m_fForceAmount.m_flLiteralValue = 1000000;
    assert.equal((original.match(/m_flLiteralValue = 9999\.0/g) || []).length, 1);
    edited = original.replace('m_flLiteralValue = 9999.0', 'm_flLiteralValue = 1000000.0');
  }
  assert.deepEqual(parse(edited), expected, 'Unrelated native particle field changed');
  for (const ref of edited.matchAll(/resource:"([^"]+)"/g)) {
    if (!ref[1].startsWith(targetPrefix)) assert(native.entries.has(ref[1] + '_c'), 'Missing native child: ' + ref[1]);
  }
  const source = header + edited + '\n', resource = targetPrefix + name;
  const output = path.join(sourceRoot, 'source', resource);
  if (mode === '--build') { fs.mkdirSync(path.dirname(output), {recursive: true}); fs.writeFileSync(output, source); }
  else assert.equal(fs.readFileSync(output, 'utf8'), source, 'Authored source drift');
  if (mode === '--verify') assert.deepEqual(parse(data(path.join(root, resource + '_c'))), modern(expected), 'Compiled DATA drift');
  rows.push({resource, native_resource: nativePrefix + name, native_data_sha256: hash(original), source_sha256: hash(source)});
}
const manifest = {format: 1, root: targetPrefix + names[0], outputs: rows,
  transformation: 'Wrapper child redirected; movement attraction 9999 -> 1000000, CP1 target and CP2 speed cap preserved; every other native source field unchanged',
  gameplay: 'No attack speed, projectile speed, range, damage, targeting, timers or networking changes',
  validation_limit: 'Source and compiled DATA checks do not prove native appearance or FPS'};
const manifestFile = path.join(sourceRoot, 'manifest.json');
if (mode === '--build') fs.writeFileSync(manifestFile, JSON.stringify(manifest, null, 2) + '\n');
else assert.deepEqual(JSON.parse(fs.readFileSync(manifestFile, 'utf8')), manifest);
console.log(JSON.stringify({status: 'KEEPER_ATTACK_PARTICLES_PASS', mode, resources: rows.length}));
