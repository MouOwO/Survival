// Cloud placement is authored from the same active-area polygons as the map.
// No collision, no depth-test bypass, and no cloud over the central island/cross.
const cloudArt={theme:'疏朗清晨云海',timeOfDay:.3,outer:[],inner:[],pavilions:[],pines:[],clearance:180,method:'Restored surrounding cloud sea and low horizontal banks between detached platforms',boundaryRingRestored:true};
const playable=land.filter(a=>!a.nativeReuse);
function activeDistance(x,y){
 if(nativePreserved(x,y))return 0;
 let d=Infinity;
 for(const a of playable){if(inside(x,y,a.polygon))return 0;d=Math.min(d,edgeDistance(x,y,a.polygon));}
 return d;
}
function cloudSafe(x,y,r){
 // Test the projected footprint too: high clouds lean toward the camera at
 // the normal Dota pitch. Internal bands have only a small elevation offset.
 return activeDistance(x,y)>r+180&&activeDistance(x,y-180)>r+180;
}
const cardHeader='<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->';
function footprintClearance(x,y,r,angle){
 // Conservatively include the transparent border and normal oblique camera
 // projection. Sample the interior too, not just the ellipse perimeter.
 let clearance=activeDistance(x,y),a=angle*Math.PI/180;
 for(const f of [.25,.5,.75,1])for(let i=0;i<24;i++){
  const t=i/24*Math.PI*2,u=Math.cos(t)*r*.92*f,v=Math.sin(t)*r*.62*f;
  const px=x+u*Math.cos(a)-v*Math.sin(a),py=y+u*Math.sin(a)+v*Math.cos(a);
  clearance=Math.min(clearance,activeDistance(px,py),activeDistance(px,py-250));
  if(Math.hypot((px-hotSpring.x)/1300,(py-hotSpring.y)/1100)<1.0)return 0;
 }
 return clearance;
}
function cloudCard(group,x,y,z,r,angle=0,alpha=.70){
 const low=group==='inner';
 const projectedClearance=footprintClearance(x,y,r,angle);
 // Low banks are horizontal and entirely below walkable floors. Opaque
 // platforms occlude them, so their footprints may extend under an island.
 if(!low&&projectedClearance<180)return;
 if(low&&nativePreserved(x,y))return;
 const target=group==='outer'?cloudArt.outer:cloudArt.inner,index=target.length;
 const name='cloud_bank_'+group+'_'+String(index).padStart(2,'0');
 const texture='cloud_native_'+(index%3===1?'b':'a');
 const value=(field,v)=>`{ _class = "C_INIT_InitFloat" m_nOutputField = ${field} m_InputValue = { m_nType = "PF_TYPE_LITERAL" m_flLiteralValue = ${Number(v).toFixed(5)} } }`;
 fs.writeFileSync(path.join(OUT,'source_particles',name+'.vpcf'),`${cardHeader}\n{
 _class = "CParticleSystemDefinition" m_nMaxParticles = 1 m_nInitialParticles = 1 m_flConstantRadius = ${r}.0
 m_ConstantColor = [ 224, 234, 239, 255 ] m_flMaxDrawDistance = 100000.0 m_bShouldSort = true
 m_BoundingBoxMin = [ -${r}.0, -${r}.0, -${r}.0 ] m_BoundingBoxMax = [ ${r}.0, ${r}.0, ${r}.0 ]
 m_Renderers = [ { _class = "C_OP_RenderSprites" m_nOrientationType = "${low?'PARTICLE_ORIENTATION_WORLD_Z_ALIGNED':'PARTICLE_ORIENTATION_SCREEN_ALIGNED'}"
 m_flStartFadeSize = 4.0 m_flEndFadeSize = 5.0 m_nFeatheringMode = "PARTICLE_DEPTH_FEATHERING_ON_OPTIONAL"
 m_flFeatheringMaxDist = { m_nType = "PF_TYPE_LITERAL" m_flLiteralValue = 100.0 }
 m_vecTexturesInput = [ { m_hTexture = resource:"materials/survival_world_v2/${texture}.vtex" } ] } ]
 m_Initializers = [ { _class = "C_INIT_CreateWithinSphere" m_fRadiusMin = 0.0 m_fRadiusMax = 0.0 }, ${value(1,100000)}, ${value(3,r)}, ${value(7,alpha)}, ${value(4,angle*Math.PI/180)} ]
 m_nBehaviorVersion = 5
}`);
 entity('info_particle_system','cultivation_'+name,[x,y,z],{effect_name:'particles/survival_world_v2/'+name+'.vpcf',start_active:'1'});
 target.push({x,y,z,r,angle,alpha,texture,projectedClearance,orientation:low?'horizontal below platforms':'billboard outside activities',topHeight:low?z:null});
}
// Restore the surrounding sea of clouds. Two offset tiers have different
// widths/elevations; all have a single large silhouette rather than 5 puffs.
for(let side=0;side<4;side++)for(let i=0;i<13;i++){
 const t=-19200+i*3200,r=2600+420*Math.sin(i*1.71+side),edge=18800+450*Math.sin(i*.91+side);
 const p=side===0?[t,edge]:side===1?[edge,t]:side===2?[t,-edge]:[-edge,t];
 cloudCard('outer',...p,-450+300*Math.sin(i*.8+side),Math.round(r),Math.sin(i+side)*13,.86);
 if(i%2===0){const p2=side===0?[t+900,edge+2600]:side===1?[edge+2600,t+900]:side===2?[t+900,-edge-2600]:[-edge-2600,t+900];cloudCard('outer',...p2,-1300,3600,(i%3-1)*11,.74);}
}
// Broad under-platform lanes replace the deleted mountain mass. They meet
// beneath island walls; their world-Z orientation never stands up across play.
const underBanks=[];
for(let i=0;i<9;i++){
 underBanks.push([-14300+i*3500,15250+Math.sin(i)*240,2350+(i%3)*160,i%2?8:-7]);
 underBanks.push([-11900+i*3300,-8350+Math.sin(i*.8)*180,2300+(i%3)*180,i%2?-8:6]);
}
for(let i=0;i<7;i++)underBanks.push([-10100+Math.sin(i)*160,10800-i*2600,2100+(i%2)*230,83+(i%3)*6]);
for(let i=0;i<5;i++)underBanks.push([8500+Math.sin(i)*200,10900-i*3200,2200+(i%2)*190,86]);
for(let i=0;i<5;i++)underBanks.push([3000+i*3000,-12600+Math.sin(i)*950,2650+(i%2)*270,i*7-12]);
underBanks.push([-14000,12300,2900,8],[-14800,3400,2100,85],[-14700,-3200,2300,3],[15100,-10300,2700,78],[850,-15000,2500,6]);
for(const [x,y,r,angle]of underBanks)cloudCard('inner',x,y,220,r,angle,.84);
// A non-colliding low atmospheric floor removes the black void between banks.
// Its broad shallow undulations sit below every water/land surface; it cannot
// create routes between islands or cover their fighting floors.
{
 const verts=[],faces=[],n=40,step=2400;
 for(let j=0;j<=n;j++)for(let i=0;i<=n;i++){
  const x=-48000+i*step,y=-48000+j*step;
  verts.push([x,y,50+30*Math.sin(x/5000+y/7000)+20*Math.cos(y/4000-x/8000)]);
 }
 const count=verts.length;for(let i=0;i<count;i++)verts.push([verts[i][0],verts[i][1],-160]);
 const ix=(x,y)=>y*(n+1)+x;
 for(let j=0;j<n;j++)for(let i=0;i<n;i++){
  const a=ix(i,j),b=ix(i+1,j),c=ix(i+1,j+1),d=ix(i,j+1);
  faces.push({v:[a,b,c],m:0},{v:[a,c,d],m:0},{v:[d+count,c+count,b+count,a+count],m:1});
 }
 const wall=(a,b)=>faces.push({v:[b,a,a+count,b+count],m:1});
 for(let i=0;i<n;i++){wall(ix(i,0),ix(i+1,0));wall(ix(i+1,n),ix(i,n));wall(ix(n,i),ix(n,i+1));wall(ix(0,i+1),ix(0,i));}
 mesh(verts,faces,['materials/survival_world_v2/cloud_sea_base.vmat','materials/tools/toolsnodraw.vmat'],'255 255 255 255','none');
 cloudArt.atmosphericBase={collision:'none',maxHeight:100,bounds:[-48000,-48000,48000,48000]};
}
// Open teal-roof pavilions sit in decorative margins, away from all spawn marks.
function pavilion(x,y,scale=1.15){
 if(markers.some(m=>Math.hypot(x-m.x,y-m.y)<950)||cloudArt.pavilions.some(p=>Math.hypot(p.x-x,p.y-y)<1600))return;
 const z=surface(x,y);entity('prop_static','cultivation_pavilion_'+cloudArt.pavilions.length,[x,y,z],{model:'models/survival_world_v2/cultivation_pavilion.vmdl',solid:'0',rendercolor:'255 255 255'},`0 ${cloudArt.pavilions.length%2*45} 0`,scale);cloudArt.pavilions.push({x,y,z,scale});
}
for(const p of [[-11800,15100],[-14900,1500],[5200,-13500],[13700,-7100]])pavilion(...p);
// Island landmarks only at the far ornamental corners, never at the gate/stairs.
for(let q=0;q<4;q++){const p=originalIsland.transform(768,1152,q);pavilion(...p,.8);}
const pineModel='maps/journey_assets/props/trees/journey_armandpine/journey_armandpine_01.vmdl';
for(const p of cloudArt.pavilions)for(let i=0;i<3;i++){
 const a=i*2.1+.5,x=p.x+Math.cos(a)*450,y=p.y+Math.sin(a)*450;
 if(markers.some(m=>Math.hypot(x-m.x,y-m.y)<550))continue;
 entity('prop_static','cultivation_pine_'+cloudArt.pines.length,[x,y,surface(x,y)],{model:pineModel,solid:'0',rendercolor:'214 232 213'},`0 ${i*113} 0`,.8+(i%2)*.15);cloudArt.pines.push({x,y});
}
fs.writeFileSync(path.join(OUT,'cultivation_design.json'),JSON.stringify(cloudArt,null,2));
