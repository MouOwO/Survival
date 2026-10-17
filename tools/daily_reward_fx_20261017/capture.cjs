'use strict';
// Isolated browser execution of the active daily controller and actual shared
// glass module. All reward replies are fixtures; no account/server is written.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {browser,sleep}=require('../shop_ui_12h/cdp.cjs');
const repo=path.resolve(__dirname,'../..'),out='design_refs/daily_reward_fx_20261017';process.chdir(repo);
const inspect=`(()=>{const card=nodes.DailyGW2Day_3,surface=card.Children().find(p=>p.BHasClass('RewardGlassSurface')),sweep=surface?.Children()[0],box=p=>p?.el.getBoundingClientRect().toJSON();return {api:cfg.SurvivalDaily.Inspect(),errors:previewErrors,card:{bounds:box(card),opacity:getComputedStyle(card.el).opacity,classes:card.GetClasses()},surface:surface?{bounds:box(surface),parent:surface.GetParent().id,visible:surface.visible,hittest:surface.hittest,hittestchildren:surface.hittestchildren}:null,sweep:sweep?{bounds:box(sweep),animationName:getComputedStyle(sweep.el).animationName,opacity:getComputedStyle(sweep.el).opacity,animations:sweep.el.getAnimations().map(a=>({time:a.currentTime,state:a.playState,rate:a.playbackRate,timing:a.effect.getComputedTiming()}))}:null,calls:previewCalls.filter(c=>c.name==='survival_daily_claim')};})()`;
(async()=>{const assemblyFile=out+'/preview/assembly.json',assembly=JSON.parse(fs.readFileSync(assemblyFile,'utf8'));
 const sourceScope=assembly.sourceGraph.filter(row=>/reward_feedback|daily_gw2\.css|daily_remaining/.test(row.path));
 const hash=value=>crypto.createHash('sha256').update(value).digest('hex');
 const verifySources=()=>sourceScope.forEach(row=>assert.equal(hash(fs.readFileSync('panorama/src/'+row.path,'utf8').replace(/^\uFEFF/,'')),row.sha256,'Frozen production source '+row.path));
 verifySources();const b=await browser(),report={kind:'daily_claim_real_source_browser_check',notGameCapture:true,fixtureOnly:true,at:new Date().toISOString(),assemblyFile,assemblySha256:hash(fs.readFileSync(assemblyFile)),sourceScope,screens:[]};
 try{for(const [width,height]of[[1920,1080],[815,528]]){
  await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await b.go(out+'/preview/index.html');assert.equal(await b.run('previewReady'),true);
  await b.run('previewCalls.length=0;nodes.DailyClaim.events.onactivate();dailyPreviewSend({pending:1,claim_result:{target_day:25000,ok:true,pending:true}});true');
  let state=await b.run(inspect);assert.equal(state.surface,null,'Pending data cannot celebrate');assert.equal(state.calls.length,1);
  await b.run('dailyPreviewSend({claim_result:{target_day:25000,ok:false,error:"隔离测试拒绝"}});true');state=await b.run(inspect);assert.equal(state.surface,null,'Rejected data cannot celebrate');
  await b.run('nodes.DailyClaim.events.onactivate();dailyPreviewSend({count:3,claimed:1,claim_result:{target_day:25000,ok:true,pending:false}});true');
  await b.run('new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>resolve(true))))');await sleep(100);
  // Headless Chrome can defer compositor animation clocks until a capture.
  // Request an actual frame before sampling computed animation properties.
  await b.call('Page.captureScreenshot',{format:'png',clip:{x:0,y:0,width:1,height:1,scale:1}});
  state=await b.run(inspect);assert.deepEqual(state.errors,[]);assert.equal(state.surface?.parent,'DailyGW2Day_3');assert.equal(state.surface.visible,true);assert.equal(state.card.opacity,'1');assert.match(state.sweep.animationName,/RewardGlassPass[AB]/);assert(+state.sweep.opacity>0,'A real painted CSS highlight is visible: '+JSON.stringify(state.sweep));
  for(const edge of['x','y','width','height'])assert(Math.abs(state.surface.bounds[edge]-state.card.bounds[edge])<1,'The live glass fills its claimed card at '+width+' '+edge);
  const image=out+'/screens/claim_glass_'+width+'x'+height+'.png';await b.shot(image,{x:0,y:0,width,height});report.screens.push({width,height,image,during:state});
  await sleep(700);state=await b.run(inspect);assert.equal(state.surface,null);assert.equal(state.card.opacity,'0.6');
  await b.run('dailyPreviewSend({count:3,claimed:1,claim_result:{target_day:25000,ok:true,pending:false}});true');state=await b.run(inspect);assert.equal(state.surface,null,'Repeated committed replies do not replay');assert.equal(state.calls.length,2,'Only explicit request and retry sent');
  await b.run('cfg.SurvivalDaily.Close();true');assert.equal((await b.run(inspect)).surface,null);
 }
 verifySources();report.status='PASS_REAL_DAILY_CLAIM_GLASS';fs.writeFileSync(out+'/report.json',JSON.stringify(report,null,2));console.log(report.status+' '+out+'/report.json');
 }finally{b.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
