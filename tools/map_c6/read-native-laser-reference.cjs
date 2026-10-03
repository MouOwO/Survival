'use strict';
const fs = require('fs'), path = require('path'), cp = require('child_process'), crypto = require('crypto');
const {Vpk} = require('./lib.cjs');
const root = path.resolve(__dirname, '../..');
const native = new Vpk(path.resolve(root, '../../dota/pak01_dir.vpk'));
// Parse resourceinfo's textual DATA without executing it; preserve float and resource types.
function parse(text) {
  const tokens = text.match(/resource:"(?:[^"\\]|\\.)*"|"(?:[^"\\]|\\.)*"|[{}\[\]=,]|[^\s{}\[\]=,]+/g);
  let at = 0;
  function value() {
    const token = tokens[at++];
    if (token === '{') {
      const obj = {};
      while (tokens[at] !== '}') {
        const key = tokens[at++];
        if (tokens[at++] !== '=') throw Error('Invalid DATA assignment');
        obj[key] = value();
      }
      at++; return obj;
    }
    if (token === '[') {
      const out = [];
      while (tokens[at] !== ']') { if (tokens[at] === ',') at++; else out.push(value()); }
      at++; return out;
    }
    if (token.startsWith('resource:')) return {resource:JSON.parse(token.slice(9))};
    if (token.startsWith('"')) return JSON.parse(token);
    if (token === 'true' || token === 'false' || token === 'null') return JSON.parse(token);
    const n = Number(token);
    if (!Number.isFinite(n)) throw Error('Unsupported DATA token ' + token);
    return /[.eE]/.test(token) ? {float:n} : n;
  }
  const result = value();
  if (at !== tokens.length) throw Error('Trailing DATA tokens');
  return result;
}
const output = path.join(root, 'art/effects/laser/reference/io');
const temp = path.join(root, 'output/io_laser_native');
fs.mkdirSync(output, {recursive:true}); fs.mkdirSync(temp, {recursive:true});
const records = [];
for (const name of ['hero_wisp/wisp_tether', 'hero_wisp/wisp_tether_c', 'hero_zuus/zuus_static_field_b']) {
  const resource = 'particles/units/heroes/' + name + '.vpcf_c';
  const bytes = native.read(resource), file = path.join(temp, path.basename(resource));
  fs.writeFileSync(file, bytes);
  const result = cp.spawnSync(path.resolve(root, '../../bin/win64/resourceinfo.exe'), ['-i',file,'-all'], {encoding:'utf8',windowsHide:true});
  if (result.status !== 0) throw Error(result.stderr);
  const marker = result.stdout.match(/--- vpcf block DATA[^\n]*\n/);
  if (!marker) throw Error('Missing DATA');
  const data = result.stdout.slice(marker.index + marker[0].length).trim();
  const stem = path.basename(name);
  fs.writeFileSync(path.join(output, stem + '.txt'), data + '\n');
  fs.writeFileSync(path.join(output, stem + '.json'), JSON.stringify(parse(data), null, 2) + '\n');
  records.push({resource, sha256:crypto.createHash('sha256').update(bytes).digest('hex'), data:stem+'.txt', parsed:stem+'.json'});
}
fs.writeFileSync(path.join(output, 'manifest.json'), JSON.stringify({source:'Dota native pak01_dir.vpk',records}, null, 2)+'\n');
console.log('IO_NATIVE_REFERENCE_PASS ' + records.length);
