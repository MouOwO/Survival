const fs=require('fs'),path=require('path'),assert=require('assert/strict');
const kit=path.resolve(__dirname,'../output/xianxia_kit/cloud_revision_v2');
const src=fs.readFileSync(path.join(__dirname,'xianxia_kit_gallery.cjs'),'utf8');
const {pngRead}=new Function('require','__dirname',src.slice(0,src.indexOf('const a=JSON.parse'))+'return {pngRead};')(require,__dirname);
const report=[];
for(const name of ['c01_cloud_sea','c02_cliff_cloud','c03_cloud_band','c04_thin_mist','c01_cloud_sea_b','c02_cliff_cloud_b']){
 const p=pngRead(path.join(kit,name.endsWith('_b')?'variants/source_materials':'source_materials',name+'_v2.png'));
 let size=p.w,a=Float32Array.from({length:size*size},(_,i)=>p.data[i*4+3]);const mips=[];
 while(size>=256){
  let edge=0;for(let i=0;i<size;i++)edge=Math.max(edge,a[i],a[(size-1)*size+i],a[i*size],a[i*size+size-1]);
  assert.equal(edge,0,name+' has visible mip border');mips.push({size,borderAlphaMax:edge});
  const n=size/2,b=new Float32Array(n*n);for(let y=0;y<n;y++)for(let x=0;x<n;x++){const i=y*2*size+x*2;b[y*n+x]=(a[i]+a[i+1]+a[i+size]+a[i+size+1])/4;}a=b;size=n;
 }report.push({name,mips,pass:true});
}
fs.writeFileSync(path.join(kit,'world_integration_mip_validation.json'),JSON.stringify(report,null,2));console.log('Six clouds: alpha borders clean at 2048, 1024, 512 and 256.');
