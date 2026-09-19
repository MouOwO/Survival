const fs=require('fs'),path=require('path');
module.exports=function(root){
 const out=path.join(root,'output/survival_world_v2'),models=path.join(out,'source_models'),materials=path.join(out,'source_materials'),particles=path.join(out,'source_particles');
 const colors={stone:[.69,.72,.68],wood:[.25,.16,.10],roof:[.10,.27,.29],trim:[.59,.43,.20],cloud:[.87,.91,.95]};
 for(const [name,color]of Object.entries(colors))fs.writeFileSync(path.join(materials,'cultivation_'+name+'.vmat'),`"Layer0"\n{\n "shader" "global_lit_simple.vfx"\n "F_SPECULAR" "0"\n "TextureColor" "[${color.join(' ')} 1]"\n "g_vColorTint" "[1 1 1 0]"\n}\n`);
 const header='<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:modeldoc28:version{fb63b6ca-f435-4aa0-a2c7-c66ddc651dca} -->';
 const assets=JSON.parse(fs.readFileSync(path.join(models,'cultivation_assets.json')));
 for(const a of assets){const remaps=a.materials.map(m=>`{ from = "${m}" to = "materials/survival_world_v2/${m}.vmat" }`).join(',');
 fs.writeFileSync(path.join(models,a.name+'.vmdl'),`${header}\n{ rootNode = { _class = "RootNode" children = [ { _class = "RenderMeshList" children = [ { _class = "RenderMeshFile" name = "${a.name}" filename = "models/survival_world_v2/${a.name}.fbx" import_scale = 0.01 } ] }, { _class = "MaterialGroupList" children = [ { _class = "DefaultMaterialGroup" remaps = [${remaps}] use_global_default = false } ] } ] } }`);}
 const fxHeader='<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->';
 const literal=v=>`{ m_nType = "PF_TYPE_LITERAL" m_flLiteralValue = ${v}.0 }`;
 const random=(a,b)=>`{ m_nType = "PF_TYPE_RANDOM_UNIFORM" m_flRandomMin = ${a} m_flRandomMax = ${b} m_nRandomMode = "PF_RANDOM_MODE_CONSTANT" }`;
 for(const [name,count,radius,spread,alpha,bias]of [['cloud_outer',5,1300,380,.85,'1.0, 0.8, 0.8'],['cloud_middle',5,650,120,.65,'1.0, 0.7, 0.20'],['cloud_inner',4,280,70,.45,'1.0, 0.6, 0.10']]){
 const fx=`${fxHeader}\n{
 _class = "CParticleSystemDefinition"
 m_nMaxParticles = ${count}
 m_nInitialParticles = ${count}
 m_flConstantRadius = ${radius}.0
 m_ConstantColor = [ 210, 229, 245, 255 ]
 m_BoundingBoxMin = [ -${radius+spread}.0, -${radius+spread}.0, -${radius}.0 ]
 m_BoundingBoxMax = [ ${radius+spread}.0, ${radius+spread}.0, ${radius}.0 ]
 m_flMaxDrawDistance = 90000.0
 m_bShouldSort = true
 m_Renderers = [ { _class = "C_OP_RenderSprites"
   m_nOrientationType = "PARTICLE_ORIENTATION_SCREEN_ALIGNED"
   m_flStartFadeSize = 4.0 m_flEndFadeSize = 5.0
   m_nFeatheringMode = "PARTICLE_DEPTH_FEATHERING_ON_OPTIONAL"
   m_flFeatheringMaxDist = ${literal(name==='cloud_inner'?70:160)}
   m_vecTexturesInput = [ { m_hTexture = resource:"models/items/vengefulspirit/vengeful_spirit_arcana/debut/materials/crownfall_debut_cloud_${name==='cloud_outer'?1:2}.vtex" } ]
 } ]
 m_Initializers = [
   { _class = "C_INIT_CreateWithinSphere" m_fRadiusMax = ${spread}.0 m_vecDistanceBias = [ ${bias} ] },
   { _class = "C_INIT_InitFloat" m_nOutputField = 1 m_InputValue = ${literal(70)} },
   { _class = "C_INIT_InitFloat" m_nOutputField = 3 m_InputValue = ${random(radius*.72,radius)} },
   { _class = "C_INIT_InitFloat" m_nOutputField = 7 m_InputValue = ${random(alpha*.72,alpha)} },
   { _class = "C_INIT_InitFloat" m_nOutputField = 4 m_InputValue = ${random(-25.0,25.0)} }
 ]
 m_Operators = [ { _class = "C_OP_Decay" }, { _class = "C_OP_FadeIn" m_flFadeInTimeMin = 0.02 m_flFadeInTimeMax = 0.05 }, { _class = "C_OP_FadeOut" m_flFadeOutTimeMin = 0.9 m_flFadeOutTimeMax = 1.0 } ]
 m_Emitters = [ { _class = "C_OP_ContinuousEmitter" m_flEmitRate = { m_nType = "PF_TYPE_LITERAL" m_flLiteralValue = ${count/60} } } ]
 m_nBehaviorVersion = 5
}`;
 fs.writeFileSync(path.join(particles,name+'.vpcf'),fx);
 }
 // Lighter cool limestone keeps the unified main island while fitting the cloud sea.
 const p=path.join(materials,'island_native_paving.vmat');let s=fs.readFileSync(p,'utf8').replaceAll('[0.450980 0.470588 0.345098 1]','[0.62 0.65 0.59 1]').replaceAll('[0.388235 0.443137 0.207843 1]','[0.55 0.59 0.48 1]');fs.writeFileSync(p,s);
 for(const name of ['ocean_water','shallow_water','spring_water']){const p=path.join(materials,name+'.vmat'),color=name==='spring_water'?'[0.12 0.32 0.29 1]':'[0.055 0.22 0.29 1]';fs.writeFileSync(p,fs.readFileSync(p,'utf8').replace(/"g_vWaterFogColor"\s*"[^"]+"/,'"g_vWaterFogColor" "'+color+'"'));}
};
