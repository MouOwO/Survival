'use strict';
// Copy the installed native Underlord graph and scale its spatial attributes.
// No native resource is replaced. Timing, counts, color, materials and topology
// remain native; the caller supplies a horizontal CP1 basis and owns lifetime.
const fs = require('fs'), path = require('path'), cp = require('child_process');
const assert = require('assert'), crypto = require('crypto');
const { open } = require('../vpk_inspect.cjs');
const root = path.resolve(__dirname, '../..');
const nativePrefix = 'particles/units/heroes/heroes_underlord/abbysal_underlord_portal_ambient';
const targetPrefix = 'particles/survival_environment/rich_portal/ambient';
const output = path.join(root, 'art/effects/rich_portal');
const evidence = path.join(root, 'tmp/portal_native_graph_20261022/rich_build');
const SCALE = 3;
const header = '<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->\n';
const number = v => { assert(Number.isFinite(v), 'Generated particle number must be finite'); return { __number: v, raw: Number.isInteger(v) ? v.toFixed(1) : String(v) }; };
const integer = v => ({ __number: v, raw: String(v) });
const n = v => v && typeof v === 'object' && '__number' in v ? v.__number : v;
const sha = v => crypto.createHash('sha256').update(v).digest('hex');
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
function extractData(text) {
  const marker = text.indexOf('--- vpcf block DATA'); assert(marker >= 0, 'No VPCF DATA');
  const begin = text.indexOf('{', marker); let depth = 0, quoted = false, escaped = false;
  for (let i = begin; i < text.length; i++) {
    const ch = text[i];
    if (quoted) { if (escaped) escaped = false; else if (ch === '\\') escaped = true; else if (ch === '"') quoted = false; continue; }
    if (ch === '"') quoted = true;
    else if (ch === '{') depth++;
    else if (ch === '}' && --depth === 0) return text.slice(begin, i + 1);
  }
  throw Error('Unclosed native DATA');
}
function scaleCurve(curve) {
  assert(curve && curve.m_spline, 'Absolute radius curve required');
  for (const point of curve.m_spline) for (const key of ['y', 'm_flSlopeIncoming', 'm_flSlopeOutgoing']) if (point[key] !== undefined) point[key] = number(n(point[key]) * SCALE);
  for (const key of ['m_vDomainMins', 'm_vDomainMaxs']) if (curve[key]) curve[key][1] = number(n(curve[key][1]) * SCALE);
}
function adapt(tree, resource) {
  const changes = [];
  if (n(tree.m_nMaxParticles) !== 0) {
    // Native C_INIT_GlobalScale operates on already initialized radius,
    // position about CP1, and velocity. Ground-projected layers must project
    // after spatial scaling; otherwise the CP1 height scales their ground
    // offset through the floor. Other layers retain the final initializer.
    // A negative scale CP disables external scaling input.
    tree.m_Initializers ||= [];
    const globalScale = { _class: 'C_INIT_GlobalScale', m_flScale: number(SCALE),
      m_nScaleControlPointNumber: integer(-1), m_nControlPointNumber: integer(1),
      m_bScaleRadius: true, m_bScalePosition: true, m_bScaleVelocity: true };
    const groundAt = tree.m_Initializers.findIndex(init => init._class === 'C_INIT_PositionPlaceOnGround');
    if (groundAt >= 0) {
      tree.m_Initializers.splice(groundAt, 0, globalScale);
      changes.push('native C_INIT_GlobalScale x3 before final ground projection; preserve ground+2');
    } else {
      tree.m_Initializers.push(globalScale);
      changes.push('append native C_INIT_GlobalScale: radius/position/velocity x3 around CP1');
    }
  }
  for (const op of tree.m_Operators || []) {
    if (op._class === 'C_OP_SetFloat' && (op.m_nOutputField === undefined || n(op.m_nOutputField) === 3)
        && op.m_nSetMethod !== 'PARTICLE_SET_SCALE_INITIAL_VALUE' && op.m_nSetMethod !== 'PARTICLE_SET_SCALE_CURRENT_VALUE') {
      // Two native rope layers write absolute radius each frame. Scaling only
      // their initial radius would be overwritten on the first simulation.
      assert.equal(op.m_InputValue.m_nMapType, 'PF_MAP_TYPE_CURVE');
      scaleCurve(op.m_InputValue.m_Curve); changes.push('absolute per-frame radius curve x3');
    }
    if (op._class === 'C_OP_OscillateScalar' && n(op.m_nField) === 3) {
      for (const key of ['m_RateMin', 'm_RateMax']) if (op[key] !== undefined) op[key] = number(n(op[key]) * SCALE);
      changes.push('additive radius oscillation rates x3');
    }
    if (op._class === 'C_OP_DampenToCP') {
      op.m_flRange = number(n(op.m_flRange) * SCALE); changes.push('distance damping range x3');
    }
  }
  for (const renderer of tree.m_Renderers || []) {
    for (const key of ['m_flTextureVWorldSize']) if (renderer[key] !== undefined) {
      if (renderer[key] && typeof renderer[key] === 'object' && !('__number' in renderer[key])) {
        assert.equal(renderer[key].m_nType, 'PF_TYPE_LITERAL');
        renderer[key].m_flLiteralValue = number(n(renderer[key].m_flLiteralValue) * SCALE);
      } else renderer[key] = number(n(renderer[key]) * SCALE);
      changes.push(key + ' x3 in world units');
    }
    if (renderer.m_flDepthBias !== undefined) changes.push('preserve native m_flDepthBias');
  }
  for (const child of tree.m_Children || []) {
    assert(child.m_ChildRef.__resource.startsWith(nativePrefix), 'Unexpected non-native child');
    child.m_ChildRef.__resource = child.m_ChildRef.__resource.replace(nativePrefix, targetPrefix);
  }
  // Preview-only model drivers are intentionally removed: rich is one ground
  // effect with no model. Runtime CP0/1/2 must share the requested center.
  delete tree.m_controlPointConfigurations;
  tree.m_BoundingBoxMin = [-1600, -1600, -1600].map(number);
  tree.m_BoundingBoxMax = [1600, 1600, 1600].map(number);
  return changes;
}
function build() {
  fs.mkdirSync(evidence, { recursive: true });
  const pack = open(path.resolve(root, '../../dota/pak01_dir.vpk'));
  const entries = new Map(pack.entries.map(e => [e.path, e]));
  const nodes = new Map();
  function load(resource) {
    if (nodes.has(resource)) return;
    const entry = entries.get(resource + '_c'); assert(entry, 'Missing native particle ' + resource);
    const bytes = pack.read(entry), extracted = path.join(evidence, path.basename(resource) + '_c');
    fs.writeFileSync(extracted, bytes);
    const text = cp.execFileSync(path.resolve(root, '../../bin/win64/resourceinfo.exe'), ['-i', extracted, '-all'],
      { encoding: 'utf8', windowsHide: true, maxBuffer: 32 * 1024 * 1024 });
    fs.writeFileSync(extracted + '.txt', text);
    const tree = parse(extractData(text)); nodes.set(resource, { tree, sha256: sha(bytes) });
    for (const child of tree.m_Children || []) load(child.m_ChildRef.__resource);
  }
  load(nativePrefix + '.vpcf'); assert.equal(nodes.size, 15, 'Native graph changed; review adaptation');
  const layers = [];
  for (const [resource, node] of nodes) {
    const native = structuredClone(node.tree), changes = adapt(node.tree, resource);
    const target = resource.replace(nativePrefix, targetPrefix), file = path.join(output, 'source', target);
    const body = header + kv(node.tree) + '\n';
    fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, body);
    layers.push({ resource: target, native_resource: resource, native_sha256: node.sha256,
      source_sha256: sha(body), native_children: (native.m_Children || []).length, changes });
  }
  const binary = fs.readFileSync(path.resolve(root, '../../bin/win64/particles.dll'));
  const schemaFields = ['C_INIT_GlobalScale', 'm_flScale', 'm_nScaleControlPointNumber', 'm_nControlPointNumber', 'm_bScaleRadius', 'm_bScalePosition', 'm_bScaleVelocity'];
  for (const field of schemaFields) assert(binary.includes(Buffer.from(field + '\0')), 'Native schema missing ' + field);
  const manifest = { root: targetPrefix + '.vpcf', native_root: nativePrefix + '.vpcf', scale: SCALE,
    transform: 'one horizontal native graph; caller sets CP0/1/2 to one ground center and their orientation basis; CP4/61/62 remain zero',
    global_scale: { class: 'C_INIT_GlobalScale', multiplier: SCALE, center_control_point: 1, external_scale_control_point: -1,
      radius: true, position: true, velocity: true,
      initializer_order: 'after native spatial attributes, before ground projection when present; otherwise last' },
    schema_evidence: { installed_dll: 'game/bin/win64/particles.dll', sha256: sha(binary), verified_strings: schemaFields,
      compiler_round_trip: 'Run tools/build_rich_portal_particles.ps1 then tools/verify_rich_portal_particles.cjs',
      reference_schema: 'https://github.com/a2x/cs2-dumper/blob/main/output/particles_dll.hpp#L5990' },
    preserved: ['15 reachable native particle systems', 'all native textures and materials', 'colors and HSV controls', 'native renderer depth bias', 'emitter rates and particle counts', 'lifetimes, startup delays, fade and alpha curves', 'child topology and repetitions'],
    original_resources_untouched: true, outputs: layers };
  fs.mkdirSync(output, { recursive: true }); fs.writeFileSync(path.join(output, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
  console.log('RICH_PORTAL_SOURCE_PASS native_nodes=15 scale=3 root=' + manifest.root);
  return manifest;
}
module.exports = { parse, kv, extractData, adapt, n, build, nativePrefix, targetPrefix };
if (require.main === module) build();
