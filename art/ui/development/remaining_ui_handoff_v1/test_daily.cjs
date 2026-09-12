const fs=require('fs'),path=require('path'),vm=require('vm'),assert=require('assert');
const repo=path.resolve(__dirname,'../../../..'),build=JSON.parse(fs.readFileSync(path.join(__dirname,'build.json'))),candidate=path.join(__dirname,'candidate/panorama');
const read=f=>fs.readFileSync(f,'utf8').replace(/\r\n/g,'\n');
const daily=read(path.join(candidate,build.inputs.find(p=>/scripts.*daily_remaining/.test(p))));
const original=read(path.join(__dirname,'baseline/content/scripts/custom_game/daily_rewards.js'));
const claimBody=s=>s.slice(s.indexOf('function claim(target)'),s.indexOf("life.Subscribe('survival_daily_snapshot'"));
assert.equal(claimBody(daily),claimBody(original),'Claim submission and repeat guard stay unchanged');
let suite=read(path.join(repo,'tools/test_daily_ui.js'));
suite=suite.replace("for(const file of ['common/ui_registry','daily_resources','ui_layers','common/ui_components','daily_rewards'])vm.runInContext(fs.readFileSync('panorama/src/scripts/custom_game/'+file+'.js','utf8'),context);","Panel.prototype.Children=function(){return this.children;};Panel.prototype.GetChildCount=function(){return this.children.length;};for(const file of ['common/ui_registry','daily_resources','ui_layers','common/ui_components'])vm.runInContext(fs.readFileSync('panorama/src/scripts/custom_game/'+file+'.js','utf8'),context);vm.runInContext(candidateHelper,context);vm.runInContext(candidateDaily,context);");
// Reproduce native reload ordering: the shared component closure has no daily
// extension, while delivered daily art remains available through the adapter.
suite=suite.replace('vm.runInContext(candidateHelper,context);',`vm.runInContext("var priorImage=config.SurvivalUI.Image;config.SurvivalUI.Image=function(parent,id,cls){if(id.indexOf('daily.')===0)throw Error('Stale daily registry: '+id);return priorImage(parent,id,cls);};".replaceAll('config.','GameUI.CustomUIConfig().'),context);vm.runInContext(candidateHelper,context);`);
suite=suite.replace('config.SurvivalDaily.Open(false);send();',`config.SurvivalDaily.Open(false);
assert.equal(panels.DailyClaimText.text,'加载中…');assert(!panels.DailyClaim.enabled);
events.survival_daily_snapshot({ok:false,error:'网络不可用'});
assert.equal(panels.DailyClaimText.text,'重试加载');assert(panels.DailyClaim.enabled);assert.equal(panels.DailyNotice.text,'网络不可用');
panels.DailyClaim.events.onactivate();panels.DailyClaim.events.onactivate();assert.equal(requests.filter(r=>r.n==='survival_daily_claim').length,0);
assert.equal(requests.filter(r=>r.n==='survival_daily_request').length,2);
config.SurvivalDaily.Close();
// Drain the one startup badge fetch; closed pages must not schedule more work.
for(let round=0;round<3;round++){const pending=[...jobs.values()];jobs.clear();pending.forEach(fn=>fn());}
assert.equal(jobs.size,0);
config.SurvivalDaily.Open(false);send();`);
vm.runInNewContext(suite,{require:require('module').createRequire(path.join(repo,'tools/test_daily_ui.js')),console,candidateDaily:daily,candidateHelper:read(path.join(candidate,build.inputs.find(p=>/^scripts\/custom_game\/remaining_/.test(p))))},{filename:'remaining_daily_behavior.cjs'});
