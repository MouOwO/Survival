'use strict';
// Actual production components with formal catalogs and explicit isolated state.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),crypto=require('node:crypto'),{pathToFileURL,fileURLToPath}=require('node:url');
const repo=path.resolve(__dirname,'../..');process.chdir(repo);
const out='output/shop_icon_clarity_20261017/preview';
const arg=name=>{const at=process.argv.indexOf(name);return at<0?null:process.argv[at+1];};
const hash=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const masterHash=hash('data/ui/item_resources.json');
if(!fs.readFileSync('panorama/src/scripts/custom_game/common/item_resources.js','utf8').includes('hash="'+masterHash+'"'))throw Error('Generate the current resource registry before building a visual snapshot');
fs.mkdirSync(out,{recursive:true});
const build=cp.spawnSync(process.execPath,['tools/menus_v10/preview.cjs','--out',out],{encoding:'utf8',windowsHide:true});
if(build.stdout)process.stdout.write(build.stdout);if(build.stderr)process.stderr.write(build.stderr);if(build.status!==0)process.exit(build.status||1);
const entry=out+'/index.html';let html=fs.readFileSync(entry,'utf8');
const sourceKey='window.PREVIEW_SOURCES=',sourceAt=html.indexOf(sourceKey)+sourceKey.length,sourceStop=html.indexOf(';window.PREVIEW_FIXTURE=',sourceAt);
const snapshotSources=JSON.parse(html.slice(sourceAt,sourceStop));
if(!snapshotSources['scripts/custom_game/common/item_resources.js'].includes('hash="'+masterHash+'"'))throw Error('Resource generator changed while the source graph was being frozen; rebuild after freeze');
function swapVariable(key,end,value){const at=html.indexOf(key)+key.length,stop=html.indexOf(end,at);if(at<key.length||stop<at)throw Error('Missing preview variable '+key);html=html.slice(0,at)+JSON.stringify(value).replaceAll('</script','<\\/script')+html.slice(stop);}
const catalogs=JSON.parse(fs.readFileSync('output/shop_icon_quality_20261017/catalogs.json','utf8').replace(/^\uFEFF/,''));
function wire(raw,payment){const grants=raw.grants||{},pricing=grants.pricing||{};return {...raw,owned:0,
 amount_fen:raw.amount_fen??raw.amount,purchase_method:payment?'cash':raw.purchase_method,
 u_coin_price:raw.u_coin_price??pricing.u_coin_price,u_coin_per_yuan:raw.u_coin_per_yuan??pricing.u_coin_per_yuan,
 required_vip_level:Number(grants.required_vip_level)||0,reward_lines:grants.lines||raw.reward_lines||[]};}
const fixtureStart='window.PREVIEW_FIXTURE=',fixtureEnd=';window.PREVIEW_SOURCE_ROOT=';
const start=html.indexOf(fixtureStart)+fixtureStart.length,stop=html.indexOf(fixtureEnd,start);
const fixture=JSON.parse(html.slice(start,stop));
fixture.commerce={paid:{...catalogs.payment,catalog_hash:'FORMAL_COMPILER_LOCAL_ACCOUNT_VIP12',products:catalogs.payment.products.map(r=>wire(r,true))},
 wallet:{...catalogs.wallet,products:catalogs.wallet.products.map(r=>wire(r,false)),balances:{u_coin:999999,shop_points:999999,shop_gold:999999}}};
swapVariable(fixtureStart,fixtureEnd,fixture);
const aliasStart='window.PREVIEW_ASSET_PATHS=',aliasEnd=';window.PREVIEW_BASELINE=';
const astart=html.indexOf(aliasStart)+aliasStart.length,astop=html.indexOf(aliasEnd,astart),aliases=JSON.parse(html.slice(astart,astop)),resolved=[];
function alias(uri,source){if(!uri||!source)return;const file=String(source).startsWith('file:')?fileURLToPath(source):path.resolve(source);if(!fs.existsSync(file))throw Error('Missing preview alias '+source);const url=pathToFileURL(file).href;aliases[uri]=url;if(uri.startsWith('file://{images}/'))aliases[uri.slice(16)]=url;resolved.push({uri,path:path.relative(repo,file).replaceAll('\\','/'),sha256:hash(file)});}
for(const file of (arg('--native-aliases')||'').split(';').filter(Boolean)){const data=JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,''));for(const[uri,source]of Object.entries(data.aliases||{}))alias(uri,typeof source==='string'?source:source.path||source.png);for(const row of data.records||data.rows||data.textures||[]){alias(row.uri||row.native_uri,row.previewPng||row.export_png||row.sourcePng||row.png||row.path||row.source);if(row.runtime&&row.runtimeSha256){if(hash(row.runtime)!==row.runtimeSha256)throw Error('Compiled texture differs from its exact decoded preview '+row.runtime);resolved.push({uri:'runtime:'+row.uri,path:row.runtime,sha256:row.runtimeSha256});}}}
const explicitAliases=new Set(resolved.map(row=>row.uri));
const master=JSON.parse(fs.readFileSync('data/ui/item_resources.json','utf8'));
for(const row of master.items){const match=String(row.uri||'').match(/^s2r:\/\/panorama\/images\/(.+)\.vtex$/);if(!match||explicitAliases.has(row.uri))continue;const candidates=[match[1].replace(/_png$/,'')+'.png',match[1]+'.png'];let source=candidates.flatMap(relative=>['art/ui/sources/','panorama/src/images/'].map(prefix=>prefix+relative)).find(f=>fs.existsSync(f));if(source)alias(row.uri,source);}
swapVariable(aliasStart,aliasEnd,aliases);
const adapter='tools/archive_v10/adapter.js';html=html.replace(pathToFileURL(path.resolve(adapter)).href,'adapter.js');
fs.writeFileSync(out+'/adapter.js',fs.readFileSync(adapter,'utf8').replace("v==='stretch-to-fit'?'fill':'contain'","v==='stretch-to-fit'?'fill':v==='stretch-to-cover-preserve-aspect'?'cover':'contain'"));
const ready=`<script>
window.iconClarityReady=previewReady.then(async function(ok){
 if(!ok)return false;
 cfg.SurvivalCommerceView.UpdateCatalog(PREVIEW_FIXTURE.commerce.paid);
 cfg.SurvivalCommerceView.UpdateWalletCatalog(PREVIEW_FIXTURE.commerce.wallet);
 cfg.SurvivalCommerceView.SelectCategory(params.get('category')||'home');
 const both=PREVIEW_FIXTURE.commerce.wallet.products.map(p=>({...p,__channel:'wallet'})).concat(PREVIEW_FIXTURE.commerce.paid.products.map(p=>({...p,__channel:'payment'})));
 const products=[...new Map(both.filter(p=>cfg.SurvivalBlackLionMarketModel.IsListed(p)).map(p=>[p.sku,p])).values()];
 window.clarityProducts=products;window.clarityContactRows=[];
 if(params.get('contact')==='1'){
  cfg.SurvivalCommerceView.Close();
  const sheet=Number(params.get('sheet')||0),perPage=24,batch=products.slice(sheet*perPage,(sheet+1)*perPage);
  const host=$.CreatePanel('Panel',root,'IconClaritySheet');host.style.position='0px 0px 0px';host.style.width='1920px';host.style.height='1080px';host.style.backgroundColor='#10171cff';host.style.zIndex='2000001';
  const title=$.CreatePanel('Label',host,'');title.text='商品图标清晰度 '+(sheet+1)+' / '+Math.ceil(products.length/perPage)+' · 原尺寸 64 / 放大检查 128 · 正式组件，本地样例';title.style.position='28px 14px 0px';title.style.fontSize='24px';title.style.color='#ead7a0';
  batch.forEach((item,i)=>{
   const cell=$.CreatePanel('Panel',host,'ClarityCell_'+i);cell.style.position=(24+i%6*316)+'px '+(62+Math.floor(i/6)*246)+'px 0px';cell.style.width='300px';cell.style.height='234px';cell.style.backgroundColor='#202a2eff';
   const row=cfg.SurvivalBlackLionMarket.Row(cell,item,{index:sheet*perPage+i,rewards:item.reward_lines,catalog:PREVIEW_FIXTURE.commerce[item.__channel==='payment'?'paid':'wallet'],action(){throw Error('No transactions');}});
   const well=row.__menuCell.iconPanel;well.SetParent(cell);well.style.position='14px 36px 0px';row.DeleteAsync(0);
   const large=$.CreatePanel('Panel',cell,'');large.style.position='132px 12px 0px';large.style.width='144px';large.style.height='144px';large.style.backgroundColor='#171b18';large.style.border='1px solid #9b8c62';large.style.overflow='clip';
   const art=cfg.SurvivalCommerceComponents.ItemIcon(large,item,'',{width:128,height:128});art.style.position='7px 7px 0px';art.style.width='128px';art.style.height='128px';
   const name=$.CreatePanel('Label',cell,'');name.text=item.title;name.style.position='10px 162px 0px';name.style.width='280px';name.style.height='30px';name.style.fontSize='21px';name.style.color='#f3e9d2';name.style.textOverflow='shrink';
   const identity=$.CreatePanel('Label',cell,'');identity.text=item.sku+' · '+item.__channel;identity.style.position='10px 197px 0px';identity.style.width='280px';identity.style.fontSize='14px';identity.style.color='#b9c3c7';
   clarityContactRows.push({sku:item.sku,title:item.title,resourceId:cfg.SurvivalItemResources.Id(item),small:well,large});
  });
 }
 await Promise.all([...document.images].map(i=>i.decode().catch(()=>false)));syncLayout();return true;
});
</script>`;
html=html.replace('</html>',ready+'</html>').replace(/(<div id="PreviewCaption">)[\s\S]*?(<\/div>)/,'$1商城图标 · 正式 XML / JS / CSS 与后端编译数据 · 本地 VIP12 / 未持有样例 · 非游戏截图$2');
fs.writeFileSync(entry,html);
const relevant=['data/ui/item_resources.json','panorama/src/scripts/custom_game/common/item_resources.js','panorama/src/scripts/custom_game/reward_presentation.js','panorama/src/scripts/custom_game/black_lion_market.js','panorama/src/scripts/custom_game/black_lion_market_model.js','panorama/src/scripts/custom_game/common/commerce_components.js','panorama/src/styles/custom_game/black_lion_market.css','panorama/src/scripts/custom_game/shop_v10_assets.js','output/shop_icon_quality_20261017/catalogs.json'];
const frozen=relevant.map(file=>({path:file,sha256:hash(file)}));
for(const row of frozen){if(!row.path.startsWith('panorama/src/'))continue;const relative=row.path.slice('panorama/src/'.length),snapshot=snapshotSources[relative];if(snapshot&&crypto.createHash('sha256').update(snapshot).digest('hex')!==row.sha256)throw Error('Scoped source changed while building its frozen browser snapshot '+row.path);}
if(hash('data/ui/item_resources.json')!==masterHash)throw Error('Resource registry changed while building the snapshot');
fs.writeFileSync(out+'/clarity_assembly.json',JSON.stringify({kind:'production_market_icon_preview',notGameCapture:true,masterHash,sources:frozen,resources:resolved,formalCounts:{wallet:catalogs.wallet.products.length,payment:catalogs.payment.products.length},accountFixture:{vip:12,owned:0,balances:'local ample balance sample'},noAccountSaveOrOrderWrites:true},null,2)+'\n');
console.log('MARKET_ICON_PREVIEW_READY '+entry+' native/source aliases='+resolved.length);
