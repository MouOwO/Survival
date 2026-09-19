// Existing Valve textures and tiles only; this creates addon-local material/template variants.
const fs=require('fs'),path=require('path'),cp=require('child_process');
const root=path.resolve(__dirname,'..'),out=path.join(root,'output/survival_world_v2');
const materialDir=path.join(out,'source_materials'),tileDir=path.join(out,'source_tilesets');
fs.mkdirSync(tileDir,{recursive:true});
const sources=[path.join(root,'output/reference_asset_study/transition_decompiled/materials/blends'),path.join(root,'output/reference_asset_study/floors_decompiled'),path.join(root,'output/reference_asset_study')];
const copied=new Set();
// Textures exported from the installed Valve VPK, keeping their matching reveal masks.
function collectDirs(dir){sources.push(dir);for(const e of fs.readdirSync(dir,{withFileTypes:true}))if(e.isDirectory())collectDirs(path.join(dir,e.name));}
collectDirs(path.join(root,'output/reference_asset_study/art_decompiled'));
function tex(name){if(!copied.has(name)){const src=sources.map(d=>path.join(d,name+'.png')).find(p=>fs.existsSync(p));if(!src)throw Error('Missing existing texture '+name);fs.copyFileSync(src,path.join(materialDir,name+'.png'));copied.add(name);}return 'materials/survival_world_v2/'+name+'.png';}
const palettes={
 forest:[['cliff_wall002_color',[.50,.57,.51]],['grass_long_01_color',[.31,.43,.19]],['dirt_path008_color',[.80,.72,.55]],['stone_path001_angled_color',[.30,.32,.30]]],
 snow:[['cliff_wall002_color',[.55,.65,.72]],['snow_directional_00_color',[.70,.76,.79]],['snow_directional_00_color',[.43,.49,.49]],['stone_path001_angled_color',[.36,.43,.46]]],
 thaw:[['snow_directional_00_color',[.70,.76,.79]],['grass_long_01_color',[.31,.43,.19]],['stone_path007_color',[.40,.45,.41]],['stone_path001_angled_color',[.30,.35,.35]]],
 volcanic:[['basalt_00_color',[1.1,1.05,1.0]],['basalt_00_color',[.75,.67,.60]],['lava_02_color',[.32,.26,.22]],['lava_01_color',[.32,.26,.22]]],
 corrupt:[['cliff_wall002_color',[.50,.60,.52]],['grass_long_01_color',[.28,.38,.24]],['basalt_00_color',[1.0,1.1,1.0]],['stone_path001_angled_color',[.50,.58,.50]]]
};
// Valve's mod_radiant_dire_000 uses texture alpha reveal masks, not uniform alpha.
// Pair each grass/snow/lava/stone layer with the corresponding native mask.
const reveal={grass_long_01_color:'grass_long_01_3fbdd738_blend',snow_directional_00_color:'snow_directional_00_3a703903_blend',stone_path001_angled_color:'stone_path001_angled_150d1d7b_blend',stone_path007_color:'stone_path006_542effc_blend',basalt_00_color:'basalt_00_ec01ebeb_blend',lava_02_color:'lava_02_a9d87084_blend',lava_01_color:'lava_01_34ef93be_blend'};
const normals={cliff_wall002_color:'cliff_wall001_normal',sand_path009_color:'sand_path001_normal',grass_long_01_color:'grass_long_01b_normal',stone_path001_angled_color:'stone_path001_angled_normal',stone_path007_color:'stone001_normal'};
reveal.dirt_path008_color='sand_cracked001_1017aede_blend';normals.dirt_path008_color='sand_path001_normal';
reveal.grass_ti10_01_color='grass_ti10_01_787faf1b_blend';
normals.grass_ti10_01_color='grass_long_00_normal';
reveal.grass_ti10_02_color='grass_ti10_02_d9034285_blend';
normals.grass_ti10_02_color='grass_bumpy_00_normal';
reveal.grass_bumpy_00_color='grass_bumpy_00_71a7bd20_blend';
normals.grass_bumpy_00_color='grass_bumpy_00_normal';
reveal.radiant_stone_ti10_01_color='radiant_stone_ti10_01_af3aacc6_blend';
normals.radiant_stone_ti10_01_color='radiant_stone_ti10_01_normal';
for(const name of ['forest','thaw']){
 palettes[name][1]=['grass_bumpy_00_color',[.34,.46,.23]];
 palettes[name][3]=['radiant_stone_ti10_01_color',[.58,.55,.47]];
}
palettes.volcanic[1]=['basalt_00_color',[1.05,.92,.80]];
palettes.volcanic[2]=['lava_02_color',[.95,.62,.36]];
palettes.volcanic[3]=['lava_01_color',[.85,.48,.24]];
// Cold, worn flagstones for the prison/challenge region; grates are models, not a texture atlas tiled on the ground.
// The adjoining camp and paving must share the same grass/stone layers so paint
// can cross the biome boundary instead of fading both sides into a stone stripe.
palettes.corrupt=palettes.forest.map(([texture,tint])=>[texture,[...tint]]);
for(const [name,layers]of Object.entries(palettes)){
 layers[0]=['cliff_wall002_color',[.50,.57,.51]];
 let s='"Layer0"\n{\n "shader" "multiblend.vfx"\n "F_WORLDSPACE_UVS" "1"\n "F_SPECULAR" "0"\n "F_NORMAL_MAP" "1"\n "g_flBumpStrength" "0.6"\n';
 layers.forEach(([texture,tint],i)=>{s+=` "TextureColor${i}" "${tex(texture)}"\n "g_vColorTint${i}" "[${tint.join(' ')} 0]"\n "g_flTexCoordScale${i}" "${i===3?3:2.5}"\n "TextureRevealMask${i}" "${reveal[texture]?tex(reveal[texture]):'[0.5 0.5 0.5 0]'}"\n "TextureNormal${i}" "${normals[texture]?tex(normals[texture]):'[0.5 0.5 1 0]'}"\n "TextureSelfIllumMask${i}" "[0 0 0 0]"\n "TextureBloom${i}" "[0 0 0 0]"\n`;});
 if(['forest','thaw','corrupt'].includes(name)){
  s=s.replace('"g_flTexCoordScale1" "2.5"','"g_flTexCoordScale1" "4.7"');
  // The native moss tint mask has discontinuous opposite edges and needs the
  // native multi-grass combination. Do not tile it alone on the camp floor.
  s+=' "g_flTexCoordRotate1" "13"\n';
 }
 s+=' "Attributes" { "dota.nav.walkable" "1" }\n}\n';fs.writeFileSync(path.join(materialDir,'transition_'+name+'.vmat'),s);
}
// Use the native generic river shader, including its fog/flow configuration.
// The authored mesh sets shallow water depth; navigation stays on the continuous bed.
let water=fs.readFileSync(path.join(root,'output/reference_asset_study/water_decompiled/water_generic_000.vmat'),'utf8');
const waterSource=path.join(root,'output/reference_asset_study/water_decompiled');
water=water.replace(/"(Texture\w+)"\s*"([^"\[\]]+\.png)"/g,(m,k,p)=>{const base=path.basename(p);fs.copyFileSync(path.join(waterSource,base),path.join(materialDir,base));return '"'+k+'" "materials/survival_world_v2/'+base+'"';});
fs.writeFileSync(path.join(materialDir,'shallow_water.vmat'),water);
let ocean=fs.readFileSync(path.join(root,'output/reference_asset_study/art_decompiled/materials/water/water_econ_dota_blue.vmat'),'utf8');
ocean=ocean.replace(/"(Texture\w+)"\s*"([^"\[\]]+\.png)"/g,(m,k,p)=>'"'+k+'" "'+tex(path.basename(p,'.png'))+'"');
// Use the explicit blue fog rather than the old terrain's brown fog map.
ocean=ocean.replace('"F_FLOW_NORMALS"\t"1"','"F_FLOW_NORMALS" "1"\n "F_USE_FOG_COLOR" "1"');
fs.writeFileSync(path.join(materialDir,'ocean_water.vmat'),ocean);
fs.writeFileSync(path.join(materialDir,'shallow_water.vmat'),ocean);
const spa=water.replace(/"g_vWaterFogColor"\s*"[^"]+"/,'"g_vWaterFogColor" "[0.23 0.48 0.43 1]"').replace(/"g_flWaterDepth"\s*"[^"]+"/,'"g_flWaterDepth" "22"').replace(/"g_flBumpStrength"\s*"[^"]+"/,'"g_flBumpStrength" "0.25"');
fs.writeFileSync(path.join(materialDir,'spring_water.vmat'),spa);
const report=[];
function endBlock(s,start){let depth=0,quote=false;for(let i=start;i<s.length;i++){if(s[i]==='"'&&s[i-1]!=='\\')quote=!quote;if(!quote){if(s[i]==='{')depth++;else if(s[i]==='}'&&!--depth)return i+1;}}throw Error('Unbalanced DMX');}
for(const name of ['radiant_basic','dire_basic','radiant_snow_basic','radiant_autumn_basic']){
 const dest=path.join(tileDir,name+'.vmap');
 cp.execFileSync('D:/steam/steamapps/common/dota 2 beta/game/bin/win64/dmxconvert.exe',['-i','D:/steam/steamapps/common/dota 2 beta/content/dota/maps/tilesets/'+name+'.vmap','-o',dest,'-oe','keyvalues2'],{stdio:'pipe'});
 let s=fs.readFileSync(dest,'utf8'),count=0,offset=0;const re=/"CMapEntity"\s*\{/g;let m;
 while((m=re.exec(s))){const start=m.index,end=endBlock(s,s.indexOf('{',start));let block=s.slice(start,end);if(/"model" "string" "[^"]*(?:lily|lotus)[^"]*"/i.test(block)){block=block.replace(/"editorOnly" "bool" "0"/g,'"editorOnly" "bool" "1"').replace(/"force_hidden" "bool" "0"/g,'"force_hidden" "bool" "1"').replace(/"renderamt" "string" "255"/g,'"renderamt" "string" "0"');s=s.slice(0,start)+block+s.slice(end);count++;}re.lastIndex=start+block.length;}
 s=s.replace(/materials\/water\/water_(?:generic|spring|autumn|ice_generic)_000(?:_slope)?\.vmat/g,'materials/survival_world_v2/ocean_water.vmat');
 if(name==='radiant_basic')s=s.replace(/materials\/blends\/mod_radiant_(?:000|path_000)\.vmat/g,'maps/ti10_assets/blends/mod_radiant_ti10_000.vmat');
 fs.writeFileSync(dest,s);report.push({template:name,disabledLilyEntities:count});
}
fs.writeFileSync(path.join(out,'transition_asset_audit.json'),JSON.stringify({palettes:Object.keys(palettes),textures:[...copied],templates:report},null,2));console.log(report);
