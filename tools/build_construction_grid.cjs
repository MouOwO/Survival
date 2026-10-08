// Deterministic native construction grid, reconstructed only from the approved
// edge/corner PNGs. Never tile reference_cell.png: it has a gray cell interior.
// node tools/build_construction_grid.cjs
// Source2 textures must be power-of-two: pad to 2048px, use radius2048, and
// leave UV controls at identity. Renderer UV scale/offset repeat this image.
// A native world-Z sprite replaces hundreds of Panorama projection writes.
'use strict';
const fs=require('node:fs'),path=require('node:path'),zlib=require('node:zlib'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),source=path.join(root,'art/ui/sources/custom_game/survival_grid');
const assetRoot=path.join(root,'art/effects/construction_grid'),out=path.join(assetRoot,'source'),prefix='survival_grid';
const SIZE=2048,RADIUS=1280,CELL=64,EDGE_WORLD=4,CORNER_WORLD=16;
// Match .StaticGridRangeLine (#75e14b99, 1px at the 32px/cell reference
// view). The visible boundary shares this sprite's plane and exact circle.
const RING_COLOR=[117,225,75],RING_OPACITY=0.60,RING_WIDTH=2,RING_AA=2;
const RING_SUPPORT=(RING_WIDTH+RING_AA)/2;
const RING_RGB_PADDING=16; // Invisible color bleed for DXT blocks and mip filtering.
const CORE_HASHES=[
 'f685612477f837ebd2628a2df40b6bf909e24724c6f8edda45e9813f407359a0',
 '519084a26edba46d34cb0aeffe69f620677f19a70d5ab021d174e6383b3fc709',
 '2933ce74895aa9f45a275455d026b8616e32f265598a47542f4a3e3089752a0d',
 'e8ad422cb793315f444be884bae8e59626cf4c7fa9412eee607c293f89d0df7d'
];
function decode(file){
 const bytes=fs.readFileSync(file),width=bytes.readUInt32BE(16),height=bytes.readUInt32BE(20),parts=[];
 assert.equal(bytes[24],8);assert.equal(bytes[25],6);
 for(let p=8;p<bytes.length;){const n=bytes.readUInt32BE(p),type=bytes.toString('ascii',p+4,p+8);if(type==='IDAT')parts.push(bytes.subarray(p+8,p+8+n));p+=n+12;}
 const raw=zlib.inflateSync(Buffer.concat(parts)),pixels=Buffer.alloc(width*height*4),stride=width*4;
 function paeth(a,b,c){const p=a+b-c,pa=Math.abs(p-a),pb=Math.abs(p-b),pc=Math.abs(p-c);return pa<=pb&&pa<=pc?a:pb<=pc?b:c;}
 for(let y=0;y<height;y++){const mode=raw[y*(stride+1)];for(let x=0;x<stride;x++){const i=y*stride+x,a=x>=4?pixels[i-4]:0,b=y?pixels[i-stride]:0,c=x>=4&&y?pixels[i-stride-4]:0;
  pixels[i]=(raw[y*(stride+1)+x+1]+(mode===0?0:mode===1?a:mode===2?b:mode===3?Math.floor((a+b)/2):paeth(a,b,c)))&255;}}
 return {width,height,pixels,sha256:crypto.createHash('sha256').update(bytes).digest('hex')};
}
function crc32(data){let crc=0xffffffff;for(const byte of data){crc^=byte;for(let bit=0;bit<8;bit++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}return(crc^0xffffffff)>>>0;}
function chunk(kind,body){const name=Buffer.from(kind),head=Buffer.alloc(4),crc=Buffer.alloc(4);head.writeUInt32BE(body.length);crc.writeUInt32BE(crc32(Buffer.concat([name,body])));return Buffer.concat([head,name,body,crc]);}
function png(width,height,pixels){const raw=Buffer.alloc(height*(width*4+1));for(let y=0;y<height;y++)pixels.copy(raw,y*(width*4+1)+1,y*width*4,(y+1)*width*4);
 const head=Buffer.alloc(13);head.writeUInt32BE(width,0);head.writeUInt32BE(height,4);head[8]=8;head[9]=6;
 return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',head),chunk('IDAT',zlib.deflateSync(raw,{level:9})),chunk('IEND',Buffer.alloc(0))]);}
// Bilinear RGBA sampling with premultiplied interpolation avoids dark outlines.
function sample(image,x,y){const result=[0,0,0,0],x0=Math.floor(x),y0=Math.floor(y),fx=x-x0,fy=y-y0;
 for(let j=0;j<2;j++)for(let i=0;i<2;i++){const px=Math.max(0,Math.min(image.width-1,x0+i)),py=Math.max(0,Math.min(image.height-1,y0+j));
  const at=(py*image.width+px)*4,w=(i?fx:1-fx)*(j?fy:1-fy),a=image.pixels[at+3]/255;
  for(let c=0;c<3;c++)result[c]+=image.pixels[at+c]/255*a*w;result[3]+=a*w;}
 return result;}
function over(dst,src,opacity){const a=src[3]*opacity;for(let c=0;c<3;c++)dst[c]=src[c]*opacity+dst[c]*(1-a);dst[3]=a+dst[3]*(1-a);}
const edge=decode(path.join(source,'reference_edge.png')),corner=decode(path.join(source,'reference_corner.png'));
assert.equal(edge.sha256,'5a59481643d4c7d5ba83497fa0572d7844c32bc34484ec858b5d9a2be5f7cc1b','approved edge texture fingerprint');
assert.equal(corner.sha256,'537fffae0c8fe5ccdf843cae80bc90d2760ee5bdd23d006c30a4f77b390538f6','approved corner texture fingerprint');
function nearest(v){const m=((v%CELL)+CELL)%CELL;return m<CELL/2?m:m-CELL;}
// Measured with CP0+32X: Source2 WORLD_Z maps texture V to world X and U
// to world Y. The asymmetric phase screenshots distinguish these axes.
function texturePhaseForWorld(phase){return [phase[1],phase[0]];}
assert.deepEqual([[0,0],[32,0],[0,32],[32,32]].map(texturePhaseForWorld),[[0,0],[0,32],[32,0],[32,32]],'native WORLD_Z world-to-texture axis contract');
function whitePixel(wx,wy,phase,cornerWorld=CORNER_WORLD){const dx=nearest(wx+phase[0]),dy=nearest(wy+phase[1]),p=[0,0,0,0];
 if(Math.abs(dy)<EDGE_WORLD/2)over(p,sample(edge,0,(dy/EDGE_WORLD+0.5)*edge.height-0.5),0.60);
 if(Math.abs(dx)<EDGE_WORLD/2)over(p,sample(edge,0,(dx/EDGE_WORLD+0.5)*edge.height-0.5),0.60);
 if(Math.abs(dx)<cornerWorld/2&&Math.abs(dy)<cornerWorld/2)
  over(p,sample(corner,(dx/cornerWorld+0.5)*corner.width-0.5,(dy/cornerWorld+0.5)*corner.height-0.5),0.75);
 const t=Math.max(0,Math.min(1,(1-Math.hypot(wx,wy)/RADIUS)/0.25)),fade=t*t*(3-2*t);
 const rgba=p[3]?[...p.slice(0,3).map(v=>Math.round(255*v/p[3])),Math.round(255*p[3]*fade)]:[255,255,255,0];
 return rgba;
}
function ringAlpha(radius){return RING_OPACITY*Math.max(0,Math.min(1,(RING_SUPPORT-Math.abs(radius-RADIUS))/RING_AA));}
function pixel(wx,wy,phase,cornerWorld=CORNER_WORLD){
 const white=whitePixel(wx,wy,phase,cornerWorld),radius=Math.hypot(wx,wy),alpha=ringAlpha(radius);
 if(!alpha)return !white[3]&&Math.abs(radius-RADIUS)<RING_RGB_PADDING?[...RING_COLOR,0]:white;
 const whiteAlpha=white[3]/255,combined=alpha+whiteAlpha*(1-alpha);
 return [...RING_COLOR.map((v,i)=>Math.round((v*alpha+white[i]*whiteAlpha*(1-alpha))/combined)),Math.round(combined*255)];
}
function coreHash(data){const hash=crypto.createHash('sha256');
 for(let y=0;y<SIZE;y++){const wy=(y+.5)*2-SIZE;
  for(let x=0;x<SIZE;x++){const wx=(x+.5)*2-SIZE;
   if(wx*wx+wy*wy<=(RADIUS*.75)**2)hash.update(data.subarray((y*SIZE+x)*4,(y*SIZE+x)*4+4));}}
 return hash.digest('hex');
}
function write(relative,text){const file=path.join(out,relative);fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,text);return file;}
function vtex(name){return `<!-- dmx encoding keyvalues2_noids 1 format vtex 1 -->
"CDmeVtex"
{
 "m_inputTextureArray" "element_array" [ "CDmeInputTexture" {
  "m_name" "string" "InputTexture0"
  "m_fileName" "string" "materials/${prefix}/${name}.png"
  "m_colorSpace" "string" "srgb"
  "m_typeString" "string" "2D"
 } ]
 "m_outputTypeString" "string" "2D"
 "m_outputFormat" "string" "DXT5"
 "m_outputClearColor" "vector4" "0 0 0 0"
 "m_nOutputMinDimension" "int" "0"
 "m_nOutputMaxDimension" "int" "0"
 "m_textureOutputChannelArray" "element_array" [ "CDmeTextureOutputChannel" {
  "m_inputTextureArray" "string_array" [ "InputTexture0" ]
  "m_srcChannels" "string" "rgba"
  "m_dstChannels" "string" "rgba"
  "m_mipAlgorithm" "CDmeImageProcessor" { "m_algorithm" "string" "Box" "m_stringArg" "string" "" "m_vFloat4Arg" "vector4" "0 0 0 0" }
  "m_outputColorSpace" "string" "srgb"
 } ]
 "m_vClamp" "vector3" "1 1 1"
 "m_bNoLod" "bool" "0"
}
`;}
function particle(name){return `<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->
{
 _class = "CParticleSystemDefinition"
 m_nBehaviorVersion = 12
 m_nMaxParticles = 1
 m_flConstantRadius = 2048.0
 m_flConstantLifespan = 999999.0
 m_flConstantAlpha = 1.0
 m_ConstantColor = [255,255,255,255]
 m_flCullRadius = -1.0
 m_flNoDrawTimeToGoToSleep = 999999.0
 m_BoundingBoxMin = [-2048.0,-2048.0,-8.0]
 m_BoundingBoxMax = [2048.0,2048.0,8.0]
 m_Renderers = [{
  _class = "C_OP_RenderSprites"
  m_bEnableFadingAndClamping = false
  m_flMaxSize = 10000.0
  m_nOrientationType = "PARTICLE_ORIENTATION_WORLD_Z_ALIGNED"
  m_bDisableZBuffering = true
  m_nFogType = "PARTICLE_FOG_DISABLED"
  m_bTintByFOW = false
  m_bTintByGlobalLight = false
  m_flOverbrightFactor = {m_nType="PF_TYPE_LITERAL" m_flLiteralValue=1.0}
  m_nOutputBlendMode = "PARTICLE_OUTPUT_BLEND_MODE_ALPHA"
  m_vecTexturesInput = [{m_hTexture=resource:"materials/${prefix}/${name}.vtex"}]
 }]
 m_Initializers = [{_class="C_INIT_CreateWithinSphereTransform" m_fRadiusMin=0.0 m_fRadiusMax=0.0}]
 m_Operators = [
  {_class="C_OP_PositionLock"},
  {_class="C_OP_SetFloat" m_nOutputField=7 m_nSetMethod="PARTICLE_SET_REPLACE_VALUE"
   m_InputValue={m_nType="PF_TYPE_CONTROL_POINT_COMPONENT" m_nControlPoint=3 m_nVectorComponent=0}},
  {_class="C_OP_EndCapTimedDecay" m_flDecayTime=0.0}
 ]
 m_Emitters = [{_class="C_OP_InstantaneousEmitter" m_nParticlesToEmit={m_nType="PF_TYPE_LITERAL" m_flLiteralValue=1.0}}]
}
`;}
function build(){
const manifest={schema_version:2,radius:RADIUS,world_size:2*RADIUS,cell_size:CELL,
 texture_size:[SIZE,SIZE],texture_world_size:SIZE*2,particle_radius:2048,texture_format:'DXT5',uv_scale:1,uv_offset:0,
 edge_world_width:EDGE_WORLD,corner_world_size:CORNER_WORLD,
 range_boundary:{radius:RADIUS,color:RING_COLOR,opacity:RING_OPACITY,width_world:RING_WIDTH,antialias_world:RING_AA,support_world:[RADIUS-RING_SUPPORT,RADIUS+RING_SUPPORT],transparent_rgb_padding_world:RING_RGB_PADDING,phase_independent:true,plane:'same sprite as white grid',purpose:'construction preview boundary; does not change ability or placement validation'},
 source:{edge:edge.sha256,corner:corner.sha256},controls:{CP0:'snapped world center, construction grid Z',CP3:'x=1 visible, x=0 hidden'},
 attachment:'PATTACH_WORLDORIGIN',max_particles:1,
 description:'Approved reference edge opacity .60 and corner opacity .75; transparent cell interiors except the explicit green boundary ring; every 64-world intersection; white circle .75R core and smooth .25R feather; green range boundary shares the same plane.',
 limits:['World-scaled edge/corner dimensions preserve the historical 2px/8px proportions at a 32px cell; dimensions follow camera perspective.',
 'Mip filtering and DXT5 alpha compression intentionally use the native renderer; runtime proof is recorded separately.'],resources:[]};
for(const phase of [[0,0],[32,0],[0,32],[32,32]]){
 const name=`reference_grid_${(phase[0]?1:0)+(phase[1]?2:0)}`;
 const texturePhase=texturePhaseForWorld(phase);
 const phaseIndex=(phase[0]?1:0)+(phase[1]?2:0);
 const data=Buffer.alloc(SIZE*SIZE*4);let filled=0;
 for(let y=0;y<SIZE;y++)for(let x=0;x<SIZE;x++){
  const color=pixel((x+0.5)*2-SIZE,(y+0.5)*2-SIZE,texturePhase),i=(y*SIZE+x)*4;
  for(let c=0;c<4;c++)data[i+c]=color[c];if(color[3])filled++;
 }
 for(let x=-1152;x<=1152;x+=CELL)for(let y=-1152;y<=1152;y+=CELL){
  const wx=x+32-phase[0],wy=y+32-phase[1];
  if(Math.abs(Math.hypot(wx,wy)-RADIUS)>=RING_SUPPORT)
   assert.equal(pixel(wy,wx,texturePhase)[3],0,'world cell interiors stay transparent outside the explicit ring band');
 }
 for(let x=-128.5;x<=128.5;x+=4)for(let y=-128.5;y<=128.5;y+=4)
  assert.deepEqual(pixel(y,x,texturePhase),pixel(y+phase[1],x+phase[0],[0,0]),'all four world phases preserve the same native world grid in the opaque core');
 assert.equal(coreHash(data),CORE_HASHES[phaseIndex],'white grid inside .75R remains byte-identical to the validated pre-ring source');
 for(let step=0;step<360;step++){
  const angle=step*Math.PI/180,wx=RADIUS*Math.cos(angle),wy=RADIUS*Math.sin(angle);
  assert.deepEqual(pixel(wy,wx,texturePhase),[...RING_COLOR,153],'each world phase has the same radius1280 green boundary');
  const tx=Math.max(0,Math.min(SIZE-1,Math.round((wy+SIZE)/2-.5))),ty=Math.max(0,Math.min(SIZE-1,Math.round((wx+SIZE)/2-.5))),at=(ty*SIZE+tx)*4;
  assert.ok(data[at+3]>=40&&data[at+1]>data[at]+50&&data[at+1]>data[at+2]+50,'raster ring is continuous at every sampled degree');
 }
 const image=png(SIZE,SIZE,data);write(`materials/${prefix}/${name}.png`,image);
 write(`materials/${prefix}/${name}.vtex`,vtex(name));write(`particles/${prefix}/${name}.vpcf`,particle(name));
 manifest.resources.push({particle:`particles/${prefix}/${name}.vpcf`,texture:`materials/${prefix}/${name}.vtex`,phase,world_phase:phase,texture_phase:texturePhase,
  png_sha256:crypto.createHash('sha256').update(image).digest('hex'),white_core_sha256:CORE_HASHES[phaseIndex],nontransparent_pixels:filled});
}
fs.writeFileSync(path.join(assetRoot,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
return manifest;
}
module.exports={build,decode,png,pixel,whitePixel,ringAlpha,texturePhaseForWorld};
if(require.main===module){const manifest=build();console.log(JSON.stringify({result:'CONSTRUCTION_GRID_ASSETS_BUILT',particles:manifest.resources.length,texture_size:manifest.texture_size,
 radius:RADIUS,cell_size:CELL,transparent_interiors_except_boundary_ring:true,range_boundary:true,unchanged_white_core:true}));}
