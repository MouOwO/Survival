// Approved V4 layout, in world units. All native terrain edits snap to 256 units.
'use strict';
const fieldSize=[1792,1536];
const continents=[
 {id:'northwest',style:'dire',box:[-15872,3072,-8960,14848]},
 {id:'northeast',style:'snow',box:[8704,4096,15872,15104]},
 {id:'southwest_a',style:'radiant',box:[-15872,-14848,-9216,-3328]},
 {id:'southwest_b',style:'radiant',center:[-4096,-10496],cross:true},
 {id:'east_mode',style:'grass',box:[8960,-6144,15872,0]},
 ...[2304,5888,9472,13056].map((x,i)=>({id:'volcanic_'+(i+1),style:'volcanic',center:[x,-12800],radius:1472}))
];
const fields=[];
for(const [id,ys,xs] of [
 ['northeast',[13056,10496,7936,5376],[14336,10752]],
 ['southwest_a',[-5120,-7680,-10240,-12800],[-10752,-14336]]
])for(let i=0;i<4;i++){
 const x=xs[i%2], y=ys[i],right=i%2===0;
 const spawnX=id==='northeast'?(right?9728:14848):(right?-14848:-10240);
 fields.push({id:id+'_field_'+(i+1),continent:id,center:[x,y],size:fieldSize,spawn:[spawnX,y],entrance:[x+(right?-1:1)*fieldSize[0]/2,y],right});
}
for(let i=0;i<4;i++)fields.push({id:'northwest_field_'+(i+1),continent:'northwest',center:[i%2?-10752:-14080,i<2?12288:6144],size:fieldSize});
for(const [i,dx,dy] of [[1,0,2560],[2,3072,0],[3,0,-2560],[4,-3072,0]])fields.push({id:'southwest_b_field_'+i,continent:'southwest_b',center:[-4096+dx,-10496+dy],size:fieldSize});
fields.push({id:'east_mode_field_1',continent:'east_mode',center:[12416,-3072],size:[4096,3328]});
const roomColumns=[[-6144,-4352,-2560,-768],[1792,3584,5376,7168]];
const training=[];
for(let p=0;p<4;p++)for(let k=1;k<=4;k++)training.push({id:`player_${p}_training_${k}`,donor:'training_0'+k,player:p,kind:k,origin:[roomColumns[p%2][k-1],p<2?12800:-4608,128]});
const rebirth=Array.from({length:10},(_,i)=>({id:'rebirth_'+String(i+1).padStart(2,'0'),origin:[-7424,9728-i*1408,16]}));
const rings=Array.from({length:10},(_,i)=>({id:'ten_realm_'+String(i+1).padStart(2,'0'),origin:[4864+(i%2)*1792,8704-Math.floor(i/2)*2048,58]}));
const endless=[3328,6144,8960,11776].map((x,p)=>({id:`player_${p}_endless`,donor:'training_04',player:p,origin:[x,-7936,128]}));
// Shift the whole dungeon column northwest relative to the approved concept.
const dungeons=[{id:'challenge_05',origin:[-5248,10752,128]},{id:'challenge_09',origin:[-5248,8704,128]},{id:'training_08',origin:[-5120,6656,128]}];
const eastChallenges=[{id:'challenge_06',origin:[10624,2304,128]},{id:'training_07',origin:[14336,2304,128]}];
function distance(c,x,y){
 if(c.cross){const [cx,cy]=c.center;return Math.min(Math.hypot((x-cx)/1.05,y-cy)-1050,...[[0,2560],[3072,0],[0,-2560],[-3072,0]].map(([a,b])=>Math.hypot((x-cx-a)/1.08,y-cy-b)-1350),Math.max(Math.abs(x-cx)-3072,Math.abs(y-cy)-600),Math.max(Math.abs(x-cx)-600,Math.abs(y-cy)-2560));}
 if(c.radius)return Math.hypot(x-c.center[0],y-c.center[1])-c.radius;
 const [a,b,d,e]=c.box,r=480,cx=(a+d)/2,cy=(b+e)/2;
 const qx=Math.abs(x-cx)-(d-a)/2+r,qy=Math.abs(y-cy)-(e-b)/2+r;
 return Math.hypot(Math.max(qx,0),Math.max(qy,0))+Math.min(Math.max(qx,qy),0)-r;
}
function region(x,y){for(const c of continents){const d=distance(c,x,y),n=95*Math.sin(x/407+y/321)+65*Math.sin(y/211-x/617);if(d+n<=0)return {...c,distance:d};}return null;}
module.exports={continents,fields,training,rebirth,rings,endless,dungeons,eastChallenges,region,distance};
