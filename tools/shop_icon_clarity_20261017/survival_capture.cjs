'use strict';
// Read-only native-size browser screenshots of actual production card images.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {pathToFileURL}=require('node:url');
const {browser,sleep}=require('../vip_bundle_icons_20261017/browser.cjs');
const root=path.resolve(__dirname,'../..');process.chdir(root);
const out='design_refs/shop_icon_clarity_20261017/survival_preview';
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const arg=name=>{const i=process.argv.indexOf(name);return i<0?null:process.argv[i+1];};
const probe=process.argv.includes('--probe');
(async()=>{
 const assembly=JSON.parse(fs.readFileSync(out+'/assembly.json','utf8'));
 if(arg('--expected-hash'))assert.equal(assembly.registryHash,arg('--expected-hash'));
 const b=await browser(),report={kind:'survival_shop_production_image_capture',notGameCapture:true,
  registryHash:assembly.registryHash,views:[],products:[],screens:[]};
 try{
  await b.call('Emulation.setDeviceMetricsOverride',{width:1920,height:1080,deviceScaleFactor:1,mobile:false});
  async function screen(name,width=1920,height=1080){const file=out+'/screens/'+name+'.png';await b.shot(file,width,height);report.screens.push({path:file,sha256:sha(fs.readFileSync(file))});}
  async function clip(file,rect){
   const x=Math.max(0,Math.floor(rect.x)),y=Math.max(0,Math.floor(rect.y));
   const result=await b.call('Page.captureScreenshot',{format:'png',clip:{x,y,width:Math.ceil(rect.right)-x,height:Math.ceil(rect.bottom)-y,scale:1}});
   fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,Buffer.from(result.data,'base64'));
  }
  for(const category of ['equipment','other','challenge']){
   await b.go(out+'/index.html','?page=shop&category='+category);
   assert.equal(await b.run('previewReady'),true);
   await sleep(600);
   const view=await b.run(`(()=>{const cards=nodes.CustomShopWindow.FindChildrenWithClassTraverse('ShopShelfSlot');return {category:${JSON.stringify(category)},errors:previewErrors,calls:previewCalls,cards:cards.map(p=>({id:p.GetAttributeString('entry_id',''),rect:p.el.getBoundingClientRect().toJSON(),image:p.el.querySelector('.ShopItemIcon').src})),window:nodes.CustomShopWindow.el.getBoundingClientRect().toJSON()};})()`);
   report.views.push(view);assert(view.cards.length>0,'Actual production tab must render cards');
   assert(!view.calls.some(c=>/purchase|checkout|draw|claim/.test(c.name||c.method||'')),'Read-only preview must not transact');
   await screen(category+'_1920x1080');
   for(const row of view.cards){
    const image=await b.run(`(async()=>{
     const p=nodes.CustomShopWindow.FindChildrenWithClassTraverse('ShopShelfSlot').find(x=>x.GetAttributeString('entry_id','')===${JSON.stringify(row.id)});
     p.el.scrollIntoView({block:'center',inline:'nearest'});syncLayout();p.events.onmouseover();syncLayout();
     await Promise.all([...p.el.querySelectorAll('img'),...nodes.ShopTooltipIconHost.el.querySelectorAll('img')].map(i=>i.decode()));
     await new Promise(r=>setTimeout(r,70));syncLayout();
     const info=i=>({uri:i.src,natural:[i.naturalWidth,i.naturalHeight],rect:i.getBoundingClientRect().toJSON(),fit:getComputedStyle(i).objectFit});
     return {entry_id:${JSON.stringify(row.id)},category:${JSON.stringify(category)},title:nodes.ShopTooltipTitle.text,
      resource:cfg.SurvivalItemResources.Lookup({entry_id:${JSON.stringify(row.id)}}),
      card:info(p.el.querySelector('.ShopItemIcon')),tooltip:info(nodes.ShopTooltipIconHost.el.querySelector('.ShopTooltipMainIcon'))};
    })()`);
    for(const icon of [image.card,image.tooltip]){
     assert.equal(icon.fit,'cover');assert(icon.natural.every(n=>n>0),'Visible image must decode');
     assert(icon.rect.width>=80&&icon.rect.height>=80,'Inspect actual production icon at its real large size');
     if(!probe)assert(Math.min(...icon.natural)>=Math.ceil(Math.min(icon.rect.width,icon.rect.height)),
      'No low-resolution source enlargement: '+image.entry_id+' '+icon.natural+' -> '+icon.rect.width+'x'+icon.rect.height);
    }
    assert.equal(image.card.uri,image.tooltip.uri,'Card and tooltip must show the same source');
    image.card_capture=out+'/products/'+row.id+'_card.png';image.tooltip_capture=out+'/products/'+row.id+'_tooltip.png';
    await clip(image.card_capture,image.card.rect);await clip(image.tooltip_capture,image.tooltip.rect);
    report.products.push(image);
   }
   await screen(category+'_tooltip_1920x1080');
  }
  const expected=require('../shop_ui_12h/catalog.cjs').csv('data/csv/商店系统/shop_entries.csv').filter(r=>r.enabled==='1').map(r=>r.shop_entry_id).sort();
  assert.deepEqual(report.products.map(r=>r.entry_id).sort(),expected,'Every formal product is captured');
  await b.call('Emulation.setDeviceMetricsOverride',{width:1280,height:720,deviceScaleFactor:1,mobile:false});
  report.compact=[];
  for(const category of ['equipment','other','challenge']){
   await b.go(out+'/index.html','?page=shop&category='+category);assert.equal(await b.run('previewReady'),true);await sleep(500);
   const compact=await b.run(`(()=>{const rows=nodes.CustomShopWindow.FindChildrenWithClassTraverse('ShopShelfSlot').map(p=>p.el.getBoundingClientRect().toJSON());return {category:${JSON.stringify(category)},errors:previewErrors,rows,firstRow:rows.filter(r=>Math.abs(r.y-rows[0].y)<1).length};})()`);
   assert.deepEqual(compact.errors,[]);assert.equal(compact.firstRow,4,'Compact production layout keeps four columns');report.compact.push(compact);
   await screen(category+'_1280x720',1280,720);
  }
  // Contact sheet is composed only of exact screenshot crops above. Each is
  // displayed at its captured pixel size; it does not imitate the shop layout.
  const sheet=out+'/contact_sheet.html';
  fs.writeFileSync(sheet,'<!doctype html><meta charset="utf-8"><style>*{box-sizing:border-box}body{margin:0;background:#151924;color:#ddd;font:13px Arial}h1{font:18px Arial;margin:14px}p{margin:14px;font:12px Arial;color:#aab}main{display:grid;grid-template-columns:repeat(4,245px);gap:4px;margin:14px}.cell{height:146px;background:#242833;padding:8px}.name{height:24px;white-space:nowrap;overflow:hidden}.icons{display:flex;gap:20px;align-items:start}img{object-fit:none;max-width:none;max-height:none}.caption{font:10px Arial;color:#aaa}</style><h1>生存商店：31 商品原始像素检查</h1><p>真实生产组件截图裁切；左为商品卡，右为Tooltip；浏览器预览，非游戏截图；未放大截图。</p><main>'+report.products.map(row=>'<div class="cell"><div class="name">'+row.title.replaceAll('&','&amp;').replaceAll('<','&lt;')+'</div><div class="icons"><div><img src="'+pathToFileURL(path.resolve(row.card_capture)).href+'"><div class="caption">Card '+row.card.rect.width.toFixed(1)+' px</div></div><div><img src="'+pathToFileURL(path.resolve(row.tooltip_capture)).href+'"><div class="caption">Tooltip '+row.tooltip.rect.width.toFixed(1)+' px</div></div></div></div>').join('')+'</main>');
  await b.call('Emulation.setDeviceMetricsOverride',{width:1024,height:1370,deviceScaleFactor:1,mobile:false});await b.go(sheet);
  await screen('all_31_actual_pixel_contact_sheet',1024,1370);
  report.status=probe?'probe_only':'pass';report.contact_sheet=out+'/screens/all_31_actual_pixel_contact_sheet.png';
  fs.writeFileSync(out+'/capture.json',JSON.stringify(report,null,2)+'\n');
  console.log('SURVIVAL_SHOP_ICONS_'+(probe?'PROBE':'PASS')+' '+report.products.length+' products; '+report.contact_sheet);
 }finally{b.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
