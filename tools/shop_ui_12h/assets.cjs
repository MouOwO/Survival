'use strict';
const fs=require('fs'),path=require('path'),crypto=require('crypto'),{pathToFileURL}=require('url');
const {browser}=require('./cdp.cjs'),{fixture}=require('./catalog.cjs');
const base=path.resolve('design_refs/shop_ui_12h'),best='B17',dir=path.resolve('panorama/src/images/custom_game/commerce_jade_v1');
const masters=path.resolve('art/ui/sources/custom_game/commerce_jade_v1');
const names=['window','header','sidebar','frame','title_flourish','content_transition','sidebar_seam','product_normal','product_hover','product_selected','art_well','price_strip','hover_shade','hover_shade_long','card_shadow','card_halo','buy_button','buy_button_hover','buy_button_pressed','nav_normal','nav_hover','nav_selected','nav_selected_glow','nav_selected_line','close_normal','close_hover','close_pressed','coin','crystal','sword_light','sword_hover','ticket_light','ticket_hover','gift_light','gift_hover','hero_light','hero_hover'];
(async()=>{
 fs.mkdirSync(dir+'/shadows',{recursive:true});fs.mkdirSync(masters,{recursive:true});
 const manifest={best,kind:'component_png_no_text_no_goods_baked',assets:{},items:{}};
 for(const name of names){const candidate=base+'/work/candidates/'+(name==='hover_shade_long'?'L21':best)+'/assets/'+name+'.png',src=fs.existsSync(candidate)?candidate:base+'/assets/'+name+'.png';fs.copyFileSync(src,dir+'/'+name+'.png');manifest.assets[name]={source:path.relative(process.cwd(),src),sha256:crypto.createHash('sha256').update(fs.readFileSync(src)).digest('hex')};}
 const b=await browser();try{
  fs.writeFileSync(base+'/work/shadow-export.html','<!doctype html><meta charset="utf-8"><canvas id="canvas" width="288" height="224"></canvas>');await b.go(base+'/work/shadow-export.html');
  const data=fixture(),icons=[...new Set(data.paid.products.concat(data.wallet.products).map(p=>p.icon))];
  for(const icon of icons){
   const file=path.resolve('panorama/src/images',icon);if(!fs.existsSync(file))throw Error('Missing real product image: '+icon);
   const srcURI='data:image/png;base64,'+fs.readFileSync(file).toString('base64');
   const result=await b.run(`(async()=>{const img=new Image();img.src=${JSON.stringify(srcURI)};await img.decode();const probe=document.createElement('canvas');probe.width=img.width;probe.height=img.height;const pc=probe.getContext('2d');pc.drawImage(img,0,0);const a=pc.getImageData(0,0,img.width,img.height).data;let x0=img.width,y0=img.height,x1=0,y1=0;for(let y=0;y<img.height;y++)for(let x=0;x<img.width;x++)if(a[(y*img.width+x)*4+3]>24){x0=Math.min(x0,x);y0=Math.min(y0,y);x1=Math.max(x1,x);y1=Math.max(y1,y);}const c=document.querySelector('canvas'),ctx=c.getContext('2d');ctx.clearRect(0,0,288,224);const alpha=document.createElement('canvas');alpha.width=256;alpha.height=192;const ac=alpha.getContext('2d'),s=Math.min(256/img.width,192/img.height,Math.max(img.width,img.height)<128?96/Math.max(img.width,img.height):Infinity);ac.drawImage(img,(256-img.width*s)/2,(192-img.height*s)/2,img.width*s,img.height*s);ac.globalCompositeOperation='source-in';ac.fillStyle='#244d51';ac.fillRect(0,0,256,192);ctx.filter='blur(8px)';ctx.globalAlpha=.23;ctx.drawImage(alpha,16,162,256,37);ctx.filter='none';ctx.globalAlpha=1;return{png:c.toDataURL('image/png').split(',')[1],size:[img.width,img.height],bounds:[x0,y0,x1,y1]};})()`);
   const id=crypto.createHash('sha256').update(icon).digest('hex').slice(0,12),shadow='custom_game/commerce_jade_v1/shadows/'+id+'.png';fs.writeFileSync(path.resolve('panorama/src/images',shadow),Buffer.from(result.png,'base64'));
   manifest.items[icon]={shadow,sourceSize:result.size,alphaBounds:result.bounds};
  }
 }finally{b.close();}
 if(fs.realpathSync(dir)!==fs.realpathSync(masters))fs.cpSync(dir,masters,{recursive:true});
 const out=path.resolve('panorama/src/scripts/custom_game/common/commerce_art_manifest.js');
 fs.writeFileSync(out,'// Generated from original catalog artwork; regenerate with tools/shop_ui_12h/assets.cjs.\nGameUI.CustomUIConfig().SurvivalCommerceArt='+JSON.stringify(manifest.items)+';\n');
 fs.writeFileSync(base+'/work/assets_manifest.json',JSON.stringify(manifest,null,2));console.log('JADE_ASSETS '+names.length+' shared materials, '+Object.keys(manifest.items).length+' source-specific shadows');
 const images=names.map(n=>'custom_game/commerce_jade_v1/'+n+'.png').concat(Object.values(manifest.items).map(i=>i.shadow));
 fs.writeFileSync('panorama/src/layout/custom_game/commerce_resources.xml','<!-- Build dependency list only; not a HUD and never replaces a dynamic shop. -->\n<root><Panel hittest="false">'+images.map(p=>'<Image src="file://{images}/'+p+'" hittest="false"/>').join('')+'</Panel></root>\n');
})().catch(e=>{console.error(e);process.exitCode=1});
