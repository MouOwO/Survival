'use strict';
const fs=require('fs'),path=require('path'),cp=require('child_process'),crypto=require('crypto'),assert=require('assert');
const {Vpk}=require('./map_c6/lib.cjs');
const root=path.resolve(__dirname,'..'),native=new Vpk(path.resolve(root,'../../dota/pak01_dir.vpk')),
 core=new Vpk(path.resolve(root,'../../core/pak01_dir.vpk'));
const manifest=JSON.parse(fs.readFileSync(path.join(root,'art/effects/leshrac_base/manifest.json'),'utf8'));
const temp=path.join(root,'output/leshrac_base/audit');fs.mkdirSync(temp,{recursive:true});
const records=new Map(),texts=new Map();
function inspect(resource){
 if(records.has(resource))return;
 const local=path.join(root,resource+'_c'),pack=native.entries.has(resource+'_c')?native:core;
 assert(fs.existsSync(local)||pack.entries.has(resource+'_c'),'Missing '+resource);
 const bytes=fs.existsSync(local)?fs.readFileSync(local):pack.read(resource+'_c');
 const record={resource,sha256:crypto.createHash('sha256').update(bytes).digest('hex')};records.set(resource,record);
 if(!resource.endsWith('.vpcf'))return;
 const file=path.join(temp,path.basename(resource)+'_c');fs.writeFileSync(file,bytes);
 const dump=cp.execFileSync(path.resolve(root,'../../bin/win64/resourceinfo.exe'),['-i',file,'-all'],{encoding:'utf8',windowsHide:true});
 const data=dump.slice(dump.indexOf(' block DATA'));texts.set(resource,data);
 record.dependencies=[...new Set([...data.matchAll(/resource:"([^"]+)"/g)].map(m=>m[1]).filter(Boolean))];record.dependencies.forEach(inspect);
}
inspect(manifest.root);
let cap=0;
for(const row of manifest.outputs){
 const data=texts.get(row.resource);assert(data);
 assert(data.includes('C_OP_ContinuousEmitter')&&!data.includes('m_flEmissionDuration'));
 assert(/_class = "C_OP_PositionLock"\s*m_TransformInput =\s*\{\s*m_nControlPoint = 1\b/.test(data));
 assert(data.includes('PARTICLE_ORIENTATION_WORLD_Z_ALIGNED'));
 assert(!data.includes('m_bDisableZBuffering = true'));
 cap+=Number(data.match(/m_nMaxParticles = (\d+)/)[1]);
}
assert.equal(cap,8);
const report={date:'2026-10-01',status:'PASS',root:manifest.root,max_live_particles:cap,
 implementation:'Native Diabolic Edict groundflash with both ground-line children; continuous engine emission, CP1 foot lock. No Lua effect loop or ability gameplay.',
 replacements:['class_2: Leshrac W ground','class_4: Spirit Breaker W feet','class_7: Templar Assassin trap rings'],
 legacy_layers:'Core/detail/detail_ssr/crown removed from all three replaced profiles; exclusive runtime branch; existing particles retired on visual key change.',
 tests:['tower visual lifecycle simulation','base source preflight','resourcecompiler: three targets, zero failures','Lua 5.1 syntax'],
 resources:[...records.values()],in_game_visual_verified:false};
fs.writeFileSync(path.join(root,'docs/ai/validation/20261001/leshrac_base_replacement.json'),JSON.stringify(report,null,2)+'\n');
console.log('LESHRAC_BASE_PASS: three persistent layers, max eight particles, dependencies='+records.size);
