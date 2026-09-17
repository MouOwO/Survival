// Read-only protocol inspection: no engine command is sent.
const net=require('net'),fs=require('fs'),p=require('path');
const result={chunks:[],headers:[],addon:[]};let buffer=Buffer.alloc(0);
const s=net.createConnection({host:'127.0.0.1',port:29000});
s.on('connect',()=>s.write(Buffer.from('5646435300d40000000d000000','hex')));
s.on('data',b=>{result.chunks.push(b.length);buffer=Buffer.concat([buffer,b]);while(buffer.length>=12){let size=buffer.readUInt32BE(6);if(size<12||size>8388608){result.invalidHeader=buffer.subarray(0,12).toString('hex');break;}if(buffer.length<size)break;let packet=buffer.subarray(0,size);buffer=buffer.subarray(size);let type=packet.toString('ascii',0,4);if(result.headers.length<80)result.headers.push({type,size});if(type==='ADON')result.addon.push(packet.subarray(12).toString('hex'));}});
s.on('error',e=>result.error=e.message);
setTimeout(()=>{s.destroy();fs.writeFileSync(p.join(__dirname,'evidence/console_protocol.json'),JSON.stringify(result,null,2));console.log(result);},2500);
