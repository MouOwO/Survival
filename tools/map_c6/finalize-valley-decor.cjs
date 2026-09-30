// Preserve existing geometry/markers and add only the reviewed art layer.
'use strict';
const fs=require('fs'),path=require('path'),crypto=require('crypto'),L=require('./lib.cjs');
const root=path.resolve(__dirname,'../..'),out=path.join(root,'output/valley_decor_v1');
const before=fs.readFileSync(path.join(out,'before.vmap'),'utf8');
const {placements,portals,particle}=JSON.parse(fs.readFileSync(path.join(out,'placements.json'),'utf8'));
const log=fs.readFileSync(path.join(out,'preview.log'),'utf8');
const heights=new Map([...log.matchAll(/VALLEY_PLACEMENT\s+(valley_decor_v1_\d+)\s+([\d.-]+)/g)].map(m=>[m[1],+m[2]]));
if(heights.size!==placements.length)throw Error('Require a complete current Workshop placement/ground probe.');
let node=Math.max(...[...before.matchAll(/"nodeID" "int" "(\d+)"/g)].map(m=>+m[1]))+1;
const additions=[],manifest=[];
function entity(cls,name,origin,props,scale=1,yaw=0){
 const guid=()=>crypto.randomUUID();
 additions.push(`"CMapEntity" { "id" "elementid" "${guid()}" "nodeID" "int" "${node++}" "children" "element_array" [] "entity_properties" "EditGameClassProps" { "id" "elementid" "${guid()}" ${Object.entries({classname:cls,targetname:name,...props}).map(([k,v])=>`"${k}" "string" "${v}"`).join(' ')} } "origin" "vector3" "${origin.join(' ')}" "angles" "qangle" "0 ${yaw} 0" "scales" "vector3" "${scale} ${scale} ${scale}" "force_hidden" "bool" "0" "editorOnly" "bool" "0" }`);
 manifest.push({cls,name,origin,...props,scale,yaw});
}
for(const p of placements){
 const origin=[p.origin[0],p.origin[1],heights.get(p.name)];
 entity('prop_static',p.name,origin,{model:p.model,solid:'0',rendercolor:p.color,skin:'0',grass_exclusion_radius:'0',disablemerging:'0'},p.scale,p.yaw);
}
for(const p of portals)entity('info_particle_system','valley_decor_v1_fx_'+p.marker,[p.origin[0],p.origin[1],132],{effect_name:particle,start_active:'1'});
const g=L.blocks(before,'CDmeDotaTileGrid')[0];
let grid=g.text,painted=0;
const opacity=L.array(grid,'blendOpacity'),color=L.array(grid,'blendColor'),grass=L.array(grid,'grassOpacity');
if(opacity.length!==1025*1025)throw Error('Unexpected paint resolution.');
const clamp=(v,a=0,b=1)=>Math.max(a,Math.min(b,v));
for(let j=0;j<1025;j++)for(let i=0;i<1025;i++){
 const x=i*32-16384+1024,y=j*32-16384-4096,r=Math.hypot(x,y);
 if(r<820||r>2700)continue;
 const idx=j*1025+i,old=opacity[idx].split(' ').map(Number);
 // Keep the stone court, stone walls, coast, other islands and existing paths.
 if(old[1]<190||old[2]>30)continue;
 const ax=Math.abs(x),ay=Math.abs(y),major=Math.max(ax,ay),minor=Math.min(ax,ay);
 const n=clamp(.5+.23*Math.sin(x*.004+y*.002)+.17*Math.sin(y*.007-x*.003)+.1*Math.sin(x*.017+y*.009));
 const wear=major>1050&&major<2160?clamp(1-Math.abs(minor-18*Math.sin(major*.004))/150):0;
 const green=Math.round(215+n*38-wear*125);
 opacity[idx]=`${Math.round(8+n*26)} ${green} 0 ${old[3]}`;
 color[idx]=`${Math.round(226+n*24)} ${Math.round(238+n*15)} ${Math.round(210+n*25)} 28`;
 grass[idx]=String(Math.round((65+n*65)*(1-wear*.9)));
 painted++;
}
grid=L.setArray(grid,'blendOpacity',opacity);grid=L.setArray(grid,'blendColor',color);grid=L.setArray(grid,'grassOpacity',grass);
let result=before.slice(0,g.start)+grid+before.slice(g.end);
const world=result.indexOf('"CMapWorld"'),start=result.indexOf('[',result.indexOf('"children" "element_array"',world)),end=L.endOf(result,start,'[',']')-1;
result=result.slice(0,end)+',\n'+additions.join(',\n')+'\n'+result.slice(end);
// All pre-existing entities/meshes and the gameplay arrays must survive intact.
for(const type of ['CMapEntity','CMapMesh']){
 const after=new Map(L.blocks(result,type).map(e=>[L.value(e.text,'nodeID'),e.text]));
 for(const e of L.blocks(before,type))if(after.get(L.value(e.text,'nodeID'))!==e.text)throw Error('Existing '+type+' changed.');
}
for(const key of ['verticesHeight','verticesWater','gridnavFlags','cellConfiguration','objectsTreeType'])if(JSON.stringify(L.array(g.text,key))!==JSON.stringify(L.array(grid,key)))throw Error('Gameplay array changed '+key);
fs.writeFileSync(path.join(out,'template_valley.vmap'),result);
fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify({baseline_sha256:crypto.createHash('sha256').update(before).digest('hex'),painted_samples:painted,props:placements.length,particles:portals.length,existing_entities_and_meshes_preserved:true,navigation_and_height_preserved:true,additions:manifest},null,2));
console.log(JSON.stringify({painted_samples:painted,props:placements.length,particles:portals.length,geometry_preserved:true}));
