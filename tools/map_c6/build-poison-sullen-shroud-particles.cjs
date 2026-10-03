'use strict';
// Sullen Rampart's full Ghost Shroud cosmetic, adapted to the poison cloud.
// CP0 = stationary ground origin; CP1.x = world radius (currently 400).
const fs = require('fs'), path = require('path'), cp = require('child_process');
const assert = require('assert'), crypto = require('crypto');
const { endOf } = require('./lib.cjs');
const repo = path.resolve(__dirname, '../..'), engine = path.resolve(repo, '../../..');
const game = path.join(engine, 'game/dota');
const nativePrefix = 'particles/econ/items/necrolyte/necro_ti9_immortal/necro_ti9_immortal_shroud';
const targetPrefix = 'particles/survival/skills/poison_sullen_shroud';
const output = path.join(repo, 'art/effects/poison_sullen_shroud');
const header = '<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->\n';
const referenceRadius = 400, nativeRadius = 750, spatialScale = referenceRadius / nativeRadius;
const ghostExtent = 188, ghostCenterFraction = 1 - ghostExtent / nativeRadius;
const suffixes = ['', '_projection_dark', '_projection', '_rings', '_rings_b', '_warp', '_burst', '_ray', '_ray_b', '_motes', '_bubbles', '_core', '_caustic', '_model'];
const number = value => ({ __number: value, raw: Number.isInteger(value) ? value.toFixed(1) : String(value) });
const integer = value => ({ __number: value, raw: String(value) });
const n = value => value && typeof value === 'object' && '__number' in value ? value.__number : value;
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const vector = values => values.map(number);
const radius = factor => ({ m_nType: 'PF_TYPE_CONTROL_POINT_COMPONENT', m_nControlPoint: integer(1), m_nVectorComponent: integer(0), m_nMapType: 'PF_MAP_TYPE_MULT', m_flMultFactor: number(factor) });
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
function native(resource) {
  const raw = cp.execFileSync(path.join(engine, 'game/bin/win64/resourceinfo.exe'), ['-game', game, '-i', resource + '_c', '-all'], { encoding: 'utf8', windowsHide: true });
  const marker = raw.indexOf('--- vpcf block DATA'), open = raw.indexOf('{', marker);
  assert(marker >= 0, 'Missing native DATA: ' + resource);
  const data = raw.slice(open, endOf(raw, open));
  return { tree: parse(data), data };
}
function scale(object, key, factor = spatialScale) {
  if (object[key] === undefined) return;
  if (Array.isArray(object[key])) object[key] = object[key].map(value => number(n(value) * factor));
  else object[key] = number(n(object[key]) * factor);
}
function literalValue(input) {
  if (input === undefined) return 0;
  if (input && '__number' in input) return n(input);
  assert.equal(input.m_nType, 'PF_TYPE_LITERAL');
  return n(input.m_flLiteralValue);
}
function constrain(tree, fraction) {
  // Modern native ConstrainDistance accepts the same CP-component float input
  // as particle radius. CP0 remains its center; CP1 never aliases a position.
  tree.m_Constraints = [...(tree.m_Constraints || []), {
    _class: 'C_OP_ConstrainDistance',
    m_fMinDistance: { m_nType: 'PF_TYPE_LITERAL', m_flLiteralValue: number(0) },
    m_fMaxDistance: radius(fraction),
    m_nControlPointNumber: integer(0), m_CenterOffset: vector([0, 0, 0]), m_bGlobalCenter: false,
  }];
}
function adapt(tree, suffix) {
  // The native graph has no entity/bone dependency and uses world CP0.
  tree.m_controlPointConfigurations = [{ m_name: 'preview', m_drivers: [
    { m_iControlPoint: integer(0), m_iAttachType: 'PATTACH_WORLDORIGIN', m_entityName: 'self' },
    { m_iControlPoint: integer(1), m_iAttachType: 'PATTACH_WORLDORIGIN', m_vecOffset: vector([referenceRadius, 0, 0]), m_entityName: 'self' },
  ] }];
  if (!suffix) {
    assert.equal(tree.m_Children.length, 13);
    for (const child of tree.m_Children) child.m_ChildRef.__resource = child.m_ChildRef.__resource.replace(nativePrefix, targetPrefix);
    return;
  }
  for (const initial of tree.m_Initializers || []) {
    if (initial._class === 'C_INIT_CreateWithinSphere') {
      // Modern transform initializer keeps CP0 and supports dynamic radius.
      initial._class = 'C_INIT_CreateWithinSphereTransform';
      for (const field of ['m_fRadiusMin', 'm_fRadiusMax']) if (initial[field] !== undefined) initial[field] = radius(literalValue(initial[field]) / nativeRadius);
    }
    if (initial._class === 'C_INIT_PositionOffset') for (const field of ['m_OffsetMin', 'm_OffsetMax']) scale(initial, field);
    if (initial._class === 'C_INIT_RingWave') {
      for (const field of ['m_flInitialRadius', 'm_flThickness', 'm_flInitialSpeedMin', 'm_flInitialSpeedMax']) {
        if (initial[field] !== undefined) {
          const value = suffix === '_model' && field === 'm_flInitialSpeedMax' ? 240 : literalValue(initial[field]);
          initial[field] = radius(value / nativeRadius);
        }
      }
    }
    if (suffix === '_warp' && initial._class === 'C_INIT_InitFloat' && (initial.m_nOutputField === undefined || n(initial.m_nOutputField) === 3)) {
      // Allocate the native 12-unit scatter inside the nominal outer radius.
      assert.equal(n(initial.m_InputValue.m_flRandomMax), 750);
      initial.m_InputValue.m_flRandomMax = number(738);
    }
  }
  // Multiplying the existing radius preserves native random size distributions,
  // including model scale, without replacing color/lifetime initializers.
  tree.m_Initializers.push({ _class: 'C_INIT_InitFloat', m_nOutputField: integer(3),
    m_nSetMethod: 'PARTICLE_SET_SCALE_CURRENT_VALUE', m_InputValue: radius(1 / nativeRadius) });
  for (const operator of tree.m_Operators || []) {
    if (operator._class === 'C_OP_BasicMovement') scale(operator, 'm_Gravity');
    if (operator._class === 'C_OP_VectorNoise' && n(operator.m_nFieldOutput) === 0) for (const field of ['m_vecOutputMin', 'm_vecOutputMax']) scale(operator, field);
  }
  for (const force of tree.m_ForceGenerators || []) {
    if (force._class === 'C_OP_CurlNoiseForce') scale(force, 'm_vecNoiseScale');
    if (force._class === 'C_OP_AttractToControlPoint') force.m_fForceAmount = radius(literalValue(force.m_fForceAmount) / nativeRadius);
  }
  for (const constraint of tree.m_Constraints || []) if (constraint._class === 'C_OP_PlanarConstraint') scale(constraint, 'm_PointOnPlane');
  if (suffix === '_projection') {
    const light = tree.m_Renderers.find(renderer => renderer._class === 'C_OP_RenderDeferredLight');
    assert.equal(n(light.m_flRadiusScale), 1.5);
    light.m_flRadiusScale = number(1);
  }
  if (suffix === '_motes') constrain(tree, 0.96);
  if (suffix === '_bubbles') constrain(tree, 0.94);
  if (suffix === '_model') constrain(tree, ghostCenterFraction);
}
const outputs = [], layers = [];
for (const suffix of suffixes) {
  const nativeResource = nativePrefix + suffix + '.vpcf', resource = targetPrefix + suffix + '.vpcf';
  const { tree, data } = native(nativeResource);
  adapt(tree, suffix);
  const body = header + kv(tree) + '\n', destination = path.join(output, 'source', resource);
  fs.mkdirSync(path.dirname(destination), { recursive: true }); fs.writeFileSync(destination, body);
  outputs.push(resource); layers.push({ native_resource: nativeResource, resource, native_data_sha256: hash(data), source_sha256: hash(body) });
}
const radii = { projection_dark: [550, 550], projection: [700, 700], rings: [400, 750], rings_b: [250, 275], warp: [650, 738], burst: [400, 750], ray: [200, 400], ray_b: [325, 355], motes: [10, 20], bubbles: [8, 20], core: [160, 180], caustic: [275, 325], model: [1, 1.3] };
fs.writeFileSync(path.join(output, 'manifest.json'), JSON.stringify({
  root: targetPrefix + '.vpcf', native_root: nativePrefix + '.vpcf',
  cosmetic: { item_definition: 12932, english: 'Sullen Rampart', chinese: '愠怒之界', ability: 'Ghost Shroud (W)', slot: 'legs', year: 2019 },
  controls: { 0: 'fixed target ground position; no hero attachment required', 1: 'x = poison radius 400' },
  configured_radius: referenceRadius, radius_multiplier: 'CP1.x / 750; initializer multiplies native randomized radius field 3',
  native_birth_radii: radii,
  size_choices: { largest_ring_and_startup_burst: 'CP1.x', projection: '700 / 750 * CP1.x; deferred light radius scale 1.0', warp: 'maximum birth radius 738 / 750 * CP1.x plus scatter 12 / 750 * CP1.x', model: 'native radius 1-1.3 multiplied by CP1.x / 750', motes_center_limit: '0.96 * CP1.x (384 at radius400)', bubbles_center_limit: '0.94 * CP1.x (376 at radius400)' },
  ghost_animation_geometry: { resource: 'models/items/necrolyte/necro_ti9_immortal_skirt/necro_ti9_immortal_ghost.vmdl', sequences: ['ghost_grab', 'ghost_crawl', 'ghost_breach', 'ghost_leap'], native_max_particle_scale: 1.3, worst_native_horizontal_animated_extent: 186.783845, conservative_extent_at_native_max_scale: ghostExtent, geometry_budget_fraction: ghostExtent / nativeRadius, center_budget_fraction: ghostCenterFraction, center_constraint_at_radius400: referenceRadius * ghostCenterFraction, ring_radius_fraction: 75 / nativeRadius, radial_speed_min_fraction: 100 / nativeRadius, radial_speed_max_fraction: 240 / nativeRadius, individual_lifetime_seconds: 2, maximum_undragged_center_at_radius400: referenceRadius * (75 + 240 * 2) / nativeRadius, maximum_animated_reach_at_radius400: referenceRadius * (75 + 240 * 2 + ghostExtent) / nativeRadius },
  movement: 'stationary CP0; native local layer movement, noise and ghost animations retained and reduced to the skill footprint',
  spatial_literals: 'Offsets, vector noise, curl noise, gravity and plane offset scale to configured radius 400; particle sizes, ring radii/speeds, radial repulsion, sphere scatter and distance constraints use CP1.x',
  lifetime: 'Native continuous emitters have no expiry; individual particles recycle. Native startup burst emits for 0.1s. Caller destroys immediately at skill expiry 5/7s and releases the particle index.',
  cleanup: 'DestroyParticle(index, true), then ReleaseParticleIndex; no independent endcap children',
  impact: 'Existing poison death explosion remains unchanged in the gameplay service',
  excluded_branches: ['hero debuff', 'status effect', 'equipped cosmetic ambient and loadout'],
  graph_notes: ['Main aura and all thirteen native children retained', 'Native ghost model, material, four animations, model renderer, color ranges, projected materials, textures, fades, emitter rates and individual lifetimes preserved', 'No control point position writers or CP aliases added', 'Nominal radii and conservative ghost geometry are verified numerically; texture alpha, refraction, bloom and final appearance need in-game visual validation'],
  outputs, layers,
}, null, 2) + '\n');
console.log('POISON_SULLEN_SHROUD_SOURCE_PASS particles=' + outputs.length + ' radius=' + referenceRadius);
