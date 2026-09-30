'use strict';
// Small ground-only tower ornaments. Uses Valve textures and the reference
// aura composition approach, with explicit size/alpha/color control points.
const fs = require('fs');
const path = require('path');
const { packs } = require('./inspect-effect-resources.cjs');
const root = path.resolve(__dirname, '../..');
const sourceRoot = path.join(root, 'art/effects/tower_bases/source');
const relative = 'particles/survival/towers';
const out = path.join(sourceRoot, relative);
fs.mkdirSync(out, { recursive: true });
// Legacy CreateWithinSphere needs Valve's version migration. Declaring the
// latest format around a legacy operator leaves a nonfunctional placeholder.
const header = '<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->\n';
const formatSource = text => text.split(/\r?\n/)
  .map(line => line.replace(/[ \t]+$/, ''))
  .filter(line => line.trim() !== '').join('\n') + '\n';
const definitions = [
  { name: 'death', texture: 'vortex/vortex1', spin: -0.16,
    children: ['base_death_void'], description: 'Rotating gravitational swirl over a small dark center; 2 particles total.' },
  { name: 'mystery', texture: 'rune/witch_rune', spin: 0.06,
    description: 'Full purple arcane rune disk, resized for the build grid.' },
  { name: 'lightning', texture: 'auras/aura_vlads', spin: 0.12,
    children: ['base_thin_ring'],
    description: 'Electrical branches from reference aura_dark inside a visible thin circular boundary; 2 particles total.' },
  { name: 'machine', texture: 'auras/aura_assaultc', spin: -0.05,
    description: 'Reference aura_durable native mechanical Assault Cuirass ring.' },
  { name: 'multi', texture: 'auras/aura_endurance', spin: 0,
    children: ['base_multi_leaf_a', 'base_multi_leaf_b', 'base_multi_leaf_c'],
    description: 'Three outward leaf-arrow shapes in a fine radial ring; 4 particles total.' },
  { name: 'frost', texture: 'groundcracks_light', spin: 0, children: ['base_thin_ring'],
    description: 'Fine radial ice cracks with an open thin ring; no solid snowflake sprite. 2 particles total.' },
  { name: 'anti_air', texture: 'gyro/gyro_ti10_immortal_missile/gyro_ti10_immortal_missile_target', spin: 0, alpha_masked: true,
    description: 'Native Gyrocopter cosmetic missile crosshair, static to retain targeting identity.' },
  { name: 'ultimate', texture: 'juggernaut/arcana/jugg_arcana_ground_symbol', spin: 0.035, alpha_masked: true,
    description: 'Arcana ground seal, also reused by the reference durable aura; no unit/model dependency.' },
  { name: 'detail_runes', texture: 'rune/witch_rune', spin: -0.065, scale: 1.03, height: 15,
    description: 'Thin counter-rotating outer rune; reusable extra SR/SSR/UR layer.' },
  { name: 'detail_motes', texture: 'auras/aura_endurance', spin: 0.12, scale: 1.1, height: 16,
    description: 'Sparse radial glints with moderate overbright; reusable third layer.' },
  { name: 'base_death_void', texture: 'particle_modulate_03',
    scale: 0.65, height: 12, modulate: true, internal: true,
    description: 'Soft dark center using the exact texture and MOD2X blend from native enigma_blackhole_m; no flat black tint or primitive white texture.' },
  { name: 'base_multi_leaf_a', texture: 'leaf/leaf_grayscale', scale: 0.34,
    offset: [42, 0, 15], roll: 90, internal: true, alpha_masked: true },
  { name: 'base_multi_leaf_b', texture: 'leaf/leaf_grayscale', scale: 0.34,
    offset: [-21, 36.4, 15], roll: 210, internal: true, alpha_masked: true },
  { name: 'base_multi_leaf_c', texture: 'leaf/leaf_grayscale', scale: 0.34,
    offset: [-21, -36.4, 15], roll: 330, internal: true, alpha_masked: true },
  { name: 'base_thin_ring', texture: 'particle_ring_softouter', scale: 0.95,
    height: 15, alpha_scale: 0.20, internal: true, alpha_masked: true,
    description: 'Soft low-alpha boundary shared by lightning and frost, using native Enigma soft outer ring texture.' },
];
const input = (component, factor = 1) => {
  const literal = Number.isInteger(factor) ? factor + '.0' : String(factor);
  return `{ m_nType = "PF_TYPE_CONTROL_POINT_COMPONENT" m_nControlPoint = 1 m_nVectorComponent = ${component} m_nMapType = "PF_MAP_TYPE_MULT" m_flMultFactor = ${literal} }`;
};
for (const definition of definitions) {
  const texture = 'materials/particle/' + definition.texture + '.vtex';
  if (!packs.valve.entries.has(texture + '_c')) throw Error('Missing Valve texture ' + texture);
  const offset = definition.offset || [0, 0, definition.height || 14];
  const text = header + `{
 _class = "CParticleSystemDefinition"
 m_nMaxParticles = 1
 m_flConstantLifespan = 999999.0
 m_flConstantRadius = 96.0
 m_ConstantColor = [255,255,255,255]
 m_nBehaviorVersion = 12
 m_Renderers = [{
  _class = "C_OP_RenderSprites"
  m_nOrientationType = "PARTICLE_ORIENTATION_WORLD_Z_ALIGNED"
  m_flOverbrightFactor = ${definition.modulate || definition.alpha_masked ? '1.0' : '2.0'}
  ${definition.modulate ? 'm_nOutputBlendMode = "PARTICLE_OUTPUT_BLEND_MODE_MOD2X"' : definition.alpha_masked ? '' : 'm_nOutputBlendMode = "PARTICLE_OUTPUT_BLEND_MODE_ADD"'}
  m_flAnimationRate = 0.0
  m_flRadiusScale = { m_nType = "PF_TYPE_LITERAL" m_flLiteralValue = 1.0 }
  m_vecTexturesInput = [{ m_hTexture = resource:"${texture}" }]
 }]
 m_Emitters = [{
  _class = "C_OP_InstantaneousEmitter"
  m_nParticlesToEmit = { m_nType = "PF_TYPE_LITERAL" m_flLiteralValue = 1.0 }
 }]
 m_Initializers = [
  { _class = "C_INIT_CreateWithinSphere" m_fRadiusMax = 0.0 },
  { _class = "C_INIT_InitFloat" m_nOutputField = 7 m_InputValue = ${input(2, definition.alpha_scale || 1)} },
  { _class = "C_INIT_InitFloat" m_nOutputField = 4 m_InputValue = { m_nType = "PF_TYPE_LITERAL" m_flLiteralValue = ${definition.roll || 0}.0 } }
 ]
 m_Operators = [
  { _class = "C_OP_SetFloat" m_nOutputField = 3 m_InputValue = ${input(0, definition.scale || 1)} },
  { _class = "C_OP_SetFloat" m_nOutputField = 7 m_InputValue = ${input(2, definition.alpha_scale || 1)} },
  { _class = "C_OP_SetToCP" m_vecOffset = [${offset.join(',')}] },
  ${definition.modulate ? '' : '{ _class = "C_OP_RemapCPtoVector" m_nCPInput = 2 m_nFieldOutput = 6 m_vInputMax = [255.0,255.0,255.0] m_vOutputMax = [1.0,1.0,1.0] },'}
  ${definition.spin ? '{ _class = "C_OP_RampScalarLinear" m_nField = 4 m_RateMin = ' + definition.spin + ' m_RateMax = ' + definition.spin + ' m_flEndTime_min = 999999.0 m_flEndTime_max = 999999.0 },' : ''}
  { _class = "C_OP_EndCapTimedDecay" m_flDecayTime = 0.15 },
  { _class = "C_OP_LerpEndCapScalar" m_nFieldOutput = 7 m_flLerpTime = 0.15 m_flOutput = 0.0 }
 ]
 ${definition.children ? 'm_Children = [ ' + definition.children.map(name => '{ m_ChildRef = resource:"' + relative + '/' + name + '.vpcf" }').join(', ') + ' ]' : ''}
 m_controlPointConfigurations = [{ m_name = "preview" m_drivers = [
  { m_iControlPoint = 0 m_iAttachType = "PATTACH_WORLDORIGIN" m_entityName = "self" },
  { m_iControlPoint = 1 m_iAttachType = "PATTACH_WORLDORIGIN" m_vecOffset = [112.0,0.0,0.45] m_entityName = "self" },
  { m_iControlPoint = 2 m_iAttachType = "PATTACH_WORLDORIGIN" m_vecOffset = [180.0,120.0,255.0] m_entityName = "self" }
 ] }]
}
`;
  fs.writeFileSync(path.join(out, definition.name + '.vpcf'), formatSource(text));
}
fs.writeFileSync(path.join(root, 'art/effects/tower_bases/source_manifest.json'), JSON.stringify({
  control_points: { 0: 'tower ground origin via ABSORIGIN_FOLLOW',
    1: 'x=radius; z=alpha (0..1); both continuously read from CP', 2: 'RGB 0..255; ignored only by black void underlay' },
  attachment: 'PATTACH_ABSORIGIN_FOLLOW; SetParticleControlEnt CP0; internal SetToCP keeps all layers attached after D relocation.',
  ground_offset: 'All sprites WORLD_Z_ALIGNED and ground origin +12..16 units.',
  cleanup: 'DestroyParticle(false), ReleaseParticleIndex; endcaps last at most 0.15 seconds.',
  resources: definitions.map(d => ({ name: d.name, resource: relative + '/' + d.name + '.vpcf',
    internal: d.internal === true, total_max_particles: 1 + (d.children || []).length,
    texture: 'materials/particle/' + d.texture + '.vtex', blend: d.modulate ? 'modulate2x' : d.alpha_masked ? 'alpha' : 'additive',
    description: d.description || 'Static leaf child for multi-shot base.' })),
}, null, 2) + '\n');
console.log(JSON.stringify({ sourceRoot, public_resources: definitions.filter(d => !d.internal).length,
  compiled_targets: definitions.length }));
