'use strict';
const net=require('net'),fs=require('fs'),{packet,printText}=require('../map_c6/console.cjs');
const s=net.createConnection({host:'127.0.0.1',port:29000});let input=Buffer.alloc(0),commands=null;
s.on('connect',()=>s.write(packet('VFCS',Buffer.from([0]))));
s.on('data',b=>{input=Buffer.concat([input,b]);while(input.length>=12){const n=input.readUInt32BE(6);if(n<12||n>8*1024*1024){s.end();return;}if(input.length<n)return;const f=input.subarray(0,n);input=input.subarray(n);if(f.toString('ascii',0,4)!=='PRNT')continue;const t=printText(f),i=t.indexOf('[COMMERCE_JADE_COMMANDS]');if(i>=0)try{commands=JSON.parse(t.slice(i+24).trim());}catch{}}});
setTimeout(()=>{if(!commands){console.error('No native command generation captured');process.exitCode=1;}else{fs.writeFileSync('design_refs/shop_ui_12h/work/native_commands.json',JSON.stringify(commands,null,2));console.log('NATIVE_COMMANDS_CAPTURED '+commands.open);}s.end();},1800);s.on('error',e=>{console.error(e.message);process.exitCode=1});
