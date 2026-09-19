const fs=require('fs'),path=require('path');
module.exports=function(root){
 const out=path.join(root,'output/survival_world_v2'),m=path.join(out,'source_materials');
 for(const name of ['ocean_water','shallow_water','spring_water']){
  const file=path.join(m,name+'.vmat'),color=name==='spring_water'?'[0.045 0.13 0.15 1]':'[0.018 0.055 0.11 1]';
  fs.writeFileSync(file,fs.readFileSync(file,'utf8').replace(/"g_vWaterFogColor"\s*"[^"]+"/,'"g_vWaterFogColor" "'+color+'"'));
 }
 let fx=fs.readFileSync(path.join(root,'output/reference_asset_study/yokai_particles/particles/world_environmental_fx/radiant_stationary_wisps.vpcf'),'utf8');
 fx=fx.replace('m_nMaxParticles = 25','m_nMaxParticles = 12').replaceAll('m_nControlPointNumber = 5','m_nControlPointNumber = 0').replace('[ 218, 232, 64, 255 ]','[ 148, 118, 232, 255 ]').replace('[ 64, 222, 232, 255 ]','[ 105, 175, 245, 255 ]').replace('[ 0.0, 0.0, 300.0 ]','[ 0.0, 0.0, 110.0 ]').replace('[ 0.0, 0.0, 200.0 ]','[ 0.0, 0.0, 70.0 ]').replace('m_flLiteralValue = 5.0','m_flLiteralValue = 2.0');
 const dir=path.join(out,'source_particles');fs.mkdirSync(dir,{recursive:true});fs.writeFileSync(path.join(dir,'yokai_wisps.vpcf'),fx);
 // A small cluster of warm additive sprites keeps the light core visible overhead.
 const glow=fx.replace('m_nMaxParticles = 12','m_nMaxParticles = 1').replace('[ 148, 118, 232, 255 ]','[ 255, 158, 72, 255 ]').replace('[ 105, 175, 245, 255 ]','[ 255, 125, 48, 255 ]').replace('m_flLiteralValue = 120.0','m_flLiteralValue = 0.0').replace('m_flLiteralValue = 55.0','m_flLiteralValue = 0.0').replace('m_flLiteralValue = 10.0','m_flLiteralValue = 0.0').replace('[ 0.0, 0.0, 110.0 ]','[ 0.0, 0.0, 0.0 ]').replace('[ 0.0, 0.0, 70.0 ]','[ 0.0, 0.0, 0.0 ]');
 const visibleGlow=glow.replace('m_nMaxParticles = 1','m_nMaxParticles = 4')
  .replace('m_flRandomMin = 16.0','m_flRandomMin = 48.0').replace('m_flRandomMax = 32.0','m_flRandomMax = 64.0')
  .replace('m_flLiteralValue = 0.0','m_flLiteralValue = 2.0')
  .replace('m_flStartScale = 0.1','m_flStartScale = 0.7')
  .replace('_class = "C_OP_RenderSprites"','_class = "C_OP_RenderSprites"\n            m_bDisableZBuffering = true');
 fs.writeFileSync(path.join(dir,'yokai_lantern_glow.vpcf'),visibleGlow);
};
