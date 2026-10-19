'use strict';
// Standalone design candidates. No production controllers or account APIs run.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const repo=path.resolve(__dirname,'../..'),out=path.join(repo,'design_refs/collection_official_five_20261019');
const catalogRoot=path.join(repo,'design_refs/official_ui_catalog_20261019');
const selection=JSON.parse(fs.readFileSync(path.join(__dirname,'asset_sources.json'),'utf8'));
const fixture=require('../collection_gw2/fixture.cjs').fixture();
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
fs.mkdirSync(path.join(out,'assets'),{recursive:true});
const assets={},records=[];
for(const row of selection){
 const key=row.key,id=row.id,extension=path.extname(row.original),file='assets/'+key+extension;
 const original=path.join(catalogRoot,row.original),fallback=path.join(out,file);
 const bytes=fs.readFileSync(fs.existsSync(original)?original:fallback);
 assert.equal(sha(bytes),row.originalSha256,'Official export changed: '+row.sourcePath);
 fs.writeFileSync(path.join(out,file),bytes);assets[key]=file;
 records.push({key,id,file,source:row.sourcePath,uri:row.uri,width:row.width,height:row.height,sha256:sha(bytes),treatment:'Exact official decoded bytes; CSS layout and tintable control masks'});
}
const themes=[
 {id:'classic',number:'01',name:'经典深灰',subtitle:'原生 HUD 面板 · 直角钢边 · 绿色斜面按钮',accent:'#9fc6ab'},
 {id:'armory',number:'02',name:'英雄军械库',subtitle:'军械库底图 · 银色金属框 · 蓝色按钮',accent:'#a5cce9'},
 {id:'crownfall',number:'03',name:'倾天之战',subtitle:'深蓝卷册 · 切角金边 · 原生六角按钮',accent:'#e1c37a'},
 {id:'paper',number:'04',name:'典藏卷册',subtitle:'官方羊皮纸 · 铜色书框 · 角色名称',accent:'#d7bc86'},
 {id:'gold',number:'05',name:'黑金典藏',subtitle:'Dota Plus 纹理 · 细金框 · 鎏金按钮',accent:'#e4c87d'}
];
for(const rows of Object.values(fixture.pages))for(const item of rows){
 const relative='panorama/src/images/custom_game/collection_portraits_compact_v1/'+item.id+'.png';
 assert(fs.existsSync(path.join(repo,relative)),relative);
 item.picture=path.relative(out,path.join(repo,relative)).replaceAll('\\','/');
}
const masks=Object.fromEntries(['paperButton','paperButtonBorder'].map(key=>[key,'data:image/png;base64,'+fs.readFileSync(path.join(out,assets[key])).toString('base64')]));
const model={themes,assets,masks,pages:fixture.pages,social:fixture.social,tabs:fixture.tabs,sample:true};
for(const file of ['ui.css','ui.js'])fs.copyFileSync(path.join(__dirname,file),path.join(out,file));
const html=`<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>收藏 · 五套官方 UI 方案</title><link rel="stylesheet" href="ui.css"></head><body><header class="review-heading"><div><div class="eyebrow">DOTA 2 官方组件 × 激战 2 布局</div><h1><span id="themeNumber"></span><span id="themeName"></span></h1><p id="themeSubtitle"></p></div><nav id="themePicker" aria-label="选择预览方案"></nav></header><main id="stage"><section id="collection" aria-label="收藏界面"><div class="surface"></div><div class="native-frame"></div><header class="window-header"><img class="collection-mark" alt=""><h2>收藏</h2><span class="window-divider"></span><span id="headerCategory"></span><button id="close" aria-label="关闭收藏"><img alt="关闭"></button></header><nav id="categories" aria-label="收藏分类"></nav><section class="content"><div class="toolbar"><div id="collectionSummary"></div><div class="view-options"><span class="quality-key"><i></i>品质</span><button id="ownershipFilter" aria-label="切换拥有状态筛选">全部收藏<span>▾</span></button></div></div><div id="grid" role="list" aria-label="收藏条目"></div><div id="empty">暂无符合条件的收藏</div></section><footer class="window-footer"><div class="currency"><img id="ticketIcon" alt=""><span id="currencyName"></span><strong id="ticketCount"></strong></div><div class="collection-meter"><span>收集进度</span><div class="meter-track"><div id="meterFill"></div></div><strong id="meterLabel"></strong></div><button id="draw" class="draw-button"><span class="draw-skin"></span><span class="draw-border"></span><span class="draw-label">抽取<span class="draw-cost"><img alt="">1</span></span></button></footer></section><aside id="tooltip" role="tooltip"></aside><button id="reopen" hidden>重新打开收藏</button></main><footer class="review-footer"><span>点击左侧图标切换收藏分类 · 悬停查看详情</span><span>离线方案预览 · 数量为展示样例</span></footer><script>window.COLLECTION_FIVE=${JSON.stringify(model).replaceAll('</script','<\\/script')};</script><script src="ui.js"></script></body></html>`;
fs.writeFileSync(path.join(out,'index.html'),html);
fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify({kind:'five_official_collection_design_candidates',productionChanged:false,notGameCapture:true,layoutReference:'design_refs/collection_gw2_v2/reference_inventory.png',layout:{categories:'Left vertical icon rail',grid:'10 columns × 4 rows, all 40 collection entries',footer:'Currency and one-ticket draw action',search:false,persistentItemSelection:false},themes,assets:records,fixture:fixture.source,fixtureValues:'Synthetic ownership and currency; no game/account/reward connection',nativeCssReference:'design_refs/official_ui_catalog_20261019/reference/panorama/styles/dotastyles.css',build:'node tools/collection_official_five_20261019/build.cjs'},null,2));
console.log('COLLECTION_OFFICIAL_FIVE_BUILT '+path.relative(repo,out)+'; '+records.length+' exact official assets; 160 formal collection items');
