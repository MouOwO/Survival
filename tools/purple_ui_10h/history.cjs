'use strict';
const net=require('node:net'),fs=require('node:fs'),{packet,printText}=require('../map_c6/console.cjs');
const socket=net.createConnection({host:'127.0.0.1',port:29000});
let input=Buffer.alloc(0),lines=[],finished=false;
function finish(){if(finished)return;finished=true;const text=lines.slice(-6000).join('');fs.mkdirSync('design_refs/purple_ui_10h/work/native',{recursive:true});fs.writeFileSync('design_refs/purple_ui_10h/work/native/engine_history.log',text);console.log(lines.slice(-6000).filter(s=>/error|exception|invalid|failed|purple|reload|HANDOFF_PRESENTED/i.test(s)).slice(-120).join('').slice(-16000));socket.end();setTimeout(()=>socket.destroy(),250);}
socket.on('connect',()=>socket.write(packet('VFCS',Buffer.from([0]))));
socket.on('data',b=>{input=Buffer.concat([input,b]);while(input.length>=12){const size=input.readUInt32BE(6);if(size<12||size>8*1024*1024)throw Error('Invalid frame');if(input.length<size)break;const f=input.subarray(0,size);input=input.subarray(size);if(f.toString('ascii',0,4)!=='PRNT')continue;const line=printText(f);lines.push(line);if(line.includes('End VConsole Buffered Messages'))finish();}});
socket.on('error',e=>{console.error(e.message);process.exitCode=1;});setTimeout(finish,5000);
