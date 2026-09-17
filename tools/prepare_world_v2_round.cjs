const fs=require('fs'),path=require('path');
module.exports=function(root){
 const out=path.join(root,'output/survival_world_v2'),dir=path.join(out,'source_materials'),ocean=path.join(root,'output/ocean_study');
 const set=(s,k,v)=>{const re=new RegExp('"'+k+'"\\s*"[^"\\n]*"');return re.test(s)?s.replace(re,'"'+k+'" "'+v+'"'):s.replace(/\n\{/,'\n{\n "'+k+'" "'+v+'"');};
 let grass=fs.readFileSync(path.join(dir,'transition_forest.vmat'),'utf8');
 grass=set(grass,'TextureColor0','materials/survival_world_v2/mountain_stone001_color.png');
 grass=set(grass,'TextureNormal0','materials/survival_world_v2/mountain_stone001_normal.png');
 grass=set(grass,'g_vColorTint0','[0.51 0.55 0.51 0]');grass=set(grass,'g_flTexCoordScale0','2.6');
 grass=set(grass,'g_vColorTint1','[0.36 0.48 0.36 0]');grass=set(grass,'g_vColorTint2','[0.58 0.54 0.44 0]');
 grass=set(grass,'g_flBumpStrength','.45');
 fs.writeFileSync(path.join(dir,'island_meadow.vmat'),grass);
 let shore='"Layer0"\n{\n "shader" "global_lit_simple.vfx"\n "F_NORMAL_MAP" "1"\n "TextureColor" "materials/survival_world_v2/mountain_stone001_color.png"\n "TextureNormal" "materials/survival_world_v2/mountain_stone001_normal.png"\n "g_vColorTint" "[0.51 0.55 0.51 0]"\n}\n';
 fs.writeFileSync(path.join(dir,'island_natural_rock.vmat'),shore);
 for(const file of fs.readdirSync(ocean).filter(n=>n.endsWith('.png')))fs.copyFileSync(path.join(ocean,file),path.join(dir,file));
 let wave=fs.readFileSync(path.join(ocean,'water_ocean_00.vmat'),'utf8').replace(/\s*"Compiled Textures"\s*\{[^}]*\}/,'').replaceAll('materials/nature/','materials/survival_world_v2/');
 wave=wave.replace('"dota.nav.walkable"\t"1"','"mapbuilder.nonsolid" "1"\n "mapbuilder.water" "1"');
 wave=set(wave,'F_WORLDSPACE_UVS','1');wave=set(wave,'F_DO_NOT_CAST_SHADOWS','1');
 wave=set(wave,'F_NORMAL_MAP','1');wave=set(wave,'g_flBumpStrength','.18');wave=set(wave,'g_flSpecularIntensity','.4');wave=set(wave,'g_flSpecularBloom','0');
 for(let i=0;i<4;i++)wave=set(wave,'TextureNormal'+i,'materials/survival_world_v2/water_river_oil_normal.png');
 for(let i=0;i<4;i++){wave=set(wave,'g_flScrollWaveHeight'+i,'0');wave=set(wave,'g_flTexCoordScale'+i,[.65,.45,.65,.8][i]);wave=set(wave,'g_vColorTint'+i,i===1||i===2?'[0.48 0.58 0.57 0]':'[0.65 0.90 1.20 0]');}
 // Color/foam scroll is animated; water remains at a stable physical elevation.
 wave=set(wave,'TextureColor0','[0.055 0.26 0.36 1]');
 wave=set(wave,'TextureColor3','[0.065 0.29 0.39 1]');
 wave=set(wave,'g_vColorTint0','[1 1 1 0]');wave=set(wave,'g_vColorTint3','[1 1 1 0]');
 fs.writeFileSync(path.join(dir,'island_ocean_waves.vmat'),wave);
 let shallows=set(wave,'TextureColor3','[0.085 0.34 0.42 1]');
 shallows=set(shallows,'F_SCROLL_WAVES','0');
 shallows=set(shallows,'TextureRevealMask3','[0.5 0.5 0.5 0]');
 shallows=set(shallows,'g_vColorTint3','[1 1 1 0]');shallows=set(shallows,'g_vTexCoordScroll3','[0 0 0 0]');shallows=set(shallows,'g_flTexCoordScale3','.65');
 fs.writeFileSync(path.join(dir,'island_shallow_blend.vmat'),shallows);
 // The native outer sea mesh has its own paint streams; all its slots use ocean
 // color, so those old streams cannot turn the entire sea into foam.
 let outer=wave;
 for(let i=1;i<4;i++)for(const [kind,file]of Object.entries({Color:'water_ocean_00_color.png',Reflectance:'water_ocean_00_refl.png'}))outer=set(outer,'Texture'+kind+i,'materials/survival_world_v2/'+file);
 for(let i=1;i<4;i++){outer=set(outer,'TextureRevealMask'+i,'[0.5 0.5 0.5 0]');outer=set(outer,'TextureColor'+i,'[0.055 0.26 0.36 1]');outer=set(outer,'g_vColorTint'+i,'[1 1 1 0]');}
 fs.writeFileSync(path.join(dir,'ocean_water.vmat'),outer);
 fs.writeFileSync(path.join(out,'round_water_design.json'),JSON.stringify({source:'Valve materials/blends/water_ocean_00',shader:'multiblend.vfx',features:['F_SCROLL_WAVES on ocean only','animated normals','shore-weighted foam','480-unit shallow depth color transition'],physicalWaves:false,centralShallows:'island_shallow_blend.vmat at 400; walkable floor 396; teal depth-color layer with constant reveal mask',oceanSurface:400},null,2));
};
