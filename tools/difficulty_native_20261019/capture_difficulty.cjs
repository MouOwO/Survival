'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),{browser}=require('./browser.cjs');
const repo=path.resolve(__dirname,'../..'),base=path.join(__dirname,'difficulty_preview'),docs=path.join(repo,'docs/design/difficulty_native_20261019'),themes=JSON.parse(fs.readFileSync(path.join(base,'themes.json'),'utf8')),sha=b=>crypto.createHash('sha256').update(b).digest('hex');
fs.mkdirSync(docs,{recursive:true});
const report={kind:'five_actual_difficulty_component_native_material_concepts',gameVerified:false,themes:[],checks:[]};
const measure=String.raw`(()=>{
 const box=n=>{const r=n.el.getBoundingClientRect();return {x:r.x,y:r.y,right:r.right,bottom:r.bottom,width:r.width,height:r.height,cx:r.x+r.width/2,cy:r.y+r.height/2};};
 const dialog=box(nodes.DifficultySelectionDialog),header=box(nodes.DifficultySelectionHeader),title=box(nodes.DifficultySelectionTitle),body=box(nodes.DifficultySelectionButtons),rows=nodes.DifficultySelectionButtons.Children().filter(n=>n.BHasClass('DifficultyOptionButton'));
 const checks=[],check=(name,pass,detail)=>checks.push({name,pass:!!pass,detail});
 check('actual scripts execute without errors',previewErrors.length===0,previewErrors.slice());
 check('dialog inside viewport',dialog.x>=0&&dialog.y>=0&&dialog.right<=innerWidth+1&&dialog.bottom<=innerHeight+1,dialog);
 check('natural header text centered',Math.abs(title.cx-header.cx)<=1.5&&Math.abs(title.cy-header.cy)<=1.5,{header,title});
 check('ten actual difficulty rows',rows.length===10,rows.length);
 check('rows remain inside scrolling viewport horizontally',rows.every(n=>{const r=box(n);return r.x>=body.x-1&&r.right<=body.right+1;}),{body,rows:rows.map(box)});
 const labels=rows.map(n=>{const h=n.Children().find(c=>c.BHasClass('DifficultyOptionHeader')),code=h.Children().find(c=>c.BHasClass('DifficultyOptionCode')),status=h.Children().find(c=>c.BHasClass('DifficultyOptionAvailability')),r=box(n),t=box(code),s=box(status);return {code:code.text,status:status.text,box:r,title:t,statusBox:s,locked:n.BHasClass('DifficultyOptionLocked')};});
 check('row text vertically centered',labels.every(x=>Math.abs(x.box.cy-x.title.cy)<=1.5),labels);
 check('locked code and condition do not overlap',labels.filter(x=>x.locked).every(x=>x.title.right<=x.statusBox.x+1),labels.filter(x=>x.locked));
 check('locked text is not clipped',rows.filter(n=>n.BHasClass('DifficultyOptionLocked')).every(n=>{const e=n.Children()[0].Children().find(c=>c.BHasClass('DifficultyOptionAvailability')).el;return e.scrollWidth<=e.clientWidth+1;}),labels.filter(x=>x.locked));
 check('preloaded team cap shown',/队伍上限 N6/.test(nodes.DifficultySelectionHint.text),nodes.DifficultySelectionHint.text);
 check('only one genuine confirm request in local log',previewCalls.filter(x=>x.name==='ui_difficulty_select_request').length===1,previewCalls.filter(x=>x.name==='ui_difficulty_select_request'));
 return {pass:checks.every(c=>c.pass),checks,errors:previewErrors.slice(),dialog,viewport:{width:innerWidth,height:innerHeight}};
})()`;
(async()=>{const b=await browser();try{
 for(const theme of themes){
  await b.call('Emulation.setDeviceMetricsOverride',{width:1920,height:1080,deviceScaleFactor:1,mobile:false});await b.go(path.join(base,theme.id,'index.html'));
  const ready=await b.run('previewReady');if(!ready)throw Error(JSON.stringify(await b.run('previewErrors')));
  const result=await b.run(measure),file=path.join(docs,String(theme.number).padStart(2,'0')+'_'+theme.id+'.png');await b.shot(file,1920,1080);
  // Render at device scale 2 before clipping: fonts are rasterized at twice
  // device density, rather than enlarging an existing raster screenshot.
  await b.call('Emulation.setDeviceMetricsOverride',{width:1920,height:1080,deviceScaleFactor:2,mobile:false});await b.run('document.fonts.ready.then(()=>{syncLayout();return true;})');
  const dialog=result.dialog,clip={x:Math.floor(dialog.x)-10,y:Math.floor(dialog.y)-10,width:Math.ceil(dialog.width)+20,height:Math.ceil(dialog.height)+20,scale:1},detailFile=path.join(docs,String(theme.number).padStart(2,'0')+'_'+theme.id+'_detail.png');
  const detail=await b.call('Page.captureScreenshot',{format:'png',captureBeyondViewport:true,clip});fs.writeFileSync(detailFile,Buffer.from(detail.data,'base64'));
  const assembly=JSON.parse(fs.readFileSync(path.join(base,theme.id,'assembly.json'),'utf8'));
  report.themes.push({...theme,...result,screenshot:path.relative(repo,file).replaceAll('\\','/'),screenshotSha256:sha(fs.readFileSync(file)),detailScreenshot:path.relative(repo,detailFile).replaceAll('\\','/'),detailSha256:sha(fs.readFileSync(detailFile)),detailDeviceScaleFactor:2,detailClip:clip,sourceHashes:assembly.sourceHashes,nativeResources:assembly.nativeResources});console.log(JSON.stringify({theme:theme.id,pass:result.pass,failed:result.checks.filter(c=>!c.pass)}));
 }
 const cards=report.themes.map(t=>`<a class="card" href="${String(t.number).padStart(2,'0')}_${t.id}.png"><h2>${String(t.number).padStart(2,'0')} ${t.name}</h2><img src="${String(t.number).padStart(2,'0')}_${t.id}_detail.png"><p>相同队伍上限 N6<br>点击查看完整画面</p></a>`).join('');
 const html=`<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>难度选择 · 五版官方组件方案</title><style>*{box-sizing:border-box}body{margin:0;padding:30px;background:#11191f;color:#dce4e9;font-family:"Microsoft YaHei",sans-serif}h1{font-size:28px;margin:0 0 12px}.note{color:#94aab6;font-size:14px;margin:0 0 24px}.grid{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:18px}.card{display:block;background:#1b2830;border:1px solid #60727c;color:inherit;text-decoration:none}h2{font-size:17px;margin:16px;min-height:24px}img{display:block;width:295px;max-width:100%;height:auto;margin:auto}p{font-size:13px;margin:12px 16px;color:#a6bac5;line-height:1.7}</style><h1>难度选择 · 5 版 Dota 2 官方组件</h1><p class="note">真实项目 XML / JS / CSS，独立比较原生底板、边框和行控件。01 为默认实现；其余为待选材质方案。局部采用2倍设备密度重新渲染，无截图放大；进度为本机样例，未进行游戏实机验证。</p><main class="grid">${cards}</main></html>`;
 fs.writeFileSync(path.join(docs,'index.html'),html);await b.call('Emulation.setDeviceMetricsOverride',{width:1920,height:1000,deviceScaleFactor:1,mobile:false});await b.go(path.join(docs,'index.html'));const height=await b.run('Math.ceil(document.querySelector("main").getBoundingClientRect().bottom+40)');await b.shot(path.join(docs,'overview.png'),1920,height);
 await b.call('Emulation.setDeviceMetricsOverride',{width:1280,height:720,deviceScaleFactor:1,mobile:false});await b.go(path.join(base,'reborn/index.html'));await b.run('previewReady');const compact=await b.run(measure);await b.shot(path.join(docs,'01_reborn_720.png'),1280,720);report.checks.push({name:'1280x720 Reborn',...compact});
 report.pass=report.themes.every(t=>t.pass)&&report.checks.every(c=>c.pass);report.at=new Date().toISOString();fs.writeFileSync(path.join(__dirname,'difficulty_capture_report.json'),JSON.stringify(report,null,2));if(!report.pass)process.exitCode=2;
 console.log(JSON.stringify({pass:report.pass,themes:report.themes.length,compact:compact.pass}));
 }finally{b.close();}})().catch(e=>{console.error(e.stack);fs.writeFileSync(path.join(__dirname,'difficulty_capture_report.json'),JSON.stringify({...report,error:e.stack,pass:false},null,2));process.exitCode=1;});
