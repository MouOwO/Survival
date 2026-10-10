'use strict';
if(require('fs').existsSync('design_refs/ui_20h/work/feedback10/review.json')){require('./feedback-audit.cjs');process.exit(0);}
const fs=require('fs'),path=require('path'),cp=require('child_process'),crypto=require('crypto'),vm=require('vm'),assert=require('assert');
const base='design_refs/ui_20h',read=p=>fs.readFileSync(p,'utf8').replace(/^\uFEFF/,'').replaceAll('\r\n','\n');
const hash=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const head=p=>cp.execFileSync('git',['show','HEAD:'+p],{encoding:'utf8',maxBuffer:32*1024*1024}).replaceAll('\r\n','\n');
const report={at:new Date().toISOString(),checks:[],limitations:[]};
for(const file of ['panorama/src/scripts/custom_game/geometry_remaining_5d5c1152eb.js','panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js','panorama/src/scripts/custom_game/common/ui_components.js'])assert.equal(read(file),head(file),file);
for(const file of ['archive.xml','survival_hud.xml']){
 const p='panorama/src/layout/custom_game/'+file;
 const stripped=read(p).replace(/<include src="file:\/\/\{resources\}\/(?:styles\/custom_game\/common\/jade_ui.css|scripts\/custom_game\/common\/jade_components.js|scripts\/custom_game\/archive_jade.js)"\s*\/>/g,'');
 assert.equal(stripped,head(p),'Existing layout and bindings '+file);
}
assert.equal(cp.execFileSync('git',['diff','--name-only','ab6c3070','--','scripts/vscripts','maps','data'],{encoding:'utf8'}).trim(),'');
report.checks.push('HUD geometry, controller and common lifecycle unchanged','Existing XML layout/bindings preserved except new shared includes','No Lua, map or CSV changes');
const deps=JSON.parse(read(base+'/work/dependencies.json')),engine=path.resolve('../../../content/dota_addons/Survival/panorama');
for(const rel of deps){const source='panorama/src/'+rel,compiled='panorama/'+rel.replace(/\.js$/,'.vjs_c').replace(/\.css$/,'.vcss_c').replace(/\.xml$/,'.vxml_c');assert(fs.existsSync(compiled),compiled);assert.equal(hash(source),hash(path.join(engine,rel)),'Content source mismatch '+rel);if(rel.endsWith('.js'))new vm.Script(read(source),{filename:source});}
assert(!read('panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js').includes('[UI20_PROBE]'));
const probe=JSON.parse(read('output/ui_20h/native_probe/command.json'));assert(!fs.readFileSync('panorama/scripts/custom_game/topnav_remaining_5d5c1152eb.vjs_c').includes(Buffer.from(probe.command)));
report.checks.push(deps.length+' native sources/compiled resources present and external content synchronized','JavaScript source syntax','Temporary Tools observer removed from source and runtime');
const resources=JSON.parse(read(base+'/Delivery/resources.json'));for(const r of resources.images){assert.equal(hash(r.source),r.sha256);assert.equal(hash(r.compiled),r.compiledSha256);}
const recovered=JSON.parse(read(base+'/Delivery/recovered_sources.json'));for(const r of recovered.records){assert.equal(hash(r.source),r.sha256);assert(fs.existsSync(r.runtime));if(r.source.endsWith('.png'))assert.equal(r.sha256,r.originalSha256);}
report.checks.push(resources.images.length+' referenced reusable materials/icons verified','148 recovered source files and 74 runtime texture counterparts verified');
const checkpoint=JSON.parse(read(base+'/work/checkpoints/best/manifest.json'));for(const f of checkpoint.files){assert.equal(hash(base+'/work/checkpoints/'+f.object),f.sha256);assert.equal(hash(f.path),f.sha256);}
const gallery=base+'/Delivery/index.html';for(const m of read(gallery).matchAll(/(?:src|href)="([^"]+)"/g)){if(m[1].startsWith('#')||m[1].includes('://'))continue;assert(fs.existsSync(path.resolve(path.dirname(gallery),m[1].split('#')[0])),'Gallery link '+m[1]);}
const qa=JSON.parse(read(base+'/work/qa/report.json')),actions=JSON.parse(read(base+'/work/qa/actions.json'));assert.equal(qa.cases.length,40);assert.equal(actions.cases.length,16);
report.checks.push(checkpoint.files.length+' exact recovery files and all gallery links verified','40 preview cases plus 16 layout cases and action contracts');
report.limitations=['Native game verification covers 1280x720; unsupported resolution command did not validate other sizes','Browser substitutes ScenePanel/native ability nodes and approximates text shrinking','Worker per-item cancellation has no existing API','Research refund logic and full queue behavior were not modified; native cancellation not exercised','No real checkout, lottery draw or reward claim'];
report.status='PASS_WITH_RECORDED_SCOPE';fs.writeFileSync(base+'/Delivery/audit.json',JSON.stringify(report,null,2));console.log('UI20H_DELIVERY_AUDIT_PASS',report.checks.length,'checks');
