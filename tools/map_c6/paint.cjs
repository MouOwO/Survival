// Native Tile Grid paint maps, editable with Hammer's Shift+V Paint Tool.
// Radiant multiblend: base=sand, R/G=two grasses, B=cliff. Alpha is
// the existing blend-sharpness value. Height and navigation are untouched.
const D=require('./layout.cjs');
const clamp=v=>Math.max(0,Math.min(1,v));
const smooth=(a,b,v)=>{const t=clamp((v-a)/(b-a));return t*t*(3-2*t);};
const byte=v=>Math.max(0,Math.min(255,Math.round(v)));
const roomById=new Map(D.rooms.map(r=>[r.id,r]));
function noise(x,y){return .5+.19*Math.sin(x*.73+y*.38)+.16*Math.sin(x*1.67-y*.91)+.1*Math.sin(y*3.1+x*2.2);}
function sample(x,y){
 const r=D.region(x,y),n=noise(x,y);
 if(!r.land)return {opacity:'0 255 0 128',color:'255 255 255 0',grass:0,path:0};
 let path=0,edge=0;
 if(r.central){
  const dx=(x-D.center.x)*D.tile,dy=(y-D.center.y)*D.tile;
  path=D.sanctuary.paint(dx,dy).path;
  edge=smooth(2200,2600,Math.hypot(dx,dy));
 }else if(r.room){
  const q=roomById.get(r.room),cx=q.x+q.w/2,cy=q.y+q.h/2;
  const inset=Math.min(x-q.x,q.x+q.w-x,y-q.y,q.y+q.h-y);
  const ellipse=Math.hypot((x-cx)/(q.w*.39),(y-cy)/(q.h*.37));
  path=(1-smooth(.5,1.05,ellipse))*1.25;
  path=Math.max(path,1-smooth(.4,1.0,Math.abs(y-cy)));
  edge=1-smooth(.3,1.3,inset);
 }else if(r.plain){
  path=.88*(1-smooth(.8,1.9,Math.abs(x-(10.5+1.5*Math.sin(y*.15)))));
 }else if(r.star){path=.9*(1-smooth(.9,1.8,Math.min(Math.abs(x-43),Math.abs(y-22))));}
 else if(r.ledge){path=.8*(1-smooth(.7,1.7,Math.abs(x-106.5)));}
 else if(r.boss){path=.9*(1-smooth(1.7,3.5,Math.hypot(x-62,y-31)));}
 // Keep fully painted centers truly solid; irregularity belongs at edges.
 const wear=clamp(path+(n-.5)*.18*4*clamp(path)*(1-clamp(path)));
 const g=byte(255*(1-wear));
 const red=byte((8+34*n+15*edge)*(1-wear));
 const palettes=[[250,244,237],[251,232,204],[233,248,222],[233,244,255]];
 const tint=palettes[r.season||0],alpha=byte(32+edge*25+n*18);
 return {opacity:`${red} ${g} 0 128`,color:`${tint.join(' ')} ${alpha}`,grass:byte((65+165*n)*(1-wear*.97)*(r.season===3?.3:1)),path:wear};
}
function apply(arrays,B){
 let painted=0;
 for(let y=0;y<B;y++)for(let x=0;x<B;x++){
  const p=sample(x/8,y/8),i=y*B+x;
  arrays.blendOpacity[i]=p.opacity;arrays.blendColor[i]=p.color;arrays.grassOpacity[i]=p.grass;
  if(p.opacity!=='0 255 0 128')painted++;
 }
 return {resolution:B,sampleSpacing:32,paintedSamples:painted};
}
module.exports={sample,apply};
