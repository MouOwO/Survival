'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const base='panorama/src/scripts/custom_game/',helper=fs.readFileSync(base+'common/tooltip_dismiss.js','utf8');
// Daily rewards now use the archive renderer directly; its former independent
// geometry mapper no longer exists. The shared archive mapper remains covered.
const files=['common/archive_tooltip.js','common/menu_v10.js','lottery_gw2.js','archive_handoff_180de7e38b.js'];
function mapper(source,values){
 const start=source.indexOf('function tooltipRect('),brace=source.indexOf('{',start);assert(start>=0);let depth=1,end=brace+1;
 for(;depth;end++){if(source[end]==='{')depth++;else if(source[end]==='}')depth--;}
 const context=vm.createContext(values);vm.runInContext(source.slice(start,end),context);return context.tooltipRect;
}
function node(id,x,y,width,height,parent){return {id,style:{},visible:true,events:{},actuallayoutwidth:width,actuallayoutheight:height,actualuiscale_x:1.7,actualuiscale_y:1.7,IsValid:()=>true,GetParent:()=>parent,GetPositionWithinWindow:()=>({x,y}),SetPanelEvent(name,fn){this.events[name]=fn;}};}
for(const file of files)for(const fit of [.5,1.4]){
 const source=fs.readFileSync(base+file,'utf8');assert(source.includes('getRect:tooltipRect'),file+' supplies its mapper to the shared policy');
 const root=node('Root',0,0,1920,1080),window=node('ArchiveWindow',0,0,1200,900,root);window.style.transform='scale3d('+fit+','+fit+',1)';
 const read=mapper(source,{scale:fit,fitScale:fit,root});
 const anchor=node('Source',20,20,100,60,window),surface=node('Surface',400,200,320,198,window);
 // Actual layout dimensions already contain native UI scale. Apply only the
 // missing CSS Fit transform, while preserving the screen-space origin.
 let box=read(surface);assert.equal(box.x,400);assert.equal(box.y,200);assert.equal(box.width,320*fit);assert.equal(box.height,198*fit);
 let cursor=[0,0],jobs=[],serial=0;const cfg={};
 const env={GameUI:{CustomUIConfig:()=>cfg,GetCursorPosition:()=>cursor},$:{Schedule(_,fn){jobs.push({id:++serial,fn});return serial;},CancelScheduled(id){jobs=jobs.filter(job=>job.id!==id);}}};
 vm.runInNewContext(helper,env);let hidden=0,policy;
 policy=cfg.SurvivalTooltipDismiss.Create({panel:surface,getRect:read,isVisible:()=>surface.visible,hide(){hidden++;surface.visible=false;policy.Hidden();}});
 const tick=()=>{const work=jobs;jobs=[];work.forEach(job=>job.fn());};
 const show=()=>{if(!policy.CanShow(anchor))return false;surface.visible=true;policy.Shown(anchor);return true;};
 cursor=[21,21];assert(show());cursor=[box.x+box.width+1,box.y+4];tick();assert(surface.visible,file+' does not dismiss beyond the scaled right edge');
 cursor=[box.x+box.width-1,box.y+box.height-1];tick();assert(!surface.visible,file+' dismisses at the scaled bottom-right interior');assert.equal(hidden,1);
 assert(!show(),file+' freezes the scaled tooltip region after dismissal');
 const anchorBox=read(anchor);cursor=[anchorBox.x+anchorBox.width-1,anchorBox.y+anchorBox.height-1];assert(!show(),file+' also scales the source lock region');
 cursor=[box.x+box.width+5,box.y+box.height+5];tick();assert(show(),file+' rearms outside both transformed regions');policy.Dispose();
 if(file==='archive_handoff_180de7e38b.js'){
  const rootTip=node('ArchiveTooltip',400,200,320,198,root),legacy=read(rootTip);assert.equal(legacy.width,320,'Root-level legacy tooltip does not inherit the source window Fit');
  const otherWindow=node('LotteryMainCanvas',0,0,1536,864,node('OtherLayout',0,0,1920,1080,root));otherWindow.style.transform='scale3d('+fit+','+fit+',1)';
  assert.equal(read(node('LotterySource',10,10,100,60,otherWindow)).width,100*fit,'Legacy tooltip reads the actual cross-layout source owner');
 }
}
console.log('TOOLTIP_FIT_GEOMETRY_PASS: four production mappers including the shared daily/archive renderer, Fit .5/1.4, native scale not duplicated, edge entry, tooltip/source lock union and root-level legacy ownership');
