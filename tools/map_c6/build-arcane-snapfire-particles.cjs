'use strict';
// Mortimer Kisses sky projectile plus its complete native impact and lava pool.
// Flight CP0/CP3 = manually tracked sky center, CP3 forward = down.
// Impact CP0/CP3 and pool CP0 = fixed landing ground center; CP20.x = radius150.
const fs = require('fs'), path = require('path'), cp = require('child_process');
const assert = require('assert'), crypto = require('crypto');
const { endOf } = require('./lib.cjs');
const repo = path.resolve(__dirname, '../..'), engine = path.resolve(repo, '../../..');
const game = path.join(engine, 'game/dota');
const nativePrefix = 'particles/units/heroes/hero_snapfire/';
const targetPrefix = 'particles/survival/skills/arcane_snapfire_';
const output = path.join(repo, 'art/effects/arcane_snapfire');
const evidence = path.join(repo, 'output/arcane_snapfire/native');
const header = '<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->\n';
const referenceRadius = 150, poolUnitXY = 10.60660553617499, sphereUnit3D = 13.734001, sphereUnitXY = 11.220378109884534;
const number = value => ({ __number: value, raw: Number.isInteger(value) ? value.toFixed(1) : String(value) });
const integer = value => ({ __number: value, raw: String(value) });
const n = value => value && typeof value === 'object' && '__number' in value ? value.__number : value;
const vector = values => values.map(number);
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const literal = value => ({ m_nType: 'PF_TYPE_LITERAL', m_flLiteralValue: number(value) });
const radius = factor => ({ m_nType: 'PF_TYPE_CONTROL_POINT_COMPONENT', m_nControlPoint: integer(20), m_nVectorComponent: integer(0), m_nMapType: 'PF_MAP_TYPE_MULT', m_flMultFactor: number(factor) });
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
// World dimensions use these native bounds; final radius inputs remain CP20-based.
// center/cap fractions reserve separate room for center, sprite width and trail.
const plans = {
  snapfire_lizard_blobs_arced: { name: 'fall', ref: 400, flight: true },
  snapfire_lizard_blobs_arced_model: { name: 'fall_model', ref: 400, flight: true },
  hero_snapfire_ultimate_projectile_ribbon: { name: 'fall_ribbon', ref: 400, flight: true },
  hero_snapfire_ultimate_projectile_magma: { name: 'fall_magma', ref: 400, flight: true },
  hero_snapfire_ultimate_blob_drips: { name: 'fall_drips', ref: 400, flight: true },
  hero_snapfire_ultimate_glow: { name: 'fall_glow', ref: 400, flight: true },
  hero_snapfire_ultimate_impact: { name: 'impact', ref: 750, center: 0.75, cap: 0.1 },
  hero_snapfire_ultimate_burst: { name: 'impact_burst_ring', ref: 300, cap: 1 },
  hero_snapfire_ultimate_impact_glow: { name: 'impact_glow', ref: 800, center: 0.1, cap: 0.9 },
  hero_snapfire_ultimate_impact_parenttrails: { name: 'impact_parenttrails', ref: 1400, center: 0.85, cap: 0.1 },
  hero_snapfire_ultimate_impact_sparks: { name: 'impact_sparks', ref: 400, center: 0.9, cap: 0.1 },
  hero_snapfire_ultimate_impact_emissive: { name: 'impact_emissive', ref: 1440, cap: 1 },
  hero_snapfire_ultimate_impact_sphere: { name: 'impact_sphere', ref: 20 * 1.2 * sphereUnit3D, model_extent: sphereUnit3D },
  hero_snapfire_ultimate_impact_rays: { name: 'impact_rays', ref: 2000, center: 0.7, cap: 0.1, trail: 0.2 },
  hero_snapfire_ultimate_linger: { name: 'linger', ref: 400 },
  hero_snapfire_ult_ground_light: { name: 'linger_light', ref: 300, cap: 1 },
  hero_snapfire_ult_ground_outer: { name: 'linger_outer', ref: 40 * poolUnitXY, model_extent: poolUnitXY },
  hero_snapfire_ult_ground_bloom: { name: 'linger_bloom', ref: 520, cap: 1 },
  hero_snapfire_ultimate_impact_directional: { name: 'linger_directional', ref: 400, center: 0.8, cap: 0.1 },
  hero_snapfire_ultimate_shockwave: { name: 'linger_shockwave', ref: 400, center: 0.8, cap: 0.1 },
  hero_snapfire_ultimate_impact_burst: { name: 'linger_burst', ref: 400, center: 0.1, cap: 0.9 },
  hero_snapfire_ultimate_linger_steam: { name: 'linger_steam', ref: 500, center: 0.45, cap: 0.55 },
  hero_snapfire_ult_ground_ring: { name: 'linger_ring', ref: 300, center: 275 / 300, cap: 25 / 300 },
  hero_snapfire_ult_ground_embers: { name: 'linger_embers', ref: 400, center: 0.8, cap: 0.1, trail: 0.1 },
  hero_snapfire_ult_ground_flames: { name: 'linger_flames', ref: 400, center: 0.8, cap: 0.2 },
  hero_snapfire_ultimate_ground_glow: { name: 'linger_glow', ref: 180 * 0.7, cap: 1 },
  hero_snapfire_ult_ground_splash_liquid: { name: 'linger_splash_liquid', ref: 500, center: 0.8, cap: 0.2 },
  hero_snapfire_ult_ground_splash: { name: 'linger_splash', ref: 500, center: 0.5, cap: 0.2, trail: 0.3 },
  hero_snapfire_ult_ground_splash_lava: { name: 'linger_splash_lava', ref: 500, center: 0.5, cap: 0.2, trail: 0.3 },
  hero_snapfire_ult_ground_bubble: { name: 'linger_bubble', ref: 20 * sphereUnitXY, model_extent: sphereUnitXY },
};
const nodes = new Map();
const excluded = new Set(['hero_snapfire_ultimate_mouthburst', 'hero_snapfire_ultimate_mouthsparks']);
function stem(resource) { return path.basename(resource, '.vpcf'); }
function target(resource) { const plan = plans[stem(resource)]; assert(plan, 'Missing native layer plan ' + resource); return targetPrefix + plan.name + '.vpcf'; }
function load(resource) {
  if (excluded.has(stem(resource)) || nodes.has(resource)) return;
  const node = native(resource); nodes.set(resource, node);
  for (const child of node.tree.m_Children || []) load(child.m_ChildRef.__resource);
}
function rendererScale(renderer) { return renderer.m_flRadiusScale === undefined ? 1 : scalar(renderer.m_flRadiusScale); }
function adapt(tree, nativeStem) {
  const plan = plans[nativeStem], factor = referenceRadius / plan.ref;
  delete tree.m_controlPointConfigurations;
  for (const child of tree.m_Children || []) child.m_ChildRef.__resource = target(child.m_ChildRef.__resource);
  // Compiling old CreateWithinSphere under its legacy name loses explicit CP3.
  // The modern TransformInput retains the actual native birth frame.
  for (const init of tree.m_Initializers || []) {
    if (init._class === 'C_INIT_CreateWithinSphere') {
      const control = n(init.m_nControlPointNumber) || 0;
      init._class = 'C_INIT_CreateWithinSphereTransform';
      init.m_TransformInput = { m_nType: 'PT_TYPE_CONTROL_POINT', m_nControlPoint: integer(control) };
      delete init.m_nControlPointNumber;
      for (const key of ['m_fRadiusMin', 'm_fRadiusMax', 'm_fSpeedMin', 'm_fSpeedMax']) if (init[key] !== undefined) init[key] = radius(scalar(init[key]) / plan.ref);
      for (const key of ['m_LocalCoordinateSystemSpeedMin', 'm_LocalCoordinateSystemSpeedMax']) scale(init, key, factor);
    }
    if (init._class === 'C_INIT_RingWave') for (const key of ['m_flInitialRadius', 'm_flThickness', 'm_flInitialSpeedMin', 'm_flInitialSpeedMax']) if (init[key] !== undefined) init[key] = radius(scalar(init[key]) / plan.ref);
    if (init._class === 'C_INIT_PositionOffset') for (const key of ['m_OffsetMin', 'm_OffsetMax']) scale(init, key, factor);
    if (init._class === 'C_INIT_InitialVelocityNoise') for (const key of ['m_vecOutputMin', 'm_vecOutputMax']) scale(init, key, factor);
    if (init._class === 'C_INIT_VelocityRandom') for (const key of ['m_LocalCoordinateSystemSpeedMin', 'm_LocalCoordinateSystemSpeedMax']) scale(init, key, factor);
    if (init._class === 'C_INIT_InitVec' && n(init.m_nOutputField) === 2) scale(init, 'm_InputValue', factor);
  }
  for (const op of tree.m_Operators || []) {
    if (op._class === 'C_OP_BasicMovement') scale(op, 'm_Gravity', factor);
    if (op._class === 'C_OP_VectorNoise' && [0, 2].includes(n(op.m_nFieldOutput))) for (const key of ['m_vecOutputMin', 'm_vecOutputMax']) scale(op, key, factor);
    if (op._class === 'C_OP_OscillateVector' && n(op.m_nField) === 2) for (const key of ['m_RateMin', 'm_RateMax']) scale(op, key, factor);
    if (op._class === 'C_OP_RampScalarLinearSimple' && (op.m_nField === undefined || n(op.m_nField) === 3)) scale(op, 'm_Rate', factor);
  }
  for (const force of tree.m_ForceGenerators || []) {
    if (force._class === 'C_OP_AttractToControlPoint') {
      force.m_fForceAmount = radius(scalar(force.m_fForceAmount) / plan.ref);
      if (n(force.m_nControlPointNumber) === 1) force.m_nControlPointNumber = integer(0);
    }
    if (force._class === 'C_OP_RandomForce') for (const key of ['m_MinForce', 'm_MaxForce']) scale(force, key, factor);
  }
  for (const renderer of tree.m_Renderers || []) {
    for (const key of ['m_flMaxLength', 'm_flMinLength', 'm_flTextureVWorldSize', 'm_cubeWidth', 'm_cutoffRadius', 'm_renderRadius']) scale(renderer, key, factor);
    if (plan.trail && renderer._class === 'C_OP_RenderTrails') renderer.m_flMaxLength = number(Math.min(n(renderer.m_flMaxLength) || 999999, referenceRadius * plan.trail));
  }
  const rendered = n(tree.m_nMaxParticles) !== 0;
  if (rendered) {
    tree.m_Initializers ||= []; tree.m_Operators ||= [];
    tree.m_Initializers.push({ _class: 'C_INIT_InitFloat', m_nOutputField: integer(3), m_nSetMethod: 'PARTICLE_SET_SCALE_CURRENT_VALUE', m_InputValue: radius(1 / plan.ref) });
    // Native ground-model/rope curves REPLACE radius every frame. Scaling their
    // final current value restores CP20 sizing without changing curve shape.
    const liveRadius = tree.m_Operators.some(op => op._class === 'C_OP_SetFloat' && (op.m_nOutputField === undefined || n(op.m_nOutputField) === 3));
    if (liveRadius) tree.m_Operators.push({ _class: 'C_OP_SetFloat', m_nOutputField: integer(3), m_nSetMethod: 'PARTICLE_SET_SCALE_CURRENT_VALUE', m_InputValue: radius(1 / plan.ref) });
    let cap = plan.model_extent ? referenceRadius / plan.model_extent : undefined;
    if (plan.cap !== undefined) {
      const renderer = tree.m_Renderers[0];
      cap = referenceRadius * plan.cap / (renderer._class === 'C_OP_RenderBlobs' ? Math.max(n(renderer.m_cutoffRadius) || 1, n(renderer.m_renderRadius) || 1) : rendererScale(renderer));
    }
    if (cap !== undefined) tree.m_Operators.push({ _class: 'C_OP_ClampScalar', m_nFieldOutput: integer(3), m_flOutputMin: number(0), m_flOutputMax: number(cap) });
    if (plan.center !== undefined) tree.m_Constraints = [...(tree.m_Constraints || []), { _class: 'C_OP_ConstrainDistance', m_nControlPointNumber: integer(0), m_fMinDistance: literal(0), m_fMaxDistance: radius(plan.center), m_CenterOffset: vector([0, 0, 0]), m_bGlobalCenter: false }];
  }
  if (plan.flight) {
    // Native flight behavior is replaced by the existing authoritative Lua
    // timing. Remove only launch/arc/attractor/endcap behavior; retain visuals.
    tree.m_Operators = (tree.m_Operators || []).filter(op => !op.m_nOpEndCapState && !['C_OP_MaxVelocity', 'C_OP_CPOffsetToPercentageBetweenCPs', 'C_OP_SetControlPointsToParticle'].includes(op._class));
    if (plan.name === 'fall') {
      delete tree.m_ForceGenerators; tree.m_flConstantLifespan = number(999999);
      tree.m_Initializers = tree.m_Initializers.filter(init => !(init._class === 'C_INIT_InitFloat' && n(init.m_nOutputField) === 1));
      for (const child of tree.m_Children || []) delete child.m_flDelay;
    }
    if (plan.name === 'fall_model') {
      tree.m_Operators = tree.m_Operators.filter(op => op._class !== 'C_OP_InterpolateRadius');
      tree.m_flConstantLifespan = number(999999);
      tree.m_Initializers = tree.m_Initializers.filter(init => !(init._class === 'C_INIT_InitFloat' && n(init.m_nOutputField) === 1));
      const normal = tree.m_Initializers.find(init => init._class === 'C_INIT_InitVec' && n(init.m_nOutputField) === 21); normal.m_InputValue.m_vLiteralValue = vector([0, 0, -1]);
    }
    if (plan.name === 'fall_glow') tree.m_flConstantLifespan = number(999999);
    if (plan.name === 'fall_drips') tree.m_Initializers = tree.m_Initializers.filter(init => init._class !== 'C_INIT_InheritVelocity');
    const locks = tree.m_Operators.filter(op => op._class === 'C_OP_PositionLock'); assert(locks.length <= 1);
    if (!locks.length) tree.m_Operators.push(fullFollow({ _class: 'C_OP_PositionLock', m_nControlPointNumber: integer(plan.name === 'fall' ? 0 : 3), m_TransformInput: { m_nType: 'PT_TYPE_CONTROL_POINT', m_nControlPoint: integer(plan.name === 'fall' ? 0 : 3) } }));
    // The body and glow follow for the whole manual fall. Native short-lived
    // ribbon/magma particles retain partial following so trails detach/fade.
    else if (['fall_model', 'fall_glow'].includes(plan.name)) locks.forEach(fullFollow);
    tree.m_BoundingBoxMin = vector([-150, -150, -150]); tree.m_BoundingBoxMax = vector([150, 150, 150]);
  }
  if (plan.name === 'linger_shockwave') {
    // Avoid requiring native cosmetic color CP61/62: use the existing orange
    // native color branch explicitly, with its original texture and glow.
    for (const init of tree.m_Initializers || []) if (init._class === 'C_INIT_RandomColor' && init.m_flOpStrength) init.m_flOpStrength = literal(1);
    for (const renderer of tree.m_Renderers || []) delete renderer.m_nHSVShiftControlPoint;
  }
}
for (const name of ['snapfire_lizard_blobs_arced', 'hero_snapfire_ultimate_impact', 'hero_snapfire_ultimate_linger']) load(nativePrefix + name + '.vpcf');
assert.equal(nodes.size, 30);
const layers = [], outputs = [];
for (const [resource, node] of nodes) {
  const name = stem(resource), plan = plans[name];
  if (name === 'snapfire_lizard_blobs_arced') node.tree.m_Children = node.tree.m_Children.filter(child => !excluded.has(stem(child.m_ChildRef.__resource)));
  adapt(node.tree, name);
  const result = target(resource), text = header + kv(node.tree) + '\n', dest = path.join(output, 'source', result);
  fs.mkdirSync(path.dirname(dest), { recursive: true }); fs.writeFileSync(dest, text);
  outputs.push(result); layers.push({ resource: result, native_resource: resource, native_data_sha256: hash(node.data), source_sha256: hash(text), plan });
}
const manifest = {
  native_ability: 'Snapfire — Mortimer Kisses (R)', radius: referenceRadius,
  roots: { flight: targetPrefix + 'fall.vpcf', impact: targetPrefix + 'impact.vpcf', linger: targetPrefix + 'linger.vpcf' },
  controls: { flight: { CP0: 'Current sky position', CP3: 'Same sky position; forward Vector(0,0,-1)', CP20_x: referenceRadius }, impact: { CP0: 'Landing ground position', CP3: 'Same landing ground position', CP20_x: referenceRadius }, linger: { CP0: 'Landing ground position', CP3: 'Same landing ground position for shared impact descendants', CP20_x: referenceRadius } },
  graph: { flight_resources: 6, impact_resources: 8, linger_resources: 17, shared_impact_glow_resources: 1, unique_resources: 30, removed_launch_children: [...excluded], old_arced_explosion_used: false },
  motion: 'Lua owns sky descent and original damage timing; no native projectile attractor, automatic arc, mouth cast burst, delay, model growth or projectile endcap',
  lifecycle: { flight: 'Immediate DestroyParticle(true)+Release at original landing time', impact: 'Release only; all native finite impact emitter/lifetime/fade/decay behavior retained', linger: 'Release only; native StopAfterCPDuration3.1s and all child emission/lifetime/fade/decay behavior retained' },
  geometry: { pool_unit_XY_AABB_extent: poolUnitXY, native_pool_curve_maximum_radius: 40, sphere_unit_XY_AABB_extent: sphereUnitXY, sphere_unit_3D_AABB_extent: sphereUnit3D, native_projectile_unit_3D_AABB_extent: 5.615005461542527, native_projectile_maximum_particle_radius: 0.6, native_projectile_renderer_radius_scale: 40 },
  sizing: 'CP20 radius scaling preserves native random initialization and interpolation. Native per-frame replacement curves receive one final SCALE_CURRENT_VALUE operator. Layer center/width/trail budgets and final fixed150-contract radius clamps keep nominal geometry within the described explosion radius. Pool/main sphere/bloom retain original models, materials, textures and colors.',
  color: 'Shockwave explicitly uses its existing native orange color branch; native color-only CP61/62 inputs are removed. Other colors remain native.',
  validation_limit: 'Compiled asset/operator verification does not establish in-game appearance, texture alpha fringe, bloom or rope tessellation bounds.',
  in_game_visual_verified: false, outputs, layers,
};
fs.writeFileSync(path.join(output, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log('ARCANE_SNAPFIRE_SOURCE_PASS resources=' + outputs.length + ' flight=6 impact=8 linger=17');
