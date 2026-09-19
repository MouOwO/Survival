// Sample installed Valve rock and staircase render meshes, rather than the
// terrain hidden inside props. These assets use uncompressed MBUF streams.
const path=require('path'),{Vpk}=require('./lib.cjs');
const cache=new Map();let pak;
function mesh(name){
 if(cache.has(name))return cache.get(name);
 pak ||= new Vpk(path.resolve(__dirname,'../../../../../game/dota/pak01_dir.vpk'));
 const asset=name.includes('/')?name:'models/props_rock/riveredge_rock'+name+'.vmdl';
 const b=pak.read(asset+'_c');
 const table=8+b.readUInt32LE(8);let data;
 for(let i=0;i<b.readUInt32LE(12);i++){
  const p=table+i*12;if(b.toString('ascii',p,p+4)==='MBUF')data=b.subarray(p+4+b.readUInt32LE(p+4),p+4+b.readUInt32LE(p+4)+b.readUInt32LE(p+8));
 }
 if(!data||data.readUInt32LE(4)!==1||data.readUInt32LE(12)!==1)throw Error('Unexpected native rock buffer '+name);
 const v=data.readUInt32LE(0),i=8+data.readUInt32LE(8),count=data.readUInt32LE(v),stride=data.readUInt32LE(v+4);
 const vp=v+16+data.readUInt32LE(v+16),ip=i+16+data.readUInt32LE(i+16),ic=data.readUInt32LE(i),is=data.readUInt32LE(i+4);
 if(data.readUInt32LE(v+20)!==count*stride||data.readUInt32LE(i+20)!==ic*is||is!==2)throw Error('Compressed native rock buffer '+name);
 const vertices=Array.from({length:count},(_,j)=>[0,4,8].map(k=>data.readFloatLE(vp+j*stride+k)));
 const triangles=Array.from({length:ic/3},(_,j)=>[0,1,2].map(k=>vertices[data.readUInt16LE(ip+(j*3+k)*2)]));
 cache.set(name,triangles);return triangles;
}
const sub=(a,b)=>a.map((v,i)=>v-b[i]);
const cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];
const dot=(a,b)=>a.reduce((s,v,i)=>s+v*b[i],0);
function sampler(rocks){
 const triangles=[];
 for(const r of rocks){const a=r.yaw*Math.PI/180,c=Math.cos(a),s=Math.sin(a),scale=r.scale;
  const transform=Array.isArray(scale)?([x,y,z])=>[r.position[0]+x*scale[0]*c-y*scale[1]*s,r.position[1]+x*scale[0]*s+y*scale[1]*c,r.position[2]+z*scale[2]]:
   ([x,y,z])=>[r.position[0]+(x*c-y*s)*scale,r.position[1]+(x*s+y*c)*scale,r.position[2]+z*scale];
  for(const face of mesh(r.model)){
   const [v,b,d]=face.map(transform);
   triangles.push({v,e1:sub(b,v),e2:sub(d,v)});
  }
 }
 return (origin,dir,max=1024)=>{
  let best=max,hit;
  for(const {v,e1,e2} of triangles){
   const p=cross(dir,e2),det=dot(e1,p);if(Math.abs(det)<1e-7)continue;
   const t=sub(origin,v),u=dot(t,p)/det;if(u<0||u>1)continue;
   const q=cross(t,e1),w=dot(dir,q)/det;if(w<0||u+w>1)continue;
   const dist=dot(e2,q)/det;if(dist<0||dist>=best)continue;
   let normal=cross(e1,e2);const length=Math.hypot(...normal),sign=dot(normal,dir)>0?-1:1;
   normal=normal.map(n=>n/length*sign);best=dist;
   hit={point:origin.map((n,i)=>n+dist*dir[i]),normal};
  }
  return hit;
 };
}
module.exports={mesh,sampler};
