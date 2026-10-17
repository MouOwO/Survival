'use strict';
// Snapshot actual production XML/JS/CSS. All ownership and eligibility stay local.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),cp=require('node:child_process'),{pathToFileURL}=require('node:url');
const repo=path.resolve(__dirname,'../..');process.chdir(repo);
const out='design_refs/vip_bundle_icons_20261017/preview';
const arg=name=>{const i=process.argv.indexOf(name);return i<0?null:process.argv[i+1];};
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const masterBytes=fs.readFileSync('data/ui/item_resources.json'),masterHash=hash(masterBytes),expected=arg('--expected-hash');
if(!expected||expected!==masterHash)throw Error('Pass the frozen item_resources SHA256 with --expected-hash. Current: '+masterHash);
fs.mkdirSync(out,{recursive:true});
let builder=fs.readFileSync('tools/item_resources_20261016/build/preview.cjs','utf8');
builder=builder.replace("const repo=path.resolve(__dirname,'../../..'),out=path.join(repo,'design_refs/item_resources_20261016/build/preview');",`const repo=process.cwd(),out=path.join(repo,${JSON.stringify(out)});`);
const temporary=path.join(out,'build_preview.cjs');fs.writeFileSync(temporary,builder);
const build=cp.spawnSync(process.execPath,[temporary],{cwd:repo,encoding:'utf8',windowsHide:true});
if(build.stdout)process.stdout.write(build.stdout);if(build.stderr)process.stderr.write(build.stderr);if(build.status!==0)process.exit(build.status||1);
const filename=path.join(out,'index.html');let html=fs.readFileSync(filename,'utf8');
const aliasesKey='window.PREVIEW_ASSET_PATHS=',aliasesEnd=';window.PREVIEW_BASELINE=',aliasesStart=html.indexOf(aliasesKey)+aliasesKey.length,aliasesStop=html.indexOf(aliasesEnd,aliasesStart);
if(aliasesStart<aliasesKey.length||aliasesStop<aliasesStart)throw Error('Preview asset map unavailable');
const aliases=JSON.parse(html.slice(aliasesStart,aliasesStop)),nativeAliases=[],aliasFile=arg('--native-aliases');
function alias(uri,source){if(!uri||!source)return;source=String(source);if(source.startsWith('file:')){aliases[uri]=source;nativeAliases.push({uri,source});return;}if(!fs.existsSync(source))throw Error('Missing native preview PNG: '+source);aliases[uri]=pathToFileURL(path.resolve(source)).href;nativeAliases.push({uri,source});}
if(aliasFile){const data=JSON.parse(fs.readFileSync(aliasFile,'utf8').replace(/^\uFEFF/,''));for(const[uri,source]of Object.entries(data.aliases||{}))alias(uri,typeof source==='string'?source:source.path||source.png);for(const row of data.records||data.rows||[])alias(row.uri||row.native_uri,row.previewPng||row.export_png||row.png||row.path||row.source);}
for(const row of JSON.parse(masterBytes).items){const match=String(row.uri||'').match(/^s2r:\/\/panorama\/images\/(.+)_png\.vtex$/);if(!match||aliases[row.uri])continue;const relative=match[1]+'.png',source=['art/ui/sources/','panorama/src/images/'].map(prefix=>prefix+relative).find(f=>fs.existsSync(f));if(source)alias(row.uri,source);}
html=html.slice(0,aliasesStart)+JSON.stringify(aliases)+html.slice(aliasesStop);
const adapter='tools/archive_v10/adapter.js';html=html.replace(pathToFileURL(path.resolve(adapter)).href,'adapter.js');
fs.writeFileSync(path.join(out,'adapter.js'),fs.readFileSync(adapter,'utf8').replace("v==='stretch-to-fit'?'fill':'contain'","v==='stretch-to-fit'?'fill':v==='stretch-to-cover-preserve-aspect'?'cover':'contain'"));
const paymentCatalogPath='design_refs/shop_functional_20261016/release_v2/payment_catalog.json',paymentSource=JSON.parse(fs.readFileSync(paymentCatalogPath,'utf8').replace(/^\uFEFF/,'')),formalPayment=paymentSource.catalog||paymentSource;
const ready=`<script>
window.vipBundleReady=itemResourceReady.then(async function(ok){
 if(!ok)return false;
 const scope=params.get('scope')||'packages';
 if(previewState.page==='commerce'){
  const source=${JSON.stringify(formalPayment).replaceAll('</script','<\\/script')},raw=Array.isArray(source)?source:source.products;
  const products=raw.filter(p=>p.enabled).map(p=>{const pricing=(p.grants||{}).pricing||{},required=Number((p.grants||{}).required_vip_level)||0;return {...p,amount_fen:p.amount===undefined?p.amount_fen:p.amount,purchase_method:'cash',u_coin_price:p.u_coin_price===undefined?pricing.u_coin_price:p.u_coin_price,u_coin_per_yuan:p.u_coin_per_yuan===undefined?pricing.u_coin_per_yuan:p.u_coin_per_yuan,original_u_coin_price:p.original_u_coin_price===undefined?pricing.original_u_coin_price:p.original_u_coin_price,required_vip_level:required,enabled:required<=12,disabled_reason:required>12?'vip_level_insufficient':'',disabled_message:'',owned:0,reward_lines:(p.grants||{}).lines||[]};});
  const paid={catalog_hash:'FORMAL_PUBLISHED_PAYMENT_CATALOG_LOCAL_VIP12',categories:source.categories||PREVIEW_FIXTURE.commerce.paid.categories,products};
  PREVIEW_FIXTURE.commerce.paid=paid;cfg.SurvivalPayments.GetCatalog=()=>paid;cfg.SurvivalCommerceView.UpdateCatalog(paid);cfg.SurvivalCommerceView.SelectCategory('vip');
 }
 if(previewState.page==='archive'){
  const all=PREVIEW_FIXTURE.v10.pages.commerce_goods;
  const rows=scope==='badges'?all.filter(r=>/^vip_(?:privilege|medal)_/.test(r.id)):scope==='all'?all:all.filter(r=>/^vip_package_\\d+$/.test(r.id));
  emit('survival_archive_snapshot',{ok:1,category_id:'commerce_goods',sequence:550,chunk:1,chunks:1,rows,pending:0,upgrade_pending:0});
 }
 if(previewState.page==='vip'){
  emitNet('survival_player_public_profiles','0',{vip_badge:1});
  const rows=cfg.VIPRewardCatalog.rewards.map(row=>({id:row.reward_id,owned:0,eligible:1,affordable:1}));
  emit('survival_vip_snapshot',{ok:true,level:12,balance:9999,recharge_total_fen:1250000,rows});
  if(!cfg.SurvivalVIP.IsOpen())cfg.SurvivalVIP.Open();
  const group=scope==='badges'?'privileges':'packages';nodes['VIPTab_'+group].events.onactivate();
 }
 if(previewState.page==='strip'){
  cfg.SurvivalArchive.Close();
  const host=$.CreatePanel('Panel',root,'VIPBundleComparison');host.style.position='44px 36px 0px';host.style.width='1740px';host.style.height='750px';host.style.backgroundColor='#171823ee';host.style.zIndex='2000001';
  const title=$.CreatePanel('Label',host,'');title.text='VIP 1—10 专属礼包 · 统一资源与正式图标工厂';title.style.position='26px 22px 0px';title.style.color='#e9d2a1';title.style.fontSize='28px';
  for(let i=1;i<=10;i++){
   const id='vip_package_'+String(i).padStart(2,'0'),row=cfg.SurvivalItemResources.Lookup(id),x=26+(i-1)%5*338,y=95+Math.floor((i-1)/5)*300;
   const cell=$.CreatePanel('Panel',host,'VIPBundleStrip_'+i);cell.style.position=x+'px '+y+'px 0px';cell.style.width='304px';cell.style.height='274px';cell.style.backgroundColor='#262736';
   const stage=$.CreatePanel('Panel',cell,'');stage.style.position='48px 12px 0px';stage.style.width='208px';stage.style.height='208px';stage.style.overflow='clip';
   const icon=cfg.SurvivalRewardPresentation.CreateRegisteredIcon(stage,{id},'',{width:208,height:208});if(!icon)throw Error('Missing registered package art '+id);icon.style.width='208px';icon.style.height='208px';
   const label=$.CreatePanel('Label',cell,'');label.text='VIP'+i+' 专属礼包';label.style.position='0px 230px 0px';label.style.width='304px';label.style.height='32px';label.style.textAlign='center';label.style.color='#e6d7b5';label.style.fontSize='23px';cell.__resource=row;cell.__art=stage;
  }
 }
 await Promise.all([...document.images].map(i=>i.decode().catch(()=>false)));syncLayout();return true;
});
</script>`;
html=html.replace('</html>',ready+'</html>').replace(/(<div id="PreviewCaption">)[\s\S]*?(<\/div>)/,'$1VIP 礼包图标 · 实际 XML / JS / CSS 与正式数据 · 隔离样例 · 本地组件预览，非游戏截图$2');fs.writeFileSync(filename,html);
const assemblyFile=path.join(out,'assembly.json'),assembly=JSON.parse(fs.readFileSync(assemblyFile,'utf8'));
Object.assign(assembly,{kind:'vip_bundle_icons_real_production_assembly',notGameCapture:true,masterResourceHash:masterHash,nativeAliasFile:aliasFile,nativeAliases,paymentCatalog:{path:paymentCatalogPath,sha256:hash(fs.readFileSync(paymentCatalogPath))},scope:'Formal products and rewards; explicit local account state; no network, account, order or save mutations.'});
assembly.frozenSourceFiles=assembly.sourceGraph.map(r=>({path:'panorama/src/'+r.path,sha256:r.sha256}));
for(const file of ['data/ui/item_resources.json','data/csv/商城兑换系统/commerce_products.csv','data/csv/商城支付系统/payment_products.csv','data/csv/存档系统/archive_vip_rewards.csv','panorama/src/scripts/custom_game/vip_catalog.js'])assembly.frozenSourceFiles.push({path:file,sha256:hash(fs.readFileSync(file))});
fs.writeFileSync(assemblyFile,JSON.stringify(assembly,null,2)+'\n');console.log('VIP_BUNDLE_PREVIEW_READY '+filename);
