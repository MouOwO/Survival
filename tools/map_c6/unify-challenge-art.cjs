// Patch the latest saved Hammer snapshot. Never rebuild the full V4 layout.
'use strict';
const fs=require('fs'),crypto=require('crypto'),L=require('./lib.cjs'),Mesh=require('./mesh.cjs');
const out='output/challenge_art_unify',source=fs.readFileSync(out+'/before_text.vmap','utf8');
const sha=s=>crypto.createHash('sha256').update(s).digest('hex');
const assert=(v,m)=>{if(!v)throw Error(m);},vec=s=>s.split(/\s+/).map(Number);
const fmt=p=>p.map(v=>Math.round(v*1e5)/1e5).join(' '),uid=()=>crypto.randomUUID();
const entities=L.blocks(source,'CMapEntity'),meshes=L.blocks(source,'CMapMesh');
let next=Math.max(...[...source.matchAll(/"nodeID" "int" "(\d+)"/g)].map(m=>+m[1]))+1;
const defs=[
 {id:'05',name:'合成宝石',center:[-5248,10752],theme:'snow'},
 {id:'09',name:'冰烬挽歌',center:[-5248,8704],theme:'waterfire'},
 {id:'08',name:'火焰巨魔',center:[-5120,6656],theme:'volcanic'},
 {id:'06',name:'冰之幽魂',center:[10624,2304],theme:'snow'},
 {id:'07',name:'熔火核心',center:[14336,2304],theme:'volcanic'}
];
const old=require('../../output/map_layout_v4/manifest.json');
const removeIDs=new Set(old.areas.filter(a=>['training_07','training_08'].includes(a.id)).flatMap(a=>[...a.placements,...a.supports]));
const removed=[],edits=[],additions=[],resources=new Set(),markers=[],newNodes=[];
const targeted=n=>/^challenge_(05|06|07|08|09)_/.test(n||'');
for(const b of [...entities,...meshes])if(removeIDs.has(+L.value(b.text,'nodeID'))){edits.push({...b,text:''});removed.push(+L.value(b.text,'nodeID'));}
// Public gameplay names survive; reposition every existing spawn within its own room.
function markerPosition(d,name){
 let p=[0,-295,148];
 if(name.endsWith('boss_spawn'))p=[0,100,148];
 else if(name.endsWith('_home'))p=[0,40,148];
 else if(/_spawn_\d+$/.test(name)){const a=(+name.match(/(\d+)$/)[1]-1)*Math.PI/5;p=[155*Math.cos(a),100+130*Math.sin(a),148];}
 return [p[0]+d.center[0],p[1]+d.center[1],p[2]];
}
for(const b of entities){const name=L.value(b.text,'targetname');if(!targeted(name))continue;const d=defs.find(a=>name.startsWith('challenge_'+a.id+'_'));const p=markerPosition(d,name);edits.push({...b,text:L.setValue(b.text,'origin',fmt(p))});markers.push({name,origin:p});}
function entity(cls,name,p,props={},scale=1,yaw=0){const id=next++;newNodes.push(id);additions.push(`"CMapEntity" { "id" "elementid" "${uid()}" "nodeID" "int" "${id}" "children" "element_array" [] "entity_properties" "EditGameClassProps" { "id" "elementid" "${uid()}" ${Object.entries({classname:cls,targetname:name,...props}).map(([k,v])=>`"${k}" "string" "${v}"`).join(' ')} } "origin" "vector3" "${fmt(p)}" "angles" "qangle" "0 ${yaw} 0" "scales" "vector3" "${fmt([scale,scale,scale])}" "force_hidden" "bool" "0" "editorOnly" "bool" "0" }`);}
for(const d of defs)for(const suffix of ['entry','home','boss_spawn']){const name='challenge_'+d.id+'_'+suffix;if(markers.some(m=>m.name===name))continue;const p=markerPosition(d,name);entity('info_target',name,p);markers.push({name,origin:p});}
const snow='materials/blends/mod_radiant_snow_default_001.vmat';
const hot='materials/blends/dire_lava.vmat',cold='materials/blends/dire_lava_ice.vmat';
const clamp=v=>Math.max(0,Math.min(1,v));
const smooth=(a,b,v)=>{const t=clamp((v-a)/(b-a));return t*t*(3-2*t);};
const noise=(x,y)=>.5+.22*Math.sin(x/107+y/151)+.17*Math.cos(y/73-x/181)+.08*Math.sin(x/29+y/47);
function addMesh(q,mat,paint,collision=true){if(!q.length)return;resources.add(mat);const id=next++;newNodes.push(id);let t=Mesh.mesh(q,mat,id,paint);if(!collision)t=L.setValue(t,'physicsType','none');additions.push(t);}
const H=524.5,N=24;
// Rounded, chipped natural outline. Cardinal extrema are exactly +/-524.5.
function xy(u,v){const r=Math.max(Math.abs(u),Math.abs(v)),a=Math.atan2(v,u);const chip=1-.026*r*r*Math.sin(4*a)**2*(.6+.4*Math.sin(7*a)**2);return [H*u*Math.sqrt(1-.18*v*v)*chip,H*v*Math.sqrt(1-.18*u*u)*chip];}
function height(x,y){const r=Math.max(Math.abs(x),Math.abs(y))/H;return 128+smooth(.55,1,r)*(9+7*noise(x,y));}
function floorPaint(d,x,y){const n=noise(x,y),r=Math.max(Math.abs(x),Math.abs(y))/H;
 if(d.theme==='snow'){const amount=clamp(.79+.19*n+.09*smooth(.5,.95,r)-.22*Math.exp(-(((x+70*Math.sin(y/130))/100)**2)));return {blend:[amount,0,0,.42],tint:[.91,.97,1,0]};}
 // Both hot and cold native materials share basalt channel G. Their shared
 // seam is pure basalt, so water/fire colours interpenetrate without a tile edge.
 const seam=d.theme==='waterfire'?smooth(15,130,Math.abs(x)):1;
 const fissure=smooth(.57,.81,n)*smooth(.40,.91,r)*seam*.85;
 return {blend:[fissure,1-fissure,0,.42],tint:[1,1,1,0]};
}
for(const d of defs){const [cx,cy]=d.center;let quads=[[],[]],boundary=[];
 const point=(i,j)=>{const p=xy(-1+2*i/N,-1+2*j/N);return [cx+p[0],cy+p[1],height(...p)];};
 for(let j=0;j<N;j++)for(let i=0;i<N;i++)quads[d.theme==='waterfire'&&i<N/2?1:0].push([point(i,j),point(i+1,j),point(i+1,j+1),point(i,j+1)]);
 const paint=(x,y)=>floorPaint(d,x-cx,y-cy);
 addMesh(quads[0],d.theme==='snow'?snow:hot,paint);
 addMesh(quads[1],cold,paint);
 for(let i=0;i<N;i++)boundary.push(point(i,0));
 for(let i=0;i<N;i++)boundary.push(point(N,i));
 for(let i=N;i>0;i--)boundary.push(point(i,N));
 for(let i=N;i>0;i--)boundary.push(point(0,i));
 const sides=[];
 for(let i=0;i<boundary.length;i++){const a=boundary[i],b=boundary[(i+1)%boundary.length],aa=[cx+(a[0]-cx)*.965,cy+(a[1]-cy)*.965,2],bb=[cx+(b[0]-cx)*.965,cy+(b[1]-cy)*.965,2];sides.push([a,aa,bb,b]);}
 addMesh(sides,d.theme==='snow'?snow:hot,(x,y,z)=>({blend:d.theme==='snow'?[.10+.56*smooth(65,146,z),0,0,.45]:[0,1,0,.45],tint:[1,1,1,0]}));
 // Uneven groups of weathered fallen rocks, kept inside the 1049 footprint.
 // Low southern rim leaves entry and characters visible from the game camera.
 const boulders=[];
 for(let k=0;k<24;k++){
  const a=k*Math.PI/12+.022*Math.sin(k*2.1),dx=Math.cos(a),dy=Math.sin(a),factor=390/Math.max(Math.abs(dx),Math.abs(dy));
  const x=dx*factor,y=dy*factor;
  if(y<-300&&Math.abs(x)<150)continue;
  const rx=48+19*(.5+.5*Math.sin(k*2.13)),ry=43+21*(.5+.5*Math.cos(k*1.9)),h=(y<0?65:100)+45*(.5+.5*Math.sin(k*2.7));
  const rings=[[],[],[],[]];
  for(let j=0;j<8;j++){const ang=j*Math.PI/4+.11*Math.sin(k),w=1+.14*Math.sin(j*3.1+k*1.9);for(let l=0;l<4;l++){const scales=[.94,1,.79,.23],zs=[-6,h*.22,h*.77,h];rings[l].push([cx+x+Math.cos(ang)*rx*w*scales[l]+l*5*Math.sin(k),cy+y+Math.sin(ang)*ry*w*scales[l],height(x,y)+zs[l]]);}}
  for(let l=0;l<3;l++)for(let j=0;j<8;j++)boulders.push([rings[l][j],rings[l][(j+1)%8],rings[l+1][(j+1)%8],rings[l+1][j]]);
  for(let j=0;j<8;j+=2)boulders.push([rings[3][j],rings[3][(j+1)%8],rings[3][(j+2)%8],[cx+x,cy+y,height(x,y)+h+3]]);
 }
 addMesh(boulders,d.theme==='snow'?snow:hot,(x,y,z)=>({blend:d.theme==='snow'?[.25+.73*smooth(155,225,z),0,0,.35]:[0,1,0,.35],tint:[1,1,1,0]}));
 // Native small debris grounds the larger banks without filling the fight area.
 for(let k=0;k<17;k++){const a=k*2.399963,rr=310+30*Math.sin(k*3.7),p=[Math.cos(a)*rr,Math.sin(a)*rr];if(p[1]<-200&&Math.abs(p[0])<120)continue;const model='models/props_rock/riveredge_rocks_small003.vmdl';resources.add(model);entity('prop_static','challenge_art_'+d.id+'_debris_'+k,[cx+p[0],cy+p[1],height(...p)-3],{model,solid:'0',rendercolor:d.theme==='snow'?'195 214 224':'146 155 161',skin:'0'},.35+.19*(.5+.5*Math.sin(k)),k*137.5);}
 d.size=[1049,1049];d.floorZ=128;d.clearCore=[600,600];
}
// Only navigation cells in these five room footprints or replaced supports change.
const grid=L.blocks(source,'CMapDotaTileGrid')[0],g=L.blocks(grid.text,'CDmeDotaTileGrid')[0];
const nav=L.array(g.text,'gridnavFlags'),navBefore=[...nav];
const clearBoxes=defs.map(d=>[d.center[0]-730,d.center[1]-730,d.center[0]+730,d.center[1]+730]);
for(const b of meshes.filter(b=>removeIDs.has(+L.value(b.text,'nodeID')))){
 const m=b.text.match(/"name" "string" "position:0"[\s\S]*?"data" "vector3_array"\s*\[([^\]]*)\]/);if(!m)continue;
 const ps=[...m[1].matchAll(/"([^"\r\n]*)"/g)].map(m=>vec(m[1]));
 const o=vec(L.value(b.text,'origin')||'0 0 0');clearBoxes.push([0,1].map(i=>Math.min(...ps.map(p=>p[i]))+o[i]-64).concat([0,1].map(i=>Math.max(...ps.map(p=>p[i]))+o[i]+64)));
}
for(let y=0;y<512;y++)for(let x=0;x<512;x++){const wx=-16352+x*64,wy=-16352+y*64,i=y*512+x;if(clearBoxes.some(b=>wx>=b[0]&&wy>=b[1]&&wx<=b[2]&&wy<=b[3]))nav[i]='1';for(const d of defs)if(Math.abs(wx-d.center[0])<310&&Math.abs(wy-d.center[1])<310)nav[i]='0';}
const updated=L.setArray(g.text,'gridnavFlags',nav),terrain=grid.text.slice(0,g.start)+updated+grid.text.slice(g.end);edits.push({...grid,text:terrain});
const assets=new Set(fs.readFileSync('output/map_layout_v4/assets.txt','utf8').split(/\r?\n/));for(const r of resources)assert(assets.has(r+'_c'),'Missing resource '+r);
edits.sort((a,b)=>a.start-b.start);let parts=[],cursor=0;
for(const e of edits){assert(e.start>=cursor,'Overlapping edit');let before=source.slice(cursor,e.start);if(e.text===''){const comma=source.slice(e.end).match(/^\s*,/);if(comma){parts.push(before);cursor=e.end+comma[0].length;continue;}before=before.replace(/,\s*$/,'');}parts.push(before,e.text);cursor=e.end;}
parts.push(source.slice(cursor));let result=parts.join('');const world=result.indexOf('"world" "CMapWorld"'),cs=result.indexOf('[',result.indexOf('"children" "element_array"',world)),ce=L.endOf(result,cs,'[',']')-1;result=result.slice(0,ce).replace(/,\s*$/,'')+',\n'+additions.join(',\n')+'\n'+result.slice(ce);
const final=L.blocks(result,'CMapEntity'),names=final.map(b=>L.value(b.text,'targetname')).filter(Boolean);assert(new Set(names).size===names.length,'Duplicate markers');
// Verify that all unrelated entities/meshes, including manual deletions, survive byte for byte.
const keep=[...entities,...meshes].filter(b=>!removeIDs.has(+L.value(b.text,'nodeID'))&&!targeted(L.value(b.text,'targetname')));
const afterNodes=new Map([...final,...L.blocks(result,'CMapMesh')].map(b=>[L.value(b.text,'nodeID'),b.text]));
for(const b of keep)assert(afterNodes.get(L.value(b.text,'nodeID'))===b.text,'Unrelated node changed '+L.value(b.text,'nodeID'));
fs.writeFileSync(out+'/unified.vmap',result);
fs.writeFileSync(out+'/manifest.json',JSON.stringify({sourceSHA256:sha(fs.readFileSync(out+'/before.vmap')),defs,markers,removed,newNodes,resources:[...resources],preservedNodes:keep.length,changedNavCells:nav.filter((v,i)=>v!==navBefore[i]).length},null,2));
console.log(JSON.stringify({rooms:defs.length,removed:removed.length,preserved:keep.length,added:additions.length,output:out+'/unified.vmap'}));
