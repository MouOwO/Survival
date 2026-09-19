// Author the same editable tile-grid channels used by Hammer's terrain brushes.
// Official tile sets resolve cliffs, corners and stair transitions at compile time.
const fs=require('fs'),path=require('path');
const {worldChildren,name}=require('./basin_handoff_merge.cjs');
const root=path.resolve(__dirname,'..'),out=path.join(root,'output/basin_native');fs.mkdirSync(out,{recursive:true});
const base=fs.readFileSync(path.join(root,'output/zombie_island_v1/source_template.vmap'),'utf8');
let s=base.slice(base.indexOf('"CMapRootElement"')),w=worldChildren(s),grid=w.nodes.find(n=>n.startsWith('"CMapDotaTileGrid"'));
const arr=(k,t,a)=>'"'+k+'" "'+t+'_array"\n['+a.map(v=>'"'+v+'"').join(',\n')+']';
const smooth=x=>{x=Math.max(0,Math.min(1,x));return x*x*(3-2*x);};
const noise=(x,y)=>Math.sin(x*.003+y*.001)*.48+Math.cos(y*.004-x*.002)*.32+Math.sin(x*.011+y*.009)*.2;
const D=2816,R=1088;
function local(x,y){return Math.abs(x)>=Math.abs(y)?{u:Math.abs(x),v:y,q:x>=0?0:2}:{u:Math.abs(y),v:x,q:y>=0?1:3};}
function courtDistance(x,y){const p=local(x,y),a=Math.atan2(p.v,p.u-D);return Math.hypot(p.u-D,p.v)-(R+55*Math.sin(a*3+.5)+32*Math.sin(a*7));}
function height(x,y){
 const r=Math.hypot(x,y),p=local(x,y),d=courtDistance(x,y);
 let h=Math.max(0,4-Math.ceil(Math.max(0,d)/256));
 // Low basin with raised shoulders in the non-route quadrants.
 if(r<1152)h=Math.max(h,1+(r>768&&Math.min(Math.abs(x),Math.abs(y))>384?1:0));
 // Three 128-unit official stair rises with short landings in between.
 if(p.u>=768&&p.u<=2304&&Math.abs(p.v)<=256)h=Math.max(h,Math.min(4,1+Math.floor(Math.max(0,p.u-1024)/256)));
 return h;
}
const heights=Array.from({length:4225},(_,i)=>height(-8192+i%65*256,-8192+Math.floor(i/65)*256));
// Respect the official tile library's one-level-per-cell cliff limit.
for(let pass=0;pass<6;pass++)for(let y=0;y<65;y++)for(let x=0;x<65;x++)for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++)if(x+dx>=0&&x+dx<65&&y+dy>=0&&y+dy<65)heights[y*65+x]=Math.min(heights[y*65+x],heights[(y+dy)*65+x+dx]+1);
const getHeight=(x,y)=>heights[Math.max(0,Math.min(64,Math.round((y+8192)/256)))*65+Math.max(0,Math.min(64,Math.round((x+8192)/256)))];
// Geometry-first review: one official palette avoids theme seams obscuring shape.
function biome(x,y){return 0;}
function active(x,y){const p=local(x,y);return Math.hypot(x,y)<970||(p.u>768&&p.u<2176&&Math.abs(p.v)<210)||Math.hypot(p.u-D,p.v)<850;}
grid=grid.replace('"-8192 -8192 128"','"-8192 -8192 0"').replaceAll('dire_basic.vmap','radiant_desert_basic.vmap').replaceAll('radiant_summer_basic.vmap','radiant_spring_basic.vmap');
grid=grid.replace(/^(\t{6})"(\w+)" "(\w+)_array"\s*\[([^\]]*)\]/gm,(all,indent,k,t,body)=>{
 if(t==='element')return all;
 let a=[...body.matchAll(/"([^"]*)"/g)].map(m=>m[1]);
 if(/^(cell|object)Configuration/.test(k))return indent+arr(k,t,[]);
 if(!/^(cells|vertices|edges|objects|blend|grass|fog|flow|gridnav)/.test(k))return all;
 for(let i=0;i<a.length;i++){
  let x,y,vertical=false;
  if(a.length===4096){x=-8192+i%64*256+128;y=-8192+Math.floor(i/64)*256+128;}
  else if(a.length===4225){x=-8192+i%65*256;y=-8192+Math.floor(i/65)*256;}
  else if(a.length===8320){const row=Math.floor(i/129),col=i%129;vertical=row<64&&col%2===0;x=-8192+(row<64?Math.floor(col/2):col)*256;y=-8192+row*256;}
  else if(a.length===66049){x=-8192+i%257*64;y=-8192+Math.floor(i/257)*64;}
  else if(a.length===65536){x=-8192+i%256*64+32;y=-8192+Math.floor(i/256)*64+32;}
  else if(a.length===263169){x=-8192+i%513*32;y=-8192+Math.floor(i/513)*32;}
  else throw Error('Unexpected grid channel '+k+' '+a.length);
  const p=local(x,y),r=Math.hypot(x,y),n=noise(x,y),b=biome(x,y),route=Math.exp(-Math.pow(p.v/230,2))*smooth((p.u-450)/600)*(1-smooth((p.u-2550)/500));
  let value=0;
  if(/VariationId$/.test(k))value=255;
  if(k==='verticesHeight')value=heights[i];
  // Official river tiles introduce a blocking bank. Keep native bed walkable;
  // the shallow water surface is a separate water-only mesh above that bed.
  if(k==='verticesWater')value=0;
  if(k==='cellsHidden')value=courtDistance(x,y)>900&&r>2112?1:0;
  if(k==='cellsTileSet'||k==='objectsTileSet')value=b;
  if(k==='edgesPath'){
   const mx=x+(vertical?0:128),my=y+(vertical?128:0),p2=local(mx,my);
   value=p2.u>=768&&p2.u<=2304&&Math.abs(p2.v)<200?1:0;
  }
  if(k==='blendOpacity'){
   const dirt=Math.round(255*Math.max(.04,Math.min(.85,.16+.22*n+.42*route+.23*Math.exp(-Math.pow((r-450)/220,2)))));
   const paving=Math.round(140*route);
   value=(r<490?Math.max(dirt,Math.round(230*(1-smooth((r-320)/250)))):dirt)+' 255 '+paving+' 128';
  }
  if(k==='blendColor')value='255 255 255 0';
  if(k==='blendTransitionAndPath')value='0 255 0 0';
  if(k==='blendHeight')value=r<540?Math.round(128-20*(1-smooth((r-280)/260))):Math.round(128+10*n*(1-route));
  if(k==='grassOpacity')value=b===2||b===1||route>.45||r<550?0:Math.round(110+65*n);
  if(k==='flowMap'||k==='fogFlowMap')value='10 20 0 0';
  if(k==='gridnavFlags')value=active(x,y)?0:1;
  a[i]=value;
 }
 return indent+arr(k,t,a);
});
const review=worldChildren(fs.readFileSync(path.join(root,'output/basin_review/survival_basin_review.vmap'),'utf8'));
let lighting=review.nodes.find(n=>name(n)==='AI_03_LIGHT_AND_MARKERS');
// Keep only lights, spawn points, bounds and game events, with fresh preview heights.
lighting=lighting.replaceAll('"0 0 88"','"0 0 64"').replaceAll('"0 0 80"','"0 0 64"');
const terrain=review.nodes.find(n=>name(n)==='AI_01_TERRAIN');
// Retain the distant background alone; every playable surface comes from tilegrid.
function childNodes(n){return worldChildren('"world" "CMapWorld"\n{'+n.slice(n.indexOf('"children"'))+'}').nodes;}
const backdrop=childNodes(terrain).find(n=>n.includes('cloud_horizon.vmat'));
const water=childNodes(terrain).find(n=>n.includes('shallow_water.vmat')).replace('"origin" "vector3" "0 0 0"','"origin" "vector3" "0 0 50"');
const nodes=[grid,lighting,backdrop,water].filter(Boolean);
s=s.slice(0,w.a+1)+'\n'+nodes.join(',\n')+'\n'+s.slice(w.b);
let id=1;s=s.replace(/("nodeID"\s+"int"\s+")\d+/g,(_,p)=>p+id++);
fs.writeFileSync(path.join(out,'survival_basin_native.vmap'),'<!-- dmx encoding keyvalues2 4 format vmap 40 -->\n'+s);
fs.writeFileSync(path.join(out,'design.json'),JSON.stringify({map:'survival_basin_native',nativeTileGrid:true,activeTileSet:'radiant_basic',courtCenters:[[D,0],[0,D],[-D,0],[0,-D]],courtHeight:512,basinLevel:128,stairs:'native edgesPath; 128-unit height levels',addedDecorations:0,stage:'terrain shape review; theme paint deferred'},null,2));
console.log('Native terrain preview authored:',path.join(out,'survival_basin_native.vmap'));
