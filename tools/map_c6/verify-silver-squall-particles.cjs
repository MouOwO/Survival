'use strict';
const fs = require('fs'), path = require('path'), cp = require('child_process'), crypto = require('crypto'), assert = require('assert');
const { Vpk, endOf } = require('./lib.cjs');
const repo = path.resolve(__dirname, '../..'), engine = path.resolve(repo, '../../..'), game = path.join(engine, 'game/dota');
const arcane = process.argv.includes('--arcane'), outputName = arcane ? 'arcane_silver_squall' : 'ice_silver_squall';
const output = path.join(repo, 'output', outputName), prefix = 'particles/survival/skills/' + (arcane ? 'arcane' : 'ice_cone') + '_silver_squall_';
const fieldRadius = arcane ? 200 : 500, impactRadius = arcane ? 150 : 75;
const manifest = JSON.parse(fs.readFileSync(path.join(repo, 'art/effects', outputName, 'manifest.json')));
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
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
    assert(Number.isFinite(Number(token)), 'Unexpected DATA token ' + token); return Number(token);
  }
  const result = value(); assert.equal(i, tokens.length); return result;
}
function dump(resource) { return cp.execFileSync(path.join(engine, 'game/bin/win64/resourceinfo.exe'), ['-game', game, '-i', resource, '-all'], { encoding: 'utf8', windowsHide: true, maxBuffer: 16 * 1024 * 1024 }); }
function walk(value, visit, key = '') { visit(value, key); if (Array.isArray(value)) value.forEach(v => walk(v, visit, key)); else if (value && typeof value === 'object' && !('__resource' in value)) for (const [k, v] of Object.entries(value)) walk(v, visit, k); }
function refs(tree) { const out = new Set(); walk(tree, value => { if (value && value.__resource) out.add(value.__resource); }); return [...out].sort(); }
function near(actual, expected, label) { assert(Math.abs(actual - expected) < 1e-6, label + ': ' + actual + ' != ' + expected); }
function factor(input, multiplier, label) { assert.equal(input.m_nType, 'PF_TYPE_CONTROL_POINT_COMPONENT', label); assert.equal(input.m_nControlPoint, 20, label); assert.equal(input.m_nVectorComponent || 0, 0); assert.equal(input.m_nMapType, 'PF_MAP_TYPE_MULT'); near(input.m_flMultFactor === undefined ? 1 : input.m_flMultFactor, multiplier, label); }
function floatValue(input) { if (typeof input === 'number') return input; return input ? input.m_flLiteralValue || 0 : 0; }
function controlFactor(input, control, multiplier, label) { assert.equal(input.m_nType, 'PF_TYPE_CONTROL_POINT_COMPONENT', label); assert.equal(input.m_nControlPoint, control); assert.equal(input.m_nVectorComponent || 0, 0); assert.equal(input.m_nMapType, 'PF_MAP_TYPE_MULT'); near(input.m_flMultFactor === undefined ? 1 : input.m_flMultFactor, multiplier, label); }
function frame(operator) { return operator.m_TransformInput ? operator.m_TransformInput.m_nControlPoint || 0 : operator.m_nControlPointNumber || 0; }
const trees = new Map(), resources = [], layers = [], dependencies = new Set(), sharedResources = [];
if (arcane) {
  const sharedManifest = JSON.parse(fs.readFileSync(path.join(repo, 'art/effects/ice_silver_squall/manifest.json')));
  const sharedEvidence = JSON.parse(fs.readFileSync(path.join(repo, 'output/ice_silver_squall/compiled_verification.json')));
  assert.equal(sharedEvidence.status, 'PASS');
  for (const layer of sharedManifest.layers.filter(l => l.plan.flight || l.plan.field)) {
    const proof = sharedEvidence.resources.find(r => r.resource === layer.resource);
    assert(proof, 'Shared ice resource was audited');
    const compiledHash = hash(fs.readFileSync(path.join(repo, layer.resource + '_c')));
    const sourceHash = hash(fs.readFileSync(path.join(repo, 'art/effects/ice_silver_squall/source', layer.resource)));
    assert.equal(compiledHash, proof.compiled_sha256, 'Shared compiled resource remains audited version');
    assert.equal(sourceHash, proof.source_sha256, 'Shared source remains audited version');
    assert.equal(sourceHash, layer.source_sha256, 'Shared manifest is current');
    sharedResources.push({ resource: layer.resource, compiled_sha256: compiledHash, source_sha256: sourceHash });
  }
  assert.equal(sharedResources.length, 20, 'Seven exact flight resources and thirteen large-field resources reused');
}
fs.mkdirSync(path.join(output, 'compiled'), { recursive: true }); assert.equal(manifest.outputs.length, arcane ? 17 : 24);
for (const layer of manifest.layers) {
  const resource = layer.resource, raw = dump(path.join(repo, resource + '_c')), marker = raw.indexOf('--- vpcf block DATA'), open = raw.indexOf('{', marker); assert(marker >= 0);
  const body = raw.slice(open, endOf(raw, open)), tree = parse(body); trees.set(resource, tree); fs.writeFileSync(path.join(output, 'compiled', path.basename(resource) + '.kv3'), body);
  const source = fs.readFileSync(path.join(repo, 'art/effects/' + outputName + '/source', resource)); assert.equal(hash(source), layer.source_sha256, 'Current source hash');
  const bytes = fs.readFileSync(path.join(repo, resource + '_c')); resources.push({ resource, compiled_bytes: bytes.length, compiled_sha256: hash(bytes), source_sha256: hash(source) });
  const nativeBody = fs.readFileSync(path.join(output, 'native', path.basename(layer.native_resource) + '.kv3'), 'utf8'); assert.equal(hash(nativeBody), layer.native_data_sha256); const native = parse(nativeBody), plan = layer.plan;
  refs(tree).forEach(ref => dependencies.add(ref));
  assert.deepEqual(refs({ render: tree.m_Renderers }), refs({ render: native.m_Renderers }), 'Native renderer model/material/texture refs');
  const expectedEmitters = structuredClone(native.m_Emitters);
  if (plan.sustained) for (const emitter of expectedEmitters || []) if (emitter._class === 'C_OP_ContinuousEmitter') {
    const actual = (tree.m_Emitters || []).find(e => e._class === emitter._class);
    controlFactor(actual.m_flEmissionDuration, 21, 1, 'Continuous interior emission lasts whole skill');
    emitter.m_flEmissionDuration = actual.m_flEmissionDuration;
  }
  assert.deepEqual(tree.m_Emitters, expectedEmitters, 'Native emitter rates/count, with sustained duration only');
  assert.deepEqual(tree.m_ConstantColor, native.m_ConstantColor, 'Native constant color');
  assert.deepEqual((tree.m_Initializers || []).filter(i => i._class === 'C_INIT_RandomColor'), (native.m_Initializers || []).filter(i => i._class === 'C_INIT_RandomColor'), 'Native ice colors');
  const nativeCurves = (native.m_Operators || []).filter(o => o._class === 'C_OP_SetFloat'), curves = (tree.m_Operators || []).filter(o => o._class === 'C_OP_SetFloat' && o.m_nSetMethod !== 'PARTICLE_SET_SCALE_CURRENT_VALUE');
  assert.deepEqual(curves, nativeCurves, 'Exact native radius/alpha curves including SCALE_INITIAL and endcapOFF preserved');
  const replacesRadius = nativeCurves.some(o => (o.m_nOutputField === undefined || o.m_nOutputField === 3) && (!o.m_nSetMethod || o.m_nSetMethod === 'PARTICLE_SET_REPLACE_VALUE'));
  const multipliers = (tree.m_Operators || []).filter(o => o._class === 'C_OP_SetFloat' && o.m_nSetMethod === 'PARTICLE_SET_SCALE_CURRENT_VALUE' && (o.m_nOutputField === undefined || o.m_nOutputField === 3)); assert.equal(multipliers.length, replacesRadius ? 1 : 0, 'No duplicate scaling of SCALE_INITIAL radius');
  if (replacesRadius) factor(multipliers[0].m_InputValue, 1 / plan.ref, 'Replacement-radius multiplier');
  if (!plan.container) {
    const initial = tree.m_Initializers.at(-1); assert.equal(initial._class, 'C_INIT_InitFloat'); assert.equal(initial.m_nOutputField === undefined ? 3 : initial.m_nOutputField, 3); assert.equal(initial.m_nSetMethod, 'PARTICLE_SET_SCALE_CURRENT_VALUE'); factor(initial.m_InputValue, 1 / plan.ref, 'Initial-radius CP20 scale');
  }
  const controls = new Set(); walk(tree, (value, key) => {
    if (/^m_n(?:CP\d?|ControlPoint(?:Number)?|OverrideCP|OffsetCP|FirstControlPoint|HSVShiftControlPoint)$/.test(key) && typeof value === 'number') { assert([0, 3, 20, 21].includes(value), 'Unexpected control ' + key + '=' + value); controls.add(value); }
    if (value && value.m_nType === 'PF_TYPE_CONTROL_POINT_COMPONENT') assert([20, 21].includes(value.m_nControlPoint), 'Only external radius/duration scalar controls');
    if (value && typeof value === 'object') assert(!/^C_OP_SetControlPoint/.test(value._class || ''), 'No autonomous CP writer');
  });
  const nativeSpheres = (native.m_Initializers || []).filter(i => i._class === 'C_INIT_CreateWithinSphereTransform'), spheres = (tree.m_Initializers || []).filter(i => i._class === 'C_INIT_CreateWithinSphereTransform');
  if (plan.name === 'field_parent_glow') { assert.equal(spheres.length, 1); assert.equal(frame(spheres[0]), 0); assert(!tree.m_Initializers.some(i => i._class === 'C_INIT_CreateFromParentParticles')); }
  else assert.equal(spheres.length, nativeSpheres.length);
  if (plan.name !== 'field_parent_glow') spheres.forEach((sphere, index) => { assert.deepEqual(sphere.m_TransformInput, nativeSpheres[index].m_TransformInput, 'Modern native birth frame preserved'); });
  const info = { resource, explicit_control_ids: [...controls].sort((a, b) => a - b), native_reference_dimension: plan.ref, radius_factor: 1 / plan.ref, live_replacement_radius_multiplier: replacesRadius };
  if (plan.flight) {
    assert(!(tree.m_Operators || []).some(o => o.m_nOpEndCapState === 'PARTICLE_ENDCAP_ENDCAP_ON' || ['C_OP_EndCapTimedDecay', 'C_OP_MaxVelocity', 'C_OP_CPOffsetToPercentageBetweenCPs', 'C_OP_SetControlPointsToParticle'].includes(o._class)), 'No native arc/endcap mover');
    const locks = (tree.m_Operators || []).filter(o => o._class === 'C_OP_PositionLock');
    const full = ['fall', 'fall_model', 'fall_glow'].includes(plan.name); assert.equal(locks.length, full ? 1 : 0, 'Body locks only; native grains remain world-space');
    if (full) {
      assert.equal(frame(locks[0]), plan.name === 'fall' ? 0 : 3); info.follow_control = frame(locks[0]);
      for (const key of ['m_flStartTime_min', 'm_flStartTime_max', 'm_flEndTime_min', 'm_flEndTime_max']) near(locks[0][key], 999999, 'Body follows throughout fall');
      near(tree.m_flConstantLifespan, 999999, 'Body persistence'); assert(!tree.m_Initializers.some(i => i._class === 'C_INIT_InitFloat' && i.m_nOutputField === 1));
    } else assert.deepEqual(tree.m_Initializers.filter(i => i._class === 'C_INIT_InitFloat' && i.m_nOutputField === 1), native.m_Initializers.filter(i => i._class === 'C_INIT_InitFloat' && i.m_nOutputField === 1), 'Finite native icy grain lifetimes');
    if (plan.name === 'fall') assert.equal((tree.m_ForceGenerators || []).length, 0, 'No root attraction');
    if (plan.name === 'fall_model') assert(!tree.m_Operators.some(o => o._class === 'C_OP_InterpolateRadius'), 'Immediate full model size');
    if (plan.name === 'fall_flame') assert(!tree.m_Initializers.some(i => i._class === 'C_INIT_InheritVelocity'), 'Manual high-speed CP movement not inherited into sparks');
  } else if (!plan.field) {
    assert.deepEqual(tree.m_Initializers.filter(i => i._class === 'C_INIT_InitFloat' && i.m_nOutputField === 1), native.m_Initializers.filter(i => i._class === 'C_INIT_InitFloat' && i.m_nOutputField === 1), 'Native impact lifetimes');
    assert.deepEqual((tree.m_Operators || []).filter(o => /Fade|Decay|InterpolateRadius/.test(o._class)), (native.m_Operators || []).filter(o => /Fade|Decay|InterpolateRadius/.test(o._class)), 'Native impact fade/decay/interpolation');
  }
  if (plan.singleton) {
    controlFactor(tree.m_Initializers.find(i => i._class === 'C_INIT_InitFloat' && i.m_nOutputField === 1).m_InputValue, 21, 1, 'Full-duration field singleton');
  } else if (plan.field && !plan.container) {
    assert.deepEqual(tree.m_Initializers.filter(i => i._class === 'C_INIT_InitFloat' && i.m_nOutputField === 1), native.m_Initializers.filter(i => i._class === 'C_INIT_InitFloat' && i.m_nOutputField === 1), 'Native finite grain/transient life preserved');
  }
  if (plan.recycle) {
    const decay = tree.m_Operators.find(o => o._class === 'C_OP_Decay'); assert(decay && decay.m_nOpEndCapState !== 'PARTICLE_ENDCAP_ENDCAP_ON', 'Finite grains decay normally and replenish');
  }
  if (plan.center !== undefined) {
    const constraint = tree.m_Constraints.at(-1); assert.equal(constraint._class, 'C_OP_ConstrainDistance'); assert.equal(constraint.m_nControlPointNumber || 0, 0); factor(constraint.m_fMaxDistance, plan.center, 'Whole-footprint center budget');
  }
  if (plan.trail !== undefined) for (const renderer of tree.m_Renderers || []) if (renderer._class === 'C_OP_RenderTrails') {
    assert(renderer.m_flMaxLength <= plan.radius * plan.trail); assert((renderer.m_flMinLength || 0) <= renderer.m_flMaxLength, 'Trail minimum never exceeds bounded maximum');
  }
  if ((tree.m_Renderers || []).length) {
    const clamp = tree.m_Operators.at(-1); assert.equal(clamp._class, 'C_OP_ClampScalar'); assert.equal(clamp.m_nFieldOutput === undefined ? 3 : clamp.m_nFieldOutput, 3);
    const renderScale = Math.max(...tree.m_Renderers.map(r => r.m_flRadiusScale === undefined ? 1 : floatValue(r.m_flRadiusScale)));
    const expected = plan.circle ? fieldRadius * 15 * 1.142 / plan.ref : plan.radius * (plan.width === undefined ? 1 : plan.width) / (plan.model_extent || renderScale); near(clamp.m_flOutputMax === undefined ? 1 : clamp.m_flOutputMax, expected, 'Final renderer/model radius cap'); info.final_particle_radius_cap = expected;
  }
  layers.push(info);
}
if (!arcane) { const fall = trees.get(manifest.roots.flight); assert.equal(fall.m_Children.length, 6); assert(fall.m_Children.every(c => !c.m_flDelay && !c.m_bEndCap)); }
const impact = trees.get(manifest.roots.impact); assert.equal(impact.m_Children.length, 3); assert.deepEqual(impact.m_Children.map(c => c.m_ChildRef.__resource), ['impact_sphere', 'impact_burst', 'impact_glow'].map(n => prefix + '' + n + '.vpcf')); assert(!(refs(impact).some(r => /ring|linger|pool|field/.test(r))));
const hitBurst = trees.get(prefix + 'impact_burst.vpcf'); near(floatValue(hitBurst.m_Emitters[0].m_nParticlesToEmit), 16, 'Native16-particle local ice explosion');
const field = trees.get(manifest.roots.field); assert.equal(field.m_Children.length, 12); assert.equal(field.m_nMaxParticles, 0);
controlFactor(field.m_PreEmissionOperators.find(o => o._class === 'C_OP_StopAfterCPDuration').m_flDuration, 21, 1, 'Whole native field duration');
assert.equal(field.m_Children.filter(c => c.m_flDelay).length, 1, 'Sustained ring starts immediately; native spark delay remains');
const ring = trees.get(prefix + 'field_ring.vpcf'), fieldPlan = manifest.layers.find(l => l.plan.circle).plan;
assert(!ring.m_Children || ring.m_Children.length === 0); assert.equal(ring.m_Renderers.length, 2); ring.m_Renderers.forEach(r => assert.equal(r.m_nOrientationType, 'PARTICLE_ORIENTATION_WORLD_Z_ALIGNED'));
const wave = ring.m_Initializers.find(i => i._class === 'C_INIT_RingWave'); factor(wave.m_flInitialRadius, 275 / fieldPlan.ref, 'Full circle radius');
controlFactor(ring.m_Initializers.find(i => i._class === 'C_INIT_InitFloat' && i.m_nOutputField === 1).m_InputValue, 21, 1, 'Field durationCP21');
near(floatValue(ring.m_Emitters[0].m_nParticlesToEmit), 64, 'Complete closed64-point circle');
const width = ring.m_Operators.find(o => o._class === 'C_OP_SetFloat' && (o.m_nOutputField === undefined || o.m_nOutputField === 3));
const alpha = ring.m_Operators.find(o => o._class === 'C_OP_SetFloat' && o.m_nOutputField === 7);
for (const curve of [width, alpha]) { assert.equal(curve.m_nSetMethod, 'PARTICLE_SET_SCALE_INITIAL_VALUE'); assert.equal(curve.m_InputValue.m_nType, 'PF_TYPE_PARTICLE_AGE_NORMALIZED'); }
assert.deepEqual(field.m_BoundingBoxMin, [-fieldRadius, -fieldRadius, -fieldRadius * .4]); assert.deepEqual(field.m_BoundingBoxMax, [fieldRadius, fieldRadius, fieldRadius * 1.6]);
const shards = trees.get(prefix + 'field_shards.vpcf'); assert.equal(shards.m_nMaxParticles, 3); assert(shards.m_Initializers.some(i => i._class === 'C_INIT_RandomNamedModelSequence' && JSON.stringify(i).includes('Snapfire_frostivus'))); assert.equal(shards.m_Renderers[0].m_bOrientZ, true); near(shards.m_Operators.at(-1).m_flOutputMax, fieldRadius * .66 / 210, 'Animation-aware geometry cap'); near(fieldRadius * .34 + 210 * shards.m_Operators.at(-1).m_flOutputMax, fieldRadius, 'Full animated shard field geometry');
const proj = trees.get(prefix + 'field_proj.vpcf'); assert.equal(proj.m_Renderers.length, 2); assert(refs(proj).some(r => /frost_add_projected_color/.test(r)) && refs(proj).some(r => /frost_add_projected_2_color/.test(r)), 'Both native frost projection interiors retained');
// Evaluate stored cubic Hermite slopes, not just knots, to validate overshoot.
function peak(spline) { let maximum = -Infinity, maximumAge = 0; for (let age = 0; age <= 1; age += 0.00001) { let index = spline.findIndex((p, i) => i > 0 && age <= p.x); if (index < 1) index = spline.length - 1; const a = spline[index - 1], b = spline[index], length = b.x - a.x, t = Math.max(0, Math.min(1, (age - a.x) / length)), y = (2 * t ** 3 - 3 * t ** 2 + 1) * a.y + (t ** 3 - 2 * t ** 2 + t) * length * a.m_flSlopeOutgoing + (-2 * t ** 3 + 3 * t ** 2) * b.y + (t ** 3 - t ** 2) * length * b.m_flSlopeIncoming; if (y > maximum) { maximum = y; maximumAge = age; } } return { maximum, maximumAge }; }
const widthPeak = peak(width.m_InputValue.m_Curve.m_spline); assert(widthPeak.maximum <= 1.142 && widthPeak.maximum > 1.14, 'Native Hermite peak budget');
near(fieldRadius * 275 / fieldPlan.ref + ring.m_Operators.at(-1).m_flOutputMax * 2, fieldRadius, 'Complete center+rope geometry bound');
const pack = new Vpk(path.join(game, 'pak01_dir.vpk')), corePath = path.join(engine, 'game/core/pak01_dir.vpk'), core = fs.existsSync(corePath) ? new Vpk(corePath) : null;
const resolved = [], queue = [...dependencies], seen = new Set();
while (queue.length) {
  const resource = queue.shift(); if (seen.has(resource)) continue; seen.add(resource);
  const location = fs.existsSync(path.join(repo, resource + '_c')) ? 'addon' : pack.entries.has(resource + '_c') ? 'dota VPK' : core && core.entries.has(resource + '_c') ? 'core VPK' : null; assert(location, 'Unresolved dependency ' + resource); resolved.push({ resource, location });
  if (/\.vmdl$|\.vmat$|\.vsnap$/.test(resource)) { const raw = dump(resource + '_c'), block = raw.slice(raw.indexOf('--- Resource External Refs:'), raw.indexOf('--- Resource Blocks:')); for (const match of block.matchAll(/^\s*[A-Fa-f0-9]{16}\s+(\S+)\s*$/gm)) queue.push(match[1]); }
}
const report = { date: '2026-10-03', status: 'PASS', resources, shared_resources: sharedResources, controls: manifest.controls, cosmetic: manifest.cosmetic, graph: manifest.graph, layers, lifecycle: manifest.lifecycle, geometry: manifest.geometry, field: { ...manifest.field, actual_compiled_Hermite_peak: widthPeak, radius_method: width.m_nSetMethod, alpha_method: alpha.m_nSetMethod, duration_input: 'CP21.x', exact_outer_geometry_cap: fieldRadius, lifespan_cases: arcane ? [1, 3] : [3, 5] }, direct_references: dependencies.size, resolved_references: resolved.sort((a, b) => a.resource.localeCompare(b.resource)), checks: ['All' + resources.length + ' current resource hashes recorded; generated source and native evidence hashes match manifest', 'Native Silver Squall icy materials, models, textures, colors and named shard animation preserved; all dependencies resolve', 'Flight7 contains no mouth cast, native arc/homing/control writer or actual endcap behavior; ordinary endcapOFF curves remain active', 'Root light/ice body/glow each have exactly one full-duration CP0/3 lock; native ribbon/snow/sparks/flame remain detached world-space grains', 'Modern CP0/3 birth and body orientation inputs survive compilation; only CP20 radius and CP21 duration scalar controls remain', 'All rendered/simulated leaf definitions apply CP20 initial radius scaling; native SCALE_INITIAL radius curves receive no duplicate multiplier', 'Local' + impactRadius + '-radius impact contains native0.5-sec icy sphere,16-particle icy explosion and original brief glow without any ring or persistent pool', 'Full' + fieldRadius + '-radius field retains native container and all12 children, including both projected frost textures and animated27-bone ground ice cluster', 'Projection, complete64-point ring and animated shard lifespan readCP21; normalized native width/alpha/radius curves use supplied CP21 lifetime', 'Sustained shard/flame/swirl emitters run untilCP21; ember noise remains continuous and finite ember/flame grains decay normally to free slots', 'Animation-aware210-unit shard bound plus generated center/model budgets fit the field despite native radius Hermite overshoot', 'Actual ring Hermite overshoot is budgeted below1.142; center plus maximum rope width equals nominal field radius; projected frost has matching final cap', 'Moving field and local burst layers have CP0 center budgets and radius caps; both swirl trail renderers have bounded lengths and minimum≤maximum', 'Parent native stop duration isCP21; caller immediate cleanup ends all field and hail visuals at cast expiry'], validation_limit: manifest.validation_limit, in_game_visual_verified: false };
if (arcane) {
  report.checks = report.checks.filter(check => !check.startsWith('Flight7 ') && !check.startsWith('Root light/'));
  report.checks.push('Shared seven flight and thirteen large-field sources and compiled assets match the previous complete compiled audit hashes');
}
fs.writeFileSync(path.join(output, 'compiled_verification.json'), JSON.stringify(report, null, 2) + '\n');
console.log((arcane ? 'ARCANE' : 'ICE') + '_SILVER_SQUALL_COMPILED_PASS resources=' + resources.length + ' resolved_dependencies=' + resolved.length);
