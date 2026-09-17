// Standalone, deterministic Hammer VMAP terrain generator. No existing map is edited.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const OUT = path.resolve(__dirname, '../output/zombie_island_v1');
fs.mkdirSync(OUT, { recursive: true });
let uid = 0, node = 10;
function id() { const h=crypto.createHash('md5').update('zombie-abyss-v1-'+uid++).digest('hex'); return `${h.slice(0,8)}-${h.slice(8,12)}-${h.slice(12,16)}-${h.slice(16,20)}-${h.slice(20)}`; }
const q=v=>'"'+String(v).replaceAll('\\','/').replaceAll('"','\\"')+'"';
const val=(k,t,v)=>`${q(k)} ${q(t)} ${q(v)}\n`;
const arr=(k,t,a)=>`${q(k)} ${q(t+'_array')}\n[${a.map(v=>q(Array.isArray(v)?v.join(' '):v)).join(',\n')}]\n`;
const el=(k,t,s)=>`${q(k)} ${q(t)}\n{${val('id','elementid',id())}${s}}\n`;
const raw=(t,s)=>`${q(t)}\n{${val('id','elementid',id())}${s}}\n`;
const ea=(k,a)=>`${q(k)} "element_array"\n[${a.join(',\n')}]\n`;
const M={rock:'materials/blends/rockwalls_dire.vmat',grass:'materials/blends/mod_radiant_000.vmat',dirt:'materials/blends/dirt_path001.vmat',stone:'materials/blends/mod_radiant_path_000.vmat',snow:'materials/blends/mod_radiant_snow_default_001.vmat',water:'materials/water/water_econ_dota_blue.vmat',black:'materials/dev/black.vmat',clip:'materials/tools/toolsclip.vmat'};
// Minimap pixels -> Source world coordinates; retain the reference's wide aspect ratio.
const SCALE=64, X=p=>(p-170)*SCALE, Y=p=>(95-p)*SCALE;
const children=[],land=[],waters=[],rooms=[];
function normal(a,b,c){const u=b.map((x,i)=>x-a[i]),v=c.map((x,i)=>x-a[i]);const n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]],l=Math.hypot(...n)||1;return n.map(x=>x/l);}
function stream(name,type,data,flags=0){return raw('CDmePolygonMeshDataStream',val('name','string',name+':0')+val('standardAttributeName','string',name)+val('semanticName','string',name)+val('semanticIndex','int',0)+val('vertexBufferLocation','int',0)+val('dataStateFlags','int',flags)+val('subdivisionBinding','element','')+arr('data',type,data));}
function data(k,n,streams){return el(k,'CDmePolygonMeshDataArray',val('size','int',n)+ea('streams',streams));}
function mesh(verts,faces,materials,tint='255 255 255 255',physics='default'){
  const edges=[],edgeMap=new Map(),faceStart=[],vertStart=verts.map(()=>-1),mat=[],normals=[];
  faces.forEach(({v,m=0},fi)=>{const start=edges.length;faceStart.push(start);mat.push(m);normals.push(normal(verts[v[0]],verts[v[1]],verts[v[2]]));v.forEach((a,j)=>{const b=v[(j+1)%v.length],i=edges.length;edges.push({a,b,face:fi,next:start+(j+1)%v.length});edgeMap.set(a+','+b,i);vertStart[a]=i;});});
  const opposite=edges.map(e=>edgeMap.get(e.b+','+e.a));
  if(opposite.some(x=>x===undefined))throw Error('Non-manifold mesh');
  let ec=0;const ed=edges.map(()=>-1);edges.forEach((e,i)=>{if(ed[i]<0)ed[i]=ed[opposite[i]]=ec++;});
  const uv=edges.map(e=>{const p=verts[e.b],n=normals[e.face];return Math.abs(n[2])>.5?[p[0]/256,-p[1]/256]:Math.abs(n[0])>.5?[p[1]/256,-p[2]/256]:[p[0]/256,-p[2]/256];});
  const seq=n=>Array.from({length:n},(_,i)=>i);
  let d=val('name','string','meshData');
  for(const [k,a] of Object.entries({vertexEdgeIndices:vertStart,vertexDataIndices:seq(verts.length),edgeVertexIndices:edges.map(e=>e.b),edgeOppositeIndices:opposite,edgeNextIndices:edges.map(e=>e.next),edgeFaceIndices:edges.map(e=>e.face),edgeDataIndices:ed,edgeVertexDataIndices:seq(edges.length),faceEdgeIndices:faceStart,faceDataIndices:seq(faces.length)}))d+=arr(k,'int',a);
  d+=arr('materials','string',materials);
  d+=data('vertexData',verts.length,[stream('position','vector3',verts,3)]);
  d+=data('faceVertexData',edges.length,[stream('texcoord','vector2',uv,3),stream('normal','vector3',edges.map(e=>normals[e.face]),1),stream('tangent','vector4',edges.map(()=>[1,0,0,-1]),1)]);
  d+=data('edgeData',ec,[stream('flags','int',Array(ec).fill(0),3)]);
  d+=data('faceData',faces.length,[stream('textureScale','vector2',faces.map(()=>[1,1])),stream('textureAxisU','vector4',faces.map(()=>[1,0,0,0])),stream('textureAxisV','vector4',faces.map(()=>[0,-1,0,0])),stream('materialindex','int',mat,8),stream('flags','int',faces.map(()=>0),3),stream('lightmapScaleBias','int',faces.map(()=>0),1)]);
  d+=el('subdivisionData','CDmePolygonMeshSubdivisionData',arr('subdivisionLevels','int',edges.map(()=>0))+ea('streams',[]));
  children.push(raw('CMapMesh',val('nodeID','int',node++)+val('referenceID','uint64','0x0')+val('origin','vector3','0 0 0')+val('angles','qangle','0 0 0')+val('scales','vector3','1 1 1')+ea('children',[])+val('editorOnly','bool',0)+val('force_hidden','bool',0)+val('tintColor','color',tint)+val('renderAmt','int',255)+val('physicsType','string',physics)+val('smoothingAngle','float',35)+el('meshData','CDmePolygonMesh',d)));
}
function polygon(points){let p=points.map(([x,y])=>[X(x),Y(y)]);let area=p.reduce((a,v,i)=>a+v[0]*p[(i+1)%p.length][1]-p[(i+1)%p.length][0]*v[1],0);return area<0?p.reverse():p;}
function rect(x1,y1,x2,y2,bevel=1){return polygon([[x1+bevel,y1],[x2-bevel,y1],[x2,y1+bevel],[x2,y2-bevel],[x2-bevel,y2],[x1+bevel,y2],[x1,y2-bevel],[x1,y1+bevel]]);}
function ellipse(cx,cy,rx,ry,n=40){return polygon(Array.from({length:n},(_,i)=>[cx+rx*Math.cos(i/n*Math.PI*2),cy+ry*Math.sin(i/n*Math.PI*2)]));}
function prism(p,z,bottom,top,side=M.rock,tint='170 175 180 255'){
  const n=p.length,v=p.map(([x,y])=>[x,y,bottom]).concat(p.map(([x,y])=>[x,y,z]));
  const f=[{v:Array.from({length:n},(_,i)=>n-1-i),m:1},{v:Array.from({length:n},(_,i)=>n+i),m:0}];
  for(let i=0;i<n;i++)f.push({v:[i,(i+1)%n,n+(i+1)%n,n+i],m:1});mesh(v,f,[top,side],tint);
}
function platform(name,p,z=384,material=M.dirt,room=false){
  land.push({name,polygon:p,z,room});if(room)rooms.push(name);
  // Inset top and faceted sloping shoulder soften the edge while retaining flat fighting ground.
  const c=p.reduce((a,v)=>[a[0]+v[0]/p.length,a[1]+v[1]/p.length],[0,0]);
  const n=p.length,v=[];for(const [height,scale] of [[-1536,1.02],[z-92,1],[z,.96]])for(const [x,y] of p)v.push([c[0]+(x-c[0])*scale,c[1]+(y-c[1])*scale,height]);
  const f=[{v:Array.from({length:n},(_,i)=>n-1-i),m:1},{v:Array.from({length:n},(_,i)=>2*n+i),m:0}];
  for(let r=0;r<2;r++)for(let i=0;i<n;i++)f.push({v:[r*n+i,r*n+(i+1)%n,(r+1)*n+(i+1)%n,(r+1)*n+i],m:r?2:1});
  mesh(v,f,[material,M.rock,M.dirt],material===M.snow?'195 207 215 255':'177 185 172 255');
  entity('info_target',name,[c[0],c[1],z+24]);
}
function entity(cls,name,origin,props={},angles='0 0 0',scale=1){children.push(raw('CMapEntity',val('nodeID','int',node++)+val('referenceID','uint64','0x0')+ea('children',[])+el('entity_properties','EditGameClassProps',Object.entries({classname:cls,targetname:name,...props}).map(([k,v])=>val(k,'string',v)).join(''))+val('origin','vector3',origin.join(' '))+val('angles','qangle',angles)+val('scales','vector3',`${scale} ${scale} ${scale}`)+val('editorOnly','bool',0)+val('force_hidden','bool',0)));}
function water(name,x1,y1,x2,y2){const p=rect(x1,y1,x2,y2,.5);waters.push({name,polygon:p,z:128});prism(p,-160,-1536,M.rock);prism(p,128,112,M.water,M.rock,'255 255 255 255');}
water('central_sea',105,30,218,121);water('western_channel',64,23,99,137);water('northeast_pool',222,25,256,73);water('eastern_sea',260,101,338,142);water('southwest_sea',66,155,151,189);
platform('central_island',ellipse(158,81,29,24),384,M.grass);
platform('western_upper',rect(2,38,60,72,2),512);
platform('western_circle',ellipse(27,97,18,13,24),384,M.grass);
platform('western_lower',rect(2,119,60,188,2),384);
platform('northeast_plateau',rect(263,4,337,77,2),640,M.snow);
for(let i=0;i<4;i++)platform('northeast_terrace_'+(i+1),rect(264,8+i*17,286,18+i*17,.6),768,M.grass);
platform('east_annex',rect(223,80,255,121,1),384,M.stone);
platform('northeast_islet',ellipse(238,50,7,5,16),320,M.grass);
platform('eastern_islet',rect(281,121,293,135,1),384,M.stone);
platform('eastern_coast',rect(311,115,338,138,1),512,M.grass);
platform('southwest_cross',polygon([[108,156],[116,165],[140,172],[117,178],[108,188],[99,178],[76,172],[99,165]]),384,M.stone);
let ri=0;for(const y of [5,132])for(const x of [71,89,107,125,176,195,214,233])platform('training_'+String(++ri).padStart(2,'0'),rect(x,y,x+13,y+10,.8),384,M.stone,true);
for(const y of [155,179])for(const x of [162,197,232,276,319])platform('training_'+String(++ri).padStart(2,'0'),rect(x,y,x+12,y+10,.8),y===179?256:384,M.stone,true);
// Sparse props on large landforms only. Training room interiors deliberately stay empty.
const trees=[[143,68],[178,84],[148,94],[167,64],[15,47],[45,59],[22,142],[46,171],[321,17],[331,65]];
trees.forEach(([x,y],i)=>{const z=x>260?640:(y<73&&x<60?512:384);entity('prop_static','island_tree_'+i,[X(x),Y(y),z],{model:'models/props_foliage/tree_pine01.vmdl',solid:'0'},`0 ${i*47%360} 0`,.75);});
for(let i=0;i<land.length;i++){const a=land[i];if(a.name.startsWith('northeast_terrace'))continue;const p=a.polygon[0];entity('prop_static','edge_rock_'+i,[p[0]+48,p[1]+48,a.z-25],{model:'models/props_debris/rock_debris001.vmdl',solid:'0'},`0 ${i*31%360} 0`,a.room?.45:.8);}
// Clip all non-land at 64-unit resolution; greedy merge spans to keep brush count low.
function inside(x,y,p){let c=false;for(let i=0,j=p.length-1;i<p.length;j=i++){const a=p[i],b=p[j];if(((a[1]>y)!=(b[1]>y))&&x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0])c=!c;}return c;}
const isLand=(x,y)=>land.some(a=>inside(x,y,a.polygon));
let active=new Map(),clips=[];
for(let iy=0;iy<192;iy++){const spans=[];let start=-1;for(let ix=0;ix<=340;ix++){const blocked=ix<340&&!isLand(X(ix+.5),Y(iy+.5));if(blocked&&start<0)start=ix;if(!blocked&&start>=0){spans.push([start,ix]);start=-1;}}const next=new Map();for(const [a,b] of spans){const k=a+','+b,r=active.get(k)||[a,iy,b,iy];r[3]=iy+1;next.set(k,r);}for(const [k,r]of active)if(!next.has(k))clips.push(r);active=next;}clips.push(...active.values());
for(const [a,b,c,d]of clips)prism(polygon([[a,b],[c,b],[c,d],[a,d]]),1400,-1600,M.clip,M.clip,'255 255 255 255');
// Dark distant floor gives abyss depth. Control clips above prevent traversing it.
prism(rect(0,0,340,192,.1),-1600,-1664,M.black,M.black,'255 255 255 255');
entity('world_bounds','abyss_world_bounds',[0,0,0],{min:`${X(0)} ${Y(192)} 0`,max:`${X(340)} ${Y(0)} 0`});
entity('info_player_start_goodguys','abyss_player_start',[X(158),Y(81),420]);
entity('info_player_start','abyss_editor_start',[X(158),Y(81),420]);
entity('info_player_start_badguys','abyss_bad_start',[X(29),Y(55),548]);
for(let i=0;i<4;i++)entity('info_target',`player_${i}_builder_spawn`,[X(153+i*3),Y(82),420]);
entity('ent_dota_game_events','abyss_game_events',[0,0,0]);
entity('water_lod_control','abyss_water_lod',[0,0,0],{cheapwaterstartdistance:'30000',cheapwaterenddistance:'40000'});
entity('env_global_light','abyss_light',[0,0,2400],{color:'170 191 218 255',lightscale:'2.2',ambientcolor1:'93 122 163 255',ambientscale1:'1.8',ambientcolor2:'100 115 128 255',ambientscale2:'.6',ambientcolor3:'60 69 83 255',groundscale:'.5',specularcolor:'80 145 200 255',specularpower:'12',enableshadows:'1',StartDisabled:'0',fow_darkness:'1.2'},'55 315 0');
entity('env_fog_controller','abyss_fog',[0,0,-1000],{fogenable:'1',fogcolor:'10 15 23',fogstart:'16000',fogend:'32000',fogmaxdensity:'.65',spawnflags:'1'});
entity('env_tonemap_controller','abyss_tonemap',[0,0,0],{UseCustomAutoExposureMin:'1',UseCustomAutoExposureMax:'1',AutoExposureMin:'.65',AutoExposureMax:'.85'});
const world=el('world','CMapWorld',val('nodeID','int',1)+val('referenceID','uint64','0x0')+ea('children',children)+el('entity_properties','EditGameClassProps',val('classname','string','worldspawn')+val('skyname','string','sky_day01_01'))+val('origin','vector3','0 0 0')+val('angles','qangle','0 0 0')+val('scales','vector3','1 1 1'));
const root=raw('CMapRootElement',val('isprefab','bool',0)+val('editorbuild','int',10871)+val('editorversion','int',400)+el('defaultcamera','CStoredCamera',val('position','vector3','0 -10500 17000')+val('lookat','vector3','0 0 0'))+world);
// Keep all editor bookkeeping from a current Hammer template. Minimal roots can crash RC.
let template=fs.readFileSync(path.join(OUT,'source_template.vmap'),'utf8');
template=template.slice(template.indexOf('"CMapRootElement"'));
function closing(s,start,open,close){let depth=0,quoted=false;for(let i=start;i<s.length;i++){if(s[i]==='"'&&s[i-1]!=='\\')quoted=!quoted;if(!quoted){if(s[i]===open)depth++;if(s[i]===close&&--depth===0)return i;}}throw Error('Unbalanced template');}
const wa=template.indexOf('"world" "CMapWorld"'),wb=template.indexOf('{',wa),we=closing(template,wb,'{','}');
let w=template.slice(wa,we+1),ca=w.indexOf('"children" "element_array"'),cb=w.indexOf('[',ca),ce=closing(w,cb,'[',']');
// A hidden native tile grid supplies flow/fog textures and painted navigation metadata.
let grid=w.slice(cb+1,ce).trim();
grid=grid.replace('"-8192 -8192 128"','"-12288 -8192 0"').replace('"gridWidth" "int" "64"','"gridWidth" "int" "96"');
const counts={4096:96*64,4225:97*65,8320:96*65+97*64,66049:385*257,65536:384*256,263169:769*513};
grid=grid.replace(/^(\t{6})"([^"]+)" "(\w+)_array"\s*\[([^\]]*)\]/gm,(all,indent,k,t,body)=>{
 if(t==='element')return all;
 const values=[...body.matchAll(/"([^"]*)"/g)].map(m=>m[1]);
 if(/^(cell|object)Configuration/.test(k))return indent+arr(k,t,[]);
 const count=counts[values.length];if(!count)return all;
 let fill=values[0]||'0';
 if(k==='cellsHidden')fill='1';
 else if(k==='verticesHeight'||k==='verticesWater'||k==='edgesPath'||k==='edgesDestruction'||k.startsWith('objects'))fill=k==='objectsVariationId'?'255':'0';
 else if(k==='blendOpacity')fill='0 255 0 128';
 else if(k==='blendColor')fill='255 255 255 0';
 else if(k==='grassOpacity'||k==='fogOpacity')fill='0';
 else if(k==='flowMap'||k==='fogFlowMap')fill='128 128 0 0';
 const a=Array(count).fill(fill);
 if(k==='gridnavFlags')for(let y=0;y<256;y++)for(let x=0;x<384;x++)a[y*384+x]=isLand(-12288+x*64+32,-8192+y*64+32)?'0':'1';
 return indent+arr(k,t,a);
});
w=w.slice(0,cb+1)+grid+',\n'+children.join(',\n')+w.slice(ce);
template=template.slice(0,wa)+w+template.slice(we+1);
fs.writeFileSync(path.join(OUT,'zombie_abyss_v1.vmap'),'<!-- dmx encoding keyvalues2 4 format vmap 40 -->\n'+template);
const report={map:'zombie_abyss_v1',scale:SCALE,bounds:[X(0),Y(192),X(340),Y(0)],rooms:rooms.length,clipBrushes:clips.length,land,waters,entities:node-10};
fs.writeFileSync(path.join(OUT,'layout.json'),JSON.stringify(report,null,2));
console.log(JSON.stringify({map:report.map,trainingRooms:rooms.length,clipBrushes:clips.length,nodes:node-10,source:path.join(OUT,'zombie_abyss_v1.vmap')}));
