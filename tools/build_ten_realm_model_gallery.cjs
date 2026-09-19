// Actual exported Blender model renders, with the approved concepts for comparison.
'use strict';
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '..');
const out = path.join(root, 'output/ten_realm_arenas');
const readJson = file => JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
const assets = readJson(path.join(out, 'asset_manifest.json'));
if (!Array.isArray(assets) || assets.length !== 10) throw Error('Expected ten exported realm assets.');
const escape = value => String(value).replace(/[&<>"']/g, ch => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
}[ch]));
const chinese = ['一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
const number = value => Number.isFinite(value) ? value.toLocaleString('zh-CN', {maximumFractionDigits: 1}) : '未记录';
const vector = values => Array.isArray(values) ? values.map(number).join(' × ') : '未记录';
const descriptions = [
  '风积沙地与风化砂岩围墙，干沙沿不规则岸线过渡到湿沙和水下岩滩。',
  '落叶林土、苔石和自然根系，树木与草丛留在围墙外侧。',
  '压实泥炭、旧木与湿苔墙，芦苇和淤泥构成沼泽岸边的层次。',
  '红砂岩层理与赭色碎砾，外侧断岩和崩落石块延伸到浅水。',
  '积雪、冻土、冷石与冰缘，利用表面粗糙度区分雪、冰和湿岩。',
  '浅色珊瑚石、贝砂与海草，礁盘和潮池形成明亮海岸。',
  '冷却玄武岩、焦岩与暗铜，湿黑礁石接入深色海水。',
  '紫灰矿岩、石英纹脉与矿晶切面，晶簇集中外缘，以反光表现材质。',
  '温润浅石、青金嵌饰与花草苔岸，形成开阔明亮的天辉庭院。',
  '暗灰石板、骨白棘饰与枯根黑泥岸，在自然光中保留清楚的材料层次。',
];
const views = [
  {id: 'hero', label: '整体', type: 'Blender 模型渲染'},
  {id: 'top', label: '俯视', type: 'Blender 模型渲染'},
  {id: 'detail', label: '材质细节', type: 'Blender 模型渲染'},
  {id: 'concept', label: '已确认概念', type: '已确认的 700 × 700 概念图'},
];
const realms = assets.slice().sort((a, b) => a.meta.rank - b.meta.rank).map((asset, index) => {
  const m = asset.meta || {}, rank = index + 1, key = String(rank).padStart(2, '0');
  if (m.rank !== rank || asset.name !== `realm_${key}` || JSON.stringify(m.footprint) !== '[700,700]') {
    throw Error('Unexpected realm rank/name/footprint: ' + asset.name);
  }
  if (!Array.isArray(asset.bounds) || asset.bounds.length !== 2
    || asset.bounds.some(v => !Array.isArray(v) || v.length !== 3 || v.some(n => !Number.isFinite(n)))) {
    throw Error('Missing measured model bounds: ' + asset.name);
  }
  const dimensions = asset.bounds[0].map((n, axis) => asset.bounds[1][axis] - n);
  if (dimensions.some(n => n <= 0)) throw Error('Invalid measured model bounds: ' + asset.name);
  return {rank, key, name: asset.name, label: m.label || asset.name, title: `${chinese[index]}戒 · ${m.label || asset.name}`,
    biome: m.biome || '', footprint: m.footprint, clear_combat_size: m.clear_combat_size,
    bounds: asset.bounds, dimensions, triangles: asset.triangles,
    material_count: Array.isArray(asset.materials) ? new Set(asset.materials).size : null,
    collision_count: asset.collision_count ?? asset.collision_hulls
      ?? (Array.isArray(asset.collision) ? asset.collision.length : asset.collision),
    description: descriptions[index], images: {
      hero: `previews/realm_${key}_hero.png`, top: `previews/realm_${key}_top.png`, detail: `previews/realm_${key}_detail.png`,
      concept: `../ten_realm_arena_concepts_v2_700x700/realm_${key}.png`,
    }};
});
function report(filename) {
  const full = path.join(out, filename);
  if (!fs.existsSync(full)) return {filename, exists: false, label: '等待验证', tone: 'pending', data: null};
  try {
    const data = readJson(full), status = String(data.status || '').toUpperCase();
    if (status === 'PASS') return {filename, exists: true, label: '通过', tone: 'pass', data};
    if (['FAIL', 'FAILED', 'ERROR'].includes(status)) return {filename, exists: true, label: '未通过', tone: 'fail', data};
    return {filename, exists: true, label: '已有记录', tone: 'pending', data};
  } catch (error) {
    return {filename, exists: true, label: '记录无法读取', tone: 'fail', data: null};
  }
}
const verification = report('verification.json');
const blenderCheck = report('blend_check.json');
const badge = (name, result) => {
  const text = `${escape(name)}：${escape(result.label)}`;
  return result.exists ? `<a class="check ${result.tone}" href="${result.filename}">${text}</a>`
    : `<span class="check ${result.tone}">${text}</span>`;
};
const cards = realms.map(realm => `<article class="card" id="realm-${realm.key}" data-rank="${realm.rank}">
<header><span class="rank-number">${realm.key}</span><div><h2>${escape(realm.title)}</h2><p>主体 700 × 700 游戏单位 · 含四面围墙</p></div></header>
<button type="button" class="picture" data-zoom="${realm.rank}" aria-label="放大${escape(realm.title)}实际模型"><img class="model-image" src="${realm.images.hero}" alt="${escape(realm.title)}实际 Blender 模型整体渲染" loading="${realm.rank <= 2 ? 'eager' : 'lazy'}"><span class="image-kind">Blender 模型渲染 · 整体</span><span class="zoom-hint">点击放大</span></button>
<div class="view-tabs" role="group" aria-label="${escape(realm.title)}查看方式">${views.map(view => `<button type="button" data-view="${view.id}" aria-pressed="${view.id === 'hero'}" class="${view.id === 'hero' ? 'active' : ''}">${view.label}</button>`).join('')}</div>
<div class="card-copy"><p class="description">${escape(realm.description)}</p><dl>
<div><dt>主体含围墙</dt><dd>${vector(realm.footprint)}</dd></div><div><dt>战斗净空</dt><dd>${vector(realm.clear_combat_size)}</dd></div><div><dt>实际外缘 X × Y</dt><dd>${vector(realm.dimensions.slice(0, 2))}</dd></div>
<div><dt>三角面</dt><dd>${number(realm.triangles)}</dd></div><div><dt>材质数</dt><dd>${number(realm.material_count)}</dd></div><div><dt>碰撞体</dt><dd>${number(realm.collision_count)}</dd></div></dl>
<p class="bounds-note">实际外缘包含岸地、岩石与植被；尺寸单位与主体相同。</p><div class="card-links"><a class="current-original" href="${realm.images.hero}" target="_blank" rel="noopener">打开当前原图 ↗</a><a href="${realm.images.concept}" target="_blank" rel="noopener">独立打开概念图 ↗</a></div></div>
</article>`).join('\n');
const clientData = JSON.stringify({realms, views}).replace(/</g, '\\u003c');
const totalTriangles = realms.every(r => Number.isFinite(r.triangles)) ? realms.reduce((n, r) => n+r.triangles, 0) : null;
const html = `<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>一至十戒 · 实际模型验看</title><style>
:root{color-scheme:dark;font:16px/1.6 system-ui,"Microsoft YaHei",sans-serif;background:#111b1d;color:#e7eae2}*{box-sizing:border-box}html{scroll-behavior:smooth;scroll-padding-top:85px}body{margin:0}main{max-width:1540px;margin:auto;padding:42px 30px 65px}a{color:#c5d9bc;text-underline-offset:4px}button{font:inherit;color:inherit;cursor:pointer}a:focus-visible,button:focus-visible,input:focus-visible,summary:focus-visible{outline:3px solid #a7cbaf;outline-offset:4px}.eyebrow{font-size:12px;letter-spacing:.2em;color:#b7c29c}h1{font-size:clamp(27px,4vw,46px);font-weight:600;line-height:1.3;margin:12px 0}h2{font-size:21px;font-weight:550;line-height:1.4;margin:0}.intro{color:#a7b8b1;max-width:1050px;margin:0}.facts{display:flex;gap:10px;flex-wrap:wrap;margin:23px 0 15px}.facts span{background:#243432;border:1px solid #46564d;border-radius:5px;padding:6px 12px;font-size:14px}.links{display:flex;gap:20px;flex-wrap:wrap;font-size:14px}.checks{display:flex;gap:10px;flex-wrap:wrap;margin:18px 0}.check{font-size:12px;border:1px solid #56614e;padding:4px 10px;border-radius:4px;text-decoration:none}.check.pass{background:#263e30;color:#c3e1bf}.check.pending{background:#373a2a;color:#d2d2ac}.check.fail{background:#4b302c;color:#efc1b3}.image-caution{font-size:13px;color:#96ada1;margin:0 0 20px}.command{display:flex;align-items:center;gap:10px;flex-wrap:wrap;background:#1c292a;border-left:3px solid #7e9c84;border-radius:3px;padding:13px 16px;margin:19px 0}.command label{font-size:13px;color:#a6b6ac}.command input{flex:1;min-width:240px;font:13px/1.5 ui-monospace,Consolas,monospace;color:#d9e3d3;background:#152123;border:1px solid #3e5447;border-radius:4px;padding:7px 9px}.command button{font-size:13px;border:1px solid #657d64;border-radius:4px;background:#2c4137;padding:6px 12px}.nav{position:sticky;top:0;z-index:3;display:flex;gap:8px;overflow-x:auto;padding:13px 0;margin:20px 0;background:#111b1df5;backdrop-filter:blur(10px)}.nav a{white-space:nowrap;flex-shrink:0;text-decoration:none;font-size:13px;padding:6px 11px;background:#263834;border:1px solid #41594b;border-radius:4px}.overview{margin:0 0 26px;border:1px solid #45534a;border-radius:8px;background:#1b292a;overflow:hidden}.overview header{padding:17px 22px;display:flex;justify-content:space-between;align-items:baseline;gap:12px}.overview header a{font-size:12px}.overview .picture{aspect-ratio:2/1}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:24px}.card{border:1px solid #3c5046;background:#1c2b2c;border-radius:8px;overflow:hidden;scroll-margin-top:86px}.card header{display:flex;align-items:center;gap:18px;padding:20px 22px}.rank-number{font-family:Georgia,serif;color:#a8bf96;font-size:35px;line-height:1}.card header p{font-size:12px;color:#9fb19f;margin:4px 0 0}.picture{display:block;border:0;padding:0;position:relative;width:100%;aspect-ratio:7/5;background:#2a363a;cursor:zoom-in}.picture img{display:block;width:100%;height:100%;object-fit:contain}.image-kind{position:absolute;left:12px;bottom:12px;font-size:11px;padding:3px 8px;border:1px solid #637662;border-radius:4px;color:#e1e8d8;background:#1d2e25dc}.zoom-hint{position:absolute;right:12px;bottom:12px;background:#1d2e25dc;color:#dde6d2;border:1px solid #637662;border-radius:4px;padding:3px 8px;font-size:11px;opacity:0}.picture:hover .zoom-hint,.picture:focus-visible .zoom-hint{opacity:1}.view-tabs{display:flex;flex-wrap:wrap;gap:7px;padding:15px 20px 0}.view-tabs button{font-size:13px;padding:5px 10px;border:1px solid #506956;border-radius:4px;background:#243732;color:#cbd6c8}.view-tabs button.active{background:#a7bf93;color:#16271b;border-color:#a7bf93}.card-copy{padding:0 22px 20px}.description{font-size:14px;color:#bccbbe;margin:15px 0}.card dl{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px 14px;margin:15px 0}.card dt{font-size:11px;color:#93ad9d}.card dd{font-size:15px;color:#d6e2cf;margin:2px 0 0}.bounds-note{font-size:11px;color:#90a697;margin:12px 0}.card-links{display:flex;gap:15px;flex-wrap:wrap;font-size:12px}.notes{margin-top:28px;padding:18px 22px;border:1px solid #405848;background:#1c2b2c;border-radius:5px;font-size:13px;color:#a9bea9}.notes summary{cursor:pointer;color:#d0dfc7;font-size:14px}.notes p{margin:12px 0}.notes ul{padding-left:21px}.notes li+li{margin-top:5px}footer{margin-top:26px;color:#82998b;font-size:12px}dialog{width:min(96vw,1680px);max-width:none;max-height:96vh;background:#14211f;color:#e2ead8;border:1px solid #6d826b;border-radius:8px;padding:0;overflow:hidden}dialog::backdrop{background:#07100ee8;backdrop-filter:blur(3px)}.viewer-header,.viewer-footer{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:12px 17px}.viewer-header strong{font-size:15px;font-weight:500}.viewer-controls{display:flex;align-items:center;gap:8px}.viewer-controls button,.viewer-footer button{font-size:13px;padding:5px 10px;background:#2b4134;border:1px solid #627b5f;border-radius:4px}.viewer-controls .close{font-size:21px;line-height:1.1}.viewer-scroll{height:73vh;display:flex;justify-content:center;align-items:center;overflow:auto;background:#263335}.viewer-scroll img{display:block;max-width:100%;max-height:100%;width:auto;height:auto;object-fit:contain}.viewer-scroll.full{display:block}.viewer-scroll.full img{max-width:none;max-height:none}.viewer-footer{font-size:12px;color:#a4b79d}.viewer-footer>div{display:flex;align-items:center;gap:10px}.viewer-views{display:flex;flex-wrap:wrap;gap:6px;padding:0 17px 12px}.viewer-views button{font-size:12px;color:#b7c9ac;background:#24392d;border:1px solid #587154;border-radius:4px;padding:4px 10px}.viewer-views button.active{background:#afc49a;color:#17291a}@media(max-width:1050px){main{padding-left:21px;padding-right:21px}.grid{gap:17px}.card header,.card-copy{padding-left:17px;padding-right:17px}.view-tabs{padding-left:17px;padding-right:17px}h2{font-size:18px}.card dl{gap:9px}.viewer-footer .keyboard{display:none}}@media(max-width:760px){main{padding:28px 15px 50px}.grid{grid-template-columns:1fr}.overview .picture{aspect-ratio:7/5}.card header{padding-top:17px;padding-bottom:17px}.zoom-hint{opacity:1}.viewer-header{flex-direction:column;align-items:flex-start}.viewer-scroll{height:61vh}.viewer-footer{flex-wrap:wrap}.card dl{grid-template-columns:repeat(3,minmax(0,1fr))}.command input{min-width:100%;font-size:11px}.nav a{padding:5px 10px}}@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}}
[hidden]{display:none!important}
</style></head><body><main>
<div class="eyebrow">SURVIVAL · TEN REALMS · ACTUAL MODEL REVIEW</div><h1>一至十戒 · 实际模型验看</h1><p class="intro">按已确认的十张正方形设计制作。这里展示实际 Blender 模型渲染，每戒可切换整体、俯视、材质细节，并与对应概念图比较。</p>
<div class="facts"><span>10 个独立模型</span><span>主体 700 × 700 · 含围墙</span><span>中央净空 612 × 612</span><span>自然岸线向外延伸</span><span>无自发光</span></div>
<div class="links"><a href="ten_realm_arenas.blend">打开 Blender 工程</a><a href="previews/all_realms.png" target="_blank" rel="noopener">完整模型总览 ↗</a><a href="../ten_realm_arena_concepts_v2_700x700/index.html">已确认概念图集</a><a href="../../docs/ai/TEN_REALM_ARENAS.md">模型与地图说明</a></div>
<div class="checks">${badge('Blender 工程检查', blenderCheck)}${badge('资源与地图静态验证', verification)}</div>
<p class="image-caution">Blender 渲染用于观察模型和材质；Source2 游戏光照以独立测试地图为准。${verification.data?.runtime_verified === true ? '验证记录声明已进行实机核验。' : '当前页面不代表已完成实机核验。'}</p>
<div class="command"><label for="review-command">游戏测试地图</label><input id="review-command" value="dota_launch_custom_game survival ten_realm_arenas_review" readonly aria-label="游戏控制台测试地图命令"><button type="button" id="copy-command">复制命令</button></div>
<nav class="nav" aria-label="选择戒数">${realms.map(r => `<a href="#realm-${r.key}">${r.key} ${escape(r.label)}</a>`).join('')}</nav>
<section class="overview"><header><h2>十戒模型总览</h2><a href="previews/all_realms.png" target="_blank" rel="noopener">打开原图 ↗</a></header><button type="button" class="picture" data-overview aria-label="放大十戒实际模型总览"><img src="previews/all_realms.png" alt="十个实际 Blender 场地模型总览"><span class="image-kind">实际 Blender 模型总览</span><span class="zoom-hint">点击放大</span></button></section>
<section class="grid" aria-label="十个实际场地模型">${cards}</section>
<details class="notes"><summary>尺寸、模型数据与测试地图</summary><p>700 × 700 是含围墙的正方形主体尺寸。每卡“实际外缘 X × Y”由导出模型的真实包围盒计算，包含岸地、岩石与植被。图片画板比例和像素尺寸与游戏单位分别表示不同尺度。</p><ul><li>每场三角面、材质数和碰撞体数量直接读取资产清单；本轮碰撞设计为 5 个简化实体，实际记录按卡片显示。全部模型合计三角面：${number(totalTriangles)}。</li><li>独立地图 <code>ten_realm_arenas_review</code> 两列五排展示十个模型；主体地面 Z=128，外部海面 Z=86，仅围墙内场开放导航。</li><li>十个 prefab 为 <code>ten_realm_arena_01</code> 至 <code>ten_realm_arena_10</code>，均保留局部模型原点；正式玩法地图与挑战配置保持现状。</li><li>静态验证与 Blender 工程检查均按实际 JSON 记录显示，缺失时标为“等待验证”。材质效果、碰撞与移动还需在实际游戏光照和镜头下观察。</li></ul><div class="links"><a href="asset_manifest.json">模型清单</a><a href="layout.json">地图装配清单</a><a href="map_manifest.json">地图与导航清单</a></div></details>
<footer>实际模型渲染与已确认概念分别标注 · 点击图片放大 · ← → 切换戒数，↑ ↓ 切换视图，Esc 关闭</footer></main>
<dialog id="viewer" aria-labelledby="viewer-title"><div class="viewer-header"><strong id="viewer-title"></strong><div class="viewer-controls"><button type="button" id="size-toggle">原始尺寸</button><button type="button" class="close" id="viewer-close" aria-label="关闭大图">×</button></div></div><div class="viewer-views" id="viewer-views" role="group" aria-label="大图视图切换">${views.map(v => `<button type="button" data-modal-view="${v.id}">${v.label}</button>`).join('')}</div><div class="viewer-scroll" id="viewer-scroll"><img id="viewer-image" alt=""></div><div class="viewer-footer"><div><button type="button" id="previous">← 上一戒</button><span id="viewer-count"></span><button type="button" id="next">下一戒 →</button></div><span class="keyboard">↑ ↓ 切视图 · Esc 关闭</span><a id="viewer-original" target="_blank" rel="noopener">打开当前原图 ↗</a></div></dialog>
<script>
const {realms,views}=${clientData};
const selectedViews=new Map(realms.map(r=>[r.rank,'hero']));
const viewer=document.getElementById('viewer'),photo=document.getElementById('viewer-image'),scroll=document.getElementById('viewer-scroll'),viewerTitle=document.getElementById('viewer-title'),counter=document.getElementById('viewer-count'),original=document.getElementById('viewer-original'),sizeToggle=document.getElementById('size-toggle'),modalViews=document.getElementById('viewer-views');
let active=0,activeView='hero',overview=false;
function selectCardView(rank,view){const realm=realms.find(r=>r.rank===rank),card=document.querySelector('article[data-rank="'+rank+'"]'),details=views.find(v=>v.id===view);selectedViews.set(rank,view);card.querySelector('.model-image').src=realm.images[view];card.querySelector('.model-image').alt=realm.title+' · '+details.type+' · '+details.label;card.querySelector('.image-kind').textContent=details.type+' · '+details.label;card.querySelector('.current-original').href=realm.images[view];card.querySelectorAll('[data-view]').forEach(button=>{const on=button.dataset.view===view;button.classList.toggle('active',on);button.setAttribute('aria-pressed',String(on));});}
function resetSize(){scroll.classList.remove('full');scroll.scrollLeft=0;scroll.scrollTop=0;sizeToggle.textContent='原始尺寸';}
function showRealm(index,view=activeView){overview=false;active=(index+realms.length)%realms.length;activeView=view;const realm=realms[active],details=views.find(v=>v.id===view);viewerTitle.textContent=realm.title+' · '+details.type+' · '+details.label;photo.src=realm.images[view];photo.alt=viewerTitle.textContent;original.href=realm.images[view];counter.textContent=realm.rank+' / '+realms.length;modalViews.hidden=false;modalViews.querySelectorAll('button').forEach(b=>{const on=b.dataset.modalView===view;b.classList.toggle('active',on);b.setAttribute('aria-pressed',String(on));});resetSize();if(!viewer.open)viewer.showModal();}
function showOverview(){overview=true;viewerTitle.textContent='十戒 · 实际 Blender 模型总览';photo.src='previews/all_realms.png';photo.alt=viewerTitle.textContent;original.href=photo.getAttribute('src');counter.textContent='十戒总览';modalViews.hidden=true;resetSize();if(!viewer.open)viewer.showModal();}
document.querySelectorAll('article [data-view]').forEach(button=>button.addEventListener('click',()=>selectCardView(Number(button.closest('article').dataset.rank),button.dataset.view)));
document.querySelectorAll('[data-zoom]').forEach(button=>button.addEventListener('click',()=>{const rank=Number(button.dataset.zoom);showRealm(rank-1,selectedViews.get(rank));}));
document.querySelector('[data-overview]').addEventListener('click',showOverview);
modalViews.querySelectorAll('button').forEach(button=>button.addEventListener('click',()=>showRealm(active,button.dataset.modalView)));
document.getElementById('previous').addEventListener('click',()=>showRealm(overview?realms.length-1:active-1,overview?'hero':activeView));
document.getElementById('next').addEventListener('click',()=>showRealm(overview?0:active+1,overview?'hero':activeView));
document.getElementById('viewer-close').addEventListener('click',()=>viewer.close());
sizeToggle.addEventListener('click',()=>{const full=scroll.classList.toggle('full');sizeToggle.textContent=full?'适应窗口':'原始尺寸';});
viewer.addEventListener('click',event=>{if(event.target===viewer)viewer.close();});
document.addEventListener('keydown',event=>{if(!viewer.open)return;if(event.key==='Escape'){event.preventDefault();viewer.close();return;}if(event.key==='ArrowLeft'||event.key==='ArrowRight'){event.preventDefault();showRealm(overview?(event.key==='ArrowLeft'?realms.length-1:0):active+(event.key==='ArrowLeft'?-1:1),overview?'hero':activeView);}else if(event.key==='ArrowUp'||event.key==='ArrowDown'){event.preventDefault();const index=views.findIndex(v=>v.id===activeView);showRealm(overview?0:active,views[(index+(event.key==='ArrowUp'?-1:1)+views.length)%views.length].id);}});
document.getElementById('copy-command').addEventListener('click',async()=>{const input=document.getElementById('review-command'),button=document.getElementById('copy-command');try{if(!navigator.clipboard)throw new Error('Clipboard unavailable');await navigator.clipboard.writeText(input.value);button.textContent='已复制';}catch(error){input.focus();input.select();button.textContent='已选中，请复制';}});
</script></body></html>\n`;
fs.writeFileSync(path.join(out, 'index.html'), html, 'utf8');
const expectedPreviews = ['previews/all_realms.png', ...realms.flatMap(r => [r.images.hero, r.images.top, r.images.detail])];
const missingPreviews = expectedPreviews.filter(file => !fs.existsSync(path.join(out, file)));
console.log(JSON.stringify({gallery: path.join(out, 'index.html'), models: realms.length,
  modelPreviews: expectedPreviews.length, availablePreviews: expectedPreviews.length-missingPreviews.length,
  missingPreviews, blenderCheck: blenderCheck.label, resourceVerification: verification.label,
  runtimeVerified: verification.data?.runtime_verified === true}, null, 2));
