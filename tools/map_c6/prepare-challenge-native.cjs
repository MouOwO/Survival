// Official textures and official winter tile geometry, isolated in addon assets.
const fs=require('fs'),path=require('path'),crypto=require('crypto'),L=require('./lib.cjs');
const out='output/challenge_native',dest=out+'/assets/materials/challenge_native';fs.mkdirSync(dest,{recursive:true});
const sources=['output/reference_asset_study/transition_decompiled/materials/blends',out,'output/reference_asset_study/art_decompiled/materials/blends','output/reference_asset_study/floors_decompiled'];
const copied=[];function tex(name){const p=sources.map(d=>path.join(d,name)).find(p=>fs.existsSync(p));if(!p)throw Error('Missing official image '+name);fs.copyFileSync(p,path.join(dest,name));copied.push({file:name,source:p,sha256:crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex')});return 'materials/challenge_native/'+name;}
function mat(name,layers){let s='"Layer0"\n{\n "shader" "multiblend.vfx"\n "F_SPECULAR" "1"\n "F_WORLDSPACE_UVS" "1"\n "g_flSpecularIntensity" "0.55"\n "g_flSpecularBloom" "0"\n';
 layers.forEach((l,i)=>{s+=` "TextureColor${i}" "${tex(l.color)}"\n "TextureReflectance${i}" "${l.refl?tex(l.refl):'[0.08 0.08 0.08 0]'}"\n "g_flTexCoordScale${i}" "${l.scale||6}"\n "g_flTexCoordRotate${i}" "0"\n "g_vTexCoordOffset${i}" "[0 0 0 0]"\n "g_vTexCoordScroll${i}" "[0 0 0 0]"\n "g_vColorTint${i}" "[${l.tint||'1 1 1'} 0]"\n "TextureSelfIllumMask${i}" "${l.emit?tex(l.emit):'[0 0 0 0]'}"\n "TextureBloom${i}" "[0 0 0 0]"\n`;if(i)s+=` "TextureRevealMask${i}" "${l.mask?tex(l.mask):'[0.5 0.5 0.5 0]'}"\n`;});
 s+=' "Attributes" { "dota.nav.walkable" "1" "dota.tile_transition_material" "1" }\n}\n';fs.writeFileSync(dest+'/'+name+'.vmat',s);}
const rock={color:'cliff_tintable_00.png',tint:'.43 .47 .50'},snow={color:'snow_directional_00_color.png',refl:'snow_directional_00_refl.png',mask:'snow_directional_00_3a703903_blend.png'},ice={color:'river_mud001_ice_color.png',mask:'river_mud001_ice_b50e1e69_blend.png',tint:'.86 .95 1'},iceRock={color:'river_rock001_ice_color.png',refl:'river_rock001_refl.png',mask:'river_rock001_ice_188ec75b_blend.png'};
const basalt={color:'basalt_00_color.png',refl:'basalt_00_refl.png',mask:'basalt_00_ec01ebeb_blend.png'},gravel={color:'dirt_path006_color.png',tint:'.55 .57 .61'},lava={color:'lava_02_color.png',emit:'lava_02_selfillum.png',mask:'lava_02_a9d87084_blend.png'};
mat('snow_blend',[rock,snow,ice,iceRock]);
mat('volcanic_blend',[{...basalt,tint:'.62 .67 .72'},basalt,gravel,lava]);
mat('waterfire_blend',[basalt,iceRock,ice,lava]);
let s=fs.readFileSync(out+'/snow_tileset.vmap','utf8');
// Snow tiles use an opaque ice sheet at z=16. Match the neighbouring official
// water instead. Sloped ice belongs to the bank, never to animated sea water.
s=s.replaceAll('materials/water/water_ice_generic_000_slope.vmat','materials/blends/mod_radiant_winter_000.vmat').replaceAll('materials/water/water_ice_generic_000.vmat','materials/water/water_flow.vmat');
const edits=[];
for(const b of L.blocks(s,'CMapTileSet')){
 const start=b.text.lastIndexOf('"materialSets" "element_array"'),a=b.text.indexOf('[',start),e=L.endOf(b.text,a,'[',']');
 const original=[...new Set(L.blocks(b.text,'CMapMesh').flatMap(q=>L.array(q.text,'materials')).filter(m=>m.startsWith('materials/blends/')))];
 if(!original.length)continue;
 const ms=(name,mats)=>`"CTileSetMaterialSet" { "id" "elementid" "${crypto.randomUUID()}" "name" "string" "${name}" "materialNames" "string_array" [${mats.map(m=>'"'+m+'"').join(',')}] "grassParams" "element" "" }`;
 const sets=[ms('Original Materials',original),...['snow','volcanic','waterfire'].map(theme=>ms('Challenge '+theme,original.map(()=>`materials/challenge_native/${theme}_blend.vmat`)))];
 edits.push({...b,text:b.text.slice(0,a)+'['+sets.join(',')+']'+b.text.slice(e)});
}
for(const e of edits.sort((a,b)=>b.start-a.start))s=s.slice(0,e.start)+e.text+s.slice(e.end);
fs.mkdirSync(out+'/assets/maps/tilesets',{recursive:true});fs.writeFileSync(out+'/assets/maps/tilesets/survival_challenge_native.vmap',s);
fs.writeFileSync(out+'/material_sources.json',JSON.stringify({textures:[...new Map(copied.map(c=>[c.file,c])).values()],water:'Official water_flow replaces winter ice sheet at the same water level; sloped ice becomes bank material',sets:['original','snow','volcanic','waterfire'],uv:'Shared world-space coordinates; static land UVs, no scrolling basalt'},null,2));
console.log('Prepared official four-channel materials and private native tile set.');
