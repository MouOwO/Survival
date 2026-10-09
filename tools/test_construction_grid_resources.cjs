// Verify shipped resources, not just generator settings: NO_LOD must preserve
// the complete DXT5 mip chain and the approved source images.
'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'..'),assetRoot=path.join(root,'art/effects/construction_grid');
function textureInfo(bytes){
 assert.ok(bytes.length>=16,'compiled resource header');
 const payloadOffset=bytes.readUInt32LE(0),table=8+bytes.readUInt32LE(8),count=bytes.readUInt32LE(12);
 assert.ok(table+count*12<=payloadOffset&&payloadOffset<=bytes.length,'compiled resource block table');
 let data;
 for(let i=0;i<count;i++){
  const at=table+i*12,offset=at+4+bytes.readUInt32LE(at+4),size=bytes.readUInt32LE(at+8);
  assert.ok(offset+size<=payloadOffset,'compiled resource block bounds');
  if(bytes.toString('ascii',at,at+4)==='DATA')data=bytes.subarray(offset,offset+size);
 }
 assert.ok(data&&data.length>=28,'texture DATA header');
 assert.equal(data.readUInt16LE(0),1,'supported Source2 texture DATA version');
 return {flags:data.readUInt16LE(2),width:data.readUInt16LE(20),height:data.readUInt16LE(22),
  depth:data.readUInt16LE(24),format:data[26],mipLevels:data[27],payload:bytes.subarray(payloadOffset)};
}
function verify(){
 const manifest=JSON.parse(fs.readFileSync(path.join(assetRoot,'manifest.json'),'utf8'));
 assert.equal(manifest.resources.length,4,'all world grid phases shipped');
 assert.equal(manifest.texture_loading.no_lod,true,'manifest requests full resolution');
 assert.equal(manifest.texture_loading.mip_levels,10,'manifest keeps camera minification mips');
 let payloadBytes=0;
 for(const entry of manifest.resources){
  assert.match(entry.texture,/^materials\/survival_grid\/reference_grid_[0-3]\.vtex$/);
  const source=path.join(assetRoot,'source',entry.texture),vtex=fs.readFileSync(source,'utf8');
  assert.match(vtex,/"m_bNoLod"\s+"bool"\s+"1"/,'source requests full resolution');
  assert.match(vtex,/"m_mipAlgorithm"\s+"CDmeImageProcessor"\s*\{\s*"m_algorithm"\s+"string"\s+"Box"/,'source retains mip filtering');
  const image=fs.readFileSync(source.replace(/\.vtex$/,'.png'));
  assert.equal(crypto.createHash('sha256').update(image).digest('hex'),entry.png_sha256,'source PNG matches checked manifest');
  const info=textureInfo(fs.readFileSync(path.join(root,entry.texture+'_c')));
  assert.equal(info.flags&8,8,entry.texture+': compiled NO_LOD must be present');
  assert.deepEqual([info.width,info.height,info.depth,info.format,info.mipLevels],[2048,2048,1,2,10],entry.texture+': DXT5 mip chain must remain intact');
  let expectedBytes=0;
  for(let mip=0;mip<info.mipLevels;mip++)expectedBytes+=Math.ceil((info.width>>mip)/4)*Math.ceil((info.height>>mip)/4)*16;
  assert.equal(info.payload.length,expectedBytes,entry.texture+': all DXT5 mip payloads must exist');
  payloadBytes+=info.payload.length;
 }
 return {result:'CONSTRUCTION_GRID_RESOURCES_PASS',textures:4,no_lod:true,mip_levels:10,payload_bytes:payloadBytes};
}
module.exports={textureInfo,verify};
if(require.main===module)console.log(JSON.stringify(verify()));
