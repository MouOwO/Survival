// Stage only new cloud resources and the asset-review map. Never edit the main map.
const fs=require('fs'),path=require('path');
const source=fs.readFileSync(path.join(__dirname,'xianxia_kit_gallery.cjs'),'utf8');
const {pngRead,pngWrite}=new Function('require','__dirname',source.slice(0,source.indexOf('const a=JSON.parse'))+'return {pngRead,pngWrite};')(require,__dirname);
const kit=path.resolve(__dirname,'../output/xianxia_kit'),out=path.join(kit,'cloud_revision_v2');
const names=['c01_cloud_sea','c02_cliff_cloud','c03_cloud_band','c04_thin_mist'];
const mipChecks=[];
const checks=JSON.parse(fs.readFileSync(path.join(out,'alpha_validation.json')));
if(checks.length!==4||checks.some(c=>!c.alphaPass||c.dimensions[0]!==2048))throw Error('Final cloud alpha QA required');
for(const d of ['source_materials','source_particles'])fs.mkdirSync(path.join(out,d),{recursive:true});
let map=fs.readFileSync(path.join(kit,'xianxia_kit_review.vmap'),'utf8');
for(const name of names){
 const p=pngRead(path.join(out,name+'.png')),side=2048,d=Buffer.alloc(side*side*4),top=(side-p.h)>>1;
 for(let y=0;y<p.h;y++)p.data.copy(d,((y+top)*side)*4,y*p.w*4,(y+1)*p.w*4);
 pngWrite(path.join(out,'source_materials',name+'_v2.png'),side,side,d);
 let alpha=Buffer.alloc(side*side);for(let i=0;i<alpha.length;i++)alpha[i]=d[i*4+3];let size=side,levels=[];
 while(size>=256){let border=0;for(let i=0;i<size;i++)border=Math.max(border,alpha[i],alpha[(size-1)*size+i],alpha[i*size],alpha[i*size+size-1]);levels.push({size,borderAlphaMax:border});if(border)throw Error(name+' clips at mip '+size);const next=Buffer.alloc(size*size/4);for(let y=0;y<size/2;y++)for(let x=0;x<size/2;x++){const at=y*2*size+x*2;next[y*size/2+x]=Math.round((alpha[at]+alpha[at+1]+alpha[at+size]+alpha[at+size+1])/4);}alpha=next;size/=2;}
 mipChecks.push({name,levels});
 for(const [folder,ext] of [['source_materials','vtex'],['source_particles','vpcf']]){
  let s=fs.readFileSync(path.join(kit,folder,name+'.'+ext),'utf8');s=s.replaceAll(name,name+'_v2');
  fs.writeFileSync(path.join(out,folder,name+'_v2.'+ext),s);
 }
 map=map.replaceAll('particles/xianxia_kit/'+name+'.vpcf','particles/xianxia_kit/'+name+'_v2.vpcf');
}
// The old bank origins were partly below the water plane, cutting a flat lower edge.
const heights=[['-2400 -900 -180','-2400 -900 480'],['2200 -400 -40','2200 -400 260'],['-2100 100 -80','-2100 100 240'],['2000 -1300 0','2000 -1300 220']];
for(const [from,to] of heights){const match='"origin" "vector3" "'+from+'"';if(!map.includes(match))throw Error('Expected cloud origin missing: '+from);map=map.replace(match,'"origin" "vector3" "'+to+'"');}
fs.writeFileSync(path.join(out,'xianxia_kit_review.vmap'),map);
fs.writeFileSync(path.join(out,'mip_validation.json'),JSON.stringify(mipChecks,null,2));
console.log('Staged four new cloud textures/particles and cloud-only test-map revision');
