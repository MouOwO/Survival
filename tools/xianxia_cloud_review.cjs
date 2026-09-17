const fs=require('fs'),path=require('path');
const source=fs.readFileSync(path.join(__dirname,'xianxia_kit_gallery.cjs'),'utf8');
const {pngRead,pngWrite}=new Function('require','__dirname',source.slice(0,source.indexOf('const a=JSON.parse'))+'return {pngRead,pngWrite};')(require,__dirname);
const root=path.resolve(__dirname,'../output/xianxia_kit/cloud_revision_v2');
const names=['c01_cloud_sea','c02_cliff_cloud','c03_cloud_band','c04_thin_mist'];
const records=[];
for(const name of names){
 const file=path.join(root,name+(process.argv.includes('--draft')?'_draft':'')+'.png');if(!fs.existsSync(file))continue;
 const p=pngRead(file);let edge=0,visible=0,soft=0;
 for(let y=0;y<p.h;y++)for(let x=0;x<p.w;x++){const a=p.data[(y*p.w+x)*4+3];if(x<4||y<4||x>=p.w-4||y>=p.h-4)edge=Math.max(edge,a);if(a>2)visible++;if(a>2&&a<245)soft++;}
 records.push({name,dimensions:[p.w,p.h],borderAlphaMax:edge,visibleFraction:visible/(p.w*p.h),softPixels:soft,alphaPass:edge===0&&visible>100});
 for(const mode of ['dark','light','checker']){
  const out=Buffer.alloc(p.data.length);
  for(let y=0;y<p.h;y++)for(let x=0;x<p.w;x++){const i=(y*p.w+x)*4,a=p.data[i+3]/255,bg=mode==='dark'?[40,60,75]:mode==='light'?[225,227,221]:((Math.floor(x/48)+Math.floor(y/48))%2?[100,110,120]:[140,150,160]);for(let k=0;k<3;k++)out[i+k]=Math.round(p.data[i+k]*a+bg[k]*(1-a));out[i+3]=255;}
  pngWrite(path.join(root,name+'_'+mode+'.png'),p.w,p.h,out);
 }
}
fs.writeFileSync(path.join(root,'alpha_validation.json'),JSON.stringify(records,null,2));
if(process.argv.includes('--draft')){console.log(records);process.exit();}
const labels=['底层云海','崖边厚云','贴崖云带','薄雾'];
let html=`<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>云组件 · 第二版对比</title><style>body{margin:0;background:#e4e9e5;color:#263e3d;font:16px/1.7 "Microsoft YaHei",sans-serif}main{max-width:1400px;margin:auto;padding:32px}section{background:#f8faf7;padding:20px;margin:24px 0;border-radius:8px}.pair{display:grid;grid-template-columns:1fr 1fr;gap:16px}img{width:100%;cursor:zoom-in;background:repeating-conic-gradient(#354654 0% 25%,#566571 0% 50%) 0 /32px 32px}button{padding:8px 18px;margin-right:12px;cursor:pointer}small{display:block}a{color:#226973}dialog{border:0;padding:12px;max-width:95vw}dialog img{max-width:90vw;max-height:85vh;object-fit:contain}dialog::backdrop{background:#000b}@media(max-width:700px){.pair{grid-template-columns:1fr}}</style><main><h1>云组件 · 第二版对比</h1><p>只调整云，模型与地面材质沿用已确认版本。以下均为 Blender 独立体积密度烘焙；不是参考图裁片。</p><p>厚云合并大小不等的主体，云带改为连续的湍流密度场。当前仍是固定视角云片，近距离或转动镜头会暴露平面性；只适合少量放在地形边界。</p><button onclick="bg('checker')">棋盘底</button><button onclick="bg('dark')">深色底</button><button onclick="bg('light')">浅色底</button>`;
for(let i=0;i<names.length;i++)html+=`<section><h2>${labels[i]}</h2><div class="pair"><div><b>上一版</b><img src="../clouds/${names[i]}.png"><small>原始 1536 × 896 RGBA</small></div><div><b>本次</b><img src="${names[i]}.png"><small>原始 2048 × 1536 RGBA · <a href="${names[i]}.blend">Blender 体积源文件</a></small></div></div></section>`;
if(fs.existsSync(path.join(root,'engine_assembly.png')))html+='<section><h2>Dota 2 局部测试</h2><img src="engine_assembly.png"><p>仅组件测试地图。主地图尚未铺设。</p></section>';
html+=`<p><a href="../index.html">已确认的模型与材质库</a> · <a href="alpha_validation.json">透明边缘验证</a></p></main><dialog id="zoom"><button onclick="zoom.close()">关闭</button><img id="big"></dialog><script>document.querySelectorAll('img').forEach(im=>im.onclick=()=>{big.src=im.src;zoom.showModal()});function bg(m){document.querySelectorAll('img').forEach(x=>x.style.background=m==='light'?'#e1e3dd':m==='dark'?'#283c4b':'')}zoom.onclick=e=>{if(e.target===zoom)zoom.close()}</script></html>`;
fs.writeFileSync(path.join(root,'index.html'),html);console.log(records);
