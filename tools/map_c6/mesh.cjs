// Editable Hammer polygon meshes with Valve's vertex-paint streams.
// The topology schema is taken from the installed Radiant water tile.
const fs=require('fs'),path=require('path'),crypto=require('crypto'),L=require('./lib.cjs');
const template=fs.readFileSync(path.join(__dirname,'water_surface.vmap'),'utf8');
const uid=()=>crypto.randomUUID();
const stream=(name,type,data,loc=0)=>`"CDmePolygonMeshDataStream" { "id" "elementid" "${uid()}" "name" "string" "${name}:0" "standardAttributeName" "string" "${name.startsWith('VertexPaint')?'':name}" "semanticName" "string" "${name}" "semanticIndex" "int" "0" "vertexBufferLocation" "int" "${loc}" "dataStateFlags" "int" "1" "subdivisionBinding" "element" "" "data" "${type}_array" [${data.map(v=>'"'+v+'"').join(',')}] }`;
function mesh(quads,material,nodeID,paint){
 if(quads.some(q=>q.length!==4||q.some(p=>p.length!==3||p.some(v=>!Number.isFinite(v)))))
  throw new Error('Invalid terrain coordinates for mesh '+nodeID+' ('+material+')');
 let s=template.replace(/"elementid" "[a-f0-9-]+"/g,()=>`"elementid" "${uid()}"`);
 s=L.setValue(L.setValue(s,'nodeID',nodeID),'origin','0 0 0');
 s=s.replace(/"referenceID" "uint64" "[^"]*"/,'"referenceID" "uint64" "0x0"');
 const n=quads.length,arrays={};
 const specs={vertexEdgeIndices:[[6,1,3,5],8],vertexDataIndices:[[0,1,2,3],4],edgeVertexIndices:[[1,0,2,1,3,2,3,0],4],edgeOppositeIndices:[[1,0,3,2,5,4,7,6],8],edgeNextIndices:[[2,6,4,1,7,3,5,0],8],edgeFaceIndices:[[0,-1,0,-1,0,-1,-1,0],1],edgeDataIndices:[[0,0,1,1,2,2,3,3],4],edgeVertexDataIndices:[[5,1,4,2,0,3,7,6],8],faceEdgeIndices:[[7],8],faceDataIndices:[[0],1]};
 for(const [k,[base,step]] of Object.entries(specs))arrays[k]=quads.flatMap((_,i)=>base.map(v=>v<0?v:v+i*step));
 for(const [k,v] of Object.entries(arrays))s=L.setArray(s,k,v);
 s=L.setArray(s,'materials',[material]);
 const positions=quads.flat().map(p=>p.join(' '));
 const uv=[],normals=[],tangents=[],blends=[],tints=[],blend1=[];
 for(const q of quads){
  const a=q[0],b=q[1],c=q[2],u=b.map((v,i)=>v-a[i]),v=c.map((v,i)=>v-a[i]);
  let normal=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]],len=Math.hypot(...normal)||1;normal=normal.map(v=>v/len);
  // Match edgeVertexDataIndices of the original quad.
  for(const vi of [3,0,1,2,2,1,0,3]){
   const p=q[vi],color=paint?paint(...p):{blend:[0,1,0,.3],tint:[1,1,1,0]};
   // Vertical/steep rock faces need vertical UVs; XY-only mapping stretched
   // their texture into stripes and made the old retaining edge look artificial.
   const axis=normal.map(Math.abs),vertical=axis[2]<.65;
   uv.push(vertical?(axis[0]>axis[1]?`${p[1]/256} ${-p[2]/256}`:`${p[0]/256} ${-p[2]/256}`):`${p[0]/256} ${-p[1]/256}`);
   normals.push(normal.join(' '));tangents.push(vertical&&axis[0]>axis[1]?'0 1 0 -1':'1 0 0 -1');
   blends.push(color.blend.join(' '));tints.push(color.tint.join(' '));blend1.push('.5 .5 .5 0');
  }
 }
 const data={vertexData:[n*4,[stream('position','vector3',positions)]],faceVertexData:[n*8,[stream('texcoord','vector2',uv),stream('normal','vector3',normals),stream('tangent','vector4',tangents),stream('VertexPaintTintColor','vector4',tints,1),stream('VertexPaintBlendParams','vector4',blends,1),stream('VertexPaintBlendParams1','vector4',blend1,1)]],edgeData:[n*4,[stream('flags','int',Array(n*4).fill(0))]],faceData:[n,[stream('textureScale','vector2',Array(n).fill('1 1')),stream('textureAxisU','vector4',Array(n).fill('1 0 0 0')),stream('textureAxisV','vector4',Array(n).fill('0 -1 0 0')),stream('materialindex','int',Array(n).fill(0)),stream('flags','int',Array(n).fill(0)),stream('lightmapScaleBias','int',Array(n).fill(0))]]};
 for(const [key,[size,streams]] of Object.entries(data)){
  const start=s.indexOf('"'+key+'" "CDmePolygonMeshDataArray"'),end=L.endOf(s,s.indexOf('{',start));
  s=s.slice(0,start)+`"${key}" "CDmePolygonMeshDataArray" { "id" "elementid" "${uid()}" "size" "int" "${size}" "streams" "element_array" [${streams.join(',')}] }`+s.slice(end);
 }
 return s;
}
module.exports={mesh};
