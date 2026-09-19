// Local Source 2 developer-console client, used only for this map's manual checks.
const net=require('net');
const command=process.argv[2]||'echo C6_CONSOLE_CONNECTED';
const s=net.createConnection({host:'127.0.0.1',port:29000});
function packet(type,body){const b=Buffer.alloc(12+body.length);b.write(type);b.writeUInt32BE(0x00d40000,4);b.writeUInt32BE(b.length,6);body.copy(b,12);return b;}
let input=Buffer.alloc(0);
s.on('connect',()=>{s.write(packet('VFCS',Buffer.from([0])));setTimeout(()=>s.write(packet('CMND',Buffer.from(command+'\0'))),350);});
s.on('data',b=>{input=Buffer.concat([input,b]);while(input.length>=12){const size=input.readUInt32BE(6);if(size<12)throw Error('Invalid frame');if(input.length<size)break;const p=input.subarray(0,size);input=input.subarray(size);if(p.toString('ascii',0,4)==='PRNT')console.log(p.subarray(12).toString('utf8').replace(/[\x00-\x08\x0e-\x1f]/g,''));}});
s.on('error',e=>{console.error(e.message);process.exitCode=1;});
setTimeout(()=>s.destroy(),Number(process.argv[3]||3500));
