// Independent checks against actual VMAP blocks, model bounds and VPK payloads.
// Never imports/runs the integrator, alters the map, or installs resources.
'use strict';
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const ROOT = path.resolve(__dirname, '../..');
const DEFAULT_OUT = path.join(ROOT, 'output/map_arena_integration_20260919');
const BASELINE = path.join(ROOT, 'output/merge_resolution_20260919/room_inventory/template_map_text.vmap');
const sha = text => crypto.createHash('sha256').update(text).digest('hex');
const fail = (ok, ...why) => { if (!ok) throw Error(why.map(v => typeof v === 'string' ? v : JSON.stringify(v)).join(' ')); };
function withTemporaryDirectory(callback){
  const parent=fs.realpathSync(require('os').tmpdir());
  const directory=fs.mkdtempSync(path.join(parent,'survival-arena-verify-'));
  try{return callback(directory);}finally{
    // Only our fresh, flat temporary directory; never recursively delete a path.
    fail(path.dirname(directory)===parent,'Unexpected temporary directory parent');
    for(const entry of fs.readdirSync(directory,{withFileTypes:true})){
      fail(entry.isFile(),'Unexpected nested temporary entry',entry.name);
      fs.unlinkSync(path.join(directory,entry.name));
    }
    fs.rmdirSync(directory);
  }
}
const finite = a => Array.isArray(a) && a.every(Number.isFinite);
const close = (a,b,e=.08) => Array.isArray(a) && Array.isArray(b) && a.length===b.length && a.every((v,i)=>Array.isArray(v)?close(v,b[i],e):Math.abs(v-b[i])<=e);
function endOf(text, start, left='{', right='}') {
  let depth=0, quoted=false, escaped=false;
  for(let i=start;i<text.length;i++) {
    const c=text[i];
    if(quoted){if(escaped)escaped=false;else if(c==='\\')escaped=true;else if(c==='"')quoted=false;continue;}
    if(c==='"')quoted=true;else if(c===left)depth++;else if(c===right && --depth===0)return i+1;
  }
  throw Error('Unbalanced VMAP delimiters');
}
function blocks(text,type) {
  const result=[], re=new RegExp('"'+type+'"\\s*\\{','g'); let m;
  while((m=re.exec(text))){const open=text.indexOf('{',m.index),end=endOf(text,open);result.push({text:text.slice(m.index,end),start:m.index,end});re.lastIndex=end;}
  return result;
}
function value(text,key) {
  const escaped=key.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
  return text.match(new RegExp('"'+escaped+'"\\s+"(?:string|int|uint64|elementid|float|bool|vector3|qangle)"\\s+"([^"\\r\\n]*)"'))?.[1];
}
function vector(raw, fallback=[0,0,0]) {const a=raw===undefined?fallback:String(raw).trim().split(/\s+/).map(Number);fail(finite(a)&&a.length===3,'Invalid vector',raw);return a;}
function blockIdentity(b) {return value(b.text,'id');}
function entity(b) {
  const properties=blocks(b.text,'EditGameClassProps')[0]?.text||b.text;
  return {...b,guid:blockIdentity(b),nodeID:value(b.text,'nodeID'),classname:value(properties,'classname'),
    name:value(properties,'targetname')||'',model:value(properties,'model'),origin:vector(value(b.text,'origin')),
    angles:vector(value(b.text,'angles')),scales:vector(value(b.text,'scales'),[1,1,1])};
}
function primitiveArrays(text) {
  const re=/"([^"\r\n]+)"\s+"(\w+)_array"\s*\[/g, result=[];let m;
  while((m=re.exec(text))) {
    if(m[2]==='element')continue;
    const open=text.indexOf('[',m.index),end=endOf(text,open,'[',']');
    const values=[...text.slice(open+1,end-1).matchAll(/"([^"\r\n]*)"/g)].map(v=>v[1]);
    result.push({key:m[1],type:m[2],start:m.index,end,values});re.lastIndex=end;
  }
  return result;
}
function union(boxes) {fail(boxes.length,'Empty spatial union');return [0,1].map(side=>[0,1,2].map(axis=>Math[side?'max':'min'](...boxes.map(b=>b[side][axis]))));}
function transformedBounds(bounds,origin,angles,scales) {
  fail(Array.isArray(bounds)&&bounds.length===2&&bounds.every(v=>finite(v)&&v.length===3),'Bad source bounds');
  const [pitch,yaw,roll]=angles.map(n=>n*Math.PI/180),c=Math.cos,s=Math.sin,points=[];
  for(const x of [0,1])for(const y of [0,1])for(const z of [0,1]) {
    let p=[bounds[x][0]*scales[0],bounds[y][1]*scales[1],bounds[z][2]*scales[2]];
    p=[p[0],c(roll)*p[1]-s(roll)*p[2],s(roll)*p[1]+c(roll)*p[2]];
    p=[c(pitch)*p[0]+s(pitch)*p[2],p[1],-s(pitch)*p[0]+c(pitch)*p[2]];
    p=[c(yaw)*p[0]-s(yaw)*p[1],s(yaw)*p[0]+c(yaw)*p[1],p[2]];
    points.push(p.map((n,i)=>n+origin[i]));
  }
  return [0,1].map(side=>[0,1,2].map(axis=>Math[side?'max':'min'](...points.map(p=>p[axis]))));
}
function overlaps(a,b,epsilon=.05) {return [0,1].every(i=>a[0][i]<b[1][i]-epsilon && b[0][i]<a[1][i]-epsilon);}
function insideBox(x,y,b,margin=0) {return x>=b[0]-margin&&y>=b[1]-margin&&x<=b[2]+margin&&y<=b[3]+margin;}
function targetMarker(name) {
  return /^(challenge_(?:01|02|03|04|07|08)_(?:entry|home|boss_spawn|spawn_\d{2})|rebirth_(?:0[1-9]|10)_\w+|rebirth_010_boss_spawn|challenge_11_stage_(?:0[1-9]|10)_(?:entry|spawn))$/.test(name);
}
function preserve(before,after,manifest) {
  const oldEntities=blocks(before,'CMapEntity').map(entity),newEntities=blocks(after,'CMapEntity').map(entity);
  const entityMap=new Map();for(const e of newEntities){fail(e.guid&&!entityMap.has(e.guid),'Duplicate/missing entity GUID',e.guid);entityMap.set(e.guid,e);}
  const kept=oldEntities.filter(e=>!targetMarker(e.name));
  for(const e of kept){const n=entityMap.get(e.guid);fail(n,'Original entity removed',e.nodeID,e.name);fail(n.text===e.text,'Original entity bytes changed',e.nodeID,e.name);}
  const keptGuids=new Set(kept.map(e=>e.guid));
  const addedNodes=new Set(manifest.areas.flatMap(a=>[...a.placements,...a.markers].map(e=>String(e.nodeID))));
  for(const e of newEntities)if(!keptGuids.has(e.guid))fail(addedNodes.has(String(e.nodeID)),'Unaccounted added entity',e.nodeID,e.name);
  const oldMeshes=blocks(before,'CMapMesh'),newMeshes=blocks(after,'CMapMesh');
  fail(oldMeshes.length===5,'Baseline must have exactly five authored meshes',oldMeshes.length);
  const newByID=new Map(newMeshes.map(m=>[blockIdentity(m),m]));
  fail(newByID.size===newMeshes.length,'Duplicate mesh GUID');
  for(const m of oldMeshes)fail(newByID.get(blockIdentity(m))?.text===m.text,'Original mesh bytes changed',value(m.text,'nodeID'));
  const supportNodes=new Set(manifest.areas.flatMap(a=>(a.supports||[]).map(s=>String(s.nodeID))));
  const oldMeshGuids=new Set(oldMeshes.map(blockIdentity));
  for(const m of newMeshes)if(!oldMeshGuids.has(blockIdentity(m)))fail(supportNodes.has(value(m.text,'nodeID')),'Unaccounted added mesh',value(m.text,'nodeID'));
  const nodeIDs=[...newEntities.map(e=>e.nodeID),...newMeshes.map(m=>value(m.text,'nodeID'))];
  fail(new Set(nodeIDs).size===nodeIDs.length,'Duplicate mesh/entity nodeID');
  const declared=manifest.preservation?.retainedEntities;
  if(declared){fail(declared.length===kept.length,'Preservation manifest omitted entities');for(const e of kept){const d=declared.find(d=>String(d.guid??d[0])===e.guid);fail(d,'Preservation entry missing',e.guid);if(d.sha256)fail(d.sha256===sha(e.text),'Preservation digest mismatch',e.guid);}}
  return {entity_blocks_unchanged:kept.length,original_entities:oldEntities.length,replaced_target_markers:oldEntities.length-kept.length,
    mesh_blocks_unchanged:5,meshes:oldMeshes.map(m=>({nodeID:value(m.text,'nodeID'),sha256:sha(m.text)})),entities:newEntities,meshesActual:newMeshes};
}
const assetCache=new Map();
function sourceAsset(model) {
  const m=/^models\/([^/]+)\/([^/]+)\.vmdl$/.exec((model||'').replace(/\\/g,'/'));
  if(!m)return null;
  if(!assetCache.has(m[1])){
    const snapshot=JSON.parse(fs.readFileSync(path.join(__dirname,'arena-assets.json'),'utf8'));
    fail(snapshot.schema_version===1,'Unsupported asset bounds snapshot');
    const assets=snapshot.namespaces[m[1]]?.assets||[];
    // When authoring artifacts exist, independently catch a stale checked-in bounds snapshot.
    const authoring=path.join(ROOT,'output',m[1],'asset_manifest.json');
    if(assets.length&&fs.existsSync(authoring))fail(sha(fs.readFileSync(authoring))===snapshot.namespaces[m[1]].source_manifest_sha256,'Asset snapshot stale versus authoring manifest',m[1]);
    assetCache.set(m[1],assets);
  }
  return assetCache.get(m[1]).find(a=>a.name===m[2])||null;
}
function meshPoints(mesh) {
  const position=blocks(mesh.text,'CDmePolygonMeshDataStream').find(b=>value(b.text,'semanticName')==='position'||value(b.text,'name')==='position:0');
  fail(position,'Missing actual mesh position stream',value(mesh.text,'nodeID'));
  const values=primitiveArrays(position.text).find(a=>a.key==='data')?.values;
  fail(values?.length,'Empty mesh positions');return values.map(v=>vector(v));
}
function nativeBoundsFor(model,native) {
  fail(model==='models/props_foliage/tree_pine01.vmdl','Unreviewed native arena model',model);
  const data=native?.[model];fail(data?.pak_resource&&data?.sha256,'Native bound provenance missing',model);
  const snapshot=JSON.parse(fs.readFileSync(path.join(__dirname,'arena-assets.json'),'utf8')).native[model];
  fail(snapshot?.sha256===data.sha256&&snapshot.pak_resource===data.pak_resource,'Native bounds metadata disagrees with versioned snapshot');
  const source=new (require('./lib.cjs').Vpk)(path.resolve(ROOT,'../../dota/pak01_dir.vpk')).read(data.pak_resource);
  fail(sha(source)===data.sha256,'Native compiled resource changed',model);
  return withTemporaryDirectory(directory=>{
    const extracted=path.join(directory,'tree_pine01.vmdl_c');fs.writeFileSync(extracted,source);
    const tool=path.resolve(ROOT,'../../../game/bin/win64/resourceinfo.exe');
    const result=require('child_process').execFileSync(tool,['-game',path.resolve(ROOT,'../../dota'),'-i',extracted,'-all'],{encoding:'utf8',maxBuffer:8*1024*1024,windowsHide:true});
    const bounds=['m_vMinBounds','m_vMaxBounds'].map(key=>result.match(new RegExp(key+' = \\[ ([^\\]]+) \\]'))?.[1].split(',').map(Number));
    fail(close(bounds,data.bounds,.001),'Native compiled bounds mismatch',model);return bounds;
  });
}
function checkAreas(areas,entities,meshes,native) {
  fail(Array.isArray(areas)&&areas.length===26,'Expected exactly 26 areas');
  const expected=[...'01 02 03 04 07 08'.split(' ').map(n=>'training_'+n),...Array.from({length:10},(_,i)=>'rebirth_'+String(i+1).padStart(2,'0')),...Array.from({length:10},(_,i)=>'ten_realm_'+String(i+1).padStart(2,'0'))];
  fail(new Set(areas.map(a=>a.id)).size===26&&expected.every(id=>areas.some(a=>a.id===id)),'Area identities mismatch');
  const byName=new Map();for(const e of entities){if(!byName.has(e.name))byName.set(e.name,[]);byName.get(e.name).push(e);}
  const byNode=new Map(entities.map(e=>[String(e.nodeID),e])),claimed=new Set(),checks=[],nativeCache=new Map();
  for(const area of areas){
    fail(finite(area.origin)&&area.origin.length===3&&Number.isFinite(area.surfaceZ),'Bad area coordinates',area.id);
    fail(area.placements?.length,'Missing actual prop placement list',area.id);
    const actualBoxes=[];let nativeCount=0;
    for(const p of area.placements){
      const name=p.targetname??p.entity_name??p.entityName??p.name;
      const found=p.nodeID!==undefined?byNode.get(String(p.nodeID)):(byName.get(name)||[]).length===1?byName.get(name)[0]:null;
      fail(found,'Placement entity missing or ambiguous',area.id,name,p.nodeID);fail(!claimed.has(found.guid),'Entity claimed by multiple regions',found.name);claimed.add(found.guid);
      fail(found.classname==='prop_static','Arena placement must be static',found.name,found.classname);
      fail(p.model&&found.model===p.model,'Actual model differs or missing from manifest',found.name);
      if(p.origin)fail(close(found.origin,p.origin,.002),'Actual origin differs',found.name);
      if(p.scales)fail(close(found.scales,p.scales,.0001),'Actual scale differs',found.name);
      if(p.angles)fail(close(found.angles,p.angles,.002),'Actual rotation differs',found.name);
      const asset=sourceAsset(found.model);
      // Native assets must provide a resourceinfo-derived local box, not a world box.
      if(!asset&&!nativeCache.has(found.model))nativeCache.set(found.model,nativeBoundsFor(found.model,native));
      const bounds=asset?.bounds??nativeCache.get(found.model);
      fail(bounds,'No independently sourced model bounds',found.model);
      if(!asset)nativeCount++;
      const box=transformedBounds(bounds,found.origin,found.angles,found.scales);
      if(p.worldBounds)fail(close(box,p.worldBounds,.12),'Placement AABB incorrect',found.name,box,p.worldBounds);
      actualBoxes.push(box);
    }
    for(const support of area.supports||[]){
      const mesh=meshes.find(m=>value(m.text,'nodeID')===String(support.nodeID));
      fail(mesh,'Support mesh missing',area.id,support.nodeID);
      const points=meshPoints(mesh),box=union(points.map(p=>[p,p]));
      fail(sha(mesh.text)===support.sha256&&close(box,support.bounds,.002),'Actual support differs',area.id,support.nodeID);
      if(area.kind==='training')fail(Math.abs(box[0][2]-2)<.01&&Math.abs(box[1][2]-127.25)<.01,'Training support elevation incorrect',area.id);
      actualBoxes.push(box);
    }
    const actual=union(actualBoxes);
    fail(close(actual,area.worldBounds,.15),'Area world bounds differ from actual models',area.id,actual,area.worldBounds);
    fail(actual[0][0]>=-8192&&actual[0][1]>=-8192&&actual[1][0]<=8192&&actual[1][1]<=8192,'Area outside map',area.id,actual);
    const expectedSize=area.kind==='training'?[900,900]:area.kind==='rebirth'?[1000,550]:[700,700];
    fail(close(area.floor_size,expectedSize,.01),'Wrong required arena size',area.id,area.floor_size);
    if(area.kind==='training')fail(area.surfaceZ===128,'Training floor must be 128',area.id);
    else if(area.kind==='rebirth')fail(area.surfaceZ===16+Number(area.id.slice(-2))*14,'Rebirth deck height mismatch',area.id);
    else fail(area.surfaceZ===58,'Realm surface must align water to 16',area.id);
    const markerChecks=[];
    fail(area.markers?.length,'Area markers missing',area.id);
    for(const m of area.markers){
      const matches=byName.get(m.name)||[];fail(matches.length===1,'Marker not unique',m.name,matches.length);
      const e=matches[0];fail(e.classname==='info_target'&&close(e.origin,m.origin,.02),'Marker position/class differs',m.name,e.origin,m.origin);
      fail(Math.abs(e.origin[2]-(area.surfaceZ+24))<.02,'Marker elevation incorrect',m.name,e.origin[2],area.surfaceZ);
      fail(e.origin[0]>=actual[0][0]&&e.origin[0]<=actual[1][0]&&e.origin[1]>=actual[0][1]&&e.origin[1]<=actual[1][1],'Marker outside its region',m.name);
      markerChecks.push({name:m.name,origin:e.origin});
    }
    const prefix=area.kind==='training'?'challenge_'+area.id.slice(-2):area.kind==='rebirth'?area.id:'challenge_11_stage_'+area.id.slice(-2);
    for(const suffix of area.kind==='training'?['entry','home',Number(area.id.slice(-2))<=4?'spawn_01':'boss_spawn']:area.kind==='rebirth'?['entry','boss_spawn']:['entry','spawn'])
      fail(area.markers.some(m=>m.name===prefix+'_'+suffix),'Required gameplay marker missing',area.id,suffix);
    checks.push({id:area.id,kind:area.kind,origin:area.origin,surfaceZ:area.surfaceZ,floor_size:area.floor_size,clear_combat_size:area.clear_combat_size,
      worldBounds:actual,model_entities:area.placements.length,support_meshes:(area.supports||[]).length,native_entities:nativeCount,markers:markerChecks});
  }
  let clearance=Infinity;
  for(let i=0;i<checks.length;i++)for(let j=0;j<i;j++){
    const a=checks[i].worldBounds,b=checks[j].worldBounds;fail(!overlaps(a,b),'Actual complete region bounds overlap',checks[i].id,checks[j].id);
    clearance=Math.min(clearance,Math.hypot(...[0,1].map(k=>Math.max(a[0][k]-b[1][k],b[0][k]-a[1][k],0))));
  }
  // Central mesh extents exclude the deliberately map-wide black seabed.
  const central=meshes.filter(m=>['4676','4677','4678','4679'].includes(value(m.text,'nodeID'))).map(m=>union(meshPoints(m).map(p=>[p,p])));
  for(const a of checks)for(const b of central)fail(!overlaps(a.worldBounds,b),'Region intersects retained central geometry',a.id);
  fail(!byName.has('rebirth_010_boss_spawn'),'Legacy misnamed rank-ten spawn still exists');
  return {areas:checks,min_complete_bounds_clearance:clearance,model_entity_count:claimed.size};
}
function checkGrid(before,after,manifest) {
  const a=blocks(before,'CMapDotaTileGrid'),b=blocks(after,'CMapDotaTileGrid');fail(a.length===1&&b.length===1,'Expected one native grid');
  const aa=primitiveArrays(a[0].text),bb=primitiveArrays(b[0].text);fail(aa.length===bb.length,'Grid primitive array count changed');
  const whitelist=manifest.gridWhitelist||{},patches=manifest.terrainPatches||[];fail(patches.length,'Terrain patch audit missing');
  const allowedNames=new Set(['cellConfiguration','cellConfigurationByName','cellsTileSet','cellsHidden','cellsOrientation','cellsMaterialSet','cellsCustomPathType','cellsVariationId','verticesHeight','verticesWater','edgesPath','edgesDestruction','objectConfiguration','objectConfigurationByName','objectsTileSet','objectsPropType','objectsPlantType','objectsTreeType','objectsTreeSize','objectsRotation','objectsPitch','objectsVariationId','blendOpacity','blendColor','blendTransitionAndPath','gridnavFlags','grassOpacity','fogOpacity','flowMap','fogFlowMap','blendHeight']);
  const central=[-4096,-3072,2048,3072];
  for(const p of patches){
    fail(manifest.areas.some(a=>a.id===p.area)&&finite(p.box)&&p.box.length===4,'Invalid terrain patch',p.area);
    fail(p.box.every(v=>v>=-8192&&v<=8192)&&p.box[0]<p.box[2]&&p.box[1]<p.box[3],'Terrain patch outside map',p.area);
    fail(!overlaps([[p.box[0],p.box[1]],[p.box[2],p.box[3]]],[[central[0],central[1]],[central[2],central[3]]]),'Terrain patch overlaps protected central rectangle',p.area);
  }
  function recordValues(values,key){
    const records=[];let cursor=0;
    while(cursor<values.length){const n=Number(values[cursor++]);fail(Number.isInteger(n)&&n>=0&&cursor+n<=values.length,'Corrupt length-prefixed grid record',key);records.push(values.slice(cursor,cursor+n));cursor+=n;}
    return records;
  }
  function coordinate(key,index){
    let width,step,offset;
    if(key.startsWith('cell'))[width,step,offset]=[64,256,128];
    else if(key.startsWith('vert'))[width,step,offset]=[65,256,0];
    else if(key.startsWith('object'))[width,step,offset]=[257,64,0];
    else if(key==='gridnavFlags')[width,step,offset]=[256,64,32];
    else if(key.startsWith('edges')){
      fail(index<8320,'Edge index out of range');const k=index%4160,x=k%64,y=Math.floor(k/64);
      return index<4160?[-8192+x*256+128,-8192+y*256]:[-8192+y*256,-8192+x*256+128];
    }else [width,step,offset]=[513,32,0];
    fail(index<width*width,'Grid index out of range',key,index);
    return [-8192+(index%width)*step+offset,-8192+Math.floor(index/width)*step+offset];
  }
  const owned=(x,y)=>!insideBox(x,y,central)&&patches.some(p=>insideBox(x,y,p.box));
  const diffs={};let changed=0;
  for(let k=0;k<aa.length;k++){
    const x=aa[k],y=bb[k];fail(x.key===y.key&&x.type===y.type,'Grid array structure changed',x.key,y.key);
    const indices=whitelist[x.key]?.indices||[];fail(!indices.length||allowedNames.has(x.key),'Unapproved terrain field',x.key);
    const allowed=new Set(indices);fail(allowed.size===indices.length&&indices.every(i=>Number.isInteger(i)&&i>=0),'Invalid grid whitelist',x.key);
    for(const index of indices){const [px,py]=coordinate(x.key,index);fail(owned(px,py),'Whitelist includes protected or unrelated terrain',x.key,index,px,py);}
    const records=/^(?:cell|object)Configuration(?:ByName)?$/.test(x.key);
    if(indices.length)fail(whitelist[x.key].index_kind===(records?'decoded_record':'array'),'Incorrect whitelist index semantics',x.key);
    const xv=records?recordValues(x.values,x.key):x.values,yv=records?recordValues(y.values,y.key):y.values;
    fail(xv.length===yv.length,'Grid record/array count changed',x.key,xv.length,yv.length);
    let count=0;
    for(let i=0;i<xv.length;i++)if(records?JSON.stringify(xv[i])!==JSON.stringify(yv[i]):xv[i]!==yv[i]){fail(allowed.has(i),'Grid change outside whitelist',x.key,i);count++;}
    if(count){diffs[x.key]=count;changed+=count;}
  }
  // Strip only approved arrays; other grid bytes (tile mappings, origins, IDs)
  // must remain identical, not merely equivalent parsed values.
  function strip(text,arrays){for(const a of [...arrays].reverse())if(whitelist[a.key])text=text.slice(0,a.start)+'[VERIFIED:'+a.key+']'+text.slice(a.end);return text;}
  fail(strip(a[0].text,aa)===strip(b[0].text,bb),'Non-array grid bytes changed');
  const nav=bb.find(x=>x.key==='gridnavFlags');fail(nav?.values.length===65536,'Expected native 256x256 navigation flags');
  function walkable(area,x,y){
    x-=area.origin[0];y-=area.origin[1];
    if(area.kind==='training'){
      // Source room interior plus recessed rear portal; fixed source dimensions.
      x/=900/2048;y/=900/2304;
      return (Math.abs(x)<968&&y>-1096&&y<1130)||(y>=1090&&y<1350&&Math.hypot(x,y-1152)<200);
    }
    return Math.abs(x)<area.clear_combat_size[0]/2&&Math.abs(y)<area.clear_combat_size[1]/2;
  }
  let ownedNav=0;
  for(let i=0;i<nav.values.length;i++){
    const [x,y]=coordinate('gridnavFlags',i);if(!owned(x,y))continue;
    const open=manifest.areas.some(a=>walkable(a,x,y));fail(nav.values[i]===(open?'0':'1'),'Actual navigation does not follow combat area/water boundary',i,x,y,nav.values[i]);ownedNav++;
  }
  const samples=[];
  for(const area of manifest.areas){
    const w=area.clear_combat_size[0],h=area.clear_combat_size[1];let opened=0;
    for(let y=area.origin[1]-h/2+64;y<=area.origin[1]+h/2-64;y+=64)for(let x=area.origin[0]-w/2+64;x<=area.origin[0]+w/2-64;x+=64){
      const index=Math.floor((y+8192)/64)*256+Math.floor((x+8192)/64);fail(nav.values[index]==='0','Combat grid cell not open',area.id,x,y,index,nav.values[index]);opened++;
    }
    fail(opened>0,'No interior grid samples',area.id);samples.push({id:area.id,open_interior_samples:opened});
    for(const marker of area.markers){const [x,y]=marker.origin,index=Math.floor((y+8192)/64)*256+Math.floor((x+8192)/64);fail(nav.values[index]==='0','Marker sits in blocked navigation cell',marker.name,index);}
  }
  return {changed_values_or_records:changed,differences_by_field:diffs,combat_grid_samples:samples,patched_navigation_cells_checked:ownedNav,whitelist_spatial_bounds_checked:true,central_grid_preserved:true,other_grid_bytes_unchanged:true};
}
const crcTable=Array.from({length:256},(_,i)=>{for(let j=0;j<8;j++)i=(i>>>1)^((i&1)?0xedb88320:0);return i>>>0;});
function crc32(data){let c=0xffffffff;for(const b of data)c=(c>>>8)^crcTable[(c^b)&255];return (c^0xffffffff)>>>0;}
function checkVpk(filename,requiredModels,source){
  const data=fs.readFileSync(filename);fail(data.length>=12&&data.readUInt32LE(0)===0x55aa1234,'Invalid VPK header');
  const version=data.readUInt32LE(4);fail(version===1||version===2,'Unsupported VPK version');
  const start=version===2?28:12,end=start+data.readUInt32LE(8);fail(end<=data.length,'Truncated VPK tree');let cursor=start,checked=0,total=0;
  const entries=new Set(),references=new Set(),entityPayloads=[];let mapPayload;
  function string(){const stop=data.indexOf(0,cursor);fail(stop>=cursor&&stop<end,'Invalid VPK string');const value=data.toString('utf8',cursor,stop);cursor=stop+1;return value;}
  let ext,dir,name;
  while((ext=string()))while((dir=string()))while((name=string())){
    fail(cursor+18<=end,'Truncated VPK directory entry');const crc=data.readUInt32LE(cursor),preload=data.readUInt16LE(cursor+4),archive=data.readUInt16LE(cursor+6),offset=data.readUInt32LE(cursor+8),length=data.readUInt32LE(cursor+12),term=data.readUInt16LE(cursor+16);cursor+=18;
    fail(term===65535&&cursor+preload<=end,'Invalid VPK entry');const prefix=data.subarray(cursor,cursor+preload);cursor+=preload;
    const key=(dir===' '?'':dir+'/')+name+'.'+ext;fail(!entries.has(key),'Duplicate VPK entry',key);entries.add(key);
    let blob,base;if(archive===0x7fff){blob=data;base=end;}else{const archiveFile=filename.replace(/(?:_dir)?\.vpk$/,'_'+String(archive).padStart(3,'0')+'.vpk');blob=fs.readFileSync(archiveFile);base=0;}
    fail(base+offset+length<=blob.length,'Truncated VPK resource',key);
    const payload=Buffer.concat([prefix,blob.subarray(base+offset,base+offset+length)]);fail(crc32(payload)===crc,'VPK CRC mismatch',key);checked++;total+=payload.length;
    if(key==='maps/template_map.vmap_c')mapPayload=payload;
    if(key.endsWith('.vents_c'))entityPayloads.push(payload);
    if(/\.(?:vmap_c|vwrld_c|vwnod_c|vents_c)$/.test(key))for(const match of payload.toString('latin1').matchAll(/models\/[A-Za-z0-9_\-/]+\.vmdl(?:_c)?/g))references.add(match[0].replace(/_c$/,''));
    if(/^(?:models|materials)\/(?:gold_training_room|wood_training_room|attribute_training_room|greater_attribute_training_room|molten_core_room|ascension_arenas|ten_realm_arenas)\//.test(key)){
      const installed=path.join(ROOT,key);fail(fs.existsSync(installed)&&fs.readFileSync(installed).equals(payload),'Embedded resource stale vs installed game asset',key);
    }
  }
  fail(cursor===end,'VPK tree did not consume exact directory');fail([...entries].some(e=>e.endsWith('.vmap_c')),'VPK missing compiled map');
  const dependencies=[];
  for(const model of requiredModels){
    fail(references.has(model)||entries.has(model+'_c'),'Compiled map missing arena model reference',model);
    const installed=path.join(ROOT,model+'_c');fail(fs.existsSync(installed),'Referenced compiled arena model is not installed',model);
    const asset=fs.readFileSync(installed);fail(asset.length>16,'Referenced compiled model is truncated',model);
    dependencies.push({model,bytes:asset.length,sha256:sha(asset)});
  }
  let compiledSource;
  if(source){
    compiledSource=withTemporaryDirectory(directory=>{
    fail(mapPayload&&entityPayloads.length,'Compiled template map/entity lump missing');
    const execute=require('child_process').execFileSync,bin=path.resolve(ROOT,'../../../game/bin/win64');
    const temporaryMap=path.join(directory,'verification_map.vmap_c'),expectedBinary=path.join(directory,'verification_expected_map.vmap');
    fs.writeFileSync(temporaryMap,mapPayload);
    const dump=execute(path.join(bin,'resourceinfo.exe'),['-game',path.resolve(ROOT,'../../dota'),'-i',temporaryMap,'-all'],{encoding:'utf8',maxBuffer:16*1024*1024,windowsHide:true});
    const inputCRC=Number(dump.match(/m_RelativeFilename = "maps\/template_map\.vmap"[\s\S]*?m_nFileCRC = (\d+)/)?.[1]);
    fail(Number.isInteger(inputCRC),'Compiled map input CRC is unavailable');
    execute(path.join(bin,'dmxconvert.exe'),['-i',source.integrated,'-o',expectedBinary,'-oe','binary'],{encoding:'utf8',maxBuffer:1024*1024,windowsHide:true});
    const expectedCRC=crc32(fs.readFileSync(expectedBinary));
    fail(inputCRC===expectedCRC,'Compiled VPK does not match the current integrated VMAP',inputCRC,expectedCRC);
    const compiledMarkers=new Map();
    for(let i=0;i<entityPayloads.length;i++){
      const file=path.join(directory,'verification_entities_'+i+'.vents_c');fs.writeFileSync(file,entityPayloads[i]);
      const text=execute(path.join(bin,'resourceinfo.exe'),['-game',path.resolve(ROOT,'../../dota'),'-i',file,'-all'],{encoding:'utf8',maxBuffer:32*1024*1024,windowsHide:true});
      const expression=/\bvalues\s*=\s*\{/g;let match;
      while((match=expression.exec(text))){
        const start=text.indexOf('{',match.index),end=endOf(text,start),body=text.slice(start,end);expression.lastIndex=end;
        const name=body.match(/\btargetname\s*=\s*"([^"]+)"/)?.[1].replace(/^\[PR#\]/,'');
        if(!name)continue;
        const origin=body.match(/\borigin\s*=\s*\[([^\]]+)\]/)?.[1].split(',').map(Number);
        if(!compiledMarkers.has(name))compiledMarkers.set(name,[]);
        compiledMarkers.get(name).push({origin,classname:body.match(/\bclassname\s*=\s*"([^"]+)"/)?.[1]});
      }
    }
    for(const marker of source.markers){
      const matches=compiledMarkers.get(marker.name)||[];
      fail(matches.length===1&&matches[0].classname==='info_target'&&close(matches[0].origin,marker.origin,.002),'Compiled marker missing/duplicated/displaced',marker.name,matches);
    }
    return {input_crc32:inputCRC,expected_binary_crc32:expectedCRC,current_integrated_source_matches:true,actual_compiled_markers_checked:source.markers.length};
    });
  }
  return {path:filename,sha256:sha(data),crc_entries:checked,payload_bytes:total,arena_model_references:requiredModels.length,installed_model_dependencies:dependencies,source_and_markers:compiledSource};
}
function main(){
  const args=process.argv.slice(2), option=(name,otherwise)=>{const i=args.indexOf(name);return i<0?otherwise:path.resolve(args[i+1]);};
  const manifestFile=option('--manifest',path.join(DEFAULT_OUT,'integration_manifest.json'));
  const reportFile=option('--report',path.join(DEFAULT_OUT,'verification.json'));
  const report={status:'FAIL',runtime_verified:false};
  try{
    const manifest=JSON.parse(fs.readFileSync(manifestFile,'utf8').replace(/^\uFEFF/,''));
    const baseline=option('--baseline',manifest.baseline_text||BASELINE),integrated=option('--map',manifest.integrated_text||path.join(DEFAULT_OUT,'template_integrated.vmap'));
    const before=fs.readFileSync(baseline,'utf8'),after=fs.readFileSync(integrated,'utf8');
    fail(sha(before)===manifest.baseline_text_sha256&&sha(after)===manifest.integrated_text_sha256,'Input hashes do not match integration manifest');
    const retained=preserve(before,after,manifest),spatial=checkAreas(manifest.areas,retained.entities,retained.meshesActual,manifest.nativeBounds),grid=checkGrid(before,after,manifest);
    const requiredModels=[...new Set(manifest.areas.flatMap(a=>a.placements.map(p=>p.model)).filter(m=>sourceAsset(m)))];
    const vpk=args.includes('--vpk')?checkVpk(option('--vpk'),requiredModels,{integrated,markers:manifest.areas.flatMap(a=>a.markers)}):null;
    delete retained.entities;delete retained.meshesActual;
    Object.assign(report,{status:'PASS',baseline_sha256:sha(before),integrated_sha256:sha(after),preservation:retained,spatial,grid,
      compiled_vpk:vpk,compiled_verified:!!vpk,note:vpk?'Source and compiled payload checks passed; run engine GridNav/ground tests separately.':'Source-only check; compiled VPK and engine behavior not yet verified.'});
  }catch(error){report.error=String(error.message||error);process.exitCode=1;}
  fs.mkdirSync(path.dirname(reportFile),{recursive:true});fs.writeFileSync(reportFile,JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify({status:report.status,report:reportFile,error:report.error,compiled_verified:report.compiled_verified}));
}
module.exports={blocks,value,vector,primitiveArrays,transformedBounds,overlaps,preserve,crc32,checkVpk,checkAreas,checkGrid};
if(require.main===module)main();
