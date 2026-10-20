'use strict';
// Generate explicit, noncolliding texture recipes. Input PNGs are never edited.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {checked}=require('./build_textures.cjs');const root=path.resolve(__dirname,'../..'),task='archive_icon_clarity_20261018';
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const args=process.argv.slice(2);assert(args.length===0||(args.length===1&&args[0]==='--all'),'Usage: prepare.cjs [--all]');
const count=args.includes('--all')?23:1,textures=[];
for(let i=1;i<=count;i++){
 const number=String(i).padStart(2,'0'),id='shadow_'+number,relativePng='images/custom_game/archive_v10/items/virtual_'+number+'.png',png='panorama/src/'+relativePng,raw=fs.readFileSync(checked(root,png));
 assert.equal(raw.subarray(0,8).toString('hex'),'89504e470d0a1a0a');const size=[raw.readUInt32BE(16),raw.readUInt32BE(20)];assert.deepEqual(size,[256,256],'retained V10 original source dimensions');
 const recipeText=`<!-- dmx encoding keyvalues2_noids 1 format vtex 1 -->
"CDmeVtex"
{
    "m_inputTextureArray" "element_array" [ "CDmeInputTexture" { "m_name" "string" "0" "m_fileName" "string" "panorama/${relativePng}" "m_colorSpace" "string" "srgb" "m_typeString" "string" "2D" } ]
    "m_outputTypeString" "string" "2D"
    "m_outputFormat" "string" "BGRA8888"
    "m_outputClearColor" "vector4" "0 0 0 0"
    "m_nOutputMinDimension" "int" "0"
    "m_nOutputMaxDimension" "int" "0"
    "m_bNoLod" "bool" "1"
    "m_textureOutputChannelArray" "element_array" [ "CDmeTextureOutputChannel" { "m_inputTextureArray" "string_array" [ "0" ] "m_srcChannels" "string" "rgba" "m_dstChannels" "string" "rgba" "m_mipAlgorithm" "CDmeImageProcessor" { "m_algorithm" "string" "" "m_stringArg" "string" "" "m_vFloat4Arg" "vector4" "0 0 0 0" } "m_outputColorSpace" "string" "srgb" } ]
}
`;
 const relativeRecipe='images/custom_game/archive_icons_hd_v1/'+id+'.vtex',recipe='panorama/src/'+relativeRecipe,recipeArt='art/ui/sources/custom_game/archive_icons_hd_v1/'+id+'.vtex';
 for(const relative of [recipe,recipeArt]){const out=checked(root,relative);fs.mkdirSync(path.dirname(out),{recursive:true});fs.writeFileSync(out,recipeText);}
 textures.push({id,png,png_sha256:hash(raw),size,recipe,recipe_art:recipeArt,recipe_sha256:hash(Buffer.from(recipeText)),relative_png:relativePng,relative_recipe:relativeRecipe,runtime:'panorama/'+relativeRecipe+'_c',uri:'s2r://panorama/'+relativeRecipe,legacy_uri:'file://{images}/custom_game/archive_v10/items/virtual_'+number+'.png'});
}
const plan={schema_version:1,policy:'Retain unmodified V10 original PNGs; noncolliding explicit BGRA8888, NO_LOD, single-mip textures. Ordinary PNG dependency compilation cannot address these separate runtime paths. Central resource registry is changed by the integrating task.',textures};
fs.writeFileSync(checked(root,'tools/'+task+'/texture_plan.json'),JSON.stringify(plan,null,2)+'\n');console.log(JSON.stringify({status:'PREPARED_EXPLICIT_TEXTURES',count,ids:textures.map(r=>r.id),original_pngs_modified:false,runtime_compiled:false,registry_modified:false}));
