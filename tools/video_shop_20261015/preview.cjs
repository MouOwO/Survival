'use strict';
// Actual production assembly with exact compiled catalogs and synthetic account state.
const fs=require('fs'),path=require('path'),{spawnSync}=require('child_process');
const out='design_refs/video_shop_20261015/final/preview';
const build=spawnSync(process.execPath,['tools/menus_v10/preview.cjs','--out',out],{encoding:'utf8',windowsHide:true});if(build.status!==0)throw Error(build.stdout+build.stderr);
const release='output/video_shop_20261015/release/',catalogPath=fs.existsSync(release+'payment_catalog_310_overlay.json')?release+'payment_catalog_310_overlay.json':'output/video_shop_20261015/payment_catalog.json';
const paid=JSON.parse(fs.readFileSync(catalogPath,'utf8')).catalog,wallet=JSON.parse(fs.readFileSync('output/video_shop_20261015/wallet_catalog.json','utf8'));
if(fs.existsSync(release+'archive_overlay_diff.json')){const overlay=JSON.parse(fs.readFileSync(release+'archive_overlay_diff.json','utf8')).overlay;wallet.products=JSON.parse(fs.readFileSync(release+'archive_bundle_overlay/'+overlay+'/bundle.json','utf8')).configs.commerce_catalog.rows;}
const data={paid,wallet};
let state=fs.readFileSync('tools/menus_v10/state.js','utf8').replace("params.get('page')||'archive'","params.get('page')||'commerce'");
state+='\nwindow.VIDEO_SOURCE_CATALOG='+JSON.stringify(data).replaceAll('</script','<\\/script')+';\n';
state+=`window.videoBundleReady=previewReady.then(async function(ok){if(!ok)return false;const level=params.get('state')==='vip0'?0:12;
 const raw=VIDEO_SOURCE_CATALOG,paid={catalog_hash:'LOCAL_COMPILED_BUNDLE_FIXTURE',categories:raw.paid.categories,products:raw.paid.products.filter(p=>p.enabled).map(p=>({...p,amount_fen:p.amount,purchase_method:'cash',enabled:!(p.grants.required_vip_level>level),required_vip_level:p.grants.required_vip_level||0,disabled_reason:p.grants.required_vip_level>level?'vip_level_required':'',owned:0,reward_lines:p.grants.lines}))};
 const wallet={categories:raw.wallet.categories,products:raw.wallet.products.filter(p=>p.enabled).map(p=>({...p,reward_lines:p.grants.lines})),balances:{u_coin:0,shop_points:320,shop_gold:2881}};
 cfg.SurvivalPayments.GetCatalog=()=>paid;cfg.SurvivalCommerceWallet.GetCatalog=()=>wallet;
 cfg.SurvivalCommerceView.UpdateWalletCatalog(wallet);cfg.SurvivalCommerceView.UpdateCatalog(paid);cfg.SurvivalCommerceView.SelectCategory('other');syncLayout();await document.fonts.ready;await Promise.all([...document.images].map(i=>i.decode().catch(()=>false)));syncLayout();return true;});\n`;
fs.writeFileSync(path.join(out,'state.js'),state);const entry=path.join(out,'index.html');let html=fs.readFileSync(entry,'utf8').replace(/<script src="[^"]*tools\/menus_v10\/state\.js"><\/script>/,'<script src="state.js"></script>');
html=html.replace(/(<div id="PreviewCaption">)[\s\S]*?(<\/div>)/,'$1视频礼包 · 真实组件及服务端编译配置 · 本地VIP/持有样例 · 不连接支付或账号$2');fs.writeFileSync(entry,html);console.log('VIDEO_BUNDLE_PREVIEW_ASSEMBLED '+out);
