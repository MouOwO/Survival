'use strict';
// Native-style persistent rope nodes; Lua owns one collection until the target
// changes. CP9/CP0 follow the source attachment, CP1 follows the target body.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { Vpk } = require('./lib.cjs');
const root = path.resolve(__dirname, '../..');
const output = path.join(root, 'art/effects/laser');
const resourceRoot = 'particles/survival/towers/';
const header = '<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->\n';
const literal = value => ({ m_nType: 'PF_TYPE_LITERAL', m_flLiteralValue: float(value) });
const ref = value => ({ resource: value });
const float = value => ({ float: value });
const init = (field, value) => ({ _class: 'C_INIT_InitFloat', m_nOutputField: field, m_InputValue: literal(value) });
const nativeTextures = [
  'materials/particle/beam_hotwhite.vtex',
  'materials/particle/beam_hotblue2.vtex',
  'materials/particle/particle_glow_05.vtex',
  'materials/particle/particle_flares/particle_flare_001.vtex',
];
function kv(value) {
  if (Array.isArray(value)) return '[ ' + value.map(kv).join(', ') + ' ]';
  if (value && value.resource) return 'resource:' + JSON.stringify(value.resource);
  if (value && Object.hasOwn(value, 'float')) return Number(value.float).toFixed(1);
  if (value && typeof value === 'object') return '{\n' + Object.entries(value)
    .map(([key, field]) => ' ' + key + ' = ' + kv(field)).join('\n') + '\n}';
  return JSON.stringify(value);
}
function system(count, radius, color) {
  return { _class: 'CParticleSystemDefinition', m_nBehaviorVersion: 12,
    m_bShouldHitboxesFallbackToRenderBounds: false,
    m_nMaxParticles: count, m_flConstantLifespan: float(999999),
    m_flConstantRadius: float(radius), m_ConstantColor: color,
    m_Emitters: [{ _class: 'C_OP_InstantaneousEmitter', m_nParticlesToEmit: literal(count) }],
    m_Operators: [{ _class: 'C_OP_EndCapTimedDecay', m_flDecayTime: float(0.1) }] };
}
function rope(texture, radius, color, brightness, alpha) {
  const definition = system(12, radius, color);
  const pathParams = { m_nStartControlPointNumber: 9, m_nEndControlPointNumber: 1 };
  definition.m_Initializers = [
    { _class: 'C_INIT_CreateSequentialPath', m_flNumToAssign: float(12), m_PathParams: pathParams },
    init(7, alpha),
  ];
  definition.m_Operators.unshift({ _class: 'C_OP_MaintainSequentialPath',
    m_flNumToAssign: float(12), m_PathParams: pathParams });
  definition.m_Renderers = [{ _class: 'C_OP_RenderRopes',
    m_flOverbrightFactor: float(brightness), m_flRadiusScale: float(0.5),
    m_flTextureVWorldSize: float(1000), m_nMinTesselation: 2, m_nMaxTesselation: 2,
    m_nOutputBlendMode: 'PARTICLE_OUTPUT_BLEND_MODE_ADD',
    m_vecTexturesInput: [{ m_hTexture: ref(texture),
      m_TextureControls: { m_flFinalTextureScaleU: literal(-1) } }] }];
  return definition;
}
function impact(texture, radius, color, brightness, alpha) {
  const definition = system(1, radius, color);
  definition.m_Initializers = [
    { _class: 'C_INIT_CreateWithinSphere', m_nControlPointNumber: 1 }, init(7, alpha),
  ];
  // This CP is an entity attachment, never a world snapshot supplied by Lua.
  definition.m_Operators.unshift({ _class: 'C_OP_SetToCP', m_nControlPointNumber: 1 });
  definition.m_Renderers = [{ _class: 'C_OP_RenderSprites',
    m_flOverbrightFactor: float(brightness),
    m_nOutputBlendMode: 'PARTICLE_OUTPUT_BLEND_MODE_ADD',
    m_vecTexturesInput: [{ m_hTexture: ref(texture) }] }];
  return definition;
}
function definitions() {
  const result = {
    laser_beam: rope(nativeTextures[0], 20, [210, 240, 255, 255], 3, 1),
    laser_beam_envelope: rope(nativeTextures[1], 38, [25, 125, 255, 255], 3, 0.8),
    laser_beam_hit: impact(nativeTextures[2], 13, [210, 240, 255, 255], 3, 1),
    laser_beam_hit_flare: impact(nativeTextures[3], 22, [55, 160, 255, 255], 2, 0.8),
  };
  result.laser_beam.m_Children = Object.keys(result).slice(1)
    .map(name => ({ m_ChildRef: ref(resourceRoot + name + '.vpcf') }));
  result.laser_beam.m_controlPointConfigurations = [{ m_name: 'preview', m_drivers: [
    { m_iControlPoint: 0, m_iAttachType: 'PATTACH_WORLDORIGIN', m_entityName: 'self' },
    { m_iControlPoint: 9, m_iAttachType: 'PATTACH_WORLDORIGIN', m_entityName: 'self' },
    { m_iControlPoint: 1, m_iAttachType: 'PATTACH_WORLDORIGIN', m_entityName: 'self',
      m_vecOffset: [float(500), float(0), float(0)] },
  ] }];
  return result;
}
function build() {
  const native = new Vpk(path.resolve(root, '../../dota/pak01_dir.vpk'));
  for (const resource of nativeTextures) {
    if (!native.entries.has(resource + '_c')) throw Error('Missing native texture ' + resource);
  }
  const outputs = [];
  for (const [name, definition] of Object.entries(definitions())) {
    const resource = resourceRoot + name + '.vpcf';
    const source = header + kv(definition) + '\n';
    const filename = path.join(output, 'source', resource);
    fs.mkdirSync(path.dirname(filename), { recursive: true });
    fs.writeFileSync(filename, source);
    outputs.push({ resource, max_particles: definition.m_nMaxParticles,
      sha256: crypto.createHash('sha256').update(source).digest('hex') });
  }
  fs.writeFileSync(path.join(output, 'manifest.json'), JSON.stringify({
    generated_by: 'tools/map_c6/build-laser-visual-particles.cjs',
    native_structure_references: [
      'particles/units/heroes/hero_phoenix/phoenix_sunray_beam_core.vpcf',
      'particles/units/heroes/hero_wisp/wisp_tether.vpcf',
    ],
    control_points: { 0: 'source child anchor', 9: 'source attachment', 1: 'target body attachment' },
    lifecycle: 'Instantaneous nodes persist; no normal-state decay/fade. Lua immediately destroys on target exit.',
    custom_particle_budget: 26, lua_particle_handles_per_target: 1,
    art: '20-radius white-blue core, 38-radius saturated envelope; 13/22-radius impact, depth-tested.',
    native_textures: nativeTextures, outputs,
  }, null, 2) + '\n');
  console.log('LASER_VISUAL_SOURCES_PASS particles=' + outputs.length + ' budget=26');
}
if (require.main === module) build();
module.exports = { definitions, nativeTextures, resourceRoot, build };
