'use strict';
const fs = require('fs'), path = require('path'), cp = require('child_process');
const assert = require('assert'), crypto = require('crypto');
const { open } = require('./vpk_inspect.cjs');
const { parse, extractData, n } = require('./map_c6/build-rich-portal-particles.cjs');
const root = path.resolve(__dirname, '..');
const art = path.join(root, 'art/effects/rich_portal');
const manifest = JSON.parse(fs.readFileSync(path.join(art, 'manifest.json'), 'utf8'));
const pack = open(path.resolve(root, '../../dota/pak01_dir.vpk'));
const entries = new Map(pack.entries.map(e => [e.path, e]));
const sha = b => crypto.createHash('sha256').update(b).digest('hex');
const plain = v => Array.isArray(v) ? v.map(plain) : v && typeof v === 'object' ?
  ('__number' in v ? n(v) : '__resource' in v ? v.__resource : Object.fromEntries(Object.entries(v).map(([k, x]) => [k, plain(x)]))) : v;
const base = path.join(root, 'tmp/portal_native_graph_20261022/rich_verify');
fs.mkdirSync(base, { recursive: true });
function readCompiled(file) {
  const dump = cp.execFileSync(path.resolve(root, '../../bin/win64/resourceinfo.exe'),
    ['-i', file, '-all'], { encoding: 'utf8', windowsHide: true, maxBuffer: 32 * 1024 * 1024 });
  fs.writeFileSync(path.join(base, path.basename(file) + '.txt'), dump);
  return parse(extractData(dump));
}
const defaults = plain(readCompiled(path.join(root, 'tmp/portal_native_graph_20261022/schema/defaults.vpcf_c')).m_Initializers[0]);
const counterexample = plain(readCompiled(path.join(root, 'tmp/portal_native_graph_20261022/schema/counterexample.vpcf_c')).m_Initializers[0]);
assert.equal(defaults._class, 'C_INIT_GlobalScale');
assert.equal(counterexample.m_nScaleControlPointNumber, 17);
for (const key of ['m_bScaleRadius', 'm_bScalePosition', 'm_bScaleVelocity']) {
  assert.equal(defaults[key], undefined, 'Defaults are omitted from native DATA');
  assert.equal(counterexample[key], false, 'Counterexample must prove native schema recognizes ' + key);
}
assert.equal(manifest.scale, 3); assert.equal(manifest.outputs.length, 15);
let scales = 0, absoluteCurves = 0, groundProjectedLayers = 0, nativeDepthRenderers = 0, checks = [];
const targets = new Set(manifest.outputs.map(x => x.resource));
for (const row of manifest.outputs) {
  const source = fs.readFileSync(path.join(art, 'source', row.resource));
  assert.equal(sha(source), row.source_sha256);
  const content = fs.readFileSync(path.resolve(root, '../../../content/dota_addons/Survival', row.resource));
  // The independent Content checkout may use CRLF under its Git settings.
  // Compare source text while preserving all non-line-ending differences.
  assert.equal(source.toString('utf8').replace(/\r\n/g, '\n'),
    content.toString('utf8').replace(/\r\n/g, '\n'), 'Content/source mismatch: ' + row.resource);
  const nativeBytes = pack.read(entries.get(row.native_resource + '_c'));
  assert.equal(sha(nativeBytes), row.native_sha256, 'Installed original changed');
  assert(!fs.existsSync(path.join(root, row.native_resource + '_c')), 'Never override original native resource');
  const tree = parse(source.toString('utf8').replace(/^<!--[^]*?-->\s*/, ''));
  const dump = cp.execFileSync(path.resolve(root, '../../bin/win64/resourceinfo.exe'),
    ['-i', path.join(root, row.resource + '_c'), '-all'],
    { encoding: 'utf8', windowsHide: true, maxBuffer: 32 * 1024 * 1024 });
  fs.writeFileSync(path.join(base, path.basename(row.resource) + '.txt'), dump);
  const compiled = parse(extractData(dump));
  if ((tree.m_Renderers || []).some(x => x.m_flDepthBias !== undefined)) {
    const nativeFile = path.join(base, 'native_' + path.basename(row.native_resource) + '_c');
    fs.writeFileSync(nativeFile, nativeBytes);
    const native = readCompiled(nativeFile);
    for (let index = 0; index < native.m_Renderers.length; index++) {
      const expected = native.m_Renderers[index].m_flDepthBias;
      if (expected === undefined) continue;
      nativeDepthRenderers++;
      assert.equal(n(compiled.m_Renderers[index].m_flDepthBias), n(expected),
        'Scaling spatial geometry must preserve the native renderer depth bias: ' + row.resource);
    }
  }
  const rendered = n(tree.m_nMaxParticles) !== 0;
  const init = (compiled.m_Initializers || []).filter(x => x._class === 'C_INIT_GlobalScale');
  assert.equal(init.length, rendered ? 1 : 0, 'Every native particle layer scales exactly once');
  if (rendered) {
    scales++;
    const scale = plain(init[0]);
    const sourceScale = plain(tree.m_Initializers.find(x => x._class === 'C_INIT_GlobalScale'));
    assert.equal(scale.m_flScale, 3); assert.equal(scale.m_nControlPointNumber, 1);
    assert.equal(sourceScale.m_nScaleControlPointNumber, -1);
    assert.equal(scale.m_nScaleControlPointNumber, undefined, 'External scale CP is the native -1 default');
    for (const key of ['m_bScaleRadius', 'm_bScalePosition', 'm_bScaleVelocity']) {
      assert.equal(sourceScale[key], true, key);
      assert.equal(scale[key], undefined, 'Enabled scaling is native default: ' + key);
    }
    const globalAt = compiled.m_Initializers.findIndex(x => x._class === 'C_INIT_GlobalScale');
    const groundAt = compiled.m_Initializers.findIndex(x => x._class === 'C_INIT_PositionPlaceOnGround');
    if (groundAt >= 0) {
      groundProjectedLayers++;
      assert.equal(globalAt + 1, groundAt, 'Project to the ground immediately after scaling the native position');
      assert.equal(n(compiled.m_Initializers[groundAt].m_flOffset), 2, 'Keep native ground offset');
      // This dimensional regression represents the actual two operations:
      // scaling around CP1 at ground+12 and projecting onto ground+2. The
      // reversed native copy used to place the black shadow at ground-18.
      const applyHeight = initializers => initializers.reduce((z, op) =>
        op._class === 'C_INIT_GlobalScale' ? 12 + n(op.m_flScale) * (z - 12) :
          op._class === 'C_INIT_PositionPlaceOnGround' ? n(op.m_flOffset) : z, 12);
      assert.equal(applyHeight(compiled.m_Initializers), 2, 'Final shadow must remain above the floor');
      const oldOrder = compiled.m_Initializers.filter(x => x._class !== 'C_INIT_GlobalScale');
      oldOrder.push(init[0]);
      assert.equal(applyHeight(oldOrder), -18, 'Negative control must reproduce the original underground shadow');
    } else assert.equal(compiled.m_Initializers.at(-1)._class, 'C_INIT_GlobalScale', 'Other native layers keep their initializer order');
  }
  assert.deepEqual(plain(compiled.m_Emitters), plain(tree.m_Emitters), 'Compiler must retain native emitter rates and times');
  assert.equal((compiled.m_Children || []).length, row.native_children);
  for (const child of compiled.m_Children || []) assert(targets.has(child.m_ChildRef.__resource), 'Every child is derived once');
  assert(!compiled.m_controlPointConfigurations, 'No model preview can introduce a model into rich');
  for (const op of compiled.m_Operators || []) {
    if (op._class === 'C_OP_DampenToCP') assert.equal(n(op.m_flRange), 315);
    if (op._class === 'C_OP_OscillateScalar' && n(op.m_nField) === 3) {
      assert.equal(n(op.m_RateMin), 30); assert.equal(n(op.m_RateMax), 9);
    }
    if (op._class === 'C_OP_SetFloat' && op.m_nOutputField === undefined && op.m_nSetMethod === undefined) {
      absoluteCurves++;
      const peak = Math.max(...op.m_InputValue.m_Curve.m_spline.map(x => n(x.y)));
      assert(peak > 26, 'Absolute radius must survive simulation at 3x size');
    }
  }
  checks.push({ resource: row.resource, compiled_sha256: sha(fs.readFileSync(path.join(root, row.resource + '_c'))), global_scale: init.length });
}
assert.equal(scales, 14); assert.equal(absoluteCurves, 2); assert.equal(groundProjectedLayers, 1); assert.equal(nativeDepthRenderers, 2);
const report = { status: 'PASS', native_nodes: 15, globally_scaled_layers: scales, scale: 3,
  absolute_radius_curves_verified: absoluteCurves, content_source_pairs: 15,
  ground_projection: { layers: groundProjectedLayers, corrected_height_above_ground: 2, previous_order_negative_control: -18 },
  native_depth_bias_preserved: { renderers: nativeDepthRenderers, void: -10, twirl: -20 },
  compiled_native_schema_round_trip: true, original_native_resources_preserved: true,
  runtime_visual_check: 'root agent owns live visual verification', checks };
fs.writeFileSync(path.join(base, 'report.json'), JSON.stringify(report, null, 2) + '\n');
console.log('RICH_PORTAL_VERIFY_PASS nodes=15 GlobalScale=14 multiplier=3 curves=2 source_content_compiled=15');
