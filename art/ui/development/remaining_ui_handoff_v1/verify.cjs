const fs=require('fs'),p=require('path'),crypto=require('crypto'),cp=require('child_process');
const here=__dirname,repo=p.resolve(here,'../../../..'),hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const build=JSON.parse(fs.readFileSync(p.join(here,'build.json'))),assets=JSON.parse(fs.readFileSync(p.join(here,'asset_audit.json')));
if(build.inputs.some(x=>x.includes('remaining_probe')))throw Error('Delivery must not include automatic probes');
for(const a of assets)if(hash(fs.readFileSync(p.join(here,'candidate/panorama',a.runtime)))!==a.sha256)throw Error('Asset differs from mapped pack: '+a.original_path);
const log=[];
for(const test of ['test_lottery.cjs','test_daily.cjs','test_rogue.cjs','test_commerce.cjs','test_archive_icons.cjs']){
 const r=cp.spawnSync(process.execPath,[p.join(here,test)],{cwd:repo,encoding:'utf8'});log.push(test+'\n'+r.stdout+r.stderr);if(r.status!==0)throw Error(log.at(-1));
}
const manifest={version:build.version,created:new Date().toISOString(),mappedAssetCount:assets.filter(a=>!a.kind).length,generatedIconCount:assets.filter(a=>a.kind==='generated_archive_icon').length,packAssetsByteIdenticalToHandoff:true,automaticProbes:false,inputs:build.inputs.map(f=>({file:f,sha256:hash(fs.readFileSync(p.join(here,'candidate/panorama',f)))})),note:'Archive icon originals are generated art, validated against project CSV. Behavior tests use mocks; actual game evidence is listed separately. No live payment validated.'};
fs.writeFileSync(p.join(here,'validation.txt'),log.join('\n'));
fs.writeFileSync(p.join(here,'delivery_manifest.json'),JSON.stringify(manifest,null,2));
console.log('PASS: five behavior suites, '+manifest.mappedAssetCount+' pack assets, '+manifest.generatedIconCount+' generated icons, no automatic probes; version '+build.version);
