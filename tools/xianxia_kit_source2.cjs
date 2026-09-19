// Stage independently authored resources. No main map is modified.
const fs=require('fs'),path=require('path');
const out=path.resolve(__dirname,'../output/xianxia_kit');
for(const d of ['source_models','source_materials','source_particles'])fs.mkdirSync(path.join(out,d),{recursive:true});
const models=JSON.parse(fs.readFileSync(path.join(out,'asset_manifest.json')));
const header='<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:modeldoc28:version{fb63b6ca-f435-4aa0-a2c7-c66ddc651dca} -->';
for(const a of models)for(const suffix of ['','_lod1']){
 const n=a.name+suffix;fs.copyFileSync(path.join(out,'models',n+'.fbx'),path.join(out,'source_models',n+'.fbx'));
 const remaps=a.materials.map(m=>`{from="${m}" to="${m}"}`).join(',');
 fs.writeFileSync(path.join(out,'source_models',n+'.vmdl'),`${header}\n{rootNode={_class="RootNode" children=[{_class="RenderMeshList" children=[{_class="RenderMeshFile" name="${n}" filename="models/xianxia_kit/${n}.fbx" import_scale=0.01}]},{_class="MaterialGroupList" children=[{_class="DefaultMaterialGroup" remaps=[${remaps}] use_global_default=false}]}]}}`);
}
for(const f of fs.readdirSync(path.join(out,'materials')))if(f.endsWith('.png'))fs.copyFileSync(path.join(out,'materials',f),path.join(out,'source_materials',f));
const mats=JSON.parse(fs.readFileSync(path.join(out,'material_manifest.json'))).map(x=>x.name).concat(['xx_leaf','xx_blossom']);
for(const n of mats){
 const leaf=['xx_leaf','xx_blossom'].includes(n);
 let s='"Layer0"\n{\n "shader" "global_lit_simple.vfx"\n "g_vColorTint" "[1 1 1 0]"\n';
 if(n==='xx_roof'||n==='xx_wood')s+=' "F_RENDER_BACKFACES" "1"\n';
 if(leaf)s+=` "TextureColor" "${n==='xx_leaf'?'[0.45 0.58 0.40 1]':'[0.86 0.64 0.69 1]'}"\n "F_RENDER_BACKFACES" "1"\n`;
 else s+=` "F_NORMAL_MAP" "1"\n "F_SPECULAR" "1"\n "TextureColor" "materials/xianxia_kit/${n}_color.png"\n "TextureNormal" "materials/xianxia_kit/${n}_normal.png"\n "TextureReflectance" "materials/xianxia_kit/${n}_reflectance.png"\n`;
 s+='}\n';
 if(n==='xx_water')s='"Layer0"\n{\n "shader" "water_dota.vfx"\n "F_FLOW_NORMALS" "1"\n "TextureNormal" "materials/xianxia_kit/xx_water_normal.png"\n "TextureNoise" "materials/xianxia_kit/xx_water_height.png"\n "TextureFlow" "[0.04 0.08 0 0]"\n "g_flNormalUvScale" "500"\n "g_flNormalFlowTimeIntervalInSeconds" "1.6"\n "g_flNormalFlowUvScrollDistance" "0.08"\n "g_flBumpStrength" "0.6"\n "g_flWaterDepth" "90"\n "g_flReflectance" "0.18"\n "g_flReflectionAmount" "0.15"\n "g_flRefractionAmount" "0.04"\n "g_vWaterFogColor" "[0.06 0.24 0.29 1]"\n "g_vRefractionTint" "[0.35 0.72 0.76 0]"\n "g_vLowEndSurfaceColor" "[0.12 0.34 0.38 1]"\n "g_flBaseBloom" "0"\n "Attributes" { "mapbuilder.water" "1" "mapbuilder.nonsolid" "1" }\n}\n';
 fs.writeFileSync(path.join(out,'source_materials',n+'.vmat'),s);
}
// Clouds are installed only once their bake and transparency QA have completed.
fs.writeFileSync(path.join(out,'source_materials/xx_waterbed.vmat'),'"Layer0"\n{\n "shader" "global_lit_simple.vfx"\n "TextureColor" "[0.07 0.26 0.30 1]"\n "g_vColorTint" "[1 1 1 0]"\n}\n');
const waterFile=path.join(out,'source_materials/xx_water.vmat');fs.writeFileSync(waterFile,fs.readFileSync(waterFile,'utf8').replace('"g_flBumpStrength" "0.6"','"g_flBumpStrength" "0.18"\n "g_flNoiseStrength" "0.1"'));
if(process.argv.includes('--clouds')){
 const clouds=JSON.parse(fs.readFileSync(path.join(out,'clouds/cloud_manifest.json')));
 if(!clouds.complete)throw Error('Cloud bake incomplete');
 const tex=fs.readFileSync(path.resolve(__dirname,'../output/survival_world_v2/source_materials/morning_billows_a.vtex'),'utf8');
 for(const {name}of clouds.items){
  fs.copyFileSync(path.join(out,'clouds/runtime',name+'.png'),path.join(out,'source_materials',name+'.png'));
  fs.writeFileSync(path.join(out,'source_materials',name+'.vtex'),tex.replaceAll('survival_world_v2/morning_billows_a','xianxia_kit/'+name).replace('"m_vClamp" "vector3" "0 0 0"','"m_vClamp" "vector3" "1 1 1"'));
  const radius=name.startsWith('c01')?1100:name.startsWith('c02')?680:850;
  const value=(f,v)=>`{_class="C_INIT_InitFloat" m_nOutputField=${f} m_InputValue={m_nType="PF_TYPE_LITERAL" m_flLiteralValue=${v}.0}}`;
  fs.writeFileSync(path.join(out,'source_particles',name+'.vpcf'),`<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->
{_class="CParticleSystemDefinition" m_nMaxParticles=1 m_nInitialParticles=1 m_flConstantRadius=${radius}.0 m_ConstantColor=[255,255,255,255] m_flMaxDrawDistance=30000.0 m_bShouldSort=true
m_BoundingBoxMin=[-${radius}.0,-${radius}.0,-${radius}.0] m_BoundingBoxMax=[${radius}.0,${radius}.0,${radius}.0]
m_Renderers=[{_class="C_OP_RenderSprites" m_nOrientationType="PARTICLE_ORIENTATION_SCREEN_ALIGNED" m_flStartFadeSize=4.0 m_flEndFadeSize=5.0 m_nFeatheringMode="PARTICLE_DEPTH_FEATHERING_ON_OPTIONAL" m_flFeatheringMaxDist={m_nType="PF_TYPE_LITERAL" m_flLiteralValue=80.0} m_vecTexturesInput=[{m_hTexture=resource:"materials/xianxia_kit/${name}.vtex"}]}]
m_Initializers=[{_class="C_INIT_CreateWithinSphere" m_fRadiusMin=0.0 m_fRadiusMax=0.0},${value(1,100000)},${value(3,radius)},${value(7,1)}] m_nBehaviorVersion=5}`);
 }
}
console.log(JSON.stringify({models:models.length,lodVariants:models.length,materials:mats.length}));
