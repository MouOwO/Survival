// Mountain-only material correction after restoring the continuous terrain.
const fs=require('fs'),path=require('path');
module.exports=function(root){
 const out=path.join(root,'output/survival_world_v2'),dir=path.join(out,'source_materials');
 const src=path.join(root,'output/mountain_material_study/native_decoded');
 for(const name of ['stone001_color','stone001_normal','gravel002_color','gravel002_normal'])fs.copyFileSync(path.join(src,name+'.png'),path.join(dir,'mountain_'+name+'.png'));
 // Keep the original shared soil underlayer at the foot of each mountain.
 // Large directional cliff cracks no longer repeat across horizontal ridges.
 let s=fs.readFileSync(path.join(dir,'transition_forest.vmat'),'utf8');
 const set=(k,v)=>{s=s.replace(new RegExp('"'+k+'"\\s*"[^"\\n]+"'),'"'+k+'" "'+v+'"');};
 for(const [i,texture,scale,color]of [[1,'stone001',2.6,[.58,.61,.59]],[2,'gravel002',2.1,[.55,.58,.55]]]){
  set('TextureColor'+i,'materials/survival_world_v2/mountain_'+texture+'_color.png');
  set('TextureNormal'+i,'materials/survival_world_v2/mountain_'+texture+'_normal.png');
  set('TextureRevealMask'+i,'[0.5 0.5 0.5 0]');
  set('g_flTexCoordScale'+i,String(scale));set('g_vColorTint'+i,'['+color.join(' ')+' 0]');
 }
 set('g_flBumpStrength','.7');
 fs.writeFileSync(path.join(dir,'transition_ridge.vmat'),s);
 fs.writeFileSync(path.join(out,'mountain_material_design.json'),JSON.stringify({restoredFrom:'before_separate_cloud_islands',geometry:'original continuous mountains retained',source:'Valve mod_mines_rock_000: stone001 and gravel002',treatment:'Low contrast stone body, sparse gravel on gentle slopes, shared soil foot transition',normalStrength:.7,transition:[160,640],clouds:'restored pre-island arrangement; no new cloud sea base'},null,2));
};
