// Included in the generator's scope. One triangulated surface per ground level;
// adjacent textures share vertices and opacity gradients instead of overlapping plates.
const clamp=v=>Math.max(0,Math.min(1,v));
const smooth=v=>{v=clamp(v);return v*v*(3-2*v);};
function edgeDistance(x,y,p){let d=Infinity;for(let i=0;i<p.length;i++){const a=p[i],b=p[(i+1)%p.length],dx=b[0]-a[0],dy=b[1]-a[1],t=clamp(((x-a[0])*dx+(y-a[1])*dy)/(dx*dx+dy*dy||1));d=Math.min(d,Math.hypot(x-a[0]-dx*t,y-a[1]-dy*t));}return d;}
function variation(x,y){return .5+.22*Math.sin(x/340+y/513)+.17*Math.cos(y/257-x/617);}
function theme(a){if(a.name.includes('n41_50_camp'))return 'thaw';if(a.material===M.snow||a.name.includes('polar_crystal')||a.name.includes('ice_elegy'))return 'snow';if(a.material===M.lava)return 'volcanic';if(a.material===M.corrupt)return 'corrupt';return 'forest';}
const level=a=>Math.ceil(a.z/128)*128;
const groundRoots=land.filter((a,i)=>!a.nativeReuse&&!land.slice(0,i).some(b=>level(b)===level(a)&&a.polygon.every(v=>inside(v[0],v[1],b.polygon))));
function groundPaint(a,x,y){
 const b=at(x,y),n=variation(x,y),d=edgeDistance(x,y,a.polygon),t=theme(a);
 const local=b&&level(b)===level(a)?b:a;
 const inward=smooth((edgeDistance(x,y,local.polygon)-30+(n-.5)*110)/280);
 if(t==='volcanic'){const inner=smooth((d-100+(n-.5)*140)/360);return [0,.16+.12*n,inner*(.12+.20*n),inner*.22*smooth((n-.45)*2)];}
 if(t==='corrupt')return [0,1-smooth((d-30)/360),.20+.38*n,0];
 if(t==='snow'){const inner=smooth((d-20+(n-.5)*90)/260);return [0,.15+.82*inner,.10*n*inner,0];}
 if(t==='thaw')return [0,smooth((d-40)/300),.25*(1-smooth(d/320)),0];
 if(local.shallow||a.name==='n01_10_island'&&Math.max(Math.abs(x-X(158)),Math.abs(y-Y(79)))<1350){
   const shore=smooth((Math.max(Math.abs(x-X(158)),Math.abs(y-Y(79)))-900)/440);
   return [0,shore*.90,(1-shore)*.55,0];
 }
 const stone=local.material===M.paving||local.material===M.stone;
 if(stone)return [0,1-inward,.45*inward*(1-inward),inward*.96];
 if(local.material===M.dirt)return [0,(1-inward)*.88,.13*n,0];
 // Worn earth and gravel follow the shore and vegetation margin, irregularly.
 const edge=smooth((d-28)/230);return [0,.76+.20*n-.30*(1-edge),.12*(1-edge),0];
}
function groundMesh(a){
 const source=a.polygon,p=[];
 // Subdivide outline and rings so blends are resolved at approximately 128 units.
 for(let i=0;i<source.length;i++){const u=source[i],v=source[(i+1)%source.length],steps=Math.max(1,Math.ceil(Math.hypot(v[0]-u[0],v[1]-u[1])/128));for(let j=0;j<steps;j++)p.push([u[0]+(v[0]-u[0])*j/steps,u[1]+(v[1]-u[1])*j/steps]);}
 const c=source.reduce((s,v)=>[s[0]+v[0]/source.length,s[1]+v[1]/source.length],[0,0]);
 const n=p.length,rings=Math.max(3,Math.ceil(Math.max(...p.map(v=>Math.hypot(v[0]-c[0],v[1]-c[1])))/160)),z=level(a)+12;
 const verts=[[c[0],c[1],z]],faces=[];
 for(let r=1;r<=rings;r++)for(const v of p)verts.push([c[0]+(v[0]-c[0])*r/rings,c[1]+(v[1]-c[1])*r/rings,z]);
 for(let j=0;j<n;j++)faces.push({v:[0,1+j,1+(j+1)%n],m:0});
 for(let r=1;r<rings;r++)for(let j=0;j<n;j++){const a0=1+(r-1)*n+j,b0=1+(r-1)*n+(j+1)%n,a1=1+r*n+j,b1=1+r*n+(j+1)%n;faces.push({v:[a0,a1,b1],m:0},{v:[a0,b1,b0],m:0});}
 // Closed underside uses tool material, never a second coplanar visible surface.
 const bottom=verts.length;verts.push([c[0],c[1],z-160]);for(const v of p)verts.push([v[0],v[1],z-160]);
 const top=1+(rings-1)*n;for(let j=0;j<n;j++){const k=(j+1)%n;faces.push({v:[bottom,bottom+1+k,bottom+1+j],m:1},{v:[top+j,bottom+1+j,bottom+1+k,top+k],m:1});}
 // Multiblend stores layers 1/2/3 in XYZ; layer 0 is the remainder.
 // W is reserved. Passing four explicit layer opacities shifts every texture.
 paintVertex=v=>{const w=groundPaint(a,v[0],v[1]);return [w[1],w[2],w[3],0];};
 mesh(verts,faces,['materials/survival_world_v2/transition_'+theme(a)+'.vmat','materials/tools/toolsnodraw.vmat'],'255 255 255 255');paintVertex=null;
}
for(const a of groundRoots)groundMesh(a);
const shallow=terrainPaint.find(a=>a.shallow);
if(shallow){
 prism(shallow.polygon,396,370,'materials/survival_world_v2/transition_forest.vmat','materials/tools/toolsnodraw.vmat','255 255 255 255');
 prism(shallow.polygon,416,414,'materials/survival_world_v2/shallow_water.vmat','materials/tools/toolsnodraw.vmat','255 255 255 255');
}
fs.writeFileSync(path.join(OUT,'surface_design.json'),JSON.stringify({mainIsland:'four rotated original U islands',sourceMap:'template_map.vmap',crossCenter:originalIsland.center,crossLength:3584,crossWidth:640,groundSurfaceZ:396,waterZ:416,transitionWidth:280,groundRoots:groundRoots.map(a=>({name:a.name,theme:theme(a),z:level(a)+12})),lilySource:'Native tileset entities; disabled in addon-local templates'},null,2));
