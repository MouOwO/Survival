// Existing Valve textures and tiles only; this creates addon-local material/template variants.
const fs=require('fs'),path=require('path'),cp=require('child_process');
const root=path.resolve(__dirname,'..'),out=path.join(root,'output/survival_world_v2');
const materialDir=path.join(out,'source_materials'),tileDir=path.join(out,'source_tilesets');
fs.mkdirSync(tileDir,{recursive:true});
const sources=[path.join(root,'output/reference_asset_study/transition_decompiled/materials/blends'),path.join(root,'output/reference_asset_study/floors_decompiled')];
const copied=new Set();
function tex(name){if(!copied.has(name)){const src=sources.map(d=>path.join(d,name+'.png')).find(p=>fs.existsSync(p));if(!src)throw Error('Missing existing texture '+name);fs.copyFileSync(src,path.join(materialDir,name+'.png'));copied.add(name);}return 'materials/survival_world_v2/'+name+'.png';}
const palettes={
 forest:[['sand_path009_color',[.42,.38,.30]],['grass_long_01_color',[.31,.43,.19]],['stone_path007_color',[.36,.38,.34]],['stone_path001_angled_color',[.30,.32,.30]]],
 snow:[['stone_path007_color',[.36,.42,.44]],['snow_directional_00_color',[.70,.76,.79]],['snow_directional_00_color',[.43,.49,.49]],['stone_path001_angled_color',[.36,.43,.46]]],
 thaw:[['snow_directional_00_color',[.70,.76,.79]],['grass_long_01_color',[.31,.43,.19]],['stone_path007_color',[.40,.45,.41]],['stone_path001_angled_color',[.30,.35,.35]]],
 volcanic:[['basalt_00_color',[1.1,1.05,1.0]],['stone_path007_color',[1.1,1.0,.9]],['lava_02_color',[1,.85,.7]],['lava_01_color',[1,.75,.55]]],
 corrupt:[['sand_path009_color',[.24,.28,.24]],['grass_long_01_color',[.20,.31,.19]],['basalt_00_color',[.28,.34,.29]],['stone_path001_angled_color',[.25,.31,.28]]]
};
for(const [name,layers]of Object.entries(palettes)){
 let s='"Layer0"\n{\n "shader" "multiblend.vfx"\n "F_SPECULAR" "0"\n';
 layers.forEach(([texture,tint],i)=>{s+=` "TextureColor${i}" "${tex(texture)}"\n "g_vColorTint${i}" "[${tint.join(' ')} 0]"\n "g_flTexCoordScale${i}" "${i===3?3:2.5}"\n "TextureRevealMask${i}" "[${name==='volcanic'&&i>=2?'0.12 0.12 0.12':'0.5 0.5 0.5'} 0]"\n "TextureSelfIllumMask${i}" "[0 0 0 0]"\n "TextureBloom${i}" "[0 0 0 0]"\n`;});
 s+=' "Attributes" { "dota.nav.walkable" "1" }\n}\n';fs.writeFileSync(path.join(materialDir,'transition_'+name+'.vmat'),s);
}
// Use the native generic river shader, including its fog/flow configuration.
// The authored mesh sets shallow water depth; navigation stays on the continuous bed.
let water=fs.readFileSync(path.join(root,'output/reference_asset_study/water_decompiled/water_generic_000.vmat'),'utf8');
const waterSource=path.join(root,'output/reference_asset_study/water_decompiled');
water=water.replace(/"(Texture\w+)"\s*"([^"\[\]]+\.png)"/g,(m,k,p)=>{const base=path.basename(p);fs.copyFileSync(path.join(waterSource,base),path.join(materialDir,base));return '"'+k+'" "materials/survival_world_v2/'+base+'"';});
fs.writeFileSync(path.join(materialDir,'shallow_water.vmat'),water);
const report=[];
function endBlock(s,start){let depth=0,quote=false;for(let i=start;i<s.length;i++){if(s[i]==='"'&&s[i-1]!=='\\')quote=!quote;if(!quote){if(s[i]==='{')depth++;else if(s[i]==='}'&&!--depth)return i+1;}}throw Error('Unbalanced DMX');}
for(const name of ['radiant_basic','dire_basic','radiant_snow_basic','radiant_autumn_basic']){
 const dest=path.join(tileDir,name+'.vmap');
 cp.execFileSync('D:/steam/steamapps/common/dota 2 beta/game/bin/win64/dmxconvert.exe',['-i','D:/steam/steamapps/common/dota 2 beta/content/dota/maps/tilesets/'+name+'.vmap','-o',dest,'-oe','keyvalues2'],{stdio:'pipe'});
 let s=fs.readFileSync(dest,'utf8'),count=0,offset=0;const re=/"CMapEntity"\s*\{/g;let m;
 while((m=re.exec(s))){const start=m.index,end=endBlock(s,s.indexOf('{',start));let block=s.slice(start,end);if(/"model" "string" "[^"]*(?:lily|lotus)[^"]*"/i.test(block)){block=block.replace(/"editorOnly" "bool" "0"/g,'"editorOnly" "bool" "1"').replace(/"force_hidden" "bool" "0"/g,'"force_hidden" "bool" "1"').replace(/"renderamt" "string" "255"/g,'"renderamt" "string" "0"');s=s.slice(0,start)+block+s.slice(end);count++;}re.lastIndex=start+block.length;}
 fs.writeFileSync(dest,s);report.push({template:name,disabledLilyEntities:count});
}
fs.writeFileSync(path.join(out,'transition_asset_audit.json'),JSON.stringify({palettes:Object.keys(palettes),textures:[...copied],templates:report},null,2));console.log(report);
