'use strict';
// The donor aggregates three separate topiary meshes. Split their draw calls;
// instancing the whole aggregate would stack three different trees together.
const fs=require('fs'),path=require('path');
const out=path.resolve(__dirname,'../../output/valley_reference_v3');
const dest=path.join(out,'source/models/survival_valley');fs.mkdirSync(dest,{recursive:true});
function load(name){const g=JSON.parse(fs.readFileSync(path.join(out,name+'.gltf'))),b=fs.readFileSync(path.join(out,g.buffers[0].uri));return {g,read(index){const a=g.accessors[index],v=g.bufferViews[a.bufferView],n={SCALAR:1,VEC2:2,VEC3:3,VEC4:4}[a.type],base=(v.byteOffset||0)+(a.byteOffset||0);return Array.from({length:a.count},(_,j)=>Array.from({length:n},(_,k)=>a.componentType===5126?b.readFloatLE(base+j*(v.byteStride||n*4)+k*4):b.readUInt32LE(base+j*(v.byteStride||n*4)+k*4)));}};}
const parts=[load('cypress'),load('cypress_trunk')];
for(let draw=0;draw<3;draw++){
 const name='reference_topiary_'+draw,lines=['mtllib '+name+'.mtl'];let offset=0;const bounds=[Infinity,Infinity,Infinity,-Infinity,-Infinity,-Infinity];
 for(let part=0;part<parts.length;part++){
  const data=parts[part],p=data.g.meshes[0].primitives[draw],pos=data.read(p.attributes.POSITION),uv=data.read(p.attributes.TEXCOORD_0),normal=data.read(p.attributes.NORMAL),indices=data.read(p.indices).flat(),used=[...new Set(indices)],map=new Map(used.map((v,i)=>[v,i+offset+1]));
  lines.push('o '+(part?'trunk':'leaves'),'usemtl '+(part?'trunk':'leaves'));
  for(const i of used){const p=pos[i],v=[p[0]/.0254,p[1]/.0254,p[2]/.0254];v.forEach((n,j)=>{bounds[j]=Math.min(bounds[j],n);bounds[j+3]=Math.max(bounds[j+3],n);});lines.push('v '+v.join(' '));}
  for(const i of used)lines.push('vt '+uv[i][0]+' '+(1-uv[i][1]));
  for(const i of used){const n=normal[i];lines.push(`vn ${n[0]} ${n[1]} ${n[2]}`);}
  for(let j=0;j<indices.length;j+=3)lines.push('f '+indices.slice(j,j+3).map(i=>`${map.get(i)}/${map.get(i)}/${map.get(i)}`).join(' '));
  offset+=used.length;
 }
 fs.writeFileSync(path.join(dest,name+'.obj'),lines.join('\n'));
 fs.writeFileSync(path.join(dest,name+'.mtl'),'newmtl leaves\nKd 1 1 1\nnewmtl trunk\nKd 1 1 1\n');
 fs.writeFileSync(path.join(dest,name+'.vmdl'),`<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:modeldoc28:version{fb63b6ca-f435-4aa0-a2c7-c66ddc651dca} -->\n{rootNode={_class="RootNode" children=[{_class="RenderMeshList" children=[{_class="RenderMeshFile" name="${name}" filename="models/survival_valley/${name}.obj" import_scale=1}]},{_class="MaterialGroupList" children=[{_class="DefaultMaterialGroup" remaps=[{from="leaves" to="materials/models/props_tree/cypress/tree_cypress001.vmat"},{from="trunk" to="materials/models/props_tree/cypress/tree_cypress001_block.vmat"}] use_global_default=false}]}]}}`);
 console.log({draw,vertices:offset,bounds});
}
