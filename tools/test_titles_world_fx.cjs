const fs=require('fs'),vm=require('vm'),assert=require('assert');
let lastOverlap;let next,listener,alive=true,dormant=false,valid=true,occluded=false,camX=960,camY=540,world=[0,0,0],now=0;
const nodes=[];
let hostOffset={x:3.4028234663852886e38,y:3.4028234663852886e38};
const host={actualuiscale_x:1,actualuiscale_y:1,actuallayoutwidth:1920,actuallayoutheight:1080,GetPositionWithinWindow:()=>hostOffset};
const cfg={SurvivalWorldOverlayVisibility:{Capture:()=>({}),Overlaps:(...args)=>{lastOverlap=args;return occluded;}}};
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
assert.equal(lastOverlap[2],357,'occlusion includes upper dragon silhouette');
assert.equal(lastOverlap[4],164,'occlusion covers full title and dragon');
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

assert.equal(byClass('SurvivalTitleDragon').length,2,'one complete dragon registered across two depth planes');
assert.equal(byClass('SurvivalTitleOrbitBody').length,0,'no segmented worm-like body');
const start=layered.Pose(0),end=layered.Pose(3);
assert.equal(start.duration,3);assert.equal(start.period,5);
assert.equal(layered.Pose(2.99).phase,'ascending');assert.equal(end.phase,'resting');
assert.equal(end.climb.scale,1);assert(Math.abs(end.climb.tx)<1e-8);assert(Math.abs(end.climb.ty)<1e-8);
assert.equal(end.climb.tilt,0);
assert(layered.Pose(.9).climb.tx>15&&layered.Pose(2.1).climb.tx< -15,'the curved orbit crosses BOTH sides of the mountain');
assert(layered.Pose(1.5).near<.01&&end.near>.99,'far passage resolves back into the foreground coil');
let previous=start.climb,maxStep=0;
for(let i=1;i<=180;i++){
 const c=layered.Pose(i/60).climb;
 maxStep=Math.max(maxStep,Math.hypot(c.tx-previous.tx,c.ty-previous.ty));
 assert(c.scale>=.88&&c.scale<=1,'preserve substantial body thickness');previous=c;
}
assert(maxStep<2,'ascent has no sudden positional jump');
for(const t of [.3,.9,1.5,2.1,3,4.5,4.9]){
 const a=layered.Pose(t),b=layered.Pose(t+5);
 for(const k of ['tx','ty','scale','tilt'])assert(Math.abs(a.climb[k]-b.climb[k])<1e-10,'exact five-second repeat');
}
now=4;frame(0);
const planes=byClass('SurvivalTitleDragon');
assert(planes.every(p=>p.body.image.endsWith('peak_clean_dragon_coiled.png')),'every plane uses the same complete painted dragon');
assert(planes.every(p=>p.style.transform===planes[0].style.transform),'body and head stay registered');
assert(planes.every(p=>Number(p.style.opacity)===1),'rest pose keeps the foreground coil visible');
const mountain=byClass('SurvivalTitleMountains')[0],letters=byClass('SurvivalTitleBase')[0];
assert(nodes.indexOf(planes[0])<nodes.indexOf(mountain),'far arch behind mountain');
assert(nodes.indexOf(planes[1])>nodes.indexOf(mountain),'belly coil in front of mountain');
assert(nodes.indexOf(letters)>nodes.indexOf(planes[1]),'dragon never covers lettering');
// Gesture must wait for arrival, then recover before the loop fades out.
for(const t of [0,.8,1.5,2.9,3.1,4.6,4.9]){
 const gesture=layered.Pose(t);assert.equal(gesture.roar,0);assert.equal(gesture.claw,0);
}
assert(layered.Pose(3.25).claw>0&&layered.Pose(3.25).roar===0,'reach precedes the roar');
assert.equal(layered.Pose(3.9).claw,1);assert.equal(layered.Pose(3.9).roar,1);
assert(layered.Pose(4.4).roar<1&&layered.Pose(4.4).roar>0,'mouth returns smoothly');
now=3.9;frame(0);
assert(planes.every(p=>p.jaw.style.transform==='rotateZ(13.000deg)'),'registered lower jaws open together');
assert(planes.every(p=>p.claw.style.transform.indexOf('rotateZ(-12.000deg)')===0),'registered claws reach together');
assert(planes.every(p=>Number(p.mouth.style.opacity)>.9),'dark mouth interior fills opening');
now=4.6;frame(0);
assert(planes.every(p=>p.jaw.style.transform==='rotateZ(0.000deg)'),'jaw returns to original pose');
assert(planes.every(p=>Number(p.mouth.style.opacity)===0),'no mouth shadow at rest');
now=2;frame(0);assert(planes.every(p=>p.jaw.style.transform==='rotateZ(0.000deg)'),'ascent keeps original anatomy');
assert.equal(byClass('SurvivalTitleDragonJaw').length,2);assert.equal(byClass('SurvivalTitleDragonClaw').length,2);
console.log('PASS arrival gesture: delayed claw reach, jaw opens, held roar, smooth return, synchronized depth planes');
const shadow=byClass('SurvivalTitleContactShadow')[0];
assert.equal(byClass('SurvivalTitleShadowReceiver').length,1,'one mountain-clipped shadow receiver');
now=1.5;frame(0);assert.equal(Number(shadow.style.opacity),0,'no foreground shadow while dragon is behind mountain');
now=3.9;frame(0);assert.equal(Number(shadow.style.opacity),1);
assert.equal(shadow.style.transform,planes[1].style.transform,'shadow tracks the actual foreground dragon');
assert(planes.every(p=>Number(p.cheek.style.opacity)>.8),'cheek bridges the jaw joint when open');
now=4.6;frame(0);assert(planes.every(p=>Number(p.cheek.style.opacity)===0),'closed jaw preserves original painting');
console.log('PASS contact shadow follows depth; cheek blend returns to original pose');
const panelCount=nodes.length;
for(let i=0;i<300;i++)frame();assert.equal(nodes.length,panelCount,'no animation-frame panel allocations');
alive=false;frame();assert(!byClass('SurvivalWorldTitle')[0].visible);alive=true;frame();
console.log('PASS coiled dragon: complete anatomy, curved orbit, depth passage, 3s ascent / 5s period, stable rest pose and panel count');
console.log('PASS world title FX: downward sweep, real-motion residue, reprojection, expiry, teleport/death/fog/modal cleanup and re-equip');
