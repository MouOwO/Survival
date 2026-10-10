'use strict';
const fs=require('fs'),path=require('path'),cp=require('child_process'),crypto=require('crypto'),vm=require('vm'),assert=require('assert');
const base='design_refs/ui_20h',content=path.resolve('../../../content/dota_addons/Survival'),read=p=>fs.readFileSync(p,'utf8').replace(/^\uFEFF/,'').replaceAll('\r\n','\n'),sha=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const git=(where,args)=>cp.execFileSync('git',['-C',where,'-c','safe.directory='+where.replaceAll('\\','/'),...args],{encoding:'utf8',maxBuffer:32*1024*1024});
const upstream=file=>git(content,['show','HEAD:panorama/'+file]).replaceAll('\r\n','\n');
const report={at:new Date().toISOString(),checks:[],limitations:[]};
for(const rel of ['geometry_remaining_5d5c1152eb.js','topnav_remaining_5d5c1152eb.js','common/ui_components.js'])assert.equal(read('panorama/src/scripts/custom_game/'+rel),git(process.cwd(),['show','HEAD:panorama/src/scripts/custom_game/'+rel]).replaceAll('\r\n','\n'),rel);
assert.equal(git(process.cwd(),['diff','--name-only','HEAD','--','scripts/vscripts','maps','data']).trim(),'');
report.checks.push('Bottom HUD geometry/controller/common lifecycle and Lua/map/CSV unchanged');
for(const name of ['archive.xml','survival_hud.xml']){
 const source='panorama/src/layout/custom_game/'+name,stripped=read(source).replace(/<include src="file:\/\/\{resources\}\/(?:styles\/custom_game\/common\/jade_ui.css|scripts\/custom_game\/common\/jade_components.js|scripts\/custom_game\/archive_jade.js)"\s*\/>/g,'');
 assert.equal(stripped,upstream('layout/custom_game/'+name),'Merged content entry retained '+name);
}
assert.equal(read('panorama/src/scripts/custom_game/world_health_bar_anchor.js'),upstream('scripts/custom_game/world_health_bar_anchor.js'));
report.checks.push('Merged title/VIP XML entries and health projection sentinel fix preserved');
const allowed=new Set(['panorama/layout/custom_game/archive.xml','panorama/layout/custom_game/survival_hud.xml','panorama/scripts/custom_game/daily_remaining_5d5c1152eb.js','panorama/scripts/custom_game/lottery_ui_remaining_5d5c1152eb.js','panorama/scripts/custom_game/production_progress.js','panorama/styles/custom_game/production_progress.css']);
for(const name of git(content,['diff','--name-only','-z']).split('\0').filter(Boolean)){const current=read(path.join(content,name)),head=git(content,['show','HEAD:'+name]).replaceAll('\r\n','\n');if(current!==head)assert(allowed.has(name),'Unrelated content change '+name);}
const deps=JSON.parse(read(base+'/work/dependencies.json'));
for(const rel of deps){const source='panorama/src/'+rel,runtime='panorama/'+rel.replace(/\.js$/,'.vjs_c').replace(/\.css$/,'.vcss_c').replace(/\.xml$/,'.vxml_c');assert(fs.existsSync(runtime),runtime);assert.equal(read(source),read(path.join(content,'panorama',rel)),'Source mismatch '+rel);if(rel.endsWith('.js'))new vm.Script(read(source),{filename:source});}
report.checks.push(deps.length+' source/compiled dependencies present, content synchronized (line endings normalized), JS syntax valid');
assert.equal(sha('panorama/scripts/custom_game/topnav_remaining_5d5c1152eb.vjs_c'),sha('output/ui_20h/native_probe/runtime.vjs_c'));
assert(!read(path.join(content,'panorama/scripts/custom_game/topnav_remaining_5d5c1152eb.js')).includes('[UI20_PROBE]'));
report.checks.push('Temporary Tools observer restored byte-for-byte in runtime and removed from content source');
const resources=JSON.parse(read(base+'/Delivery/resources.json'));for(const r of resources.images){assert.equal(sha(r.source),r.sha256,'Resource source '+r.source);assert.equal(sha(r.compiled),r.compiledSha256,'Compiled resource '+r.compiled);}
for(const r of JSON.parse(read(base+'/Delivery/recovered_sources.json')).records){assert.equal(sha(r.source),r.sha256);assert(fs.existsSync(r.runtime));if(r.source.endsWith('.png'))assert.equal(r.sha256,r.originalSha256);}
const titles=JSON.parse(read(base+'/work/feedback10/title_sources.json'));for(const r of titles){assert.equal(sha(r.source),r.sha256);assert.equal(sha(r.original),r.sha256);if(r.compiled)assert(fs.existsSync(r.compiled));}
report.checks.push('Reusable material/icon pixels and recovered sources unchanged; '+titles.length+' original title sources retained');
const review=JSON.parse(read(base+'/work/feedback10/review.json'));assert.equal(review.records.length,10);assert.equal(new Set(review.records.map(x=>x.id)).size,10);assert.equal(review.kept.length,7);
for(const r of review.records){assert(['keep','reject'].includes(r.decision));assert(r.variables.length>=1&&r.variables.length<=3);for(const file of [r.source,r.default])assert(fs.existsSync(base+'/work/feedback10/'+file));}
const best=JSON.parse(read(base+'/BEST_VERSION.json'));assert.deepEqual(best.selected,review.kept);assert(best.validation.native.status.startsWith('PARTIAL'));
report.checks.push('10 distinct candidate purposes, 7 selections, decisions/costs/checkpoints recorded; latest not automatically selected');
const qa=JSON.parse(read(base+'/work/qa/report.json')),actions=JSON.parse(read(base+'/work/qa/actions.json')),categories=JSON.parse(read(base+'/work/feedback10/categories/report.json'));
assert.equal(qa.cases.length,40);assert.equal(actions.cases.length,16);assert.equal(categories.records.length,15);
report.checks.push('40 viewport/state cases, 16 layout and event cases, 15 archive categories and original title equip event');
const manifest=JSON.parse(read(base+'/work/checkpoints/best/manifest.json'));for(const f of manifest.files){assert.equal(sha(base+'/work/checkpoints/'+f.object),f.sha256);assert.equal(sha(f.path),f.sha256);}
for(const f of JSON.parse(read(base+'/work/feedback10/final/source_manifest.json')))assert.equal(sha(f.path),f.sha256);
const gallery=base+'/Delivery/index.html';for(const match of read(gallery).matchAll(/(?:src|href)="([^"]+)"/g)){const link=match[1];if(link.startsWith('#')||link.includes('://'))continue;assert(fs.existsSync(path.resolve(path.dirname(gallery),link.split('#')[0])),'Gallery link '+link);}
report.checks.push(manifest.files.length+' exact recovery files, final source/compiled hashes and all gallery links verified');
report.limitations=['Native 1280x720 archive captured with 44 real server rows before final compatibility changes','Dota client required update; local reload had zero players, final line-height/host/title/HUD and R08 training checks remain native-unverified','Higher resolutions and category fixtures are component previews, ScenePanel/engine nodes remain stand-ins','Worker per-item cancellation has no existing API; original research refund logic unchanged','No real checkout, lottery draw or reward claim'];
report.status='PASS_WITH_NATIVE_LIMITATIONS';fs.writeFileSync(base+'/Delivery/audit.json',JSON.stringify(report,null,2));console.log('FEEDBACK10_AUDIT_PASS '+report.checks.length+' groups; '+manifest.files.length+' recovery files; native limitations explicit');
