const fs=require('fs'),path=require('path');
module.exports=function(root){
 const dir=path.join(root,'output/survival_world_v2/source_materials');
 let s='"Layer0"\n{\n "shader" "multiblend.vfx"\n "F_WORLDSPACE_UVS" "1"\n "F_SPECULAR" "0"\n "F_NORMAL_MAP" "1"\n "g_flBumpStrength" "0.5"\n';
 for(let i=0;i<4;i++)s+=` "TextureColor${i}" "materials/survival_world_v2/radiant_stone_ti10_01_color.png"\n "TextureNormal${i}" "materials/survival_world_v2/radiant_stone_ti10_01_normal.png"\n "TextureRevealMask${i}" "[0.5 0.5 0.5 0]"\n "g_vColorTint${i}" "[0.52 0.50 0.44 0]"\n "g_flTexCoordScale${i}" "3"\n "TextureSelfIllumMask${i}" "[0 0 0 0]"\n "TextureBloom${i}" "[0 0 0 0]"\n`;
 s+=' "Attributes" { "dota.nav.walkable" "1" }\n}\n';
 fs.writeFileSync(path.join(dir,'island_stairs.vmat'),s);
};
