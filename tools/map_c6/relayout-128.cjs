// Move completed units from a saved current-map snapshot. Never regenerate art.
'use strict';
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const L=require('./lib.cjs');
const ROOT=path.resolve(__dirname,'../..'),OUT=path.join(ROOT,'output/map_layout_128_20260920');
const source=fs.readFileSync(path.join(OUT,'template_before_text.vmap'),'utf8');
const previous=JSON.parse(fs.readFileSync(path.join(ROOT,'output/map_arena_integration_20260919/integration_manifest.json')));
const assert=(v,m)=>{if(!v)throw Error(m)},vec=s=>s.split(/\s+/).map(Number),fmt=p=>p.map(n=>Math.round(n*1e6)/1e6).join(' ');
const inside=(x,y,b)=>x>=b[0]&&x<=b[2]&&y>=b[1]&&y<=b[3];
const entities=L.blocks(source,'CMapEntity'),meshes=L.blocks(source,'CMapMesh');
const byNode=new Map([...entities,...meshes].map(b=>[+L.value(b.text,'nodeID'),b]));
let nextNode=Math.max(...[...source.matchAll(/"nodeID" "int" "(\d+)"/g)].map(m=>+m[1]))+1;
const guid=()=>crypto.randomUUID();
const reidentify=t=>t.replace(/"elementid" "[^"]+"/g,()=>`"elementid" "${guid()}"`).replace(/"nodeID" "int" "\d+"/g,()=>`"nodeID" "int" "${nextNode++}"`).replace(/"referenceID" "uint64" "[^"]+"/g,'"referenceID" "uint64" "0x0"');
function shift(t,d,mesh=false){
 if(mesh)return t.replace(/("name" "string" "position:0"[\s\S]*?"data" "vector3_array"\s*)\[([^\]]*)\]/,(_,h,b)=>h+'['+[...b.matchAll(/"([^"\r\n]*)"/g)].map(m=>'"'+fmt(vec(m[1]).map((n,i)=>n+(d[i]||0)))+'"').join(',')+']');
 return L.setValue(t,'origin',fmt(vec(L.value(t,'origin')).map((n,i)=>n+(d[i]||0))));
}
const destinations={training_01:[-6144,11904],training_02:[-4096,11904],training_03:[2048,11904],training_04:[4096,11904],training_07:[-4096,-4224],training_08:[2048,-4224]};
for(let n=1;n<=10;n++){
 const k=String(n).padStart(2,'0');
 destinations['rebirth_'+k]=n===10?[-12800,4096]:[-8192,11776-(n-1)*2048];
 destinations['ten_realm_'+k]=n===10?[12544,6144]:[8192,11776-(n-1)*2048];
}
const areas=previous.areas.map(a=>({...a,oldOrigin:a.origin.slice(),origin:[...destinations[a.id],a.origin[2]],delta:[destinations[a.id][0]-a.origin[0],destinations[a.id][1]-a.origin[1],0]}));
const playerPositions=[[-12800,11904],[12800,11904],[-12800,-11904],[12800,-11904]];
const editByNode=new Map(),insertions=[],newMarkers=[],patches=[];
function marker(name,p){
 const node=nextNode++;newMarkers.push({name,origin:p,nodeID:node});
 insertions.push(`"CMapEntity" { "id" "elementid" "${guid()}" "nodeID" "int" "${node}" "children" "element_array" [] "entity_properties" "EditGameClassProps" { "id" "elementid" "${guid()}" "classname" "string" "info_target" "targetname" "string" "${name}" } "origin" "vector3" "${fmt(p)}" "angles" "qangle" "0 0 0" "scales" "vector3" "1 1 1" "force_hidden" "bool" "0" "editorOnly" "bool" "0" }`);
}
for(const a of areas){
 for(const item of [...a.placements,...a.markers,...a.supports]){
  const b=byNode.get(item.nodeID);assert(b,'Missing original node '+item.nodeID);
  editByNode.set(item.nodeID,shift(b.text,a.delta,a.supports.includes(item)));
 }
 patches.push({id:a.id,box:a.terrainBox,delta:a.delta});
 a.worldBounds=a.worldBounds.map(p=>p.map((n,i)=>n+a.delta[i]));
 a.markers=a.markers.map(m=>({...m,origin:m.origin.map((n,i)=>n+a.delta[i])}));
}
// Identical room sizes and collision for all four players; cosmetics retained.
for(let p=0;p<4;p++){
 const donor=previous.areas.find(a=>a.id==='training_01'),dest=playerPositions[p],d=[dest[0]-donor.origin[0],dest[1]-donor.origin[1],0];
 const id='player_'+p+'_training';
 for(const item of [...donor.placements,...donor.supports]){
  let t=reidentify(shift(byNode.get(item.nodeID).text,d,donor.supports.includes(item)));
  if(item.targetname)t=L.setValue(t,'targetname',item.targetname.replace('arena_integration_training_01','layout128_'+id));
  insertions.push(t);
 }
 patches.push({id,box:donor.terrainBox,delta:d});
 const a={id,kind:'player_training',player_id:p,origin:[...dest,128],worldBounds:donor.worldBounds.map(q=>q.map((n,i)=>n+d[i])),markers:[]};
 for(const [suffix,x,y] of [['hero_spawn',-192,0],['training_entry',-192,0],['training_home',-192,0],['training_target',192,0]]){
  const m={name:'player_'+p+'_'+suffix,origin:[dest[0]+x,dest[1]+y,152]};marker(m.name,m.origin);a.markers.push(m);
 }
 areas.push(a);
}
// These are the remaining native islands, including all native paint and foliage.
const legacy=[
 {id:'challenge_06',box:[-7680,1280,-5376,3328],delta:[18432,-2304,0]},
 {id:'challenge_10',box:[-7680,-1024,-5376,1024],delta:[-6144,-2048,0]},
 {id:'challenge_09',box:[-7680,-3328,-5376,-1280],delta:[18432,-1792,0]},
 {id:'challenge_05',box:[-5120,-5376,-2816,-3328],delta:[-2048,-6912,0]},
 {id:'reserve_native',box:[-5120,-7680,-2816,-5632],delta:[4096,-4608,0]}
];
patches.push(...legacy,{id:'central',box:[-4608,-3072,2560,3072],delta:[0,4096,0]});
for(const b of entities){
 const n=+L.value(b.text,'nodeID');if(editByNode.has(n))continue;
 const cls=L.value(b.text,'classname'),p=vec(L.value(b.text,'origin')||'0 0 0');
 if(!/^(prop_|ent_dota_tree|info_target|info_player_start|info_courier_spawn)/.test(cls))continue;
 const a=legacy.find(a=>inside(p[0],p[1],a.box));
 editByNode.set(n,shift(b.text,a?a.delta:[0,4096,0]));
}
for(const b of meshes){
 const n=+L.value(b.text,'nodeID');if(editByNode.has(n))continue;
 if(n===4675){
  // The original sea-bed quad spans the old bounds; extend its XY only.
  editByNode.set(n,b.text.replace(/("name" "string" "position:0"[\s\S]*?"data" "vector3_array"\s*)\[([^\]]*)\]/,(_,h,t)=>h+'['+[...t.matchAll(/"([^"\r\n]*)"/g)].map(m=>'"'+fmt(vec(m[1]).map((v,i)=>i<2?v*2:v))+'"').join(',')+']'));
 }else editByNode.set(n,shift(b.text,[0,4096,0],true));
}
// Expand native terrain, transplanting whole patches, never resampling paint.
const grid=L.blocks(source,'CMapDotaTileGrid')[0],g=L.blocks(grid.text,'CDmeDotaTileGrid')[0];
assert(L.value(g.text,'gridWidth')==='64','Expected current 64-grid snapshot');
const old={},types={};
for(const m of g.text.matchAll(/"(\w+)" "(int|uint8|bool|color|string)_array"\s*\[([^\]]*)\]/g)){
 const a=[...m[3].matchAll(/"([^"\r\n]*)"/g)].map(m=>m[1]);if(a.length>=4096){old[m[1]]=a;types[m[1]]=m[2];}
}
for(const k of ['cellConfiguration','cellConfigurationByName','objectConfiguration','objectConfigurationByName'])old[k]=L.records(old[k]);
const wc=previous.canonical_water_cell;
const cells=['cellsTileSet','cellsHidden','cellsOrientation','cellsMaterialSet','cellsCustomPathType','cellsVariationId'];
const defaults={verticesHeight:'0',verticesWater:'1',edgesPath:'0',edgesDestruction:'0',gridnavFlags:'1',grassOpacity:'0',fogOpacity:'255',blendOpacity:'0 255 0 128',blendColor:'255 255 255 0',blendTransitionAndPath:'0 255 0 0',blendHeight:'128',flowMap:'10 20 0 0',fogFlowMap:'10 20 0 0',objectConfiguration:[],objectConfigurationByName:[]};
for(const k of cells)defaults[k]=old[k][wc];defaults.cellsHidden='0';
for(const k of ['cellConfiguration','cellConfigurationByName'])defaults[k]=old[k][wc];
const arrays={},stats={};
for(const [k,a] of Object.entries(old)){
 let ow,step,offset=0,nw;
 if(k.startsWith('edges')){
  const b=Array(128*129*2).fill('0');
  for(const patch of patches)for(let orient=0;orient<2;orient++)for(let y=0;y<65;y++)for(let x=0;x<64;x++){
   const px=-8192+(orient?y:x+.5)*256,py=-8192+(orient?x+.5:y)*256;
   if(!inside(px,py,patch.box))continue;
   const nx=x+32+patch.delta[orient?1:0]/256,ny=y+32+patch.delta[orient?0:1]/256;
   b[orient*128*129+ny*128+nx]=a[orient*64*65+y*64+x];
  }arrays[k]=b;continue;
 }
 if(a.length===4096){ow=64;step=256;offset=128;nw=128;}
 else if(a.length===4225){ow=65;step=256;nw=129;}
 else if(a.length===66049){ow=257;step=64;nw=513;}
 else if(a.length===65536){ow=256;step=64;offset=32;nw=512;}
 else if(a.length===263169){ow=513;step=32;nw=1025;}
 else throw Error('Unknown native array '+k+' '+a.length);
 const fill=defaults[k]??(k==='objectsVariationId'?'255':'0');
 const b=Array(nw*nw).fill(fill);let copied=0;
 for(const patch of patches){
  const [minX,minY,maxX,maxY]=patch.box;
  for(let y=Math.max(0,Math.ceil((minY+8192-offset)/step));y<ow&&-8192+y*step+offset<=maxY;y++)
   for(let x=Math.max(0,Math.ceil((minX+8192-offset)/step));x<ow&&-8192+x*step+offset<=maxX;x++){
    const nx=x+(8192+patch.delta[0])/step,ny=y+(8192+patch.delta[1])/step;
    assert(Number.isInteger(nx)&&Number.isInteger(ny)&&nx>=0&&ny>=0&&nx<nw&&ny<nw,'Patch off lattice '+patch.id);
    b[ny*nw+nx]=a[y*ow+x];copied++;
   }
 }arrays[k]=b;stats[k]={length:b.length,copied};
}
console.log('Native arrays transplanted');
let updated=g.text.replace(/"(\w+)" "(int|uint8|bool|color|string)_array"\s*\[[^\]]*\]/g,(all,k,type)=>{
 if(!arrays[k])return all;
 const a=/Configuration/.test(k)?arrays[k].flatMap(r=>[String(r.length),...r]):arrays[k];
 return `"${k}" "${type}_array" [`+a.map(v=>'"'+v+'"').join(',')+']';
});
updated=L.setValue(L.setValue(updated,'gridWidth',128),'gridHeight',128);
let terrain=grid.text.slice(0,g.start)+updated+grid.text.slice(g.end);
assert(terrain.includes('"origin" "vector3" "-8192 -8192 128"'),'Expected native grid origin');
terrain=terrain.replace('"origin" "vector3" "-8192 -8192 128"','"origin" "vector3" "-16384 -16384 128"');
const edits=[{...grid,text:terrain},...[...entities,...meshes].filter(b=>editByNode.has(+L.value(b.text,'nodeID'))).map(b=>({...b,text:editByNode.get(+L.value(b.text,'nodeID'))}))];
edits.sort((a,b)=>a.start-b.start);let parts=[],cursor=0;
for(const e of edits){assert(e.start>=cursor,'Nested edits');parts.push(source.slice(cursor,e.start),e.text);cursor=e.end;}
parts.push(source.slice(cursor));let result=parts.join('');
const world=result.indexOf('"world" "CMapWorld"'),cs=result.indexOf('[',result.indexOf('"children" "element_array"',world)),ce=L.endOf(result,cs,'[',']')-1;
result=result.slice(0,ce)+',\n'+insertions.join(',\n')+'\n'+result.slice(ce);
const finalEntities=L.blocks(result,'CMapEntity'),seen=new Set(),markers=[];
for(const b of finalEntities){const name=L.value(b.text,'targetname');if(name){assert(!seen.has(name),'Duplicate target '+name);seen.add(name);}if(L.value(b.text,'classname')==='info_target')markers.push({name,origin:vec(L.value(b.text,'origin'))});}
for(const a of areas){
 assert(a.worldBounds[0].slice(0,2).every(v=>v>-16384)&&a.worldBounds[1].slice(0,2).every(v=>v<16384),'Out of map '+a.id);
 for(const b of areas){if(a.id>=b.id)continue;assert([0,1].some(k=>a.worldBounds[1][k]<b.worldBounds[0][k]||b.worldBounds[1][k]<a.worldBounds[0][k]),'Overlapping units '+a.id+' '+b.id);}
 for(const m of a.markers){const [x,y]=m.origin,i=Math.floor((y+16384)/64)*512+Math.floor((x+16384)/64);assert(arrays.gridnavFlags[i]==='0','Blocked marker '+m.name);}
}
fs.writeFileSync(path.join(OUT,'template_layout128.vmap'),result);
const manifest={map:'template_map',grid:{tiles:128,unitsPerTile:256,bounds:[-16384,16384]},centralDelta:[0,4096,0],areas:areas.map(({placements,supports,...a})=>a),patches,markers,stats,checks:{uniqueNames:true,unitBounds:true,noUnitOverlap:true,entryGridNav:true,compiled:false,runtime:false},before_sha256:crypto.createHash('sha256').update(source).digest('hex')};
fs.writeFileSync(path.join(OUT,'layout_manifest.json'),JSON.stringify(manifest,null,2));
console.log(JSON.stringify({entities:finalEntities.length,areas:areas.length,markers:markers.length,output:path.join(OUT,'template_layout128.vmap')}));
