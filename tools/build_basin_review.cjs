// Independent gameplay-layout/art sample. Does not replace survival_world_v2.
const fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'..'),out=path.join(root,'output/basin_review');fs.mkdirSync(out,{recursive:true});
const set=(s,k,v)=>s.replace(new RegExp('"'+k+'"\\s*"[^"\\n]*"'),'"'+k+'" "'+v+'"');
const materialDir=path.join(out,'materials');fs.mkdirSync(materialDir,{recursive:true});
const themes=['peach','snow','pine','sand'];
for(const theme of themes){
 let s=fs.readFileSync(path.join(root,'output/survival_world_v2/source_materials/transition_'+(theme==='snow'?'snow':'forest')+'.vmat'),'utf8');
 s=set(s,'TextureColor0','materials/survival_world_v2/mountain_stone001_color.png');
 s=set(s,'TextureNormal0','materials/survival_world_v2/mountain_stone001_normal.png');
 const tint={peach:['.50 .62 .57','.36 .53 .42','.58 .57 .45','.55 .68 .61'],snow:['.47 .55 .60','.82 .87 .88','.59 .67 .71','.57 .64 .69'],pine:['.50 .56 .49','.43 .56 .39','.56 .52 .40','.61 .63 .53'],sand:['.70 .57 .43','.67 .55 .40','.73 .61 .45','.74 .61 .45']}[theme];
 if(theme==='sand'){
  s=set(s,'TextureColor1','materials/survival_world_v2/sand_path009_color.png');s=set(s,'TextureNormal1','materials/survival_world_v2/sand_path001_normal.png');
  s=set(s,'TextureRevealMask1','materials/survival_world_v2/sand_cracked001_1017aede_blend.png');
 }
 for(let i=0;i<4;i++){s=set(s,'g_vColorTint'+i,'['+tint[i]+' 0]');s=set(s,'g_flTexCoordScale'+i,[2.8,3.8,2.6,2.7][i]);}
 fs.writeFileSync(path.join(materialDir,theme+'.vmat'),s);
 let wall='"Layer0"\n{\n "shader" "global_lit_simple.vfx"\n "F_NORMAL_MAP" "1"\n "TextureColor" "materials/survival_world_v2/mountain_stone001_color.png"\n "TextureNormal" "materials/survival_world_v2/mountain_stone001_normal.png"\n "g_vColorTint" "['+tint[0]+' 0]"\n}\n';
 fs.writeFileSync(path.join(materialDir,theme+'_rock.vmat'),wall);
 let stone=fs.readFileSync(path.join(root,'output/xianxia_kit/source_materials/xx_stone.vmat'),'utf8');
 stone=set(stone,'g_vColorTint','['+tint[3]+' 0]');stone=stone.replace(/}\s*$/,' "Attributes" { "dota.nav.walkable" "1" }\n}\n');fs.writeFileSync(path.join(materialDir,theme+'_stone.vmat'),stone);
}
let src=fs.readFileSync(path.join(__dirname,'build_zombie_abyss_map.cjs'),'utf8');
let prefix=src.slice(0,src.indexOf("water('central_sea'"));
prefix=prefix.replace('../output/zombie_island_v1','../output/basin_review').replace('zombie-abyss-v1-','basin-review-');
prefix=prefix.replace("stream('normal','vector3',edges.map(e=>normals[e.face]),1)","stream('normal','vector3',edges.map(e=>paintNormal&&faces[e.face].m===0?paintNormal(verts[e.b]):normals[e.face]),1),stream('VertexPaintBlendParams','vector4',edges.map(e=>paintVertex&&faces[e.face].m===0?paintVertex(verts[e.b]):[0,0,0,0]),1),stream('VertexPaintBlendParams1','vector4',edges.map(()=>[.36,.32,.30,0]),1),stream('VertexPaintTintColor','vector4',edges.map(()=>[1,1,1,0]),1)");
prefix=prefix.replace("return Math.abs(n[2])>.5?", "return floorUV&&faces[e.face].m===0?floorUV(p):Math.abs(n[2])>.5?");
new Function('require','__dirname','let paintVertex=null,paintNormal=null,floorUV=null;\n'+prefix+fs.readFileSync(path.join(__dirname,'basin_review_scene.cjs'),'utf8'))(require,__dirname);
