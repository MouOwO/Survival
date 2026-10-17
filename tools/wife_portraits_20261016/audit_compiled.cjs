'use strict';
// Read native bytes to verify resolution, alpha, identity and single-mip format.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {textureInfo}=require('../test_construction_grid_resources.cjs');
const repo=path.resolve(__dirname,'../..'),hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const manifest=JSON.parse(fs.readFileSync(path.join(repo,'data/ui/wife_portraits_v1.json'),'utf8'));
assert.equal(manifest.art_status,'generated_wife_portrait_v1');assert.equal(Object.keys(manifest.items).length,40);
const records=Object.entries(manifest.items).map(([id,asset])=>{
 const original=fs.readFileSync(path.join(repo,'panorama/src/images',asset.icon_path)),recipe=fs.readFileSync(path.join(repo,asset.recipe_path),'utf8');
 assert.equal(hash(original),asset.sha256,id+': source original bytes');assert.deepEqual([original.readUInt32BE(16),original.readUInt32BE(20)],[asset.source_width,asset.source_height]);
 assert(recipe.includes('"panorama/images/'+asset.icon_path+'"'),id+': exact same-id recipe input');
 assert.match(recipe,/"m_outputFormat"\s+"string"\s+"BGRA8888"/);assert.match(recipe,/"m_nOutputMaxDimension"\s+"int"\s+"512"/);
 assert.match(recipe,/"m_bNoLod"\s+"bool"\s+"1"/);assert.match(recipe,/"m_mipAlgorithm"\s+"CDmeImageProcessor"\s*\{\s*"m_algorithm"\s+"string"\s+""/);
 const compiled=fs.readFileSync(path.join(repo,asset.runtime_uri.replace('s2r://','')+'_c')),info=textureInfo(compiled);
 assert.deepEqual([info.flags,info.width,info.height,info.depth,info.format,info.mipLevels],[8,512,512,1,28,1],id+': native NO_LOD 512px BGRA8888 single mip');
 assert.equal(info.payload.length,1048576,id+': complete RGBA base level');
 let transparent=0,opaque=0;for(let i=3;i<info.payload.length;i+=4){if(info.payload[i]===0)transparent++;if(info.payload[i]>=250)opaque++;}
 assert(transparent>0&&opaque>0,id+': real native alpha and opaque subject');
 return {id,canonical_name:asset.canonical_name,series:asset.series,width:info.width,height:info.height,format:'BGRA8888',mips:1,no_lod:true,transparent_texels:transparent,opaque_texels:opaque,compiled_sha256:hash(compiled),source_sha256:asset.sha256};
});
console.log(JSON.stringify({status:'PASS_NATIVE_WIFE_TEXTURES',count:records.length,records},null,2));
