'use strict';
// Verify the actual compiled texture, not just the input PNG or recipe.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {textureInfo}=require('../test_construction_grid_resources.cjs');
const {decodePng}=require('../collection_gw2/opaque_probe.cjs');
const root=path.resolve(__dirname,'../..'),folder='custom_game/collection_user_skin_v1';
const png=fs.readFileSync(path.join(root,'art/ui/sources',folder,'background.png'));
assert.deepEqual(fs.readFileSync(path.join(root,'panorama/src/images',folder,'background.png')),png,'Original PNG/source mirrors');
const image=decodePng(png),raw=fs.readFileSync(path.join(root,'panorama/images',folder,'background.vtex_c')),texture=textureInfo(raw);
assert.deepEqual([texture.width,texture.height,texture.depth,texture.format,texture.mipLevels,texture.flags],[image.width,image.height,1,28,1,8]);
assert.equal(texture.payload.length,image.width*image.height*4);
for(let pixel=0;pixel<image.width*image.height;pixel++){
 const source=pixel*image.channels,native=pixel*4;
 assert.equal(texture.payload[native],image.pixels[source+2]);assert.equal(texture.payload[native+1],image.pixels[source+1]);assert.equal(texture.payload[native+2],image.pixels[source]);assert.equal(texture.payload[native+3],image.channels===4?image.pixels[source+3]:255);
}
const report={status:'PASS_EXACT_COMPILED_PIXELS',width:texture.width,height:texture.height,format:'BGRA8888',mips:1,noLod:true,pixelsChecked:image.width*image.height,payloadBytes:texture.payload.length,sourceSha256:crypto.createHash('sha256').update(png).digest('hex'),compiledSha256:crypto.createHash('sha256').update(raw).digest('hex'),nativeGameVerified:false};
fs.writeFileSync(path.join(root,'output/collection_user_skin_20261019/texture_audit.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
