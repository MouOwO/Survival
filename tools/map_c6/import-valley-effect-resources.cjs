'use strict';
// Import the selected reference VPCFs and their complete non-Valve dependency
// closure. Never loads Workshop Lua, never replaces a differing local resource.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { references, packs } = require('./inspect-effect-resources.cjs');
const root = path.resolve(__dirname, '../..');
const selected = [
  'particles/units/towers/aura_dark.vpcf',
  'particles/units/towers/aura_durable.vpcf',
  'particles/units/towers/aura_evil.vpcf',
  'particles/units/towers/qualification_build_t04_base.vpcf',
];
const seen = new Set(), records = [], native = new Set();
function visit(resource) {
  const key = resource.endsWith('_c') ? resource : resource + '_c';
  if (seen.has(key)) return;
  seen.add(key);
  if (!packs.reference.entries.has(key)) {
    if (!packs.valve.entries.has(key)) throw Error('Missing dependency ' + key);
    native.add(key);
    return;
  }
  const bytes = packs.reference.read(key);
  if (packs.valve.entries.has(key) && packs.valve.read(key).equals(bytes)) {
    native.add(key);
    return;
  }
  const dest = path.resolve(root, key);
  if (!dest.startsWith(root + path.sep)) throw Error('Invalid resource path: ' + key);
  if (fs.existsSync(dest) && !fs.readFileSync(dest).equals(bytes)) {
    throw Error('Refusing differing local resource: ' + key);
  }
  const deps = references(bytes);
  // Validate all dependency paths before making any writes.
  for (const dep of deps) visit(dep);
  records.push({ resource: key, bytes: bytes.length,
    sha256: crypto.createHash('sha256').update(bytes).digest('hex'), dependencies: deps });
}
for (const resource of selected) visit(resource);
for (const record of records) {
  const dest = path.join(root, record.resource);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest, packs.reference.read(record.resource));
}
const out = path.join(root, 'art/effects/valley_reference');
fs.mkdirSync(out, { recursive: true });
const manifest = {
  workshop_id: '3164617180',
  reference_pack: packs.reference.filename,
  validation: 'STATIC: RERL dependency closure and exact SHA256 import; no runtime binding inferred from encrypted Lua.',
  selected, records, native_dependencies: [...native].sort(),
};
fs.writeFileSync(path.join(out, 'import_manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log(JSON.stringify({ imported: records.length,
  bytes: records.reduce((n, r) => n + r.bytes, 0), native_dependencies: native.size }));
