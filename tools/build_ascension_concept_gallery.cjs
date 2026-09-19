// Approval gallery: show original concept PNGs directly, never composite/edit them.
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '..');
const out = path.join(root, 'output/ascension_arena_concepts_v1');
const source = JSON.parse(fs.readFileSync(path.join(out, 'prompts.json'), 'utf8').replace(/^\uFEFF/, ''));
const escape = value => String(value).replace(/[&<>"']/g, ch=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
const notes = {
  1:'普通夯土与细碎石，朴素、低矮，保留泥地的自然磨损。',
  2:'木梁与旧木板加固夯土地面，顺纹、端面和铁箍形成材料区别。',
  3:'由泥木过渡到粗青石，宽阔石板铺地配合低薄石台。',
  4:'砌石更加规整，台沿和四角收束完整，层次逐步清晰。',
  5:'浅色白石提升明度，温润表面配合克制的金属饰边。',
  6:'青玉镶面与白石相接，利用柔和光泽表现更精细的材料。',
  7:'冷色矿石与玄晶切面，强调抛光和哑光的差异，仍然落地。',
  8:'浅云开始托底，天玉地面逐步融入云面，进入凌空阶段。',
  9:'顶部以云面为主，玉石边框保留整体矩形轮廓。',
  10:'战斗面由柔软、平整且有实体轮廓的云层构成，完成云擂进阶。',
};
const tiers = source.tiers.slice().sort((a,b)=>a.rank-b.rank).map(t=>({
  rank:t.rank, name:t.name, materials:t.materials || [],
  file:`rank_${String(t.rank).padStart(2,'0')}.png`, note:notes[t.rank] || '',
}));
if(tiers.length !== 10 || tiers.some((t,i)=>t.rank !== i+1)) throw new Error('Expected one concept for every rank 1–10.');
const cards = tiers.map(t=>`<article class="card" id="rank-${t.rank}">
<div class="card-heading"><span class="rank-number">${String(t.rank).padStart(2,'0')}</span><div><h2>${t.rank} 转 · ${escape(t.name)}</h2><p class="layers">设计目标 · ${t.rank} 层低台基</p></div></div>
<button class="image-button" type="button" data-rank="${t.rank}" aria-label="放大 ${t.rank} 转 ${escape(t.name)}设计图"><img src="${t.file}" width="1536" height="1024" alt="${t.rank} 转 ${escape(t.name)}概念图：整体、俯视、侧视与材料" loading="${t.rank<=2?'eager':'lazy'}"><span class="zoom-hint">点击放大</span></button>
<div class="card-copy"><div class="materials">${t.materials.map(m=>`<span>${escape(m)}</span>`).join('')}</div><p>${escape(t.note)}</p><a class="original" href="${t.file}" target="_blank" rel="noopener">打开原图 ↗</a></div></article>`).join('\n');
const html = `<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>一至十转擂台 · 概念验看</title><style>
*{box-sizing:border-box}html{scroll-behavior:smooth;scroll-padding-top:88px}body{margin:0;background:#e8e4dc;color:#292f2b;font:16px/1.65 system-ui,"Microsoft YaHei",sans-serif}a{color:#3e645c;text-underline-offset:4px}button{font:inherit}a:focus-visible,button:focus-visible,summary:focus-visible{outline:3px solid #628c82;outline-offset:4px}header,main,footer{max-width:1640px;margin:0 auto;padding:26px 36px}header{padding-top:46px;padding-bottom:20px}.eyebrow{font-size:12px;letter-spacing:.19em;color:#6a7165}h1{font-size:clamp(28px,4vw,46px);font-weight:600;letter-spacing:.045em;line-height:1.3;margin:10px 0 12px}.lead{margin:0;color:#646a60;max-width:840px}.approval{display:inline-block;margin-top:18px;border:1px solid #b9b391;border-radius:4px;background:#f1ecd9;padding:4px 12px;font-size:13px;color:#665d38}.brief{display:grid;grid-template-columns:repeat(4,1fr);gap:18px;margin-top:26px}.brief>div{padding:14px 18px;border-left:2px solid #879489;background:#f5f2eb}.brief strong{font-size:22px;font-weight:550;display:block}.brief span{color:#6f756b;font-size:13px}.rank-nav{position:sticky;top:0;z-index:3;background:#e8e4dcf5;border-top:1px solid #d3cfc5;border-bottom:1px solid #cacbc0;backdrop-filter:blur(10px)}.rank-nav>div{max-width:1640px;margin:auto;padding:12px 36px;display:flex;align-items:center;gap:10px;overflow-x:auto}.rank-nav .label{font-size:12px;color:#71776b;margin-right:6px;white-space:nowrap}.rank-nav a{flex-shrink:0;text-decoration:none;border:1px solid #b9c0b4;background:#f4f2eb;border-radius:5px;padding:5px 15px;font-size:14px}.rank-nav a:hover{background:#dae3d8;border-color:#8ba18f}main{padding-top:28px}.gallery{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:26px}.card{border:1px solid #cbcfc2;background:#f5f2eb;border-radius:9px;overflow:hidden;scroll-margin-top:82px}.card-heading{display:flex;align-items:center;gap:17px;padding:19px 23px}.rank-number{font-family:Georgia,serif;font-size:35px;color:#8a9584;line-height:1}h2{font-size:21px;line-height:1.4;font-weight:550;margin:0}.layers{font-size:12px;color:#7a8175;margin:4px 0 0}.image-button{display:block;width:100%;padding:0;border:0;cursor:zoom-in;position:relative;background:#c2bfb6}.image-button img{display:block;width:100%;height:auto;aspect-ratio:3/2;object-fit:contain}.zoom-hint{position:absolute;bottom:12px;right:13px;color:#f5f1e6;background:#25342ccc;padding:4px 11px;border-radius:4px;font-size:12px;opacity:0;transition:opacity .15s}.image-button:hover .zoom-hint,.image-button:focus-visible .zoom-hint{opacity:1}.card-copy{padding:17px 23px 21px}.materials{display:flex;flex-wrap:wrap;gap:9px}.materials span{font-size:12px;color:#596957;background:#e3e7db;padding:2px 9px;border-radius:3px}.card-copy p{color:#66705f;font-size:14px;margin:12px 0 10px}.original{font-size:12px}.notes{margin:30px 0 8px;border:1px solid #c4c9bb;border-radius:6px;padding:18px 22px;font-size:14px}.notes summary{cursor:pointer;color:#4f5d49;font-weight:550}.notes p{color:#69705f}.notes ul{padding-left:21px;color:#69705f}.links{display:flex;flex-wrap:wrap;gap:20px}footer{font-size:12px;color:#7b8375;padding-bottom:42px}dialog{width:min(96vw,1660px);max-width:none;max-height:95vh;border:1px solid #667466;border-radius:8px;padding:0;background:#202820;color:#edece2;overflow:hidden}dialog::backdrop{background:#121812dd;backdrop-filter:blur(3px)}.viewer-header,.viewer-footer{display:flex;align-items:center;justify-content:space-between;padding:12px 17px;gap:12px}.viewer-header strong{font-size:16px;font-weight:500}.viewer-controls{display:flex;gap:8px;flex-wrap:wrap}.viewer-controls button,.viewer-footer button{cursor:pointer;border:1px solid #69745f;background:#303c30;color:#e7ebdc;border-radius:4px;padding:5px 12px;font-size:13px}.viewer-controls .close{font-size:20px;line-height:1.1;padding:5px 11px}.viewer-scroll{height:min(77vh,1030px);overflow:auto;display:flex;align-items:center;justify-content:center;background:#b6b1a6}.viewer-scroll img{display:block;max-width:100%;max-height:100%;width:auto;height:auto;object-fit:contain}.viewer-scroll.full{display:block}.viewer-scroll.full img{width:1536px;height:1024px;max-width:none;max-height:none}.viewer-footer{font-size:12px;color:#a6b29f}.viewer-footer a{color:#cedebf}.viewer-footer>div{display:flex;gap:12px;align-items:center}@media(max-width:1050px){header,main,footer{padding-left:22px;padding-right:22px}.rank-nav>div{padding-left:22px;padding-right:22px}.brief{grid-template-columns:repeat(2,1fr);gap:12px}.gallery{gap:18px}.card-heading,.card-copy{padding-left:17px;padding-right:17px}h2{font-size:18px}}@media(max-width:720px){header{padding-top:28px}.gallery{grid-template-columns:1fr}.rank-nav .label{display:none}.rank-nav a{padding:5px 12px}.brief strong{font-size:20px}.viewer-header{align-items:flex-start;flex-direction:column}.viewer-header strong{font-size:14px}.viewer-scroll{height:66vh}.viewer-footer .keyboard{display:none}.viewer-footer>div{gap:8px}.zoom-hint{opacity:1}.card-heading{padding-top:16px;padding-bottom:16px}}
</style></head><body>
<header><div class="eyebrow">ASCENSION ARENAS · CONCEPT SERIES 01—10</div><h1>一至十转擂台 · 概念验看</h1><p class="lead">从朴素泥地逐步进阶到云层擂台。先比较材料、台层与整体轮廓，验收后再制作模型。</p><span class="approval">设计待验收 · 尚未建模</span><div class="brief"><div><strong>700 × 350</strong><span>本批擂台整体占地 · 长 × 宽</span></div><div><strong>1 → 10 层</strong><span>低薄台基 · 每转增加一层</span></div><div><strong>900 × 900</strong><span>另行适用的练功房正方形规范</span></div><div><strong>开阔战斗面</strong><span>层高为示意 · 建模时再确定</span></div></div></header>
<nav class="rank-nav" aria-label="按转数跳转"><div><span class="label">转数</span>${tiers.map(t=>`<a href="#rank-${t.rank}">${t.rank} 转</a>`).join('')}</div></nav>
<main><section class="gallery" aria-label="十张擂台概念设计图">${cards}</section><details class="notes"><summary>设计约束与制作说明</summary><p>十张均为审批前概念图，主要用于确认风格、材料、轮廓与层次。整体占地的设计目标为长 700 × 宽 350；900 × 900 是练功房规范，两者分别适用。</p><ul><li>一至十转分别设计一至十层低台基，台层清晰可数，单层高度与总高度尚未确定。</li><li>上方保持宽阔平整，装饰留在四角及边缘；不采用高耸金字塔、角色、巨塔或强发光。</li><li>一至七转落地，八转浅云托底并出现局部云面，九转以云面为主，十转以有实体轮廓的柔软云层作为战斗面。</li><li>当前未建模，也不表示既有练功房已经调整到新尺寸。模型边界、碰撞、导航和实机效果需在后续阶段验证。</li></ul><div class="links"><a href="../../docs/ai/ASCENSION_ARENA_CONCEPTS.md">完整设计与验收规范</a><a href="prompts.json">概念制作记录</a></div></details></main><footer>原始设计图直接展示 · 1536 × 1024 PNG · 点击图片可放大，左右方向键切换，Esc 关闭</footer>
<dialog id="viewer" aria-labelledby="viewer-title"><div class="viewer-header"><strong id="viewer-title"></strong><div class="viewer-controls"><button type="button" id="size-toggle">原始尺寸</button><button type="button" class="close" id="viewer-close" aria-label="关闭大图">×</button></div></div><div class="viewer-scroll" id="viewer-scroll"><img id="viewer-image" width="1536" height="1024" alt=""></div><div class="viewer-footer"><div><button type="button" id="previous">← 上一转</button><span id="viewer-count"></span><button type="button" id="next">下一转 →</button></div><span class="keyboard">← → 切换 · Esc 关闭</span><a id="viewer-original" target="_blank" rel="noopener">打开原图 ↗</a></div></dialog>
<script>
const concepts=${JSON.stringify(tiers).replace(/</g,'\\u003c')};
const viewer=document.getElementById('viewer'),photo=document.getElementById('viewer-image'),scroll=document.getElementById('viewer-scroll'),title=document.getElementById('viewer-title'),counter=document.getElementById('viewer-count'),original=document.getElementById('viewer-original'),sizeToggle=document.getElementById('size-toggle');
let active=0;
function showConcept(index){active=(index+concepts.length)%concepts.length;const t=concepts[active];title.textContent=t.rank+' 转 · '+t.name;photo.src=t.file;photo.alt=t.rank+' 转 '+t.name+'概念设计原图';counter.textContent=t.rank+' / '+concepts.length;original.href=t.file;scroll.classList.remove('full');sizeToggle.textContent='原始尺寸';scroll.scrollTop=0;scroll.scrollLeft=0;if(!viewer.open)viewer.showModal();}
document.querySelectorAll('[data-rank]').forEach(button=>button.addEventListener('click',()=>showConcept(Number(button.dataset.rank)-1)));
document.getElementById('viewer-close').addEventListener('click',()=>viewer.close());
document.getElementById('previous').addEventListener('click',()=>showConcept(active-1));
document.getElementById('next').addEventListener('click',()=>showConcept(active+1));
sizeToggle.addEventListener('click',()=>{const full=scroll.classList.toggle('full');sizeToggle.textContent=full?'适应窗口':'原始尺寸';});
viewer.addEventListener('click',event=>{if(event.target===viewer)viewer.close();});
document.addEventListener('keydown',event=>{if(!viewer.open)return;if(event.key==='ArrowLeft'){event.preventDefault();showConcept(active-1);}else if(event.key==='ArrowRight'){event.preventDefault();showConcept(active+1);}else if(event.key==='Escape'){event.preventDefault();viewer.close();}});
</script></body></html>\n`;
let finalHtml=html.replace('<a href="prompts.json">概念制作记录</a>',
 '<a href="prompts.json">初版提示词（内置 imagegen）</a><a href="refinement_prompts.json">九、十转分层修订提示词</a>');
if(source.status==='approved_for_first_model_pass')finalHtml=finalHtml
 .replace('先比较材料、台层与整体轮廓，验收后再制作模型。','已据此制作首版模型，可与原设计逐转对照。')
 .replace('设计待验收 · 尚未建模','概念已认可 · 首版模型已制作')
 .replace('层高为示意 · 建模时再确定','首版模型每层 14 单位')
 .replace('十张均为审批前概念图，主要用于确认风格、材料、轮廓与层次。','十张为已认可的原概念图，用于对照模型的风格、材料、轮廓与层次。')
 .replace('单层高度与总高度尚未确定。','首版模型每层高度为 14 单位。')
 .replace('当前未建模，也不表示既有练功房已经调整到新尺寸。模型边界、碰撞、导航和实机效果需在后续阶段验证。','首版擂台模型已制作；既有练功房 900 × 900 尺寸调整属于另一项工作。实机导航及最终光照需要游戏内验看。')
 .replace('<div class="links">','<div class="links"><a href="../ascension_arenas/index.html">首版模型与概念对照</a>');
fs.writeFileSync(path.join(out,'index.html'),finalHtml,'utf8');
const imageStatus=tiers.map(t=>({rank:t.rank,file:t.file,exists:fs.existsSync(path.join(out,t.file))}));
console.log(JSON.stringify({gallery:path.join(out,'index.html'),specification:path.join(root,'docs/ai/ASCENSION_ARENA_CONCEPTS.md'),conceptRecord:path.join(out,'prompts.json'),expectedImages:tiers.length,availableImages:imageStatus.filter(t=>t.exists).length,images:imageStatus},null,2));
