import fs from 'node:fs';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {createRequire} from 'node:module';
import {fileURLToPath,pathToFileURL} from 'node:url';
const base=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),req=createRequire(import.meta.url);
const modules=process.env.CODEX_PRIMARY_RUNTIME_NODE_MODULES;
const {chromium}=req(modules?path.join(modules,'playwright'):'playwright');
const sharp=req(modules?path.join(modules,'sharp'):'sharp');
const atlasMetadata=await sharp(path.join(base,'assets/item_cutout_atlas.png')).metadata();
if(atlasMetadata.width!==2048||atlasMetadata.height!==768||!atlasMetadata.hasAlpha)throw new Error('cutout atlas must be 2048x768 with alpha');
for(let i=0;i<8;i++)await sharp(path.join(base,'assets/item_cutout_atlas.png')).extract({left:(i%4)*512,top:Math.floor(i/4)*384,width:512,height:384}).png().toFile(path.join(base,`assets/item_cutout_${String(i+1).padStart(2,'0')}.png`));
// Export separate item-shadow layers so game assembly does not rely on browser drop-shadow filters.
for(let i=1;i<=8;i++){
 const id=String(i).padStart(2,'0'),png=fs.readFileSync(path.join(base,`assets/item_cutout_${id}.png`)).toString('base64');
 const layer=`<svg xmlns="http://www.w3.org/2000/svg" width="288" height="224"><defs><filter id="shadow" x="-30%" y="-30%" width="160%" height="180%"><feGaussianBlur in="SourceAlpha" stdDeviation="7" result="blur"/><feOffset in="blur" dy="9" result="offset"/><feFlood flood-color="#193e45" flood-opacity=".26" result="color"/><feComposite in="color" in2="offset" operator="in"/></filter></defs><image x="16" y="16" width="256" height="192" href="data:image/png;base64,${png}" filter="url(#shadow)"/></svg>`;
 await sharp(Buffer.from(layer)).png().toFile(path.join(base,`assets/item_shadow_${id}.png`));
}
const write=(p,s)=>fs.writeFileSync(path.join(base,p),s);
const svg=(w,h,body)=>`<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">${body}</svg>`;
const deco={
 'nav_selected':fs.readFileSync(path.join(base,'source/nav_selected_material.svg'),'utf8'),
 'nav_selected_glow':svg(340,116,'<defs><filter id="g" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="3.4"/></filter><filter id="b" x="-30%" y="-100%" width="160%" height="300%"><feGaussianBlur stdDeviation="4"/></filter></defs><path d="M20 14h300l4 4v84l-4 4H20l-4-4V18z" fill="none" stroke="#e5c477" stroke-width="2" opacity=".44" filter="url(#g)"/><ellipse cx="170" cy="105" rx="130" ry="4" fill="#ecc86f" opacity=".48" filter="url(#b)"/>'),
 'card_shadow':svg(320,376,'<defs><filter id="s" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="4"/></filter></defs><rect x="12" y="14" width="296" height="348" rx="9" fill="none" stroke="#31535b" stroke-width="3" opacity=".25" filter="url(#s)"/>'),
 'card_halo':svg(320,376,'<defs><filter id="g" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="3"/></filter></defs><rect x="12" y="8" width="296" height="348" rx="9" stroke="#dbb35b" stroke-width="3" fill="none" opacity=".5" filter="url(#g)"/>'),
 'card_cloud':svg(264,224,'<g fill="none" stroke="#c5d4cb" stroke-width="1.2" opacity=".3"><path d="M-12 80c24-10 37 6 26 20-10 11-24-4-14-11m-8 25c38-15 42 10 62 3 16-6 5-25-5-18M180 15c20-8 26 6 16 11-10 4-10-8-5-8m-3 15c21-7 31 7 45-2 15-9-3-22-10-12M211 181c19-6 36 12 24 22-9 6-19-4-12-9m-13 20c21-11 43 1 66-7"/></g>'),
 'title_flourish':svg(200,24,'<g fill="none" stroke="#b39a66" stroke-width="1.5"><path d="M0 12h147m18 0h35M140 12l8-5 8 5-8 5zM156 12l8-8 8 8-8 8z"/></g>'),
 'cloud_corner':svg(236,132,'<g stroke="#b7a574" stroke-width="1.2" fill="#f5efdc" fill-opacity=".6"><path d="M0 130V105c16-4 36 1 38-11 3-15-22-19-20-37 2-18 24-28 41-15 13 9 7 27-5 25-11-2-9-16 0-15M0 114c23-1 60 16 75-5 14-20-12-31-7-48 5-16 25-17 37-7 17 14 3 37-11 28-10-7-3-18 5-12M0 129c32-14 70 10 102-8 21-12 7-33 26-41 19-8 39 14 25 26-9 8-20-2-14-9M112 129c34-15 60-3 83-18 19-12 40-11 43 0v21z"/><path d="M0 89c19 1 29-11 26-25M79 132c21-13 26-16 29-29M143 131c23-12 40-3 56-21" fill="none"/></g>'),
 'frame':svg(1600,920,'<g fill="none" stroke="#b9a372"><rect x="1" y="1" width="1598" height="918" rx="7" stroke-width="1.6"/><rect x="6" y="6" width="1588" height="908" rx="4" stroke-width=".6" opacity=".45"/><path d="M7 28V8h20M1573 8h20v20M7 892v20h20M1573 912h20v-20" stroke-width="1.1"/></g>'),
 'coin':svg(40,40,'<defs><linearGradient id="g" x2=".8" y2="1"><stop stop-color="#ffedb1"/><stop offset=".55" stop-color="#d5a453"/><stop offset="1" stop-color="#987044"/></linearGradient></defs><circle cx="20" cy="20" r="17" fill="url(#g)" stroke="#8b663b" stroke-width="1.2"/><circle cx="20" cy="20" r="12.5" fill="#9e763f" stroke="#f5d79a" stroke-width="1.2"/><path d="M14 12v11c0 9 12 9 12 0V12" fill="none" stroke="#ffe9ae" stroke-width="3.5" stroke-linecap="round"/>'),
 'crystal':svg(40,40,'<g stroke="#397a9d" stroke-width=".7"><path d="M20 2l11 12-4 15-7 9-7-9-4-15z" fill="#63c0e9"/><path d="M20 2v36L13 29l-4-15z" fill="#b2e4f2"/><path d="M20 2l4 15-4 21 11-24z" fill="#327ac3"/><path d="M20 8l4 9-4 18-4-18z" fill="#e8fbff"/><path d="M9 14l-6 7 7 8 10 9-7-9zM31 14l6 7-7 8-10 9 7-9z" fill="#418bbe"/></g>')
};
const helmet='<path d="M20 5c-9 0-14 8-13 17l4 8 5 4V22l-5-4 9 2 9-2-5 4v12l5-4 4-8C34 13 29 5 20 5zM20 5v10M7 14l6-4M33 14l-6-4"/>';
const ticket='<path d="M8 9h24v7c-6 0-6 8 0 8v7H8v-7c6 0 6-8 0-8zM24 10v3m0 4v3m0 4v3m0 2v1"/>';
for(const [id,body]of [['hero',helmet],['ticket',ticket]])for(const [st,color]of [['light','#eeeede'],['hover','#af9154']])deco[id+'_'+st]=svg(40,40,`<g fill="none" stroke="${color}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${body}</g>`);
for(const [st,color]of [['normal','#244554'],['hover','#9e7a3b'],['pressed','#725c37']])deco['close_'+st]=svg(40,40,`<path d="M10 10l20 20M30 10L10 30" stroke="#fff8e9" stroke-width="5" opacity=".7" stroke-linecap="round"/><path d="M10 10l20 20M30 10L10 30" stroke="${color}" stroke-width="2.8" stroke-linecap="round"/>`);
for(const [id,s]of Object.entries(deco)){write(`source/${id}.svg`,s);await sharp(Buffer.from(s)).png().toFile(path.join(base,`assets/${id}.png`));}
const recipes=[];
const add=(id,w,h,css)=>recipes.push({id,width:w,height:h,file:`assets/${id}.png`,css});
add('window',1600,920,"background:linear-gradient(130deg,#f7f6eff5,#eff3ecf4);border-radius:7px;");
add('header',1600,112,"background:linear-gradient(90deg,#f7f5e914,#fbf9ebc4 40%,#fbf9ebc4 60%,#f7f5e914),url('../assets/scenery.png') center 50%/cover;border-radius:7px 7px 0 0;");
add('sidebar',320,808,"background:linear-gradient(#153944f5 0%,#153944ee 24%,#1c3e49d9 48%,#24495680 68%,#24495638 100%),url('../assets/scenery.png') 4% 62%/auto 128%;border-right:1px solid #a5afa0;");
for(const st of ['normal','hover','selected']){
 if(st!=='selected')add(`nav_${st}`,320,96,"background:"+(st==='hover'?'linear-gradient(90deg,transparent,#e9f0e620,transparent)':'transparent')+";border-bottom:1px solid #f2efe42b;");
 add(`product_${st}`,296,348,"background:radial-gradient(ellipse at 45% 0%,#ffffffdc,transparent 70%),linear-gradient(135deg,#f8f8efd9,#eaf0e7d9);border:1px solid "+(st==='normal'?'#b4c3ba':'#cfac62')+";border-radius:8px;box-shadow:inset 0 1px 0 #ffffffed,inset 0 -1px 0 #c1cfc23d;"+(st!=='normal'?"box-shadow:inset 0 0 0 1px #ecd9a65e,inset 0 1px 0 #ffffffe0;":""));
}
add('nav_selected_line',320,2,"background:linear-gradient(90deg,#b4924099,#f0c762 24%,#f0c762 76%,#b4924099);");
add('art_well',264,224,"background:radial-gradient(ellipse at 50% 65%,#dde9de88,transparent 69%),linear-gradient(#f7f9f246,#eef3e700);border-radius:6px;");
add('price_strip',264,42,"background:linear-gradient(90deg,transparent,#d2ddd336 28%,#d2ddd336 72%,transparent);border-top:1px solid #bccbb640;");
add('hover_shade',264,224,"background:linear-gradient(0deg,#153944ef 0%,#153944d9 22%,#153944a8 38%,#15394424 65%,#15394400 86%);border-radius:6px;");
add('effect_backing',264,48,"background:linear-gradient(90deg,#142a3200,#142a327a 12%,#142a327a 88%,#142a3200);");
for(const st of ['normal','hover','pressed'])add('buy_button'+(st==='normal'?'':'_'+st),188,46,`background:linear-gradient(${st==='pressed'?'#437b7e,#2f606c':st==='hover'?'#91c6be,#4a8b92':'#75aba7,#417d87'});border:1px solid ${st==='hover'?'#ffe7a6':'#ded8ac'};border-radius:5px;box-shadow:inset 0 1px 0 #effffb80,inset 0 -1px 0 #14374140;`);
add('plus_button',28,28,"background:linear-gradient(#719998,#4d7578);border:1px solid #759594;border-radius:4px;box-shadow:inset 0 1px 0 #fff3;");
add('backdrop',1920,1080,"background:#0a18299c;");
for(const id of ['product_normal','product_hover','product_selected','art_well','price_strip','hover_shade','effect_backing','card_cloud','card_shadow','card_halo','content_transition','sidebar_seam','buy_button','buy_button_hover','buy_button_pressed']){const source=fs.readFileSync(path.join(base,'source/materials',id+'.svg'));await sharp(source).png().toFile(path.join(base,'assets',id+'.png'));}
const browser=await chromium.launch({headless:true,executablePath:process.env.CJ_CHROMIUM_PATH,args:['--no-sandbox']});
const page=await browser.newPage({viewport:{width:1920,height:1080}});
const nativeMaterials=new Set(['product_normal','product_hover','product_selected','art_well','price_strip','hover_shade','effect_backing','buy_button','buy_button_hover','buy_button_pressed']);
for(const a of recipes){
 if(nativeMaterials.has(a.id))continue;
 write('source/export.html',`<!doctype html><style>*{box-sizing:border-box}html,body{margin:0;background:transparent}.a{width:${a.width}px;height:${a.height}px;${a.css}}</style><div class="a"></div>`);
 await page.goto(pathToFileURL(path.join(base,'source/export.html')).href);
 await page.locator('.a').screenshot({path:path.join(base,a.file),omitBackground:true});
}
for(const r of recipes){const sourcePath='source/materials/'+r.id+'.svg';if(fs.existsSync(path.join(base,sourcePath))){delete r.css;r.nativeSource=sourcePath;}}
write('source/component_recipes.json',JSON.stringify(recipes,null,2));
write('components_manifest.json',JSON.stringify(recipes.map(({css,...r})=>r),null,2));
const manifest=[];for(const id of fs.readdirSync(path.join(base,'assets')).filter(id=>id.endsWith('.png')).sort()){const data=fs.readFileSync(path.join(base,'assets',id)),m=await sharp(data).metadata();manifest.push({file:'assets/'+id,width:m.width,height:m.height,sha256:createHash('sha256').update(data).digest('hex')});}
write('asset_manifest.json',JSON.stringify(manifest,null,2));
await browser.close();console.log('exported '+recipes.length+' texture components + '+Object.keys(deco).length+' vector decorations');
