'use strict';
// Native rocket art, adapted only from an elevated flare path to attack tracking.
const fs = require('fs'), path = require('path'), cp = require('child_process'), assert = require('assert');
const {Vpk, endOf} = require('./lib.cjs');
const root = path.resolve(__dirname, '../..');
const pack = new Vpk(path.resolve(root, '../../dota/pak01_dir.vpk'));
const out = path.join(root, 'art/effects/techies_missiles');
const temp = path.join(root, 'output/techies_anti_air');
fs.mkdirSync(temp, {recursive:true});
const header = '<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->\n';
const sources = [
 ['r', 'particles/units/heroes/hero_rattletrap/rattletrap_rocket_flare.vpcf'],
 ['sr', 'particles/econ/items/clockwerk/clockwerk_2022_cc/clockwerk_2022_cc_rocket_flare.vpcf'],
 ['ssr', 'particles/econ/items/clockwerk/clockwerk_paraflare/clockwerk_para_rocket_flare.vpcf'],
];
const outputs = [];
for (const [tier, source] of sources) {
 const target = path.join(temp, path.basename(source)+'_c');
 fs.writeFileSync(target, pack.read(source+'_c'));
 let s = cp.execFileSync(path.resolve(root, '../../bin/win64/resourceinfo.exe'), ['-i', target, '-all'], {encoding:'utf8', windowsHide:true});
 s = s.slice(s.indexOf(' block DATA')); s = s.slice(s.indexOf('{'));
 const offset = s.indexOf('_class = "C_OP_CPOffsetToPercentageBetweenCPs"');
 assert(offset >= 0, 'Native flare controller changed: '+source);
 const start = s.lastIndexOf('{', offset), end = endOf(s, start);
 s = s.slice(0, start)+s.slice(end).replace(/^\s*,/, '');
 assert(s.includes('m_nControlPointNumber = 4'));
 s = s.replace('m_nControlPointNumber = 4', 'm_nControlPointNumber = 1');
 s = s.replace('m_flDelay = 0.1', 'm_flDelay = 0.0');
 // No illumination field/parachute or huge skill AoE on an ordinary attack.
 s = s.replace(/resource:"[^"]*rocket_flare_explosion\.vpcf"/g,
  'resource:"particles/units/heroes/hero_gyrocopter/gyro_base_attack_explosion.vpcf"');
 s = s.replace(/m_bDisableZBuffering = true/g, 'm_bDisableZBuffering = false');
 assert(!s.includes('2000.0') && !s.includes('C_OP_CPOffsetToPercentageBetweenCPs'));
 const resource = 'particles/survival/towers/techies/techies_'+tier+'_missile.vpcf';
 const file = path.join(out, 'source', resource); fs.mkdirSync(path.dirname(file), {recursive:true});
 fs.writeFileSync(file, header+s.split(/\r?\n/).map(l=>l.trimEnd()).join('\n').trim()+'\n');
 outputs.push({resource, native:source, tier, role:'tracking_projectile'});
}
fs.writeFileSync(path.join(out, 'manifest.json'), JSON.stringify({
 control_points:'CP0 launch; CP1 moving target; CP2 existing attack speed; CP3 native flight children. No Lua particle update timer.', outputs
}, null, 2)+'\n');
console.log('TECHIES_MISSILE_SOURCE_PASS variants='+outputs.length);
