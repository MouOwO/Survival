'use strict';
// Package already inspected, foreground-captured evidence without retouching images.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const repo=path.resolve(__dirname,'../..'),root=path.join(repo,'design_refs/void_shadow_v1'),out=path.join(root,'Delivery');
const manifest=JSON.parse(fs.readFileSync(path.join(out,'CHANGE_LIST.json'),'utf8'));
const sha=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const compile=JSON.parse(fs.readFileSync(path.join(root,'work/compile.json'),'utf8').replace(/^\uFEFF/,''));
const checks=compile.records.map(row=>({source:row.source,sourceMatches:sha(row.source)===row.sourceHash.toLowerCase(),contentMatches:sha(row.content)===row.sourceHash.toLowerCase(),artifact:row.artifact,artifactMatches:sha(row.artifact)===row.compiledHash.toLowerCase()}));
if(checks.some(row=>!row.sourceMatches||!row.contentMatches||!row.artifactMatches))throw Error('Production changed since the tested compilation; review before packaging.');
const screenshots=[
 ['physical_shadow_current_1600.png','full_page_game_1600x900.png','All: 23 actual archive items, 8+8+7; live counts and caps'],
 ['physical_owned_1600.png','owned_game_1600x900.png','Owned: 3 items, counts 2, 1, 1'],
 ['physical_shadow_locked_1600.png','locked_game_1600x900.png','Locked: 20 items with known count 0'],
 ['physical_shadow_tooltip_1600.png','tooltip_game_1600x900.png','Physical hover: existing tooltip, real count 2 and effect wood +10'],
 ['physical_clear_restored_1600.png','other_category_restored_game_1600x900.png','Switch to clear: original archive view and shell restored'],
 ['physical_closed_verified_1600.png','closed_game_1600x900.png','Close: archive absent, battlefield and HUD visible'],
 ['physical_clear_reopen_verified_1600.png','reopened_archive_game_1600x900.png','Physical archive entry: default clear page opens'],
 ['physical_shadow_reopen_verified_1600.png','reopened_shadow_game_1600x900.png','Physical shadow category: new page opens again']
];
const evidence=screenshots.map(([from,to,state])=>{
 const source=path.join(root,'work/native',from),dest=path.join(out,to);fs.copyFileSync(source,dest);
 return {source:path.relative(repo,source).replaceAll('\\','/'),output:to,sha256:sha(dest),capturedAt:fs.statSync(source).mtime.toISOString(),state,kind:'actual_game_foreground_client_capture',size:[1600,900],method:'window.ps1: verified Survival Workshop process, guarded foreground mouse input and CopyFromScreen client rectangle',visuallyReviewed:true,unaltered:true};
});
const checkpoint=path.join(root,'work/checkpoint_v1/source');
const sources=[...manifest.productionSourceFiles,...manifest.originalPngFiles];
sources.forEach(row=>{const dest=path.join(checkpoint,row.path);fs.mkdirSync(path.dirname(dest),{recursive:true});fs.copyFileSync(path.join(repo,row.path),dest);});
fs.writeFileSync(path.join(root,'work/checkpoint_v1/MANIFEST.json'),JSON.stringify({at:new Date().toISOString(),scope:'Tested V1, production source and original component PNGs only',files:sources.map(row=>({path:row.path,sha256:sha(path.join(repo,row.path))}))},null,2)+'\n');
const browser=JSON.parse(fs.readFileSync(path.join(root,'work/browser_v1/report.json'),'utf8'));
fs.writeFileSync(path.join(out,'ACCEPTANCE.json'),JSON.stringify({at:new Date().toISOString(),version:'void_shadow_v1',scope:'Single page first-version review',native:{resolution:[1600,900],evidence,verified:['complete 23 items in 8+8+7','owned 3, locked 20 using real counts','physical hover and original tooltip','switch category restores existing shell','close and reopen via physical game entry'],unchanged:'UI-only review; no profile fixtures or archive save calls'},browser:{status:browser.status,sourceDigest:browser.sourceDigest,report:'../work/browser_v1/report.json',limitation:'Browser adapter approximates native layout and shrink; extra resolutions and extreme fixture values are browser-only'},compilation:{at:compile.at,success:compile.success,exactFiles:checks.length,sourceContentRuntimeChecks:checks},excludedEvidence:'Early work/native captures with stale/background frames were not accepted as state-transition evidence.',visualDifferences:['Real names, quantities, category labels and caps differ from data_preview.json by design','Native text rasterization is heavier than the package dynamic preview','Existing tooltip presentation retained; outer background is the live battlefield'],blockers:[],reviewStatus:'Awaiting user review; no further visual iteration this round'},null,2)+'\n');
const entries=[['正式效果','full_page_game_1600x900.png'],['已拥有 · 3 项','owned_game_1600x900.png'],['未解锁 · 20 项','locked_game_1600x900.png'],['原有 Tooltip','tooltip_game_1600x900.png'],['切回其他分类','other_category_restored_game_1600x900.png'],['关闭后','closed_game_1600x900.png'],['重新打开虚空之影','reopened_shadow_game_1600x900.png']];
fs.writeFileSync(path.join(out,'Review.html'),'<!doctype html><meta charset="utf-8"><title>虚空之影 V1 · 实机验收</title><style>body{background:#141020;color:#eee8fa;font:16px system-ui;margin:24px}a{color:#e4bd7d}figure{margin:30px 0}img{display:block;width:min(100%,1600px);height:auto;border:1px solid #665376}figcaption{margin-bottom:8px}</style><h1>虚空之影 V1 · 实机验收</h1><p>下列均为真实游戏前台窗口 1600×900 截图，未重绘或后期修改。第一版仅接入这一页。</p><p><a href="README.md">接入说明与验证范围</a> · <a href="CHANGE_LIST.md">修改清单</a> · <a href="ACCEPTANCE.json">来源记录</a></p>'+entries.map(([label,file])=>'<figure><figcaption>'+label+'</figcaption><a href="'+file+'"><img src="'+file+'" loading="lazy"></a></figure>').join(''));
console.log(JSON.stringify({checks:checks.length,screenshots:evidence.length,checkpointFiles:sources.length,browser:browser.status,review:'design_refs/void_shadow_v1/Delivery/Review.html'}));
