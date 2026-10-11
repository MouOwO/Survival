'use strict';
// Exact original native exports for browser verification; no crop or repaint.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),crypto=require('node:crypto'),{pathToFileURL}=require('node:url');
const root=path.resolve(__dirname,'../..'),data=require(path.join(root,'data/ui/archive_v10_icon_bindings.json'));
const base=path.join(root,'design_refs/archive_v10/work/icon_binding_verification'),viewer=path.join(root,'output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe');
const aliases={},records=[];
for(const row of data.bindings){
 const stem=row.evidence.resource.replace(/[\\/]/g,'__'),input=path.join(base,stem),output=input.replace(/\.vtex_c$/,'.png');
 if(!fs.existsSync(input))throw Error('Run build_icons.cjs first: '+input);
 const sha=crypto.createHash('sha256').update(fs.readFileSync(input)).digest('hex');if(sha!==row.evidence.resource_sha256)throw Error('Stale native resource evidence: '+row.id);
 if(!fs.existsSync(output))cp.execFileSync(viewer,['-i',input,'-o',output,'-d'],{windowsHide:true,stdio:'pipe'});
 if(!fs.existsSync(output))throw Error('No exact native PNG: '+row.id);
 const png=fs.readFileSync(output);if(png.subarray(0,8).toString('hex')!=='89504e470d0a1a0a'||png.subarray(12,16).toString()!=='IHDR')throw Error('Invalid native PNG: '+row.id);const actualSize=[png.readUInt32BE(16),png.readUInt32BE(20)];if(actualSize.some((n,i)=>n!==row.source_size[i]))throw Error('Native PNG dimensions differ from display rectangle: '+row.id+' '+actualSize+' vs '+row.source_size);
 aliases[row.uri]=pathToFileURL(output).href;records.push({category:row.category,id:row.id,uri:row.uri,size:row.source_size,pngSize:actualSize,sourceSha256:sha,previewPng:path.relative(root,output)});
}
fs.writeFileSync(path.join(base,'manifest.json'),JSON.stringify({kind:'exact_official_dota_texture_exports_preview_only',aliases,records},null,2));
const bridge=path.join(root,'design_refs/archive_v10/work/icon_map_v11');fs.mkdirSync(bridge,{recursive:true});
fs.writeFileSync(path.join(bridge,'native_aliases.json'),JSON.stringify({kind:'exact_official_dota_texture_exports_preview_only',aliases,records},null,2));
const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const groups=['fragment','building','points'].map(category=>'<section><h2>'+esc({fragment:'神兵碎片：保留精确饰品原图',building:'存档神器：同名原生物品',points:'积分装备：按正式名称适配原生图'}[category])+'</h2><div class="grid">'+data.bindings.filter(r=>r.category===category).map(r=>'<article><div class="slot"><img src="'+esc(aliases[r.uri])+'"></div><strong>'+esc(r.name)+'</strong><small>'+esc(r.id)+' · '+r.source_size.join('×')+'</small></article>').join('')+'</div></section>').join('');
fs.writeFileSync(path.join(bridge,'montage.html'),'<!doctype html><meta charset="utf-8"><title>V10原生图标实际组装</title><style>body{margin:32px;background:#181329;color:#eeeaf5;font:16px "Microsoft YaHei",sans-serif}h1{font-size:24px}h2{font-size:18px;color:#d7b77b}section{margin:28px 0}.grid{display:grid;grid-template-columns:repeat(7,144px);gap:20px}article{text-align:center}.slot{width:120px;height:120px;background:linear-gradient(145deg,#29223e,#110e1c);border:1px solid #514468;display:flex;align-items:center;justify-content:center;margin:auto auto 8px}.slot img{width:120px;height:120px;object-fit:contain}strong{display:block;font-size:14px;font-weight:400;white-space:nowrap}small{display:block;font-size:11px;color:#a79bb9;margin-top:5px}</style><h1>原生图标实际组装 · 35项</h1><p>保持原始像素和比例。该图是本地资源组件预览，不是游戏截图；名称独立，未写入玩家存档。</p>'+groups);
console.log('ARCHIVE_V10_BINDING_PREVIEW_PASS: '+records.length+' bindings, '+Object.keys(aliases).length+' exact original textures');
