'use strict';
// Native-style persistent rope nodes; Lua owns one collection until the target
// changes. CP9/CP0 are the overhead orb; Lua samples the head surface at CP1.
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
  'materials/particle/blood_generic_spattering_color.vtex',
  'materials/particle/spark_glow_01.vtex',
  'materials/particle/beam_generic_3.vtex',
  'materials/particle/sparks/sparks.vtex',
  'materials/particle/particle_flares/aircraft_blue2.vtex',
  'materials/particle/orb_tintable/particle_energy_orb_fluid_tintable.vtex',
  'materials/particle/beam_hotblue.vtex',
  'materials/particle/electricity/electricity_beam_white_a.vtex',
  'materials/particle/electrical_arc/electrical_arc.vtex',
];
function kv(value) {
  if (Array.isArray(value)) return '[ ' + value.map(kv).join(', ') + ' ]';
  if (value && value.resource) return 'resource:' + JSON.stringify(value.resource);
  if (value && Object.hasOwn(value, 'float')) return Number.isInteger(value.float) ? value.float.toFixed(1) : String(value.float);
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
  // Beam impacts follow the head-surface CP; the charge orb uses tower CP0.
  definition.m_Operators.unshift({ _class: 'C_OP_SetToCP', m_nControlPointNumber: 1 });
  definition.m_Renderers = [{ _class: 'C_OP_RenderSprites',
    m_flOverbrightFactor: float(brightness),
    m_nOutputBlendMode: 'PARTICLE_OUTPUT_BLEND_MODE_ADD',
    m_vecTexturesInput: [{ m_hTexture: ref(texture) }] }];
  return definition;
}
function definitions() {
  const nativeDefinition = name => JSON.parse(fs.readFileSync(path.join(output, 'reference/io', name + '.json'), 'utf8'));
  // Use Io's actual beam material, width, renderer and electric filament DATA.
  // Only adapt endpoint ownership/lifetime and cap emission for tower battles.
  const io = nativeDefinition('wisp_tether');
  io.m_nMaxParticles = 16;
  io.m_flConstantLifespan = float(999999);
  io.m_Operators = io.m_Operators.filter(op => ['C_OP_MaintainSequentialPath','C_OP_EndCapTimedDecay'].includes(op._class));
  for (const op of [...io.m_Operators, ...io.m_Initializers]) {
    if (op.m_PathParams) op.m_PathParams.m_nStartControlPointNumber = 9;
  }
  const result = {
    laser_beam: io,
    laser_beam_hit: impact(nativeTextures[2], 24, [255, 255, 255, 255], 2, 1),
    laser_beam_hit_flare: impact(nativeTextures[3], 24, [255, 255, 255, 255], 1.4, 0.6),
  };
  const tint = () => ({ _class: 'C_OP_RemapCPtoVector', m_nCPInput: 2,
    m_nFieldOutput: 6, m_vInputMax: [float(255),float(255),float(255)],
    m_vOutputMax: [float(1),float(1),float(1)] });
  for (const [name, definition] of Object.entries(result)) {
    if (name !== 'laser_beam') definition.m_Operators.unshift(tint());
  }
  const electric = nativeDefinition('wisp_tether_c');
  electric.m_nMaxParticles = 32;
  delete electric.m_nFirstMultipleOverride_BackwardCompat;
  for (const op of [...electric.m_Operators, ...electric.m_Initializers]) {
    if (op.m_PathParams) op.m_PathParams.m_nStartControlPointNumber = 9;
  }
  result.laser_beam_io_electric = electric;
  // Zeus static field's model-bound arcs, sustained only while this beam exists.
  // CP7 owns the enemy model; CP1 remains the independently sampled head point.
  const arcs = nativeDefinition('zuus_static_field_b');
  arcs.m_nMaxParticles = 16;
  arcs.m_bShouldHitboxesFallbackToRenderBounds = true;
  arcs.m_Emitters = [{ _class:'C_OP_ContinuousEmitter', m_flEmitRate:literal(24) }];
  for (const op of [...arcs.m_Operators, ...arcs.m_Initializers]) {
    if (['C_OP_LockToBone','C_INIT_CreateOnModel'].includes(op._class)) op.m_nControlPointNumber = 7;
  }
  for (const renderer of arcs.m_Renderers) delete renderer.m_nHSVShiftControlPoint;
  result.laser_target_electric = arcs;
  // Reference tinker_laser_f: age-driven CP9 -> CP1 travel, not ambient drift.
  // Constraints re-evaluate moving endpoints; lifetime prevents overshoot.
  const travel = (count, radius, seconds, rate, spread) => {
    const p = system(count, radius, [255,255,255,255]);
    p.m_flConstantLifespan = float(seconds);
    p.m_Emitters = [{ _class: 'C_OP_ContinuousEmitter', m_flEmitRate: literal(rate) }];
    p.m_Initializers = [{ _class: 'C_INIT_CreateWithinSphere', m_nControlPointNumber: 9, m_fRadiusMax: float(spread) }];
    p.m_Operators = [tint(), { _class: 'C_OP_BasicMovement' },
      { _class: 'C_OP_FadeOutSimple', m_flFadeOutTime: float(0.85) }, { _class: 'C_OP_Decay' }];
    p.m_Constraints = [{ _class: 'C_OP_ConstrainDistanceToPath', m_flTravelTime: float(seconds),
      m_flMaxDistance0: float(spread), m_flMaxDistance1: float(0),
      m_PathParameters: { m_nStartControlPointNumber: 9, m_nEndControlPointNumber: 1 } }];
    return p;
  };
  const motes = travel(24, 3, 0.14, 80, 12);
  motes.m_Renderers = [{ _class: 'C_OP_RenderTrails', m_flOverbrightFactor: float(3),
    m_flMaxLength: float(48), m_flLengthFadeInTime: float(0.02),
    m_nOutputBlendMode: 'PARTICLE_OUTPUT_BLEND_MODE_ADD',
    m_vecTexturesInput: [{ m_hTexture: ref(nativeTextures[7]) }] }];
  result.laser_beam_motes = motes;
  const pulse = travel(8, 11, 0.18, 9, 0);
  pulse.m_Renderers = impact(nativeTextures[2], 11, [255,255,255,255], 4, 1).m_Renderers;
  result.laser_beam_pulse = pulse;
  // Match the visual pulse cadence, with a travel-time offset; purely cosmetic.
  const strike = impact(nativeTextures[3], 28, [255,255,255,255], 3, 1);
  strike.m_nMaxParticles = 4;
  strike.m_flConstantLifespan = float(0.09);
  strike.m_Emitters = [{ _class: 'C_OP_ContinuousEmitter', m_flStartTime: literal(0.18), m_flEmitRate: literal(9) }];
  strike.m_Operators = [tint(), { _class: 'C_OP_SetToCP', m_nControlPointNumber: 1 },
    { _class: 'C_OP_InterpolateRadius', m_flStartScale: float(0.65), m_flEndScale: float(1.2) },
    { _class: 'C_OP_FadeOutSimple', m_flFadeOutTime: float(0.25) }, { _class: 'C_OP_Decay' }];
  result.laser_beam_strike = strike;
  // Reference laser_cutter_sparks: short upward cutting trails at the impact.
  const sparks = system(16, 2, [255,255,255,255]);
  sparks.m_flConstantLifespan = float(0.3);
  sparks.m_Emitters = [{ _class: 'C_OP_ContinuousEmitter', m_flEmitRate: literal(40) }];
  sparks.m_Initializers = [{ _class: 'C_INIT_CreateWithinSphere', m_nControlPointNumber: 1,
    m_fRadiusMax: float(5), m_fSpeedMin: float(60), m_fSpeedMax: float(160),
    m_LocalCoordinateSystemSpeedMin: [float(-90),float(-90),float(60)],
    m_LocalCoordinateSystemSpeedMax: [float(90),float(90),float(190)] }];
  sparks.m_Operators = [tint(), { _class: 'C_OP_BasicMovement', m_Gravity: [float(0),float(0),float(-350)], m_fDrag: float(0.5) },
    { _class: 'C_OP_FadeOutSimple', m_flFadeOutTime: float(0.6) }, { _class: 'C_OP_Decay' }];
  sparks.m_Renderers = [{ _class: 'C_OP_RenderTrails', m_flOverbrightFactor: float(4),
    m_flMaxLength: float(25), m_flLengthFadeInTime: float(0.05),
    m_nOutputBlendMode: 'PARTICLE_OUTPUT_BLEND_MODE_ADD',
    m_vecTexturesInput: [{ m_hTexture: ref(nativeTextures[7]) }] }];
  result.laser_beam_sparks = sparks;
  result.laser_beam.m_Children = Object.keys(result).slice(1)
    .map(name => ({ m_ChildRef: ref(resourceRoot + name + '.vpcf') }));
  result.laser_beam.m_controlPointConfigurations = [{ m_name: 'preview', m_drivers: [
    { m_iControlPoint: 2, m_iAttachType: 'PATTACH_WORLDORIGIN', m_entityName: 'self', m_vecOffset: [float(80),float(150),float(255)] },
    { m_iControlPoint: 0, m_iAttachType: 'PATTACH_WORLDORIGIN', m_entityName: 'self' },
    { m_iControlPoint: 9, m_iAttachType: 'PATTACH_WORLDORIGIN', m_entityName: 'self' },
    { m_iControlPoint: 1, m_iAttachType: 'PATTACH_WORLDORIGIN', m_entityName: 'self',
      m_vecOffset: [float(500), float(0), float(0)] },
  ] }];
  const cp = (factor) => ({ m_nType: 'PF_TYPE_CONTROL_POINT_COMPONENT', m_nControlPoint: 1,
    m_nVectorComponent: 0, m_nMapType: 'PF_MAP_TYPE_MULT', m_flMultFactor: float(factor) });
  const blood = system(32, 7, [180,18,25,255]);
  blood.m_flConstantLifespan = float(0.55);
  blood.m_Emitters = [{ _class: 'C_OP_InstantaneousEmitter', m_nParticlesToEmit: cp(8) }];
  blood.m_Initializers = [{ _class: 'C_INIT_CreateWithinSphere', m_fRadiusMax: float(8),
    m_fSpeedMin: float(55), m_fSpeedMax: float(110) }, init(7, 0.9)];
  blood.m_Operators = [{ _class: 'C_OP_BasicMovement', m_Gravity: [float(0),float(0),float(-220)], m_fDrag: float(0.1) },
    { _class: 'C_OP_FadeOutSimple', m_flFadeOutTime: float(0.6) }, { _class: 'C_OP_Decay' }];
  blood.m_Renderers = [{ _class: 'C_OP_RenderSprites', m_vecTexturesInput: [{ m_hTexture: ref(nativeTextures[4]) }] }];
  result.laser_blood = blood;
  // Legacy custom beam support; native Tinker mode does not create this orb.
  const charge = impact(nativeTextures[9], 10, [180,235,255,255], 1.2, 0.9);
  charge.m_Initializers[0].m_nControlPointNumber = 0;
  charge.m_Operators[0].m_nControlPointNumber = 0;
  charge.m_Operators[0].m_vecOffset = [float(0),float(0),float(185)];
  result.laser_charge = charge;
  charge.m_Operators.push({ _class: 'C_OP_RampScalarLinear', m_nField: 4,
    m_RateMin: float(0.45), m_RateMax: float(0.45), m_flEndTime_min: float(999999), m_flEndTime_max: float(999999) });
  // Adapt illuminate_charge_b: particles from the torso are pulled upward
  // into an explicit orb CP. Both CPs follow the same tower through relocation.
  const feed = system(12, 2, [160,220,255,255]);
  feed.m_PreEmissionOperators = [{ _class: 'C_OP_SetControlPointPositions',
    m_nHeadLocation: 0, m_nCP1: 3, m_nCP2: 4, m_nCP3: 5, m_nCP4: 6,
    m_vecCP1Pos: [float(0),float(0),float(70)],
    m_vecCP2Pos: [float(0),float(0),float(185)],
    m_vecCP3Pos: [float(0),float(0),float(0)], m_vecCP4Pos: [float(0),float(0),float(0)] }];
  feed.m_flConstantLifespan = float(0.55);
  feed.m_Emitters = [{ _class: 'C_OP_ContinuousEmitter', m_flEmitRate: literal(18) }];
  feed.m_Initializers = [{ _class: 'C_INIT_CreateWithinSphere', m_nControlPointNumber: 3,
    m_fRadiusMin: float(12), m_fRadiusMax: float(35),
    m_LocalCoordinateSystemSpeedMin: [float(-12),float(-12),float(90)],
    m_LocalCoordinateSystemSpeedMax: [float(12),float(12),float(140)] }];
  feed.m_Operators = [{ _class: 'C_OP_BasicMovement', m_fDrag: float(0.1) },
    { _class: 'C_OP_FadeInSimple', m_flFadeInTime: float(0.08) },
    { _class: 'C_OP_FadeOutSimple', m_flFadeOutTime: float(0.8) }, { _class: 'C_OP_Decay' }];
  feed.m_ForceGenerators = [{ _class: 'C_OP_AttractToControlPoint', m_nControlPointNumber: 4,
    m_fForceAmount: literal(240), m_fFalloffPower: float(0) }];
  feed.m_Renderers = impact(nativeTextures[2], 2, [160,220,255,255], 1.2, 1).m_Renderers;
  result.laser_charge_feed = feed;
  charge.m_Children = ['laser_charge_feed'].map(name => ({ m_ChildRef: ref(resourceRoot + name + '.vpcf') }));
  // Detached death tail: all emitters fire once, all particles expire in 0.3s.
  // Never inherit the live beam's continuous children or enemy model binding.
  const afterglow = JSON.parse(JSON.stringify(io));
  afterglow.m_flConstantLifespan = float(0.3);
  afterglow.m_Children = [{ m_ChildRef:ref(resourceRoot + 'laser_afterglow_arcs.vpcf') }];
  afterglow.m_Operators = afterglow.m_Operators.filter(op => op._class !== 'C_OP_EndCapTimedDecay');
  afterglow.m_Operators.push({ _class:'C_OP_FadeOutSimple', m_flFadeOutTime:float(0.25) }, { _class:'C_OP_Decay' });
  result.laser_afterglow = afterglow;
  const afterglowArcs = system(8, 22, [180,220,255,255]);
  afterglowArcs.m_flConstantLifespan = float(0.3);
  afterglowArcs.m_Initializers = [
    { _class:'C_INIT_CreateWithinSphere', m_nControlPointNumber:1, m_fRadiusMax:float(24), m_fSpeedMax:float(45) },
    { _class:'C_INIT_RandomSequence', m_nSequenceMax:3 },
    { _class:'C_INIT_InitFloat', m_nOutputField:4, m_InputValue:{m_nType:'PF_TYPE_RANDOM_UNIFORM',m_flRandomMin:float(0),m_flRandomMax:float(360)} },
  ];
  afterglowArcs.m_Operators = [{_class:'C_OP_BasicMovement'},
    {_class:'C_OP_FadeOutSimple',m_flFadeOutTime:float(0.2)}, {_class:'C_OP_Decay'}];
  afterglowArcs.m_Renderers = impact(nativeTextures[12],22,[180,220,255,255],2,1).m_Renderers;
  result.laser_afterglow_arcs = afterglowArcs;
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
      'particles/units/heroes/hero_wisp/wisp_tether.vpcf',
      'particles/units/heroes/hero_wisp/wisp_tether_c.vpcf',
      'particles/units/heroes/hero_zuus/zuus_static_field_b.vpcf',
    ],
    control_points: { 0: 'beam orb / burst origin / charge tower origin', 9: 'beam orb (tower origin +185)', 1: 'head surface / blood strength 1..4', 2: 'tier accent RGB 0..255; Io core and orb stay blue-white', 3: 'feed torso (origin +70)', 4: 'feed attractor (origin +185)', 7: 'enemy entity for model-bound Zeus arcs' },
    lifecycle: 'Beam rope/impact nodes persist until target exit. Motes have bounded continuous emission and decay; blood is a released finite burst; charge is owned by tower visual lifecycle.',
    custom_particle_budget: outputs.reduce((n,row)=>n+row.max_particles,0), lua_particle_handles_per_target: 1,
    death_afterglow: { seconds:0.3, particles_per_kill:24, lua_timers:0, entity_bindings:0, lifecycle:'Instant burst released to engine; snapshot endpoints survive target removal.' },
    reference_workshop: '3164617180: tinker_1/big_laser, laser_cutter_sparks, illuminate_charge_b; see reference_manifest.json',
    reference_native: 'reference/io/manifest.json; native Io tether core and electric strand, Zeus model-bound static field arcs',
    art: 'Legacy custom Io beam resources retained for compatibility. Production CSV now directly selects native Tinker Q variants; no Io charge orb is created in native mode.',
    native_textures: nativeTextures, outputs,
  }, null, 2) + '\n');
  console.log('LASER_VISUAL_SOURCES_PASS particles=' + outputs.length + ' budget=' + outputs.reduce((n,row)=>n+row.max_particles,0));
}
if (require.main === module) build();
module.exports = { definitions, nativeTextures, resourceRoot, build };
