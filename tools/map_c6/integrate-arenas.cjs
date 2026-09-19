// Integrate the approved art into a COPY of the current main Hammer map.
// Never regenerate the central sanctuary or install/compile content implicitly.
'use strict';
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const {execFileSync} = require('child_process');
const L = require('./lib.cjs');
const ROOT = path.resolve(__dirname, '../..');
const ENGINE = path.resolve(ROOT, '../../..');
const CONTENT = path.join(ENGINE, 'content/dota_addons/survival');
const OUT = path.join(ROOT, 'output/map_arena_integration_20260919');
const ASSET_SNAPSHOT = path.join(__dirname, 'arena-assets.json');
const arg = name => process.argv.find(v => v.startsWith(name + '='))?.slice(name.length + 1);
const INPUT = path.resolve(arg('--source') || path.join(CONTENT, 'maps/template_map.vmap'));
const sha = text => crypto.createHash('sha256').update(text).digest('hex');
const readJson = p => JSON.parse(fs.readFileSync(p, 'utf8').replace(/^\uFEFF/, ''));
const round = n => Math.round(n * 1e6) / 1e6;
const vec = s => s.split(/\s+/).map(Number);
const fmt = p => p.map(round).join(' ');
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const assert = (ok, msg) => { if (!ok) throw Error(msg); };
const assetSnapshot = readJson(ASSET_SNAPSHOT);
assert(assetSnapshot.schema_version === 1, 'Unsupported arena asset snapshot');
const namespaceAssets = namespace => {
  const entry = assetSnapshot.namespaces[namespace];
  assert(entry?.assets?.length, 'Missing versioned assets for ' + namespace);
  return entry.assets;
};
fs.mkdirSync(OUT, {recursive: true});
const baselineText = path.join(OUT, 'template_before_text.vmap');
if (fs.readFileSync(INPUT).subarray(0, 100).toString().includes('encoding keyvalues2')) {
  fs.copyFileSync(INPUT, baselineText);
} else {
  execFileSync(path.join(ENGINE, 'game/bin/win64/dmxconvert.exe'),
    ['-i', INPUT, '-o', baselineText, '-oe', 'keyvalues2'], {stdio: 'inherit'});
}
const baseline = fs.readFileSync(baselineText, 'utf8');
assert(!baseline.includes('arena_integration_'), 'Already integrated: use the saved pre-integration baseline to rebuild.');
const originalEntities = L.blocks(baseline, 'CMapEntity');
const originalMeshes = L.blocks(baseline, 'CMapMesh');
const gridBlock = L.blocks(baseline, 'CMapDotaTileGrid')[0];
assert(gridBlock && L.value(gridBlock.text, 'gridWidth') === '64'
  && L.value(gridBlock.text, 'gridHeight') === '64', 'Expected the current 64 x 64 main map.');
assert(originalMeshes.length === 5, 'Expected five preserved central/sea-bed meshes.');
const centralBounds = [[-4096, -3072], [2048, 3072]];
const originalNodes = [...baseline.matchAll(/"nodeID" "int" "(\d+)"/g)].map(m => +m[1]);
let nextNode = Math.max(...originalNodes) + 1, nextGuid = 0;
function guid() {
  const hex = sha('main-arena-integration-20260919-' + nextGuid++).slice(0, 32);
  return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`;
}
function reidentify(text) {
  return text.replace(/"elementid" "[^"]+"/g, () => `"elementid" "${guid()}"`)
    .replace(/"nodeID" "int" "\d+"/g, () => `"nodeID" "int" "${nextNode++}"`)
    .replace(/"referenceID" "uint64" "[^"]+"/g, '"referenceID" "uint64" "0x0"');
}
function boundsOf(points) {
  assert(points.length > 0, 'No points to bound');
  const min = [Infinity, Infinity, Infinity], max = [-Infinity, -Infinity, -Infinity];
  for (const p of points) for (let i = 0; i < 3; i++) {
    assert(Number.isFinite(p[i]), 'Non-finite coordinate');
    min[i] = Math.min(min[i], p[i]); max[i] = Math.max(max[i], p[i]);
  }
  return [min.map(round), max.map(round)];
}
function rotation([pitch, yaw, roll]) {
  const [p,y,r] = [pitch,yaw,roll].map(v => v*Math.PI/180);
  const [cp,sp,cy,sy,cr,sr] = [Math.cos(p),Math.sin(p),Math.cos(y),Math.sin(y),Math.cos(r),Math.sin(r)];
  return [[cy*cp,cy*sp*sr-sy*cr,cy*sp*cr+sy*sr],
    [sy*cp,sy*sp*sr+cy*cr,sy*sp*cr-cy*sr],[-sp,cp*sr,cp*cr]];
}
function worldBounds(local, origin, scales, angles) {
  const R = rotation(angles), points=[];
  for (const x of [local[0][0],local[1][0]]) for (const y of [local[0][1],local[1][1]])
    for (const z of [local[0][2],local[1][2]]) {
      const p=[x,y,z].map((v,i)=>v*scales[i]);
      points.push(R.map((row,i)=>origin[i]+row.reduce((n,v,j)=>n+v*p[j],0)));
    }
  return boundsOf(points);
}
function meshPositions(text) {
  const m = text.match(/"name" "string" "position:0"[\s\S]*?"data" "vector3_array"\s*\[([^\]]*)\]/);
  assert(m, 'Missing mesh position stream');
  return [...m[1].matchAll(/"([^"\r\n]*)"/g)].map(v=>vec(v[1]));
}
function transformMesh(text, area, training) {
  const scale=area.xyScale || [1,1];
  const points=meshPositions(text).map(p=>[
    area.origin[0]+p[0]*scale[0], area.origin[1]+p[1]*scale[1],
    training ? (p[2] < 100 ? 2 : p[2]) : area.origin[2]+p[2]
  ]);
  text=text.replace(/("name" "string" "position:0"[\s\S]*?"data" "vector3_array"\s*)\[[^\]]*\]/,
    (_,head)=>head+'['+points.map(p=>'"'+fmt(p)+'"').join(',')+']');
  text=reidentify(text);
  area.supports.push({nodeID:+L.value(text,'nodeID'),bounds:boundsOf(points),
    materials:L.array(text,'materials'),sha256:sha(text)});
  return text;
}
const nativeBounds = {};
let nativePak;
function nativeModelBounds(model) {
  if (nativeBounds[model]) return nativeBounds[model].bounds;
  const expected=assetSnapshot.native[model];
  assert(expected, 'Unreviewed native model: '+model);
  nativePak ||= new L.Vpk(path.join(ENGINE,'game/dota/pak01_dir.vpk'));
  const actual=nativePak.read(expected.pak_resource);
  assert(sha(actual)===expected.sha256,'Native asset changed; refresh reviewed bounds: '+model);
  nativeBounds[model]={...expected,compiled_source:path.join(ENGINE,'game/dota/pak01_dir.vpk')+':'+expected.pak_resource};
  return expected.bounds;
}
const children=[],areas=[],insertedMarkers=[],removedMarkers=[];
const roomDefs=[
  ['01','wood_training_room',-6656,6784],['02','gold_training_room',-4352,6784],
  ['03','attribute_training_room',-4352,4480],['04','greater_attribute_training_room',-6656,4480],
  ['07','molten_core_room',-6656,-4480],['08','molten_core_room',-6656,-6784]
];
const arenaXY=rank=>rank===10?[1024,-5120]:[7168-Math.floor((rank-1)/3)*2048,-3072-((rank-1)%3)*2048];
const realmXY=rank=>rank===10?[1024,5120]:[7168-Math.floor((rank-1)/3)*2048,7168-((rank-1)%3)*2048];
function addMarker(name,origin,role,area) {
  assert(!insertedMarkers.some(m=>m.name===name),'Duplicate new marker '+name);
  const nodeID=nextNode++;
  const text=`"CMapEntity" { "id" "elementid" "${guid()}" "nodeID" "int" "${nodeID}"
"children" "element_array" [] "entity_properties" "EditGameClassProps" {
"id" "elementid" "${guid()}" "classname" "string" "info_target" "targetname" "string" "${name}" }
"origin" "vector3" "${fmt(origin)}" "angles" "qangle" "0 0 0" "scales" "vector3" "1 1 1"
"force_hidden" "bool" "0" "editorOnly" "bool" "0" }`;
  const marker={name,origin:origin.map(round),role,nodeID};
  children.push(text);area.markers.push(marker);insertedMarkers.push(marker);
}
function importPrefab(area, prefab, namespace, training=false) {
  const filename=path.join(CONTENT,'maps/prefabs',prefab+'.vmap');
  const text=fs.readFileSync(filename,'utf8');
  assert(text.includes('encoding keyvalues2'), 'Prefab must be editable text: '+filename);
  const assets=namespaceAssets(namespace);
  const byModel=new Map(assets.map(a=>[`models/${namespace}/${a.name}.vmdl`,a]));
  area.prefab=filename;area.prefab_sha256=sha(fs.readFileSync(filename));
  area.asset_manifest=ASSET_SNAPSHOT;area.asset_namespace=namespace;
  area.placements=[];area.supports=[];area.markers=[];
  for (const b of L.blocks(text,'CMapMesh')) children.push(transformMesh(b.text,area,training));
  for (const b of L.blocks(text,'CMapEntity')) {
    const cls=L.value(b.text,'classname'),oldName=L.value(b.text,'targetname');
    if (cls==='info_target') {
      if (!training) continue;
      let name=oldName;
      if (area.challenge==='08') name=name.replace(/^challenge_07_/,'challenge_08_');
      const p=vec(L.value(b.text,'origin'));
      addMarker(name,[area.origin[0]+p[0]*area.xyScale[0],area.origin[1]+p[1]*area.xyScale[1],p[2]],
        name.endsWith('_entry')?'entry':name.endsWith('_home')?'home':'spawn',area);
      continue;
    }
    assert(cls==='prop_static', 'Unexpected prefab entity '+cls);
    let t=b.text;
    const model=L.value(t,'model'),asset=byModel.get(model),oldOrigin=vec(L.value(t,'origin'));
    const angles=vec(L.value(t,'angles')||'0 0 0'),oldScales=vec(L.value(t,'scales')||'1 1 1');
    const origin=oldOrigin.map((n,i)=>training?(i<2?area.origin[i]+n*area.xyScale[i]:n):area.origin[i]+n);
    let scales=oldScales.slice(), approximate=false, scalePolicy='unscaled_prefab';
    if (training) {
      // Cardinal wall/floor props are exact. Oblique vegetation cannot represent
      // global anisotropic shear in a prop transform, so preserve its rotation
      // and use each transformed local-axis length; bounds below are ACTUAL
      // resulting prop bounds, never idealized room-scaled source bounds.
      const R=rotation(angles), A=[...area.xyScale,1];
      scales=scales.map((s,j)=>s*Math.hypot(...R.map((row,i)=>row[j]*A[i])));
      approximate=angles[0]!==0||angles[2]!==0||Math.abs(angles[1]/90-Math.round(angles[1]/90))>1e-8;
      scalePolicy=approximate?'oblique_local_axis_lengths':'exact_cardinal_xy';
      if (/\/(?:b06|f06)_arc_60\.vmdl$/.test(model)) {
        // All three rotated segments share one circular centre. Different
        // per-axis lengths would shear their seams apart. A common XY scale
        // preserves the authored joins and still overlaps the end pillars.
        assert(angles[0]===0&&angles[2]===0, 'Unexpected tilted structural arc');
        const common=(area.xyScale[0]+area.xyScale[1])/2;
        scales=[oldScales[0]*common,oldScales[1]*common,oldScales[2]];
        approximate=false;scalePolicy='continuous_arc_uniform_xy';
      }
    }
    const name=`arena_integration_${area.id}_${oldName}`;
    t=L.setValue(L.setValue(L.setValue(t,'origin',fmt(origin)),'scales',fmt(scales)),'targetname',name);
    t=reidentify(t);
    const local=asset?.bounds||nativeModelBounds(model),actualOrigin=vec(L.value(t,'origin')),actualScales=vec(L.value(t,'scales'));
    const item={targetname:name,nodeID:+L.value(t,'nodeID'),model,origin:actualOrigin,scales:actualScales,angles,
      localBounds:local,worldBounds:worldBounds(local,actualOrigin,actualScales,angles),
      bounds_source:asset?area.asset_manifest:nativeBounds[model].compiled_source,
      approximation:approximate?'oblique nonuniform scaling uses local-axis lengths; actual transformed bounds verified':'exact',
      scale_policy:scalePolicy,solid:L.value(t,'solid')};
    area.placements.push(item);children.push(t);
  }
  area.worldBounds=boundsOf([...area.placements.flatMap(p=>p.worldBounds),...area.supports.flatMap(p=>p.bounds)]);
}
for (const [key,namespace,x,y] of roomDefs) {
  const area={id:'training_'+key,kind:'training',challenge:key,namespace,origin:[x,y,128],
    xyScale:[900/2048,900/2304],floor_size:[900,900],clear_combat_size:[850.78125,869.53125],surfaceZ:128,
    terrainBox:[x-1024,y-896,x+1024,y+896],navigation:{kind:'training_scaled',source_scale:[900/2048,900/2304]}};
  importPrefab(area,namespace,namespace,true);areas.push(area);
}
for(let rank=1;rank<=10;rank++) {
  const key=String(rank).padStart(2,'0'),[x,y]=arenaXY(rank),namespace='ascension_arenas';
  const a=namespaceAssets(namespace).find(a=>a.meta.rank===rank),m=a.meta;
  assert(eq(m.footprint,[1000,550]), 'Outdated ascension footprint');
  const area={id:'rebirth_'+key,kind:'rebirth',rank,namespace,origin:[x,y,16],floor_size:m.footprint,
    clear_combat_size:m.clear_combat_size,surfaceZ:16+m.deck_z,terrainBox:[x-1024,y-1024,x+1024,y+1024],
    navigation:{kind:'rectangle',size:m.clear_combat_size}};
  importPrefab(area,'ascension_arena_'+key,namespace);
  // The long axis leaves room for the encounter service's inward spawn offset.
  const dx=Math.min(300,m.clear_combat_size[0]/2-80),z=area.surfaceZ+24;
  addMarker('rebirth_'+key+'_entry',[x-dx,y,z],'entry',area);
  addMarker('rebirth_'+key+'_boss_spawn',[x+dx,y,z],'spawn',area);
  addMarker('ascension_arena_'+key+'_center',[x,y,z],'center',area);
  areas.push(area);
}
for(let rank=1;rank<=10;rank++) {
  const key=String(rank).padStart(2,'0'),[x,y]=realmXY(rank),namespace='ten_realm_arenas';
  const area={id:'ten_realm_'+key,kind:'ten_realm',rank,namespace,origin:[x,y,58],floor_size:[700,700],
    clear_combat_size:[612,612],surfaceZ:58,waterZ:16,terrainBox:[x-1024,y-1024,x+1024,y+1024],
    navigation:{kind:'rectangle',size:[612,612]}};
  importPrefab(area,'ten_realm_arena_'+key,namespace);
  addMarker('challenge_11_stage_'+key+'_entry',[x,y-234,82],'entry',area);
  addMarker('challenge_11_stage_'+key+'_spawn',[x,y+234,82],'spawn',area);
  addMarker('ten_realm_arena_'+key+'_center',[x,y,82],'center',area);
  areas.push(area);
}
const replacedName=name=>/^challenge_(?:01|02|03|04|07|08)_(?:entry|home|boss_spawn|spawn_\d+)$/.test(name)
  || /^rebirth_(?:0[1-9]|10|010)_(?:entry|boss_spawn)$/.test(name)
  || /^challenge_11_stage_\d+_(?:entry|spawn)$/.test(name);
const edits=[];
const retainedEntities=[];
for(const b of originalEntities) {
  const name=L.value(b.text,'targetname')||'';
  if(replacedName(name)) {
    assert(L.value(b.text,'classname')==='info_target','Only owned markers can be removed');
    removedMarkers.push({name,origin:vec(L.value(b.text,'origin')),nodeID:+L.value(b.text,'nodeID')});
    edits.push({start:b.start,end:b.end,text:''});
  } else retainedEntities.push({guid:b.text.match(/"id" "elementid" "([^"]+)"/)[1],
    nodeID:+L.value(b.text,'nodeID'),classname:L.value(b.text,'classname'),targetname:name,sha256:sha(b.text)});
}
assert(removedMarkers.length===52, 'Unexpected main-map marker ownership: '+removedMarkers.length);
// Keep the central block and all unrelated authored entities byte-for-byte.
const preservation={centralBounds,meshNodes:originalMeshes.map(b=>({nodeID:+L.value(b.text,'nodeID'),sha256:sha(b.text)})),
  retainedEntities,removedMarkerNames:removedMarkers.map(m=>m.name)};

// Native terrain editing is restricted to old peripheral island rectangles.
// A water-cell configuration copied from THIS map retains the actual native
// water material/height. Props supply their own collision + walkable supports.
const arrays={},types={};
for(const m of gridBlock.text.matchAll(/"(\w+)" "(int|uint8|bool|color|string)_array"\s*\[([^\]]*)\]/g)) {
  if(arrays[m[1]]) continue;
  arrays[m[1]]=[...m[3].matchAll(/"([^"\r\n]*)"/g)].map(v=>v[1]);types[m[1]]=m[2];
}
const N=64,V=65,O=257,B=513;
const cellRecords=L.records(arrays.cellConfiguration),cellNames=L.records(arrays.cellConfigurationByName);
const objectRecords=L.records(arrays.objectConfiguration),objectNames=L.records(arrays.objectConfigurationByName);
assert(cellRecords.length===4096&&cellNames.length===4096&&objectRecords.length===66049&&objectNames.length===66049,
  'Unexpected encoded native terrain records');
const pointIn=(x,y,b,inclusive=true)=>inclusive?x>=b[0]&&y>=b[1]&&x<=b[2]&&y<=b[3]:x>b[0]&&y>b[1]&&x<b[2]&&y<b[3];
// Adjacent peripheral boxes touch X=2048. Shared lattice vertices and blend
// samples on that line still belong to the protected central rectangle.
const owned=(x,y)=>!pointIn(x,y,[...centralBounds[0],...centralBounds[1]])
  && areas.some(a=>pointIn(x,y,a.terrainBox));
const whitelist={},changes={};
function setAt(field,index,value) {
  (whitelist[field]||=new Set()).add(index);
  if(arrays[field][index]!==String(value)) {(changes[field]||=[]).push(index);arrays[field][index]=String(value);}
}
let waterCell=-1;
for(let y=0;y<N&&waterCell<0;y++)for(let x=0;x<N;x++) {
  const idx=y*N+x,vs=[y*V+x,y*V+x+1,(y+1)*V+x,(y+1)*V+x+1];
  if(arrays.cellsTileSet[idx]==='0'&&vs.every(v=>arrays.verticesWater[v]==='1'&&arrays.verticesHeight[v]==='0')) {
    waterCell=idx;break;
  }
}
assert(waterCell>=0,'No canonical native water cell');
const waterConfig=cellRecords[waterCell].slice(),waterNames=cellNames[waterCell].slice();
const cellFields=['cellsTileSet','cellsHidden','cellsOrientation','cellsMaterialSet','cellsCustomPathType','cellsVariationId'];
const waterSettings=Object.fromEntries(cellFields.map(k=>[k,arrays[k][waterCell]]));
waterSettings.cellsHidden='0';
const cellIndices=[],vertexIndices=[],objectIndices=[],navIndices=[],blendIndices=[];
for(let y=0;y<N;y++)for(let x=0;x<N;x++) {
  const px=-8192+x*256+128,py=-8192+y*256+128,i=y*N+x;
  if(!owned(px,py))continue;cellIndices.push(i);
  for(const k of cellFields)setAt(k,i,waterSettings[k]);
  for(const [field,records,val] of [['cellConfiguration',cellRecords,waterConfig],['cellConfigurationByName',cellNames,waterNames]]) {
    (whitelist[field]||=new Set()).add(i);if(!eq(records[i],val))(changes[field]||=[]).push(i);records[i]=val.slice();
  }
}
for(let y=0;y<V;y++)for(let x=0;x<V;x++) {
  if(!owned(-8192+x*256,-8192+y*256))continue;const i=y*V+x;vertexIndices.push(i);
  setAt('verticesWater',i,1);setAt('verticesHeight',i,0);
}
const objectFields=Object.keys(arrays).filter(k=>k.startsWith('objects')&&arrays[k].length===O*O);
for(let y=0;y<O;y++)for(let x=0;x<O;x++) {
  if(!owned(-8192+x*64,-8192+y*64))continue;const i=y*O+x;objectIndices.push(i);
  for(const k of objectFields)setAt(k,i,k==='objectsVariationId'?255:0);
  for(const [field,records] of [['objectConfiguration',objectRecords],['objectConfigurationByName',objectNames]]) {
    (whitelist[field]||=new Set()).add(i);if(records[i].length)(changes[field]||=[]).push(i);records[i]=[];
  }
}
function canWalk(area,x,y) {
  x-=area.origin[0];y-=area.origin[1];
  if(area.kind==='training') {
    x/=area.xyScale[0];y/=area.xyScale[1];
    return (Math.abs(x)<968&&y>-1096&&y<1130)||(y>=1090&&y<1350&&Math.hypot(x,y-1152)<200);
  }
  return Math.abs(x)<area.clear_combat_size[0]/2&&Math.abs(y)<area.clear_combat_size[1]/2;
}
for(const a of areas)a.openGridCells=0;
for(let y=0;y<256;y++)for(let x=0;x<256;x++) {
  const px=-8192+x*64+32,py=-8192+y*64+32,i=y*256+x;
  if(!owned(px,py))continue;navIndices.push(i);
  const area=areas.find(a=>canWalk(a,px,py));if(area)area.openGridCells++;
  setAt('gridnavFlags',i,area?0:1);
}
for(let y=0;y<B;y++)for(let x=0;x<B;x++) {
  if(!owned(-8192+x*32,-8192+y*32))continue;const i=y*B+x;blendIndices.push(i);setAt('grassOpacity',i,0);
}
// Prevent old path overlays crossing the newly cleared water. Native edge
// records are two orientations for each N*(N+1) lattice, as in the seed.
for(const k of ['edgesPath','edgesDestruction']) {
  assert(arrays[k].length===8320,'Unexpected edge grid');
  for(let y=0;y<V;y++)for(let x=0;x<N;x++) {
    const i=y*N+x;
    if(owned(-8192+x*256+128,-8192+y*256))setAt(k,i,0);
    if(owned(-8192+y*256,-8192+x*256+128))setAt(k,4160+i,0);
  }
}
const encode=records=>records.flatMap(r=>[String(r.length),...r]);
arrays.cellConfiguration=encode(cellRecords);arrays.cellConfigurationByName=encode(cellNames);
arrays.objectConfiguration=encode(objectRecords);arrays.objectConfigurationByName=encode(objectNames);
let updatedGrid=gridBlock.text.replace(/"(\w+)" "(int|uint8|bool|color|string)_array"\s*\[[^\]]*\]/g,(all,k,type)=> {
  if(!whitelist[k])return all;
  return `"${k}" "${type}_array" [${arrays[k].map(v=>'"'+v+'"').join(',')} ]`;
});
edits.push({start:gridBlock.start,end:gridBlock.end,text:updatedGrid});
let integrated=baseline;
for(const e of edits.sort((a,b)=>b.start-a.start))integrated=integrated.slice(0,e.start)+e.text+integrated.slice(e.end);
// Empty entity removal leaves optional commas; DMX tolerates whitespace but not
// duplicate separators. Delete only redundant separators at the world level.
integrated=integrated.replace(/,\s*,/g,',').replace(/\[\s*,/g,'[').replace(/,\s*\]/g,']');
const worldStart=integrated.indexOf('"world" "CMapWorld"');
const childrenStart=integrated.indexOf('[',integrated.indexOf('"children" "element_array"',worldStart));
const childrenEnd=L.endOf(integrated,childrenStart,'[',']')-1;
integrated=integrated.slice(0,childrenEnd)+',\n'+children.join(',\n')+'\n'+integrated.slice(childrenEnd);
const target=path.join(OUT,'template_integrated.vmap');
fs.writeFileSync(target,integrated);

const preservedByNode=new Map(L.blocks(integrated,'CMapEntity').map(b=>[+L.value(b.text,'nodeID'),b.text]));
for(const r of retainedEntities)assert(sha(preservedByNode.get(r.nodeID)||'')===r.sha256,'Preserved entity changed: '+r.nodeID);
const actualMeshes=new Map(L.blocks(integrated,'CMapMesh').map(b=>[+L.value(b.text,'nodeID'),b.text]));
for(const r of preservation.meshNodes)assert(sha(actualMeshes.get(r.nodeID)||'')===r.sha256,'Preserved central mesh changed: '+r.nodeID);
const names=new Map();
for(const b of L.blocks(integrated,'CMapEntity')) {
  const n=L.value(b.text,'targetname');if(n) {assert(!names.has(n),'Duplicate final targetname '+n);names.set(n,+L.value(b.text,'nodeID'));}
}
assert(!names.has('rebirth_010_boss_spawn')&&names.has('rebirth_10_boss_spawn'),'Rebirth 10 typo not repaired');
let minClearance=Infinity;
let arcJoinsChecked=0;
for(let i=0;i<areas.length;i++) {
  const a=areas[i],b=a.worldBounds;
  assert(b[0].slice(0,2).every(n=>n>=-8192)&&b[1].slice(0,2).every(n=>n<=8192),'Area exceeds map: '+a.id);
  assert(!(b[0][0]<centralBounds[1][0]&&b[1][0]>centralBounds[0][0]&&b[0][1]<centralBounds[1][1]&&b[1][1]>centralBounds[0][1]),'Area touches central protected rectangle: '+a.id);
  assert(a.openGridCells>0,'No nav for '+a.id);
  if(a.kind==='training') {
    const arcs=a.placements.filter(p=>p.scale_policy==='continuous_arc_uniform_xy').sort((p,q)=>p.angles[1]-q.angles[1]);
    assert(arcs.length===3,'Expected three structural arc segments: '+a.id);
    const arcPoint=(p,degrees)=> {
      const t=degrees*Math.PI/180,R=rotation(p.angles),v=[256*Math.cos(t)*p.scales[0],256*Math.sin(t)*p.scales[1],0];
      return R.map((row,k)=>p.origin[k]+row.reduce((sum,n,j)=>sum+n*v[j],0));
    };
    for(let j=1;j<arcs.length;j++) {
      const left=arcPoint(arcs[j-1],120),right=arcPoint(arcs[j],60);
      assert(Math.hypot(...left.map((v,k)=>v-right[k]))<.001,'Structural arc seam mismatch: '+a.id);
      arcJoinsChecked++;
    }
  }
  for(const m of a.markers)assert(canWalk(a,m.origin[0],m.origin[1]),'Marker outside room walkable shape: '+m.name);
  for(let j=0;j<i;j++) {
    const c=areas[j].worldBounds;
    const gaps=[0,1].map(k=>Math.max(b[0][k]-c[1][k],c[0][k]-b[1][k],0));
    assert(gaps.some(n=>n>0),'Model overlap: '+a.id+' / '+areas[j].id);
    minClearance=Math.min(minClearance,Math.hypot(...gaps));
  }
}
const report={schema_version:1,map:'template_map',generated_at:new Date().toISOString(),
  asset_snapshot:ASSET_SNAPSHOT,asset_snapshot_sha256:sha(fs.readFileSync(ASSET_SNAPSHOT)),
  baseline_source:INPUT,baseline_text:baselineText,baseline_source_sha256:sha(fs.readFileSync(INPUT)),
  baseline_text_sha256:sha(baseline),integrated_text:target,integrated_text_sha256:sha(integrated),
  centralBounds,mapBounds:[[-8192,-8192],[8192,8192]],seaZ:16,
  areas,markers:insertedMarkers,removedMarkers,nativeBounds,preservation,
  terrainPatches:areas.map(a=>({area:a.id,box:a.terrainBox})),
  gridWhitelist:Object.fromEntries(Object.entries(whitelist).map(([k,v])=>[k,{indices:[...v].sort((a,b)=>a-b),
    index_kind:/Configuration/.test(k)?'decoded_record': 'array'}])),
  gridChangedIndices:changes,canonical_water_cell:waterCell,
  gridCoordinates:{origin:[-8192,-8192],cells:{width:64,step:256,offset:128},vertices:{width:65,step:256,offset:0},
    objects:{width:257,step:64,offset:0},gridnav:{width:256,step:64,offset:32},blend:{width:513,step:32,offset:0},
    edges:{orientation_stride:4160,width:64,height:65,step:256}},
  counts:{training:6,rebirth:10,ten_realm:10,areas:areas.length,props:areas.reduce((n,a)=>n+a.placements.length,0),
    newMarkers:insertedMarkers.length,removedMarkers:removedMarkers.length,openGridCells:areas.reduce((n,a)=>n+a.openGridCells,0)},
  checks:{preserved_entity_blocks:true,preserved_mesh_blocks:true,unique_markers:true,area_bounds:true,
    no_area_overlap:true,min_model_clearance:round(minClearance),continuous_arc_joins:arcJoinsChecked,
    compiled:false,runtime_verified:false},
  notes:['The current main-map lights and all unrelated entities are preserved.',
    'Training oblique vegetation uses approximate anisotropic transforms; stored bounds describe the exact resulting transforms.',
    'Training support bases reach Z=2. Ascension base Z=16; realm base Z=58 and local water -42 match the native sea Z=16.',
    'Encoded cell/object Configuration indices in whitelists refer to decoded records, not flattened array offsets.',
    'Compilation and actual GridNav/teleport checks are required after explicit installation.']};
fs.writeFileSync(path.join(OUT,'integration_manifest.json'),JSON.stringify(report,null,2));
console.log(JSON.stringify({output:target,manifest:path.join(OUT,'integration_manifest.json'),counts:report.counts,checks:report.checks},null,2));
