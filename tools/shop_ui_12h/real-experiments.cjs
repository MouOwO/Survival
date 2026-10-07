'use strict';
const fs=require('fs'),path=require('path'),{pathToFileURL}=require('url'),{browser}=require('./cdp.cjs');
const base='design_refs/shop_ui_12h',root=path.resolve(base),uri=f=>pathToFileURL(path.resolve(f)).href;
const specs={L21:{longShade:.84},L22:{longShade:.94},T23:{legacySize:96},T24:{legacySize:128}};
(async()=>{const b=await browser();try{for(const[id,change]of Object.entries(specs)){
 const dir=base+'/work/candidates/'+id;fs.mkdirSync(dir+'/assets',{recursive:true});fs.writeFileSync(dir+'/config.json',JSON.stringify({id,parent:'B17_production',changes:change,scope:'real shared factory with original CSV art; no live inventory changes'},null,2));
 if(change.longShade){
  const s=`<svg xmlns="http://www.w3.org/2000/svg" width="264" height="224"><defs><linearGradient id="v" x2="0" y2="1"><stop stop-color="white" stop-opacity="0"/><stop offset=".07" stop-color="white" stop-opacity=".7"/><stop offset=".14" stop-color="white"/><stop offset=".86" stop-color="white"/><stop offset="1" stop-color="white" stop-opacity="0"/></linearGradient><linearGradient id="h"><stop stop-color="white" stop-opacity="0"/><stop offset=".05" stop-color="white" stop-opacity=".7"/><stop offset=".12" stop-color="white"/><stop offset=".88" stop-color="white"/><stop offset=".95" stop-color="white" stop-opacity=".7"/><stop offset="1" stop-color="white" stop-opacity="0"/></linearGradient><mask id="m"><rect width="264" height="224" fill="url(#v)"/></mask><mask id="n"><rect width="264" height="224" fill="url(#h)"/></mask></defs><g mask="url(#m)"><rect width="264" height="224" fill="#214e56" opacity="${change.longShade}" mask="url(#n)"/></g></svg>`;
  fs.writeFileSync(dir+'/assets/hover_shade_long.svg',s);fs.writeFileSync(dir+'/export.html',`<style>body{margin:0;background:transparent}</style><img src="${uri(dir+'/assets/hover_shade_long.svg')}">`);
  await b.go(dir+'/export.html');await b.call('Emulation.setDefaultBackgroundColorOverride',{color:{r:0,g:0,b:0,a:0}});await b.shot(dir+'/assets/hover_shade_long.png',{x:0,y:0,width:264,height:224});await b.call('Emulation.setDefaultBackgroundColorOverride',{color:{r:255,g:255,b:255,a:1}});
 }
 for(const state of ['normal','hover']){
  await b.go(base+'/work/production/after.html','?category='+(change.longShade?'technology':'item'));
  if(change.longShade){await b.run(`CATALOG_FIXTURE.wallet.products.find(p=>p.category_id==='technology').reward_lines=[];CATALOG_FIXTURE.wallet.products.find(p=>p.category_id==='technology').description='仅用于长字段组件压力检查。'+Array(20).fill('全属性增加，攻击和护甲说明保持动态文本。').join('\\n');cfg.SurvivalCommerceView.UpdateWalletCatalog(CATALOG_FIXTURE.wallet);selectCategory('technology');syncFlows();`);await b.run(`document.querySelectorAll('.CJLongEffect').forEach(e=>{e.style.background='transparent';e.parentElement.querySelector('.CJHoverShade').src=${JSON.stringify(uri(dir+'/assets/hover_shade_long.png'))}})`);}
  else {await b.run(`document.querySelectorAll('.RCProductArt').forEach(i=>{if(i.naturalWidth<128){i.style.width='${change.legacySize}px';i.style.height='${change.legacySize}px';i.style.left='${(264-change.legacySize)/2}px';i.style.top='${(192-change.legacySize)/2+4}px'}})`);}
  if(state==='hover')await b.run(`document.querySelector('.CJProduct').classList.add('CJVisualHover')`);
  await b.shot(dir+'/'+state+'.png');await b.shot(dir+'/card_'+state+'.png',{x:502,y:250,width:302,height:356});
 }
 fs.writeFileSync(dir+'/assembly.html',fs.readFileSync(base+'/work/production/after.html','utf8'));
 console.log('REAL_COMPONENT_CANDIDATE '+id);
}}finally{b.close();}})().catch(e=>{console.error(e);process.exitCode=1});
