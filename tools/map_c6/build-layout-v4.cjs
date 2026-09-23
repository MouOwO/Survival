// Recompose current saved map, retaining approved central art and room assets.
// Writes a reviewable source snapshot only. Installation is an explicit step.
'use strict';
const fs=require('fs'),path=require('path'),crypto=require('crypto'),L=require('./lib.cjs'),D=require('./layout-v4.cjs'),Mesh=require('./mesh.cjs');
const ROOT=path.resolve(__dirname,'../..'),OUT=path.join(ROOT,'output/map_layout_v4');
const source=fs.readFileSync(path.join(OUT,'template_before_text.vmap'),'utf8');
const previous=require('../../output/map_arena_integration_20260919/integration_manifest.json');
const current=require('../../output/map_layout_128_20260920/layout_manifest.json');
const seed=fs.readFileSync(path.join(OUT,'seed.vmap'),'utf8');
const assert=(ok,msg)=>{if(!ok)throw Error(msg)},vec=s=>s.split(/\s+/).map(Number),fmt=p=>p.map(v=>Math.round(v*1e6)/1e6).join(' ');
const inside=(x,y,b)=>x>=b[0]&&y>=b[1]&&x<=b[2]&&y<=b[3];
const entities=L.blocks(source,'CMapEntity'),meshes=L.blocks(source,'CMapMesh'),byNode=new Map([...entities,...meshes].map(b=>[+L.value(b.text,'nodeID'),b]));
const grid=L.blocks(source,'CMapDotaTileGrid')[0],g=L.blocks(grid.text,'CDmeDotaTileGrid')[0];
assert(L.value(g.text,'gridWidth')==='128','Expected the saved 128 tile current map');
let nextNode=Math.max(...[...source.matchAll(/"nodeID" "int" "(\d+)"/g)].map(m=>+m[1]))+1;
const uid=()=>crypto.randomUUID();
const reidentify=t=>t.replace(/"elementid" "[^"]+"/g,()=>`"elementid" "${uid()}"`).replace(/"nodeID" "int" "\d+"/g,()=>`"nodeID" "int" "${nextNode++}"`).replace(/"referenceID" "uint64" "[^"]+"/g,'"referenceID" "uint64" "0x0"');
function shift(t,d,mesh=false){if(mesh)return t.replace(/("name" "string" "position:0"[\s\S]*?"data" "vector3_array"\s*)\[([^\]]*)\]/,(_,h,b)=>h+'['+[...b.matchAll(/"([^"\r\n]*)"/g)].map(m=>'"'+fmt(vec(m[1]).map((v,i)=>v+d[i]))+'"').join(',')+']');return L.setValue(t,'origin',fmt(vec(L.value(t,'origin')).map((v,i)=>v+d[i])));}
const additions=[],areas=[],markers=[],patches=[],consumed=new Set(),replacements=new Map(),resources=new Set();
function entity(cls,name,p,props={},scale=1,yaw=0){const id=nextNode++;additions.push(`"CMapEntity" { "id" "elementid" "${uid()}" "nodeID" "int" "${id}" "children" "element_array" [] "entity_properties" "EditGameClassProps" { "id" "elementid" "${uid()}" ${Object.entries({classname:cls,targetname:name,...props}).map(([k,v])=>`"${k}" "string" "${v}"`).join(' ')} } "origin" "vector3" "${fmt(p)}" "angles" "qangle" "0 ${yaw} 0" "scales" "vector3" "${Array.isArray(scale)?fmt(scale):fmt([scale,scale,scale])}" "force_hidden" "bool" "0" "editorOnly" "bool" "0" }`);return id;}
function marker(name,p,role){const nodeID=entity('info_target',name,p);markers.push({name,origin:p,role,nodeID});return markers.at(-1);}
function addMesh(quads,material,paint){resources.add(material);const n=nextNode++;additions.push(Mesh.mesh(quads,material,n,paint));return n;}
function prop(model,p,scale=1,yaw=0,color='255 255 255'){resources.add(model);const tree=model.startsWith('models/props_tree/');entity(tree?'ent_dota_tree':'prop_static','',p,{model,solid:'0',rendercolor:color,skin:'0',...(tree?{always_use_showcase_tree:'1'}:{})},scale,yaw);}
// Each donor is extracted from the CURRENT saved map by its stable node IDs.
const donors=new Map(previous.areas.map(a=>{const c=current.areas.find(q=>q.id===a.id);assert(c,'Missing current area '+a.id);return [a.id,{...a,origin:c.origin,worldBounds:c.worldBounds,terrainBox:a.terrainBox.map((v,i)=>v+c.delta[i%2])}];}));
for(const a of donors.values())for(const q of [...a.placements,...a.supports,...a.markers])consumed.add(q.nodeID);
function cloneRoom(def,rename){
 const a=donors.get(def.donor||def.id),d=def.origin.map((v,i)=>v-a.origin[i]),b={...def,worldBounds:a.worldBounds.map(p=>p.map((v,i)=>v+d[i])),markers:[],supports:[],placements:[]};
 for(const q of [...a.placements,...a.supports]){
  const old=byNode.get(q.nodeID);assert(old,'Missing saved node '+q.nodeID);
  let t=reidentify(shift(old.text,d,a.supports.includes(q)));
  const name=L.value(t,'targetname');if(name)t=L.setValue(t,'targetname',name.replace('arena_integration_'+a.id,'v4_'+def.id));
  additions.push(t);(a.supports.includes(q)?b.supports:b.placements).push(+L.value(t,'nodeID'));
 }
 for(const q of a.markers){const old=byNode.get(q.nodeID);const name=rename?rename(q.name):q.name;if(name)b.markers.push(marker(name,vec(L.value(old.text,'origin')).map((v,i)=>v+d[i]),q.role));}
 // Paint/navigation only: the donor's empty water patch is cropped to avoid
 // overwriting adjacent rooms after compacting the layout.
 patches.push({id:def.id,box:[a.origin[0]-704,a.origin[1]-704,a.origin[0]+704,a.origin[1]+704],delta:d});
 areas.push(b);return b;
}
for(const a of D.training){
 const room=cloneRoom(a,n=>'player_'+a.player+'_'+n);
 if(a.player===0)for(const m of room.markers)marker(m.name.replace('player_0_',''),m.origin,m.role);
 if(a.kind===1){const p=[a.origin[0]-192,a.origin[1],152];for(const suffix of ['hero_spawn','training_entry','training_home'])marker('player_'+a.player+'_'+suffix,p);marker('player_'+a.player+'_training_target',[a.origin[0]+192,a.origin[1],152]);}
}
for(const a of [...D.rebirth,...D.rings])cloneRoom(a);
for(const a of D.endless){const room=cloneRoom(a,n=>n.endsWith('_entry')?`player_${a.player}_endless_cycle_sanctum_entry`:n.endsWith('_home')?`player_${a.player}_endless_cycle_sanctum_home`:null);marker(`player_${a.player}_endless_cycle_sanctum_target`,[a.origin[0]+150,a.origin[1]-64,152]);if(a.player===0){for(const m of room.markers)marker(m.name.replace('player_0_',''),m.origin,m.role);marker('endless_cycle_sanctum_target',[a.origin[0]+150,a.origin[1]-64,152]);}}
cloneRoom(D.dungeons[2]);
// Restore both omitted standalone challenge areas at their original size.
cloneRoom(D.eastChallenges.find(a=>a.id==='training_07'));
const legacy=current.patches.filter(p=>/^challenge_|reserve_native/.test(p.id)).map(p=>({...p,box:p.box.map((v,i)=>v+p.delta[i%2])}));
const legacyMoves=new Map([...D.dungeons.slice(0,2),D.eastChallenges.find(a=>a.id==='challenge_06')].map(d=>{const p=legacy.find(q=>q.id===d.id);const old=[(p.box[0]+p.box[2])/2,(p.box[1]+p.box[3])/2,128];return [d.id,{...d,box:p.box,delta:d.origin.map((v,i)=>v-old[i])}];}));
for(const p of legacyMoves.values()){assert(p.delta.slice(0,2).every(v=>v%256===0),'Native donor translation off grid');patches.push(p);}
const centralBox=[-4608,1024,2560,7168];patches.push({id:'central',box:centralBox,delta:[0,0,0]});
const rehome={challenge_10_stage_01_entry:[11648,-3072,152],challenge_10_stage_01_spawn:[13184,-3072,152]};
for(const b of entities){const id=+L.value(b.text,'nodeID'),name=L.value(b.text,'targetname')||'',cls=L.value(b.text,'classname'),p=vec(L.value(b.text,'origin')||'0 0 0');
 if(consumed.has(id)||name.startsWith('layout128_')||/^player_[0-3]_(hero_spawn|training_)/.test(name)){replacements.set(id,'');continue;}
 if(rehome[name]){replacements.set(id,L.setValue(b.text,'origin',fmt(rehome[name])));continue;}
 const old=legacy.find(a=>inside(p[0],p[1],a.box));
 if(old&&/^(prop_|ent_dota_tree|info_target)/.test(cls)){
  const move=legacyMoves.get(old.id);
  if(move){replacements.set(id,shift(b.text,move.delta));if(cls==='info_target')markers.push({name,origin:p.map((v,i)=>v+move.delta[i]),role:'legacy',nodeID:id});}
  else if(cls==='info_target'){replacements.set(id,L.setValue(b.text,'origin',fmt([-4096,-10496,152])));}
  else replacements.set(id,'');
 }
}
for(const b of meshes){const n=+L.value(b.text,'nodeID');if(consumed.has(n)||n>8161)replacements.set(n,'');}
// Read native tile grid channels from the current map and official tile seed.
function readArrays(t,min){const out={};for(const m of t.matchAll(/"(\w+)" "(int|uint8|bool|color|string)_array"\s*\[([^\]]*)\]/g)){const a=[...m[3].matchAll(/"([^"\r\n]*)"/g)].map(v=>v[1]);if(a.length>=min)out[m[1]]=a;}for(const k of ['cellConfiguration','cellConfigurationByName','objectConfiguration','objectConfigurationByName'])if(out[k])out[k]=L.records(out[k]);return out;}
const old=readArrays(g.text,16384),sg=L.blocks(seed,'CDmeDotaTileGrid')[0],sa=readArrays(sg.text,4096);
const variants=new Map();for(let y=0;y<64;y++)for(let x=0;x<64;x++){const i=y*64+x,vs=[y*65+x,y*65+x+1,(y+1)*65+x,(y+1)*65+x+1];if(vs.some(v=>sa.verticesHeight[v]!=='0'))continue;const k=sa.cellsTileSet[i]+':'+vs.map(v=>sa.verticesWater[v]).join('');if(!variants.has(k))variants.set(k,[]);variants.get(k).push(i);}
const wc=variants.get('0:1111')[0],arrays={},defaults={verticesHeight:'0',verticesWater:'1',gridnavFlags:'1',grassOpacity:'0',fogOpacity:'255',blendOpacity:'0 255 0 128',blendColor:'255 255 255 0',blendTransitionAndPath:'0 255 0 0',blendHeight:'128',flowMap:'10 20 0 0',fogFlowMap:'10 20 0 0',objectConfiguration:[],objectConfigurationByName:[]};
for(const [k,a] of Object.entries(old)){let val=defaults[k]??(k==='objectsVariationId'?'255':'0');if(k.startsWith('cells')||k.startsWith('cellConfiguration'))val=sa[k][wc];arrays[k]=Array(a.length).fill(val);}
const N=128,V=129,O=513,B=1025;
for(let y=0;y<V;y++)for(let x=0;x<V;x++){if(D.region(-16384+x*256,-16384+y*256))arrays.verticesWater[y*V+x]='0';}
for(let pass=0;pass<2;pass++)for(let y=0;y<N;y++)for(let x=0;x<N;x++){const vs=[y*V+x,y*V+x+1,(y+1)*V+x,(y+1)*V+x+1],s=vs.map(v=>arrays.verticesWater[v]).join('');if(s==='1001'||s==='0110')arrays.verticesWater[vs[s==='1001'?0:1]]='0';}
// The saved winter seed lacks two concave corner variants. Round those tiny
// coast notches into land instead of inserting conspicuous green Radiant tiles.
for(let pass=0;pass<32;pass++){
 let changed=0;
 for(let y=78;y<125;y++)for(let x=96;x<127;x++){
  const vs=[y*V+x,y*V+x+1,(y+1)*V+x,(y+1)*V+x+1],s=vs.map(v=>arrays.verticesWater[v]).join('');
  if(s==='1000'||s==='0100'||s==='1001'||s==='0110')for(const v of vs)if(arrays.verticesWater[v]==='1'){arrays.verticesWater[v]='0';changed++;}
 }
 if(!changed)break;
}
let fallback=0;
for(let y=0;y<N;y++)for(let x=0;x<N;x++){
 const i=y*N+x,vs=[y*V+x,y*V+x+1,(y+1)*V+x,(y+1)*V+x+1],water=vs.map(v=>arrays.verticesWater[v]).join('');
 const r=(x>=96&&x<127&&y>=78&&y<125&&water!=='1111'?D.continents.find(c=>c.id==='northeast'):null)||D.region(-16256+x*256,-16256+y*256)||vs.map(v=>D.region(-16384+(v%V)*256,-16384+Math.floor(v/V)*256)).find(Boolean);
 let ts=water==='1111'?0:r?.style==='snow'?2:['dire','volcanic'].includes(r?.style)?1:0;
 let options=variants.get(ts+':'+water);if(!options){ts=0;options=variants.get(ts+':'+water);fallback++;}if(!options){ts=1;options=variants.get('1:'+water);}assert(options,'No valid native shore mask '+water);
 const c=options[(x*13+y*7)%options.length];
 for(const k of ['cellsTileSet','cellsHidden','cellsOrientation','cellsMaterialSet','cellsCustomPathType','cellsVariationId','cellConfiguration','cellConfigurationByName'])arrays[k][i]=sa[k][c];
}
const clamp=v=>Math.max(0,Math.min(1,v)),smooth=(a,b,v)=>{let t=clamp((v-a)/(b-a));return t*t*(3-2*t);},byte=v=>Math.round(clamp(v)*255);
const noise=(x,y)=>.5+.2*Math.sin(x/347+y/193)+.16*Math.sin(y/139-x/251)+.1*Math.sin(x/91+y/77);
for(let y=0;y<B;y++)for(let x=0;x<B;x++){
 const wx=-16384+x*32,wy=-16384+y*32,r=D.region(wx,wy);if(!r)continue;const i=y*B+x,n=noise(wx,wy);let grass=.7,path=0;
 const fields=D.fields.filter(f=>f.continent===r.id),f=fields.find(f=>Math.abs(wx-f.center[0])<f.size[0]/2&&Math.abs(wy-f.center[1])<f.size[1]/2);
 const lane=fields.some(f=>f.spawn&&Math.abs(wy-f.center[1])<240&&wx>=Math.min(f.spawn[0],f.center[0])&&wx<=Math.max(f.spawn[0],f.center[0]));
 if(r.style==='radiant'){grass=f?.18+.33*n:.06+.14*n;path=1-grass;}else if(r.style==='snow'){grass=f?.32+.58*smooth(.3,.7,n):0;}else if(r.style==='dire'||r.style==='volcanic'){grass=0;path=.7+.22*n;}else{grass=f?.45+.3*n:.75+.2*n;}
 if(lane){grass*=.15;path=.95;}
 arrays.blendOpacity[i]=`${byte((1-grass)*.25)} ${byte(grass)} 0 128`;
 arrays.blendColor[i]=r.style==='snow'?'231 243 255 65':r.style==='radiant'?'255 248 226 30':r.style==='volcanic'?'100 111 126 70':'255 255 255 0';
 arrays.grassOpacity[i]=String(byte(grass*(r.style==='snow'?.04:.55)));
 arrays.blendTransitionAndPath[i]=`0 ${byte(path)} 0 0`;
}
// Restore untouched central paint and approved room collision masks.
for(const [k,a] of Object.entries(old)){
 if(k.startsWith('edges')){for(const p of patches.filter(p=>p.id==='central'||legacyMoves.has(p.id)))for(let o=0;o<2;o++)for(let y=0;y<129;y++)for(let x=0;x<128;x++){const wx=-16384+(o?y:x+.5)*256,wy=-16384+(o?x+.5:y)*256;if(!inside(wx,wy,p.box))continue;const nx=x+p.delta[o?1:0]/256,ny=y+p.delta[o?0:1]/256;arrays[k][o*128*129+ny*128+nx]=a[o*128*129+y*128+x];}continue;}
 let width,step,offset=0;if(a.length===16384){width=128;step=256;offset=128;}else if(a.length===16641){width=129;step=256;}else if(a.length===263169){width=513;step=64;}else if(a.length===262144){width=512;step=64;offset=32;}else if(a.length===1050625){width=1025;step=32;}else throw Error('Unknown array '+k+' '+a.length);
 for(const p of patches){const native=p.id==='central'||legacyMoves.has(p.id);if(!native&&k!=='gridnavFlags')continue;
  for(let y=Math.ceil((p.box[1]+16384-offset)/step);y<width&&-16384+y*step+offset<=p.box[3];y++)for(let x=Math.ceil((p.box[0]+16384-offset)/step);x<width&&-16384+x*step+offset<=p.box[2];x++){
   const nx=x+p.delta[0]/step,ny=y+p.delta[1]/step;assert(Number.isInteger(nx)&&Number.isInteger(ny),'Off lattice '+p.id+' '+k);arrays[k][ny*width+nx]=a[y*width+x];
  }
 }
}
// Native land navigation: keep a safe coastal inset, entire attack lanes clear.
for(let y=0;y<512;y++)for(let x=0;x<512;x++){const wx=-16352+x*64,wy=-16352+y*64,r=D.region(wx,wy);if(r&&r.distance<-220)arrays.gridnavFlags[y*512+x]='0';}
// Add functional markers, restrained shore vegetation and open battlefield rims.
let rng=90420;const random=()=>{rng=(Math.imul(rng,1664525)+1013904223)>>>0;return rng/4294967296;};
const rockModels=['models/props_rock/riveredge_rocks_small001.vmdl','models/props_rock/riveredge_rocks_small003.vmdl'];
for(const c of D.continents){
 let placed=0;
 for(let y=-15104;y<15360;y+=320)for(let x=-15872;x<15872;x+=320){
  const r=D.region(x,y);if(r?.id!==c.id)continue;const d=D.distance(c,x,y);if(d<-570||d>-130)continue;
  const route=D.fields.some(f=>f.continent===c.id&&f.spawn&&Math.abs(y-f.center[1])<500);if(route)continue;
  const px=x+(random()-.5)*90,py=y+(random()-.5)*90;
  const dark=['dire','volcanic'].includes(c.style),snow=c.style==='snow';
  prop(dark?'models/props_rock/badside_rocks003.vmdl':rockModels[placed%2],[px,py,96],.75+random()*.7,random()*360,snow?'220 231 240':'255 255 255');
  if(placed%3===0&&c.style!=='volcanic'){const model=snow?'models/props_tree/tree_pine_01_heavysnow.vmdl':dark?'models/props_tree/dire_tree004.vmdl':'models/props_tree/tree_oak_spring_01.vmdl';prop(model,[px,py,128],.85+random()*.3,random()*360);}
  placed++;
 }
 const cp=c.center||[(c.box[0]+c.box[2])/2,(c.box[1]+c.box[3])/2];marker('v4_'+c.id+'_entry',[...cp,152]);
 if(c.style==='volcanic'){
  // Narrow, irregular lava fissures around the rim, never across the usable core.
  const qs=[];for(let j=0;j<5;j++){const angle=j*1.256+.23,points=[];for(let k=0;k<6;k++){const r=1050+k*55,a=angle+Math.sin(k*2.4+j)*.09;points.push([cp[0]+r*Math.cos(a),cp[1]+r*Math.sin(a),132]);}for(let k=0;k<points.length-1;k++){const a=points[k],b=points[k+1],dx=b[0]-a[0],dy=b[1]-a[1],len=Math.hypot(dx,dy),w=10+k*3;qs.push([[a[0]-dy/len*w,a[1]+dx/len*w,132],[a[0]+dy/len*w,a[1]-dx/len*w,132],[b[0]+dy/len*w,b[1]-dx/len*w,132],[b[0]-dy/len*w,b[1]+dx/len*w,132]]);}}
  addMesh(qs,'materials/blends/dire_lava.vmat',()=>({blend:[1,0,0,.3],tint:[1,1,1,0]}));marker('v4_'+c.id+'_spawn',[cp[0]+384,cp[1],152]);
 }
}
function strip(x1,y1,x2,y2,width,z=140){const dx=x2-x1,dy=y2-y1,l=Math.hypot(dx,dy),a=-dy/l*width/2,b=dx/l*width/2;return [[x1+a,y1+b,z],[x1-a,y1-b,z],[x2-a,y2-b,z],[x2+a,y2+b,z]];}
for(const f of D.fields){
 const [x,y]=f.center,[w,h]=f.size,c=D.continents.find(c=>c.id===f.continent);marker('v4_'+f.id+'_center',[x,y,152]);
 const quads=[strip(x-w/2,y-h/2,x+w/2,y-h/2,48),strip(x+w/2,y+h/2,x-w/2,y+h/2,48)];
 for(const sign of [-1,1]){const ex=x+sign*w/2,opening=f.spawn&&(sign===(f.right?-1:1));if(opening){quads.push(strip(ex,y-h/2,ex,y-240,48),strip(ex,y+240,ex,y+h/2,48));}else quads.push(strip(ex,y-h/2,ex,y+h/2,48));}
 addMesh(quads,c.style==='dire'?'materials/blends/mod_dire_path_000.vmat':'materials/blends/mod_radiant_base_000.vmat',()=>({blend:[0,0,1,.3],tint:[1,1,1,0]}));
 if(f.spawn){marker('v4_'+f.id+'_spawn',[...f.spawn,152]);marker('v4_'+f.id+'_gate',[...f.entrance,152]);marker('v4_'+f.id+'_entry',[f.center[0]+(f.right?-384:384),y,152]);assert(f.spawn[1]===y,'Spawn not aligned');}
}
// Native multiblend surfaces: editable vertex paint, independent of props.
// Explicit material channels were verified with resourceinfo: Radiant base B
// selects stone, snow R selects snow / G grass, lava R selects glowing lava.
for(const c of D.continents.filter(c=>c.style==='radiant')){
 const quads=[];for(let y=-15104;y<-3072;y+=128)for(let x=-16000;x<1024;x+=128){const ps=[[x,y,129],[x+128,y,129],[x+128,y+128,129],[x,y+128,129]];if(ps.every(p=>D.distance(c,p[0],p[1])<-320))quads.push(ps);}
 const material='materials/blends/mod_radiant_base_000.vmat';
 addMesh(quads,material,(x,y)=>{const n=noise(x,y),edge=1-smooth(320,740,-D.distance(c,x,y));const f=D.fields.find(f=>f.continent===c.id&&Math.abs(x-f.center[0])<f.size[0]/2&&Math.abs(y-f.center[1])<f.size[1]/2);const inset=f?Math.min(f.size[0]/2-Math.abs(x-f.center[0]),f.size[1]/2-Math.abs(y-f.center[1])):0;const moss=f?(.65+.3*smooth(.25,.8,n))*smooth(0,128,inset):.035*smooth(.35,.8,n)+edge*.6;return {blend:[0,moss,1-moss,.4],tint:[1,.98,.91,.08]};});
}
for(const f of D.fields.filter(f=>['northeast','northwest'].includes(f.continent))){
 const snow=f.continent==='northeast',quads=[];const [x,y]=f.center,[w,h]=f.size;
 for(let dy=-h/2;dy<h/2;dy+=128)for(let dx=-w/2;dx<w/2;dx+=128)quads.push([[x+dx,y+dy,129],[x+dx+128,y+dy,129],[x+dx+128,y+dy+128,129],[x+dx,y+dy+128,129]]);
 addMesh(quads,snow?'materials/blends/mod_radiant_snow_default_001.vmat':'materials/blends/mod_dire_path_000.vmat',(px,py)=>{
  const n=noise(px,py),edge=smooth(0,220,Math.min(w/2-Math.abs(px-x),h/2-Math.abs(py-y)));
  const grass=edge*smooth(.27,.72,n)*.93;
  return snow?{blend:[1-grass,grass,0,.4],tint:[.87,.94,1,.07]}:{blend:[.12+.25*n,0,.84-.25*n,.35],tint:[1,1,1,0]};
 });
}
marker('shadow_realm_forecourt_entry',[5888,-12800,152]);marker('shadow_realm_forecourt_home',[5888,-12800,152]);
for(const [name,p] of Object.entries(rehome))if(!entities.some(b=>L.value(b.text,'targetname')===name))marker(name,p);
// The historical ice island has no home marker; give its restored room an
// explicit home at its original boss anchor, preserving the public contract.
if(!entities.some(b=>L.value(b.text,'targetname')==='challenge_06_home')){
 const boss=markers.find(m=>m.name==='challenge_06_boss_spawn');assert(boss,'Missing restored ice spawn');marker('challenge_06_home',boss.origin,'home');
}
// Validate every native resource before compilation, with zero invented paths.
const assets=new Set(fs.readFileSync(path.join(OUT,'assets.txt'),'utf8').split(/\r?\n/));for(const r of resources)assert(assets.has(r+'_c'),'Missing official resource '+r);
const updated=g.text.replace(/"(\w+)" "(int|uint8|bool|color|string)_array"\s*\[[^\]]*\]/g,(all,k,type)=>{if(!arrays[k])return all;const a=/Configuration/.test(k)?arrays[k].flatMap(r=>[String(r.length),...r]):arrays[k];return `"${k}" "${type}_array" [`+a.map(v=>'"'+v+'"').join(',')+']';});
const terrain=grid.text.slice(0,g.start)+updated+grid.text.slice(g.end);
const edits=[{...grid,text:terrain},...[...entities,...meshes].filter(b=>replacements.has(+L.value(b.text,'nodeID'))).map(b=>({...b,text:replacements.get(+L.value(b.text,'nodeID'))}))].sort((a,b)=>a.start-b.start);
let parts=[],cursor=0;for(const e of edits){assert(e.start>=cursor,'Nested edits');let before=source.slice(cursor,e.start);if(e.text===''){// Remove the trailing delimiter of a deleted element.
 if(/^\s*,/.test(source.slice(e.end,e.end+40))){let m=source.slice(e.end).match(/^\s*,/);parts.push(before);cursor=e.end+m[0].length;continue;}
 before=before.replace(/,\s*$/,'');}
 parts.push(before,e.text);cursor=e.end;}parts.push(source.slice(cursor));let result=parts.join('');
const world=result.indexOf('"world" "CMapWorld"'),cs=result.indexOf('[',result.indexOf('"children" "element_array"',world)),ce=L.endOf(result,cs,'[',']')-1;
result=result.slice(0,ce).replace(/,\s*$/,'')+',\n'+additions.join(',\n')+'\n'+result.slice(ce);
const finalEntities=L.blocks(result,'CMapEntity'),seen=new Set();for(const b of finalEntities){const n=L.value(b.text,'targetname');if(n){assert(!seen.has(n),'Duplicate target '+n);seen.add(n);}}
for(const a of areas)for(const b of areas){if(a.id>=b.id)continue;assert([0,1].some(k=>a.worldBounds[1][k]<b.worldBounds[0][k]||b.worldBounds[1][k]<a.worldBounds[0][k]),'Rooms overlap '+a.id+' '+b.id);}
const checks=[];for(const b of finalEntities){if(L.value(b.text,'classname')!=='info_target')continue;const name=L.value(b.text,'targetname'),p=vec(L.value(b.text,'origin'));const i=Math.floor((p[1]+16384)/64)*512+Math.floor((p[0]+16384)/64);if(/^(player_\d+_(challenge|hero|endless)|v4_.*_(spawn|center|entry|gate)|rebirth_|challenge_)/.test(name)){checks.push({name,origin:p,open:arrays.gridnavFlags[i]==='0'});}}
assert(checks.every(q=>q.open),'Blocked target '+checks.filter(q=>!q.open).map(q=>q.name).join(','));
fs.writeFileSync(path.join(OUT,'template_layout_v4.vmap'),result);
fs.writeFileSync(path.join(OUT,'manifest.json'),JSON.stringify({map:'template_map',grid:128,source_sha256:crypto.createHash('sha256').update(source).digest('hex'),centralPreserved:true,areas,continents:D.continents,fields:D.fields,dungeons:D.dungeons,eastChallenges:D.eastChallenges,markers:checks,resources:[...resources],entityCount:finalEntities.length,fallbackShoreCells:fallback},null,2));
console.log(JSON.stringify({output:'template_layout_v4.vmap',rooms:areas.length,continents:D.continents.length,entities:finalEntities.length,markers:checks.length,fallback}));
