'use strict';
// Reconstruct reference decoration from compiled world-node transforms, then
// fit it to our existing four lanes. Source markers and navigation stay intact.
const fs=require('fs'),path=require('path'),crypto=require('crypto'),L=require('./lib.cjs'),M=require('./mesh.cjs');
const out=path.resolve(__dirname,'../../output/valley_reference_v3');
const before=fs.readFileSync(path.join(out,'before.vmap'),'utf8');
const source=JSON.parse(fs.readFileSync(path.join(out,'instances.json')));
const imported=JSON.parse(fs.readFileSync(path.join(out,'prop_import.json'))).selected;
const guid=()=>crypto.randomUUID(),round=n=>+n.toFixed(5);
let node=Math.max(...[...before.matchAll(/"nodeID" "int" "(\d+)"/g)].map(m=>+m[1]))+1;
let result=before;const additions=[],placements=[],counts={},removed=[];
for(const b of L.blocks(before,'CMapGroup').filter(b=>/^valley_v2_(border|stones|red_flower_scatter|spawn)_/.test(L.value(b.text,'name')||'')).reverse()){
 const keep=L.blocks(b.text,'CMapEntity').filter(e=>L.value(e.text,'classname')==='info_particle_system').map(e=>e.text);
 result=result.slice(0,b.start)+(keep.length?keep.join(',\n'):'')+result.slice(b.end);
 removed.push(L.value(b.text,'name'));
}
// Removing sibling elements can leave empty comma slots in KV2 arrays.
result=result.replace(/\[\s*,/g,'[').replace(/,(\s*,)+/g,',').replace(/,\s*\]/g,']');
const grid=L.blocks(before,'CDmeDotaTileGrid')[0].text,heights=L.array(grid,'verticesHeight').map(Number);
const sampled=new Map([...fs.readFileSync(path.join(out,'ground_probe.log'),'utf8').matchAll(/^VALLEY_GROUND_ROW (-?\d+) ([01]+)\r?$/gm)].map(m=>[+m[1],m[2]]));
if(sampled.size!==193)throw Error('Expected complete Workshop surface samples');
const surface=(x,y)=>sampled.get(y)?.[(x+3072)/32]==='1';
function plateau(x,y){
 const i=Math.floor((x-1024+16384)/256),j=Math.floor((y+4096+16384)/256);
 return [heights[j*129+i],heights[j*129+i+1],heights[(j+1)*129+i],heights[(j+1)*129+i+1]].every(h=>h===2);
}
function add(group,text){(counts[group]??=[]).push(text);additions.push(text);}
function prop(group,model,pos,angles,scales,tint,reference){
 const name=`valley_v3_${group}_${placements.length}`;
 add(group,`"CMapEntity" { "id" "elementid" "${guid()}" "nodeID" "int" "${node++}" "children" "element_array" [] "entity_properties" "EditGameClassProps" { "id" "elementid" "${guid()}" "classname" "string" "prop_static" "targetname" "string" "${name}" "model" "string" "${model}" "solid" "string" "0" "rendercolor" "string" "${tint.join(' ')}" "skin" "string" "0" "grass_exclusion_radius" "string" "0" } "origin" "vector3" "${pos.map(round).join(' ')}" "angles" "qangle" "${angles.map(round).join(' ')}" "scales" "vector3" "${scales.map(round).join(' ')}" "force_hidden" "bool" "0" "editorOnly" "bool" "0" }`);
 placements.push({name,group,model,origin:pos,angles,scales,tint,reference});
}
function place(group,g,i,pos,factor=1,rotation=0){
 const t=i.transform,s=[Math.hypot(t[0],t[4],t[8]),Math.hypot(t[1],t[5],t[9]),Math.hypot(t[2],t[6],t[10])];
 const angles=[Math.asin(-t[8]/s[0])*180/Math.PI,Math.atan2(t[4],t[0])*180/Math.PI+rotation,Math.atan2(t[9]/s[1],t[10]/s[2])*180/Math.PI];
 prop(group,g.model,pos,angles,s.map(v=>v*factor),i.tint,{origin:[t[3],t[7],t[11]],draw:i.draw});
}
const clamp=(x,a,b)=>Math.max(a,Math.min(b,x));
// Use the same local flower mesh, colors, orientation and clusters as the donor.
// Only the coordinate fit and surface elevation differ with our arena footprint.
for(const g of source.filter(g=>(imported.includes(g.model)&&!/crypt_|stone_wall/.test(g.model))||/tree_cypress001\.vmdl$/.test(g.model)))for(const i of g.instances){
 if(!i.transform)continue;const t=i.transform,rx=t[3],ry=t[7],ax=Math.abs(rx),ay=Math.abs(ry);
 if(ax<450&&ay<1250||ay<450&&ax<1250)continue;
 let x,y,z,group;
 if(Math.min(ax,ay)<400&&Math.max(ax,ay)>1250){
  const r=1450+(Math.max(ax,ay)-1250)*.43,s=(ax<ay?rx:ry)*.85;
  if(r>2780||Math.abs(s)<155||Math.abs(s)>305)continue;
  [x,y]=ax<ay?[s,Math.sign(ry)*r]:[Math.sign(rx)*r,s];z=130+clamp(t[11]-152,-3,15);group='corridor_reference';
 }else{
  x=Math.sign(rx)*(540+(ax-450)*.58);y=Math.sign(ry)*(540+(ay-450)*.58);
  if(Math.min(Math.abs(x),Math.abs(y))<580||Math.max(Math.abs(x),Math.abs(y))>2900||!plateau(x,y))continue;
  // Our existing carved emblems occupy different positions from the donor's.
  // Keep their centers legible while retaining the surrounding flower groups.
  if([[1550,1170],[1170,-1550],[-1550,-1170],[-1170,1550]].some(([ex,ey])=>Math.hypot(x-ex,y-ey)<200))continue;
  z=386+clamp(t[11]-264,-4,12);group='meadow_reference';
 }
 if(/tree_cypress001\.vmdl$/.test(g.model)){
  if(group!=='meadow_reference'||Math.max(ax,ay)>2700||Math.min(ax,ay)<600)continue;
  if(i.draw!==2&&Math.min(ax,ay)>1100&&Math.max(ax,ay)<2300)continue;
  place('topiary_reference',{model:'models/survival_valley/reference_topiary_'+i.draw+'.vmdl'},i,[x-1024,y+4096,z],.85);
 }else place(group,g,i,[x-1024,y+4096,z],.85);
}
// Repeat one intact NE spawn ensemble, rotated into each existing lane.
// This preserves the reference's three-sided crypt basin and paired statues.
const rot=(x,y,k)=>[[x,y],[y,-x],[-x,-y],[-y,x]][k],fit=.78;
const treeSource=source.find(g=>/tree_cypress001\.vmdl$/.test(g.model));
const roundTree=treeSource.instances.find(i=>i.draw===2&&Math.abs(i.transform[3]-1132)<1&&Math.abs(i.transform[7]-328)<1);
if(!roundTree)throw Error('Reference inner-corner round topiary missing');
for(let k=0;k<4;k++){
 const [x,y]=rot(1120,700,k);
 place('topiary_reference',{model:'models/survival_valley/reference_topiary_2.vmdl'},roundTree,[x-1024,y+4096,386],.85,-90*k);
}
for(let k=0;k<4;k++){
 for(const g of source.filter(g=>imported.includes(g.model)&&/_(crypt_door_01|crypt_statue_01)\.vmdl$/.test(g.model)))for(const i of g.instances){
  const t=i.transform;if(t[3]<250||t[3]>1100||t[7]<250||t[7]>1100)continue;
  const [x,y]=rot((t[3]-672)*fit,1112+(t[7]-672)*fit,k);
  place('spawn_reference_'+k,g,i,[x-1024,y+4096,128+(t[11]-168)*fit],fit,-90*k);
 }
 // A low, broad slab floor inside the three source stone walls; open exit.
 const quads=[];
 const q=(x0,y0,x1,y1,z)=>[[x0,y0],[x1,y0],[x1,y1],[x0,y1]].map(([x,y])=>{let p=rot(x,y+1112,k);return[p[0]-1024,p[1]+4096,z];});
 for(let y=-230;y<260;y+=35)for(let x=-245;x<245;x+=35)quads.push(q(x,y,x+35,y+35,131));
 let floor=M.mesh(quads,'maps/ti10_assets/blends/mod_radiant_ti10_angled_000.vmat',node++,()=>({blend:[0,.08,.92,.5],tint:[.82,.87,.9,0]}));
 add('spawn_reference_'+k,L.setValue(floor,'physicsType','none'));
 for(const side of [-1,1]){
  const [x,y]=rot(side*200,1400,k);
  prop('spawn_reference_'+k,'models/props_debris/candles001.vmdl',[x-1024,y+4096,136],[0,-90*k,0],[.7,.7,.7],[255,255,255],null);
 }
}
// Grass/stone vertex blending on the flat raised courts. This also replaces
// the old dirt and small-cobble courts without repainting unrelated islands.
for(let k=0;k<4;k++){
 const quads=[];
 for(let y=384;y<3040;y+=32)for(let x=384;x<3040;x+=32){
  const corners=[[x,y],[x+32,y],[x+32,y+32],[x,y+32]].map(p=>rot(...p,k));
  if(corners.some(([px,py])=>!surface(px,py)))continue;
  quads.push(corners.map(([px,py])=>[px-1024,py+4096,385.5]));
 }
 let mesh=M.mesh(quads,'maps/ti10_assets/blends/mod_radiant_ti10_angled_000.vmat',node++,(wx,wy)=>{
  const x=wx+1024,y=wy-4096,n=.5+.24*Math.sin(x*.003+y*.0013)+.18*Math.cos(y*.005-x*.002);
  const stone=clamp((Math.sin(x*.016+Math.sin(y*.007)*1.8)*Math.cos(y*.019-x*.002)-.63)*1.3,0,.42);
  return{blend:[.08+(.1*n),1-stone,stone,.5],tint:[.76+n*.08,.90+n*.06,.90+n*.05,1]};
 });
 add('meadow_ground_'+k,L.setValue(mesh,'physicsType','none'));
}
const groups=Object.entries(counts).map(([name,children])=>`"CMapGroup" { "id" "elementid" "${guid()}" "nodeID" "int" "${node++}" "name" "string" "valley_v3_${name}" "children" "element_array" [${children.join(',\n')}] "origin" "vector3" "0 0 0" "angles" "qangle" "0 0 0" "scales" "vector3" "1 1 1" }`);
const w=result.indexOf('"CMapWorld"'),a=result.indexOf('[',result.indexOf('"children" "element_array"',w)),e=L.endOf(result,a,'[',']')-1;
result=result.slice(0,e)+',\n'+groups.join(',\n')+'\n'+result.slice(e);
if(L.blocks(result,'CDmeDotaTileGrid')[0].text!==grid)throw Error('Tile terrain/nav modified');
for(const b of L.blocks(before,'CMapEntity').filter(b=>/^monsterborn_player/.test(L.value(b.text,'targetname')||'')))if(!result.includes(b.text))throw Error('Spawn marker changed');
fs.writeFileSync(path.join(out,'review.vmap'),result);
fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify({revision:3,removed,groups:Object.fromEntries(Object.entries(counts).map(([k,v])=>[k,v.length])),placements,terrain_navigation_preserved:true,layout:'Reference local transforms fitted to our existing arena; not a 1:1 copy of the entire reference map.'},null,2));
const paletteModels=new Map();
for(const text of additions){const model=L.value(text,'model');if(model&&!paletteModels.has(model))paletteModels.set(model,text);}
// Include the third source variant even when the fitted scene uses only two.
const cone=paletteModels.get('models/survival_valley/reference_topiary_1.vmdl');
paletteModels.set('models/survival_valley/reference_topiary_0.vmdl',L.setValue(cone,'model','models/survival_valley/reference_topiary_0.vmdl'));
let index=0;
const palette=[...paletteModels].map(([model,text])=>{
 text=text.replace(/"elementid" "[^"]+"/g,()=>`"elementid" "${guid()}"`);
 text=L.setValue(text,'nodeID',++index);text=L.setValue(text,'origin',`${(index-1)%4*360} ${Math.floor((index-1)/4)*440} 0`);
 text=L.setValue(text,'angles','0 0 0');text=L.setValue(text,'targetname','reference_palette_'+model.split('/').pop().replace('.vmdl',''));
 return text;
});
fs.writeFileSync(path.join(out,'reference_asset_palette.vmap'),`<!-- dmx encoding keyvalues2 1 format vmap 29 -->\n"CMapRootElement" { "id" "elementid" "${guid()}" "mapVersion" "int" "1" "world" "CMapWorld" { "id" "elementid" "${guid()}" "nodeID" "int" "${index+1}" "children" "element_array" [${palette.join(',\n')}] "entity_properties" "EditGameClassProps" { "id" "elementid" "${guid()}" "classname" "string" "worldspawn" } } }`);
console.log({props:placements.length,groups:Object.fromEntries(Object.entries(counts).map(([k,v])=>[k,v.length]))});
