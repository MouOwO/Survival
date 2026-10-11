'use strict';
// Captures actual project Tooltip panels. Browser simulation, never game evidence.
const fs=require('fs'),path=require('path'),crypto=require('crypto'),assert=require('node:assert/strict'),{fileURLToPath}=require('url');
const {browser}=require('../shop_ui_12h/cdp.cjs');
const phase=process.argv[2]||'after',out='design_refs/archive_v10/work/nine_slice',input='design_refs/archive_v10/work/preview/index.html';
const manifest=JSON.parse(fs.readFileSync('design_refs/archive_v10/package/archive_ui_final_v1/asset_manifest.json','utf8'));
const assets=Object.fromEntries(manifest.assets.filter(x=>['tooltip_background','tooltip_frame','tooltip_shadow'].includes(x.id)).map(x=>[x.id,x]));
const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));
function inspect(){
 const rect=node=>node.el.getBoundingClientRect().toJSON(),tip=nodes.ArchiveV10Tooltip,canvas=nodes.ArchiveV10Canvas,scale=rect(canvas).width/1672;
 const artOf=node=>node.BHasClass('ArchiveV10Image')?node:node.Children().flatMap(child=>child.BHasClass('ArchiveV10Image')?[child]:child.Children().filter(c=>c.BHasClass('ArchiveV10Image')))[0];
 const srcOf=node=>node.type==='Image'?node.el.src:(getComputedStyle(node.el).backgroundImage.match(/^url\(["']?(.*?)["']?\)$/)||[])[1]||'';
 const layers=tip.Children().map(host=>{const img=artOf(host),match=(img?srcOf(img):'').match(/tooltip_(background|frame|shadow)\.png/);if(!match)return null;return {asset:'tooltip_'+match[1],type:host.type,bounds:rect(host),logicalWidth:rect(host).width/scale,logicalHeight:rect(host).height/scale,insets:host.__v10Slice?.insets||[],assetAttribute:host.__v10Slice?.asset||'',pieces:host.Children().filter(x=>x.BHasClass('ArchiveV10Crop')).map((clip,index)=>{const art=artOf(clip),src=art?srcOf(art):'',decoded=window.previewTooltipBackgrounds?.[src],ar=art?rect(art):null,cr=rect(clip),cs=art?getComputedStyle(art.el):null;return {index,bounds:cr,logicalWidth:cr.width/scale,logicalHeight:cr.height/scale,art:art?{type:art.type,method:art.type==='Image'?'image':'panel_background',bounds:ar,logicalWidth:ar.width/scale,logicalHeight:ar.height/scale,logicalOffset:[(ar.x-cr.x)/scale,(ar.y-cr.y)/scale],src,decoded:art.type==='Image'?art.el.complete&&art.el.naturalWidth>0:!!decoded?.decoded,naturalWidth:art.type==='Image'?art.el.naturalWidth:decoded?.width,naturalHeight:art.type==='Image'?art.el.naturalHeight:decoded?.height,backgroundSize:cs.backgroundSize,backgroundRepeat:cs.backgroundRepeat}:null};})};}).filter(Boolean);
 const s=nodes.ArchiveV10TooltipSurface;
 return {visible:tip.visible,scale,bounds:rect(tip),surface:rect(s),surfaceHeight:rect(s).height/scale,layers,errors:previewErrors};
}
async function main(){
 assert(['before','after'].includes(phase),'Use before or after');fs.mkdirSync(out,{recursive:true});
 const b=await browser(),report={phase,at:new Date().toISOString(),kind:'production_component_browser_preview',notGameCapture:true,sourceGraph:JSON.parse(fs.readFileSync('design_refs/archive_v10/work/preview/assembly.json','utf8')),cases:[],limitations:['Actual production XML/JS/CSS is executed with a browser Panorama adapter. Native rasterization and game mouse input remain separate.','Minimum and long cases are explicit local read-only fixtures; normal map case reads its official CSV fixture. No account or saved data is written.']};
 try{
  await b.go(input,'?category=map_level');assert.equal(await b.run('previewReady'),true);
  await b.run(`(async()=>{const urls=[...new Set([...nodes.ArchiveV10Tooltip.el.querySelectorAll('.ArchiveV10Image')].map(el=>(getComputedStyle(el).backgroundImage.match(/^url\\(["']?(.*?)["']?\\)$/)||[])[1]).filter(Boolean))];window.previewTooltipBackgrounds=Object.fromEntries(await Promise.all(urls.map(async src=>{const img=new Image();img.src=src;try{await img.decode();}catch(error){throw new Error('Tooltip background decode failed: '+src+' '+error);}return [src,{decoded:true,width:img.naturalWidth,height:img.naturalHeight}];})));return true;})()`);
  for(const name of ['minimum','map_level','long']){
   await b.run(`(()=>{const card=nodes.ArchiveGrid.Children().find(c=>c.visible&&c.BHasClass('ArchiveCard')),item=JSON.parse(JSON.stringify(card.__archiveItem));if(${JSON.stringify(name)}==='minimum'){item.name='最小 Tooltip 高度验收';item.description='攻击力 +1';cfg.ArchiveHandoff.ShowEffectOnly(item,card);}else{if(${JSON.stringify(name)}==='long')item.description=(item.description+'\\n').repeat(60);cfg.ArchiveHandoff.Show(item,'map_level',card);}syncLayout();return true;})()`);
   await wait(160);await b.run('syncLayout();true');const info=await b.run('('+inspect.toString()+')()');assert(info.visible);assert.equal(info.errors.length,0);
   if(name==='minimum')assert(Math.abs(info.surfaceHeight-198)<.7,'Minimum Tooltip panel remains 198 logical pixels');
   if(name==='long')assert(Math.abs(info.surfaceHeight-730)<.7,'Long Tooltip caps at 730 logical pixels');
   if(phase==='after'){
    assert.equal(info.layers.length,3,'Background, metal frame and shadow are independent actual components');
    for(const layer of info.layers){
     const asset=assets[layer.asset],inset=asset.nine_slice_ltrb;assert(asset);assert.equal(layer.pieces.length,9,layer.asset+' uses nine cropped actual Panel backgrounds');assert.equal(layer.assetAttribute,layer.asset,'Layer exposes the exact original asset key');assert.deepEqual(layer.insets,inset,'Runtime uses the approved component-pack inset metadata');
     const [left,top,right,bottom]=inset,corners=[[0,left,top],[2,right,top],[6,left,bottom],[8,right,bottom]];
     for(const [index,width,height] of corners){const p=layer.pieces[index];assert(Math.abs(p.logicalWidth-width)<.7&&Math.abs(p.logicalHeight-height)<.7,layer.asset+' corner '+index+' keeps manifest dimensions independent of Tooltip height');assert(p.art?.decoded);assert(Math.abs(p.art.logicalWidth-asset.size[0])<.7&&Math.abs(p.art.logicalHeight-asset.size[1])<.7,layer.asset+' corner source image remains unscaled');}
     const raster=fs.readFileSync(fileURLToPath(layer.pieces[0].art.src)),hash=crypto.createHash('sha256').update(raster).digest('hex');assert.equal(hash,asset.sha256,'Nine-slice retains the exact approved original bitmap bytes');layer.sourceAssetSha256=hash;
     const xs=[0,left,asset.size[0]-right,asset.size[0]],ys=[0,top,asset.size[1]-bottom,asset.size[1]];
     for(const p of layer.pieces){
      assert(p.logicalWidth>0&&p.logicalHeight>0,'No negative or zero slice dimensions');assert.equal(p.art.type,'Panel','Native Image aspect fitting is bypassed with an actual Panel background');assert.equal(p.art.backgroundSize,'100% 100%','Explicit two-axis raster stretching');assert.equal(p.art.backgroundRepeat,'no-repeat');assert.deepEqual([p.art.naturalWidth,p.art.naturalHeight],asset.size,'Decoded original background dimensions match manifest');
      const col=p.index%3,row=Math.floor(p.index/3),sx=p.logicalWidth/(xs[col+1]-xs[col]),sy=p.logicalHeight/(ys[row+1]-ys[row]);
      assert(Math.abs(p.art.logicalWidth-asset.size[0]*sx)<.8&&Math.abs(p.art.logicalHeight-asset.size[1]*sy)<.8,'Full background has independent crop-axis scaling');
      // Production rounds the negative source position to a logical pixel.
      assert(Math.abs(p.art.logicalOffset[0]+xs[col]*sx)<1.1&&Math.abs(p.art.logicalOffset[1]+ys[row]*sy)<1.1,'Each panel exposes its original source crop');
     }
    }
   }
   const r=info.bounds,clip={x:Math.max(0,Math.floor(r.x-4)),y:Math.max(0,Math.floor(r.y-4)),width:Math.ceil(r.width+8),height:Math.ceil(r.height+8)};
   await b.shot(out+'/'+phase+'_'+name+'_full.png',{x:0,y:0,width:1920,height:1080});await b.shot(out+'/'+phase+'_'+name+'_tooltip.png',clip);
   fs.writeFileSync(out+'/'+phase+'_'+name+'.json',JSON.stringify(info,null,2));report.cases.push({name,...info});
  }
  if(phase==='after')for(const key of Object.keys(assets))for(const index of [0,2,6,8]){
   const dims=report.cases.map(c=>c.layers.find(l=>l.asset===key).pieces[index]);for(const p of dims.slice(1))assert(Math.abs(p.logicalWidth-dims[0].logicalWidth)<.7&&Math.abs(p.logicalHeight-dims[0].logicalHeight)<.7,'All heights preserve '+key+' corner '+index);
  }
  report.status=phase==='after'?'PASS_TOOLTIP_THREE_LAYER_NINE_SLICE':'CAPTURED_BEFORE';
  if(phase==='after'&&fs.existsSync(out+'/before_report.json')){
   const titles={minimum:'最小高度 198',map_level:'正式地图等级 Tooltip',long:'长正文上限 730'},rows=report.cases.map(c=>'<section><h2>'+titles[c.name]+' · 逻辑高度 '+Math.round(c.surfaceHeight)+'</h2><div class="pair">'+['before','after'].map(p=>'<div><h3>'+({before:'修复前：仅边框九宫格',after:'修复后：背景 / 边框 / 阴影均九宫格'}[p])+'</h3><img src="'+p+'_'+c.name+'_tooltip.png"></div>').join('')+'</div></section>').join('');
   fs.writeFileSync(out+'/comparison.html','<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>Tooltip 实际组件九宫格前后对比</title><style>*{box-sizing:border-box}body{margin:0;padding:16px;background:#171322;color:#eee;font:14px "Segoe UI",sans-serif}h1{font-size:20px;margin:0 0 8px}p{margin:0 0 18px;color:#aaa}h2{font-size:17px;margin:0 0 8px}h3{font-size:13px;margin:0 0 8px;font-weight:normal}.pair{display:grid;grid-template-columns:1fr 1fr;gap:16px}.pair img{display:block;max-width:100%;height:auto}section{margin:0 0 24px}</style><h1>Tooltip 实际组件组装 · 三层九宫格前后对比</h1><p>同一正式数据样例与位置 · 浏览器组装截图，非游戏内截图 · 原素材像素未修改</p>'+rows+'</html>');
   await b.call('Emulation.setDeviceMetricsOverride',{width:920,height:1080,deviceScaleFactor:1,mobile:false});await b.go(out+'/comparison.html');const height=await b.run('document.documentElement.scrollHeight');await b.shot(out+'/comparison.png',{x:0,y:0,width:920,height});report.comparison='comparison.png';
  }
 }catch(error){report.status='FAIL_TOOLTIP_NINE_SLICE';report.failure=error.stack||String(error);throw error;}
 finally{fs.writeFileSync(out+'/'+phase+'_report.json',JSON.stringify(report,null,2));b.close();}
 console.log(report.status+' '+out+'/'+phase+'_report.json');
}
main().catch(error=>{console.error(error.stack||error);process.exitCode=1;});
