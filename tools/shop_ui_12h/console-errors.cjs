'use strict';
const net=require('net'),{packet,printText}=require('../map_c6/console.cjs');
const s=net.createConnection({host:'127.0.0.1',port:29000});let input=Buffer.alloc(0),hits=[];
s.on('connect',()=>s.write(packet('VFCS',Buffer.from([0]))));
s.on('data',b=>{input=Buffer.concat([input,b]);while(input.length>=12){const n=input.readUInt32BE(6);if(n<12||n>8*1024*1024){s.end();return;}if(input.length<n)return;const f=input.subarray(0,n);input=input.subarray(n);if(f.toString('ascii',0,4)!=='PRNT')continue;let t;try{t=printText(f);}catch{continue;}if(/COMMERCE_JADE|HANDOFF_HUD|Invalid value for property|exception|TypeError|ReferenceError|SyntaxError|RESOURCE COMPILE ERROR|Unable to load.*custom_game|Failed to load.*commerce/i.test(t))hits.push(t.trim());}});
setTimeout(()=>{console.log(hits.slice(-60).join('\n'));s.end();},1800);s.on('error',e=>{console.error(e.message);process.exitCode=1});
