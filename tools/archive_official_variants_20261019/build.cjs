'use strict';
// Offline design proposals. Only installed Valve art and static preview data.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../..'),output=path.join(root,'design_refs/archive_official_variants_20261019');
const catalogRoot=path.join(root,'design_refs/official_ui_catalog_20261019');
const read=p=>JSON.parse(fs.readFileSync(p,'utf8').replace(/^\uFEFF/,''));
const catalog=read(path.join(catalogRoot,'catalog.json')),configuration=read(path.join(__dirname,'themes.json')),fixture=read(path.join(__dirname,'fixture.json'));
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const provenance=[],assets={},used=new Set(),byId=new Map(catalog.assets.map(a=>[a.id,a]));
function include(id){
 if(used.has(id))return id;
 const row=byId.get(id);assert(row,'Missing official UI resource '+id);
 const original=path.resolve(catalogRoot,row.original);assert(original.startsWith(catalogRoot+path.sep));
 const data=fs.readFileSync(original);assert.equal(sha(data),row.originalSha256,'Official export changed '+id);
 const rel='assets/'+id+path.extname(original);fs.mkdirSync(path.join(output,'assets'),{recursive:true});fs.writeFileSync(path.join(output,rel),data);
 assets[id]=rel;used.add(id);provenance.push({id,uri:row.uri,sourcePath:row.sourcePath,export:row.original,path:rel,width:row.width,height:row.height,sha256:sha(data)});return id;
}
const common=['UI04795','UI01932','UI02975','UI02971','UI04813','UI01797','UI02028'];
for(const id of common)include(id);
for(const theme of configuration.themes)for(const id of Object.values(theme.assets))if(id.startsWith('UI'))include(id);
for(const id of Object.values(configuration.navigationIcons))include(id);
for(const item of [...fixture.points,...fixture.clear]){
 const name=(item.nativeName||item.officialIconUri.split('/').pop().replace(/\.png$/,'')).toLowerCase();
 const row=catalog.assets.find(a=>a.sourcePath==='panorama/images/items/'+name+'_png.vtex_c')||catalog.assets.find(a=>a.family==='items'&&a.name===name);
 assert(row,'Missing official item artwork '+name);item.assetId=include(row.id);
}
const data={themes:configuration.themes,icons:configuration.navigationIcons,fixture,assets};
const title='存档界面 · 五套官方 UI 方案';
fs.mkdirSync(output,{recursive:true});
fs.writeFileSync(path.join(output,'preview-data.js'),'window.ARCHIVE_DESIGN_DATA='+JSON.stringify(data).replaceAll('<','\\u003c')+';\n');
for(const file of ['ui.css','app.js'])fs.copyFileSync(path.join(__dirname,file),path.join(output,file));
const html=`<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title><link rel="stylesheet" href="ui.css"></head><body>
<div class="review-toolbar"><div class="review-brand"><b>存档界面</b><span>5 套官方素材方案</span></div><nav id="theme-switcher" aria-label="切换界面方案"></nav><button id="compare-button">五套总览</button></div>
<div class="review-note"><span id="theme-summary"></span><span>可切换分类、搜索、查看详情 · 解锁状态为展示样例</span></div>
<main id="viewport"><div id="stage"><div class="ambient"></div><div id="archive-window" role="region" aria-label="存档界面预览"></div><div class="design-label"><span id="design-name"></span><span>界面方案预览 · 样例存档</span></div></div></main>
<div id="item-tooltip" role="tooltip" hidden></div>
<dialog id="comparison"><div class="comparison-heading"><div><span>OFFICIAL UI / ARCHIVE</span><h1>五套存档方案</h1><p>相同内容与结构，比较官方材质、边框和氛围。</p></div><button id="close-comparison" aria-label="关闭总览">×</button></div><div id="comparison-grid"></div></dialog>
<script src="preview-data.js"></script><script src="app.js"></script></body></html>`;
fs.writeFileSync(path.join(output,'index.html'),html);
fs.writeFileSync(path.join(output,'assets.json'),JSON.stringify({source:'Installed Valve Dota 2 pak01_dir.vpk; decoded official exports, copied without image edits.',assets:provenance},null,2));
const receipt={status:'BUILT',entry:path.relative(root,path.join(output,'index.html')),themes:configuration.themes.map(t=>({id:t.id,title:t.title})),officialAssets:provenance.length,sourceHashes:{}};
for(const file of ['build.cjs','themes.json','fixture.json','ui.css','app.js'])receipt.sourceHashes[file]=sha(fs.readFileSync(path.join(__dirname,file)));
const work=path.join(root,'output/archive_official_variants_20261019');fs.mkdirSync(work,{recursive:true});fs.writeFileSync(path.join(work,'build.json'),JSON.stringify(receipt,null,2));
console.log(JSON.stringify(receipt));
