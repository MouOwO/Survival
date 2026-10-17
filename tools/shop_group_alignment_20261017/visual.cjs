'use strict';
// Actual production market components in a local browser adapter. No game input,
// account traffic, checkout, save changes, reward grants, or production writes.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const assert=require('node:assert/strict'),{spawnSync}=require('node:child_process');
const {pathToFileURL}=require('node:url');
const {browser,sleep}=require('../shop_ui_12h/cdp.cjs');
const repo=path.resolve(__dirname,'../..'),out=path.join(repo,'output/shop_group_alignment_20261017');
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
 html=html.replace(/(<div id="PreviewCaption">)[\s\S]*?(<\/div>)/,'$1商城名称与价格整组居中 · 正式组件和商品数据 · 本地 VIP12 样例 · 非实机截图$2');
 fs.writeFileSync(entry,html);
 return {sources:frozen,catalogs:{path:catalogsPath,sha256:hash(catalogsPath)},entrySha256:hash(entry)};
}
const inspect=String.raw`(()=>{
 function rect(element){const r=element.getBoundingClientRect();return{x:r.x,y:r.y,width:r.width,height:r.height,right:r.right,bottom:r.bottom,cx:r.x+r.width/2,cy:r.y+r.height/2};}
 function textRect(panel){const range=document.createRange();range.selectNodeContents(panel.el);return rect({getBoundingClientRect:()=>range.getBoundingClientRect()});}
 function union(rects){const x=Math.min(...rects.map(r=>r.x)),y=Math.min(...rects.map(r=>r.y)),right=Math.max(...rects.map(r=>r.right)),bottom=Math.max(...rects.map(r=>r.bottom));return{x,y,right,bottom,width:right-x,height:bottom-y,cx:(x+right)/2,cy:(y+bottom)/2};}
 function authoredPosition(panel){return Object.hasOwn(panel._style,'position')?panel._style.position:null;}
 const market=cfg.SurvivalBlackLionMarket.GetWindow(),windowBounds=rect(market.panel.el),scale=windowBounds.width/1380;
 const heading=market.panel.FindChildrenWithClassTraverse('BLMarketPriceHeading')[0];
 const rows=window.groupAlignmentSamples.map(({row,item,index})=>{
  const name=row.__menuCell.namePanel,owned=row.__menuCell.countPanel,names=row.FindChildrenWithClassTraverse('BLMarketNameColumnStack')[0];
  const price=row.FindChildrenWithClassTraverse('BLMarketRowPrice')[0],stack=row.FindChildrenWithClassTraverse('BLMarketRowPriceStack')[0];
  const line=row.FindChildrenWithClassTraverse('BLMarketPriceLine')[0],icon=row.FindChildrenWithClassTraverse('BLMarketPriceCurrency')[0];
  const main=row.FindChildrenWithClassTraverse('BLMarketPriceMain')[0],secondary=row.FindChildrenWithClassTraverse('BLMarketPriceSecondary')[0];
  const rb=rect(row.el),ib=rect(icon.el),mg=textRect(main),sg=secondary.visible?textRect(secondary):null,ng=textRect(name),og=owned.visible?textRect(owned):null;
  const mainGlyphUnion=union([ib,mg]),priceGlyphUnion=union([mainGlyphUnion,...sg?[sg]:[]]),nameGlyphUnion=union([ng,...og?[og]:[]]);
  return{index,sku:item.sku,name:item.title,owned:Number(item.owned),kind:secondary.visible?'u_coin_with_rmb':'points_single_line',row:rb,
   names:rect(names.el),nameLabel:rect(name.el),nameGlyphUnion,nameGlyphs:ng,ownedGlyphs:og,priceColumn:rect(price.el),stack:rect(stack.el),line:rect(line.el),
   icon:ib,mainGlyphs:mg,mainGlyphUnion,secondaryGlyphs:sg,priceGlyphUnion,
   authoredPositions:Object.fromEntries([['names',names],['name',name],['owned',owned],['stack',stack],['line',line],['icon',icon],['main',main],['secondary',secondary]].map(([key,panel])=>[key,authoredPosition(panel)]))};
 });
 return{windowBounds,scale,heading:{bounds:rect(heading.el),glyphs:textRect(heading),authoredPosition:authoredPosition(heading)},rows,errors:previewErrors,
  missingImages:[...document.querySelectorAll('.BLMarketWindow img')].filter(image=>!image.complete||!image.naturalWidth).map(image=>image.src),
  transactions:previewCalls.filter(row=>row.method==='paid'||row.method==='wallet'||row.name==='survival_commerce_request'&&row.payload.action==='purchase'||row.name==='survival_payment_request'&&row.payload.action==='create')};
})()`;
async function main(){
 const assembly=assemble(),report={kind:'actual_production_market_name_and_price_group_geometry',notGameCapture:true,noAccountSaveOrOrderWrites:true,assembly,scenarios:[],
  limitations:['The browser adapter approximates native Panorama flow and fonts. Screenshots and geometry are component previews, not live Dota verification.',
   'The actual production Row factory renders unchanged formal product metadata with copied local owned=0/3 fixtures. This deliberately bypasses storefront filtering so owned-only layout remains measurable without granting or buying a product.',
   'Vertical assertions use the complete flow group bounds. Font glyph ranges are also recorded; browser font ascenders/descenders extend beyond authored line-height, so glyph-center offsets are reported separately.']};
 function stable(){for(const row of assembly.sources)assert.equal(sourceHash(row.path),row.sha256,'Source remains equal to frozen preview '+row.path);}
 stable();let timer;
 const b=await Promise.race([browser(),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('Local Chrome/CDP connection timed out; run the read-only preview with process permission.')),30000);})]).finally(()=>clearTimeout(timer));
 try{
  await b.call('Network.enable');await b.call('Network.setBlockedURLs',{urls:['http://*','https://*']});
  for(const[width,height]of[[1920,1080],[1280,720]])for(const owned of[0,3]){
   await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
   await b.go(entry,'?page=commerce&category=all');assert.equal(await b.run('marketGeometryReady'),true);
   const fixture=await b.run(`(()=>{
    const market=cfg.SurvivalBlackLionMarket.GetWindow(),paid=PREVIEW_FIXTURE.commerce.paid,wallet=PREVIEW_FIXTURE.commerce.wallet;
    const coin=paid.products.find(item=>item.enabled&&item.u_coin_price>0&&item.amount_fen>0),points=wallet.products.filter(item=>item.enabled&&item.currency==='shop_points');
    const point=points.find(item=>item.title==='箭塔改造')||points[0];if(!coin||!point)throw Error('Required formal price kinds are missing');
    market.content.RemoveAndDeleteChildren();const host=$.CreatePanel('Panel',market.content,'GroupAlignmentRows');host.AddClass('BLMarketRows');
    window.groupAlignmentSamples=[];for(let i=0;i<7;i++){
     const source=i%2?points[(Math.floor(i/2))%points.length]:coin,item={...source,owned:${owned}},catalog=i%2?wallet:paid;
     const row=cfg.SurvivalBlackLionMarket.Row(host,item,{index:i,rewards:item.reward_lines||[],catalog,action(){throw Error('This geometry preview cannot submit transactions');}});
     groupAlignmentSamples.push({row,item,index:i});
    }
    syncLayout();return{owned:${owned},sourceProducts:groupAlignmentSamples.map(({item,index})=>({sku:item.sku,title:item.title,index,owned:item.owned,amount_fen:item.amount_fen,price:item.price,u_coin_price:item.u_coin_price}))};
   })()`);
   await b.run('Promise.all([...document.images].map(image=>image.decode().catch(()=>false))).then(()=>{syncLayout();return true;})');
   const scene=await b.run(inspect);scene.viewport=[width,height];scene.fixture=fixture;
   assert.deepEqual(scene.errors,[]);assert.deepEqual(scene.transactions,[]);assert.equal(scene.rows.length,7);
   assert.deepEqual([...new Set(scene.rows.map(row=>row.kind))].sort(),['points_single_line','u_coin_with_rmb']);
   assert.equal(scene.heading.authoredPosition,null,'Heading caption has no authored absolute position');
   for(const row of scene.rows){
    const scaled=value=>value/scene.scale;
    row.deltas={nameGroupY:scaled(row.names.cy-row.row.cy),priceGroupY:scaled(row.stack.cy-row.row.cy),nameGlyphY:scaled(row.nameGlyphUnion.cy-row.row.cy),priceGlyphY:scaled(row.priceGlyphUnion.cy-row.row.cy),
     titleToMainGlyphX:scaled(row.mainGlyphUnion.cx-scene.heading.glyphs.cx),titleToSecondaryGlyphX:row.secondaryGlyphs?scaled(row.secondaryGlyphs.cx-scene.heading.glyphs.cx):null};
    assert(Math.abs(row.deltas.nameGroupY)<.15,'Complete name/owned group centers vertically '+row.index);
    assert(Math.abs(row.deltas.priceGroupY)<.15,'Complete price group centers vertically '+row.index);
    assert(Math.abs(row.deltas.titleToMainGlyphX)<.8,'Currency icon and actual amount glyphs center under the title '+row.index);
    if(row.secondaryGlyphs)assert(Math.abs(row.deltas.titleToSecondaryGlyphX)<.8,'Actual RMB glyphs share the title center '+row.index);
    assert.equal(row.owned,owned);assert.equal(!!row.ownedGlyphs,owned>0,'Ownership line follows local sample');
    assert(row.nameLabel.right<=row.priceColumn.x-19*scene.scale+.5,'Names retain a20px gap before the price');
    assert(Math.abs(scaled(row.priceColumn.x-row.row.x)-825)<.1,'Earlier100px price move is retained');
    for(const[key,value]of Object.entries(row.authoredPositions))assert.equal(value,null,'Flow content has no authored position: '+key);
   }
   scene.knownNativeTextureAliases=scene.missingImages.filter(file=>/\/(?:gold_large_png|ticket_illustrated_png|gift_light_png)\.png$/.test(file)||/\/control_icons\/24px\/plus\.svg$/.test(file));
   assert.deepEqual(scene.missingImages.filter(file=>!scene.knownNativeTextureAliases.includes(file)),[],'Product assets decode');
   scene.screenshot=path.relative(repo,path.join(out,'groups_owned_'+owned+'_'+width+'x'+height+'.png')).replaceAll('\\','/');
   await b.shot(scene.screenshot,{x:0,y:0,width,height});report.scenarios.push(scene);
  }
  stable();report.status='PASS';
 }catch(error){report.status='FAIL';report.failure=error.stack;try{report.previewErrors=await b.run('previewErrors');await b.shot(path.join(out,'failure.png'));}catch{}throw error;}
 finally{b.close();fs.writeFileSync(path.join(out,'visual_report.json'),JSON.stringify(report,null,2)+'\n');}
 console.log('SHOP_GROUP_ALIGNMENT_VISUAL_PASS '+JSON.stringify({scenarios:report.scenarios.length,rows:report.scenarios.reduce((sum,scene)=>sum+scene.rows.length,0),report:path.relative(repo,path.join(out,'visual_report.json'))}));
}
main().catch(error=>{console.error(error.stack||error);process.exitCode=1;});
