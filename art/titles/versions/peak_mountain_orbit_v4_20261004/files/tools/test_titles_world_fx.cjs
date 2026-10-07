const fs=require('fs'),vm=require('vm'),assert=require('assert');
let next,listener,alive=true,dormant=false,valid=true,occluded=false,camX=960,camY=540,world=[0,0,0],now=0;
const nodes=[];
let hostOffset={x:3.4028234663852886e38,y:3.4028234663852886e38};
const host={actualuiscale_x:1,actualuiscale_y:1,actuallayoutwidth:1920,actuallayoutheight:1080,GetPositionWithinWindow:()=>hostOffset};
const cfg={SurvivalWorldOverlayVisibility:{Capture:()=>({}),Overlaps:()=>occluded}};
function $(id){return host;}
$.Schedule=(_,fn)=>{next=fn;};
$.CreatePanel=(type,parent)=>{
 const p={type,parent,classes:new Set(),style:{},children:[],visible:true,
  AddClass(c){this.classes.add(c);},SetScaling(){},SetImage(s){this.image=s;},
  DeleteAsync(){this.deleted=true;this.children.forEach(c=>c.DeleteAsync());}};
 if(parent.children)parent.children.push(p);nodes.push(p);return p;
};
const env={$,$,GameUI:{CustomUIConfig:()=>cfg},Game:{GetGameTime:()=>now,WorldToScreenX:(x)=>camX+x,WorldToScreenY:(x,y)=>camY-y},Entities:{IsValidEntity:()=>valid,IsAlive:()=>alive,IsDormant:()=>dormant,IsIllusion:()=>false,GetUnitName:()=> 'hero',GetAbsOrigin:()=>world,GetHealthBarOffset:()=>190},CustomNetTables:{GetAllTableValues:()=>[{key:'title_0',value:{entindex:9,title_id:'peak_perfection',unit_name:'hero'}}],SubscribeNetTableListener:(_,fn)=>{listener=fn;}}};
vm.createContext(env);
for(const name of ['title_layered_art','world_health_bar_anchor','title_world'])vm.runInContext(fs.readFileSync('panorama/src/scripts/custom_game/'+name+'.js','utf8'),env);
const byClass=cls=>nodes.filter(n=>!n.deleted&&n.classes.has(cls));
const embers=()=>byClass('SurvivalTitleEmber');
const shown=()=>embers().filter(p=>p.visible);
function frame(dt=1/60){now+=dt;next();}
const root=byClass('SurvivalWorldTitle')[0];
assert(root.visible,'native uninitialized-layout sentinel must not hide equipped title');assert.equal(root.style.position,'848.00px 413.00px 0px');
hostOffset={x:0,y:0};
assert.equal(byClass('SurvivalTitleStar').length,6);assert.equal(byClass('SurvivalTitleSweep').length,1);
const sweep=byClass('SurvivalTitleSweep')[0];
now=0.25;next();const earlyY=parseFloat(sweep.style.transform.replace('translateY(',''));
assert(Number(sweep.style.opacity)>0,'downward sweep starts at top');
now=0.65;next();assert(parseFloat(sweep.style.transform.replace('translateY(',''))>earlyY,'light moves down');
now=1.5;next();assert.equal(Number(sweep.style.opacity),0,'rest between passes');
assert(byClass('SurvivalTitleStar').every(p=>Number(p.style.opacity)===0),'no stray flashes between passes');
now=3.25;next();assert.equal(parseFloat(sweep.style.transform.replace('translateY(','')),earlyY,'repeat exactly every 3 seconds');
assert.equal(byClass('SurvivalTitleBase')[0].style.brightness,'1','keep original lettering brightness');
assert(byClass('SurvivalTitleBase')[0].image.endsWith('peak_clean_letters.png'));
now=0.43;next();let initialSpark=byClass('SurvivalTitleStar').map(p=>p.style.opacity).join(',');
for(let i=0;i<45;i++){camX+=1;frame();}
assert.equal(embers().length,0,'camera-only movement must never emit');
assert.notEqual(byClass('SurvivalTitleStar').map(p=>p.style.opacity).join(','),initialSpark,'glints follow the light then rest');
camX=960;host.actualuiscale_x=host.actualuiscale_y=0.75;frame();
assert.equal(root.style.position,'1168.00px 593.00px 0px');assert.equal(embers().length,0);
host.actualuiscale_x=host.actualuiscale_y=1;
for(let i=0;i<120;i++){world=[i*3,0,0];frame();}
assert(shown().length>0,'actual hero movement emits ash');assert(embers().length<=18,'bounded panel pool');
let titleLeft=parseFloat(root.style.position);
assert(shown().some(p=>parseFloat(p.style.position)<titleLeft+112),'left residue');
assert(shown().some(p=>parseFloat(p.style.position)>titleLeft+112),'right residue');
const count=embers().length,particle=shown()[0],oldX=parseFloat(particle.style.position);
camX+=20;next();assert.equal(embers().length,count);assert(Math.abs(parseFloat(particle.style.position)-oldX-20)<0.02,'residue reprojects with camera, never glues to viewport');
for(let i=0;i<70;i++)frame();assert.equal(shown().length,0,'stationary residue expires');
for(let i=0;i<18;i++){world[0]-=3;frame();}assert(shown().length>0);
world[0]-=300;frame();assert.equal(shown().length,0,'teleport clears distant trails');
for(let i=0;i<20;i++){world[0]+=3;frame();}assert(shown().length>0);
alive=false;frame();assert(!root.visible);assert.equal(shown().length,0);
alive=true;frame();assert(root.visible);assert.equal(shown().length,0);
dormant=true;frame();assert(!root.visible);assert.equal(shown().length,0);
dormant=false;occluded=true;frame();assert(!root.visible);
occluded=false;camX=-10000;frame();assert(!root.visible);
camX=960;frame();assert(root.visible);
for(let i=0;i<20;i++){world[0]+=3;frame();}assert(shown().length>0);
listener('survival_hero_health_bar','title_0',{entindex:17,title_id:'peak_perfection',unit_name:'hero'});
assert.equal(shown().length,0,'hero replacement clears old residue');frame();
listener('survival_hero_health_bar','title_0',{entindex:17,title_id:''});assert(root.deleted);assert.equal(embers().length,0);
listener('survival_hero_health_bar','title_0',{entindex:17,title_id:'peak_perfection',unit_name:'hero'});frame();
assert.equal(byClass('SurvivalWorldTitle').length,1,'re-equip must not duplicate title');assert.equal(byClass('SurvivalTitleStar').length,6);
const layered=cfg.SurvivalTitleLayeredArt;
assert.equal(byClass('SurvivalTitleOrbitBody').length,64,'fixed 32-segment body with near/far copies');
assert.equal(byClass('SurvivalTitleOrbitHead').length,2,'head has real near/far layers');
const end=layered.Pose(3),rest=layered.Pose(4);
assert.equal(end.duration,3);assert.equal(layered.Pose(2.99).phase,'ascending');
assert.equal(end.phase,'resting');assert.equal(end.staticWeight,1);assert.equal(end.procedural,0);
assert.equal(end.head.x,rest.head.x);assert.equal(end.head.y,rest.head.y);
let prev=layered.Point(0,0),distance=0,depthCrossings=0,xCrossings=0,lastDepth=1,lastX=1;
for(let i=1;i<=180;i++) {
 const t=i/60,p=layered.Pose(t),head=layered.Point(t,0),step=Math.hypot(head.x-prev.x,head.y-prev.y);
 assert(step<8,'continuous head trajectory');distance+=step;
 if(t<2.45){
  const d=Math.sign(head.depth),x=Math.sign(head.x-108);
  if(d!==lastDepth)depthCrossings++;if(x!==lastX)xCrossings++;lastDepth=d;lastX=x;
  let near=0,far=0;
  for(let j=0;j<=20;j++){
   const v=j/20,q=layered.Point(t,v);
   assert(q.y+q.thickness/2<94,'body stays above health bar');
   if(q.depth>.15)near++;if(q.depth<-.15)far++;
  }
  assert(near>0 && far>0,'different body sections simultaneously wrap in front and behind the mountain');
 }
 if(t>=.32)assert.equal(p.alpha,1,'actual ascent is not a whole-sprite fade');
 prev=head;
}
assert(depthCrossings>=3 && xCrossings>=3,'must circle the axis repeatedly, not sweep once left to right');
assert(distance>300,'head completes an orbit rather than a short diagonal');
for(let t of [.15,.6,1.2,2.4,4.9]){
 const a=layered.Pose(t),b=layered.Pose(t+5);
 assert(Math.abs(a.head.x-b.head.x)<1e-8 && Math.abs(a.head.y-b.head.y)<1e-8,'exact five-second repeat');
}
now=1;frame(0);
assert(byClass('SurvivalTitleOrbitBody').some(p=>p.visible && p.style.brightness==='0.76'),'rear sections are actually rendered below mountain');
assert(byClass('SurvivalTitleOrbitBody').some(p=>p.visible && p.style.brightness==='1'),'front sections are actually rendered above mountain');
now=3;frame(0);assert.equal(byClass('SurvivalTitleDragonFront')[0].style.opacity,'1.0000');
assert(byClass('SurvivalTitleOrbitBody').every(p=>!p.visible),'procedural body retires at rest');
assert(byClass('SurvivalTitleOrbitHead').every(p=>!p.visible));
const bodyCount=byClass('SurvivalTitleOrbitBody').length;
for(let i=0;i<300;i++)frame();assert.equal(byClass('SurvivalTitleOrbitBody').length,bodyCount,'no per-frame allocation');
alive=false;frame();assert(!byClass('SurvivalWorldTitle')[0].visible);alive=true;frame();
console.log('PASS true mountain orbit: segmented head/body/tail, repeated axis crossings, simultaneous front/rear occlusion, 3s ascent, fixed panel count');
console.log('PASS world title FX: 3-second downward sweep, synchronized stars, real-motion two-sided residue, world reprojection, 18-panel cap, expiry, teleport/death/fog/modal cleanup, replace and re-equip');
