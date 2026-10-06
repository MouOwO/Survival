'use strict';
// World Chasm Artifact Black Hole, following the existing void-pulse movement.
// CP0 = current ground center; CP20.x = damage radius300;
// CP21.x = slow range600 at levels3-5, otherwise0.
const fs = require('fs'), path = require('path'), cp = require('child_process');
const assert = require('assert'), crypto = require('crypto');
const { endOf } = require('./lib.cjs');
const repo = path.resolve(__dirname, '../..'), engine = path.resolve(repo, '../../..');
const game = path.join(engine, 'game/dota');
const nativePrefix = 'particles/econ/items/enigma/enigma_world_chasm/enigma_blackhole_ti5';
const targetPrefix = 'particles/survival/skills/void_world_chasm';
const output = path.join(repo, 'art/effects/void_world_chasm');
const header = '<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->\n';
const referenceRadius = 300, nativeSpatialReference = 800, spatialScale = referenceRadius / nativeSpatialReference;
const number = value => ({ __number: value, raw: Number.isInteger(value) ? value.toFixed(1) : String(value) });
const integer = value => ({ __number: value, raw: String(value) });
const n = value => value && typeof value === 'object' && '__number' in value ? value.__number : value;
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const vector = values => values.map(number);
const literal = value => ({ m_nType: 'PF_TYPE_LITERAL', m_flLiteralValue: number(value) });
const radius = (factor, control = 20) => ({ m_nType: 'PF_TYPE_CONTROL_POINT_COMPONENT', m_nControlPoint: integer(control), m_nVectorComponent: integer(0), m_nMapType: 'PF_MAP_TYPE_MULT', m_flMultFactor: number(factor) });
function parse(text) {
  const tokens = text.match(/resource:"(?:\\.|[^"\\])*"|"(?:\\.|[^"\\])*"|[{}\[\]=,]|[^\s{}\[\]=,]+/g); let i = 0;
  function value() {
    const token = tokens[i++];
    if (token === '{') { const object = {}; while (tokens[i] !== '}') { const key = tokens[i++]; assert.equal(tokens[i++], '='); object[key] = value(); if (tokens[i] === ',') i++; } i++; return object; }
    if (token === '[') { const array = []; while (tokens[i] !== ']') { array.push(value()); if (tokens[i] === ',') i++; } i++; return array; }
    if (token.startsWith('resource:')) return { __resource: JSON.parse(token.slice(9)) };
    if (token.startsWith('"')) return JSON.parse(token);
    if (token === 'true' || token === 'false') return token === 'true';
    if (token === 'null') return null;
    assert(Number.isFinite(Number(token)), 'Unexpected native KV3 token ' + token);
    return { __number: Number(token), raw: token };
  }
  const result = value(); assert.equal(i, tokens.length); return result;
}
function kv(value, indent = 0) {
  if (value === null) return 'null';
  if (Array.isArray(value)) return '[ ' + value.map(v => kv(v, indent)).join(', ') + ' ]';
  if (value && typeof value === 'object' && '__number' in value) return value.raw;
  if (value && typeof value === 'object' && '__resource' in value) return 'resource:' + JSON.stringify(value.__resource);
  if (typeof value === 'object') return '{\n' + Object.entries(value).map(([key, v]) => '\t'.repeat(indent + 1) + key + ' = ' + kv(v, indent + 1)).join('\n') + '\n' + '\t'.repeat(indent) + '}';
  return JSON.stringify(value);
}
function dump(resource) {
  return cp.execFileSync(path.join(engine, 'game/bin/win64/resourceinfo.exe'), ['-game', game, '-i', resource + '_c', '-all'], { encoding: 'utf8', windowsHide: true, maxBuffer: 16 * 1024 * 1024 });
}
function native(resource) {
  const raw = dump(resource), marker = raw.indexOf('--- vpcf block DATA'), open = raw.indexOf('{', marker);
  assert(marker >= 0, 'Missing native DATA: ' + resource);
  const data = raw.slice(open, endOf(raw, open)); return { tree: parse(data), data };
}
function scale(object, key, factor = spatialScale) {
  if (object[key] === undefined) return;
  const value = object[key];
  if (Array.isArray(value)) object[key] = value.map(v => number(n(v) * factor));
  else if (value && '__number' in value) object[key] = number(n(value) * factor);
  else if (value && typeof value === 'object') for (const field of ['m_flLiteralValue', 'm_flRandomMin', 'm_flRandomMax']) scale(value, field, factor);
}
function scalar(input) {
  if (input === undefined) return 0;
  if (input && '__number' in input) return n(input);
  assert.equal(input.m_nType, 'PF_TYPE_LITERAL'); return n(input.m_flLiteralValue);
}
function fullFollow(lock) {
  // These are normalized start/end FADEOUT times, not an activation delay.
  // Keeping both far in the future gives full translation strength even after
  // a native singleton's short lifespan, while the caller owns cleanup.
  for (const key of ['m_flStartTime_min', 'm_flStartTime_max', 'm_flEndTime_min', 'm_flEndTime_max']) lock[key] = number(999999);
  return lock;
}
const plans = {
  '': { radius: 1 / 400 },
  _ground: { radius: 1 / 800 }, _ground_darken: { radius: 1 / 500 }, _ground_scorch: { radius: 1 / 800, center: 0.7 },
  _light: { radius: 1 / 800 }, _dark_swirl: { radius: 0.9 / 700, center: 0.1 },
  _star_perimeter: { radius: 1 / 800, center: 0.95 }, _star_perimeter_sml: { radius: 1 / 800, center: 0.95 },
  _ember: { radius: 1 / 800, center: 0.7 }, _warp_ripple: { radius: 1 / 1424 }, _warp: { radius: 1 / 800 },
  _ring_spiral: {}, _spiral_arm: { radius: 1 / 800 }, _spiral_armb: { radius: 1 / 800 },
  _spiral_cloud: { radius: 1 / 800 }, _spiral_cloudb: { radius: 1 / 800 },
  _swirl_orange: { radius: 0.8 / 350, center: 0.2 }, _galaxy: { radius: 0.55 / 750, center: 0.45 },
  _core_rays: { radius: 1 / 800, center: 0.45 }, _core_glow: { radius: 0.5 / 450, center: 0.2 },
  _model: { explicit_radius: 1 / 80 }, _ring: { radius: 1 / 400 },
  _outer_debris: { radius: 1 / 800, center: 0.95 }, _ember_streak: { radius: 1 / 800, center: 0.7 },
  _streak_start: { radius: 1 / 800, center: 0.35 }, _ring_flash: { radius: 1 / 800, center: 0.2 },
  _nebula: { radius: 0.5 / 150, center: 0.5 }, _flare: { radius: 1 / 800, radius_limit: referenceRadius },
  _shake: { radius: 1 / 800 }, _flare_b: { radius: 1 / 800 }, _xray: { radius: 1 / 800, radius_limit: 80 },
  _flare_c: { radius: 1 / 800 },
};
const nodes = new Map();
function load(resource) {
  if (nodes.has(resource)) return;
  const node = native(resource); nodes.set(resource, node);
  for (const child of node.tree.m_Children || []) load(child.m_ChildRef.__resource);
}
function adapt(tree, suffix) {
  const plan = plans[suffix]; assert(plan, 'Missing native visual budget ' + suffix);
  const existingLocks = (tree.m_Operators || []).filter(operator => operator._class === 'C_OP_PositionLock');
  assert(existingLocks.length <= 1, 'Multiple native movement locks ' + suffix);
  for (const lock of existingLocks) {
    // CP3 is an unused external trail frame in the native spell. Existing CP1
    // locks retain native rotation: root already moves that frame with CP0.
    if (n(lock.m_nControlPointNumber) === 3) lock.m_nControlPointNumber = integer(0);
    fullFollow(lock);
  }
  if (n(tree.m_nMaxParticles) !== 0) {
    tree.m_Operators ||= [];
    if (!existingLocks.length) tree.m_Operators.push(fullFollow({ _class: 'C_OP_PositionLock', m_nControlPointNumber: integer(0), m_TransformInput: { m_nType: 'PT_TYPE_CONTROL_POINT', m_nControlPoint: integer(0) } }));
    tree.m_Initializers ||= [];
    if (plan.radius !== undefined) tree.m_Initializers.push({ _class: 'C_INIT_InitFloat', m_nOutputField: integer(3), m_nSetMethod: 'PARTICLE_SET_SCALE_CURRENT_VALUE', m_InputValue: radius(plan.radius) });
    if (plan.explicit_radius !== undefined) tree.m_Initializers.push({ _class: 'C_INIT_InitFloat', m_nOutputField: integer(3), m_InputValue: radius(plan.explicit_radius) });
  }
  // Translate into the current moving frame before orbiting about that frame.
  // Moving the single lock preserves every other native operator's order.
  const orbitAt = (tree.m_Operators || []).findIndex(operator => operator._class === 'C_OP_MovementRotateParticleAroundAxis');
  const lockAt = (tree.m_Operators || []).findIndex(operator => operator._class === 'C_OP_PositionLock');
  if (orbitAt >= 0 && lockAt > orbitAt) {
    const [lock] = tree.m_Operators.splice(lockAt, 1);
    tree.m_Operators.splice(orbitAt, 0, lock);
  }
  for (const initial of tree.m_Initializers || []) {
    if (initial._class === 'C_INIT_CreateWithinSphere') {
      initial._class = 'C_INIT_CreateWithinSphereTransform';
      const nativeControl = n(initial.m_nControlPointNumber) || 0;
      initial.m_TransformInput = { m_nType: 'PT_TYPE_CONTROL_POINT', m_nControlPoint: integer(nativeControl) };
      delete initial.m_nControlPointNumber;
      for (const key of ['m_fRadiusMin', 'm_fRadiusMax', 'm_fSpeedMin', 'm_fSpeedMax']) if (initial[key] !== undefined) initial[key] = radius(scalar(initial[key]) / nativeSpatialReference);
      for (const key of ['m_LocalCoordinateSystemSpeedMin', 'm_LocalCoordinateSystemSpeedMax']) scale(initial, key);
    }
    if (initial._class === 'C_INIT_RingWave') for (const key of ['m_flInitialRadius', 'm_flThickness', 'm_flInitialSpeedMin', 'm_flInitialSpeedMax']) if (initial[key] !== undefined) initial[key] = radius(scalar(initial[key]) / nativeSpatialReference);
    if (initial._class === 'C_INIT_PositionOffset') for (const key of ['m_OffsetMin', 'm_OffsetMax']) scale(initial, key);
    if (initial._class === 'C_INIT_PositionWarp') for (const key of ['m_vecWarpMin', 'm_vecWarpMax']) scale(initial, key);
    if (initial._class === 'C_INIT_InitialVelocityNoise') for (const key of ['m_vecOutputMin', 'm_vecOutputMax']) scale(initial, key);
  }
  for (const renderer of tree.m_Renderers || []) for (const key of ['m_flMaxLength', 'm_flMinLength', 'm_flTextureVWorldSize']) scale(renderer, key);
  for (const operator of tree.m_Operators || []) {
    if (operator._class === 'C_OP_BasicMovement') scale(operator, 'm_Gravity');
    if (operator._class === 'C_OP_VectorNoise' && n(operator.m_nFieldOutput) === 0) for (const key of ['m_vecOutputMin', 'm_vecOutputMax']) scale(operator, key);
    if (operator._class === 'C_OP_DampenToCP') scale(operator, 'm_flRange');
    if (operator._class === 'C_OP_OscillateScalar' && (operator.m_nField === undefined || n(operator.m_nField) === 3)) for (const key of ['m_RateMin', 'm_RateMax']) scale(operator, key);
    if (operator._class === 'C_OP_RampScalarLinearSimple' && (operator.m_nField === undefined || n(operator.m_nField) === 3)) scale(operator, 'm_Rate');
  }
  if (plan.radius_limit !== undefined) tree.m_Operators.push({ _class: 'C_OP_ClampScalar', m_nFieldOutput: integer(3), m_flOutputMin: number(0), m_flOutputMax: number(plan.radius_limit) });
  for (const force of tree.m_ForceGenerators || []) {
    if (force._class === 'C_OP_AttractToControlPoint') force.m_fForceAmount = radius(scalar(force.m_fForceAmount) / nativeSpatialReference);
    if (force._class === 'C_OP_TwistAroundAxis') scale(force, 'm_fForceAmount');
    if (force._class === 'C_OP_CurlNoiseForce') scale(force, 'm_vecNoiseScale');
    if (force._class === 'C_OP_TimeVaryingForce') for (const key of ['m_StartingForce', 'm_EndingForce']) scale(force, key);
  }
  for (const operator of tree.m_PreEmissionOperators || []) {
    if (operator._class === 'C_OP_SetControlPointPositions') for (const key of ['m_vecCP1Pos', 'm_vecCP2Pos', 'm_vecCP3Pos', 'm_vecCP4Pos']) scale(operator, key);
    if (operator._class === 'C_OP_SetSingleControlPointPosition') scale(operator, 'm_vecCP1Pos');
  }
  if (plan.center !== undefined) tree.m_Constraints = [...(tree.m_Constraints || []), {
    _class: 'C_OP_ConstrainDistance', m_nControlPointNumber: integer(0),
    m_fMinDistance: literal(0), m_fMaxDistance: radius(plan.center), m_CenterOffset: vector([0, 0, 0]), m_bGlobalCenter: false,
  }];
  for (const child of tree.m_Children || []) child.m_ChildRef.__resource = child.m_ChildRef.__resource.replace(nativePrefix, targetPrefix);
  if (suffix === '') {
    tree.m_Children.push({ m_ChildRef: { __resource: targetPrefix + '_slow_range.vpcf' } });
    tree.m_BoundingBoxMin = vector([-600, -600, -20]); tree.m_BoundingBoxMax = vector([600, 600, 800]);
  }
  if (tree.m_controlPointConfigurations) delete tree.m_controlPointConfigurations;
}
function outerRange() {
  // Separate boundary uses the cosmetic's native core-ring texture/color.
  // Its ground-aligned single particle is hidden when CP21.x is zero.
  return {
    _class: 'CParticleSystemDefinition', m_nMaxParticles: integer(1), m_flConstantLifespan: number(999999),
    m_ConstantColor: [integer(255), integer(156), integer(60), integer(255)],
    m_Renderers: [{ _class: 'C_OP_RenderSprites', m_nOrientationType: 'PARTICLE_ORIENTATION_WORLD_Z_ALIGNED',
      m_flOverbrightFactor: number(2), m_vecTexturesInput: [{ m_hTexture: { __resource: 'materials/particle/particle_ring_softouter.vtex' } }], m_nOutputBlendMode: 'PARTICLE_OUTPUT_BLEND_MODE_ADD' }],
    m_Initializers: [{ _class: 'C_INIT_CreateWithinSphereTransform', m_fRadiusMax: literal(0) },
      { _class: 'C_INIT_PositionOffset', m_OffsetMin: vector([0, 0, 8]), m_OffsetMax: vector([0, 0, 8]) },
      { _class: 'C_INIT_InitFloat', m_nOutputField: integer(3), m_InputValue: radius(1, 21) },
      { _class: 'C_INIT_InitFloat', m_nOutputField: integer(7), m_InputValue: literal(0.08) }],
    m_Operators: [fullFollow({ _class: 'C_OP_PositionLock', m_nControlPointNumber: integer(0), m_TransformInput: { m_nType: 'PT_TYPE_CONTROL_POINT', m_nControlPoint: integer(0) } }),
      { _class: 'C_OP_SetFloat', m_nOutputField: integer(3), m_InputValue: radius(1, 21) }],
    m_Emitters: [{ _class: 'C_OP_InstantaneousEmitter', m_nParticlesToEmit: literal(1) }], m_nBehaviorVersion: integer(12),
  };
}
load(nativePrefix + '.vpcf'); assert.equal(nodes.size, 32, 'Unexpected native Black Hole graph');
const outputs = [], layers = [];
function write(resource, tree, info) {
  const body = header + kv(tree) + '\n', dest = path.join(output, 'source', resource);
  fs.mkdirSync(path.dirname(dest), { recursive: true }); fs.writeFileSync(dest, body);
  outputs.push(resource); layers.push({ ...info, resource, source_sha256: hash(body) });
}
for (const [nativeResource, node] of nodes) {
  const suffix = nativeResource.slice(nativePrefix.length, -5), nativeChildCount = (node.tree.m_Children || []).length;
  const locks = (node.tree.m_Operators || []).filter(operator => operator._class === 'C_OP_PositionLock');
  adapt(node.tree, suffix);
  write(targetPrefix + suffix + '.vpcf', node.tree, { native_resource: nativeResource, native_data_sha256: hash(node.data), native_child_count: nativeChildCount, plan: plans[suffix], movement_lock: n(node.tree.m_nMaxParticles) === 0 ? 'container; native child frames retained' : locks.length ? 'single native position lock retained; CP3 trails remapped toCP0; normalized fadeout starts/ends999999' : 'one CP0 position lock added; normalized fadeout starts/ends999999', snapshot_binding_retained: node.tree.m_hSnapshot ? n(node.tree.m_nSnapshotControlPoint) : null });
}
write(targetPrefix + '_slow_range.vpcf', outerRange(), { native_resource: nativePrefix + '_ring.vpcf', role: 'subtle600slowrange' });
fs.writeFileSync(path.join(output, 'manifest.json'), JSON.stringify({
  root: targetPrefix + '.vpcf', native_root: nativePrefix + '.vpcf',
  cosmetic: { item_definition: 8326, english: 'World Chasm Artifact', chinese: '世界之渊珍宝', ability: 'Black Hole (R)', slot: 'arms', year: 2015 },
  controls: { 0: 'current moving ground center; sync every50ms', 20: 'x = damage radius300 at alllevels', 21: 'x = slow aura radius600 at levels3-5;0 at levels1-2' },
  lifetime: 'Caller owns3s main and2s secondary lifetime; immediate DestroyParticle(true) then ReleaseParticleIndex at every termination',
  graph: { native_resources: 32, root_native_immediate_children: 26, root_derived_immediate_children: 27, derived_resources: 33, native_endcaps: ['_ground', '_ground_darken', '_ground_scorch'], endcap_duration_seconds: 6, endcap_cleanup: 'retained ingraph; immediate destruction suppresses them at gameplay expiry' },
  radius: { reference: referenceRadius, native_spatial_reference: nativeSpatialReference, positions_velocity_noise_force_literal_scale: spatialScale, nominal_main_footprint: 'Per-layer CP20 sizes and CP20-centered constraints fit the300 damage area; native800light/flares and1424warp-ripple scale to300', flare_clamp: 'Final native ClampScalar uses fixed300 max for the configured CP20.x300 contract; default renderer radius scale1, interpolation scale2 and active radius oscillation retained', galaxy: 'sprite max0.55R plus moving center max0.45R', nebula: 'sprite max0.5R plus moving center max0.5R', core_model: 'explicit radius CP20.x/80; native sphere conservative3D unit extent13.734001', xray: 'native column endpoint2000 scaled to750Z at R300; native oscillating particle radius capped80, renderer radius scale0.5', outer_aura: 'CP21.x exact nominal radius; flat native amber softouterring atz8; alpha0.08;zero radius hides it' },
  snapshot: { resource: 'particles/models/items/enigma/enigma_ti5_blackhole_part.vsnap', point_count: 40, maximum_point_horizontal_extent: 7.782320599, native_warp_xy_range: [30, 40], scaled_warp_xy_range: [30 * spatialScale, 40 * spatialScale], maximum_scaled_snapshot_horizontal_center_extent: 7.782320599 * 40 * spatialScale, storage_control: 6, spatial_controls: [0, 7, 8, 9], preserve_native_storage: true, native_orientation_degrees: [190, 20, 210], double_position_lock: false },
  motion: 'Exactly one position lock per rendered leaf; normalized start/end fadeout999999 keeps full follow beyond native short lifespans. A single lock precedes every axis orbit operator to translate into the current frame before orbiting. Native CP1 sphere birth frames use explicit modern TransformInput. CP3 trail locks useCP0. Snapshot leaves retain their single nativeCP0 lockRot=true; CP6 is storage and is untouched. Native local orbit/attraction follows the current center and stays visual-only.',
  culling_bounds: { minimum: [-600, -600, -20], maximum: [600, 600, 800], purpose: 'include optional600slowrange and750-high native scaled xray' },
  preserved: ['All32native resource nodes and distinctive snapshot spiral arms/clouds, galaxy, sphere core, stars, amber flares and particle textures', 'Native colors, renderer styles, local rotations, particle-count gradients, fade curves, emitter rates and startup delays', 'Native control frames0..9 and snapshot binding6; external20/21 arefree and have no native writer'],
  gameplay: 'Damage, slow ranges, proc chance, targeting, movement speed, timing and secondary count stay owned by existing Lua; no Black Hole pull/channel/stun behavior added',
  validation_limit: 'Numerical particle/model contracts and compiled assets can be audited; texture alpha, bloom, refraction, rope tessellation and final appearance require in-game visual inspection',
  outputs, layers,
}, null, 2) + '\n');
console.log('VOID_WORLD_CHASM_SOURCE_PASS particles=' + outputs.length + ' core_radius=' + referenceRadius + ' slow_range=600');
