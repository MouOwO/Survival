// Static, offline review pages for the three independent themed practice rooms.
// Photographs are Blender previews; compiled-asset status comes from the verifier.
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '..');
const output = path.join(root, 'output');
const themes = [
  {key:'wood', folder:'wood_training_room', title:'木材练功房', en:'TIMBER YARD', accent:'#c9a476',
    intro:'顺纹木梁、旧木地板与原木锯架，让木材成为房间的主体。',
    detail:'木纤维、节疤、端面年轮和开裂分别处理；磨亮的木面、粗糙树皮与旧铁箍呈现不同反光。',
    features:['错缝木板与木墙','原木端面与树皮','锯架与木材徽记'], challenge:'01'},
  {key:'attribute', folder:'attribute_training_room', title:'属性练功房', en:'JADE GROWTH', accent:'#88b4a2',
    intro:'浅冷石材围合翠玉庭院，以三瓣生长纹表现力量的积累。',
    detail:'磨损石面保持柔和反光；翠玉矿物、银铜嵌件与哑光挂旗彼此区分，矿簇集中在外围。',
    features:['翠玉三瓣成长纹','浅冷石材与银铜','外围翠玉矿簇'], challenge:'03'},
  {key:'greater_attribute', folder:'greater_attribute_training_room', title:'大属性练功房', en:'CRYSTAL CROWN', accent:'#ac9fd1',
    intro:'深色矿石承托蓝紫切面晶体，银金饰边与三晶冠形成更高阶的识别。',
    detail:'深石地面控制明暗反差，浅色石缘留在外围；晶体切面和分层金属嵌件强化材质差异。',
    features:['三晶冠与六边地纹','深石与蓝紫晶体','分层银金饰边'], challenge:'04'},
];
const read = file => JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
const escape = value => String(value).replace(/[&<>"']/g, ch=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
const css = `
*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:#181d1d;color:#ece9e0;font:16px/1.75 system-ui,"Microsoft YaHei",sans-serif}a{color:var(--accent,#c6bd9f);text-underline-offset:4px}a:focus-visible,button:focus-visible{outline:2px solid var(--accent);outline-offset:5px}header,main,footer{max-width:1320px;margin:auto;padding:24px 32px}header{padding-top:46px;padding-bottom:12px}footer{font-size:13px;color:#929c97;padding-bottom:48px}h1{font-size:clamp(30px,4vw,50px);line-height:1.25;font-weight:600;margin:10px 0 16px;letter-spacing:.03em}h2{font-size:25px;font-weight:550;margin:0 0 10px}h3{font-weight:550;margin:12px 0 5px}.eyebrow{font-size:12px;color:var(--accent);letter-spacing:.2em}.lead{max-width:860px;color:#c7d0c8;margin:8px 0 22px}.nav,.tags,.actions{display:flex;flex-wrap:wrap;gap:10px}.nav{margin:22px 0 10px}.nav a{font-size:14px;padding:8px 15px;border:1px solid #44504a;border-radius:30px;text-decoration:none}.nav .active{background:var(--accent);border-color:var(--accent);color:#18211c}.tags{margin:12px 0 24px}.tags span{font-size:12px;border-left:2px solid var(--accent);padding:0 12px;color:#d0d5cb}.hero{display:block;width:100%;border-radius:10px}.caption{color:#9faa9f;font-size:13px;margin:9px 0 0}.section{margin:40px 0}.split{display:grid;grid-template-columns:1.18fr 1fr;gap:22px}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:20px}.reference-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:20px}figure{margin:0}figure img{display:block;width:100%;border-radius:8px;background:#292e2a}figcaption{font-size:14px;color:#b6c1b6;margin-top:10px}.room-card{background:#232a27;border:1px solid #3e4b42;border-radius:10px;overflow:hidden}.room-card>img,.room-card>a>img{display:block;width:100%;aspect-ratio:4/3;object-fit:cover}.card-body{padding:20px 22px 23px}.card-body p{font-size:14px;color:#b7c3b8;margin:8px 0 18px}.actions a,.button{background:#2c3630;border:1px solid #52614f;border-radius:5px;padding:9px 15px;font-size:14px;text-decoration:none}.meta{font-size:13px;color:#a8b6a9;margin:9px 0}.notice{border-left:3px solid var(--accent);background:#242c27;padding:13px 18px;color:#bdc8bd;font-size:14px;margin:22px 0}details{margin:24px 0;padding:18px 21px;border:1px solid #435044;border-radius:8px}summary{cursor:pointer;color:#d7ded2}code{font-size:13px;font-family:Consolas,monospace;overflow-wrap:anywhere}pre{white-space:pre-wrap;overflow-wrap:anywhere;padding:15px 18px;background:#111814;border-radius:6px}.test{margin-top:26px;padding-top:20px;border-top:1px solid #3d493f}.inline-links{font-size:14px;display:flex;gap:15px;flex-wrap:wrap}.back{font-size:13px;text-decoration:none}.reference-grid .room-card>a>img{aspect-ratio:16/10}.reference-grid h3{margin-top:0}@media(max-width:900px){.grid{grid-template-columns:1fr}.room-card>a>img{aspect-ratio:16/9}.split{grid-template-columns:1fr}.reference-grid{grid-template-columns:1fr}}@media(max-width:600px){header,main,footer{padding-left:18px;padding-right:18px}.nav a{padding:7px 12px}.section{margin:30px 0}.tags{gap:7px}.tags span{padding:0 8px}}
`;
const document = (title,accent,body) => `<!doctype html>\n<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>${escape(title)}</title><style>${css}</style></head><body style="--accent:${accent}">${body}</body></html>\n`;
const nav = (active, summary=false) => `<nav class="nav" aria-label="房间主题">${summary?'':`<a href="../training_rooms/index.html">全部房间</a>`}${themes.map(t=>`<a${t.key===active?' class="active" aria-current="page"':''} href="../${t.folder}/index.html">${t.title}</a>`).join('')}</nav>`;
const photo = (file,caption) => `<figure><a href="previews/${file}.png" target="_blank" rel="noopener"><img src="previews/${file}.png" loading="lazy" alt="${escape(caption)}，Blender 预览"></a><figcaption>${escape(caption)}</figcaption></figure>`;
const stats = [];
for(const t of themes){
  const dir = path.join(output,t.folder);
  const assets = read(path.join(dir,'asset_manifest.json'));
  const materials = read(path.join(dir,'material_manifest.json'));
  const layout = read(path.join(dir,'room_layout.json'));
  const map = read(path.join(dir,'map_manifest.json'));
  const verifyPath = path.join(dir,'verification.json');
  const verified = fs.existsSync(verifyPath) ? read(verifyPath) : null;
  const state = verified?.status === 'PASS' ? '实际编译资源检查已通过。' : '实际编译资源检查结果以 verification.json 为准。';
  const count = `${assets.length} 个自制模块 · ${materials.length} 套材质 · ${layout.placements.length} 个场景实例`;
  const command = `dota_launch_custom_game survival ${map.review}`;
  const body = `<header><a class="back" href="../training_rooms/index.html">← 练功房材质与主题总览</a><div class="eyebrow" style="margin-top:24px">${t.en} · PRACTICE ROOM</div><h1>${t.title}</h1><p class="lead">${t.intro}</p>${nav(t.key)}<div class="tags">${t.features.map(f=>`<span>${f}</span>`).join('')}</div></header>
<main><a href="previews/room_overview.png" target="_blank" rel="noopener"><img class="hero" src="previews/room_overview.png" alt="${t.title}整体，Blender 同照明预览"></a><p class="caption">Blender 同照明预览 · 图片可点击放大 · 全部为普通受光材质，无自发光或粒子。</p>
<section class="section"><h2>材质与主题细节</h2><p class="lead">${t.detail}</p><div class="split">${photo('material_detail','近看材料：表面起伏、磨损与反光差异')}${photo('entry_detail','后侧入口：独立纹章、挂旗与传送底座')}</div></section>
<section class="section"><h2>保持开阔的战斗区</h2>${photo('room_top','俯视布局：2048 × 2304 内场，装饰集中于外围')}<p class="meta">${count}</p></section>
<section class="section"><h2>打开场景</h2><div class="actions"><a href="${t.folder}.blend">Blender 完整场景</a><a href="source/maps/${map.review}.vmap">Hammer 测试地图</a><a href="source/maps/${map.prefab}.vmap">房间预制件</a></div><div class="test"><p>在 Workshop 控制台粘贴：</p><pre><code>${command}</code></pre><p class="meta">也可双击项目中的「打开地图测试.cmd」，选择对应房间。</p></div></section>
<details><summary>制作与验证说明</summary><p>沿用已认可的金币房表面处理：法线与反射随材料变化，保留石材、木材、矿物、金属和布料的区别。</p><p>Source 2 使用 <code>global_lit_simple.vfx</code>、显式法线与线性 R 通道反射遮罩；粗糙度和金属度贴图用于 Blender 预览，两种着色器的表现并非完全相同。</p><p>${state} 本页展示 Blender 渲染，不把静态资源检查作为实机画质或导航验收。</p><p>独立样板对应 <code>challenge_${t.challenge}</code> 的入口、归位点与八个刷怪标记；正式地图及玩法未替换。</p><div class="inline-links"><a href="verification.json">编译资源验证</a><a href="material_manifest.json">材质清单</a><a href="asset_manifest.json">模型清单</a><a href="room_layout.json">场景摆放</a><a href="map_manifest.json">地图信息</a></div></details></main><footer>练功房主题打磨 · 可编辑模型与材质 · 图像为离线 Blender 预览</footer>`;
  fs.writeFileSync(path.join(dir,'index.html'),document(t.title+' · 材质与主题',t.accent,body));
  stats.push({theme:t.key,modules:assets.length,materials:materials.length,instances:layout.placements.length,compiledVerification:verified?.status||'not available'});
}
const cards = themes.map(t=>`<article class="room-card" style="--accent:${t.accent}"><a href="../${t.folder}/index.html"><img src="../${t.folder}/previews/room_overview.png" alt="${t.title}整体，Blender 预览" loading="lazy"></a><div class="card-body"><div class="eyebrow">${t.en}</div><h2>${t.title}</h2><p>${t.intro}</p><a href="../${t.folder}/index.html">查看房间与细节 →</a></div></article>`).join('');
const summary = `<header><div class="eyebrow">PRACTICE ROOMS · SURFACE &amp; IDENTITY</div><h1>练功房 · 材质与主题</h1><p class="lead">延续金币练功房的材质表现，让木材、翠玉、矿晶与熔火各自有清晰的质感。</p>${nav(null,true)}</header><main><div class="notice">下方为 Blender 预览，沿用金币房的照明条件。点击房间查看全景、俯视与近景；实际游戏表现仍需在对应测试地图中验看。</div><section class="grid section">${cards}</section><section class="section"><h2>熔火打磨与金币基准</h2><div class="reference-grid"><article class="room-card" style="--accent:#d7a078"><a href="../molten_core_room/material_review/index.html"><img src="../molten_core_room/material_review/basalt_copper_after.png" alt="熔火核心玄武岩与旧铜，修改后 Blender 预览" loading="lazy"></a><div class="card-body"><h3>熔火核心挑战房</h3><p>玄武岩孔隙、焦黑石面、氧化旧铜与锻铁火盆，保留材料之间的反光差异。</p><a href="../molten_core_room/material_review/index.html">查看材质前后对比 →</a></div></article><article class="room-card" style="--accent:#d3be83"><a href="../gold_training_room/material_review/index.html"><img src="../gold_training_room/material_review/stone_coin_after.png" alt="金币房石材与金币，已认可的 Blender 材质基准" loading="lazy"></a><div class="card-body"><h3>金币练功房 · 已认可基准</h3><p>石面起伏、磨损面的反光，金币与青铜的氧化和磨亮区域。</p><a href="../gold_training_room/material_review/index.html">查看金币材质基准 →</a></div></article></div></section><details><summary>编辑与检查</summary><p>三个新房间分别保存为独立 Blender 场景、Hammer 地图与预制件，可通过项目「打开地图测试.cmd」选择打开。正式地图与玩法仍保持原状。</p><p>模型、纹理、材质编译及地图 VPK 检查见各房间的 <code>verification.json</code>；当前图集不宣称已完成实机外观与行走验证。</p><div class="inline-links">${themes.map(t=>`<a href="../${t.folder}/verification.json">${t.title}资源检查</a>`).join('')}<a href="../../docs/ai/THEMED_TRAINING_ROOMS.md">制作与重建说明</a></div></details></main><footer>独立房间样板 · 无发光与粒子 · 所有图片可在分房间页面打开原图</footer>`;
fs.mkdirSync(path.join(output,'training_rooms'),{recursive:true});
fs.writeFileSync(path.join(output,'training_rooms/index.html'),document('练功房 · 材质与主题','#c2c5a5',summary));
console.log(JSON.stringify({gallery:'output/training_rooms/index.html',rooms:stats},null,2));
