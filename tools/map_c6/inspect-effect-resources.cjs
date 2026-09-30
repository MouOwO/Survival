'use strict';
// Resource-only audit. Does not execute any code from Workshop packages.
const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const { Vpk } = require('./lib.cjs');
const root = path.resolve(__dirname, '../..');
const packs = {
  reference: new Vpk('D:/SteamLibrary/steamapps/workshop/content/570/3164617180/3164617180.vpk'),
  valve: new Vpk(path.resolve(root, '../../dota/pak01_dir.vpk')),
};
function references(bytes) {
  const result = [], h = 8 + bytes.readUInt32LE(8);
  for (let i = 0; i < bytes.readUInt32LE(12); i++) {
    const q = h + i * 12, s = q + 4 + bytes.readUInt32LE(q + 4);
    if (bytes.toString('ascii', q, q + 4) !== 'RERL') continue;
    const e = s + bytes.readUInt32LE(s);
    for (let j = 0; j < bytes.readUInt32LE(s + 4); j++) {
      const r = e + j * 16 + 8, t = r + Number(bytes.readBigInt64LE(r));
      result.push(bytes.toString('utf8', t, bytes.indexOf(0, t)));
    }
  }
  return result;
}
function audit(resources, out, dump = false) {
  const results = [];
  fs.mkdirSync(out, { recursive: true });
  for (const resource of resources) {
    const key = resource.endsWith('_c') ? resource : resource + '_c';
    const origins = Object.keys(packs).filter(p => packs[p].entries.has(key));
    if (!origins.length) throw Error('Missing resource ' + key);
    const origin = origins[0], bytes = packs[origin].read(key);
    const rec = { resource: key, origin, bytes: bytes.length,
      references: references(bytes), also_native: origins.includes('valve') };
    if (dump) {
      const dest = path.join(out, key);
      fs.mkdirSync(path.dirname(dest), { recursive: true });
      fs.writeFileSync(dest, bytes);
      const executable = path.resolve(root, '../../bin/win64/resourceinfo.exe');
      const result = cp.spawnSync(executable, ['-i', dest, '-all'], { encoding: 'utf8', windowsHide: true });
      if (result.status !== 0) throw Error(result.stderr || 'resourceinfo failed: ' + key);
      fs.writeFileSync(dest + '.txt', result.stdout);
      rec.dump = path.relative(root, dest + '.txt').replace(/\\/g, '/');
    }
    results.push(rec);
  }
  fs.writeFileSync(path.join(out, 'audit.json'), JSON.stringify(results, null, 2));
  return results;
}
if (require.main === module) {
  const resources = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  const out = path.resolve(root, process.argv[3] || 'output/effect_reference/audit');
  console.log(JSON.stringify(audit(resources, out, process.argv.includes('--dump')), null, 2));
}
module.exports = { references, audit, packs };
