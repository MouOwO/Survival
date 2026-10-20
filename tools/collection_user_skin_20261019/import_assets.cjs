'use strict';
// Import supplied artwork byte-for-byte; encode its runtime texture losslessly.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../..'),folder='custom_game/collection_user_skin_v1',out=path.join(root,'output/collection_user_skin_20261019');
const art=path.join(root,'art/ui/sources',folder),mirror=path.join(root,'panorama/src/images',folder);
const index=process.argv.indexOf('--source'),check=process.argv.includes('--check'),source=index>=0?path.resolve(process.argv[index+1]):path.join(art,'background.png');
const png=fs.readFileSync(source),hash=b=>crypto.createHash('sha256').update(b).digest('hex');
assert.equal(png.subarray(0,8).toString('hex'),'89504e470d0a1a0a');const size=[png.readUInt32BE(16),png.readUInt32BE(20)];
const recipe=`<!-- dmx encoding keyvalues2_noids 1 format vtex 1 -->
"CDmeVtex"
{
    "m_inputTextureArray" "element_array" [ "CDmeInputTexture" { "m_name" "string" "0" "m_fileName" "string" "panorama/images/${folder}/background.png" "m_colorSpace" "string" "srgb" "m_typeString" "string" "2D" } ]
    "m_outputTypeString" "string" "2D"
    "m_outputFormat" "string" "BGRA8888"
    "m_outputClearColor" "vector4" "0 0 0 0"
    "m_nOutputMinDimension" "int" "0"
    "m_nOutputMaxDimension" "int" "0"
    "m_bNoLod" "bool" "1"
    "m_textureOutputChannelArray" "element_array" [ "CDmeTextureOutputChannel" { "m_inputTextureArray" "string_array" [ "0" ] "m_srcChannels" "string" "rgba" "m_dstChannels" "string" "rgba" "m_mipAlgorithm" "CDmeImageProcessor" { "m_algorithm" "string" "" "m_stringArg" "string" "" "m_vFloat4Arg" "vector4" "0 0 0 0" } "m_outputColorSpace" "string" "srgb" } ]
}
`;
for(const base of [art,mirror]){if(!check)fs.mkdirSync(base,{recursive:true});for(const [name,bytes]of [['background.png',png],['background.vtex',Buffer.from(recipe)]]){const file=path.join(base,name);if(check){const actual=fs.readFileSync(file);if(name.endsWith('.png'))assert.deepEqual(actual,bytes);else assert.equal(actual.toString().replaceAll('\r\n','\n'),bytes.toString());}else fs.writeFileSync(file,bytes);}}
const xml='<root>\n  <Panel visible="false" hittest="false" hittestchildren="false">\n    <Image src="s2r://panorama/images/'+folder+'/background.vtex" visible="false" hittest="false" style="visibility:collapse; width:0px; height:0px;" />\n  </Panel>\n</root>\n';
const layout=path.join(root,'panorama/src/layout/custom_game/collection_user_skin_assets.xml');
if(check)assert.equal(fs.readFileSync(layout,'utf8').replaceAll('\r\n','\n'),xml);else fs.writeFileSync(layout,xml);
if(!check){fs.mkdirSync(out,{recursive:true});fs.writeFileSync(path.join(out,'assets.json'),JSON.stringify({source,size,sha256:hash(png),bytes:png.length,sourceBytesPreserved:true,runtime:'s2r://panorama/images/'+folder+'/background.vtex'},null,2));}
console.log('COLLECTION_USER_SKIN_'+(check?'CHECK_PASS':'IMPORTED')+' '+size.join('x')+' original PNG retained');
