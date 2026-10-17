'use strict';
// Narrow resource-only maintenance. Existing source pixels and economics stay intact.
const fs=require('fs'),path=require('path'),assert=require('assert/strict'),crypto=require('crypto');
const root=path.resolve(__dirname,'../..'),master=path.join(root,'data/ui/item_resources.json'),out=path.join(root,'output/shop_icon_quality_20261017');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const original=fs.readFileSync(master),table=JSON.parse(original.toString('utf8').replace(/^\uFEFF/,''));
const ids=['weapon_growth_sword_01','equipment_attack_gloves_01','equipment_burning_blade_01','equipment_iron_armor_01','item_death_mask','item_forging_hammer','item_small_polar_crystal','item_knowledge_book','item_super_knowledge_book','service_early_final_boss'];
const native=JSON.parse(fs.readFileSync(path.join(out,'native/manifest.json'),'utf8')).records;
const changed=[],textures=[];
function change(id,uri,size){const row=table.items.find(r=>r.id===id);assert(row,'Exact existing resource '+id);const before=JSON.parse(JSON.stringify(row));row.kind='image';row.uri=uri;row.source_size=size;delete row.native_type;delete row.native_name;changed.push({id,before,after:JSON.parse(JSON.stringify(row))});}
function recipe(id,sourcePng,maxDimension){const source=fs.readFileSync(path.join(root,sourcePng)),size=[source.readUInt32BE(16),source.readUInt32BE(20)];assert(Math.min(...size)>=256,'Real original has sufficient pixels: '+id);const stem='custom_game/shop_icons_hd_v1/'+id,rel='panorama/src/images/'+stem+'.vtex',input=sourcePng.replace('panorama/src/','panorama/'),uri='s2r://panorama/images/'+stem+'.vtex';
 const text='<!-- dmx encoding keyvalues2_noids 1 format vtex 1 -->\n"CDmeVtex"\n{\n"m_inputTextureArray" "element_array" [ "CDmeInputTexture" { "m_name" "string" "0" "m_fileName" "string" "'+input+'" "m_colorSpace" "string" "srgb" "m_typeString" "string" "2D" } ]\n"m_outputTypeString" "string" "2D"\n"m_outputFormat" "string" "BGRA8888"\n"m_outputClearColor" "vector4" "0 0 0 0"\n"m_nOutputMinDimension" "int" "0"\n"m_nOutputMaxDimension" "int" "'+maxDimension+'"\n"m_bNoLod" "bool" "1"\n"m_textureOutputChannelArray" "element_array" [ "CDmeTextureOutputChannel" { "m_inputTextureArray" "string_array" [ "0" ] "m_srcChannels" "string" "rgba" "m_dstChannels" "string" "rgba" "m_mipAlgorithm" "CDmeImageProcessor" { "m_algorithm" "string" "" "m_stringArg" "string" "" "m_vFloat4Arg" "vector4" "0 0 0 0" } "m_outputColorSpace" "string" "srgb" } ]\n}\n';
 fs.mkdirSync(path.dirname(path.join(root,rel)),{recursive:true});fs.writeFileSync(path.join(root,rel),text);textures.push({id,sourcePng,sourcePngSha256:sha(source),sourceSize:size,recipe:rel,recipeSha256:sha(Buffer.from(text)),runtime:'panorama/images/'+stem+'.vtex_c',uri,targetMaxDimension:maxDimension,expectedMinimumDimension:256,expectedFormat:28,expectedFormatName:'BGRA8888',expectedNoLod:true,expectedMipLevels:1,dimensionPolicy:'Read compiled VTEX DATA header; Source2 may downsample non-power-of-two source dimensions in whole mip steps.'});return {uri,size};}
for(const id of ids){const t=recipe(id,'panorama/src/images/custom_game/archive_items_v2/shop_'+id+'.png',512);change(id,t.uri,t.size);}
const hammer=textures.find(r=>r.id==='item_forging_hammer');change('commerce_p013',hammer.uri,hammer.sourceSize);
const ticket=recipe('special_lottery_ticket','panorama/src/images/custom_game/lottery_tickets_v2/gold_ticket.png',256);change('pay_special_lottery_ticket_single',ticket.uri,ticket.size);
const red=native.find(r=>r.uri==='file://{images}/econ/tools/redemptiontoken.png');assert(red);change('commerce_p001',red.uri,[red.width,red.height]);
const heroes=['undying','bloodseeker','dragon_knight','sven','bane','life_stealer','dark_willow','grimstroke','spectre_alt1','doom_bringer'];
for(let i=0;i<heroes.length;i++){const uri='file://{images}/heroes/selection/npc_dota_hero_'+heroes[i]+'.png',asset=native.find(r=>r.uri===uri);assert(asset);change('rebirth_challenge_'+String(i+1).padStart(2,'0'),uri,[asset.width,asset.height]);}
assert.equal(changed.length,23);assert.equal(textures.length,11);
// Refuse to overwrite a concurrent maintenance write; read fresh next time.
assert.equal(sha(fs.readFileSync(master)),sha(original),'Resource table changed concurrently');
fs.writeFileSync(master,JSON.stringify(table,null,2)+'\n');
fs.mkdirSync(out,{recursive:true});fs.writeFileSync(path.join(out,'resource_changes.json'),JSON.stringify({scope:'Artwork metadata only; exact existing identities and aliases retained',previousHash:sha(original),newHash:sha(fs.readFileSync(master)),changed},null,2)+'\n');
fs.writeFileSync(path.join(out,'texture_plan.json'),JSON.stringify({schemaVersion:1,policy:'Use unmodified existing HD source PNGs; BGRA8888, no LOD, no mip chain; no interpolation upscaling',textures},null,2)+'\n');
console.log(JSON.stringify({changed:changed.length,textures:textures.length,hash:sha(fs.readFileSync(master))}));
