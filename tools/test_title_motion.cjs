const fs=require('fs'),vm=require('vm'),assert=require('assert');const cfg={},nodes=[];
function node(type,parent){const p={type,parent,children:[],style:{},classes:[],AddClass(c){this.classes.push(c);},SetImage(v){this.image=v;},SetScaling(v){assert.equal(v,"stretch-to-fit-preserve-aspect","native Image scaling must be supported");this.scaling=v;}};if(parent)parent.children.push(p);nodes.push(p);return p;}
const env={GameUI:{CustomUIConfig:()=>cfg},$:{CreatePanel:node}};vm.createContext(env);
for(const n of ['title_motion_data','title_series_art'])vm.runInContext(fs.readFileSync('panorama/src/scripts/custom_game/'+n+'.js','utf8'),env);
const api=cfg.SurvivalTitleSeriesArt,rigs={},long=new Set(['jinghong','cangqiong','tianxia_diyi','chushen']);
const near=(a,b,msg)=>assert(Math.abs(a-b)<1e-8,msg);
for(const id of Object.keys(api.Config)){
 const c=api.Config[id];
 const textBottom=c.height*(.05+.9*(c.rects[0][1]+c.rects[0][3])/100);
 assert(Math.abs(c.height-textBottom-8)<.001,'same text baseline above health bar');
 assert(c.rects[0][0]>=0&&c.rects[0][0]+c.rects[0][2]<=100,'enlarged lettering stays in bounds');
 c.frames.forEach(([x,y,w,h])=>assert(x>=0&&y>=0&&w>0&&h>0&&x+w<=c.size[0]&&y+h<=c.size[1]));
 const fx=api.Create(node('Panel'),id,true);rigs[id]=fx;const base=JSON.stringify(fx.letters.style),n=nodes.length,period=long.has(id)?8:6;
 // Verify source pixels land at the clip boundaries after native aspect-fit.
 // This catches unsupported scaling and aspect-fit padding missed by the old stub.
 const atlasNodes=[];(function visit(p){if(p.classes.includes('MotionAtlas'))atlasNodes.push(p);p.children.forEach(visit);})(fx.stage);
 for(const image of atlasNodes){
  const wh=parseFloat(image.style.width),hh=parseFloat(image.style.height),pos=image.style.position.split(' ').map(parseFloat);
  const index=c.frames.findIndex(f=>Math.abs(wh-c.size[0]/f[2]*100)<1e-7&&Math.abs(pos[0]+f[0]/f[2]*100)<1e-7&&Math.abs(pos[1]+f[1]/f[3]*100)<1e-7);
  assert(index>=0,'atlas maps to a declared source region');const f=c.frames[index],rect=c.rects[index];
  const yScale=Number(image.style.transform.match(/scale3d\(1, ([\d.]+), 1\)/)[1]);
  for(const scale of [.6666667,.8333333,1,1.5]){
   const slotW=c.width*.94*rect[2]/100*scale,slotH=c.height*.9*rect[3]/100*scale;
   const width=slotW*wh/100,height=slotH*hh/100;
   near(width/height,c.size[0]/c.size[1],'no native letterboxing');
   assert(Math.abs(pos[0]/100*slotW+f[0]/c.size[0]*width)<.001,'source left aligns with crop');
   assert(Math.abs(pos[1]/100*slotH+f[1]/c.size[1]*height*yScale)<.001,'source top aligns with crop');
   assert(Math.abs(f[2]/c.size[0]*width-slotW)<.001,'full frame width');
   assert(Math.abs(f[3]/c.size[1]*height*yScale-slotH)<.001,'full frame height');
  }
 }
 for(let i=0;i<=1440;i++){
  const t=i/60;api.Animate(fx,t);assert.equal(JSON.stringify(fx.letters.style),base,'letters never move');assert.equal(nodes.length,n,'no frame allocations');
  assert(fx.pose.fxGain>=.15-1e-9&&fx.pose.fxGain<=1);near(api.Pose(t+3,id).opacity,fx.pose.opacity,'3 second sweep retained');
  if(id==='chushen'){assert.equal(+fx.left.style.opacity,1);assert.equal(+fx.right.style.opacity,1);assert(+fx.left.tail.style.opacity>=.35);}
 }
 for(const t of [0,5.5,period])assert.equal(api.Pose(t,id).action,0);
 assert(api.Pose(long.has(id)?2.9:1.95,id).action>.9);
 for(const t of [.2,1.3,2.3,4.8]){
  const a=api.Pose(t,id),b=api.Pose(t+period,id);for(const k of ['action','tail','roar','reach'])near(a[k],b[k],'gesture period');
 }
 const still=api.Create(node('Panel'),id,false);assert.equal(still.mask.visible,false);const st=JSON.stringify(still.stage.style);api.Animate(still,2);assert.equal(st,JSON.stringify(still.stage.style));
}
for(const id of Object.keys(rigs))api.Animate(rigs[id],1.95);
api.Animate(rigs.jinghong,2.8);assert(rigs.jinghong.wing.style.transform.includes('rotateZ(10.000deg)'));
assert(rigs.jinghong.tail.style.transform!==rigs.jinghong.wing.style.transform);
for(const id of ['jinghong','cangqiong'])assert(api.Pose(3.8,id).action>.6,'wing settles gradually');
api.Animate(rigs.youlong,2.3);assert(rigs.youlong.headRig.style.transform.includes('rotateZ(-8.000deg)'));assert(!rigs.youlong.claw.style.transform.includes('rotateZ(0.000deg)'));
assert(rigs.youlong.neck.children[0].image.endsWith('youlong_neck_v7.png'));assert.equal(rigs.youlong.neck.parent,rigs.youlong.headRig);assert.equal(rigs.youlong.head.parent,rigs.youlong.headRig);assert.equal(rigs.youlong.neck.style.transform,undefined);assert.equal(rigs.youlong.head.style.transform,undefined);
assert(+rigs.jian_tianya.bladeLight.band.style.opacity>0);assert(+rigs.jian_tianya.light.band.style.opacity===0);
assert.equal(api.Pose(2.44,'tianxia_diyi').roar,0);assert(api.Pose(2.44,'tianxia_diyi').action>.8);
for(const t of [2.68,3.1,3.74])near(api.Pose(t,'tianxia_diyi').roar,1,'held roar');
assert.equal(api.Pose(4.55,'tianxia_diyi').roar,0);
api.Animate(rigs.tianxia_diyi,3.3);assert(+rigs.tianxia_diyi.left.mouth.style.opacity>0);assert(rigs.tianxia_diyi.left.jaw.style.transform!==rigs.tianxia_diyi.right.jaw.style.transform);
assert(rigs.cangqiong.left.style.transform!==rigs.cangqiong.right.style.transform);
assert(rigs.sihai.left.root.style.transform!==rigs.sihai.right.root.style.transform);assert(rigs.sihai.left.sail.style.transform!==rigs.sihai.right.sail.style.transform);
assert(rigs.daoyuan.disc.style.transform.includes('rotateZ(11.700deg)'));
api.Animate(rigs.chushen,3.3);assert.equal(+rigs.chushen.left.style.opacity,1);assert(+rigs.chushen.left.tail.style.opacity<1&&+rigs.chushen.mistLeft.style.opacity>0);
assert(rigs.chushen.mistLeft.children[0].classes.includes('MotionMask_spirit_tail_left'));
for(const id of Object.keys(rigs)){api.Animate(rigs[id],5.5);assert.equal(+rigs[id].light.band.style.opacity,0);}
assert.equal(+rigs.tianxia_diyi.left.mouth.style.opacity,0);assert.equal(+rigs.chushen.left.tail.style.opacity,1);assert.equal(+rigs.chushen.mistLeft.style.opacity,0);
console.log('PASS V7: bounds, stationary letters, allocation-free updates, 6/8s gestures, 3s sweep, held roar, protected spirit heads and recovery');

for(const name of ['neck_body','neck_join','mountain','cloud','softband','spirit_head_left','spirit_head_right','spirit_tail_left','spirit_tail_right']){
 const svg=fs.readFileSync('panorama/src/images/custom_game/titles/motion/'+name+'.svg','utf8');
 for(const rect of svg.matchAll(/<rect\b[^>]*>/g))assert(!/(?:width|height)="[^"]*%"/.test(rect[0]),'native SVG rectangle bounds must be explicit: '+name);
 assert(svg.includes('viewBox="0 0 300 100"'),'native mask canvas: '+name);
}
console.log('PASS native Image aspect, transformed crop boundaries at four UI scales, and explicit SVG mask geometry');

// A visible snout lift must still settle without a per-frame snap at 60 fps.
let previousAngle=null,maxHeadStep=0;
for(let i=0;i<=720;i++){
 api.Animate(rigs.youlong,i/60);
 const angle=Number(rigs.youlong.headRig.style.transform.match(/rotateZ\(([-\d.]+)deg\)/)[1]);
 if(previousAngle!==null)maxHeadStep=Math.max(maxHeadStep,Math.abs(angle-previousAngle));previousAngle=angle;
}
assert(maxHeadStep<.4,'stronger head lift has no angular snap');
for(const time of [2.05,2.3,2.6])near(api.Pose(time,'youlong').action,1,'held head lift is readable');
for(const time of [0,4,5.99,6])near(api.Pose(time,'youlong').action,0,'full return before next loop');
assert.equal(rigs.cangqiong.mountain.style.position,rigs.cangqiong.peak.style.position,'peak light follows raised mountain');
const mountainTop=api.Config.cangqiong.height*(.05+.9*api.Config.cangqiong.rects[1][1]/100)-9;
assert(mountainTop>0,'raised mountains remain inside stage');
console.log('PASS stronger held dragon lift, smooth recovery and raised mountain/light registration');

// Native Panorama interprets bare gradient endpoints as tiny user-space values.
// Explicit canvas-sized coordinates prevent one-pixel mountain/neck strips.
for(const name of ['mountain_depth','cloud_depth','neck_body_depth']){
 const svg=fs.readFileSync('panorama/src/images/custom_game/titles/motion/'+name+'.svg','utf8');
 const gradients=[...svg.matchAll(/<linearGradient\b[^>]*>/g)];assert(gradients.length>0);
 for(const match of gradients){assert(match[0].includes('gradientUnits="userSpaceOnUse"'));assert(/(?:x2="300"|y2="100")/.test(match[0]),'native gradient spans the intended mask canvas');}
}
assert(rigs.youlong.body.children[0].classes.includes('MotionMask_neck_body_depth'));
assert(rigs.cangqiong.mountain.children[0].classes.includes('MotionMask_mountain_depth'));
assert(rigs.cangqiong.cloud.children[0].classes.includes('MotionMask_cloud_depth'));
console.log('PASS native explicit gradient coordinates for mountain, cloud and neck masks');
