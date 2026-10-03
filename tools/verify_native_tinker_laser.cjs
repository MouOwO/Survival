'use strict';
// Production uses untouched Valve particles; the old yellow clones are unused.
const fs=require('fs'),path=require('path'),cp=require('child_process'),assert=require('assert'),crypto=require('crypto');
const {Vpk}=require('./map_c6/lib.cjs'); const root=path.resolve(__dirname,'..');
const native=new Vpk(path.resolve(root,'../../dota/pak01_dir.vpk')),core=new Vpk(path.resolve(root,'../../core/pak01_dir.vpk'));
const roots={R:'particles/units/heroes/hero_tinker/tinker_laser.vpcf',SR:'particles/econ/items/tinker/tinker_ti10_immortal_laser/tinker_ti10_immortal_laser.vpcf',SSR:'particles/econ/items/tinker/tinker_ti10_immortal_laser/tinker_ti10_immortal_laser_aghs.vpcf'};
const rows=fs.readFileSync(path.join(root,'data/csv/建筑与工人系统/防御塔/tower_laser_effects.csv'),'utf8').split(/\r?\n/).filter(x=>x.startsWith('laser_lv')).map(x=>x.split(','));
assert.equal(rows.length,20);
for(const r of rows){const tier=r[0].split(':')[1];assert.equal(r[3],roots[tier==='default'?'R':tier]);assert.equal(r[4],'native');assert.equal(+r[7],0.3,'unmodified short pulses need replay');assert.equal(+r[8],0.72,'bounded overlap');assert.equal(r[20],'');assert.equal(+r[21],1);assert.equal(+r[22],0);}
const temp=path.join(root,'output/tinker_native_restore');fs.mkdirSync(temp,{recursive:true});
const seen=new Set(),records=[],texts=new Map();
function inspect(resource){
 if(seen.has(resource))return;seen.add(resource);
 const key=resource+'_c',pack=native.entries.has(key)?native:core;
 assert(pack.entries.has(key),'Missing native dependency: '+resource);
 const bytes=pack.read(key),local=path.join(root,key);
 if(fs.existsSync(local))assert(fs.readFileSync(local).equals(bytes),'Addon override changes original art: '+resource);
 if(!/\.(vpcf|vmat)$/.test(resource))return;
 const file=path.join(temp,path.basename(key));fs.writeFileSync(file,bytes);
 let s=cp.execFileSync(path.resolve(root,'../../bin/win64/resourceinfo.exe'),['-i',file,'-all'],{encoding:'utf8',windowsHide:true});s=s.slice(s.indexOf(' block DATA'));texts.set(resource,s);
 records.push({resource,sha256:crypto.createHash('sha256').update(bytes).digest('hex')});
 for(const m of s.matchAll(/resource:"([^"]+)"/g))if(m[1])inspect(m[1]);
}
Object.values(roots).forEach(inspect);
for(const resource of Object.values(roots)){const s=texts.get(resource);assert(s.includes('m_flLiteralValue = 0.7'),'original beam lifetime');assert(!s.includes('survival/tinker_growth'));}
assert(texts.get(roots.R).includes('m_ConstantColor = [ 7, 50, 211, 255 ]'));
assert(texts.get(roots.SR).includes('m_LiteralColor = [ 255, 41, 41, 255 ]'));
const report={status:'PASS',source:'installed Dota pak01_dir.vpk',rows:20,roots,unchanged_native_art:true,dependency_files:seen.size,native_width:true,visual_replay_seconds:0.3,visual_segment_lifetime_seconds:0.72,colors:['R native blue','SR original TI10 Immortal','SSR original red Immortal Aghanim variant'],excluded_color_candidate:{item:'Blackshield Protodrone Laser',itemdef:'14064',reason:'Blue mecha_hornet particle is particle_create weapon ambient, not a Q skill beam.'},in_game_visual_verified:false,records};
fs.writeFileSync(path.join(root,'docs/ai/validation/20261002/tinker_native_restore.json'),JSON.stringify(report,null,2)+'\n');
console.log('NATIVE_TINKER_RESTORE_PASS rows='+rows.length+' dependencies='+seen.size+' custom_art=0');
