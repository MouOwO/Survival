const fs=require('fs'),p=require('path'),crypto=require('crypto');
module.exports=function(repo,write,assets){
 const rows=JSON.parse(fs.readFileSync(p.join(__dirname,'art/audit.json'),'utf8'));
 if(rows.length!==52||new Set(rows.map(r=>r.card_id)).size!==52)throw Error('Rogue art audit is incomplete');
 const map={};
 for(const row of rows){
  const runtime='images/'+row.image_path,source='panorama/src/'+runtime,bytes=fs.readFileSync(p.join(repo,source));
  const hash=crypto.createHash('sha256').update(bytes).digest('hex');if(hash!==row.sha256)throw Error('Rogue art changed: '+row.card_id);
  write(runtime,bytes);assets.push({original_path:source,runtime,sha256:hash,kind:'generated_rogue_art'});
  const texture='images/custom_game/rogue_cards_gpu/'+row.card_id+'.vtex';
  const recipe='<!-- dmx encoding keyvalues2_noids 1 format vtex 1 -->\n"CDmeVtex"\n{\n'+
   '"m_inputTextureArray" "element_array" [ "CDmeInputTexture" { "m_name" "string" "0" "m_fileName" "string" "panorama/'+runtime+'" "m_colorSpace" "string" "srgb" "m_typeString" "string" "2D" } ]\n'+
   '"m_outputTypeString" "string" "2D"\n"m_outputFormat" "string" "BGRA8888"\n"m_outputClearColor" "vector4" "0 0 0 0"\n"m_nOutputMinDimension" "int" "0"\n"m_nOutputMaxDimension" "int" "768"\n"m_bNoLod" "bool" "0"\n'+
   '"m_textureOutputChannelArray" "element_array" [ "CDmeTextureOutputChannel" { "m_inputTextureArray" "string_array" [ "0" ] "m_srcChannels" "string" "rgba" "m_dstChannels" "string" "rgba" "m_mipAlgorithm" "CDmeImageProcessor" { "m_algorithm" "string" "" "m_stringArg" "string" "" "m_vFloat4Arg" "vector4" "0 0 0 0" } "m_outputColorSpace" "string" "srgb" } ]\n}\n';
  write(texture,recipe);assets.push({original_path:'art/ui/development/remaining_ui_handoff_v1/candidate/panorama/'+texture,runtime:texture,sha256:crypto.createHash('sha256').update(recipe).digest('hex'),kind:'compiled_icon_recipe'});
  map[row.card_id]={uri:'s2r://panorama/'+texture};
 }
 return map;
};
