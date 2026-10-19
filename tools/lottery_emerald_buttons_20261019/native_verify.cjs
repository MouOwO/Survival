'use strict';
// QA of real Panorama sources in a browser adapter. This is NOT a game capture.
// The only simulated draw requests go to the adapter's in-memory event journal.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict'),cp=require('node:child_process'),Module=require('node:module'),{pathToFileURL}=require('node:url');
const repo=path.resolve(__dirname,'../..'),out=path.join(repo,'output/lottery_emerald_buttons_20261019/native'),preview=path.join(out,'preview'),captures=path.join(out,'browser');
process.chdir(repo);fs.mkdirSync(out,{recursive:true});
const temp=path.join(out,'tmp');fs.mkdirSync(temp,{recursive:true});process.env.TEMP=temp;process.env.TMP=temp;
const sha=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'),textSha=file=>crypto.createHash('sha256').update(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,'')).digest('hex');
const sourceFiles=['scripts/custom_game/lottery_gw2.js','styles/custom_game/lottery_gw2.css'];
function checkFrozen(assembly){const changed=assembly.sourceGraph.filter(row=>textSha(path.join(repo,'panorama/src',row.path))!==row.sha256).map(row=>row.path);assert.deepEqual(changed,[],'The final production source graph remains frozen during QA');return changed;}
function exportNative(){
 const {open}=require('../vpk_inspect.cjs'),vpk=open(path.resolve(repo,'../../dota/pak01_dir.vpk'));
 const source=sourceFiles.map(file=>fs.readFileSync(path.join(repo,'panorama/src',file),'utf8')).join('\n');
 const uris=[...new Set([...source.matchAll(/(?:file:\/\/\{images\}\/|s2r:\/\/panorama\/images\/)[^"'\s)]+?\.(?:png|svg|vtex)/g)].map(match=>match[0]))].filter(uri=>!uri.includes('/custom_game/'));
 const root=path.join(out,'native_assets');fs.mkdirSync(root,{recursive:true});
 const records=[],aliases={},viewer=path.join(repo,'output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe');
 for(const uri of uris){
  const rel=uri.replace(/^file:\/\/\{images\}\//,'').replace(/^s2r:\/\/panorama\/images\//,'');
  const candidates=uri.startsWith('s2r:')?['panorama/images/'+rel+'_c']:rel.endsWith('.svg')?['panorama/images/'+rel.replace(/\.svg$/,'.vsvg_c')]:['panorama/images/'+rel.replace(/\.png$/,'_png.vtex_c'),'panorama/images/'+rel+'.vtex_c'];
  const entry=candidates.map(candidate=>vpk.entries.find(row=>row.path===candidate)).find(Boolean);assert(entry,'Exact installed Valve asset exists: '+uri);
  const bytes=vpk.read(entry),digest=crypto.createHash('sha256').update(bytes).digest('hex'),name=path.basename(rel).replace(/\.[^.]+$/,'')+'_'+digest.slice(0,12),svg=entry.path.endsWith('.vsvg_c'),input=path.join(root,name+path.extname(entry.path)),output=path.join(root,name+(svg?'.svg':'.png'));
  if(!fs.existsSync(output)){
   fs.writeFileSync(input,bytes);
   if(svg){const start=bytes.indexOf('<svg'),end=bytes.indexOf('</svg>',start);assert(start>=0&&end>start);fs.writeFileSync(output,bytes.subarray(start,end+6));}
   else cp.execFileSync(viewer,['-i',input,'-o',output,'-d'],{windowsHide:true,stdio:'pipe',env:process.env});
  }
  const nativeUri=rel.startsWith('masks/')?'data:image/'+(svg?'svg+xml':'png')+';base64,'+fs.readFileSync(output).toString('base64'):pathToFileURL(output).href;aliases[uri]=nativeUri;aliases[rel]=nativeUri;
  if(rel.endsWith('.png'))aliases['s2r://panorama/images/'+rel.replace(/\.png$/,'_png.vtex')]=nativeUri;
  records.push({uri,resource:entry.path,sourceSha256:digest,previewPath:path.relative(repo,output).replaceAll('\\','/'),previewSha256:sha(output),method:svg?'Exact SVG payload from installed VSVG':'Source2Viewer decode of installed VTEX, without visual edits'});
 }
 const manifest={kind:'exact_installed_valve_assets_browser_aliases',notGameCapture:true,records,aliases};fs.writeFileSync(path.join(root,'manifest.json'),JSON.stringify(manifest,null,2));return manifest;
}
function buildPreview(native){
 const file=path.join(repo,'tools/lottery_fullscreen_20261018/preview.cjs');
 let source=fs.readFileSync(file,'utf8').replaceAll('output/lottery_fullscreen_20261018','output/lottery_emerald_buttons_20261019/native');
 const runner='const Module=require("node:module"),file='+JSON.stringify(file)+';const m=new Module(file,module);m.filename=file;m.paths=Module._nodeModulePaths(require("node:path").dirname(file));m._compile('+JSON.stringify(source)+',file);';
 const built=cp.spawnSync(process.execPath,['-e',runner],{cwd:repo,encoding:'utf8',windowsHide:true,env:process.env});if(built.stdout)process.stdout.write(built.stdout);if(built.stderr)process.stderr.write(built.stderr);assert.equal(built.status,0,'Real production lottery source assembly succeeds');
 const entry=path.join(preview,'index.html');let html=fs.readFileSync(entry,'utf8'),css=fs.readFileSync(path.join(preview,'style.css'),'utf8');
 const prefix='window.PREVIEW_ASSET_PATHS=',start=html.indexOf(prefix)+prefix.length,end=html.indexOf(';window.',start);assert(start>=prefix.length&&end>start);
 const assets=JSON.parse(html.slice(start,end));Object.assign(assets,native.aliases);html=html.slice(0,start)+JSON.stringify(assets).replaceAll('</script','<\\/script')+html.slice(end);
 for(const record of native.records){const rel=record.uri.replace(/^file:\/\/\{images\}\//,'').replace(/^s2r:\/\/panorama\/images\//,''),wrong=pathToFileURL(path.join(repo,'panorama/src/images',rel)).href;css=css.replaceAll(wrong,native.aliases[record.uri]).replaceAll(record.uri,native.aliases[record.uri]);}
 html=html.replace(/(<div id="PreviewCaption">)[\s\S]*?(<\/div>)/,'$1幽林翡翠 · 实际 Panorama 源码及安装官方素材 · 离线样例 · 非游戏截图，无账号或抽奖服务连接$2');
 fs.writeFileSync(entry,html);fs.writeFileSync(path.join(preview,'style.css'),css);
 const assemblyPath=path.join(preview,'assembly.json'),assembly=JSON.parse(fs.readFileSync(assemblyPath,'utf8'));assembly.kind='lottery_emerald_buttons_actual_sources_offline_qa';assembly.gameVerified=false;assembly.additionalNativeAliases=native;assembly.previewHarness.push({path:path.relative(repo,__filename).replaceAll('\\','/'),sha256:sha(__filename)});fs.writeFileSync(assemblyPath,JSON.stringify(assembly,null,2));return assembly;
}
function createBrowser(){
 const file=path.join(repo,'tools/market_filter_20261017/browser.cjs'),source=fs.readFileSync(file,'utf8').replace('design_refs/market_filter_20261017/preview/browser/profile_','output/lottery_emerald_buttons_20261019/native/browser/profile_');
 const loaded=new Module(file,module);loaded.filename=file;loaded.paths=Module._nodeModulePaths(path.dirname(file));loaded._compile(source,file);return loaded.exports;
}
async function inspect(){
 const shown=p=>{if(!p)return false;for(let el=p.el;el;el=el.parentElement){const css=getComputedStyle(el);if(el.hidden||css.display==='none'||css.visibility==='hidden')return false;}const r=p.el.getBoundingClientRect();return r.width>0&&r.height>0;};
 const rect=p=>{if(!p)return null;const box=p.el.getBoundingClientRect().toJSON(),css=getComputedStyle(p.el);return {id:p.id,...box,position:p.style.position,widthStyle:p.style.width,heightStyle:p.style.height,visible:shown(p),enabled:p.enabled,text:p.text,classes:p.GetClasses(),background:css.backgroundColor,backgroundImage:css.backgroundImage,color:css.color,opacity:css.opacity,font:css.fontSize,shadow:css.textShadow};};
 const urls=value=>[...String(value||'').matchAll(/url\(["']?([^"')]+)["']?\)/g)].map(match=>match[1]);
 const backgrounds=[...new Set([nodes.LotterySingleButton,nodes.LotteryTenButton].flatMap(p=>[p,...p.FindChildrenWithClassTraverse('Panel')]).filter(Boolean).flatMap(p=>urls(getComputedStyle(p.el).backgroundImage)))];
 for(const p of [nodes.LotterySingleButton,nodes.LotteryTenButton])for(const el of [p.el,...p.el.querySelectorAll('*')])backgrounds.push(...urls(getComputedStyle(el).backgroundImage));
 const decoded=await Promise.all([...new Set(backgrounds)].map(async src=>{const image=new Image();image.src=src;try{await image.decode();return {src,decoded:!!image.naturalWidth,width:image.naturalWidth,height:image.naturalHeight};}catch{return {src,decoded:false};}}));
 const buttons=['LotterySingleButton','LotteryTenButton'].map(id=>{const p=nodes[id],r=p.el.getBoundingClientRect(),hit=document.elementFromPoint(r.x+r.width/2,r.y+r.height/2);return {...rect(p),hit:hit?.id,hotzone:!!hit&&(hit===p.el||p.el.contains(hit)),children:[...p.el.querySelectorAll('*')].map(el=>({id:el.id,classes:[...el.classList],bounds:el.getBoundingClientRect().toJSON(),text:el.textContent,background:getComputedStyle(el).backgroundImage,color:getComputedStyle(el).color,font:getComputedStyle(el).fontSize,opacity:getComputedStyle(el).opacity}))};});
 const rewards=nodes.LotteryGW2PreviewItems.Children().map(p=>({...rect(p),images:[...p.el.querySelectorAll('img')].map(el=>({src:el.currentSrc||el.src,decoded:el.complete&&el.naturalWidth>0}))}));
 return {errors:previewErrors,scriptFailures:previewScriptResults.filter(row=>!row.ok),api:cfg.SurvivalPurpleLottery.Inspect(),canvas:rect(nodes.LotteryMainCanvas),content:rect(nodes.LotteryGW2Content),previewGroup:rect(nodes.LotteryGW2Preview),rewardContainer:rect(nodes.LotteryGW2PreviewItems),pity:rect(nodes.LotteryDrawPity),footerActions:['LHDetails','LHHistory','LotteryAnnouncement','LotterySkipAnimation'].map(id=>rect(nodes[id])).filter(Boolean),rewards,buttons,decoded,calls:previewCalls};
}
function check(state,width,height,pool){
 assert.deepEqual(state.errors,[]);assert.deepEqual(state.scriptFailures,[]);assert.equal(state.api.selected,pool);assert.equal(state.rewards.length,8,'Eight real preview rewards');
 const scale=state.canvas.width/1672,logical=box=>({x:(box.x-state.content.x)/scale,y:(box.y-state.content.y)/scale,w:box.width/scale,h:box.height/scale}),near=(got,want,label)=>assert(Math.abs(got-want)<1,label+': '+got+' / '+want);
 for(const [index,want]of [[0,[781,560,220,84]],[1,[1021,560,244,84]]]){const button=state.buttons[index],box=logical(button);for(const[key,val]of Object.entries({x:want[0],y:want[1],w:want[2],h:want[3]}))near(box[key],val,button.id+' '+key);assert(button.enabled&&button.hotzone,button.id+' is enabled and has an unobscured real pointer hotzone');}
 const rewards=state.rewards.map(logical),group=logical(state.previewGroup);near(group.x,44,'Reward group x');near(group.y,390,'Reward group top');near(group.h,158,'Reward group height');near(Math.min(...rewards.map(r=>r.y)),432,'Actual cards follow the preview caption');assert(Math.max(...rewards.map(r=>r.y+r.h))<=548.8,'Rewards end above the draw buttons');
 const separate=(a,b)=>a.right<=b.x||a.x>=b.right||a.bottom<=b.y||a.y>=b.bottom;
 for(const reward of state.rewards){assert(reward.images.length&&reward.images.every(row=>row.decoded),'Reward image decodes');for(const button of state.buttons)assert(separate(reward,button),'Preview reward never covers draw buttons');if(state.pity?.visible)assert(separate(reward,state.pity),'Pity caption must not overlap any reward name');}
 if(state.pity?.visible)for(const control of [...state.buttons,...state.footerActions])assert(separate(state.pity,control),'Pity caption clears draw buttons and footer controls');
 assert(state.decoded.length>0&&state.decoded.every(row=>row.decoded),'Every official button background decodes');assert(state.canvas.x>=-1&&state.canvas.y>=-1&&state.canvas.right<=width+1&&state.canvas.bottom<=height+1,'Fitted canvas remains inside viewport');return {scale,buttons:state.buttons.map(logical),rewards};
}
async function point(b,id,type){const p=await b.run(`(()=>{const r=nodes[${JSON.stringify(id)}].el.getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2};})()`);await b.call('Input.dispatchMouseEvent',{type,...p,button:type==='mouseMoved'?'none':'left',clickCount:type==='mouseMoved'?0:1});}
async function main(){
 assert(process.argv.includes('--run'),'Preparation only until deployment is ready. Pass --run after the final production agent confirms its sources.');
 const frozen=sourceFiles.map(file=>({file,sha256:textSha(path.join(repo,'panorama/src',file))}));
 const native=exportNative(),assembly=buildPreview(native);checkFrozen(assembly);fs.mkdirSync(captures,{recursive:true});
 const report={at:new Date().toISOString(),kind:'lottery_emerald_buttons_actual_sources_offline_qa',gameVerified:false,networkBlocked:true,frozen,nativeResources:native.records,cases:[],inputTests:[],limitations:['Actual production XML/JS/CSS and formal CSV data run in a browser Panorama adapter.','All game event output is recorded only in memory; there is no account, payment or native game connection.','The native prefix in this QA filename refers to production components and installed official textures, not native game rendering.','Cinematic playback and other unchanged systems are outside this focused button regression.']};
 const {browser,sleep}=createBrowser(),b=await browser();let width=1920,height=1080;
 try{
  await b.call('Network.setBlockedURLs',{urls:['http://*','https://*','ws://*','wss://*']});
  for(const size of [[1920,1080],[1280,720]]){
   [width,height]=size;await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await b.go(path.join(preview,'index.html'));assert(await b.run('previewReady'));
   for(const pool of ['map','cultivation','dragon_knight','summer']){
    await b.run('lotteryPreviewSelect('+JSON.stringify(pool)+',20)');const state=await b.run('('+inspect.toString()+')()'),geometry=check(state,width,height,pool),name=width+'x'+height+'_'+pool;
    fs.writeFileSync(path.join(captures,name+'.json'),JSON.stringify(state,null,2));await b.shot(path.join(captures,name+'.png'),width,height);report.cases.push({width,height,pool,...geometry,screenshot:path.relative(repo,path.join(captures,name+'.png')).replaceAll('\\','/')});console.log('EMERALD_PANORAMA_OFFLINE_CATEGORY_PASS '+name);
   }
   await b.run("lotteryPreviewSelect('map',20)");
   for(const [id,count]of [['LotterySingleButton',1],['LotteryTenButton',10]]){
    const before=await b.run("previewCalls.filter(row=>row.name==='ui_lottery_draw_request').length");await point(b,id,'mouseMoved');await sleep(100);await b.shot(path.join(captures,width+'x'+height+'_'+count+'_hover.png'),width,height);await point(b,id,'mousePressed');await b.shot(path.join(captures,width+'x'+height+'_'+count+'_pressed.png'),width,height);await point(b,id,'mouseReleased');await sleep(120);
    const sent=await b.run("(()=>{const rows=previewCalls.filter(row=>row.name==='ui_lottery_draw_request');return{length:rows.length,last:rows.at(-1)};})()");assert.equal(sent.length,before+1,'Button sends its original request exactly once');assert.equal(sent.last.payload.count,count);
    await b.run(`emit('ui_lottery_result',{ok:0,error:'OFFLINE_QA_REJECTION',request_id:${JSON.stringify(sent.last.payload.request_id)},pool_id:'map'});syncLayout();true`);report.inputTests.push({width,height,id,count,requestId:sent.last.payload.request_id,requests:1});
   }
   await b.run("lotteryPreviewSend('map',0);syncLayout();true");const disabled=await b.run('('+inspect.toString()+')()');assert(disabled.buttons.every(row=>row.enabled===false),'Both draw actions disable when no tickets remain');await b.shot(path.join(captures,width+'x'+height+'_disabled.png'),width,height);report.inputTests.push({width,height,kind:'zero-ticket-disabled',buttons:disabled.buttons});
  }
  report.changedSinceSnapshot=checkFrozen(assembly);report.status='PASS';
 }catch(error){report.status='FAIL';report.failure=error.stack||String(error);try{report.failureState=await b.run('('+inspect.toString()+')()');await b.shot(path.join(captures,'failure.png'),width,height);}catch{}throw error;}
 finally{fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));b.close();}
 console.log('EMERALD_PANORAMA_OFFLINE_QA_PASS '+path.relative(repo,path.join(out,'report.json')));
}
if(require.main===module){let settled=false;process.on('beforeExit',()=>{if(!settled)process.exitCode=1;});main().then(()=>{settled=true;},error=>{settled=true;console.error(error.stack||error);process.exitCode=1;});}
module.exports={inspect,check};
