'use strict';
// Preserve the existing welfare seal pixels; no registry or runtime mutation.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../..'),png='panorama/src/images/custom_game/archive_handoff_v1/art_01.png';
const bytes=fs.readFileSync(path.join(root,png)),hash=b=>crypto.createHash('sha256').update(b).digest('hex');
assert.equal(bytes.subarray(0,8).toString('hex'),'89504e470d0a1a0a');
const size=[bytes.readUInt32BE(16),bytes.readUInt32BE(20)];assert.deepEqual(size,[130,95],'Only the existing original-size seal is accepted');
const sourceHash=hash(bytes),relative='images/custom_game/archive_icons_hd_v1/welfare_seal.vtex';
const text=`<!-- dmx encoding keyvalues2_noids 1 format vtex 1 -->
"CDmeVtex"
{
    "m_inputTextureArray" "element_array" [ "CDmeInputTexture" { "m_name" "string" "0" "m_fileName" "string" "panorama/images/custom_game/archive_handoff_v1/art_01.png" "m_colorSpace" "string" "srgb" "m_typeString" "string" "2D" } ]
    "m_outputTypeString" "string" "2D"
    "m_outputFormat" "string" "BGRA8888"
    "m_outputClearColor" "vector4" "0 0 0 0"
    "m_nOutputMinDimension" "int" "0"
    "m_nOutputMaxDimension" "int" "0"
    "m_bNoLod" "bool" "1"
    "m_textureOutputChannelArray" "element_array" [ "CDmeTextureOutputChannel" { "m_inputTextureArray" "string_array" [ "0" ] "m_srcChannels" "string" "rgba" "m_dstChannels" "string" "rgba" "m_mipAlgorithm" "CDmeImageProcessor" { "m_algorithm" "string" "" "m_stringArg" "string" "" "m_vFloat4Arg" "vector4" "0 0 0 0" } "m_outputColorSpace" "string" "srgb" } ]
}
`;
const artRecipe='art/ui/sources/'+relative.replace(/^images\//,'');
for(const file of ['panorama/src/'+relative,artRecipe]){fs.mkdirSync(path.dirname(path.join(root,file)),{recursive:true});fs.writeFileSync(path.join(root,file),text);}
assert.equal(hash(fs.readFileSync(path.join(root,png))),sourceHash,'Original PNG bytes stay unchanged');
const table=JSON.parse(fs.readFileSync(path.join(root,'data/ui/item_resources.json'),'utf8'));
const affected=table.items.filter(row=>['file://{images}/custom_game/archive_handoff_v1/art_01.png','s2r://panorama/images/custom_game/archive_icons_hd_v1/welfare_seal.vtex'].includes(row.uri));
assert.equal(affected.length,36,'All existing welfare IDs retain the same shared art identity');
const report={status:'PREPARED_NOT_COMPILED',source:png,source_sha256:sourceHash,size,recipe:'panorama/src/'+relative,recipe_art:artRecipe,recipe_sha256:hash(Buffer.from(text)),runtime:'panorama/'+relative+'_c',uri:'s2r://panorama/'+relative,old_uri:'file://{images}/custom_game/archive_handoff_v1/art_01.png',affected_ids:affected.map(row=>row.id),expected_native:{size,format:'BGRA8888',format_id:28,mips:1,no_lod:true,payload_bytes:size[0]*size[1]*4},source_upscaled:false,source_modified:false,registry_modified:false,runtime_compiled:false};
const output=path.join(root,'output/archive_images_audit_20261018/welfare_plan.json');fs.mkdirSync(path.dirname(output),{recursive:true});fs.writeFileSync(output,JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report,null,2));
