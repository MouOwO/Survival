'use strict';
const fs=require('fs'),path=require('path'),{pathToFileURL}=require('url');
const {browser}=require('./cdp.cjs');
const base=path.resolve('design_refs/shop_ui_12h'),work=path.join(base,'work');
const defs={
 J01:{headerOpacity:.5},J02:{header:'warm-mist'},J03:{seamOpacity:.35},J04:{seam:'soft'},
 C05:{card:'warm'},C06:{card:'flat'},C07:{card:'quiet'},C08:{cardShadow:.35},C09:{cardShadow:.62},
 I10:{itemShadow:.55},I11:{itemScale:.94},I12:{well:'warm'},
 N13:{title:'quiet'},N14:{price:'soft'},H15:{overlay:'wide'},H16:{overlay:'soft'},
 B17:{button:'flat'},B18:{button:'gloss'},V19:{nav:'quiet'},V20:{navGlow:.5}
};
const svg=(w,h,body)=>`<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}">${body}</svg>`;
const uri=f=>pathToFileURL(f).href;
async function make(id,parent,b){
 const dir=path.join(work,'candidates',id);fs.mkdirSync(dir+'/assets',{recursive:true});
 const ancestor=parent==='baseline'?{}:JSON.parse(fs.readFileSync(path.join(work,'candidates',parent,'config.json'))).config;
 const config={...ancestor,...defs[id]};fs.writeFileSync(dir+'/config.json',JSON.stringify({id,parent,changes:defs[id],config},null,2));
 const overrides={};
 if(config.header)overrides.content_transition=svg(1280,96,'<defs><linearGradient id="g" x2="0" y2="1"><stop stop-color="#fcfaf1" stop-opacity="0"/><stop offset=".25" stop-color="#f9f8ef" stop-opacity=".72"/><stop offset=".58" stop-color="#f6f6ef" stop-opacity=".52"/><stop offset="1" stop-color="#f6f6ef" stop-opacity="0"/></linearGradient></defs><path d="M0 0h1280v96H0z" fill="url(#g)"/>');
 if(config.seam)overrides.sidebar_seam=svg(24,808,'<defs><linearGradient id="g"><stop stop-color="#def0e7" stop-opacity="0"/><stop offset=".38" stop-color="#e6edde" stop-opacity=".28"/><stop offset=".63" stop-color="#fffff6" stop-opacity=".48"/><stop offset="1" stop-color="#e4eee4" stop-opacity="0"/></linearGradient></defs><path d="M0 0h24v808H0z" fill="url(#g)"/><path d="M8 0v808" stroke="#a7b9b1" opacity=".32" stroke-width=".6"/>');
 if(config.card)for(const state of ['normal','hover','selected']){
  let source=fs.readFileSync(path.join(base,'source/materials/product_'+state+'.svg'),'utf8');
  if(config.card==='warm')source=source.replaceAll('#f2f4ed','#f8f7ef').replaceAll('#e7ede5','#eff1e8').replaceAll('.038','.018').replaceAll('#8faaa5','#a5b7b1');
  if(config.card==='flat')source=source.replaceAll('#f2f4ed','#fbfaf2').replaceAll('#e7ede5','#f5f6ee').replaceAll('.038','.012').replaceAll('stroke-width="1.6"','stroke-width=".8"').replaceAll('opacity=".48"','opacity=".22"').replaceAll('stroke-opacity=".16"','stroke-opacity=".05"');
  if(config.card==='quiet')source=source.replaceAll('#f2f4ed','#f9f8f1').replaceAll('#e7ede5','#f0f3eb').replaceAll('.038','.016').replaceAll('stroke-width="1.6"','stroke-width="1.05"').replaceAll('#8faaa5','#b1beb7').replaceAll('stroke-opacity=".16"','stroke-opacity=".08"').replaceAll('opacity=".48"','opacity=".3"');
  overrides['product_'+state]=source;
 }
 if(config.well)overrides.art_well=svg(264,224,'<defs><radialGradient id="g" cx=".5" cy=".8" rx=".6" r=".55"><stop stop-color="#d7e3d8" stop-opacity=".17"/><stop offset=".62" stop-color="#fdfcf4" stop-opacity=".2"/><stop offset="1" stop-color="#fdfcf4" stop-opacity="0"/></radialGradient></defs><ellipse cx="132" cy="150" rx="126" ry="105" fill="url(#g)"/>');
 if(config.price)overrides.price_strip=svg(264,42,'<defs><linearGradient id="g"><stop stop-color="#b8ceca" stop-opacity="0"/><stop offset=".18" stop-color="#c1d4cf" stop-opacity=".22"/><stop offset=".82" stop-color="#c1d4cf" stop-opacity=".22"/><stop offset="1" stop-color="#b8ceca" stop-opacity="0"/></linearGradient></defs><rect y="2" width="264" height="38" rx="12" fill="url(#g)"/>');
 if(config.overlay){let source=fs.readFileSync(path.join(base,'source/materials/hover_shade.svg'),'utf8');source=source.replace('opacity=".91"',config.overlay==='soft'?'opacity=".79"':'opacity=".9"').replaceAll('#173d46',config.overlay==='soft'?'#214e56':'#173e49');if(config.overlay==='wide')source=source.replaceAll('offset=".13"','offset=".07"').replaceAll('offset=".87"','offset=".93"');overrides.hover_shade=source;}
 if(config.button)for(const state of ['','_hover','_pressed']){
  let source=fs.readFileSync(path.join(base,'source/materials/buy_button'+state+'.svg'),'utf8');
  if(config.button==='flat')source=source.replace('l-4 4H5l-4-4V5z','l-4 4H5l-4-4V5z').replaceAll('#dbcfa1','#c0cbb6').replaceAll('stroke-opacity=".48"','stroke-opacity=".25"').replaceAll('stroke-opacity=".4"','stroke-opacity=".16"').replaceAll('#6d9d98','#6d9e9a').replaceAll('#3c7179','#4b8085');
  if(config.button==='gloss')source=source.replaceAll('#6d9d98','#83aca4').replaceAll('#3c7179','#487c83').replaceAll('stop-opacity=".16"','stop-opacity=".3"');
  overrides['buy_button'+state]=source;
 }
 if(config.nav){let source=fs.readFileSync(path.join(base,'source/nav_selected_material.svg'),'utf8');source=source.replaceAll('#f1f0df','#f9f8ef').replaceAll('#d9dfcd','#edf0e5');overrides.nav_selected=source;}
 const rules=[];
 for(const [name,source]of Object.entries(overrides)){
  fs.writeFileSync(dir+'/assets/'+name+'.svg',source);const match=source.match(/width="(\d+)" height="(\d+)"/);const width=Number(match[1]),height=Number(match[2]);
  fs.writeFileSync(dir+'/export.html',`<!doctype html><style>html,body{margin:0;background:transparent}img{display:block}</style><img width="${width}" height="${height}" src="${uri(dir+'/assets/'+name+'.svg')}">`);
  await b.go(dir+'/export.html');await b.call('Emulation.setDefaultBackgroundColorOverride',{color:{r:0,g:0,b:0,a:0}});await b.shot(dir+'/assets/'+name+'.png',{x:0,y:0,width,height});
 }
 const asset=name=>uri(fs.existsSync(dir+'/assets/'+name+'.png')?dir+'/assets/'+name+'.png':base+'/assets/'+name+'.png');
 const texture=(selector,name)=>rules.push(`${selector}{background-image:url('${asset(name)}')!important;}`);
 for(const[name,sel]of Object.entries({content_transition:'.content-transition',sidebar_seam:'.sidebar-seam',art_well:'.artwell',price_strip:'.price',hover_shade:'.hoverbox',nav_selected:'.nav.selected'}))if(overrides[name])texture(sel,name);
 if(config.card){texture('.card','product_normal');texture('.card.is-hover,.card:hover','product_hover');}
 if(config.button){texture('.buy','buy_button');texture('.buy:hover','buy_button_hover');texture('.buy:active,.buy.PreviewPressed','buy_button_pressed');}
 if(config.headerOpacity!==undefined)rules.push(`.content-transition{opacity:${config.headerOpacity};}`);
 if(config.seamOpacity!==undefined)rules.push(`.sidebar-seam{opacity:${config.seamOpacity};}`);
 if(config.cardShadow!==undefined)rules.push(`.card::before{opacity:${config.cardShadow};}`);
 if(config.itemShadow!==undefined)rules.push(`.item-shadow,.card:hover .item-shadow,.card.is-hover .item-shadow{opacity:${config.itemShadow};}`);
 if(config.itemScale!==undefined)rules.push(`.item-art{transform:scale(${config.itemScale});}.card:hover .item-art,.card.is-hover .item-art{transform:translateY(-3px) scale(${config.itemScale*1.035});}`);
 if(config.title)rules.push('.item-title{font-weight:500;letter-spacing:.2px;color:#214551;text-shadow:none}.price{color:#426269;}');
 if(config.navGlow!==undefined)rules.push(`.nav.selected .nav-glow{opacity:${config.navGlow};}`);
 let html=fs.readFileSync(base+'/source/shop.html','utf8').replaceAll('../assets/',uri(base+'/assets/')).replaceAll('../fonts/',uri(base+'/fonts/'));
 html=html.replace('</html>',`<style>${rules.join('\n')}</style><script>window.ITERATION_CONFIG=${JSON.stringify(config)};</script></html>`);fs.writeFileSync(dir+'/assembly.html',html);fs.writeFileSync(dir+'/overrides.css',rules.join('\n'));
 await b.call('Emulation.setDefaultBackgroundColorOverride',{color:{r:255,g:255,b:255,a:1}});
 for(const state of ['normal','hover']){await b.go(dir+'/assembly.html','?clean=1&hover='+(state==='hover'?1:0));await b.shot(dir+'/'+state+'.png');await b.shot(dir+'/card_'+state+'.png',{x:state==='hover'?816:504,y:252,width:300,height:352});if(state==='normal'){await b.shot(dir+'/header.png',{x:472,y:150,width:720,height:160});await b.shot(dir+'/sidebar.png',{x:430,y:280,width:100,height:650});}}
 console.log('CANDIDATE_ASSEMBLED '+id+' parent='+parent);
}
(async()=>{const args=process.argv.slice(2),i=args.indexOf('--parent'),parent=i<0?'baseline':args[i+1],ids=(i<0?args:args.slice(0,i));const b=await browser();try{for(const id of ids){if(!defs[id])throw new Error('Unknown candidate '+id);await make(id,parent,b);}}finally{b.close();}})().catch(e=>{console.error(e);process.exitCode=1});
