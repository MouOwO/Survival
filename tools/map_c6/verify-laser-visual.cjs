'use strict';
// Source/CSV graph checks always run; --compiled additionally inspects Valve's
// actual DATA and dependencies instead of trusting a successful compiler exit.
const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const crypto = require('crypto');
const assert = require('assert');
const { Vpk } = require('./lib.cjs');
const root = path.resolve(__dirname, '../..');
const args = process.argv.slice(2);
const compiled = args.includes('--compiled');
const logIndex = args.indexOf('--log-dir');
const logDir = path.resolve(root, logIndex < 0
  ? 'output/tower_vfx_polish_20261001' : args[logIndex + 1]);
const outDir = path.join(root, 'output/laser_continuous_audit/compiled');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'art/effects/laser/manifest.json')));
const native = new Vpk(path.resolve(root, '../../dota/pak01_dir.vpk'));
const known = new Set(manifest.outputs.map(row => row.resource));
const records = [];
let total = 0;
const isSource = resource => path.join(root, 'art/effects/laser/source', resource);
function references(bytes) {
  const result = [], header = 8 + bytes.readUInt32LE(8);
  for (let i = 0; i < bytes.readUInt32LE(12); i++) {
    const block = header + i * 12;
    if (bytes.toString('ascii', block, block + 4) !== 'RERL') continue;
    const start = block + 4 + bytes.readUInt32LE(block + 4);
    const entries = start + bytes.readUInt32LE(start);
    for (let j = 0; j < bytes.readUInt32LE(start + 4); j++) {
      const entry = entries + j * 16 + 8;
      const name = entry + Number(bytes.readBigInt64LE(entry));
      result.push(bytes.toString('utf8', name, bytes.indexOf(0, name)));
    }
  }
  return result;
}
function allRefs(text) {
  return [...text.matchAll(/resource:"([^"]+)"/g)].map(match => match[1]);
}
function contract(text, row, label) {
  assert(text.includes('C_OP_InstantaneousEmitter'), label + ': emitter must allocate once');
  assert(!text.includes('C_OP_ContinuousEmitter'), label + ': no endless particle churn');
  assert(!text.includes('C_OP_Decay') && !text.includes('C_OP_FadeOutSimple')
    && !text.includes('C_OP_StopAfterCPDuration'), label + ': normal-state expiry would silently kill a live handle');
  assert(text.includes('C_OP_EndCapTimedDecay'), label + ': native endcap cleanup missing');
  assert(/m_flConstantLifespan\s*=\s*999999(?:\.0)?/.test(text), label + ': sustained lifespan missing');
  assert(new RegExp('m_nMaxParticles\\s*=\\s*' + row.max_particles + '\\b').test(text), label + ': particle budget drift');
  assert(!text.includes('m_bDisableZBuffering = true'), label + ': endpoint glow must respect depth');
  if (row.resource.endsWith('laser_beam.vpcf') || row.resource.endsWith('laser_beam_envelope.vpcf')) {
    assert(text.includes('C_OP_RenderRopes') && text.includes('C_OP_MaintainSequentialPath'),
      label + ': missing native rope/follow operator');
    assert(text.includes('C_INIT_CreateSequentialPath'), label + ': path initializer missing');
    assert(/m_nStartControlPointNumber\s*=\s*9\b/.test(text)
      && /m_nEndControlPointNumber\s*=\s*1\b/.test(text), label + ': runtime CP9 -> CP1 contract changed');
    assert(!text.includes('C_OP_InterpolateRadius') && !text.includes('C_OP_FadeInSimple'),
      label + ': solid beam must not taper out or restart a long fade');
  } else {
    assert(text.includes('C_OP_RenderSprites'), label + ': hit sprite missing');
    assert(/_class\s*=\s*"C_OP_SetToCP"\s+m_nControlPointNumber\s*=\s*1\b/.test(text),
      label + ': hit point must stay pinned to body CP1');
  }
}
for (const row of manifest.outputs) {
  const source = fs.readFileSync(isSource(row.resource), 'utf8');
  const sha = crypto.createHash('sha256').update(source).digest('hex');
  assert.equal(sha, row.sha256, 'Source manifest hash mismatch: ' + row.resource);
  assert(!/[ \t]+$/m.test(source), 'Source trailing whitespace: ' + row.resource);
  contract(source, row, 'source ' + row.resource);
  for (const dependency of allRefs(source)) {
    assert(known.has(dependency) || native.entries.has(dependency + '_c'), 'Unresolved dependency: ' + dependency);
  }
  total += row.max_particles;
  const record = { resource: row.resource, source_sha256: sha, max_particles: row.max_particles };
  if (compiled) {
    const content = path.resolve(root, '../../../content/dota_addons/survival', row.resource);
    assert(fs.readFileSync(content, 'utf8') === source, 'Content/source drift: ' + row.resource);
    const filename = path.join(root, row.resource + '_c');
    const bytes = fs.readFileSync(filename);
    const result = cp.spawnSync(path.resolve(root, '../../bin/win64/resourceinfo.exe'),
      ['-i', filename, '-all'], { encoding: 'utf8', windowsHide: true });
    assert.equal(result.status, 0, result.stderr || 'resourceinfo failed');
    const at = result.stdout.indexOf('--- vpcf block DATA');
    assert(at >= 0, 'Missing DATA block: ' + row.resource);
    const data = result.stdout.slice(at);
    contract(data, row, 'compiled ' + row.resource);
    if (row.resource.includes('_hit')) {
      assert(data.includes('C_INIT_CreateWithinSphereTransform'), 'Legacy sphere did not migrate: ' + row.resource);
    }
    const dependencies = references(bytes);
    for (const dependency of dependencies) {
      assert(native.entries.has(dependency + '_c') || fs.existsSync(path.join(root, dependency + '_c')),
        'Unresolved compiled dependency: ' + dependency);
    }
    for (const dependency of allRefs(source)) {
      assert(dependencies.includes(dependency), 'Compiled resource lost source dependency: ' + dependency);
    }
    const name = path.basename(row.resource, '.vpcf');
    const log = fs.readFileSync(path.join(logDir, 'compile_' + name + '.log'), 'utf8');
    assert(/0 failed/.test(log) && !/RESOURCE COMPILE ERROR|Unknown class/.test(log), 'Compile failed: ' + name);
    fs.mkdirSync(outDir, { recursive: true });
    fs.writeFileSync(path.join(outDir, name + '.txt'), result.stdout);
    Object.assign(record, { compiled_bytes: bytes.length,
      compiled_sha256: crypto.createHash('sha256').update(bytes).digest('hex'), dependencies });
  }
  records.push(record);
}
assert.equal(total, 26, 'Total live particle budget changed');
assert.equal(known.size, 4, 'Persistent beam closure must contain four collections');
const csv = fs.readFileSync(path.join(root, 'data/csv/建筑与工人系统/防御塔/tower_laser_effects.csv'), 'utf8');
const rows = csv.trim().split(/\r?\n/).filter(line => /^laser_lv/.test(line)).map(line => line.split(','));
assert.equal(rows.length, 5);
for (const row of rows) {
  assert.equal(row[3], 'particles/survival/towers/laser_beam.vpcf');
  assert.equal(row[4], 'continuous');
  assert.deepEqual(row.slice(5, 14), ['0', '0.03', '0.12', '0.18', '160', '70', '5', '5', '1'],
    'CSV timing/range/fallback/damage values drifted');
}
const lua = fs.readFileSync(path.join(root, 'scripts/vscripts/config/generated/tower_laser_effects.lua'), 'utf8');
assert.equal((lua.match(/beam_mode = "continuous"/g) || []).length, 5, 'CSV generated Lua is stale');
assert.equal((lua.match(/particle_name = "particles\/survival\/towers\/laser_beam\.vpcf"/g) || []).length, 5);
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, compiled ? 'compiled_validation.json' : 'source_validation.json'),
  JSON.stringify({ status: 'PASS', compiled, custom_particle_budget: total, records }, null, 2) + '\n');
console.log('LASER_VISUAL_CONTRACT_PASS compiled=' + compiled + ' resources=' + records.length + ' budget=' + total);
