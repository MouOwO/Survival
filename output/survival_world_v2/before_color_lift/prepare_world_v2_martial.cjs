const fs=require('fs'),path=require('path');
module.exports=function(root){
 const dir=path.join(root,'output/survival_world_v2/source_materials');
 const tint={forest:[[.38,.42,.35],[.46,.48,.44],[.38,.42,.43]],snow:[[.55,.60,.64],[.48,.46,.42],[.38,.42,.43]],volcanic:[[.78,.79,.80],[.60,.39,.27],[.55,.34,.23]]};
 for(const type of Object.keys(tint)){
  let s=fs.readFileSync(path.join(dir,'transition_'+type+'.vmat'),'utf8');
  for(let i=1;i<4;i++)s=s.replace(new RegExp('"g_vColorTint'+i+'" "[^"\\n]+"'),'"g_vColorTint'+i+'" "['+tint[type][i-1].join(' ')+' 0]"');
  if(type==='forest')s=s.replaceAll('dirt_path008_color.png','sand_path009_color.png').replaceAll('radiant_stone_ti10_01_color.png','stone_path001_angled_color.png').replaceAll('radiant_stone_ti10_01_normal.png','stone_path001_angled_normal.png').replaceAll('radiant_stone_ti10_01_af3aacc6_blend.png','stone_path001_angled_150d1d7b_blend.png');
  fs.writeFileSync(path.join(dir,'transition_martial_'+type+'.vmat'),s);
 }
};
