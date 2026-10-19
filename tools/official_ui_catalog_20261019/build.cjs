'use strict';
// Installed Valve resources only. This review artifact never loads addon or official game scripts.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),crypto=require('node:crypto'),cp=require('node:child_process');
const {open}=require('../vpk_inspect.cjs');
const root=path.resolve(__dirname,'../..'),base=path.join(root,'design_refs/official_ui_catalog_20261019'),work=path.join(root,'output/official_ui_catalog_20261019');
const archive=path.resolve(root,'../../dota/pak01_dir.vpk'),viewer=process.env.DOTA_UI_VIEWER||path.join(root,'output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex'),slash=s=>s.replaceAll('\\','/');
const core=new Set('control_icons hud tooltips backgrounds textures masks status_icons topbar settings glows transport_controls connection_icons primary_attribute_icons game_modes badges guilds banners dota_plus plus minimap pings rank_tier_icons hero_badges hero_relics battle_report challenges trophies items loadout_backgrounds profile profile_badges conduct new_player_intro coaching guild_patterns treasures'.split(' '));
const themed=new Set('events compendium battlepass cavern dpc store_home weekend_tourney post_game fantasy_craft battle_path hero_selection playercards'.split(' '));
const uiKeyword=/(button|btn|(^|[/_])tab[s_]|tooltip|background|(^|[/_])bg[_.]|panel|border|frame|window|popup|(^|[/_])coin|currency|gold_icon|points_icon|shards_icon|scroll|slider|checkbox|radiobutton|progress|dropdown|(^|[/_])bar[_./]|search|(^|[/_])close|(^|[/_])arrow|(^|[/_])plus|ribbon|(^|[/_])divider|separator|(^|[/_])badge|(^|[/_])icon|(^|[/_])check|(^|[/_])tick|(^|[/_])lock|(^|[/_])glow|vignette|gradient|ornament|emblem|texture|header|footer|reward)/i;
const labels={button:'按钮底图',tab:'标签与切换',input:'输入与搜索',slider:'滑块与滚动条',progress:'进度条与血条',panel:'窗体与背景',tooltip:'提示框',frame:'边框与卡槽',icon:'功能小图标',currency:'货币、票券与奖励',badge:'徽章与段位',hud:'HUD 与资源面板',texture:'材质、装饰与光效',mask:'透明遮罩',event:'活动主题素材',item:'道具图标',other:'其他界面素材'};
function selected(resource){if(!/\.(vtex|vsvg)_c$/.test(resource))return false;const s=resource.slice('panorama/images/'.length),a=s.split('/');if(a.length===1||core.has(a[0]))return true;if(themed.has(a[0]))return !/(visual_novel\/.*(?:character|portrait)|\/comics\/|\/end_credits\/|\/heroes_icons\/|\/artwork\/|\/levels\/)/i.test(s)&&uiKeyword.test(s);return /(?:^|\/)(?:coin_icon|gold_icon|shards_icon|currency_icon|points_icon|ti10_seasonal_item_background)[^/]*\.(vtex|vsvg)_c$/.test(s);}
function category(p){
 const s=p.slice('panorama/images/'.length);
 if(s.startsWith('masks/'))return'mask';if(s.startsWith('items/'))return'item';
 if(/tooltip|(?:^|\/)tooltips\//i.test(s))return'tooltip';
 if(/checkbox|radiobutton|radio_button|check_box|check_gradient|check_shadow|checkbox_check/i.test(s))return'input';
 if(/scroll|slider|track_thumb/i.test(s))return'slider';
 if(/button|btn|(?:^|\/)gray_button|(?:^|\/)red_large_off/i.test(s))return'button';
 if(/(?:^|[/_])tab[s_.]|toggle|filter_|sidebar_selected|nav_selected/i.test(s))return'tab';
 if(/textentry|dropdown|search|input_box|input_field/i.test(s))return'input';
 if(/health_bar|healthbar|mana_bar|manabar|progress|xp_bar|exp_bar|bar_red|bar_black|loading_bar/i.test(s))return'progress';
 if(/coin|currency|gold_icon|points_icon|shards_icon|ticket|tokens?[/_.]|reward/i.test(s))return'currency';
 if(/badge|rank_tier|troph|medal|relic/i.test(s))return'badge';
 if(/border|frame|card_slot|item_slot|empty_slot|ring_|slot_border/i.test(s))return'frame';
 if(/background|(?:^|[/_])bg[_.]|panel|window|popup|header|footer/i.test(s))return'panel';
 if(/control_icons\/|status_icons\/|connection_icons\/|primary_attribute_icons\/|transport_controls\/|(?:^|[/_])icon|arrow|chevron|caret|(?:^|[/_])close|(?:^|[/_])plus|check|lock|pings\//i.test(s))return'icon';
 if(/textures\/|glows\/|gradient|vignette|glow|ribbon|divider|separator|ornament|texture|guild_patterns\//i.test(s))return'texture';
 if(s.startsWith('hud/')||s.startsWith('topbar/')||s.startsWith('minimap/'))return'hud';
 if(themed.has(s.split('/')[0]))return'event';return'other';
}
function uri(p){if(p.endsWith('.png'))return'file://{images}/'+p.slice('panorama/images/'.length);return p.endsWith('.vsvg_c')?'file://{images}/'+p.slice('panorama/images/'.length).replace(/\.vsvg_c$/,'.svg'):'s2r://'+p.slice(0,-2);}
function tags(p,cat){const t=[labels[cat]],rules=[[/crownfall/,'倾天之战'],[/dark_carnival/,'暗黑狂欢节'],[/aghanim/,'阿哈利姆'],[/frostivus/,'迎霜节'],[/battlepass/,'勇士令状'],[/compendium/,'互动指南'],[/monster_hunter/,'怪物猎人'],[/diretide/,'夜魇暗潮'],[/hud/,'游戏内面板'],[/reborn/,'新生界面'],[/hover/,'悬停'],[/selected|checked/,'选中'],[/disabled|inactive/,'禁用'],[/pressed|down_png/,'按下'],[/gold|bronze/,'金色'],[/silver/,'银色'],[/blue/,'蓝色'],[/green/,'绿色'],[/red/,'红色'],[/plus/,'加号'],[/close/,'关闭'],[/arrow/,'箭头'],[/check/,'勾选'],[/ticket/,'抽奖券'],[/coin|gold/,'金币']];for(const [re,label]of rules)if(re.test(p))t.push(label);return t;}
function save(file,data){fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,data);}
function inventory(){
 const vpk=open(archive),all=vpk.entries.filter(e=>e.path.startsWith('panorama/images/')).sort((a,b)=>a.path.localeCompare(b.path,'en'));
 let serial=0;const index=all.map((e,i)=>({id:'I'+String(i+1).padStart(5,'0'),sourcePath:e.path,uri:uri(e.path),category:category(e.path),family:e.path.slice(16).split('/')[0],bytes:e.length+e.preload.length,previewed:selected(e.path)}));
 const plan=[];for(let i=0;i<all.length;i++){const e=all[i];if(!index[i].previewed)continue;const bytes=vpk.read(e),input=path.join(work,'compiled',e.path);save(input,bytes);const row={id:'UI'+String(++serial).padStart(5,'0'),sourcePath:e.path,uri:uri(e.path),category:index[i].category,family:index[i].family,tags:tags(e.path,index[i].category),sourceSha256:sha(bytes),bytes:bytes.length,format:e.path.endsWith('.vsvg_c')?'SVG':'PNG',original:'assets/'+e.path.replace(/\.vtex_c$/,'.png').replace(/\.vsvg_c$/,'.svg')};index[i].previewId=row.id;plan.push(row);}
 const css=vpk.entries.find(e=>e.path==='panorama/styles/dotastyles.vcss_c');if(!css)throw Error('Official stylesheet missing');save(path.join(work,'reference_compiled/panorama/styles/dotastyles.vcss_c'),vpk.read(css));
 save(path.join(work,'plan.json'),JSON.stringify({archive,index,assets:plan,categories:labels},null,2));
 console.log(JSON.stringify({stage:'extract',indexed:all.length,selected:plan.length,compiledBytes:plan.reduce((s,r)=>s+r.bytes,0)}));
}
function decompile(){
 if(!fs.existsSync(viewer))throw Error('Local Source2Viewer CLI not found: '+viewer);
 // Small batches outside the game tree avoid reloading the whole VPK for every texture.
 // A 64 MiB ceiling also avoids consuming the system drive with a second full export.
 const plan=JSON.parse(fs.readFileSync(path.join(work,'plan.json'),'utf8')),batches=[];let batch=[],bytes=0;
 for(const row of plan.assets){if(batch.length&&(bytes+row.bytes>64*1024*1024||batch.length>=300)){batches.push(batch);batch=[];bytes=0;}batch.push(row);bytes+=row.bytes;}if(batch.length)batches.push(batch);
 fs.mkdirSync(path.join(base,'assets'),{recursive:true});fs.mkdirSync(path.join(base,'reference'),{recursive:true});
 for(let i=0;i<=batches.length;i++){
  const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'codex-official-ui-20261019-')),reference=i===batches.length,log=reference?'reference.log':'textures_'+String(i+1).padStart(2,'0')+'.log';
  try{
   if(reference)fs.cpSync(path.join(work,'reference_compiled'),temporary,{recursive:true});
   else for(const row of batches[i]){const dest=path.join(temporary,row.sourcePath);fs.mkdirSync(path.dirname(dest),{recursive:true});fs.copyFileSync(path.join(work,'compiled',row.sourcePath),dest);}
   const fd=fs.openSync(path.join(work,log),'w');let result;try{result=cp.spawnSync(viewer,['-i',temporary,'-o',path.join(base,reference?'reference':'assets'),'-d','--recursive','--threads','4'],{windowsHide:true,stdio:['ignore',fd,fd],maxBuffer:1024*1024});}finally{fs.closeSync(fd);}
   if(result.error||result.status!==0)throw Error('Decoder failed, see '+log+': '+(result.error||result.status));
   console.log('OFFICIAL_UI_DECODE_BATCH '+(i+1)+'/'+(batches.length+1));
  }finally{
   const resolved=fs.realpathSync(temporary),tempRoot=fs.realpathSync(os.tmpdir());
   if(path.dirname(resolved).toLowerCase()!==tempRoot.toLowerCase()||!/^codex-official-ui-20261019-[A-Za-z0-9]+$/.test(path.basename(resolved)))throw Error('Unexpected temporary cleanup target');
   fs.rmSync(resolved,{recursive:true,force:true});
  }
 }
 console.log('OFFICIAL_UI_NATIVE_DECODE_COMPLETE');
}
function assemble(){
 const plan=JSON.parse(fs.readFileSync(path.join(work,'plan.json'),'utf8')),thumbs=JSON.parse(fs.readFileSync(path.join(work,'thumbnails.json'),'utf8'));
 // Include uncompiled PNG files and the one image-associated material in the complete directory index too.
 const byPath=new Map(plan.assets.map(r=>[r.sourcePath,r]));
 plan.index=open(archive).entries.filter(e=>e.path.startsWith('panorama/images/')).sort((a,b)=>a.path.localeCompare(b.path,'en')).map((e,i)=>({id:'I'+String(i+1).padStart(5,'0'),sourcePath:e.path,uri:uri(e.path),category:category(e.path),family:e.path.slice(16).split('/')[0],bytes:e.length+e.preload.length,previewed:byPath.has(e.path),previewId:byPath.get(e.path)?.id}));
 const assets=thumbs.records.map(r=>({...plan.assets.find(p=>p.id===r.id),...r,name:path.posix.basename(r.sourcePath).replace(/_(?:png|psd|jpg)\.vtex_c$|\.vsvg_c$|\.vtex_c$/,'')}));
 const order=Object.keys(labels);assets.sort((a,b)=>order.indexOf(a.category)-order.indexOf(b.category)||Number(!/crownfall\/buttons|hud\/reborn|control_icons\/24px/.test(a.sourcePath))-Number(!/crownfall\/buttons|hud\/reborn|control_icons\/24px/.test(b.sourcePath))||a.sourcePath.localeCompare(b.sourcePath,'en'));
 const seen=new Set(assets.map(r=>r.id));for(const row of plan.index){row.previewed=!!row.previewId&&seen.has(row.previewId);}
 const {buildComponents}=require('./components.cjs'),components=buildComponents({cssPath:path.join(base,'reference/panorama/styles/dotastyles.css')});
 const categories=Object.entries(labels).map(([id,label])=>({id,label,count:assets.filter(r=>r.category===id).length}));
 const meta={title:'Dota 2 官方 UI 图册',archive,generatedAt:new Date().toISOString(),totalOfficialImages:plan.index.length,previewCount:assets.length,indexedCount:plan.index.length,notes:['素材直接从本机 Dota 2 官方 pak01_dir.vpk 解码；没有重新绘制。','可视图册覆盖通用控件、HUD、窗体、边框、提示框、图标和活动主题；其余官方图片保留完整路径索引。','HTML 内嵌浏览缩略图，可单独打开；原始导出图在相邻 assets 文件夹，缩略图不会改动原图。','原生控件仅为浏览器近似演示；详情保留官方 Panorama CSS 原文和复用代码。','选择编号后复制清单发回聊天，即可在游戏界面中采用对应素材。']};
 const data={meta,categories,assets,index:plan.index,components};
 const {render}=require('./template.cjs');save(path.join(base,'官方UI图册.html'),render(data));
 const manifest={meta,categories,components:components.map(({demoHtml,...r})=>r),assets:assets.map(({preview,...r})=>r),index:plan.index,failed:thumbs.failed};
 save(path.join(base,'catalog.json'),JSON.stringify(manifest,null,2));
 const quote=s=>'"'+String(s??'').replaceAll('"','""')+'"';save(path.join(base,'全部官方图片索引.csv'),'\ufeff'+[['编号','预览编号','分类','官方资源URI','VPK路径','已预览'].map(quote).join(','),...plan.index.map(r=>[r.id,r.previewId||'',labels[r.category],r.uri,r.sourcePath,r.previewed?'是':'路径索引'].map(quote).join(','))].join('\r\n'));
 save(path.join(work,'build_report.json'),JSON.stringify({success:true,meta,categories,failed:thumbs.failed,htmlBytes:fs.statSync(path.join(base,'官方UI图册.html')).size,htmlSha256:sha(fs.readFileSync(path.join(base,'官方UI图册.html'))),components:components.length},null,2));
 console.log(JSON.stringify({stage:'build',assets:assets.length,components:components.length,failed:thumbs.failed.length,html:path.relative(root,path.join(base,'官方UI图册.html')),bytes:fs.statSync(path.join(base,'官方UI图册.html')).size}));
}
if(require.main===module){
 const mode=process.argv[2]||'all';if(!['all','extract','decode','build'].includes(mode))throw Error('Expected all, extract, decode, or build');
 if(mode==='extract'||mode==='all')inventory();if(mode==='decode'||mode==='all')decompile();
 if(mode==='all'){const localPython=path.join(process.env.LOCALAPPDATA||'','Programs/Python/Python314/python.exe'),python=process.env.DOTA_UI_PYTHON||(fs.existsSync(localPython)?localPython:'python');const result=cp.spawnSync(python,[path.join(__dirname,'thumbnails.py')],{windowsHide:true,stdio:'inherit'});if(result.status!==0)throw Error('Preview thumbnail preparation failed');}
 if(mode==='build'||mode==='all')assemble();
}
module.exports={selected,category,uri};
