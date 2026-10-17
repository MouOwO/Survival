// Promote the native texture settings only after the one-picture live comparison.
const fs = require('fs');
const crypto = require('crypto');
const assert = require('assert/strict');
const path = require('path');
const root = path.resolve(__dirname, '../..');
const target = path.join(root, 'data/ui/item_resources.json');
const evidence = path.join(root, 'design_refs/collection_clarity_20261017');
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const bytes = fs.readFileSync(target);
const current = JSON.parse(bytes);
const audit = JSON.parse(fs.readFileSync(path.join(evidence, 'grid_v2_post_compile.json'), 'utf8'));
assert.equal(audit.status, 'PASS_NATIVE_PIXELS_AUDITED');
assert.equal(audit.count, 160);
const records = new Map(audit.outputs.map(row => [row.id, row]));
const before = structuredClone(current);
let count = 0;
for (const row of current.items) {
  if (!/^(ex|friend|wife|beast)_(0[1-9]|[1-3][0-9]|40)$/.test(row.id)) continue;
  const texture = records.get(row.id);
  assert(texture && texture.width === 128 && texture.height === 128);
  assert(texture.mips === 1 && texture.flags === 8 && texture.all_rgba_pixels_equal_to_png === true);
  const runtime = path.join(root, texture.runtime_uri.replace('s2r://', '') + '_c');
  assert.equal(hash(fs.readFileSync(runtime)), texture.compiled_sha256);
  row.uri = texture.runtime_uri;
  row.source_size = [128, 128];
  count++;
}
assert.equal(count, 160);
const changed = [];
for (let i = 0; i < before.items.length; i++) {
  const a = before.items[i], b = current.items[i];
  assert.equal(a.id, b.id);
  if (JSON.stringify(a) === JSON.stringify(b)) continue;
  assert(records.has(a.id), 'Unrelated item changed: ' + a.id);
  const allowed = structuredClone(a);
  allowed.uri = b.uri;
  allowed.source_size = b.source_size;
  assert.deepEqual(allowed, b);
  changed.push({id: a.id, before_uri: a.uri, after_uri: b.uri});
}
assert.equal(changed.length, 160);
fs.mkdirSync(path.join(evidence, 'final'), {recursive: true});
fs.writeFileSync(path.join(evidence, 'final/item_resources_before.json'), bytes);
assert.equal(hash(fs.readFileSync(target)), hash(bytes), 'Resource table changed during promotion.');
const output = JSON.stringify(current, null, 2) + '\n';
fs.writeFileSync(target, output);
fs.writeFileSync(path.join(evidence, 'final/resource_changes.json'), JSON.stringify({
  status: 'PASS', count, before_sha256: hash(bytes), after_sha256: hash(output),
  unchanged_other_rows: current.items.length - count,
  changed_fields_only: ['uri', 'source_size'], items: changed
}, null, 2) + '\n');
console.log('COLLECTION_GRID_V2_PROMOTION_PASS: 160 texture references; other 1310 rows preserved.');
