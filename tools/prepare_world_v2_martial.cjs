const fs=require('fs'),path=require('path');
module.exports=function(root){
 const dir=path.join(root,'output/survival_world_v2/source_materials');
 const tint={forest:[[.40,.49,.32],[.54,.53,.47],[.50,.54,.55]],snow:[[.64,.70,.75],[.55,.56,.55],[.50,.54,.58]],volcanic:[[1.05,1.02,.98],[.92,.60,.40],[.80,.46,.27]]};
 for(const type of Object.keys(tint)){
  let s=fs.readFileSync(path.join(dir,'transition_'+type+'.vmat'),'utf8');
  for(let i=1;i<4;i++)s=s.replace(new RegExp('"g_vColorTint'+i+'" "[^"\\n]+"'),'"g_vColorTint'+i+'" "['+tint[type][i-1].join(' ')+' 0]"');
  if(type==='forest')s=s.replaceAll('dirt_path008_color.png','sand_path009_color.png').replaceAll('radiant_stone_ti10_01_color.png','stone_path001_angled_color.png').replaceAll('radiant_stone_ti10_01_normal.png','stone_path001_angled_normal.png').replaceAll('radiant_stone_ti10_01_af3aacc6_blend.png','stone_path001_angled_150d1d7b_blend.png');
  fs.writeFileSync(path.join(dir,'transition_martial_'+type+'.vmat'),s);
 }
};
