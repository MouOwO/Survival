// Shared morning palette; used after the older biome/paving preparations.
const fs=require('fs'),path=require('path');
module.exports=function(root){
 const out=path.join(root,'output/survival_world_v2'),dir=path.join(out,'source_materials');
 const set=(s,k,v)=>s.replace(new RegExp('"'+k+'"\\s*"[^"\\n]+"'),'"'+k+'" "'+v+'"');
 const tint=(s,k,rgb)=>set(s,k,'['+rgb.join(' ')+' 0]');
 const changes=[];
 fs.copyFileSync(path.join(dir,'transition_forest.vmat'),path.join(dir,'transition_ridge.vmat'));
 for(const name of ['forest','corrupt','snow','thaw','volcanic','martial_forest','martial_snow','martial_volcanic','ridge']){
  const file='transition_'+name+'.vmat';let s=fs.readFileSync(path.join(dir,file),'utf8');
  s=tint(s,'g_vColorTint0',[.64,.66,.62]);s=set(s,'g_flBumpStrength','.35');
  s=set(s,'g_flTexCoordScale0','3.5');
  // A cliff texture is not a suitable exposed underlayer on horizontal ground.
  // The heightfield chooses a dedicated ridge palette only on steep faces.
  if(name!=='ridge'){
   s=set(s,'TextureColor0','materials/survival_world_v2/sand_path009_color.png');
   s=set(s,'TextureNormal0','materials/survival_world_v2/sand_path001_normal.png');
   s=tint(s,'g_vColorTint0',[.58,.60,.56]);
  }else{
   s=set(s,'TextureColor0','materials/survival_world_v2/stone_path001_angled_color.png');
   s=set(s,'TextureNormal0','materials/survival_world_v2/stone_path001_angled_normal.png');
  }
  // All palettes meet on the same warm gray stone layer, including normals,
  // scale and reveal mask. Biome-specific grass/snow/lava stay on layers 1/2.
  for(const [k,v]of Object.entries({TextureColor3:'stone_path001_angled_color.png',TextureNormal3:'stone_path001_angled_normal.png',TextureRevealMask3:'stone_path001_angled_150d1d7b_blend.png'}))s=set(s,k,'materials/survival_world_v2/'+v);
  s=tint(s,'g_vColorTint3',[.63,.63,.59]);s=set(s,'g_flTexCoordScale3','4');
  if(/forest|corrupt/.test(name)){
   s=tint(s,'g_vColorTint1',[.48,.59,.40]);s=tint(s,'g_vColorTint2',[.63,.61,.54]);
   s=set(s,'TextureColor2','materials/survival_world_v2/sand_path009_color.png');
  }else if(/snow|thaw/.test(name))s=tint(s,'g_vColorTint1',[.67,.72,.74]);
  else {s=tint(s,'g_vColorTint1',[1.03,1.06,1.05]);s=tint(s,'g_vColorTint2',[.80,.54,.39]);}
  if(name==='martial_forest')for(let i=0;i<4;i++){
   s=set(s,'TextureColor'+i,'materials/survival_world_v2/stone_path001_angled_color.png');
   s=set(s,'TextureNormal'+i,'materials/survival_world_v2/stone_path001_angled_normal.png');
   s=set(s,'g_flTexCoordScale'+i,'4');s=tint(s,'g_vColorTint'+i,[.63,.63,.59]);
  }
  fs.writeFileSync(path.join(dir,file),s);changes.push(file);
 }
 let stone=fs.readFileSync(path.join(dir,'island_native_paving.vmat'),'utf8');
 for(let i=0;i<4;i++){
  stone=tint(stone,'g_vColorTint'+i,[.68,.66,.61]);stone=tint(stone,'g_vColorTintB'+i,[.64,.63,.59]);
  stone=set(stone,'TextureBloom'+i,'[0 0 0 0]');stone=set(stone,'TextureSelfIllumMask'+i,'[0 0 0 0]');
 }
 stone=set(stone,'g_flBumpStrength','.65');fs.writeFileSync(path.join(dir,'island_native_paving.vmat'),stone);changes.push('island_native_paving.vmat');
 let pavilion=fs.readFileSync(path.join(dir,'cultivation_stone.vmat'),'utf8');pavilion=set(pavilion,'TextureColor','[0.42 0.44 0.42 1]');fs.writeFileSync(path.join(dir,'cultivation_stone.vmat'),pavilion);changes.push('cultivation_stone.vmat');
 const vtexTemplate=fs.readFileSync(path.join(root,'output/reference_asset_study/cloud_texture_preview/crownfall_debut_cloud_1.vtex'),'utf8');
 for(const [name,source]of [['cloud_native_a','crownfall_debut_cloud_1'],['cloud_native_b','crownfall_debut_cloud_2']]){
  fs.copyFileSync(path.join(root,'output/reference_asset_study/cloud_texture_preview',source+'.png'),path.join(dir,name+'.png'));
  fs.writeFileSync(path.join(dir,name+'.vtex'),vtexTemplate.replace(/"m_fileName" "string" "[^"]+"/,'"m_fileName" "string" "materials/survival_world_v2/'+name+'.png"').replace('"DXT5"','"RGBA8888"'));
 }
 fs.writeFileSync(path.join(dir,'cloud_sea_base.vmat'),'"Layer0"\n{\n "shader" "global_lit_simple.vfx"\n "F_SPECULAR" "0"\n "TextureColor" "[0.32 0.40 0.47 1]"\n "g_vColorTint" "[1 1 1 0]"\n "Attributes" { "dota.nav.walkable" "0" }\n}\n');
 for(const name of ['morning_billows_a','morning_billows_b','morning_ribbon_a','morning_ribbon_b']){
  fs.copyFileSync(path.join(out,'cloud_cards',name+'.png'),path.join(dir,name+'.png'));
  const vtex=vtexTemplate.replace(/"m_fileName" "string" "[^"]+"/,'"m_fileName" "string" "materials/survival_world_v2/'+name+'.png"').replace('"DXT5"','"RGBA8888"');
  fs.writeFileSync(path.join(dir,name+'.vtex'),vtex);
 }
 fs.writeFileSync(path.join(out,'morning_palette.json'),JSON.stringify({materials:changes,grass:[.48,.59,.40],paving:[.63,.63,.59],exposure:1.05,lightScale:1.9,ambientScale:1.7,bloom:'No added bloom or self illumination',cloudTextures:'Original Blender density renders; uncompressed RGBA8888 (local BC7 encoder unavailable)'},null,2));
};
