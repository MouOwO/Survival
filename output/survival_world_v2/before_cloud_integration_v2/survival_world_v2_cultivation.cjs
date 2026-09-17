// Cloud placement is authored from the same active-area polygons as the map.
// No collision, no depth-test bypass, and no cloud over the central island/cross.
const cloudArt={theme:'疏朗清晨云海',timeOfDay:.3,outer:[],inner:[],pavilions:[],pines:[],clearance:180,method:'Authored open banks, single baked cloud card per emitter; no perimeter or area scatter'};
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
 const projectedClearance=footprintClearance(x,y,r,angle);if(projectedClearance<180)return;
 const target=group==='outer'?cloudArt.outer:cloudArt.inner,index=target.length;
 const name='cloud_bank_'+group+'_'+String(index).padStart(2,'0');
 const texture='morning_'+(group==='outer'?'billows':'ribbon')+'_'+(index%2?'b':'a');
 const value=(field,v)=>`{ _class = "C_INIT_InitFloat" m_nOutputField = ${field} m_InputValue = { m_nType = "PF_TYPE_LITERAL" m_flLiteralValue = ${Number(v).toFixed(5)} } }`;
 fs.writeFileSync(path.join(OUT,'source_particles',name+'.vpcf'),`${cardHeader}\n{
 _class = "CParticleSystemDefinition" m_nMaxParticles = 1 m_nInitialParticles = 1 m_flConstantRadius = ${r}.0
 m_ConstantColor = [ 224, 234, 239, 255 ] m_flMaxDrawDistance = 100000.0 m_bShouldSort = true
 m_BoundingBoxMin = [ -${r}.0, -${r}.0, -${r}.0 ] m_BoundingBoxMax = [ ${r}.0, ${r}.0, ${r}.0 ]
 m_Renderers = [ { _class = "C_OP_RenderSprites" m_nOrientationType = "PARTICLE_ORIENTATION_SCREEN_ALIGNED"
 m_flStartFadeSize = 4.0 m_flEndFadeSize = 5.0 m_nFeatheringMode = "PARTICLE_DEPTH_FEATHERING_ON_OPTIONAL"
 m_flFeatheringMaxDist = { m_nType = "PF_TYPE_LITERAL" m_flLiteralValue = 100.0 }
 m_vecTexturesInput = [ { m_hTexture = resource:"materials/survival_world_v2/${texture}.vtex" } ] } ]
 m_Initializers = [ { _class = "C_INIT_CreateWithinSphere" m_fRadiusMin = 0.0 m_fRadiusMax = 0.0 }, ${value(1,100000)}, ${value(3,r)}, ${value(7,alpha)}, ${value(4,angle*Math.PI/180)} ]
 m_nBehaviorVersion = 5
}`);
 entity('info_particle_system','cultivation_'+name,[x,y,z],{effect_name:'particles/survival_world_v2/'+name+'.vpcf',start_active:'1'});
 target.push({x,y,z,r,angle,alpha,texture,projectedClearance});
}
// Separate atmospheric masses, with large gaps between them. Their centers
// intentionally cross neither a constant edge coordinate nor a closed loop.
const outerBanks=[
 [-19400,15400,-500,3900,-9,.72],[-16600,15200,1500,3000,10,.76],[-22300,12500,-950,4300,4,.55],
 [-5200,19000,-700,3700,-5,.58],[-1800,20100,-1200,3000,9,.44],
 [17800,14400,100,2800,-9,.70],[20700,11500,-600,3800,6,.62],
 [19200,2100,-450,3200,10,.64],[22400,-400,-1400,4300,-7,.46],
 [17500,-15000,1300,3000,-5,.74],[21200,-17300,-1000,4400,8,.53],
 [-7800,-18500,-250,3200,-8,.74],[-11400,-20100,-1000,3900,7,.52],
 [-18600,-11900,-300,3100,5,.68],[-21900,-9400,-1200,4200,-6,.50],
 [-19900,1800,-850,3400,8,.50]
];
for(const p of outerBanks)cloudCard('outer',...p);
// Five authored open ribbons across unused ridges, never a loop per room.
const ridgeBanks=[
 [-13400,13000,1500,-9],[-11300,11900,1050,7],
 [-2100,14700,1200,9],[-800,15350,1100,-8],
 [-8500,-8500,1000,-7],[-6650,-8480,950,6],
 [850,-8280,1000,6],[2660,-8280,900,-7],[4500,-8290,950,8],
 [12300,-13300,1450,-8],[14500,-14000,1550,6],
 [3500,-14300,1300,-7]
];
for(const [x,y,r,a] of ridgeBanks)cloudCard('inner',x,y,terrainHeight(x,y)+360,r,a,.60);
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
