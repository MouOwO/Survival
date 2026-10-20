'use strict';
// Retain the supplied PNG bytes. All edge feathering is a separate vector UI mask.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../..'),folder='custom_game/archive_user_skin_v1';
const art=path.join(root,'art/ui/sources',folder),mirror=path.join(root,'panorama/src/images',folder),out=path.join(root,'output/archive_user_skin_20261019');
const option=process.argv.indexOf('--source'),check=process.argv.includes('--check');
assert(option<0||process.argv[option+1],'--source requires a PNG file');
const source=option>=0?path.resolve(process.argv[option+1]):path.join(art,'background.png');
const png=fs.readFileSync(source),sha=data=>crypto.createHash('sha256').update(data).digest('hex');
assert.equal(png.subarray(0,8).toString('hex'),'89504e470d0a1a0a','Supplied file must be a PNG');
const size=[png.readUInt32BE(16),png.readUInt32BE(20)];assert(size.every(n=>n>0));
const ramp='<stop offset="0" stop-color="white" stop-opacity="1"/><stop offset="0.25" stop-color="white" stop-opacity="0.9"/><stop offset="0.5" stop-color="white" stop-opacity="0.5"/><stop offset="0.75" stop-color="white" stop-opacity="0.1"/><stop offset="1" stop-color="white" stop-opacity="0"/>';
const backgroundMask=`<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 256 256" preserveAspectRatio="none">
  <defs>
    <linearGradient id="right" gradientUnits="userSpaceOnUse" x1="240" y1="0" x2="256" y2="0">${ramp}</linearGradient>
    <linearGradient id="bottom" gradientUnits="userSpaceOnUse" x1="0" y1="240" x2="0" y2="256">${ramp}</linearGradient>
    <radialGradient id="corner" gradientUnits="userSpaceOnUse" cx="240" cy="240" r="16">${ramp}</radialGradient>
  </defs>
  <rect width="240" height="240" fill="white"/>
  <rect x="240" width="16" height="240" fill="url(#right)"/>
  <rect y="240" width="240" height="16" fill="url(#bottom)"/>
  <rect x="240" y="240" width="16" height="16" fill="url(#corner)"/>
</svg>
`;
const rightMask=`<svg xmlns="http://www.w3.org/2000/svg" width="512" height="128" viewBox="0 0 256 64" preserveAspectRatio="none">
  <defs><linearGradient id="right" gradientUnits="userSpaceOnUse" x1="240" y1="0" x2="256" y2="0">${ramp}</linearGradient></defs>
  <rect width="240" height="64" fill="white"/>
  <rect x="240" width="16" height="64" fill="url(#right)"/>
</svg>
`;
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
const assets=[['background.png',png],['background_fade.svg',Buffer.from(backgroundMask)],['right_fade.svg',Buffer.from(rightMask)],['background.vtex',Buffer.from(recipe)]];
for(const directory of [art,mirror]){
 if(!check)fs.mkdirSync(directory,{recursive:true});
 for(const [name,bytes]of assets){const target=path.join(directory,name);if(check){const actual=fs.readFileSync(target);if(name.endsWith('.png'))assert.deepEqual(actual,bytes,'Original PNG: '+name);else assert.equal(actual.toString().replaceAll('\r\n','\n'),bytes.toString(),'Vector/texture recipe: '+name);}else fs.writeFileSync(target,bytes);}
}
const xml='<root>\n  <Panel visible="false" hittest="false" hittestchildren="false">\n'+assets.filter(([name])=>!name.endsWith('.png')).map(([name])=>'    <Image src="'+(name.endsWith('.vtex')?'s2r://panorama/images/':'file://{images}/')+folder+'/'+name+'" visible="false" hittest="false" style="visibility:collapse; width:0px; height:0px;" />').join('\n')+'\n  </Panel>\n</root>\n';
const layout=path.join(root,'panorama/src/layout/custom_game/archive_user_skin_assets.xml');
if(check)assert.equal(fs.readFileSync(layout,'utf8').replaceAll('\r\n','\n'),xml);else fs.writeFileSync(layout,xml);
if(!check){fs.mkdirSync(out,{recursive:true});fs.writeFileSync(path.join(out,'assets.json'),JSON.stringify({source,sourceSha256:sha(png),size,sourceBytesPreserved:true,texturePolicy:'Original supplied PNG; source and art mirrors are identical; static SVG masks feather only the right and bottom decoration edges.',assets:assets.map(([name,bytes])=>({path:folder+'/'+name,sha256:sha(bytes)}))},null,2));}
console.log('ARCHIVE_USER_SKIN_ASSETS_'+(check?'CHECK_PASS':'IMPORTED')+' '+size.join('x')+' PNG byte-for-byte retained');
