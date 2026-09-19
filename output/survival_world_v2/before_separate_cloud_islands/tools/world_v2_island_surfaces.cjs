// Use the exact Valve materials referenced by radiant_basic.vmap.
// Preserve the existing cap subdivision, outline, height, and collision volume.
// Entire island surfaces now use the same native old-stone paving layer.
function nativeIslandPrism(p,z,bottom,kind='bank'){
 const boundary=[];
 for(let i=0;i<p.length;i++){
  const a=p[i],b=p[(i+1)%p.length],n=Math.ceil(Math.hypot(b[0]-a[0],b[1]-a[1])/80);
  for(let j=0;j<n;j++)boundary.push([a[0]+(b[0]-a[0])*j/n,a[1]+(b[1]-a[1])*j/n]);
 }
 const c=p.reduce((s,v)=>[s[0]+v[0]/p.length,s[1]+v[1]/p.length],[0,0]);
 const n=boundary.length,verts=[],faces=[];
 // Three concentric rings keep shared vertices watertight and all top faces flat.
 for(const scale of [1,2/3,1/3])for(const v of boundary)verts.push([c[0]+(v[0]-c[0])*scale,c[1]+(v[1]-c[1])*scale,z]);
 const center=verts.length;verts.push([...c,z]);
 for(let ring=0;ring<2;ring++)for(let i=0;i<n;i++){
  const a=ring*n+i,b=ring*n+(i+1)%n,d=(ring+1)*n+i,e=(ring+1)*n+(i+1)%n;
  faces.push({v:[a,b,e],m:0},{v:[a,e,d],m:0});
 }
 for(let i=0;i<n;i++)faces.push({v:[2*n+i,2*n+(i+1)%n,center],m:0});
 const lower=verts.length;for(const v of boundary)verts.push([...v,bottom]);
 const floorCenter=verts.length;verts.push([...c,bottom]);
 for(let i=0;i<n;i++){
  const next=(i+1)%n;
  faces.push({v:[lower+i,lower+next,next,i],m:1},{v:[floorCenter,lower+next,lower+i],m:1});
 }
 const previous=paintVertex;
 // Layer 3 is old stone on top and cliff rock on the side material.
 // All original island lawns are also painted to their paving layer.
 paintVertex=()=>[0,0,1,0];
 mesh(verts,faces,['materials/survival_world_v2/island_native_paving.vmat','materials/blends/mod_radiant_000.vmat'],'255 255 255 255');
 paintVertex=previous;
}
