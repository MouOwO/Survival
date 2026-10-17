'use strict';
// Actual production market components in a local browser adapter. No game input,
// account traffic, checkout, save changes, reward grants, or production writes.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const assert=require('node:assert/strict'),{spawnSync}=require('node:child_process');
const {pathToFileURL}=require('node:url');
const {browser,sleep}=require('../shop_ui_12h/cdp.cjs');
const repo=path.resolve(__dirname,'../..'),out=path.join(repo,'output/shop_row_price_20261017');
const preview=path.join(out,'preview'),entry=path.join(preview,'index.html');
process.chdir(repo);fs.mkdirSync(out,{recursive:true});
const sha=value=>crypto.createHash('sha256').update(value).digest('hex');
const hash=file=>sha(fs.readFileSync(file));
const sourceHash=file=>sha(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,''));
const readJson=file=>JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,''));
function field(input,key,stop){const start=input.indexOf(key)+key.length,end=input.indexOf(stop,start);assert(start>=key.length&&end>start,'Frozen preview field '+key);return JSON.parse(input.slice(start,end));}
function replace(input,key,stop,value){const start=input.indexOf(key)+key.length,end=input.indexOf(stop,start);return input.slice(0,start)+JSON.stringify(value).replaceAll('</script','<\\/script')+input.slice(end);}
function assemble(){
 const built=spawnSync(process.execPath,['tools/menus_v10/preview.cjs','--out',path.relative(repo,preview)],{encoding:'utf8',windowsHide:true});
 if(built.status!==0)throw Error(built.stdout+built.stderr);
 let html=fs.readFileSync(entry,'utf8');
 const sources=field(html,'window.PREVIEW_SOURCES=',';window.PREVIEW_FIXTURE=');
 const frozen=['scripts/custom_game/black_lion_market.js','styles/custom_game/black_lion_market.css'].map(relative=>({path:'panorama/src/'+relative,sha256:sha(sources[relative])}));
 const catalogsPath='output/shop_icon_quality_20261017/catalogs.json',catalogs=readJson(catalogsPath);
 function wire(raw,payment){const grants=raw.grants||{},pricing=grants.pricing||{};return {...raw,owned:0,
  amount_fen:raw.amount_fen??raw.amount,purchase_method:payment?'cash':raw.purchase_method,
  u_coin_price:raw.u_coin_price??pricing.u_coin_price,u_coin_per_yuan:raw.u_coin_per_yuan??pricing.u_coin_per_yuan,
  required_vip_level:Number(grants.required_vip_level)||0,reward_lines:grants.lines||raw.reward_lines||[]};}
 const fixture=field(html,'window.PREVIEW_FIXTURE=',';window.PREVIEW_SOURCE_ROOT=');
 fixture.commerce={paid:{...catalogs.payment,catalog_hash:'FORMAL_COMPILER_LOCAL_VIP12_LAYOUT_SAMPLE',products:catalogs.payment.products.map(row=>wire(row,true))},
  wallet:{...catalogs.wallet,products:catalogs.wallet.products.map(row=>wire(row,false)),balances:{u_coin:999999,shop_points:999999,shop_gold:999999}}};
 html=replace(html,'window.PREVIEW_FIXTURE=',';window.PREVIEW_SOURCE_ROOT=',fixture);
 const aliases=field(html,'window.PREVIEW_ASSET_PATHS=',';window.PREVIEW_BASELINE=');
 const oldPreview='output/shop_icon_clarity_20261017/preview/index.html';
 if(fs.existsSync(oldPreview))Object.assign(aliases,field(fs.readFileSync(oldPreview,'utf8'),'window.PREVIEW_ASSET_PATHS=',';window.PREVIEW_BASELINE='));
 const master=readJson('data/ui/item_resources.json');
 for(const row of master.items){const match=String(row.uri||'').match(/^s2r:\/\/panorama\/images\/(.+)\.vtex$/);if(!match)continue;
  const candidates=[match[1].replace(/_png$/,'')+'.png',match[1]+'.png'];
  const file=candidates.flatMap(relative=>['art/ui/sources/','panorama/src/images/'].map(root=>root+relative)).find(file=>fs.existsSync(file));
  if(file)aliases[row.uri]=pathToFileURL(path.resolve(file)).href;
 }
 html=replace(html,'window.PREVIEW_ASSET_PATHS=',';window.PREVIEW_BASELINE=',aliases);
 // Preserve the authored native cover-scaling mode in this browser-only adapter.
 fs.writeFileSync(path.join(preview,'adapter.js'),fs.readFileSync('tools/archive_v10/adapter.js','utf8').replace("v==='stretch-to-fit'?'fill':'contain'","v==='stretch-to-fit'?'fill':v==='stretch-to-cover-preserve-aspect'?'cover':'contain'"));
 html=html.replace(/<script src="[^"]*tools\/archive_v10\/adapter\.js"><\/script>/,'<script src="adapter.js"></script>');
 fs.writeFileSync(path.join(preview,'state.js'),fs.readFileSync('tools/menus_v10/state.js','utf8')+String.raw`
window.marketGeometryReady=previewReady.then(async function(ok){
 if(!ok)return false;
 cfg.SurvivalCommerceView.UpdateCatalog(PREVIEW_FIXTURE.commerce.paid);
 cfg.SurvivalCommerceView.UpdateWalletCatalog(PREVIEW_FIXTURE.commerce.wallet);
 cfg.SurvivalCommerceView.SelectCategory(params.get('category')||'all');
 await document.fonts.ready;await Promise.all([...document.images].map(image=>image.decode().catch(()=>false)));syncLayout();return true;
});
`);
 html=html.replace(/<script src="[^"]*tools\/menus_v10\/state\.js"><\/script>/,'<script src="state.js"></script>');
 html=html.replace(/(<div id="PreviewCaption">)[\s\S]*?(<\/div>)/,'$1商城横条与价格列 · 正式组件和商品数据 · 本地 VIP12 样例 · 非实机截图$2');
 fs.writeFileSync(entry,html);
 return {sources:frozen,catalogs:{path:catalogsPath,sha256:hash(catalogsPath)},entrySha256:hash(entry)};
}
const inspect=String.raw`(()=>{
 function rect(element){const r=element.getBoundingClientRect();return{x:r.x,y:r.y,width:r.width,height:r.height,right:r.right,bottom:r.bottom,cx:r.x+r.width/2,cy:r.y+r.height/2};}
 function textRect(element){const range=document.createRange();range.selectNodeContents(element);return rect({getBoundingClientRect:()=>range.getBoundingClientRect()});}
 const market=cfg.SurvivalBlackLionMarket.GetWindow(),windowBounds=rect(market.panel.el),scale=windowBounds.width/1380;
 const heading=market.panel.FindChildrenWithClassTraverse('BLMarketPriceHeading')[0],view=cfg.SurvivalCommerceView.Inspect();
 const rows=market.content.FindChildrenWithClassTraverse('BLMarketRow').map((row,index)=>{
  const price=row.FindChildrenWithClassTraverse('BLMarketRowPrice')[0],line=row.FindChildrenWithClassTraverse('BLMarketPriceLine')[0];
  const icon=row.FindChildrenWithClassTraverse('BLMarketPriceCurrency')[0],main=row.FindChildrenWithClassTraverse('BLMarketPriceMain')[0];
  const secondary=row.FindChildrenWithClassTraverse('BLMarketPriceSecondary')[0],wash=row.FindChildrenWithClassTraverse('BLMarketRowWash')[0];
  const rb=rect(row.el),pb=rect(price.el),lb=rect(line.el),ib=rect(icon.el),mb=rect(main.el),secondaryBounds=rect(secondary.el);
  const contentLeft=Math.min(ib.x,mb.x),contentRight=Math.max(ib.right,mb.right),visible=rb.bottom>0&&rb.y<innerHeight;
  return{sku:view.visibleSkus[view.page*40+index],index,visible,row:rb,price:pb,line:lb,icon:ib,main:{...mb,text:main.text,glyphs:textRect(main.el)},
   secondary:{...secondaryBounds,text:secondary.text,visible:secondary.visible,glyphs:secondary.visible?textRect(secondary.el):null},
   name:rect(row.__menuCell.namePanel.el),buy:rect(row.FindChildrenWithClassTraverse('BLMarketBuy')[0].el),
   priceX:(pb.x-rb.x)/scale,priceWidth:pb.width/scale,mainGroupCenter:(contentLeft+contentRight)/2,
   wash:{source:wash.el.src,bright:wash.BHasClass('BLMarketBrightRowWash'),brightness:Number(getComputedStyle(wash.el).getPropertyValue('--pano-brightness')),filter:getComputedStyle(wash.el).filter,natural:[wash.el.naturalWidth,wash.el.naturalHeight]}};
 });
 return{windowBounds,scale,heading:{bounds:rect(heading.el),glyphs:textRect(heading.el),text:heading.text},view,rows,errors:previewErrors,
  missingImages:[...document.querySelectorAll('.BLMarketWindow img')].filter(image=>!image.complete||!image.naturalWidth).map(image=>image.src),
  transactions:previewCalls.filter(row=>row.method==='paid'||row.method==='wallet'||row.name==='survival_commerce_request'&&row.payload.action==='purchase'||row.name==='survival_payment_request'&&row.payload.action==='create')};
})()`;
async function main(){
 const assembly=assemble(),report={kind:'actual_production_market_row_geometry',notGameCapture:true,noAccountSaveOrOrderWrites:true,assembly,scenarios:[],
  limitations:['Local browser adapter approximates native Panorama layout and fonts. Screenshots are component previews, not live Dota captures.','Products and prices come from a previously exported formal compiler catalog; eligibility, balances and ownership are isolated local fixture values.']};
 function stable(){for(const row of assembly.sources)assert.equal(sourceHash(row.path),row.sha256,'Source remains equal to frozen preview '+row.path);}
 stable();const b=await browser();
 try{
  await b.call('Network.enable');await b.call('Network.setBlockedURLs',{urls:['http://*','https://*']});
  for(const[width,height]of[[1920,1080],[1280,720]])for(const category of['all','bundles','vip']){
   await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
   await b.go(entry,'?page=commerce&category='+category);
   assert.equal(await b.run('marketGeometryReady'),true);await b.run('syncLayout()');
   const scene=await b.run(inspect);scene.viewport=[width,height];scene.category=category;
   assert.deepEqual(scene.errors,[]);assert.deepEqual(scene.transactions,[]);assert(scene.rows.length,'Formal goods present '+category);
   for(const row of scene.rows){
    assert(Math.abs(row.priceX-825)<.1,'Price column moves from925 to825: '+row.sku);
    assert(Math.abs(row.priceWidth-235)<.1,'Shared price column width');
    assert(Math.abs(scene.heading.bounds.cx-row.price.cx)<.25,'Heading and price column centers align '+row.sku);
    assert(Math.abs(scene.heading.glyphs.cx-row.price.cx)<1.1,'Visible price heading centers '+row.sku);
    assert(Math.abs(row.line.cx-row.price.cx)<.25,'Main price line centers '+row.sku);
    assert(Math.abs(row.mainGroupCenter-row.price.cx)<.65,'Currency icon and amount center as a group '+row.sku);
    if(row.secondary.visible){assert(Math.abs(row.secondary.cx-row.price.cx)<.25,'Secondary price column centers');assert(Math.abs(row.secondary.glyphs.cx-row.price.cx)<1.1,'Visible secondary price centers');}
    assert(row.name.right<=row.price.x-19*scene.scale+.5,'Long names reserve a20px gap before the price '+row.sku);
    assert(row.price.right<row.buy.x,'Price does not collide with purchase action '+row.sku);
    assert.equal(row.wash.brightness,row.wash.bright?1.45:1,'Only the lighter source stripe is brightened');
   }
   scene.knownNativeTextureAliases=scene.missingImages.filter(file=>/\/(?:gold_large_png|ticket_illustrated_png|gift_light_png)\.png$/.test(file)||/\/control_icons\/24px\/plus\.svg$/.test(file));
   assert.deepEqual(scene.missingImages.filter(file=>!scene.knownNativeTextureAliases.includes(file)),[],'No unrelated missing images');
   scene.screenshot=path.relative(repo,path.join(out,category+'_'+width+'x'+height+'.png')).replaceAll('\\','/');
   await b.shot(scene.screenshot,{x:0,y:0,width,height});
   const light=scene.rows.find(row=>row.wash.bright&&row.visible);assert(light,'A bright stripe is visible');
   const hoverPoint=[light.row.x+460*scene.scale,Math.min(height-20,light.row.cy)];
   await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:hoverPoint[0],y:hoverPoint[1]});await sleep(120);await b.run('syncLayout()');
   const hovered=await b.run(inspect),hoverRow=hovered.rows.find(row=>row.sku===light.sku);
   assert.equal(hoverRow.wash.brightness,1.55,'Bright stripe stays bright on hover');
   scene.hover={sku:light.sku,point:hoverPoint,brightness:hoverRow.wash.brightness};
   if(category==='all'){scene.hover.screenshot=path.relative(repo,path.join(out,'all_hover_'+width+'x'+height+'.png')).replaceAll('\\','/');await b.shot(scene.hover.screenshot,{x:0,y:0,width,height});}
   await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:3,y:3});await b.run('syncLayout()');
   report.scenarios.push(scene);
  }
  stable();report.status='PASS';
 }catch(error){report.status='FAIL';report.failure=error.stack;try{report.previewErrors=await b.run('previewErrors');await b.shot(path.join(out,'failure.png'));}catch{}throw error;}
 finally{b.close();fs.writeFileSync(path.join(out,'visual_report.json'),JSON.stringify(report,null,2)+'\n');}
 console.log('SHOP_ROW_PRICE_VISUAL_PASS '+JSON.stringify({scenarios:report.scenarios.length,screenshots:8,report:path.relative(repo,path.join(out,'visual_report.json'))}));
}
main().catch(error=>{console.error(error.stack||error);process.exitCode=1;});
