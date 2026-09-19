// Reconstruct the supporting body from the SAME vertex lattice as the native
// island tiles. Clip the shoreline at half a tile instead of sloping an entire
// rectangular grid down into the sea. This removes exposed triangular shelves.
// Native high shoreline combinations omit part of their underwater floor.
// Keep a flat submerged floor underneath; it must never rise into shore shelves.
prism([[preserved[0],preserved[1]],[preserved[2],preserved[1]],[preserved[2],preserved[3]],[preserved[0],preserved[3]]],254,-512,'materials/survival_world_v2/transition_forest.vmat','materials/tools/toolsnodraw.vmat','255 255 255 255');
const foundationAudit=[];
function buildIslandFoundation(tier){
const foundationVerts=[],foundationFaces=[],foundationIds=new Map(),foundationBoundary=new Map();
function foundationVertex(p){
 const key=p.map(n=>n.toFixed(3)).join(',');
 if(!foundationIds.has(key)){foundationIds.set(key,foundationVerts.length);foundationVerts.push(p);}
 return foundationIds.get(key);
}
function foundationTriangle(ids){
 foundationFaces.push({v:ids,m:0});
 for(let i=0;i<3;i++){
  const a=ids[i],b=ids[(i+1)%3],reverse=b+','+a;
  if(foundationBoundary.has(reverse))foundationBoundary.delete(reverse);
  else foundationBoundary.set(a+','+b,[a,b]);
 }
}
function foundationSample(x,y){
 const h=originalIsland.height(x,y);
 const dx=Math.abs(x-originalIsland.center[0]),dy=Math.abs(y-originalIsland.center[1]),r=Math.max(dx,dy),v=Math.min(dx,dy);
 const customOrStairs=r<=3328&&v<1024;
 return {x,y,w:tier===3?(h>5&&!customOrStairs?1:0):(h>3?1:0)};
}
function foundationClip(triangle){
 const result=[];
 for(let i=0;i<3;i++){
  const a=triangle[i],b=triangle[(i+1)%3],ina=a.w>=.5,inb=b.w>=.5;
  if(ina)result.push(a);
  if(ina!==inb){const t=(.5-a.w)/(b.w-a.w);result.push({x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t,w:.5});}
 }
 if(result.length<3)return;
 const ids=result.map(p=>{
  const local=originalIsland.locate(p.x,p.y);
  const underEntrance=originalIsland.approach(p.x,p.y)&&local.x-originalIsland.pivot[0]<originalIsland.levels.stairEnd;
  return foundationVertex([p.x,p.y,originalIsland.shallow(p.x,p.y)||underEntrance?372:tier===3?766:638]);
 });
 for(let i=1;i+1<ids.length;i++)foundationTriangle([ids[0],ids[i],ids[i+1]]);
}
// Aligned to -16384 + n*256, matching survival_world_v2_native.cjs.
for(let y=-2560;y<7936;y+=256)for(let x=-6400;x<4096;x+=256){
 const a=foundationSample(x,y),b=foundationSample(x+256,y),c=foundationSample(x+256,y+256),d=foundationSample(x,y+256);
 foundationClip([a,b,c]);foundationClip([a,c,d]);
}
const foundationTopCount=foundationVerts.length,foundationTopFaces=foundationFaces.length;
for(let i=0;i<foundationTopCount;i++)foundationVerts.push([foundationVerts[i][0],foundationVerts[i][1],tier===3?620:160]);
// Mirror every top triangle. A fan across a concave bottom crosses the water lanes.
for(let i=0;i<foundationTopFaces;i++)foundationFaces.push({v:foundationFaces[i].v.slice().reverse().map(id=>id+foundationTopCount),m:1});
for(const [a,b]of foundationBoundary.values())foundationFaces.push({v:[b,a,a+foundationTopCount,b+foundationTopCount],m:2});
const oldFoundationPaint=paintVertex;
paintVertex=()=>[0,0,1,0];
mesh(foundationVerts,foundationFaces,['materials/survival_world_v2/island_native_paving.vmat','materials/tools/toolsnodraw.vmat','materials/survival_world_v2/island_masonry.vmat'],'255 255 255 255');
paintVertex=oldFoundationPaint;
foundationAudit.push({tier,top:tier===3?766:638,bottom:tier===3?620:160,topTriangles:foundationTopFaces,boundarySegments:foundationBoundary.size,vertices:foundationVerts.length});
}
buildIslandFoundation(2);buildIslandFoundation(3);
fs.writeFileSync(path.join(OUT,'island_foundation_design.json'),JSON.stringify({method:'two solid terrace foundations with vertical masonry faces',gridOrigin:-16384,gridStep:256,shoreThreshold:.5,tiers:foundationAudit,copingThickness:32,closed:true,entrances:'custom main and side stair envelopes excluded from upper foundation',removed:'bilinear rectangular slope shelves and cliff-projected platform side texture'},null,2));
