'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
process.chdir(path.resolve(__dirname,'../..'));
const base='design_refs/points_daily_unique_20261019',release='output/points_daily_unique_20261019/release_v3';
const read=file=>JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,''));
const remote=phase=>read(release+'/remote/'+phase+'.json').records.at(-1);
const plan=read(release+'/plan.json'),live=read(base+'/server/live_verification.json'),browser=read(base+'/browser/report.json'),backend=read(base+'/backend/candidate_regression.json');
const semantics=read(base+'/backend/semantic_plan_regression.json');assert(semantics.ok&&semantics.tests_run===4&&!semantics.errors&&!semantics.failures);
assert.equal(crypto.createHash('sha256').update(fs.readFileSync('server/archive_backend/daily_unique.py')).digest('hex'),semantics.helper_sha256);
const localSource=read(base+'/backend/local_recovery_regression.json');assert(localSource.ok&&localSource.all_12_daily_max_owned_one);
for(const[file,hash]of Object.entries(localSource.source_sha256))assert.equal(crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'),hash,'Local task source drifted: '+file);
const deployed=remote('verify'),validated=remote('validate'),backup=remote('backup'),local=read(release+'/local_install.json');
assert.equal(deployed.status,'DEPLOYMENT_VERIFIED');
for(const value of [deployed.bundle,live.bundle,local.bundle,read('server/bundles/current.json').hash])assert.equal(value,plan.bundle);
assert.equal(live.validated_database_constraint,true);assert.equal(live.daily_extra_copies_remaining,0);assert.equal(live.lottery_extra_copies_remaining,0);
assert.equal(live.runtime_role_cannot_execute_constraint_helper,true);
assert.equal(live.repaired_accounts,3);assert.equal(live.removed_extra_copies,16);assert.equal(live.credited_shop_points,400);
assert.deepEqual(live.growth_gem_counts,[1,1,1]);assert.equal(live.max_daily_count,1);
assert.equal(browser.status,'PASS');assert(backend.ok&&backend.tests_run===10&&!backend.errors&&!backend.failures);
assert.equal(deployed.payment_unchanged,true);
for(const name of ['archive_compile.json','compile.json'])for(const record of read(base+'/'+name).records){
 for(const [file,hash]of [[record.source,record.sourceHash],[record.content,record.sourceHash],[record.artifact,record.compiledHash]])assert.equal(crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'),hash);
}
const nativeSource='design_refs/menus_v10/work/native/points_daily_unique_20261019_deployed.png';
assert(fs.existsSync(nativeSource));fs.mkdirSync(base+'/native',{recursive:true});fs.copyFileSync(nativeSource,base+'/native/points_top.png');
const hoverSource='design_refs/menus_v10/work/native/points_daily_unique_20261019_growth_verified.png';assert(fs.existsSync(hoverSource));fs.copyFileSync(hoverSource,base+'/native/growth_hover.png');
const report={status:'COMPLETE',at:new Date().toISOString(),archiveRelease:deployed.archive_release,bundle:plan.bundle,
 correction:'Daily reward items were incorrectly preserved as stackable in the previous task. This release makes all 109 points-page items unique.',
 ui:{uniqueItems:109,states:['已解锁','未解锁','状态待同步'],quantityRatiosRemoved:true,legacyGrowthGemCount3ShowsUnlocked:true,nativeScreenshot:base+'/native/points_top.png',nativeHoverScreenshot:base+'/native/growth_hover.png',nativeVisualVerified:true,nativeLimitation:'Existing game session still has its earlier Lua catalog loaded; all 109 configured items are verified by frozen worker and browser, not claimed from the 105-row current-session screenshot.',browserSizes:browser.cases.map(row=>[row.width,row.height])},
 server:{dailyItems:12,lotteryItems:97,maxCount:1,databaseConstraintValidated:true,repairedAccounts:3,removedExtraCopies:16,creditedShopPoints:400,removedDuplicateEffects:live.removed_duplicate_effects,remainingDuplicates:0,growthGemCounts:live.growth_gem_counts,paymentUnchanged:true},
 validation:{candidateWorkerTests:backend.tests_run,repairScopeTests:semantics.tests_run,browser:browser.status,realPostgres:validated.database,deploy:deployed.status},
 backup:{database:backup.database_backup,sources:backup.source_backup},
 artifacts:{liveVerification:base+'/server/live_verification.json',candidate:base+'/backend/candidate_regression.json',deploy:release+'/remote/verify.json'},
 git:{commitCreated:false,pushed:false,otherWorkPreserved:true}};
fs.writeFileSync(base+'/completion.json',JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({status:report.status,archiveRelease:report.archiveRelease,uniqueItems:109,maxStoredCount:1,repairedAccounts:3,removedExtraCopies:16,creditedShopPoints:400,growthGemCounts:live.growth_gem_counts}));
