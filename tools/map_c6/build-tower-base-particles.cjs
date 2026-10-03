'use strict';
// Small ground-only tower ornaments. Uses Valve textures and the reference
// aura composition approach, with explicit size/alpha/color control points.
const fs = require('fs');
const path = require('path');
const { packs } = require('./inspect-effect-resources.cjs');
const root = path.resolve(__dirname, '../..');
const sourceRoot = path.join(root, 'art/effects/tower_bases/source');
// Separate the refined assets from the accepted legacy files. A running game
// may still hold old particle handles; those same-path resources stay intact.
const relative = 'particles/survival/towers/bases';
const out = path.join(sourceRoot, relative);
fs.mkdirSync(out, { recursive: true });
// Legacy CreateWithinSphere needs Valve's version migration. Declaring the
// latest format around a legacy operator leaves a nonfunctional placeholder.
const header = '<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->\n';
const formatSource = text => text.split(/\r?\n/)
  .map(line => line.replace(/[ \t]+$/, ''))
  .filter(line => line.trim() !== '').join('\n') + '\n';
// Keep the R silhouette readable. Tier detail stays inside that silhouette;
// no profession receives another profession's full-size rune disk.
const definitions = [
  { name: 'death', texture: 'vortex/vortex1', spin: -0.16,
    children: ['base_death_void'], description: 'Rotating gravitational swirl over a small dark center; 2 particles total.' },
  { name: 'mystery', texture: 'rune/witch_rune', spin: 0.06,
    description: 'Purple arcane rune disk, reserved for the mystery profession.' },
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
  { name: 'anti_air', texture: 'ping_world_crosshairs3', spin: 0, scale: 0.94,
    description: 'Native circular aiming reticle with fine center lines and open quadrants; replaces the filled Gyrocopter square.' },
  { name: 'ultimate', texture: 'juggernaut/arcana/jugg_arcana_ground_symbol', spin: 0.035, alpha_masked: true,
    description: 'Arcana ground seal, also reused by the reference durable aura; no unit/model dependency.' },
  { name: 'detail_ultimate', texture: 'auras/aura_assaultc', spin: -0.035,
    scale: 0.82, alpha_scale: 0.65, height: 16,
    description: 'Small counter-rotating ceremonial pattern inside the UR seal; no generic outer rune.' },
  { name: 'detail_motes', texture: 'auras/aura_endurance', spin: 0.075, scale: 0.72, height: 18,
    alpha_scale: 0.7,
    description: 'Red-star/UR only: subdued inner glints, never a second wide halo.' },
  { name: 'base_death_void', texture: 'particle_modulate_03',
    scale: 0.65, height: 12, modulate: true, internal: true,
    description: 'Soft dark center using the exact texture and MOD2X blend from native enigma_blackhole_m; no flat black tint or primitive white texture.' },
  { name: 'base_multi_leaf_a', texture: 'leaf/leaf_grayscale', scale: 0.30,
    offset: [36, 0, 15], roll: 90, internal: true, alpha_masked: true },
  { name: 'base_multi_leaf_b', texture: 'leaf/leaf_grayscale', scale: 0.30,
    offset: [-18, 31.2, 15], roll: 210, internal: true, alpha_masked: true },
  { name: 'base_multi_leaf_c', texture: 'leaf/leaf_grayscale', scale: 0.30,
    offset: [-18, -31.2, 15], roll: 330, internal: true, alpha_masked: true },
  { name: 'base_thin_ring', texture: 'particle_ring_softouter', scale: 0.95,
    height: 15, alpha_scale: 0.20, internal: true, alpha_masked: true,
    description: 'Soft low-alpha boundary shared by lightning and frost, using native Enigma soft outer ring texture.' },
];
// Each tier uses a single extra sprite. Texture, orientation and counter-spin
// carry the profession identity rather than adding more full-size layers.
const tierDetails = [
  { name: 'death', texture: 'vortex/vortex1', scale: [0.70, 0.84], spin: [0.065, 0.10], roll: 90, alpha: 0.75,
    description: 'Compact reverse-flow gravitational spiral' },
  { name: 'mystery', texture: 'rune/witch_rune', scale: [0.80, 0.92], spin: [-0.045, -0.075], roll: 30, alpha: 0.65,
    description: 'Counter-rotating arcane engraving, exclusive to mystery' },
  { name: 'lightning', texture: 'auras/aura_vlads', scale: [0.73, 0.89], spin: [-0.18, -0.26], roll: 90, alpha: 0.72,
    description: 'Reverse-spinning fine electrical branches' },
  { name: 'machine', texture: 'auras/aura_assaultc', scale: [0.70, 0.86], spin: [0.04, 0.065], roll: 45, alpha: 0.66,
    description: 'Slow mechanical inner engraving' },
  { name: 'multi', texture: 'auras/aura_endurance', scale: [0.78, 0.92], spin: [-0.035, -0.06], roll: 22.5, alpha: 0.55,
    description: 'Sparse radial arrow-like glints behind the three leaf tips' },
  { name: 'frost', texture: 'groundcracks_light', scale: [0.72, 0.87], spin: [0, 0], roll: 60, alpha: 0.60,
    description: 'Static offset ice fissures, avoiding a rotating magic circle' },
  { name: 'anti_air', texture: 'ping_world_crosshairs3', scale: [0.58, 0.70], spin: [0, 0], roll: 45, alpha: 0.55,
    description: 'Small static diagonal aiming calibration inside the outer circular sight' },
];
for (const detail of tierDetails) {
  for (const [index, tier] of ['sr', 'ssr'].entries()) {
    definitions.push({ name: 'detail_' + detail.name + '_' + tier, texture: detail.texture,
      scale: detail.scale[index], spin: detail.spin[index], roll: detail.roll,
      alpha_scale: detail.alpha, height: 16,
      description: detail.description + '; ' + tier.toUpperCase() + ' uses one contained detail sprite.' });
  }
}
const float = value => Number.isInteger(value) ? value + '.0' : String(value);
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
  m_flOverbrightFactor = ${definition.modulate || definition.alpha_masked ? '1.0' : '1.2'}
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
  { _class = "C_INIT_InitFloat" m_nOutputField = 4 m_InputValue = { m_nType = "PF_TYPE_LITERAL" m_flLiteralValue = ${float(definition.roll || 0)} } }
 ]
 m_Operators = [
  { _class = "C_OP_SetFloat" m_nOutputField = 3 m_InputValue = ${input(0, definition.scale || 1)} },
  { _class = "C_OP_SetFloat" m_nOutputField = 7 m_InputValue = ${input(2, definition.alpha_scale || 1)} },
  { _class = "C_OP_SetToCP" m_vecOffset = [${offset.map(float).join(',')}] },
  ${definition.modulate ? '' : '{ _class = "C_OP_RemapCPtoVector" m_nCPInput = 2 m_nFieldOutput = 6 m_vInputMax = [255.0,255.0,255.0] m_vOutputMax = [1.0,1.0,1.0] },'}
  ${definition.spin ? '{ _class = "C_OP_RampScalarLinear" m_nField = 4 m_RateMin = ' + definition.spin + ' m_RateMax = ' + definition.spin + ' m_flEndTime_min = 999999.0 m_flEndTime_max = 999999.0 },' : ''}
  { _class = "C_OP_EndCapTimedDecay" m_flDecayTime = 0.15 },
  { _class = "C_OP_LerpEndCapScalar" m_nFieldOutput = 7 m_flLerpTime = 0.15 m_flOutput = 0.0 }
 ]
 ${definition.children ? 'm_Children = [ ' + definition.children.map(name => '{ m_ChildRef = resource:"' + relative + '/' + name + '.vpcf" }').join(', ') + ' ]' : ''}
 m_controlPointConfigurations = [{ m_name = "preview" m_drivers = [
  { m_iControlPoint = 0 m_iAttachType = "PATTACH_WORLDORIGIN" m_entityName = "self" },
  { m_iControlPoint = 1 m_iAttachType = "PATTACH_WORLDORIGIN" m_vecOffset = [100.0,0.0,0.45] m_entityName = "self" },
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
  art_revision: '20261001_contained_profession_details',
  ground_offset: 'All sprites WORLD_Z_ALIGNED and ground origin +12..18 units, with explicit FLOAT SetToCP offsets.',
  cleanup: 'Production removes ownership then DestroyParticle(true), ReleaseParticleIndex; source retains 0.15 second endcaps for editor use.',
  tier_policy: 'N none; R core; SR core + profession detail_sr; SSR core + profession detail_ssr; red SSR/UR add small inner glints. No increase in handle or child-sprite counts.',
  resources: definitions.map(d => ({ name: d.name, resource: relative + '/' + d.name + '.vpcf',
    internal: d.internal === true, total_max_particles: 1 + (d.children || []).length,
    texture: 'materials/particle/' + d.texture + '.vtex', blend: d.modulate ? 'modulate2x' : d.alpha_masked ? 'alpha' : 'additive',
    radius_scale: d.scale || 1, alpha_scale: d.alpha_scale || 1,
    overbright: d.modulate || d.alpha_masked ? 1 : 1.2, spin: d.spin || 0,
    children: d.children || [],
    description: d.description || 'Static leaf child for multi-shot base.' })),
}, null, 2) + '\n');
console.log(JSON.stringify({ sourceRoot, public_resources: definitions.filter(d => !d.internal).length,
  compiled_targets: definitions.length }));
