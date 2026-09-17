// Lossless container wrapping of captured JPEG frames. No generated animation or mock UI.
const fs=require('fs'),p=require('path'),folder=p.resolve(process.argv[2]),m=JSON.parse(fs.readFileSync(p.join(folder,'capture.json'),'utf8').replace(/^\uFEFF/,''));
const word=n=>{const b=Buffer.alloc(4);b.writeUInt32LE(n>>>0);return b;};
const chunk=(id,b)=>Buffer.concat([Buffer.from(id),word(b.length),b,b.length%2?Buffer.alloc(1):Buffer.alloc(0)]);
const list=(id,b)=>chunk('LIST',Buffer.concat([Buffer.from(id),b]));
const source=m.frames.map(f=>({...f,data:fs.readFileSync(p.join(folder,f.file))}));
const fps=m.fps,n=Math.ceil(m.elapsedMs*fps/1000),frames=[];let at=0;
for(let i=0;i<n;i++){while(at+1<source.length&&source[at+1].ms<=i*1000/fps)at++;frames.push(source[at].data);}
const max=Math.max(...frames.map(b=>b.length));
const avih=Buffer.alloc(56);[Math.round(1e6/fps),max*fps,0,0x10,n,0,1,max,m.width,m.height].forEach((v,i)=>avih.writeUInt32LE(v>>>0,i*4));
const strh=Buffer.alloc(56);strh.write('vidsMJPG');strh.writeUInt32LE(1,20);strh.writeUInt32LE(fps,24);strh.writeUInt32LE(n,32);strh.writeUInt32LE(max,36);strh.writeUInt32LE(0xffffffff,40);strh.writeUInt16LE(m.width,52);strh.writeUInt16LE(m.height,54);
const strf=Buffer.alloc(40);strf.writeUInt32LE(40);strf.writeInt32LE(m.width,4);strf.writeInt32LE(m.height,8);strf.writeUInt16LE(1,12);strf.writeUInt16LE(24,14);strf.write('MJPG',16);strf.writeUInt32LE(m.width*m.height*3,20);
let offset=4;const index=frames.map(b=>{const row=Buffer.concat([Buffer.from('00dc'),word(0x10),word(offset),word(b.length)]);offset+=8+b.length+b.length%2;return row;});
const body=Buffer.concat([Buffer.from('AVI '),list('hdrl',Buffer.concat([chunk('avih',avih),list('strl',Buffer.concat([chunk('strh',strh),chunk('strf',strf)]))])),list('movi',Buffer.concat(frames.map(b=>chunk('00dc',b)))),chunk('idx1',Buffer.concat(index))]);
const dest=folder.replace(/_frames$/,'')+'.avi';fs.writeFileSync(dest,Buffer.concat([Buffer.from('RIFF'),word(body.length),body]));console.log(JSON.stringify({video:dest,frames:n,fps,duration:n/fps,bytes:body.length+8}));
