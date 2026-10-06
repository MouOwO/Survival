'use strict';
// Native Pangolier Swashbuckle visuals carried along the existing blade pulse.
// CP0 = start and facing, CP1 = visual velocity, CP2.x = native sword scale,
// CP3 = moving carrier with the pulse orientation.
// The owner stops the root at the hero attack-range endpoint; no damage lives here.
const fs = require('fs');
const path = require('path');
const assert = require('assert');
const childProcess = require('child_process');
const { Vpk, endOf } = require('./lib.cjs');
const root = path.resolve(__dirname, '../..');
const engine = path.resolve(root, '../../..');
const vpk = new Vpk(path.join(engine, 'game/dota/pak01_dir.vpk'));
const native = 'particles/units/heroes/hero_pangolier/';
const target = 'particles/survival/skills/';
const out = path.join(root, 'art/effects/blade_swashbuckle');
const temp = path.join(root, 'output/blade_swashbuckle/native');
fs.mkdirSync(temp, { recursive: true });
const header = '<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->\n';
const names = ['', '_images', '_bumper', '_bumper_halo', '_jab_embers', '_light'];
const outputs = [];
const nativeResources = [];
function operator(source, type, edit) {
  const at = source.indexOf('_class = "' + type + '"');
  assert(at >= 0, 'Missing native operator ' + type);
  const start = source.lastIndexOf('{', at);
  const end = endOf(source, start);
  const replacement = edit(source.slice(start, end));
  return source.slice(0, start) + replacement
    + (replacement ? source.slice(end) : source.slice(end).replace(/^\s*,/, ''));
}
function lifetime(source, seconds) {
  return operator(source, 'C_INIT_InitFloat', block => {
    assert(/m_nOutputField = 1\b/.test(block), 'Expected native lifetime initializer first');
    return block.replace(/m_flLiteralValue = [\d.]+/, 'm_flLiteralValue = ' + seconds.toFixed(1));
  });
}
for (const suffix of names) {
  const resource = native + 'pangolier_swashbuckler' + suffix + '.vpcf';
  assert(vpk.entries.has(resource + '_c'), 'Missing installed native asset ' + resource);
  const nativeFile = path.join(temp, path.basename(resource) + '_c');
  fs.writeFileSync(nativeFile, vpk.read(resource + '_c'));
  const dump = childProcess.execFileSync(path.join(engine, 'game/bin/win64/resourceinfo.exe'),
    ['-game', path.join(engine, 'game/dota'), '-i', nativeFile, '-all'],
    { encoding: 'utf8', windowsHide: true });
  const dataAt = dump.indexOf('--- vpcf block DATA');
  assert(dataAt >= 0, 'Missing installed native DATA ' + resource);
  let source = dump.slice(dump.indexOf('{', dataAt));
  nativeResources.push(resource);
  if (suffix === '') {
    source = source.replace('m_flVelocityScale = 2.0', 'm_flVelocityScale = 1.0');
    source = source.replace('m_bSetOrientation = true', 'm_bSetOrientation = false');
    // Preserve the exact hit path instead of the native randomized side offset.
    source = operator(source, 'C_INIT_PositionOffset', () => '');
    source = lifetime(source, 1);
  } else if (suffix === '_images') {
    source = source.replace('m_nMaxParticles = 8', 'm_nMaxParticles = 16');
    // v45 migrates these two transforms from the legacy CP field. Supply it
    // explicitly so migration cannot overwrite a modern TransformInput to CP0.
    source = operator(source, 'C_OP_PositionLock', block => block.replace(
      '_class = "C_OP_PositionLock"',
      '_class = "C_OP_PositionLock"\n\t\t\tm_nControlPointNumber = 0'
    ));
    source = operator(source, 'C_INIT_PositionOffset', block => block.replace(
      '_class = "C_INIT_PositionOffset"',
      '_class = "C_INIT_PositionOffset"\n\t\t\tm_nControlPointNumber = 0'
    ).replace('m_nControlPoint = 3', 'm_nControlPoint = 0'));
    source = operator(source, 'C_INIT_RingWave', block => block
      .replace('m_nControlPointNumber = 3', 'm_nControlPointNumber = 0'));
    // The native sword mesh already extends 805.9557 units along local Z.
    // Keep the ghost animation at the launch origin so it does not add that
    // geometry to the moving carrier distance. CP2.x scales its native 1.1
    // radius to the hero's attack range; the native ring80/-80 offset remains.
    const radiusAt = source.indexOf('m_flRandomMin = 1.1');
    assert(radiusAt >= 0, 'Missing native ghost model radius');
    const radiusValueAt = source.lastIndexOf('m_InputValue =', radiusAt);
    const radiusOpen = source.indexOf('{', radiusValueAt);
    const radiusClose = endOf(source, radiusOpen);
    source = source.slice(0, radiusOpen)
      + '{ m_nType = "PF_TYPE_CONTROL_POINT_COMPONENT" m_nControlPoint = 2 m_nVectorComponent = 0 m_nMapType = "PF_MAP_TYPE_MULT" m_flMultFactor = 1.1 }'
      + source.slice(radiusClose);
    // Reuse the native short ghost-arm animation at the launch origin.
    const emitterAt = source.indexOf('m_Emitters =');
    const open = source.indexOf('[', emitterAt);
    const close = endOf(source, open, '[', ']');
    const emitters = source.slice(open, close);
    source = source.slice(0, open) + emitters.slice(0, -1)
      + '{ _class = "C_OP_ContinuousEmitter" m_flEmitRate = { m_nType = "PF_TYPE_LITERAL" m_flLiteralValue = 25.0 } m_flEmissionDuration = { m_nType = "PF_TYPE_LITERAL" m_flLiteralValue = 1.0 } },\n]'
      + source.slice(close);
  } else if (suffix === '_bumper_halo' || suffix === '_light') {
    // Native velocity was doubled; match the existing damage projectile.
    source = source.replace('m_flVelocityScale = 2.0', 'm_flVelocityScale = 1.0');
    source = lifetime(source, 1);
    if (suffix === '_bumper_halo') {
      // Native radius 140 spills 60 units in front of its -80 offset.
      source = source.replace('m_flLiteralValue = 140.0', 'm_flLiteralValue = 80.0');
    } else {
      // Keep the light behind the carrier rather than a 300-unit leading glow.
      source = source.replace('m_fDrag = 0.07', 'm_fDrag = 0.0')
        .replace('m_flRadiusScale = 3.0', 'm_flRadiusScale = 1.0');
    }
  } else if (suffix === '_jab_embers') {
    source = operator(source, 'C_OP_ContinuousEmitter', block => block
      .replace('m_flLiteralValue = 1.5', 'm_flLiteralValue = 1.0'));
    // CP3 already moves along the requested path. Native forward offsets and
    // 1000-1200 unit/s spatter add hundreds of units beyond that path.
    source = operator(source, 'C_INIT_InitialVelocityNoise', block => block
      .replace('m_vecOutputMax = [ 1200.0, 132.0, 0.0 ]', 'm_vecOutputMax = [ 0.0, 132.0, 0.0 ]')
      .replace('m_vecOutputMin = [ 1000.0, -132.0, 0.0 ]', 'm_vecOutputMin = [ 0.0, -132.0, 0.0 ]'));
    source = operator(source, 'C_INIT_PositionOffset', block => block
      // Trail sprites have radius up to 8; put their forward edge at CP3.
      .replace('m_OffsetMax = [ 200.0, 50.0, 50.0 ]', 'm_OffsetMax = [ -8.0, 50.0, 50.0 ]')
      .replace('m_OffsetMin = [ 200.0, -50.0, 100.0 ]', 'm_OffsetMin = [ -8.0, -50.0, 100.0 ]'));
  }
  source = source.replace(/resource:"([^\"]+\.vpcf)"/g, (whole, child) => {
    const index = names.findIndex(name => child === native + 'pangolier_swashbuckler' + name + '.vpcf');
    assert(index >= 0, 'Unexpected native child ' + child);
    return 'resource:"' + target + 'blade_swashbuckle' + names[index] + '.vpcf"';
  });
  const output = target + 'blade_swashbuckle' + suffix + '.vpcf';
  const destination = path.join(out, 'source', output);
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.writeFileSync(destination, header + source);
  outputs.push(output);
}
fs.writeFileSync(path.join(out, 'manifest.json'), JSON.stringify({
  root: target + 'blade_swashbuckle.vpcf',
  native_root: native + 'pangolier_swashbuckler.vpcf',
  controls: {
    0: 'launch origin and facing; fixed ghost model anchor',
    1: 'visual carrier velocity, capped by owner at hero attack range',
    2: 'x = hero attack range / (805.9557 * 1.1); native ghost model radius scale',
    3: 'launch origin and pulse orientation; native carrier updates position',
  },
  native_sword_forward_extent: 805.9557,
  native_sword_radius: 1.1,
  ghost_models_at_launch_origin: true,
  ember_radius_maximum: 8,
  ember_forward_offset: -8,
  ember_forward_velocity: 0,
  duration_seconds: 1,
  owner_stops_at_endpoint: true,
  native_resources: nativeResources,
  outputs,
}, null, 2) + '\n');
console.log('BLADE_SWASHBUCKLE_SOURCE_PASS particles=' + outputs.length);
