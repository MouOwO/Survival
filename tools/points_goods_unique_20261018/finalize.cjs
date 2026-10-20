'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'../..'),base='design_refs/points_goods_unique_20261018',release='output/points_goods_unique_20261018/release';
process.chdir(root);
const read=name=>JSON.parse(fs.readFileSync(name,'utf8').replace(/^\uFEFF/,''));
const remote=name=>read(release+'/remote/'+name+'.json').records.at(-1);
const plan=read(release+'/plan.json'),browser=read(base+'/browser/report.json'),backend=read(base+'/release/candidate_backend_independent.json');
const before=read(base+'/server/inventory_preview_before.json'),after=read(base+'/server/inventory_preview.json');
const deployed=remote('verify'),activated=remote('activate'),backup=remote('backup'),local=read(release+'/local_install.json');
assert.equal(deployed.status,'DEPLOYMENT_VERIFIED');assert.equal(deployed.bundle,plan.bundle);assert.equal(after.archive_bundle,plan.bundle);assert.equal(local.bundle,plan.bundle);
assert.equal(deployed.payment_unchanged,true);assert.equal(activated.database.player_updates,0);assert.equal(activated.database.payment_updates,0);
assert.equal(browser.status,'PASS');assert(backend.ok&&backend.tests_run===49&&!backend.errors&&!backend.failures);
assert.equal(before.extra_copies,0);assert.equal(after.extra_copies,0);assert.equal(after.unique_item_count,97);
assert.equal(read('server/bundles/current.json').hash,plan.bundle);
const compiled=read(base+'/archive_compile.json');
const own=['scripts/custom_game/archive_v10.js','scripts/custom_game/archive_v10_semantics.js','styles/custom_game/archive_v10.css'];
for(const record of compiled.records.filter(record=>own.includes(record.relative))){
 for(const [file,expected]of [[record.source,record.sourceHash],[record.content,record.sourceHash],[record.artifact,record.compiledHash]])assert.equal(crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'),expected);
}
const report={status:'COMPLETE',at:new Date().toISOString(),archiveRelease:deployed.archive_release,bundle:plan.bundle,
 ui:{layout:'shared commerce grid',uniqueStates:['已解锁','未解锁','状态待同步'],maxOwned:1,stackableDailyMaterialsPreserved:true,browserSizes:browser.cases.map(row=>[row.width,row.height]),compiledSourcesCurrent:true,nativeVisualScreenshotVerified:false},
 settlement:{uniqueItems:97,duplicatesCurrency:'shop_points',firstCopyEffectsOnly:true,duplicateShopPurchasesRejected:true,bulkEmberOfferDisabled:true,singleEmberPrice:29},
 inventory:{accountsScanned:after.scanned_accounts,extraCopiesBefore:before.extra_copies,extraCopiesAfter:after.extra_copies,playerMigrationApplied:false},
 verification:{independentCandidateTests:backend.tests_run,browser:browser.status,deployed:deployed.status,paymentUnchanged:deployed.payment_unchanged,ordersCreated:deployed.orders_created},
 backup:{database:backup.database_backup,sources:backup.source_backup},
 artifacts:{browser:base+'/browser/report.json',backend:base+'/release/candidate_backend_independent.json',deploy:release+'/remote/verify.json'},
 git:{commitCreated:false,pushed:false,preexistingChangesPreserved:true},nextUse:'Re-enter the game so the current bundle is loaded.'};
fs.writeFileSync(base+'/completion.json',JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({status:report.status,archiveRelease:report.archiveRelease,bundle:report.bundle,uniqueItems:97,extraCopiesAfter:after.extra_copies,independentTests:backend.tests_run,browser:'PASS',paymentUnchanged:true}));
