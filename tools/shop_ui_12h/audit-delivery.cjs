'use strict';
const fs=require('fs'),path=require('path'),crypto=require('crypto'),assert=require('assert/strict');
const root='design_refs/shop_ui_12h',read=f=>fs.readFileSync(f,'utf8').replace(/^\uFEFF/,'').replaceAll('\r\n','\n'),hash=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const baseline=JSON.parse(read(root+'/work/checkpoints/baseline/manifest.json'));
const report={at:new Date().toISOString(),unchangedFiles:[],unchangedBusiness:[],compiled:[],originalArt:[],hud:'',temporaryProbes:''};
for(const file of ['panorama/src/styles/custom_game/remaining_5d5c1152eb.css','panorama/src/scripts/custom_game/common/ui_components.js']){assert.equal(hash(file),baseline.files[file]);report.unchangedFiles.push(file);}
const hud=read('panorama/src/layout/custom_game/survival_hud.xml').replace(/<include src="file:\/\/\{resources\}\/(styles\/custom_game\/common\/commerce_jade.css|scripts\/custom_game\/common\/commerce_(art_manifest|components).js)"\/>/g,'');
assert.equal(hud,read(root+'/work/checkpoints/baseline/survival_hud.xml'));report.hud='PASS: only three stylesheet/script includes; all existing HUD markup preserved';
const current=read('panorama/src/scripts/custom_game/commerce_remaining_5d5c1152eb.js'),old=read(root+'/work/checkpoints/baseline/commerce_remaining_5d5c1152eb.js');
function named(text,name){const start=text.indexOf('function '+name+'('),next=text.indexOf('\n    function ',start+1),config=text.indexOf('\n    cfg.SurvivalCommerceView=',start+1);assert(start>=0,name);return text.slice(start,Math.min(...[next,config].filter(x=>x>=0))).trim();}
for(const name of ['checkout','purchaseLabel','noticeText','singleTicket','rewardText','update','mergeCatalogs','updatePaid']){assert.equal(named(current,name),named(old,name),name);report.unchangedBusiness.push(name);}
const api=(text,start,end)=>text.slice(text.indexOf(start),text.indexOf(end,text.indexOf(start))).trim();
assert.equal(api(current,'Open:function()','        Inspect:function()'),api(old,'Open:function()','        Inspect:function()'));report.unchangedBusiness.push('Open / Close / UpdateCatalog / UpdateWalletCatalog / IsOpen / SetNotice / OpenTicketPurchase');
const compiled=JSON.parse(read(root+'/work/compile_report.json'));
for(const f of compiled.files){assert.equal(hash('panorama/src/'+f.source),f.sha256.toLowerCase());const live='panorama/'+f.source.replace(/\.js$/,'.vjs_c').replace(/\.css$/,'.vcss_c').replace(/\.xml$/,'.vxml_c');assert.equal(hash(live),f.compiled_sha256.toLowerCase());report.compiled.push(live);}
const resources=JSON.parse(read(root+'/Delivery/resources.json'));
for(const item of resources.originalArtwork){assert.equal(hash(item.source),item.sha256);assert.equal(hash(item.shadow),item.shadowSha256);report.originalArt.push(item.source);}
for(const r of resources.materials){assert.equal(hash(r.master),r.sha256);assert(fs.existsSync(r.runtime),'Missing compiled material '+r.id);}
const images=read('panorama/src/layout/custom_game/commerce_resources.xml').match(/file:\/\/\{images\}\/[^" ]+/g);assert.equal(images.length,112);
for(const image of images){assert(fs.existsSync('panorama/images/'+image.replace('file://{images}/','').replace(/\.png$/,'_png.vtex_c')),image);}
assert(!fs.existsSync('panorama/images/custom_game/commerce_jade_v1/startup_probe_png.vtex_c'));
const probes=JSON.parse(read(root+'/work/probes_restored.json'));assert(probes.every(p=>p.restored));report.temporaryProbes='PASS: startup, mode and baseline probes restored; owned temporary texture removed';
report.materials=resources.materials.length;report.shadows=resources.originalArtwork.length;report.status='PASS';
const checkpoint=JSON.parse(read(root+'/work/checkpoints/production_best/manifest.json')),compiledCheckpoint=JSON.parse(read(root+'/work/checkpoints/production_best/compiled_manifest.json'));
for(const f of checkpoint.files.concat(compiledCheckpoint.files))assert.equal(hash(root+'/work/checkpoints/production_best/'+f.path),f.sha256);
for(const r of resources.materials)assert.equal(hash(root+'/work/checkpoints/production_best/'+r.master),r.sha256);
for(const r of resources.originalArtwork)assert.equal(hash(root+'/work/checkpoints/production_best/'+r.shadow),r.shadowSha256);
report.checkpoint='PASS: saved source, PNG and runtime hashes';
const gallery=root+'/Delivery/index.html',html=read(gallery);
for(const match of html.matchAll(/(?:href|src)="([^"]+)"/g)){
 if(match[1].startsWith('#')||match[1].includes('://'))continue;
 assert(fs.existsSync(path.resolve(path.dirname(gallery),match[1].split('#')[0])),'Missing gallery link '+match[1]);
}
report.galleryLinks='PASS: all local artifact links exist';
fs.writeFileSync(root+'/Delivery/integration_audit.json',JSON.stringify(report,null,2));console.log('INTEGRATION_AUDIT_PASS: baseline HUD/business preservation, 6 compiled sources, 112 textures, 75 original images, restored probes');
