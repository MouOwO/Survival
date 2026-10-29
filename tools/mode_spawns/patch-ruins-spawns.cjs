// Add/update only the nine ruins markers in the current saved Hammer source.
'use strict';
const fs=require('fs'),crypto=require('crypto'),assert=require('assert/strict'),L=require('../map_c6/lib.cjs');
const [input,output]=process.argv.slice(2);assert(input&&output&&input!==output);
const source=fs.readFileSync(input,'utf8');assert(source.slice(0,100).includes('encoding keyvalues2'));
const row=JSON.parse(fs.readFileSync('art/maps/mode_spawns/layout.json','utf8')).modes.ruins;
const entities=L.blocks(source,'CMapEntity'),edits=[],additions=[],names=[];
let node=Math.max(...[...source.matchAll(/"nodeID" "int" "(\d+)"/g)].map(m=>+m[1]))+1;
for(const [kind,points] of [['center',[row.center]],['player',row.players],['monster',row.monsters]])points.forEach((p,id)=>{
 const name=kind==='center'?'ruins_start':`mode_ruins_${kind}_${id}_spawn`,origin=[p[0],p[1],p[2]+16].join(' ');
 names.push(name);const matches=entities.filter(b=>L.value(b.text,'targetname')===name);assert(matches.length<=1);
 if(matches.length){const b=matches[0];assert.equal(L.value(b.text,'classname'),'info_target');edits.push({...b,text:L.setValue(b.text,'origin',origin)});}
 else additions.push(`"CMapEntity" { "id" "elementid" "${crypto.randomUUID()}" "nodeID" "int" "${node++}"\n`
  +`"children" "element_array" [] "entity_properties" "EditGameClassProps" { "id" "elementid" "${crypto.randomUUID()}" `
  +`"classname" "string" "info_target" "targetname" "string" "${name}" }\n`
  +`"origin" "vector3" "${origin}" "angles" "qangle" "0 0 0" "scales" "vector3" "1 1 1" "force_hidden" "bool" "0" "editorOnly" "bool" "0" }`);
});
edits.sort((a,b)=>a.start-b.start);let cursor=0;const parts=[];
for(const b of edits){parts.push(source.slice(cursor,b.start),b.text);cursor=b.end;}parts.push(source.slice(cursor));let result=parts.join('');
if(additions.length){const world=result.indexOf('"world" "CMapWorld"');assert(world>=0);
 const start=result.indexOf('[',result.indexOf('"children" "element_array"',world)),end=L.endOf(result,start,'[',']')-1;
 result=result.slice(0,end).replace(/,\s*$/,'')+',\n'+additions.join(',\n')+'\n'+result.slice(end);
}
const afterEntities=L.blocks(result,'CMapEntity');
const byNode=new Map(afterEntities.map(b=>[L.value(b.text,'nodeID'),b.text]));
for(const entity of entities){const name=L.value(entity.text,'targetname');if(names.includes(name))continue;
 assert.equal(byNode.get(L.value(entity.text,'nodeID')),entity.text,'Existing entity changed: '+name);}
for(const type of ['CDmeDotaTileGrid','CMapDotaTileGrid','CMapMesh']){
 const before=L.blocks(source,type),after=L.blocks(result,type);assert.equal(after.length,before.length);
 before.forEach((block,i)=>assert.equal(after[i].text,block.text,'Existing terrain/mesh changed'));
}
assert.equal(afterEntities.length,entities.length+additions.length);
fs.writeFileSync(output,result);
fs.writeFileSync(output+'.json',JSON.stringify({source_sha256:crypto.createHash('sha256').update(source).digest('hex'),
 markers:names,added:additions.length,updated:edits.length,all_existing_entities_terrain_meshes_preserved:true},null,2)+'\n');
console.log('RUINS_MAP_PATCH_PASS: nine own markers; existing entities, terrain/navigation and meshes preserved');
