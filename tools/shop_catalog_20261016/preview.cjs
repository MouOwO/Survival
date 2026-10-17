"use strict";
// Assemble the active production XML / JS / CSS chain with offline profile states.
const fs=require("node:fs"),path=require("node:path"),crypto=require("node:crypto"),{spawnSync}=require("node:child_process");
const repo=path.resolve(__dirname,"../.."),out=path.join(repo,"design_refs/shop_catalog_20261016/ui/preview");
process.chdir(repo);fs.mkdirSync(out,{recursive:true});
const build=spawnSync(process.execPath,["tools/menus_v10/preview.cjs","--out",out],{encoding:"utf8",windowsHide:true});
if(build.status!==0)throw Error(build.stdout+build.stderr);
const hash=JSON.parse(fs.readFileSync("server/bundles/current.json","utf8").replace(/^\uFEFF/,"" )).hash;
const walletArg=process.argv.indexOf("--wallet"),walletPath=walletArg>=0?process.argv[walletArg+1]:"design_refs/shop_catalog_20261016/release/commerce_catalog.json";
const walletSource=JSON.parse(fs.readFileSync(walletPath,"utf8").replace(/^\uFEFF/,"")),walletCatalog=walletSource.catalog||walletSource;
const walletRows=Array.isArray(walletCatalog)?walletCatalog:walletCatalog.products;
if(!Array.isArray(walletRows))throw Error("A formal compiled wallet catalog is required");
const catalogArg=process.argv.indexOf("--catalog"),paidPath=catalogArg>=0?process.argv[catalogArg+1]:"design_refs/shop_catalog_20261016/release/payment_catalog.json";
const paidSource=JSON.parse(fs.readFileSync(paidPath,"utf8").replace(/^\uFEFF/,"")),paidCatalog=paidSource.catalog||paidSource;
const paidRows=Array.isArray(paidCatalog)?paidCatalog:paidCatalog.products;
if(!Array.isArray(paidRows))throw Error("A formal compiled or preflight payment catalog is required");
const categories=Array.isArray(paidCatalog.categories)?paidCatalog.categories:require("../shop_ui_12h/catalog.cjs").csv("data/csv/商城支付系统/payment_categories.csv").filter(row=>row.enabled==='1').sort((a,b)=>Number(a.sort_order)-Number(b.sort_order)).map(row=>({id:row.category_id,label:row.display_name}));
const paid={categories,products:paidRows};
const data={paid,wallet:walletRows};
let state=fs.readFileSync("tools/menus_v10/state.js","utf8").replace("params.get('page')||'archive'","params.get('page')||'commerce'");
state+="\nwindow.MARKET_CATALOG_SOURCE="+JSON.stringify(data).replaceAll("</script","<\\/script")+";\n";
state+=String.raw`
window.marketReady=previewReady.then(async function(ok){
 if(!ok)return false;
 const raw=MARKET_CATALOG_SOURCE,scenario=params.get('state')||'vip0',level=scenario==='vip5'?5:scenario==='vip12'?12:0;
 const ownedSku=scenario==='owned'?(raw.wallet.find(p=>p.enabled&&p.purchase_limit===1&&p.currency==='shop_points')||{}).sku:null;
 const paidRows=raw.paid.products.filter(p=>p.enabled).map(p=>{
  const pricing=(p.grants||{}).pricing||{},required=Number((p.grants||{}).required_vip_level)||0,owned=p.sku===ownedSku?1:p.purchase_limit===0&&scenario==='owned'?3:0,ownedFull=owned>0&&p.purchase_limit===1;
  const coin=p.u_coin_price===undefined?pricing.u_coin_price:p.u_coin_price,rate=p.u_coin_per_yuan===undefined?pricing.u_coin_per_yuan:p.u_coin_per_yuan,original=p.original_u_coin_price===undefined?pricing.original_u_coin_price:p.original_u_coin_price;
  return {...p,amount_fen:p.amount===undefined?p.amount_fen:p.amount,purchase_method:'cash',u_coin_price:coin,u_coin_per_yuan:rate,original_u_coin_price:original,enabled:!ownedFull&&required<=level,
   required_vip_level:required,disabled_reason:ownedFull?'already_owned':required>level?'vip_level_insufficient':'',
   disabled_message:'',owned,reward_lines:(p.grants||{}).lines||[]};
 });
 const walletRows=raw.wallet.filter(p=>p.enabled).map(p=>{
  const owned=p.sku===ownedSku?1:p.purchase_limit===0&&scenario==='owned'?3:0,required=Number((p.grants||{}).required_vip_level)||0;
  const reason=owned&&p.purchase_limit===1?'already_owned':required>level?'vip_level_insufficient':scenario==='insufficient'&&p.currency==='shop_points'?'insufficient_balance':'';
  return {...p,enabled:!reason,owned,disabled_reason:reason,disabled_message:'',required_vip_level:required,reward_lines:(p.grants||{}).lines||[]};
 });
 const paid={catalog_hash:'OFFLINE_COMPILED_PAYMENT_CATALOG',categories:raw.paid.categories,products:paidRows};
 const wallet={categories:raw.paid.categories,products:walletRows,balances:{u_coin:0,shop_points:scenario==='insufficient'?0:425,shop_gold:0}};
 cfg.SurvivalPayments.GetCatalog=()=>paid;cfg.SurvivalCommerceWallet.GetCatalog=()=>wallet;
 cfg.SurvivalCommerceView.UpdateWalletCatalog(wallet);cfg.SurvivalCommerceView.UpdateCatalog(paid);
 cfg.SurvivalCommerceView.SelectCategory(params.get('category')||'home');syncLayout();
 window.marketFixture={scenario,vipLevel:level,ownedSku,catalog:{categories:paid.categories,products:walletRows.concat(paidRows.filter(p=>!walletRows.some(w=>w.sku===p.sku)))},note:'Offline synthetic eligibility and balances; source products/grants/prices come from compiled catalogs. No account, payment, order or save access.'};
 await document.fonts.ready;await Promise.all([...document.images].map(i=>i.decode().catch(()=>false)));syncLayout();return true;
});
`;
fs.writeFileSync(path.join(out,"state.js"),state);
const htmlPath=path.join(out,"index.html");let html=fs.readFileSync(htmlPath,"utf8").replace(/<script src="[^"]*tools\/menus_v10\/state\.js"><\/script>/,'<script src="state.js"></script>');
html=html.replace(/(<div id="PreviewCaption">)[\s\S]*?(<\/div>)/,'$1商城五分栏 · 真实 XML / JS / CSS 组装 · 正式商品配置＋离线 VIP/持有样例 · 未连接游戏或支付$2');
html=html.replace('</style>','.BLMarketWindow .panel::-webkit-scrollbar-thumb{background:#948257}.BLMarketWindow .panel::-webkit-scrollbar-track{background:#11150f}</style>');
fs.writeFileSync(htmlPath,html);
const assembly=JSON.parse(fs.readFileSync(path.join(out,"assembly.json"),"utf8"));
assembly.marketFixture={localActiveBundleHash:hash,walletCatalogPath:walletPath,paymentCatalogPath:paidPath,sourceHashes:[walletPath,paidPath].map(file=>({path:file,sha256:crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex")})),scenarios:["vip0","vip5","vip12","owned","insufficient"],scope:"Real production assembly with explicit synthetic eligibility; not native-game verification; no account or payment requests."};
fs.writeFileSync(path.join(out,"assembly.json"),JSON.stringify(assembly,null,2));
console.log("SHOP_CATALOG_PREVIEW_BUILT "+path.relative(repo,out));
