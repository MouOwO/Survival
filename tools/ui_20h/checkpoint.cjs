'use strict';
const fs=require('fs'),path=require('path'),crypto=require('crypto'),cp=require('child_process'),assert=require('assert');
const base='design_refs/ui_20h/work/checkpoints',objects=base+'/objects';
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
function keep(file,bytes){const sha=hash(bytes),obj=objects+'/'+sha+'.bin';fs.mkdirSync(objects,{recursive:true});if(!fs.existsSync(obj))fs.writeFileSync(obj,bytes);return {path:file,sha256:sha,object:'objects/'+sha+'.bin',bytes:bytes.length};}
const dependencies=JSON.parse(fs.readFileSync('design_refs/ui_20h/work/dependencies.json','utf8').replace(/^\uFEFF/,''));
const codeFiles=dependencies.flatMap(p=>['panorama/src/'+p,'panorama/'+p.replace(/\.js$/,'.vjs_c').replace(/\.css$/,'.vcss_c').replace(/\.xml$/,'.vxml_c')]);
const action=process.argv[2]||'verify',version=process.argv[3]||'best';
if(action==='snapshot'){
 const files=codeFiles.map(p=>keep(p,fs.readFileSync(p)));
 const extra=JSON.parse(fs.readFileSync('design_refs/ui_20h/Delivery/resources.json','utf8'));
 for(const r of extra.images)for(const p of [r.source,r.compiled].filter(Boolean))if(!files.some(x=>x.path===p))files.push(keep(p,fs.readFileSync(p)));
 for(const r of JSON.parse(fs.readFileSync('design_refs/ui_20h/Delivery/recovered_sources.json','utf8')).records)for(const p of [r.source,r.runtime])if(!files.some(x=>x.path===p))files.push(keep(p,fs.readFileSync(p)));
 const titles='design_refs/ui_20h/work/feedback10/title_sources.json';if(fs.existsSync(titles))for(const r of JSON.parse(fs.readFileSync(titles)))for(const p of [r.source,r.compiled].filter(Boolean))if(!files.some(x=>x.path===p))files.push(keep(p,fs.readFileSync(p)));
 const manifest={at:new Date().toISOString(),baselineCommit:cp.execFileSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).trim(),scope:'Final selected source, compiled reference closure and reused assets; no temporary probes',files};
 fs.mkdirSync(base+'/best',{recursive:true});fs.writeFileSync(base+'/best/manifest.json',JSON.stringify(manifest,null,2));
 const prior=[];for(const p of codeFiles){let bytes;const saved=base+'/baseline/'+p;if(fs.existsSync(saved))bytes=fs.readFileSync(saved);else try{bytes=cp.execFileSync('git',['show','HEAD:'+p],{stdio:['ignore','pipe','ignore'],maxBuffer:32*1024*1024});}catch{continue;}prior.push(keep(p,bytes));}
 fs.mkdirSync(base+'/baseline_full',{recursive:true});fs.writeFileSync(base+'/baseline_full/manifest.json',JSON.stringify({...manifest,scope:'Initial committed UI; original seven raw source backups take priority',files:prior},null,2));
 for(const area of ['queue','hud','archive','shared']){fs.mkdirSync(base+'/'+area,{recursive:true});fs.writeFileSync(base+'/'+area+'/manifest.json',JSON.stringify({at:manifest.at,scope:'Final group freeze, shared files are restored as one consistent version; not a historical capture-time snapshot',restore:'best',recipes:'../../experiments.json',best:'../../../BEST_VERSION.json',files:files.filter(f=>f.path.startsWith('panorama/src/'))},null,2));}
 console.log('UI20H_CHECKPOINT_SAVED',files.length,'files,',prior.length,'baseline files');
}else{
 const manifest=JSON.parse(fs.readFileSync(base+'/'+version+'/manifest.json','utf8'));
 for(const f of manifest.files){assert.equal(hash(fs.readFileSync(base+'/'+f.object)),f.sha256,'Checkpoint object '+f.path);if(version==='best')assert.equal(hash(fs.readFileSync(f.path)),f.sha256,'Working file '+f.path);}
 console.log('UI20H_CHECKPOINT_VERIFIED',version,manifest.files.length);
}
