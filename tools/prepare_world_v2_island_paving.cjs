// Reuse Valve's original stone layer in every terrain blend slot. Native tiles
// modulate the paint weights at runtime; all slots must agree for full paving.
module.exports=function(root){
 const fs=require('fs'),path=require('path');
 const source=path.join(root,'output/reference_asset_study/transition_decompiled/materials/blends');
 const dest=path.join(root,'output/survival_world_v2/source_materials');
 const textures={Color:'stone_path001_angled_color.png',Normal:'stone_path001_angled_normal.png',RevealMask:'stone_path001_angled_150d1d7b_blend.png',Reflectance:'stone_path001_refl.png',SelfIllumMask:'stone_path001_9f73e6b_selfillum.png',Bloom:'stone_path001_9f73e6b_bloom.png',TintMask:'sand_path002_mask_f27f0cf4_mask.png'};
 for(const file of Object.values(textures))fs.copyFileSync(path.join(source,file),path.join(dest,file));
 let s='"Layer0"\n{\n "shader" "multiblend.vfx"\n "F_WORLDSPACE_UVS" "1"\n "F_NORMAL_MAP" "1"\n "F_SPECULAR" "1"\n "F_TINT_MASK" "1"\n "g_flBumpStrength" "1"\n "g_flSpecularBloom" "0"\n "g_flSpecularIntensity" "0.5"\n';
 for(let i=0;i<4;i++){
  s+=` "g_flTexCoordScale${i}" "5"\n "g_flTexCoordRotate${i}" "0"\n "g_vColorTint${i}" "[0.450980 0.470588 0.345098 1]"\n "g_vColorTintB${i}" "[0.388235 0.443137 0.207843 1]"\n`;
  for(const [kind,file]of Object.entries(textures))s+=` "Texture${kind}${i}" "materials/survival_world_v2/${file}"\n`;
 }
 s+=' "Attributes" { "dota.nav.walkable" "1" }\n}\n';
 fs.writeFileSync(path.join(dest,'island_native_paving.vmat'),s);
 // A masonry retaining face needs vertical UVs; the terrain cliff blend projects
 // its top-down rock pattern onto the wall and makes the paving look detached.
 for(const [name,tint,scale]of [['island_masonry',[.43,.45,.40],1.5],['island_coping',[.49,.50,.44],.8]]){
  let wall='"Layer0"\n{\n "shader" "multiblend.vfx"\n "F_WORLDSPACE_UVS" "0"\n "F_SPECULAR" "0"\n';
  for(let i=0;i<4;i++)wall+=` "TextureColor${i}" "materials/survival_world_v2/stone_paving_color.png"\n "TextureRevealMask${i}" "[0.5 0.5 0.5 0]"\n "TextureSelfIllumMask${i}" "[0 0 0 0]"\n "TextureBloom${i}" "[0 0 0 0]"\n "g_vColorTint${i}" "[${tint.join(' ')} 0]"\n "g_flTexCoordScale${i}" "${scale}"\n`;
  wall+='}\n';fs.writeFileSync(path.join(dest,name+'.vmat'),wall);
 }
};
