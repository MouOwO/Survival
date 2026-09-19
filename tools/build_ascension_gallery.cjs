const fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'..'),out=path.join(root,'output/ascension_arenas');
const assets=JSON.parse(fs.readFileSync(path.join(out,'asset_manifest.json'),'utf8'));
const footprints=[...new Set(assets.map(a=>a.meta.footprint.join(' × ')))];
const footprintSummary=footprints.join(' / ');
const descriptions=[
 '压实泥土、细砂砾、旧木桩与朴素石沿。',
 '保留泥地，加入顺纹木梁、端面年轮和铁箍。',
 '粗青石铺面与三层旧石基，木构退到边角。',
 '规整砌石与铜角件，铺地更完整。',
 '浅白石、磨损石沿与细金属嵌饰。',
 '青玉镶面、象牙白石框和柔和反光。',
 '冷色矿石、烟蓝矿晶与浅金属压边。',
 '天玉为主，部分战斗地面开始转为实体云面。',
 '云面成为主体，少量玉石留在边框。',
 '十层实体云台，平整云面与轻薄金色边饰。'];
const cards=assets.map((a,i)=>{
 const key=String(i+1).padStart(2,'0'),m=a.meta;
 return `<article id="rank-${key}" data-key="${key}"><header><span class="rank">${key}</span><div><h2>${m.label}</h2><p>${i+1} 转 · ${m.layers} 层 · 台面高度 ${m.deck_z}</p></div></header>
 <button class="picture" data-zoom="previews/arena_${key}_hero.png" aria-label="放大${m.label}"><img class="model" src="previews/arena_${key}_hero.png" alt="${m.label}模型预览" loading="lazy"></button>
 <div class="switch" role="group" aria-label="查看角度"><button class="on" data-view="hero">整体</button><button data-view="top">俯视</button><button data-view="side">侧面层数</button><button data-view="concept">原设计图</button></div>
 <p class="description">${descriptions[i]}</p><dl><div><dt>整体占地</dt><dd>${m.footprint.join(' × ')}</dd></div><div><dt>中央净空</dt><dd>${m.clear_combat_size.join(' × ')}</dd></div><div><dt>三角面</dt><dd>${a.triangles.toLocaleString('en-US')}</dd></div><div><dt>碰撞体</dt><dd>${a.collision_hulls}</dd></div></dl></article>`;
}).join('\n');
const html=`<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>一至十转擂台 · 尺寸扩展版</title>
<style>
:root{color-scheme:dark;font:16px/1.6 "Microsoft YaHei",system-ui,sans-serif;background:#101719;color:#e6e7df}*{box-sizing:border-box}body{margin:0}main{max-width:1500px;margin:auto;padding:48px 28px 72px}.eyebrow{letter-spacing:.22em;color:#b8a779;font-size:13px}h1{font-size:clamp(28px,4vw,48px);margin:10px 0 12px;line-height:1.25}h2{margin:0;font-size:23px}.intro{max-width:850px;color:#abb6b5}.meta{display:flex;flex-wrap:wrap;gap:12px;margin:26px 0}.meta span{padding:8px 15px;background:#223032;border:1px solid #3c4947;border-radius:5px}.links{display:flex;gap:22px;flex-wrap:wrap}a{color:#d0bf8f;text-underline-offset:4px}.nav{position:sticky;top:0;z-index:2;background:#101719ee;backdrop-filter:blur(12px);display:flex;flex-wrap:wrap;gap:8px;padding:14px 0;margin:24px 0}.nav a{padding:7px 13px;background:#273436;text-decoration:none;border-radius:4px}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:24px}article{border:1px solid #354240;border-radius:8px;background:#1c2729;overflow:hidden;scroll-margin-top:85px}article header{display:flex;align-items:center;gap:18px;padding:20px 24px}article header p{margin:1px 0;color:#a3b2b0;font-size:14px}.rank{font-size:36px;color:#c8b887;font-family:Georgia,serif}.picture{padding:0;border:0;display:block;width:100%;cursor:zoom-in;background:#343b41;aspect-ratio:1.4}.picture img{width:100%;height:100%;display:block;object-fit:contain}.switch{display:flex;gap:7px;padding:16px 20px 0}button{font:inherit;color:inherit;cursor:pointer}.switch button{font-size:14px;border:1px solid #455451;background:transparent;padding:6px 11px;border-radius:4px}.switch .on{background:#c3b389;color:#142321;border-color:#c3b389}.description{padding:0 24px;margin:15px 0;color:#c9d1c8}dl{display:grid;grid-template-columns:repeat(4,1fr);margin:18px 24px 24px;gap:8px}dt{color:#9ba8a4;font-size:12px}dd{margin:2px 0 0;font-size:14px}.notes{margin-top:32px;padding:24px;background:#1c2729;border-left:3px solid #b7a376}.notes p{margin:4px 0}dialog{background:#11191b;border:1px solid #53615a;max-width:96vw;max-height:96vh;padding:10px}dialog::backdrop{background:#000d}dialog img{max-width:90vw;max-height:84vh;display:block;margin:auto}dialog button{display:block;margin:8px 0 0 auto;background:#2a3837;border:0;padding:5px 14px}footer{margin:35px 0;color:#879591;font-size:13px}@media(max-width:820px){main{padding:28px 15px}.grid{grid-template-columns:1fr}.nav{gap:5px}.nav a{padding:6px 10px}dl{grid-template-columns:repeat(2,1fr)}}
</style><main><div class="eyebrow">SURVIVAL / ASCENSION ARENAS / SIZE UPDATE</div><h1>从夯土，到云端。</h1><p class="intro">按照已确认的十张设计图制作，并按追加要求扩展平面尺寸，高度保持不变。一至十转保持相同占地，以材料、台层和边缘细节体现升阶；每转可切换整体、俯视、侧面和原设计图。</p><div class="meta"><span>10 个独立模型</span><span>整体 ${footprintSummary}</span><span>每层 14 单位</span><span>1—10 层逐级增加</span><span>无自发光</span></div><div class="links"><a href="ascension_arenas.blend">Blender 完整工程</a><a href="previews/all_arenas.png">模型总览</a><a href="../ascension_arena_concepts_v1/index.html">概念图集</a><a href="../../docs/ai/ASCENSION_ARENAS.md">使用说明</a></div><nav class="nav">${assets.map((a,i)=>`<a href="#rank-${String(i+1).padStart(2,'0')}">${i+1} 转</a>`).join('')}</nav><section class="grid">${cards}</section><section class="notes"><p>原设计图尺寸 700 × 350，现模型已按追加要求扩大为 ${footprintSummary}。原概念图及图内尺寸标注保留历史版本，未重新绘制。</p><p>本页图片为 Blender 材质与模型预览。游戏使用独立的法线与反射遮罩，实际光照请在测试地图内验看。</p><p>八至十转在预览场景中分别抬起 10 / 20 / 30 单位；独立模型原点仍位于底部。训练房 900 × 900 的调整属于另一项工作。</p><p>测试地图：<code>ascension_arenas_review</code>；独立预制件：<code>ascension_arena_01</code> 至 <code>ascension_arena_10</code>。</p></section><footer>尺寸扩展版供验看 · 中央保留战斗净空 · 全部贴图打包在 Blender 工程中</footer></main><dialog><img alt="放大预览"><button>关闭 · Esc</button></dialog><script>
const dialog=document.querySelector('dialog');
document.querySelectorAll('[data-view]').forEach(button=>button.addEventListener('click',()=>{const card=button.closest('article'),key=card.dataset.key,view=button.dataset.view;const src=view==='concept'?'../ascension_arena_concepts_v1/rank_'+key+'.png':'previews/arena_'+key+'_'+view+'.png';card.querySelector('img.model').src=src;card.querySelector('.picture').dataset.zoom=src;card.querySelectorAll('[data-view]').forEach(b=>b.classList.toggle('on',b===button));}));
document.querySelectorAll('[data-zoom]').forEach(b=>b.addEventListener('click',()=>{dialog.querySelector('img').src=b.dataset.zoom;dialog.showModal();}));dialog.querySelector('button').onclick=()=>dialog.close();dialog.addEventListener('click',e=>{if(e.target===dialog)dialog.close();});
</script></html>`;
fs.writeFileSync(path.join(out,'index.html'),html);
console.log('ASCENSION_GALLERY '+assets.length);
