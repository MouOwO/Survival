'use strict';
// Silver Squall mount Mortimer Kisses: hail, local native icy explosions and
// one complete landed field, including its projected frost and animated ice.
const fs = require('fs'), path = require('path'), cp = require('child_process');
const assert = require('assert'), crypto = require('crypto');
const { endOf } = require('./lib.cjs');
const repo = path.resolve(__dirname, '../..'), engine = path.resolve(repo, '../../..'), game = path.join(engine, 'game/dota');
// Arcane shares the exact cosmetic conversion; only its landed geometry differs.
// Keep the default output byte-for-byte identical to the existing ice assets.
const arcane = process.argv.includes('--arcane');
const impactRadius = arcane ? 150 : 75, fieldRadius = arcane ? 200 : 500;
const nativePrefix = 'particles/econ/items/snapfire/snapfire_frostivus_2023/';
const targetPrefix = 'particles/survival/skills/' + (arcane ? 'arcane' : 'ice_cone') + '_silver_squall_';
const outputName = arcane ? 'arcane_silver_squall' : 'ice_silver_squall';
const output = path.join(repo, 'art/effects', outputName), evidence = path.join(repo, 'output', outputName, 'native');
const header = '<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->\n';
const number = value => ({ __number: value, raw: Number.isInteger(value) ? value.toFixed(1) : String(value) });
const integer = value => ({ __number: value, raw: String(value) });
const n = value => value && typeof value === 'object' && '__number' in value ? value.__number : value;
const vector = values => values.map(number);
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
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
function native(resource) {
  const raw = cp.execFileSync(path.join(engine, 'game/bin/win64/resourceinfo.exe'), ['-game', game, '-i', resource + '_c', '-all'], { encoding: 'utf8', windowsHide: true, maxBuffer: 16 * 1024 * 1024 });
  const marker = raw.indexOf('--- vpcf block DATA'), open = raw.indexOf('{', marker); assert(marker >= 0, resource);
  const data = raw.slice(open, endOf(raw, open)); fs.mkdirSync(evidence, { recursive: true });
  fs.writeFileSync(path.join(evidence, path.basename(resource) + '.kv3'), data);
  return { tree: parse(data), data };
}
function scale(object, key, factor) {
  if (object[key] === undefined) return;
  const value = object[key];
  if (Array.isArray(value)) object[key] = value.map(v => number(n(v) * factor));
  else if (value && '__number' in value) object[key] = number(n(value) * factor);
  else if (value && typeof value === 'object') {
    for (const field of ['m_flLiteralValue', 'm_flRandomMin', 'm_flRandomMax', 'm_vLiteralValue', 'm_vRandomMin', 'm_vRandomMax']) scale(value, field, factor);
  }
}
function scalar(input) { if (input && '__number' in input) return n(input); assert.equal(input.m_nType, 'PF_TYPE_LITERAL'); return n(input.m_flLiteralValue); }
function fullFollow(lock) {
  for (const key of ['m_flStartTime_min', 'm_flStartTime_max', 'm_flEndTime_min', 'm_flEndTime_max']) lock[key] = number(999999);
  return lock;
}
const plans = {
  snapfire_frostivus_ultimate_lizard_blobs_arced: { name: 'fall', radius: 200, ref: 400, flight: true },
  snapfire_frostivus_ultimate_projectile_ribbon: { name: 'fall_ribbon', radius: 200, ref: 400, flight: true },
  snapfire_frostivus_ultimate_snow: { name: 'fall_snow', radius: 200, ref: 400, flight: true },
  snapfire_frostivus_ultimate_blobs_arced_sparks: { name: 'fall_sparks', radius: 200, ref: 400, flight: true },
  snapfire_frostivus_ultimate_blobs_arced_flame: { name: 'fall_flame', radius: 200, ref: 400, flight: true },
  snapfire_frostivus_ultimate_blobs_arced_model: { name: 'fall_model', radius: 200, ref: 400, flight: true, model_extent: 5.615005461542527 * 40 },
  snapfire_frostivus_ultimate_glow: { name: 'fall_glow', radius: 200, ref: 400, flight: true },
  snapfire_frostivus_ultimate_impact: { name: 'impact', radius: 75, ref: 750 },
  snapfire_frostivus_ultimate_impact_sphere: { name: 'impact_sphere', radius: 75, ref: 20 * 1.2 * 13.734001, model_extent: 13.734001 },
  snapfire_frostivus_ultimate_linger: { name: 'field', radius: 500, ref: 400, field: true, container: true },
  snapfire_frostivus_ultimate_linger_proj: { name: 'field_proj', radius: 500, ref: 300, field: true, singleton: true, width: 1 },
  snapfire_frostivus_ultimate_linger_shockwave: { name: 'field_shockwave', radius: 500, ref: 700, field: true, center: .9, width: .1 },
  snapfire_frostivus_ultimate_linger_impact_burst: { name: 'field_burst', radius: 500, ref: 400, field: true, center: .1, width: .9 },
  // Hermite curves overshoot their1.0 knots to1.141965259; rounded1.142
  // preserves that native shape and reserves its complete maximum width.
  snapfire_frostivus_ultimate_linger_ground_ring: { name: 'field_ring', radius: 500, ref: 275 + 15 * 2 * 1.142, field: true, circle: true, singleton: true, native_curve_peak: 1.141965259, bounded_curve_peak: 1.142 },
  snapfire_frostivus_ultimate_linger_ground_embers: { name: 'field_embers', radius: 500, ref: 400, field: true, sustained: true, recycle: true, center: .8, width: .1, trail: .1 },
  snapfire_frostivus_ultimate_linger_ground_flames: { name: 'field_flames', radius: 500, ref: 800, field: true, sustained: true, recycle: true, center: .8, width: .2 },
  snapfire_frostivus_ultimate_linger_ground_iceshards: { name: 'field_shards', radius: 500, ref: 500, field: true, sustained: true, singleton: true, center: .34, width: .66, model_extent: 210 },
  snapfire_frostivus_ultimate_linger_ground_shockwave: { name: 'field_ground_shockwave', radius: 500, ref: 400, field: true, center: .1, width: .9 },
  snapfire_frostivus_ultimate_linger_ground_sparks: { name: 'field_sparks', radius: 500, ref: 1200, field: true, center: .9, width: .1 },
  snapfire_frostivus_ultimate_linger_impact_glow: { name: 'field_glow', radius: 500, ref: 500, field: true, width: 1 },
  snapfire_frostivus_ultimate_linger_torns: { name: 'field_torns', radius: 500, ref: 1250, field: true, sustained: true, center: .4, width: .2, trail: .4 },
  snapfire_frostivus_ultimate_impact_glow: { name: 'field_parent_glow', radius: 500, ref: 800, field: true, center: .1, width: .9 },
};
const hitCopies = [
  { native_stem: 'snapfire_frostivus_ultimate_linger_impact_burst', name: 'impact_burst', radius: 75, ref: 400, center: .1, width: .9 },
  { native_stem: 'snapfire_frostivus_ultimate_linger_impact_glow', name: 'impact_glow', radius: 75, ref: 500, width: 1 },
];
if (arcane) {
  for (const plan of Object.values(plans)) {
    if (plan.field) plan.radius = fieldRadius;
    else if (!plan.flight) plan.radius = impactRadius;
  }
  for (const plan of hitCopies) plan.radius = impactRadius;
}
const nodes = new Map(), excluded = new Set(['snapfire_frostivus_ultimate_mouthburst', 'snapfire_frostivus_ultimate_mouthsparks']);
function stem(resource) { return path.basename(resource, '.vpcf'); }
function target(resource) { const plan = plans[stem(resource)]; assert(plan, 'Missing Silver Squall layer ' + resource); return targetPrefix + plan.name + '.vpcf'; }
function load(resource) {
  if (nodes.has(resource) || excluded.has(stem(resource))) return;
  const node = native(resource); nodes.set(resource, node);
  for (const child of node.tree.m_Children || []) load(child.m_ChildRef.__resource);
}
function adapt(tree, nativeStem, plan = plans[nativeStem]) {
  const factor = plan.radius / plan.ref;
  delete tree.m_controlPointConfigurations;
  for (const child of tree.m_Children || []) child.m_ChildRef.__resource = target(child.m_ChildRef.__resource);
  for (const init of tree.m_Initializers || []) {
    if (init._class === 'C_INIT_CreateWithinSphere') {
      init._class = 'C_INIT_CreateWithinSphereTransform';
      init.m_TransformInput = { m_nType: 'PT_TYPE_CONTROL_POINT', m_nControlPoint: integer(n(init.m_nControlPointNumber) || 0) };
      delete init.m_nControlPointNumber;
    }
    if (init._class === 'C_INIT_CreateWithinSphereTransform') {
      // The cosmetic is already modern; retain its exact TransformInput.
      for (const key of ['m_fRadiusMin', 'm_fRadiusMax', 'm_fSpeedMin', 'm_fSpeedMax']) scale(init, key, factor);
      for (const key of ['m_LocalCoordinateSystemSpeedMin', 'm_LocalCoordinateSystemSpeedMax']) scale(init, key, factor);
    }
    if (init._class === 'C_INIT_PositionOffset') for (const key of ['m_OffsetMin', 'm_OffsetMax']) scale(init, key, factor);
    if (init._class === 'C_INIT_InitialVelocityNoise') for (const key of ['m_vecOutputMin', 'm_vecOutputMax']) scale(init, key, factor);
    if (init._class === 'C_INIT_RingWave') for (const key of ['m_flInitialRadius', 'm_flInitialRadiusThickness', 'm_flInitialSpeedMin', 'm_flInitialSpeedMax']) scale(init, key, factor);
    if (plan.circle && init._class === 'C_INIT_RingWave') init.m_flInitialRadius = radius(275 / plan.ref);
    if (plan.singleton && init._class === 'C_INIT_InitFloat' && n(init.m_nOutputField) === 1) init.m_InputValue = radius(1, 21);
    if (plan.name === 'field_parent_glow' && init._class === 'C_INIT_CreateFromParentParticles') {
      // This native child has an empty parent. Anchor its position explicitly
      // while preserving its place and appearance in the complete field DAG.
      for (const key of Object.keys(init)) delete init[key];
      Object.assign(init, { _class: 'C_INIT_CreateWithinSphereTransform', m_TransformInput: { m_nType: 'PT_TYPE_CONTROL_POINT', m_nControlPoint: integer(0), m_bFollowNamedValue: false }, m_fRadiusMax: literal(0) });
    }
  }
  for (const op of tree.m_Operators || []) {
    if (op._class === 'C_OP_BasicMovement') scale(op, 'm_Gravity', factor);
    if (op._class === 'C_OP_VectorNoise' && [0, 2].includes(n(op.m_nFieldOutput))) for (const key of ['m_vecOutputMin', 'm_vecOutputMax']) scale(op, key, factor);
  }
  for (const force of tree.m_ForceGenerators || []) if (force._class === 'C_OP_RandomForce') for (const key of ['m_MinForce', 'm_MaxForce']) scale(force, key, factor);
  for (const renderer of tree.m_Renderers || []) for (const key of ['m_flTextureVWorldSize', 'm_flMaxLength', 'm_flMinLength']) scale(renderer, key, factor);
  if (plan.trail !== undefined) for (const renderer of tree.m_Renderers || []) if (renderer._class === 'C_OP_RenderTrails') {
    const maximum = Math.min(n(renderer.m_flMaxLength) || plan.radius * plan.trail, plan.radius * plan.trail);
    renderer.m_flMaxLength = number(maximum);
    if (renderer.m_flMinLength !== undefined) renderer.m_flMinLength = number(Math.min(n(renderer.m_flMinLength), maximum));
  }
  tree.m_Initializers ||= []; tree.m_Operators ||= [];
  if (!plan.container) tree.m_Initializers.push({ _class: 'C_INIT_InitFloat', m_nOutputField: integer(3), m_nSetMethod: 'PARTICLE_SET_SCALE_CURRENT_VALUE', m_InputValue: radius(1 / plan.ref) });
  // SCALE_INITIAL radius curves already read the scaled initial radius. Only
  // replacement curves need a final CP20 multiplier; never multiply twice.
  const replacesRadius = tree.m_Operators.some(op => op._class === 'C_OP_SetFloat' && (op.m_nOutputField === undefined || n(op.m_nOutputField) === 3) && (!op.m_nSetMethod || op.m_nSetMethod === 'PARTICLE_SET_REPLACE_VALUE'));
  if (replacesRadius) tree.m_Operators.push({ _class: 'C_OP_SetFloat', m_nOutputField: integer(3), m_nSetMethod: 'PARTICLE_SET_SCALE_CURRENT_VALUE', m_InputValue: radius(1 / plan.ref) });
  if (plan.flight) {
    // END_CAP_OFF marks ordinary native curves; preserve them. Remove only
    // actual endcap and autonomous parent arc/homing behavior.
    tree.m_Operators = tree.m_Operators.filter(op => op.m_nOpEndCapState !== 'PARTICLE_ENDCAP_ENDCAP_ON' && !['C_OP_EndCapTimedDecay', 'C_OP_MaxVelocity', 'C_OP_CPOffsetToPercentageBetweenCPs', 'C_OP_SetControlPointsToParticle'].includes(op._class));
    if (plan.name === 'fall') {
      delete tree.m_ForceGenerators;
      for (const child of tree.m_Children || []) delete child.m_flDelay;
      tree.m_Operators.push(fullFollow({ _class: 'C_OP_PositionLock', m_TransformInput: { m_nType: 'PT_TYPE_CONTROL_POINT', m_nControlPoint: integer(0) } }));
    }
    if (['fall', 'fall_model', 'fall_glow'].includes(plan.name)) {
      tree.m_flConstantLifespan = number(999999);
      tree.m_Initializers = tree.m_Initializers.filter(init => !(init._class === 'C_INIT_InitFloat' && n(init.m_nOutputField) === 1));
      const locks = tree.m_Operators.filter(op => op._class === 'C_OP_PositionLock'); assert.equal(locks.length, 1, 'One body/light lock'); locks.forEach(fullFollow);
      // vpcf45's legacy PositionLock upgrade derives TransformInput from this
      // field even for a modern native input. Keep both to retain CP3 facing.
      if (plan.name !== 'fall') for (const lock of locks) lock.m_nControlPointNumber = integer(3);
    }
    if (plan.name === 'fall_model') {
      tree.m_Operators = tree.m_Operators.filter(op => op._class !== 'C_OP_InterpolateRadius');
      const normal = tree.m_Initializers.find(init => init._class === 'C_INIT_InitVec' && n(init.m_nOutputField) === 21); normal.m_InputValue.m_vLiteralValue = vector([0, 0, -1]);
    }
    if (plan.name === 'fall_flame') tree.m_Initializers = tree.m_Initializers.filter(init => init._class !== 'C_INIT_InheritVelocity');
    tree.m_BoundingBoxMin = vector([-200, -200, -300]); tree.m_BoundingBoxMax = vector([200, 200, 300]);
  }
  if (plan.center !== undefined) {
    tree.m_Constraints ||= [];
    tree.m_Constraints.push({ _class: 'C_OP_ConstrainDistance', m_nControlPointNumber: integer(0), m_fMinDistance: literal(0), m_fMaxDistance: radius(plan.center) });
  }
  if ((tree.m_Renderers || []).length) {
    const rendererScale = Math.max(...tree.m_Renderers.map(renderer => renderer.m_flRadiusScale === undefined ? 1 : scalar(renderer.m_flRadiusScale)));
    const cap = plan.circle ? plan.radius * 15 * plan.bounded_curve_peak / plan.ref : plan.radius * (plan.width === undefined ? 1 : plan.width) / (plan.model_extent || rendererScale);
    tree.m_Operators.push({ _class: 'C_OP_ClampScalar', m_nFieldOutput: integer(3), m_flOutputMin: number(0), m_flOutputMax: number(cap) });
  }
  if (plan.field) {
    tree.m_BoundingBoxMin = vector([-plan.radius, -plan.radius, -plan.radius * .4]); tree.m_BoundingBoxMax = vector([plan.radius, plan.radius, plan.radius * 1.6]);
    if (plan.sustained) for (const emitter of tree.m_Emitters || []) if (emitter._class === 'C_OP_ContinuousEmitter') emitter.m_flEmissionDuration = radius(1, 21);
    if (plan.recycle) for (const op of tree.m_Operators) if (op._class === 'C_OP_Decay') delete op.m_nOpEndCapState;
    if (plan.container) {
      for (const op of [...tree.m_Operators, ...(tree.m_PreEmissionOperators || [])]) if (op._class === 'C_OP_StopAfterCPDuration') op.m_flDuration = radius(1, 21);
      for (const child of tree.m_Children) if (child.m_ChildRef.__resource.endsWith('_field_ring.vpcf')) delete child.m_flDelay;
    }
  }
  if (plan.name === 'impact') {
    for (const hit of hitCopies) tree.m_Children.push({ m_ChildRef: { __resource: targetPrefix + hit.name + '.vpcf' } });
  }
}
for (const name of [...(arcane ? [] : ['snapfire_frostivus_ultimate_lizard_blobs_arced']), 'snapfire_frostivus_ultimate_impact', 'snapfire_frostivus_ultimate_linger']) load(nativePrefix + name + '.vpcf');
assert.equal(nodes.size, arcane ? 15 : 22);
const layers = [], outputs = [];
function write(resource, node, plan) {
  const tree = structuredClone(node.tree);
  if (plan.name === 'fall') tree.m_Children = tree.m_Children.filter(child => !excluded.has(stem(child.m_ChildRef.__resource)));
  adapt(tree, stem(resource), plan);
  const result = targetPrefix + plan.name + '.vpcf', text = header + kv(tree) + '\n', dest = path.join(output, 'source', result);
  fs.mkdirSync(path.dirname(dest), { recursive: true }); fs.writeFileSync(dest, text);
  outputs.push(result); layers.push({ resource: result, native_resource: resource, native_data_sha256: hash(node.data), source_sha256: hash(text), plan });
}
for (const [resource, node] of nodes) write(resource, node, plans[stem(resource)]);
for (const plan of hitCopies) { const resource = nativePrefix + plan.native_stem + '.vpcf'; write(resource, nodes.get(resource), plan); }
const manifest = {
  cosmetic: { item_id: 26401, item_name: 'Silver Squall - Mount', chinese_name: '银白烈风 - 坐骑', ability: 'Mortimer Kisses (R)' },
  roots: { flight: targetPrefix + 'fall.vpcf', impact: targetPrefix + 'impact.vpcf', field: targetPrefix + 'field.vpcf' },
  controls: { flight: { CP0: 'Current sky position', CP3: 'Same sky position; forward Vector(0,0,-1)', CP20_x: 200 }, impact: { CP0: 'Small landing ground position', CP3: 'Same ground position with default world orientation', CP20_x: 75 }, field: { CP0: 'Fixed ground center', CP3: 'Same ground center', CP20_x: 500, CP21_x: 'Skill duration3sec at levels1-4,5sec at level5' } },
  graph: { flight_resources: 7, impact_resources: 4, field_resources: 13, unique_resources: 24, removed_mouth_casts: [...excluded], per_hit_ring_or_pool: false, field_instances_per_cast: 1, native_field_children: 12, hail_landings: { duration3: 48, duration5: 80 } },
  lifecycle: { flight: 'Caller owns .45-.65sec manual hail descent and immediate cleanup at landing; body/light/glow follow throughout; snow/ribbon/spark/flame grains retain native world-space motion and finite life', impact: 'Caller releases the index after creation; native root, sphere,16-particle icy explosion and centered glow self-terminate with original finite emission/life/Decay and brief natural fade', field: 'Complete native linger graph once; projection/ring/animated shard life=CP21.x; shard/flame/swirl emitters run forCP21.x; ember noise remains continuous; finite ember/flame grains decay and replenish; parent stop duration=CP21.x; immediate caller cleanup at3/5sec' },
  sizing: 'Hail flight nominal200; local landing nominal75; complete field nominal500. CP20 scales native initial radii. Native SCALE_INITIAL curves remain exact and are never scaled twice. Final fixed-contract radius caps, CP0 center constraints and bounded trail lengths reserve the whole geometry footprint.',
  geometry: { projectile_model_unit_3D_AABB_extent: 5.615005461542527, projectile_model_maximum_native_radius: 0.4, projectile_renderer_scale: 40, sphere_unit_3D_AABB_extent: 13.734001, sphere_maximum_native_radius: 20, sphere_maximum_interpolation_scale: 1.2, animated_shards_unit_XY_extent: 206.073359755, animated_shards_unit_XY_budget: 210, animated_shards_center_cap: 170, animated_shards_geometry_cap: 330, animated_shards_particle_radius_cap: 330 / 210, animated_shards_curve_peak: 1.114228151772, animated_shards_sequence: 'Snapfire_frostivus', animated_shards_max_particles: 3 },
  field: { full_native_interior: true, sustained_layers: ['field_proj', 'field_ring', 'field_shards', 'field_embers', 'field_flames', 'field_torns'], projected_frost_curve_peak: 1.1393079459556, projected_frost_geometry_cap: 500, native_center_radius: 275, native_particle_radius: 15, maximum_renderer_radius_scale: 2, native_width_curve_peak: 1.141965259, bounded_width_curve_peak: 1.142, native_outer_radius_budget: 309.26, circle_center_at_R500: 500 * 275 / 309.26, maximum_particle_radius_at_R500: 500 * 15 * 1.142 / 309.26, maximum_outer_geometry_at_R500: 500, color: [143, 222, 254], textures: ['materials/particle/beam_ice.vtex', 'materials/particle/beam_generic_7.vtex'], orientation: 'PARTICLE_ORIENTATION_WORLD_Z_ALIGNED', cases: [{ levels: '1-4', duration: 3 }, { level: 5, duration: 5 }] },
  validation_limit: 'Asset/operator checks do not establish in-game appearance, texture alpha fringe or bloom bounds.',
  in_game_visual_verified: false, outputs, layers,
};
if (arcane) {
  const sharedPrefix = 'particles/survival/skills/ice_cone_silver_squall_';
  manifest.roots.flight = sharedPrefix + 'fall.vpcf';
  manifest.roots.field_large = sharedPrefix + 'field.vpcf';
  manifest.controls.impact.CP20_x = impactRadius;
  manifest.controls.field.CP20_x = fieldRadius;
  manifest.controls.field.CP21_x = 'Barrage duration from cast start:1sec at levels1-4,3sec at level5';
  manifest.controls.field_large = { ...manifest.controls.field, CP20_x: 500 };
  manifest.graph = { flight_resources_shared: 7, impact_resources: 4, field_resources: 13, new_resources: 17, per_hit_ring_or_pool: false, field_instances_per_cast: 1, native_field_children: 12, shared_large_field_resources: 13 };
  manifest.lifecycle.flight = 'Reuse the exact ice-cone200-size flight; caller owns manual sky descent and destroys immediately at original missile landing time';
  manifest.lifecycle.field = 'Complete native linger graph once for the whole barrage. CP21.x sets projection/ring/animated shard life and sustained emissions. Caller destroys at the original1/3sec barrage end, reset or invalid caster.';
  manifest.sizing = 'Shared flight remains200; each local explosion is150; levels2-5 use a complete200-radius field, level1 reuses the original500 field. Geometry offsets, velocities, radius caps and trail lengths are all generated for their own150/200 contracts; setting CP20 alone cannot resize fixed native geometry.';
  manifest.geometry.animated_shards_center_cap = fieldRadius * .34;
  manifest.geometry.animated_shards_geometry_cap = fieldRadius * .66;
  manifest.geometry.animated_shards_particle_radius_cap = fieldRadius * .66 / 210;
  manifest.field.projected_frost_geometry_cap = fieldRadius;
  delete manifest.field.circle_center_at_R500;
  delete manifest.field.maximum_particle_radius_at_R500;
  delete manifest.field.maximum_outer_geometry_at_R500;
  manifest.field.circle_center_at_R200 = fieldRadius * 275 / 309.26;
  manifest.field.maximum_particle_radius_at_R200 = fieldRadius * 15 * 1.142 / 309.26;
  manifest.field.maximum_outer_geometry_at_R200 = fieldRadius;
  manifest.field.cases = [{ levels: '1', radius: 500, duration: 1, shared: true }, { levels: '2-4', radius: fieldRadius, duration: 1 }, { level: 5, radius: fieldRadius, duration: 3 }];
}
fs.writeFileSync(path.join(output, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log((arcane ? 'ARCANE' : 'ICE') + '_SILVER_SQUALL_SOURCE_PASS resources=' + outputs.length + (arcane ? ' flight=shared' : ' flight=7') + ' impact=4 field=13');
