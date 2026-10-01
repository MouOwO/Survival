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
  assert(!text.includes('m_bDisableZBuffering = true'), label + ': effects must respect depth');
  if (/laser_afterglow(?:_arcs)?\.vpcf$/.test(row.resource)) {
    assert(text.includes('C_OP_InstantaneousEmitter') && !text.includes('C_OP_ContinuousEmitter'), label + ': death tail must emit once');
    assert(text.includes('C_OP_Decay') && text.includes('C_OP_FadeOutSimple'), label + ': death tail must fade and expire');
    assert(/m_flConstantLifespan\s*=\s*0\.3\b/.test(text), label + ': tail must last 0.3 seconds');
    assert(!text.includes('C_OP_LockToBone') && !text.includes('laser_target_electric') && !text.includes('laser_beam_io_electric'), label + ': tail must not depend on a corpse or continuous child');
    assert(new RegExp('m_nMaxParticles\\s*=\\s*' + row.max_particles + '\\b').test(text), label + ': tail budget drift');
    if (row.resource.endsWith('laser_afterglow.vpcf')) {
      assert(text.includes('C_OP_MaintainSequentialPath') && /m_nStartControlPointNumber\s*=\s*9\b/.test(text)
        && /m_nEndControlPointNumber\s*=\s*1\b/.test(text), label + ': detached tail must preserve the beam path');
    }
    return;
  }
  if (/laser_(beam_io_electric|target_electric)\.vpcf$/.test(row.resource)) {
    assert(text.includes('C_OP_ContinuousEmitter') && text.includes('C_OP_Decay')
      && text.includes('C_OP_FadeOutSimple'), label + ': native arcs need bounded continuous emission');
    assert(new RegExp('m_nMaxParticles\\s*=\\s*' + row.max_particles + '\\b').test(text), label + ': arc budget drift');
    if (row.resource.includes('target_electric')) {
      assert(text.includes('C_INIT_CreateOnModel') && text.includes('C_OP_LockToBone'), label + ': arcs must follow enemy model');
      if (label.startsWith('compiled ')) {
        // Valve migrates the legacy CP field to separate model/transform inputs.
        assert.equal((text.match(/m_nControlPoint\s*=\s*7\b/g) || []).length, 4, label + ': model and transform inputs must all use CP7');
        assert.equal((text.match(/PM_TYPE_CONTROL_POINT/g) || []).length, 2, label + ': both operators need entity models');
      } else {
        assert.equal((text.match(/m_nControlPointNumber\s*=\s*7\b/g) || []).length, 2, label + ': model spawn and lock must both use CP7');
      }
      assert(text.includes('materials/particle/electrical_arc/electrical_arc.vtex'), label + ': Zeus arc texture missing');
    } else {
      assert(text.includes('C_OP_LockToSavedSequentialPath'), label + ': Io electric strand must follow the beam');
      assert.equal((text.match(/m_nStartControlPointNumber\s*=\s*9\b/g) || []).length, 2, label + ': electric path must start at orb');
      assert(text.includes('materials/particle/electricity/electricity_beam_white_a.vtex'), label + ': Io electric texture missing');
    }
    return;
  }
  if (/laser_(blood|beam_motes|beam_sparks|beam_pulse|beam_strike|charge_feed)\.vpcf$/.test(row.resource)) {
    assert(text.includes('C_OP_Decay') && text.includes('C_OP_FadeOutSimple'), label + ': finite particles must expire');
    assert(text.includes('C_OP_BasicMovement') || (row.resource.includes('beam_strike') && text.includes('C_OP_SetToCP')), label + ': missing motion/impact anchor');
    if (/beam_(motes|pulse)/.test(row.resource)) {
      assert(text.includes('C_OP_ConstrainDistanceToPath'), label + ': directed travel missing');
      assert(/m_nStartControlPointNumber\s*=\s*9\b/.test(text) && /m_nEndControlPointNumber\s*=\s*1\b/.test(text), label + ': pulses must travel from orb to enemy');
      const seconds = row.resource.includes('motes') ? '0.14' : '0.18';
      assert(text.includes('m_flTravelTime = ' + seconds), label + ': travel time changed');
    }
    assert(new RegExp('m_nMaxParticles\\s*=\\s*' + row.max_particles + '\\b').test(text), label + ': budget drift');
    return;
  }
  assert(text.includes('C_OP_InstantaneousEmitter'), label + ': emitter must allocate once');
  assert(!text.includes('C_OP_ContinuousEmitter'), label + ': no endless particle churn');
  assert(!text.includes('C_OP_Decay') && !text.includes('C_OP_FadeOutSimple')
    && !text.includes('C_OP_StopAfterCPDuration'), label + ': normal-state expiry would silently kill a live handle');
  assert(text.includes('C_OP_EndCapTimedDecay'), label + ': native endcap cleanup missing');
  assert(/m_flConstantLifespan\s*=\s*999999(?:\.0)?/.test(text), label + ': sustained lifespan missing');
  assert(new RegExp('m_nMaxParticles\\s*=\\s*' + row.max_particles + '\\b').test(text), label + ': particle budget drift');
  assert(!text.includes('m_bDisableZBuffering = true'), label + ': endpoint glow must respect depth');
  if (/laser_beam(?:_envelope|_filament)?\.vpcf$/.test(row.resource)) {
    assert(text.includes('C_OP_RenderRopes') && text.includes('C_OP_MaintainSequentialPath'),
      label + ': missing native rope/follow operator');
    assert(text.includes('C_INIT_CreateSequentialPath'), label + ': path initializer missing');
    assert(/m_nStartControlPointNumber\s*=\s*9\b/.test(text)
      && /m_nEndControlPointNumber\s*=\s*1\b/.test(text), label + ': runtime CP9 -> CP1 contract changed');
    assert(!text.includes('C_OP_InterpolateRadius') && !text.includes('C_OP_FadeInSimple'),
      label + ': solid beam must not taper out or restart a long fade');
  } else {
    assert(text.includes('C_OP_RenderSprites'), label + ': hit sprite missing');
    assert(text.includes('C_OP_SetToCP'), label + ': sprite must follow its anchor');
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
assert.equal(total, 187, 'Resource closure budget (163 plus one 24-particle death tail) changed');
assert.equal(known.size, 14, 'Io beam, electric strands, model-bound arcs, impact, blood, compact charge and finite death tail closure');
const rootSource = fs.readFileSync(isSource('particles/survival/towers/laser_beam.vpcf'), 'utf8');
assert(!/laser_beam_(envelope|filament)/.test(rootSource), 'Broad light curtain must not be linked');
assert(rootSource.includes('materials/particle/beam_hotblue.vtex') && /m_flConstantRadius\s*=\s*96\.0/.test(rootSource), 'Use actual Io core texture and width');
assert(!rootSource.includes('C_OP_RemapCPtoVector'), 'Io core must not become a thin red line');
assert(rootSource.includes('laser_target_electric') && rootSource.includes('laser_beam_io_electric'), 'Electric layers must be owned by the beam');
const charge = fs.readFileSync(isSource('particles/survival/towers/laser_charge.vpcf'), 'utf8');
assert(!charge.includes('laser_charge_fluid') && !charge.includes('C_OP_RemapCPtoVector')
  && !charge.includes('particle_glow_05') && !charge.includes('C_OP_OscillateScalar'), 'Overhead red glow curtain must be removed');
assert(/m_flConstantRadius\s*=\s*10\.0/.test(charge), 'Legacy source must remain small');
assert(rootSource.includes('laser_beam_motes') && rootSource.includes('laser_beam_sparks'),
  'Removing the curtain must preserve discrete light particles');
const csv = fs.readFileSync(path.join(root, 'data/csv/建筑与工人系统/防御塔/tower_laser_effects.csv'), 'utf8');
const rows = csv.trim().split(/\r?\n/).filter(line => /^laser_lv/.test(line)).map(line => line.split(','));
assert.equal(rows.length, 20);
for (const row of rows) {
  assert(native.entries.has(row[3] + '_c') && row[3].includes('tinker'), 'Production must use an existing native Tinker effect');
  assert.equal(row[4], 'native');
  assert.equal(row[15], '1', 'production laser must use head surface');
  assert.equal(row[19], '1', 'production source must be the orb');
  assert.deepEqual(row.slice(5, 14), ['0', '0.03', '0.24', '0.48', '185', '70', '5', '5', '1'],
    'CSV timing/range/fallback/damage values drifted');
}
const lua = fs.readFileSync(path.join(root, 'scripts/vscripts/config/generated/tower_laser_effects.lua'), 'utf8');
assert.equal((lua.match(/beam_mode = "native"/g) || []).length, rows.length, 'CSV generated Lua is stale');
for (const row of rows) assert(lua.includes('particle_name = "' + row[3] + '"'), 'Native generated path missing');
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, compiled ? 'compiled_validation.json' : 'source_validation.json'),
  JSON.stringify({ status: 'PASS', compiled, custom_particle_budget: total, records }, null, 2) + '\n');
console.log('LASER_VISUAL_CONTRACT_PASS compiled=' + compiled + ' resources=' + records.length + ' budget=' + total);
