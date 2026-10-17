'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {browser}=require('../vip_bundle_icons_20261017/browser.cjs');
const root=path.resolve(__dirname,'../..'),out=path.join(root,'output/survival_shop_nav_20261017');
process.chdir(root);
function hash(file){return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');}
async function main(){
 const assembly=JSON.parse(fs.readFileSync(path.join(out,'preview_assembly.json'),'utf8'));
 function verify(){for(const [file,sha]of Object.entries(assembly.sourceHashes))assert.equal(hash(path.join(root,file)),sha,'Reviewed source remains unchanged: '+file);}
 verify();const b=await browser(),report={scope:'Actual production panel geometry, CSS and SVGs through local browser adapter; NOT a game screenshot',notGameCapture:true,heroShortcut:'labelled geometry placeholder',screens:[],states:{}};
 try{
  await b.call('Emulation.setDeviceMetricsOverride',{width:1920,height:1080,deviceScaleFactor:1,mobile:false});
  for(const state of ['locked','active']){
   await b.go(path.join(out,'preview.html'),'?state='+state);
   assert.equal(await b.run('previewReady'),true);assert.deepEqual(await b.run('previewErrors'),[]);
   const info=await b.run(`(()=>{const rect=id=>document.getElementById(id).getBoundingClientRect().toJSON(),shop=document.getElementById('HandoffNav_survival_shop');return{shopVisible:!shop.hidden&&getComputedStyle(shop).display!=='none',shop:rect(shop.id),treasure:rect('HandoffNav_treasure'),vip:rect('HandoffNav_vip'),effects:rect('HandoffCombatEffects'),collection:rect('HandoffNav_collection'),hero:rect('SurvivalLocalHeroPortrait'),images:[...document.images].filter(i=>{const r=i.getBoundingClientRect();return r.width>0&&r.height>0;}).map(i=>({id:i.id,decoded:i.complete&&i.naturalWidth>0,source:i.src}))};})()`);
   assert.equal(info.shopVisible,state==='active');assert(info.images.every(i=>i.decoded),'every visible original SVG decodes');
   assert(Math.abs(info.collection.x-(info.effects.x+info.effects.width))<4,'collection follows compacted first row');
   if(state==='active'){
    assert(Math.abs(info.shop.x+info.shop.width/2-info.treasure.x-info.treasure.width/2)<1.1,'shop centered under treasure');
    assert(info.shop.y>=info.treasure.y+info.treasure.height-1,'shop is below first row');
    assert(info.hero.y>=info.shop.y+info.shop.height,'hero shortcut is below the second row');
   }
   const file=path.join(out,state+'_browser.png');await b.shot(file,900,340);
   report.states[state]=info;report.screens.push({file:path.relative(root,file).replaceAll('\\','/'),sha256:hash(file),width:900,height:340});
  }
  assert.equal(report.states.locked.vip.x,report.states.active.vip.x);assert.equal(report.states.locked.effects.x,report.states.active.effects.x);
  verify();report.status='PASS';
 }catch(error){report.status='FAIL';report.failure=error.stack;throw error;}finally{fs.writeFileSync(path.join(out,'browser_report.json'),JSON.stringify(report,null,2)+'\n');b.close();}
 console.log('SURVIVAL_SHOP_NAV_BROWSER_PASS: locked/active original SVGs, compacted row, centered lower shop, hero clearance');
}
main().catch(error=>{console.error(error);process.exitCode=1;});
