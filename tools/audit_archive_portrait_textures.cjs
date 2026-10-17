// Inspect the shipped texture bytes and original receipts, not just recipe text.
'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {textureInfo}=require('./test_construction_grid_resources.cjs');
const root=path.resolve(__dirname,'..');
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
function audit(ids,version){
 if(version!==undefined)assert.ok(['v3','v4','v5'].includes(version),'selected texture version');
 const receipts=JSON.parse(fs.readFileSync(path.join(root,'data/ui/archive_portraits_v3.json'),'utf8'));
 const expected=['friend','ex'].flatMap(group=>Array.from({length:40},(_,i)=>group+'_'+String(i+1).padStart(2,'0')));
 assert.deepEqual(Object.keys(receipts).sort(),expected.slice().sort(),'eighty original portrait receipts');
 ids=ids&&ids.length?ids:expected;
 assert.equal(new Set(ids).size,ids.length,'distinct selected portraits');
 return ids.map(id=>{
  assert.ok(expected.includes(id),'formal portrait ID: '+id);
  const receipt=receipts[id],image=fs.readFileSync(path.join(root,'panorama/src/images/custom_game/archive_portraits_v3',id+'.png'));
  assert.equal(hash(image),receipt.sha256,id+': approved source pixels unchanged');
  assert.equal(image.subarray(0,8).toString('hex'),'89504e470d0a1a0a',id+': source PNG');
  assert.deepEqual([image.readUInt32BE(16),image.readUInt32BE(20)],[receipt.source_width,receipt.source_height],id+': original source dimensions');
  assert.ok(['v3','v4','v5'].some(v=>receipt.runtime_uri==='s2r://panorama/images/custom_game/archive_gpu_regular/head_'+v+'_'+id+'.vtex'),id+': formal texture URI');
  const uri=version?'s2r://panorama/images/custom_game/archive_gpu_regular/head_'+version+'_'+id+'.vtex':receipt.runtime_uri;
  const recipe=fs.readFileSync(path.join(root,'panorama/src',uri.substring('s2r://panorama/'.length)),'utf8');
  assert.ok(recipe.includes('"panorama/images/custom_game/archive_portraits_v3/'+id+'.png"'),id+': recipe original image identity');
  assert.match(recipe,/"m_outputFormat"\s+"string"\s+"BGRA8888"/,id+': lossless UI texture format');
  const noLod=recipe.match(/"m_bNoLod"\s+"bool"\s+"([01])"/),mip=recipe.match(/"m_mipAlgorithm"\s+"CDmeImageProcessor"\s*\{\s*"m_algorithm"\s+"string"\s+"([^"]*)"/);
  assert.ok(noLod&&mip,id+': explicit loading and filter settings');
  const bytes=fs.readFileSync(path.join(root,uri.substring('s2r://'.length)+'_c')),info=textureInfo(bytes);
  assert.equal(info.flags&8,noLod[1]==='1'?8:0,id+': compiled NO_LOD agrees with recipe');
  assert.equal(info.format,28,id+': compiled BGRA8888');assert.equal(info.depth,1,id+': 2D portrait');
  if(uri.includes('/head_v4_')){
   assert.match(recipe,/"m_algorithm"\s+"string"\s+"ScaleToPowerOfTwo"/,id+': native input preparation');
   assert.equal(mip[1],'Box',id+': native minification filter');
   assert.deepEqual([info.flags,info.width,info.height,info.mipLevels],[8,256,256,9],id+': full filtered v4 resource');
  }
  if(uri.includes('/head_v5_')){
   assert.deepEqual([image.readUInt32BE(16),image.readUInt32BE(20)],[1254,1254],id+': v5 retains original full-resolution input');
   assert.match(recipe,/"m_algorithm"\s+"string"\s+"ScaleToPowerOfTwo"/,id+': native input preparation');
   assert.match(recipe,/"m_nOutputMaxDimension"\s+"int"\s+"512"/,id+': explicit v5 dimension');
   assert.equal(noLod[1],'1',id+': v5 disables LOD');
   assert.equal(mip[1],'',id+': v5 has no mip filter');
   assert.deepEqual([info.flags,info.width,info.height,info.mipLevels],[8,512,512,1],id+': full-resolution v5 resource');
   assert.equal(info.payload.length,1048576,id+': complete 512px BGRA8888 base level');
  }
  assert.ok(info.width>=74&&info.height>=74,id+': native cell resolution retained');
  if(mip[1]==='')assert.equal(info.mipLevels,1,id+': explicit no-mip experiment');
  else if(mip[1]==='Box')assert.ok(info.mipLevels>1,id+': minification mips actually compiled');
  else assert.fail(id+': unexpected mip algorithm '+mip[1]);
  let expectedPayload=0;for(let level=0;level<info.mipLevels;level++)expectedPayload+=Math.max(1,info.width>>level)*Math.max(1,info.height>>level)*4;
  assert.equal(info.payload.length,expectedPayload,id+': complete uncompressed mip payload');
  return {id,source_sha256:receipt.sha256,source_width:receipt.source_width,source_height:receipt.source_height,no_lod:!!(info.flags&8),mip_algorithm:mip[1],width:info.width,height:info.height,format:'BGRA8888',mip_levels:info.mipLevels,payload_bytes:info.payload.length,payload_sha256:hash(info.payload),compiled_sha256:hash(bytes)};
 });
}
module.exports={audit};
if(require.main===module){const args=process.argv.slice(2);let version;if(args[0]==='--version'){version=args.splice(0,2)[1];assert.ok(['v3','v4','v5'].includes(version),'selected texture version');}const records=audit(args,version);console.log(JSON.stringify({result:'ARCHIVE_PORTRAIT_TEXTURES_PASS',count:records.length,original_pixels_unchanged:true,records},null,2));}
