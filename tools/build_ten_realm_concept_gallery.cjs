// Display the original approval sheets directly; never redraw or composite them.
'use strict';
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '..');
const args = process.argv.slice(2);
if (args.length > 1 || args.some(arg => !/^--version=v[12]$/.test(arg))) {
  throw new Error('Usage: node tools/build_ten_realm_concept_gallery.cjs [--version=v2|--version=v1]');
}
const version = args.length ? args[0].slice('--version='.length) : 'v2';
const square = version === 'v2';
const directories = {v1: 'ten_realm_arena_concepts_v1', v2: 'ten_realm_arena_concepts_v2_700x700'};
const out = path.join(root, 'output', directories[version]);
const record = path.join(out, 'prompts.json');
const source = JSON.parse(fs.readFileSync(record, 'utf8').replace(/^\uFEFF/, ''));
const isSquareFootprint = value => Array.isArray(value) && value.length === 2 && value.every(n => n === 700);
if (square && (!isSquareFootprint(source.footprint_game_units)
  || !Array.isArray(source.tiers) || source.tiers.some(t => !isSquareFootprint(t.footprint_game_units)))) {
  throw new Error('Version 2 requires a 700 × 700 game-unit footprint for all ten arenas.');
}
const escape = value => String(value).replace(/[&<>"']/g, ch => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
}[ch]));
const chinese = ['一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
const notes = {
  1: '风蚀砂岩围合干燥沙地，沙丘留在外围；湿沙逐渐过渡到水下浅滩。',
  2: '林土、苔石与根系构成天然围合，树冠退到外侧，保留中央林间空地。',
  3: '压实泥炭承载战斗，腐木与低苔墙围合；芦苇、湿泥与浅水分布在外围。',
  4: '层理明显的红砂岩与断崖围合开阔砾地，崩落碎岩自然延伸入水。',
  5: '冻土、浅雪与霜白石墙形成冷地环境，冰缘与湿岩接入清冷海水。',
  6: '浅色珊瑚石与贝砂形成海岛质感，外围潮池、海草和礁盘依次衔接。',
  7: '冷却玄武岩、焦岩和暗铜表现火山地貌，黑礁在岸边呈现湿润反光。',
  8: '矿岩与石英切面依靠日光呈现光泽，晶簇集中于外缘与低矮墙角。',
  9: '浅白石、青金细节与繁茂花草表现天辉气质，苔岩和草岸自然落入浅水。',
  10: '灰岩、骨白棘饰与枯根表现夜魇气质，暗色环境仍保留清晰的地表层次。',
};
const tiers = (source.tiers || []).slice().sort((a, b) => a.rank - b.rank).map(t => ({
  rank: t.rank, name: t.name, terrain: t.terrain, materials: t.materials || [],
  shore: t.shore, file: t.file, note: notes[t.rank] || '',
}));
if (tiers.length !== 10 || tiers.some((t, i) => t.rank !== i + 1)) {
  throw new Error('Expected ten concept sheets, numbered 1–10.');
}
for (const t of tiers) {
  if (t.file !== `realm_${String(t.rank).padStart(2, '0')}.png`) {
    throw new Error(`Unexpected concept image path for realm ${t.rank}.`);
  }
  if (!t.name || !t.terrain || !t.shore || !Array.isArray(t.materials)) {
    throw new Error(`Incomplete concept metadata for realm ${t.rank}.`);
  }
}
const title = t => `${chinese[t.rank - 1]}戒 · ${t.name}`;
const pageTitle = square ? '一至十戒 · 700 × 700 正方形场地' : '一至十戒 · 初版封闭场地概念';
const sizeLabel = square ? '700 × 700 游戏单位 · 正方形主体含围墙' : '初版概念 · 未绑定游戏单位尺寸';
const dimensionNote = square
  ? '十处场地主体统一为 700 × 700 游戏单位的正方形，尺寸包含完整围墙；自然岸地、浅滩及水面沿主体外围延伸。设计图为 1536 × 1024 像素的横向画板，图片像素不代表场地长宽比例。'
  : '此页保留初版近矩形构图，当时尚未绑定游戏单位尺寸。当前方案已改为 700 × 700 正方形主体，见第二版图库。';
const editionLink = square
  ? '<a href="../ten_realm_arena_concepts_v1/index.html">查看初版历史图集</a>'
  : '<a href="../ten_realm_arena_concepts_v2_700x700/index.html">查看当前 700 × 700 正方形图集</a>';
const directLinks = tiers.map(t => `<a href="${t.file}" target="_blank" rel="noopener">${String(t.rank).padStart(2, '0')} · ${escape(t.name)} ↗</a>`).join('');
const cards = tiers.map(t => `<article class="card" id="realm-${t.rank}">
  <div class="card-heading"><span class="number">${String(t.rank).padStart(2, '0')}</span><div><h2>${escape(title(t))}</h2><p class="terrain">${escape(t.terrain)}</p><p class="dimensions">${escape(sizeLabel)}</p></div></div>
  <button type="button" class="image-button" data-realm="${t.rank}" aria-label="放大${escape(title(t))}概念图"><img src="${t.file}" width="1536" height="1024" alt="${escape(title(t))}：整体、俯视布局与岸线衔接" loading="${t.rank <= 2 ? 'eager' : 'lazy'}"><span class="zoom-hint">点击放大</span></button>
  <div class="card-copy"><div class="materials">${t.materials.map(m => `<span>${escape(m)}</span>`).join('')}</div><p>${escape(t.note)}</p><p class="shore"><strong>岸线</strong> ${escape(t.shore)}</p><a class="original" href="${t.file}" target="_blank" rel="noopener">打开原图 ↗</a></div>
</article>`).join('\n');
const html = `<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>${escape(pageTitle)}</title><style>
*{box-sizing:border-box}html{scroll-behavior:smooth;scroll-padding-top:88px}body{margin:0;background:#e7e6df;color:#28312e;font:16px/1.65 system-ui,"Microsoft YaHei",sans-serif}a{color:#306d70;text-underline-offset:4px}button{font:inherit}a:focus-visible,button:focus-visible,summary:focus-visible{outline:3px solid #488a8c;outline-offset:4px}header,main,footer{max-width:1640px;margin:auto;padding:26px 36px}header{padding-top:46px;padding-bottom:22px}.eyebrow{font-size:12px;letter-spacing:.18em;color:#627975}h1{font-size:clamp(27px,4vw,44px);line-height:1.3;font-weight:600;letter-spacing:.04em;margin:10px 0 12px}.lead{max-width:910px;margin:0;color:#60716a}.status{display:inline-block;margin-top:18px;border:1px solid #bbb497;background:#f0eddc;border-radius:4px;padding:4px 12px;font-size:13px;color:#665e3c}.brief{display:grid;grid-template-columns:repeat(4,1fr);gap:16px;margin-top:26px}.brief>div{padding:14px 17px;border-left:2px solid #71938b;background:#f3f3ec}.brief strong{font-size:21px;font-weight:550;display:block}.brief span{color:#6a7970;font-size:13px}.realm-nav{position:sticky;top:0;z-index:3;background:#e7e6dff5;border-top:1px solid #ccd1c7;border-bottom:1px solid #c4cdc2;backdrop-filter:blur(10px)}.realm-nav>div{max-width:1640px;margin:auto;padding:12px 36px;display:flex;align-items:center;gap:9px;overflow-x:auto}.realm-nav a{flex-shrink:0;text-decoration:none;border:1px solid #b7c6bd;background:#f4f4ee;border-radius:4px;padding:5px 13px;font-size:13px}.realm-nav a:hover{background:#dce8de;border-color:#729b91}main{padding-top:28px}.gallery{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:26px}.card{border:1px solid #c5cec1;background:#f5f4ee;border-radius:9px;overflow:hidden;scroll-margin-top:82px}.card-heading{display:flex;align-items:center;gap:17px;padding:19px 23px}.number{font-family:Georgia,serif;font-size:35px;color:#78918a;line-height:1}h2{font-size:21px;line-height:1.4;font-weight:550;margin:0}.terrain{font-size:12px;color:#738279;margin:4px 0 0}.image-button{display:block;width:100%;padding:0;border:0;cursor:zoom-in;position:relative;background:#bfbbb0}.image-button img{display:block;width:100%;height:auto;aspect-ratio:3/2;object-fit:contain}.zoom-hint{position:absolute;bottom:12px;right:13px;background:#24413dcc;color:#f4f1e6;padding:4px 11px;border-radius:4px;font-size:12px;opacity:0;transition:opacity .15s}.image-button:hover .zoom-hint,.image-button:focus-visible .zoom-hint{opacity:1}.card-copy{padding:17px 23px 21px}.materials{display:flex;flex-wrap:wrap;gap:8px}.materials span{background:#e0e9df;color:#51695a;border-radius:3px;padding:2px 9px;font-size:12px}.card-copy p{font-size:14px;color:#637367;margin:12px 0}.card-copy .shore{font-size:12px;color:#3d746d;margin-bottom:13px}.shore strong{font-weight:550;margin-right:7px}.original{font-size:12px}.notes{margin:30px 0 8px;border:1px solid #bdc9bb;border-radius:6px;padding:18px 22px;font-size:14px}.notes summary{cursor:pointer;font-weight:550;color:#486151}.notes p,.notes ul{color:#66755f}.notes ul{padding-left:21px}.notes li+li{margin-top:6px}.links{display:flex;flex-wrap:wrap;gap:20px}footer{font-size:12px;color:#718071;padding-bottom:40px}dialog{width:min(96vw,1660px);max-width:none;max-height:95vh;padding:0;border:1px solid #57756b;border-radius:8px;background:#1e2c28;color:#eeeee6;overflow:hidden}dialog::backdrop{background:#10211ddd;backdrop-filter:blur(3px)}.viewer-header,.viewer-footer{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:12px 17px}.viewer-header strong{font-size:16px;font-weight:500}.viewer-controls{display:flex;gap:8px}.viewer-controls button,.viewer-footer button{cursor:pointer;border:1px solid #59776a;border-radius:4px;background:#2b4037;color:#e4ece0;padding:5px 12px;font-size:13px}.viewer-controls .close{font-size:20px;line-height:1.1;padding:5px 11px}.viewer-scroll{height:min(77vh,1030px);overflow:auto;display:flex;align-items:center;justify-content:center;background:#b9b4a9}.viewer-scroll img{display:block;max-width:100%;max-height:100%;width:auto;height:auto;object-fit:contain}.viewer-scroll.full{display:block}.viewer-scroll.full img{max-width:none;max-height:none;width:auto;height:auto}.viewer-footer{font-size:12px;color:#a0b5a6}.viewer-footer>div{display:flex;align-items:center;gap:12px}.viewer-footer a{color:#c8ddd1}@media(max-width:1050px){header,main,footer{padding-left:22px;padding-right:22px}.realm-nav>div{padding-left:22px;padding-right:22px}.brief{grid-template-columns:repeat(2,1fr);gap:12px}.gallery{gap:18px}.card-heading,.card-copy{padding-left:17px;padding-right:17px}h2{font-size:18px}}@media(max-width:720px){header{padding-top:28px}.gallery{grid-template-columns:1fr}.brief strong{font-size:19px}.realm-nav a{padding:5px 10px}.viewer-header{align-items:flex-start;flex-direction:column}.viewer-header strong{font-size:14px}.viewer-scroll{height:66vh}.viewer-footer .keyboard{display:none}.viewer-footer>div{gap:7px}.zoom-hint{opacity:1}}@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}*{transition:none!important}}
.dimensions{display:inline-block;font-size:12px;font-weight:550;color:#2c675b;background:#e2ece1;border:1px solid #bed1bd;border-radius:4px;padding:2px 8px;margin:8px 0 0}.dimension-note{font-size:14px;color:#55705f;max-width:1080px;margin:15px 0 0}.originals{margin-bottom:26px;border:1px solid #bdcbbf;background:#f1f4eb;border-radius:7px;padding:18px 22px}.originals h2{font-size:17px}.originals p{color:#6b7c6c;font-size:12px;margin:5px 0 13px}.original-grid{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:10px}.original-grid a{font-size:13px;text-decoration:none;border:1px solid #c7d4c5;border-radius:4px;padding:8px 10px;background:#f9faf4}.original-grid a:hover{background:#e2ecdf}@media(max-width:1050px){.original-grid{grid-template-columns:repeat(3,minmax(0,1fr))}}@media(max-width:720px){.original-grid{grid-template-columns:repeat(2,minmax(0,1fr))}.dimensions{font-size:11px}.originals{padding:16px}}
</style></head><body>
<header><div class="eyebrow">TEN REALMS · ENCLOSED ARENA CONCEPTS · ${version.toUpperCase()}</div><h1>${escape(pageTitle)}</h1><p class="lead">十种地貌，完整十张独立露天场地设计。比较围合方式、地表材料和从陆地到水面的自然过渡，中央始终保留开阔战斗空间。</p><p class="dimension-note">${escape(dimensionNote)}</p><span class="status">${square ? '第二版概念待验收 · 尚未建模' : '初版历史概念 · 尚未建模'}</span><div class="brief"><div><strong>${square ? '700 × 700' : '十种地貌'}</strong><span>${square ? '游戏单位 · 正方形主体含围墙' : '初版构图 · 当前规范见第二版'}</span></div><div><strong>四面闭合</strong><span>露天围合 · 两侧预留落点</span></div><div><strong>中央净空</strong><span>平整连续 · 装饰集中外缘</span></div><div><strong>自然岸线外延</strong><span>主体外衔接湿岸、浅滩与深水</span></div></div></header>
<nav class="realm-nav" aria-label="按地貌跳转"><div>${tiers.map(t => `<a href="#realm-${t.rank}">${String(t.rank).padStart(2, '0')} ${escape(t.terrain.replace('出生地风格', ''))}</a>`).join('')}</div></nav>
<main><section class="originals" aria-labelledby="originals-title"><h2 id="originals-title">完整十张 · 原图直达</h2><p>以下链接分别打开每一戒的完整设计图；下方同时展示全部十张。</p><div class="original-grid">${directLinks}</div></section><section class="gallery" aria-label="十张独立场地概念图">${cards}</section><details class="notes"><summary>设计约束与制作说明</summary><p>当前用于确认十种地貌、完整围合和水岸衔接。每张展示同一方案的整体、俯视布局与岸线细节；图中材料表现为建模目标。</p><ul><li>${escape(dimensionNote)}</li><li>四边均有连续低矮实体边界，包括正前方；上方露天。相对两侧的圆纹是落点构图预留，尚未改动玩法。</li><li>内场约三分之二保留为连续开阔战斗面，水沟、礁石、树根与高植被安排在外围。</li><li>外岛岸线自然、不规则，按干地 → 湿岸 → 可见水下浅滩 → 深水衔接；十种地貌分别采用相应土壤、岩石与植被。</li><li>“地方出生地”暂按敌方夜魇出生地风格理解，与九戒天辉圣庭形成区别。</li><li>本轮为概念设计，尚未制作模型或接入地图；边界、碰撞、导航及实机效果留待模型阶段验证。</li></ul><div class="links"><a href="../../docs/ai/TEN_REALM_ARENA_CONCEPTS.md">设计与验收规范</a><a href="prompts.json">概念制作记录</a>${editionLink}</div></details></main>
<footer>原始 PNG 直接展示 · 图片分辨率 1536 × 1024 像素${square ? ' · 场地主体 700 × 700 游戏单位' : ''} · 点击放大，左右方向键切换，Esc 关闭</footer>
<dialog id="viewer" aria-labelledby="viewer-title"><div class="viewer-header"><strong id="viewer-title"></strong><div class="viewer-controls"><button type="button" id="size-toggle">原始尺寸</button><button type="button" class="close" id="viewer-close" aria-label="关闭大图">×</button></div></div><div class="viewer-scroll" id="viewer-scroll"><img id="viewer-image" alt=""></div><div class="viewer-footer"><div><button type="button" id="previous">← 上一张</button><span id="viewer-count"></span><button type="button" id="next">下一张 →</button></div><span class="keyboard">← → 切换 · Esc 关闭</span><a id="viewer-original" target="_blank" rel="noopener">打开原图 ↗</a></div></dialog>
<script>
const concepts=${JSON.stringify(tiers.map(t => ({...t, title: title(t)}))).replace(/</g, '\\u003c')};
const viewer=document.getElementById('viewer'),photo=document.getElementById('viewer-image'),scroll=document.getElementById('viewer-scroll'),title=document.getElementById('viewer-title'),counter=document.getElementById('viewer-count'),original=document.getElementById('viewer-original'),sizeToggle=document.getElementById('size-toggle');
let active=0;
function showConcept(index){active=(index+concepts.length)%concepts.length;const t=concepts[active];title.textContent=t.title+' · '+t.terrain;photo.src=t.file;photo.alt=t.title+'概念设计原图';counter.textContent=t.rank+' / '+concepts.length;original.href=t.file;scroll.classList.remove('full');sizeToggle.textContent='原始尺寸';scroll.scrollTop=0;scroll.scrollLeft=0;if(!viewer.open)viewer.showModal();}
document.querySelectorAll('[data-realm]').forEach(button=>button.addEventListener('click',()=>showConcept(Number(button.dataset.realm)-1)));
document.getElementById('viewer-close').addEventListener('click',()=>viewer.close());
document.getElementById('previous').addEventListener('click',()=>showConcept(active-1));
document.getElementById('next').addEventListener('click',()=>showConcept(active+1));
sizeToggle.addEventListener('click',()=>{const full=scroll.classList.toggle('full');sizeToggle.textContent=full?'适应窗口':'原始尺寸';});
viewer.addEventListener('click',event=>{if(event.target===viewer)viewer.close();});
document.addEventListener('keydown',event=>{if(!viewer.open)return;if(event.key==='ArrowLeft'){event.preventDefault();showConcept(active-1);}else if(event.key==='ArrowRight'){event.preventDefault();showConcept(active+1);}else if(event.key==='Escape'){event.preventDefault();viewer.close();}});
</script></body></html>\n`;
fs.writeFileSync(path.join(out, 'index.html'), html, 'utf8');
const images = tiers.map(t => ({rank: t.rank, file: t.file, exists: fs.existsSync(path.join(out, t.file))}));
console.log(JSON.stringify({
  version,
  gallery: path.join(out, 'index.html'),
  specification: path.join(root, 'docs/ai/TEN_REALM_ARENA_CONCEPTS.md'),
  conceptRecord: record,
  expectedImages: tiers.length,
  availableImages: images.filter(t => t.exists).length,
  images,
}, null, 2));
