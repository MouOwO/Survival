"use strict";
const fs=require('fs'),path=require('path'),assert=require('assert'),crypto=require('crypto');const {browser,sleep}=require('../shop_ui_12h/cdp.cjs');
const out='design_refs/resource_icons_20261015/final',preview='design_refs/resource_icons_20261015/preview';fs.mkdirSync(out,{recursive:true});
(async()=>{const b=await browser(),records=[];try{
await b.call('Network.enable');await b.call('Network.setBlockedURLs',{urls:['http://*','https://*','ws://*','wss://*']});
for(const [width,height] of [[1600,900],[960,720]]){
await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await b.go(preview+'/index.html');assert(await b.run('previewReady'));
let data=await b.run(`(()=>{let rows=resourceEntries;return {errors:previewErrors,cards:document.querySelectorAll('.ShopShelfSlot').length,entries:rows.map(e=>({id:e.entry_id,gold:e.gold_cost,wood:e.wood_cost,shop:e.shop_id})),nodes:Object.keys(nodes).filter(n=>/ShopTooltip/.test(n))};})()`);
fs.writeFileSync(out+'/inspect_'+width+'.json',JSON.stringify(data,null,2));assert.deepEqual(data.errors,[]);assert(data.cards>0);
// Use an actual dual-resource formal product so both shared glyphs are visible.
await b.run("resourceShopTab('other');syncLayout()");
// Hover an actual visible production card, never call Tooltip.Show directly.
const chosen=await b.run(`(()=>{const p=nodes.ShopItemList.FindChildrenWithClassTraverse('ShopShelfSlot').find(p=>{const e=resourceEntries.find(e=>e.entry_id===p.GetAttributeString('entry_id',''));return p.el.getBoundingClientRect().width>0&&e&&e.gold_cost>0&&e.wood_cost>0});const r=p.el.getBoundingClientRect();return {id:p.GetAttributeString('entry_id',''),x:r.x+r.width/2,y:r.y+r.height/2};})()`);
assert(chosen.x>0&&chosen.x<width&&chosen.y>0&&chosen.y<height);
await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:chosen.x,y:chosen.y});await sleep(200);await b.run('syncLayout()');
const actual=await b.run(`(()=>{const t=nodes.ShopEntryTooltip,r=t.el.getBoundingClientRect(),entry=resourceEntries.find(e=>e.entry_id===${JSON.stringify(chosen.id)});return {entry,hidden:t.BHasClass('Hidden'),bounds:r.toJSON(),title:nodes.ShopTooltipTitle.text,gold:{value:nodes.ShopTooltipGoldCost.text,visible:nodes.ShopTooltipGoldCost.GetParent().visible,image:nodes.ShopTooltipGoldCost.GetParent().el.querySelector('img').src,loaded:nodes.ShopTooltipGoldCost.GetParent().el.querySelector('img').naturalWidth},wood:{value:nodes.ShopTooltipWoodCost.text,visible:nodes.ShopTooltipWoodCost.GetParent().visible,image:nodes.ShopTooltipWoodCost.GetParent().el.querySelector('img').src,loaded:nodes.ShopTooltipWoodCost.GetParent().el.querySelector('img').naturalWidth},calls:previewCalls,errors:previewErrors};})()`);
assert(!actual.hidden,'Actual physical hover opens tooltip');assert.deepEqual(actual.errors,[]);assert.equal(actual.title,actual.entry.name);for(const currency of ['gold','wood']){assert(actual[currency].image.endsWith('/custom_game/hud_resources_v2/'+currency+'.svg'));assert.equal(actual[currency].visible,Number(actual.entry[currency+'_cost'])>0);assert(actual[currency].loaded===32);}
assert(actual.bounds.x>=0&&actual.bounds.y>=0&&actual.bounds.right<=width+1&&actual.bounds.bottom<=height+1,'Tooltip stays in viewport');
assert(!actual.calls.some(c=>/purchase|checkout|draw|pay/i.test(c.name||c.method||'')));
await b.shot(out+'/shop_tooltip_dual_'+width+'x'+height+'.png');
await b.go(preview+'/topbar.html');assert(await b.run('topbarReady'));
const top=await b.run(`(()=>{return [...document.querySelectorAll('img')].map(e=>({id:e.id,url:e.src,width:e.naturalWidth,height:e.naturalHeight,displayWidth:e.getBoundingClientRect().width}));})()`);assert.equal(top.length,6);assert(top.every(e=>e.width===32&&e.height===32));assert.equal(top.find(e=>e.id==='ActualTopGold').url,actual.gold.image);assert.equal(top.find(e=>e.id==='ActualTopWood').url,actual.wood.image);await b.shot(out+'/topbar_resources_'+width+'x'+height+'.png');
records.push({viewport:[width,height],tooltip:actual,topbar:top,screenshots:['shop_tooltip_dual_'+width+'x'+height+'.png','topbar_resources_'+width+'x'+height+'.png']});
}
const assembly=fs.readFileSync(preview+'/assembly.json');fs.writeFileSync(out+'/validation.json',JSON.stringify({status:'PASS',scope:'Offline browser actual shop XML/JS/CSS with formal CSV prices and physical hover; actual extracted topbar art(). No game/network/purchases.',assembly_sha256:crypto.createHash('sha256').update(assembly).digest('hex'),checks:records},null,2));console.log('RESOURCE_ICONS_PREVIEW_PASS '+records.length+' resolutions, 4 screenshots');
}finally{b.close();}})().catch(e=>{fs.writeFileSync(out+'/failure.json',JSON.stringify({status:'FAIL',message:String(e),stack:e.stack},null,2));console.error(e);process.exitCode=1;});
