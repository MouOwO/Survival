'use strict';
// Review only: decode exact installed Valve resources; never rewrite their pixels.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),crypto=require('node:crypto');
const {pathToFileURL}=require('node:url');
const {open}=require('../vpk_inspect.cjs');
const root=path.resolve(__dirname,'../..'),out=path.join(root,'output/daily_native_icons_20261017');
const viewer=path.join(root,'output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe');
const vpkPath=path.resolve(root,'../../dota/pak01_dir.vpk'),vpk=open(vpkPath);
const selected=[...['lesser_crit','ring_of_regen','ring_of_health','ultimate_orb','circlet','crown','javelin',
    'vitality_booster','stout_shield','vanguard','quelling_blade','branches','hand_of_midas','gloves','refresher',
    'tome_of_knowledge','helm_of_the_dominator','heart','holy_locket','tango','furion_gold_bag'].map(name=>['items',name]),
    ...['precious_egg','longclaws_amulet','craggy_coat','oblivions_locket','amorphotic_shell'].map(name=>['econ/artifacts',name])];
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
fs.mkdirSync(path.join(out,'native'),{recursive:true});
const records=[],missing=[];
for(const [folder,name] of selected){
    const resource='panorama/images/'+folder+'/'+name+'_png.vtex_c',entry=vpk.entries.find(e=>e.path===resource);
    if(!entry){missing.push(resource);continue;}
    const bytes=vpk.read(entry),id=folder.replaceAll('/','_')+'_'+name,input=path.join(out,'native',id+'.vtex_c'),png=path.join(out,'native',id+'.png');
    const cached=fs.existsSync(input)&&fs.existsSync(png)&&sha(fs.readFileSync(input))===sha(bytes);
    fs.writeFileSync(input,bytes);
    if(!cached)cp.execFileSync(viewer,['-i',input,'-o',png,'-d'],{windowsHide:true,stdio:'pipe'});
    const b=fs.readFileSync(png);
    records.push({id,name,folder,resource,uri:'file://{images}/'+folder+'/'+name+'.png',
        source_sha256:sha(bytes),png_sha256:sha(b),width:b.readUInt32BE(16),height:b.readUInt32BE(20),png});
}
const alphaScript=`import json,sys\nfrom PIL import Image\nrecords=json.load(sys.stdin)\nfor row in records:\n im=Image.open(row['png']).convert('RGBA');a=im.getchannel('A');h=a.histogram();row.update(alpha_min=a.getextrema()[0],alpha_max=a.getextrema()[1],transparent_pixels=h[0],semitransparent_pixels=sum(h[1:255]),opaque_pixels=h[255])\njson.dump(records,sys.stdout)\n`;
const alpha=cp.execFileSync('C:/Users/Administrator/AppData/Local/Programs/Python/Python314/python.exe',['-B','-X','utf8','-c',alphaScript],{input:JSON.stringify(records),encoding:'utf8',windowsHide:true});
const audited=JSON.parse(alpha),manifest={kind:'exact_installed_dota_resources_review_only',source_vpk:vpkPath,
    original_pixels_unchanged:true,variants_are_browser_css_only:true,not_native_game_capture:true,
    variants:{original:{},muted_warm:{saturation:0.65,washColor:'#f2e6cc',browser_approximation:true}},records:audited,missing};
fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
const esc=v=>String(v).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;');
const texture=pathToFileURL(path.join(root,'panorama/src/images/custom_game/shop_v10_v1/window_substrate.png')).href;
const html=`<!doctype html><meta charset="utf-8"><title>Dota native daily icon review</title><style>
*{box-sizing:border-box}body{margin:0;padding:24px;color:#eee9dc;font:15px "Microsoft YaHei",sans-serif;background:#302e2a url("${texture}") center/cover}
h1{font-size:25px;margin:0 0 10px}p{margin:5px 0 18px;color:#cfc6b6}.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px}
article{background:linear-gradient(130deg,#575145d9,#302e2ae8);border:1px solid #82765e;padding:12px;min-height:198px}
h2{font-size:16px;font-weight:normal;margin:0 0 8px;white-space:nowrap}.variants{display:flex;justify-content:space-evenly;gap:10px}.variant{text-align:center;flex:1}.well{height:112px;width:112px;max-width:100%;margin:auto;border:1px solid #998d72;background:#38342d;display:flex;align-items:center;justify-content:center}
img{width:106px;height:106px;max-width:100%;object-fit:contain}.warm{filter:url(#wash) saturate(.65)}small{display:block;color:#cfc5b2;font-size:12px;margin-top:6px}.meta{font-size:12px;color:#b8ad99;margin-top:9px}
</style><svg width="0" height="0" style="position:absolute"><filter id="wash" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values=".949 0 0 0 0  0 .902 0 0 0  0 0 .8 0 0  0 0 0 1 0"/></filter></svg>
<h1>每日签到 · Dota2 原生图标比较</h1><p>左：原色　右：低饱和暖色（浏览器近似 Panorama saturation .65 / washColor #f2e6cc）。原始 PNG 未改；所有图完整等比显示。此图为离线选图稿。</p>
<main class="grid">${audited.map(row=>`<article><h2>${esc(row.folder+'/'+row.name)}</h2><div class="variants">${['','warm'].map((cls,i)=>`<div class="variant"><div class="well"><img class="${cls}" src="${pathToFileURL(row.png).href}"></div><small>${i?'低饱和暖金':'原始配色'}</small></div>`).join('')}</div><div class="meta">${row.width}×${row.height} · Alpha ${row.alpha_min}–${row.alpha_max} · ${row.transparent_pixels?'有透明区域':'无全透明像素'}</div></article>`).join('')}</main>`;
fs.writeFileSync(path.join(out,'comparison.html'),html);
console.log(JSON.stringify({exported:audited.length,missing,items:audited.filter(r=>r.folder==='items').map(r=>({name:r.name,width:r.width,height:r.height,alpha:[r.alpha_min,r.alpha_max]})),artifacts:audited.filter(r=>r.folder!=='items').map(r=>({name:r.name,width:r.width,height:r.height,alpha:[r.alpha_min,r.alpha_max]})),html:path.join(out,'comparison.html')},null,2));
