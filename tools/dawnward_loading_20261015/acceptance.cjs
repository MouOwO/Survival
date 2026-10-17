'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {browser,sleep}=require('../shop_ui_12h/cdp.cjs');
const outputArg=process.argv.indexOf('--out');
const out=outputArg>=0?process.argv[outputArg+1]:'output/loading_refine_20261016',page=out+'/preview/index.html';
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const assemblyFile=out+'/preview/assembly.json',assembly=JSON.parse(fs.readFileSync(assemblyFile,'utf8'));
function frozen(){for(const row of [...assembly.sources,...assembly.assets])assert.equal(sha(fs.readFileSync(row.read_from||row.path)),row.sha256,'production inputs drifted: '+row.path);}
const inspect=String.raw`(()=>{syncLayout();
const visible=element=>{if(!element)return false;for(let p=element;p;p=p.parentElement){const css=getComputedStyle(p);if(p.hidden||css.display==='none'||css.visibility==='hidden'||css.getPropertyValue('--pano-visibility').trim()==='collapse'||Number(css.opacity)===0)return false;}return !!element.getClientRects().length;};
const box=element=>element&&element.getBoundingClientRect().toJSON();
const title=nodes.StartupLoadingTitle.el,track=nodes.StartupLoadingProgressTrack.el,fill=nodes.StartupLoadingProgressFill.el,image=nodes.StartupLoadingBackground.el;
const labels=[...document.querySelectorAll('.SurvivalStartupLoading .label')].filter(visible).map(element=>{const range=document.createRange();range.selectNodeContents(element);return{id:element.id,text:element.textContent,box:box(element),textBoxes:[...range.getClientRects()].map(r=>r.toJSON())};});
return {fixture:loadingFixture,errors:previewErrors,scripts:previewScriptResults,calls:previewCalls,title:{text:title.textContent,visible:visible(title),box:box(title)},track:{visible:visible(track),box:box(track)},fill:{percent:parseFloat(nodes.StartupLoadingProgressFill.style.width),box:box(fill),well:box(fill.parentElement),background:getComputedStyle(fill).backgroundImage},percent:nodes.StartupLoadingPercent.text,root:{visible:nodes.StartupLoadingSurface.visible,hittest:nodes.StartupLoadingSurface.hittest,hittestchildren:nodes.StartupLoadingSurface.hittestchildren},background:{visible:visible(image),src:image.src,width:image.naturalWidth,height:image.naturalHeight,opacity:getComputedStyle(image).opacity},labels,frames:[...document.querySelectorAll('.StartupLoadingProgressFrame img')].map(element=>({src:element.src,decoded:element.complete&&element.naturalWidth>0,box:box(element),scaling:getComputedStyle(element).objectFit})),retry:{visible:visible(nodes.StartupLoadingRetry.el),enabled:nodes.StartupLoadingRetry.enabled},errorVisible:visible(nodes.StartupLoadingErrorBox.el),removed:['StartupPartyStart','StartupLoadingStatus','StartupLoadingDetail','StartupLoadingReadyCount','StartupLoadingPlayers'].filter(id=>!!nodes[id])};})()`;
const inside=(b,w,h)=>b.left>=-1&&b.top>=-1&&b.right<=w+1&&b.bottom<=h+1;
(async()=>{
 frozen();const b=await browser(),checks=[];
 try{
  await b.call('Network.enable');await b.call('Network.setBlockedURLs',{urls:['http://*','https://*','ws://*','wss://*']});
  for(const [width,height] of [[1920,1080],[1280,720]]){
   await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
   for(const state of ['resources','waiting','error','team_setup']){
    frozen();await b.go(page,'?state='+state);assert(await b.run('loadingReady'),'preview fixture did not start');await sleep(200);
    let s=await b.run(inspect);assert.deepEqual(s.errors,[]);assert(s.scripts.length&&s.scripts.every(row=>row.ok),'actual production scripts execute');assert.deepEqual(s.removed,[],'old custom lobby UI must be absent');
    assert.equal(s.percent,s.fixture.expectedPercent+'%');assert(Math.abs(s.fill.percent-s.fixture.expectedFill)<.01,'percentage is authoritative real fixture progress');
    assert(s.background.width>0&&s.background.height>0,'actual loading image decoded');assert(s.frames.every(row=>row.decoded&&row.scaling==='fill'),'real native frame assets decoded using authored stretch-to-fit');
    if(state==='team_setup'){
     assert.equal(s.root.visible,false);assert.equal(s.root.hittest,false);assert.equal(s.root.hittestchildren,false);assert.equal(s.title.visible,false);assert.equal(s.track.visible,false);assert.equal(s.background.visible,false);assert.equal(s.labels.length,0);
     assert(s.calls.some(row=>row.name==='survival_loading_client_ready'),'image handshake survives hidden official setup');
    }else{
     assert.equal(s.root.visible,true);assert(s.background.visible&&s.title.visible&&s.track.visible);assert.equal(s.title.text,'孤城逐晓');
     assert(Math.abs(s.title.box.x+s.title.box.width/2-width/2)<=1,'title centered');assert(s.title.box.top>=0&&s.title.box.bottom<height*.35,'title in upper part of screen');assert(inside(s.track.box,width,height));assert(s.track.box.height<height*.06,'narrow Warcraft progress bar');
     const actual=s.fill.box.width/s.fill.well.width*100;assert(Math.abs(actual-s.fixture.expectedFill)<.4,'rendered blue fill matches actual progress');
     assert(s.fill.box.left>=s.track.box.left&&s.fill.box.top>=s.track.box.top&&s.fill.box.right<=s.track.box.right&&s.fill.box.bottom<=s.track.box.bottom,'blue fill stays inside the native frame');
     assert(s.labels.every(row=>row.id==='StartupLoadingTitle'||state==='error'),'normal loading contains only the game name, no old status card');
     assert.equal(s.errorVisible,state==='error');
     if(state==='error'){
      assert(s.retry.visible&&s.retry.enabled);assert(s.labels.some(row=>row.id==='StartupLoadingError'&&row.text.includes('setup_hammer_backend.cmd')));assert(s.labels.every(row=>inside(row.box,width,height)),'error labels fit viewport');
      const retry=s.labels.find(row=>row.text==='重试').box,x=retry.x+retry.width/2,y=retry.y+retry.height/2;
      await b.call('Input.dispatchMouseEvent',{type:'mousePressed',button:'left',clickCount:1,x,y});await b.call('Input.dispatchMouseEvent',{type:'mouseReleased',button:'left',clickCount:1,x,y});await sleep(30);s=await b.run(inspect);assert(s.calls.some(row=>row.name==='survival_loading_retry'),'real retry handler executes');
     }
    }
    assert(s.calls.every(row=>['survival_loading_client_ready','survival_loading_retry'].includes(row.name)),'preview emits no removed party or gameplay requests');
    const screenshot=out+'/screenshots/'+state+'_'+width+'x'+height+'.png';await b.shot(screenshot,{x:0,y:0,width,height});
    checks.push({width,height,state,screenshot,passed:true,evidence:s});console.log('PREVIEW_PASS '+state+' '+width+'x'+height);
   }
  }
  frozen();const report={status:'PASS',at:new Date().toISOString(),scope:'Offline browser executes actual production XML/CSS/JS with local nettable fixtures; native game remains unverified',native_game_verified:false,external_network_requests:'HTTP/HTTPS/WS/WSS blocked by DevTools before navigation',assembly_sha256:sha(fs.readFileSync(assemblyFile)),adapter_corrections:assembly.adapter_corrections,checks};fs.writeFileSync(out+'/preview_validation.json',JSON.stringify(report,null,2)+'\n');
 }catch(error){fs.writeFileSync(out+'/preview_validation.failed.json',JSON.stringify({status:'FAIL',error:String(error),stack:error.stack,checks},null,2)+'\n');throw error;}
 finally{b.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
