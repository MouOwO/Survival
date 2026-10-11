'use strict';
// Actual production renderer + original native bitmap exports. No game input or server calls.
const fs=require('fs'),assert=require('node:assert/strict'),{browser}=require('../shop_ui_12h/cdp.cjs');
const input='design_refs/archive_v10/work/preview/index.html',out='design_refs/archive_v10/work/browser_bindings';
const bindings=JSON.parse(fs.readFileSync('data/ui/archive_v10_icon_bindings.json','utf8')).bindings;
const aliasManifest=JSON.parse(fs.readFileSync('design_refs/archive_v10/work/icon_map_v11/native_aliases.json','utf8'));
const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));
function inspect(){
 const rect=n=>n.el.getBoundingClientRect().toJSON(),tip=nodes.ArchiveV10Tooltip,surface=nodes.ArchiveV10TooltipSurface,viewport=nodes.ArchiveV10TooltipViewport,body=nodes.ArchiveV10TooltipBody;
 return {errors:previewErrors,api:cfg.SurvivalArchiveV10.Inspect(),canvas:rect(nodes.ArchiveV10Canvas),models:previewGeometryModels,cards:nodes.ArchiveGrid.Children().filter(c=>c.visible&&c.__v10).map(c=>({id:c.__archiveItem.id,name:c.__v10.name.text,icon:{src:c.__v10.art.el.src||'',fit:getComputedStyle(c.__v10.art.el).objectFit,decoded:c.__v10.art.el.complete&&c.__v10.art.el.naturalWidth>0,naturalWidth:c.__v10.art.el.naturalWidth,naturalHeight:c.__v10.art.el.naturalHeight,bounds:rect(c.__v10.art)}})),tooltip:{visible:tip.visible,bounds:rect(tip),surface:rect(surface),viewport:rect(viewport),viewportHeight:viewport.el.clientHeight,viewportScrollHeight:viewport.el.scrollHeight,scrollTop:viewport.el.scrollTop,body:rect(body),title:rect(nodes.ArchiveV10TooltipTitle),titleText:nodes.ArchiveV10TooltipTitle.text,bodyFlow:body.style.flowChildren,bodyHeight:body.style.height,viewportOverflow:viewport.style.overflow}};
}
async function main(){
 fs.mkdirSync(out,{recursive:true});const b=await browser(),report={at:new Date().toISOString(),kind:'production_component_browser_preview',notGameCapture:true,assembly:JSON.parse(fs.readFileSync('design_refs/archive_v10/work/preview/assembly.json','utf8')),bindings:bindings.length,resolutions:[],limitations:['Production renderer and exact Dota VPK texture PNGs are assembled by a browser Panorama adapter. These images are not native game captures.','Runtime counts and currencies are labeled local samples. No game input, account, server or payment mutation.','UIScale model excludes CSS transforms, following the actual native 1600x900 diagnostic probe; native font flow and delayed layout still require game verification.']};
 try{
  assert.equal(bindings.length,35);
  for(const [width,height]of [[1280,720],[1920,1080],[2560,1440],[2560,1080]]){
   await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});const result={width,height,categories:[]};
   for(const category of ['fragment','building','points']){
    await b.go(input,'?category='+category);assert.equal(await b.run('previewReady'),true);await wait(160);await b.run('syncLayout();true');let info=await b.run('('+inspect.toString()+')()');assert.equal(info.errors.length,0);assert.equal(info.api.category,category);
    const expected=bindings.filter(x=>x.category===category),actual=[];
    for(const binding of expected){
     const card=info.cards.find(x=>x.id===binding.id);assert(card,'Formal binding '+binding.id+' is mounted in its category');assert.equal(card.name,binding.name,'Independent label matches the official binding name');assert.equal(card.icon.src,aliasManifest.aliases[binding.uri],'Actual component uses the exact exported original texture');assert.equal(card.icon.decoded,true);assert.equal(card.icon.fit,'contain','Original rectangular bitmap preserves its ratio inside the authored square icon slot');assert.deepEqual([card.icon.naturalWidth,card.icon.naturalHeight],binding.source_size,'Decoded texture dimensions match native resource evidence');const scale=info.canvas.width/1672;assert(Math.abs(card.icon.bounds.width-120*scale)<.8&&Math.abs(card.icon.bounds.height-120*scale)<.8,'Whole-canvas scaling preserves the 120px icon slot');actual.push({id:card.id,name:card.name,icon:card.icon,sourceResourceSha256:binding.evidence.resource_sha256});
    }
    if(category==='points'){await b.run(`(()=>{nodes.ArchiveGrid.Children().find(c=>c.__archiveItem?.id===${JSON.stringify(expected[0].id)}).ScrollToFit();syncLayout();return true;})()`);await wait(100);}
    await b.shot(out+'/'+width+'x'+height+'_'+category+'.png',{x:0,y:0,width,height});
    await b.run(`(()=>{const card=nodes.ArchiveGrid.Children().find(c=>c.visible&&c.__archiveItem?.id===${JSON.stringify(expected[0].id)});card.events.onmouseover();syncLayout();return true;})()`);await wait(900);await b.run('syncLayout();true');info=await b.run('('+inspect.toString()+')()');const tip=info.tooltip,scale=info.canvas.width/1672;assert(tip.visible);assert(tip.bounds.x>=-.5&&tip.bounds.y>=-.5&&tip.bounds.right<=width+.7&&tip.bounds.bottom<=height+.7,'Tooltip stays within the actual viewport');assert.equal(tip.titleText,expected[0].name);assert.equal(tip.bodyFlow,'down');assert.equal(tip.bodyHeight,'fit-children');assert.equal(tip.viewportOverflow,'squish scroll');assert(Math.abs(tip.viewport.x-(tip.surface.x+22*scale))<.8&&Math.abs(tip.viewport.y-(tip.surface.y+19*scale))<.8,'Text viewport follows the actual Tooltip background inset');assert(Math.abs(tip.title.x-tip.viewport.x)<.8&&Math.abs(tip.title.y-tip.viewport.y)<.8,'Title starts inside the background rather than at the source card origin');assert(tip.title.right<=tip.viewport.right+.8,'Title width remains inside the Tooltip viewport');assert(tip.body.height>=tip.viewport.height||tip.viewportScrollHeight===tip.viewportHeight,'Flowing content is fully laid out independently of its scroll viewport');
    await b.shot(out+'/'+width+'x'+height+'_'+category+'_tooltip.png',{x:0,y:0,width,height});result.categories.push({id:category,actualBindings:actual,tooltip:tip,api:info.api});
    if(category==='fragment'&&width===1920&&height===1080){
     const row=await b.run(`(()=>{const card=nodes.ArchiveGrid.Children().find(c=>c.visible&&c.__archiveItem?.id==='fragment_09');if(!card)throw Error('Missing formal pure-gold fragment');card.events.onmouseover();syncLayout();return card.__archiveItem;})()`);
     assert.equal(row.name,'神兵-纯金之触');assert(row.description.includes('Lv18 '),'The Tooltip uses every formal CSV level through level 18');await wait(900);await b.run('syncLayout();true');const gold=await b.run('('+inspect.toString()+')()'),g=gold.tooltip,gs=gold.canvas.width/1672;
     assert.equal(g.titleText,row.name);assert(g.visible);assert(g.surface.height/gs<=730+.7,'Formal long Tooltip stays within the authored 730px maximum');assert(g.viewport.x>=g.surface.x&&g.viewport.y>=g.surface.y&&g.viewport.right<=g.surface.right+.7&&g.viewport.bottom<=g.surface.bottom+.7,'Entire text viewport remains inside the original background');assert(g.body.height>=g.viewport.height||g.viewportScrollHeight===g.viewportHeight,'All formal lines are naturally laid out');
     const text=await b.run('nodes.ArchiveV10TooltipEffect.el.textContent');assert(/LV18\s/i.test(text),'Final official level remains present, never truncated from content');await b.shot(out+'/pure_gold_tooltip.png',{x:0,y:0,width,height});
     let scroll=null;if(g.viewportScrollHeight>g.viewportHeight){await b.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:g.viewport.x+g.viewport.width/2,y:g.viewport.y+g.viewport.height/2});await b.call('Input.dispatchMouseEvent',{type:'mouseWheel',x:g.viewport.x+g.viewport.width/2,y:g.viewport.y+g.viewport.height/2,deltaX:0,deltaY:1000});await wait(130);const after=await b.run('('+inspect.toString()+')()');assert(after.tooltip.scrollTop>0,'Long formal content can scroll inside its independent viewport');await b.shot(out+'/pure_gold_tooltip_scrolled.png',{x:0,y:0,width,height});scroll={scrollTop:after.tooltip.scrollTop,screenshot:'pure_gold_tooltip_scrolled.png'};}
     report.pureGold={kind:'production_component_browser_preview',notGameCapture:true,item:row,formalLevels:18,tooltip:g,screenshot:'pure_gold_tooltip.png',scroll,maximumHeightLogical:730};
    }
   }
   report.resolutions.push(result);
  }
  report.status='PASS_ARCHIVE_V10_35_NATIVE_BINDINGS_AND_TOOLTIP_VIEWPORT';
 }catch(error){report.status='FAIL_ARCHIVE_V10_BINDING_VIEWPORT';report.failure=error.stack||String(error);try{report.failureSnapshot=await b.run('('+inspect.toString()+')()');}catch(_){}throw error;}
 finally{fs.writeFileSync(out+'/report.json',JSON.stringify(report,null,2));b.close();}
 console.log(report.status+' '+out+'/report.json');
}
main().catch(error=>{console.error(error.stack||error);process.exitCode=1;});
