"use strict";
const assert=require("node:assert/strict"),{Readable}=require("node:stream"),API=require("./network50_perf_vconsole.cjs");
(async()=>{
 const command="network50_inspect_1700000000000_1",nonce="abcdef0123456789abcdef0123456789";
 let sent=0,closed=0;const output=[];
 class Fake{
  constructor(options){assert.equal(options.port,29069);assert.equal(options.retainOutput,false);}
  async connect(){}
  async close(){closed++;}
  async send(requests,expect,drain,options){sent++;assert.equal(requests.length,1);assert.equal(requests[0].name,"console_send");assert.equal(requests[0].arguments.commands,command+" "+nonce);assert.equal(expect,"");assert.equal(options.responsePrefix,"[NETWORK50_UI_INSPECT] "+nonce+" ");return {expected_output_received:true,matched_line:options.responsePrefix+JSON.stringify({active:true,tools:true,game_time:100,paused:false,wave:{status:"spawning"}})};}
 }
 await API.run(command,Readable.from([JSON.stringify({op:"inspect",nonce})+"\n",'{"op":"close"}\n']),{write(line){output.push(JSON.parse(line));}},Fake);
 assert.equal(sent,1);assert.ok(closed>=1);assert.equal(output[0].ready,true);assert.equal(output[1].nonce,nonce);assert.equal(output[2].closed,true);
 sent=0;await assert.rejects(API.run(command,Readable.from(['{"op":"exec","command":"quit"}\n']),{write(){}},Fake),/read_only_inspect_required/);assert.equal(sent,0);
 sent=0;await assert.rejects(API.run(command,Readable.from([JSON.stringify({op:"inspect",nonce:nonce+";quit"})+"\n"]),{write(){}},Fake),/fresh_32hex_nonce_required/);assert.equal(sent,0);
 console.log('NETWORK50_PERF_VCONSOLE_PASS persistent one-readback, no arbitrary console/Lua, nonce binding, close/failure cleanup; no native socket used');
})().catch(error=>{console.error(error.message);process.exitCode=1;});
