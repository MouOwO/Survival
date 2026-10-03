'use strict';
const fs=require('fs'),path=require('path'),cp=require('child_process'),assert=require('assert');
const {Vpk}=require('./map_c6/lib.cjs');const root=path.resolve(__dirname,'..');
const native=new Vpk(path.resolve(root,'../../dota/pak01_dir.vpk')),core=new Vpk(path.resolve(root,'../../core/pak01_dir.vpk'));
const manifest=JSON.parse(fs.readFileSync(path.join(root,'art/effects/tower_trial/manifest.json'),'utf8'));
manifest.outputs.push(...JSON.parse(fs.readFileSync(path.join(root,'art/effects/techies_missiles/manifest.json'),'utf8')).outputs);
const seen=new Map(),texts=new Map(),temp=path.join(root,'output/tower_trial/audit');fs.mkdirSync(temp,{recursive:true});
function inspect(resource){
 if(seen.has(resource))return; const file=path.join(root,resource+'_c'),pack=native.entries.has(resource+'_c')?native:core;
 assert(fs.existsSync(file)||pack.entries.has(resource+'_c'),'Missing dependency '+resource);
 const record={resource,source:fs.existsSync(file)?'survival':'native'};seen.set(resource,record);
 if(!resource.endsWith('.vpcf'))return;
 const target=path.join(temp,String(seen.size)+'.vpcf_c');fs.writeFileSync(target,fs.existsSync(file)?fs.readFileSync(file):pack.read(resource+'_c'));
 let s=cp.execFileSync(path.resolve(root,'../../bin/win64/resourceinfo.exe'),['-i',target,'-all'],{encoding:'utf8',windowsHide:true});s=s.slice(s.indexOf(' block DATA'));texts.set(resource,s);
 record.dependencies=[...new Set([...s.matchAll(/resource:"([^"]+)"/g)].map(m=>m[1]).filter(Boolean))];record.dependencies.forEach(inspect);
}
for(const row of manifest.outputs)inspect(row.resource);
// Validate every preset too, not just the currently active attack list.
for(const preset of ['A','B','C']){
 const f=path.join(root,'data/tower_visual_presets',preset+'.json');
 if(fs.existsSync(f))for(const row of JSON.parse(fs.readFileSync(f,'utf8')).stages){inspect(row.body_model);inspect(row.projectile);}
}

const contract=JSON.parse(fs.readFileSync(path.join(root,'output/tower_trial/config_contract.json'),'utf8'));
for(const route of contract.routes)for(const resource of route.projectiles)inspect(resource);
inspect('particles/units/heroes/hero_clinkz/clinkz_searing_arrow_linear_proj.vpcf');
inspect('particles/econ/items/techies/techies_arcana/techies_bigshot_fuse.vpcf');
for(const row of manifest.outputs){
 const s=texts.get(row.resource);assert(s&&s.includes('CParticleSystemDefinition'));
 assert(!s.includes('m_bDisableZBuffering = true'),'custom particle must respect depth');
 assert(!s.includes('C_OP_StopAfterCPDuration'),'no unbound duration CP may stop the trial effect');
 if(row.role==='persistent_ground'){
  assert(s.includes('C_OP_PositionLock')||s.includes('C_OP_SetToCP'),'ground must follow relocation without Lua updates');
  assert(/_class = "C_OP_SetFloat"\s+m_nOutputField = 7/.test(s),'ground alpha must recover after late control points');
 }

 if(row.role==='tracking_projectile'){
  assert(s.includes('C_OP_AttractToControlPoint')&&/m_TransformInput =\s*\{\s*m_nControlPoint = 1\b/.test(s));
  assert(!s.includes('C_INIT_VelocityFromCP')&&!s.includes('C_OP_CPOffsetToPercentageBetweenCPs'));
 }
}
const report={status:'PASS',compiled_outputs:manifest.outputs.length,dependencies:seen.size,resources:[...seen.values()],in_game_visual_verified:false};
fs.writeFileSync(path.join(root,'output/tower_trial/resource_contract.json'),JSON.stringify(report,null,2)+'\n');
console.log('TOWER_TRIAL_RESOURCE_PASS compiled='+manifest.outputs.length+' dependency_files='+seen.size+'; ground follow, tracking CPs and no depth bypass');
