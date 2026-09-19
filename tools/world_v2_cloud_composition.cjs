// Sparse, authored whole-map cloud composition. Input polygons are gameplay exclusions.
module.exports=function({fs,path,OUT,land,nativePreserved,inside,edgeDistance,terrainHeight,hotSpring,entity,prism}){
 const kit=path.resolve(OUT,'../xianxia_kit'),revision=path.join(kit,'cloud_revision_v2');
 const pngSource=fs.readFileSync(path.resolve(OUT,'../../tools/xianxia_kit_gallery.cjs'),'utf8');
 const {pngRead}=new Function('require','__dirname',pngSource.slice(0,pngSource.indexOf('const a=JSON.parse'))+'return {pngRead};')(require,path.resolve(OUT,'../../tools'));
 const art={theme:'清晨疏云与远景云海',timeOfDay:.3,outer:[],inner:[],rejected:[],pavilions:[],pines:[],clearance:180,method:'Six independent baked density fields; alpha-footprint clearance at 50/60/70 degree views; sparse open banks, distant background below map'};
 const playable=land.filter(a=>!a.nativeReuse),samples=new Map();
 function distance(x,y){if(nativePreserved(x,y)||Math.hypot((x-hotSpring.x)/1350,(y-hotSpring.y)/1100)<1)return 0;let d=Infinity;for(const a of playable){if(inside(x,y,a.polygon))return 0;d=Math.min(d,edgeDistance(x,y,a.polygon));}return d;}
 function alphaPoints(texture){
  if(samples.has(texture))return samples.get(texture);
  const name=texture.replace(/_v2$/,''),file=path.join(revision,name.endsWith('_b')?'variants':'',name+'.png');
  const p=pngRead(file),points=[],pad=(2048-p.h)/2;
  for(let y=0;y<p.h;y+=48)for(let x=0;x<p.w;x+=48){let a=0;for(let dy=0;dy<48&&y+dy<p.h;dy+=8)for(let dx=0;dx<48&&x+dx<p.w;dx+=8)a=Math.max(a,p.data[((y+dy)*p.w+x+dx)*4+3]);if(a>18)points.push([(x+24)/1024-1,1-(y+24+pad)/1024]);}
  samples.set(texture,points);return points;
 }
 function clearance(x,y,z,r,angle,texture){let d=Infinity;const a=angle*Math.PI/180,c=Math.cos(a),s=Math.sin(a);
  for(const [u,v]of alphaPoints(texture))for(const pitch of [50,60,70]){
   const px=x+(u*c-v*s)*r,vertical=(u*s+v*c)*r,theta=pitch*Math.PI/180;
   // Include both elevation shifts conservatively; normal camera uses +Y shift.
   const shift=Math.abs(z-640)/Math.tan(theta);
   for(const sign of [-1,1]){const py=y+vertical/Math.sin(theta)+shift*sign;d=Math.min(d,distance(px,py));if(d<180)return d;}
  }return d;
 }
 const header='<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->';
 function add(group,texture,x,y,z,r,angle,alpha){
  let d=0;const original=r;for(let attempt=0;attempt<4;attempt++){d=clearance(x,y,z,r,angle,texture);if(d>=180)break;r=Math.round(r*.84);}
  if(d<180){art.rejected.push({group,x,y,r:original,reason:'Projected cloud would overlap activity polygon'});return;}
  const target=art[group],name='cloud_bank_'+group+'_'+String(target.length).padStart(2,'0');
  const value=(field,v)=>`{_class="C_INIT_InitFloat" m_nOutputField=${field} m_InputValue={m_nType="PF_TYPE_LITERAL" m_flLiteralValue=${Number(v).toFixed(6)}}}`;
  fs.writeFileSync(path.join(OUT,'source_particles',name+'.vpcf'),`${header}\n{_class="CParticleSystemDefinition" m_nMaxParticles=1 m_nInitialParticles=1 m_flConstantRadius=${r}.0 m_ConstantColor=[245,248,250,255] m_flMaxDrawDistance=100000.0 m_bShouldSort=true
 m_BoundingBoxMin=[-${r}.0,-${r}.0,-${r}.0] m_BoundingBoxMax=[${r}.0,${r}.0,${r}.0]
 m_Renderers=[{_class="C_OP_RenderSprites" m_nOrientationType="PARTICLE_ORIENTATION_SCREEN_ALIGNED" m_flStartFadeSize=4.0 m_flEndFadeSize=5.0 m_nFeatheringMode="PARTICLE_DEPTH_FEATHERING_ON_OPTIONAL" m_flFeatheringMaxDist={m_nType="PF_TYPE_LITERAL" m_flLiteralValue=180.0} m_vecTexturesInput=[{m_hTexture=resource:"materials/xianxia_kit/${texture}.vtex"}]}]
 m_Initializers=[{_class="C_INIT_CreateWithinSphere" m_fRadiusMin=0.0 m_fRadiusMax=0.0},${value(1,100000)},${value(3,r)},${value(7,alpha)},${value(4,angle*Math.PI/180)}] m_nBehaviorVersion=5}`);
  entity('info_particle_system','cultivation_'+name,[x,y,z],{effect_name:'particles/survival_world_v2/'+name+'.vpcf',start_active:'1'});
  target.push({x,y,z,r,angle,alpha,texture,projectedClearance:d});
 }
 const textures=['c02_cliff_cloud_v2','c01_cloud_sea_b_v2','c02_cliff_cloud_b_v2','c01_cloud_sea_v2'];
 const outer=[[-15000,17200,1700,2600,-7],[-10000,17400,1250,2800,5],[-4000,18100,900,2300,-4],[2500,17400,1450,2800,7],[8500,17500,1100,2300,-5],[13500,17000,1650,2700,4],
 [-17600,13000,1600,2500,8],[-18200,7000,1000,3000,-5],[-17100,1000,1350,2300,6],[-17600,-6500,1200,2900,-7],[-18000,-12500,1700,2800,4],
 [17500,13000,1400,2500,-8],[18100,7600,950,2800,6],[17500,1300,1550,2500,-3],[17700,-5300,1200,2800,8],[17900,-11500,1600,2900,-6],
 [-14300,-17300,1100,2600,-8],[-9200,-17600,1550,2900,3],[-4000,-18000,800,2400,-6],[2400,-17400,1500,2700,6],[8500,-17800,1100,2800,-4],[13700,-17000,1700,2500,7],
 [-21400,18700,250,3100,-3],[21200,-17900,350,3100,5]];
 outer.forEach((p,i)=>add('outer',textures[i%4],...p,i>21?.62:.84));
 const inner=[[-13400,13700,1300,-8],[-11100,12200,1100,6],[-2100,15100,1250,7],[1300,15400,1100,-6],[-7800,-8500,1250,-6],[1100,-8450,1400,4],[3950,-8600,1100,-4],[12500,-13200,1700,-7],[14300,-14000,1200,7],[3700,-14500,1550,4]];
 inner.forEach(([x,y,r,a],i)=>add('inner',i%3===2?'c04_thin_mist_v2':'c03_cloud_band_v2',x,y,terrainHeight(x,y)+420,r,a,i%3===2?.65:.9));
 // Continuous distant atmospheric color under the perimeter; not a cloud-texture carpet.
 // It is outside the native grid and below its -512 underside, never a playing surface.
 const far=64000,near=16256,z=-1600,mat='materials/survival_world_v2/cloud_horizon.vmat';
 fs.writeFileSync(path.join(OUT,'source_materials/cloud_horizon.vmat'),'"Layer0"\n{\n "shader" "global_lit_simple.vfx"\n "F_FULLBRIGHT" "1"\n "F_DO_NOT_CAST_SHADOWS" "1"\n "TextureColor" "[0.37 0.47 0.54 1]"\n "g_vColorTint" "[1 1 1 0]"\n "Attributes" { "mapbuilder.nonsolid" "1" }\n}\n');
 for(const [x0,y0,x1,y1]of [[-far,-far,far,-near],[-far,near,far,far],[-far,-near,-near,near],[near,-near,far,near]])prism([[x0,y0],[x1,y0],[x1,y1],[x0,y1]],z,z-16,mat,'materials/tools/toolsnodraw.vmat','255 255 255 255');
 art.background={material:mat,z,innerHalfExtent:near,outerHalfExtent:far,opaqueCloudCarpet:false};
 return art;
};
