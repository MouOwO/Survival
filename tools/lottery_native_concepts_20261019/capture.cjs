'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'../..'),out=path.join(root,'output/lottery_native_concepts_20261019'),dest=path.join(root,'docs/design/lottery_native_concepts_20261019');
const assembly=JSON.parse(fs.readFileSync(path.join(out,'assembly.json'),'utf8')),screens=[];
fs.mkdirSync(dest,{recursive:true});
const inspect=`(()=>{const rect=selector=>{const e=document.querySelector(selector),r=e.getBoundingClientRect(),s=getComputedStyle(e);return{selector,x:r.x,y:r.y,right:r.right,bottom:r.bottom,width:r.width,height:r.height,text:e.textContent.trim(),backgroundImage:s.backgroundImage,borderImage:s.borderImageSource};};return{theme:document.body.dataset.theme,window:rect('.window'),wallet:rect('.wallet'),close:rect('.close'),chest:rect('.hero-treasure'),rewards:[...document.querySelectorAll('.reward')].map((e,i)=>rect('.reward:nth-child('+(i+1)+')')),single:rect('.secondary'),ten:rect('.primary'),tabs:[...document.querySelectorAll('.pool')].map((e,i)=>rect('.pool:nth-child('+(i+1)+')')),selected:document.querySelectorAll('.pool.selected').length,images:[...document.images].map(e=>({src:e.src,decoded:e.complete&&e.naturalWidth>0})),textOverflows:[...document.querySelectorAll('.pool span,.reward-name,.draw>span')].filter(e=>e.scrollWidth>e.clientWidth+1).map(e=>e.textContent)};})()`;
const within=(a,b)=>a.x>=b.x-1&&a.y>=b.y-1&&a.right<=b.right+1&&a.bottom<=b.bottom+1;
const overlap=(a,b)=>Math.min(a.right,b.right)>Math.max(a.x,b.x)+1&&Math.min(a.bottom,b.bottom)>Math.max(a.y,b.y)+1;
async function check(b,t,width,height,file){
 await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
 await b.go(path.join(out,'render/index.html'),'?theme='+t.id);await b.run('conceptReady');
 await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:width-1,y:height-1});
 const s=await b.run(inspect);assert.equal(s.theme,t.id);assert.equal(s.selected,1);assert.equal(s.rewards.length,8);assert.equal(s.tabs.length,4);
 assert(s.images.every(i=>i.decoded),'All official and content images decode');assert.deepEqual(s.textOverflows,[],'Titles and action text fit');
 const screen={x:0,y:0,right:width,bottom:height};assert(within(s.window,screen));
 for(const n of [s.wallet,s.close,s.chest,s.single,s.ten,...s.rewards,...s.tabs])assert(within(n,s.window),'Component stays inside window: '+n.selector);
 assert(!overlap(s.wallet,s.close),'Balance group clears close');assert(!overlap(s.single,s.ten),'Draw buttons are separate');
 for(const r of s.rewards){assert(!overlap(r,s.single)&&!overlap(r,s.ten),'Prizes clear draw buttons');assert(!overlap(r,s.chest),'Prizes clear central treasure');}
 if(file)await b.shot(file,width,height);
 return{...s,viewport:{width,height},file:file&&path.relative(root,file).replaceAll('\\','/'),sha256:file&&crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')};
}
function gallery(){
 const tiles=assembly.themes.map(t=>'<a class="tile" href="'+t.number+'_'+t.id+'.png" target="_blank"><div class="label"><span>'+t.number+'</span><strong>'+t.name+'</strong><small>'+t.description+'</small></div><img src="'+t.number+'_'+t.id+'.png" alt="'+t.name+'"></a>').join('');
 const html='<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>抽卡界面 · 五套官方组件方案</title><style>*{box-sizing:border-box}body{margin:0;background:#10151a;color:#e6e3d9;font-family:"Microsoft YaHei",sans-serif;padding:42px}h1{font-size:31px;font-weight:500;letter-spacing:2px;margin:0 0 9px}p{margin:0;color:#9ea9ac;font-size:16px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:30px 24px;margin-top:30px}.tile{display:block;min-width:0;color:inherit;text-decoration:none;border:1px solid #78888c44;background:#192128;box-shadow:0 7px 20px #0003}.tile img{width:100%;height:auto;display:block}.label{height:57px;display:flex;align-items:center;padding:0 17px;gap:12px}.label>span{color:#d8c59b;font-family:Georgia;font-size:21px}.label strong{font-size:20px;font-weight:500;white-space:nowrap}.label small{font-size:12px;color:#97a6aa;margin-left:auto}.tile:nth-child(5){grid-column:1/-1;width:calc(50% - 12px);justify-self:center}.tile:hover{border-color:#ccbe92}.note{margin-top:24px;text-align:center;font-size:14px;color:#88979d}@media(max-width:1000px){body{padding:22px}.grid{grid-template-columns:1fr}.tile:nth-child(5){grid-column:auto;width:100%}.label small{display:none}}</style><h1>抽卡界面 · 五套官方组件方案</h1><p>Dota 2 原生素材拼装，参考激战 2 信息布局；统一龙骑宝箱、余额与奖励内容。</p><div class="grid">'+tiles+'</div><div class="note">点开单张图片查看完整细节 · 离线界面方案预览</div></html>';
 fs.writeFileSync(path.join(dest,'index.html'),html);
}
(async()=>{const b=await require('./browser.cjs').browser();try{
 for(const t of assembly.themes){const file=path.join(dest,t.number+'_'+t.id+'.png');screens.push(await check(b,t,1920,1080,file));console.log('CONCEPT_CAPTURED '+t.number+' '+t.name);}
 const compact=[];for(const t of assembly.themes)compact.push(await check(b,t,1280,720,null));
 gallery();await b.call('Emulation.setDeviceMetricsOverride',{width:1600,height:1800,deviceScaleFactor:1,mobile:false});await b.go(path.join(dest,'index.html'));
 const height=await b.run('Math.ceil(document.documentElement.scrollHeight)');await b.shot(path.join(dest,'overview.png'),1600,height);
 const report={status:'PASS_OFFLINE_CONCEPTS',kind:'five_native_component_lottery_designs',gameVerified:false,productionModified:false,assembly,screens,compactChecks:compact,overview:{path:'docs/design/lottery_native_concepts_20261019/overview.png',width:1600,height},layoutReferences:['https://wiki.guildwars2.com/wiki/Black_Lion_Chest/historical_7','https://wiki.guildwars2.com/wiki/File:Black_Lion_Trading_Company_interface.jpg'],checks:['Five different native component families, same configured pool, balance and eight rewards','Every texture/illustration resolves locally; source hashes verified during assembly','1920x1080 and 1280x720: no component clips, balance/Close overlap, draw-button overlap or prize/chest overlap','Explicit preview only: no game controller, network, purchase or draw event is loaded'],limitations:['Static design concepts are browser-rendered; these are not native in-game screenshots.','The native treasure chest is preview art. Existing addon scene, reward and user ticket illustrations remain game content.']};
 fs.writeFileSync(path.join(out,'capture_report.json'),JSON.stringify(report,null,2)+'\n');console.log('FIVE_NATIVE_CONCEPTS_PASS 5 full screenshots, 5 compact geometry checks, comparison and gallery');
 }finally{b.close();}})().catch(error=>{console.error(error);process.exitCode=1;});
