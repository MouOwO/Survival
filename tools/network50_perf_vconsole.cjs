"use strict";
// One persistent, loopback-only readback connection. No Lua generation, game
// mutation, history export or arbitrary console command is supported here.
const readline=require("node:readline");
const {ConsoleSession}=require("./map_c6/console-session.cjs");
function parseCommand(value){if(typeof value!=="string"||!/^network50_inspect_[0-9]{10,16}_[0-9]{1,6}$/.test(value))throw Error("registered_inspect_command_required");return value;}
function parseNonce(value){if(typeof value!=="string"||! /^[0-9a-f]{32}$/.test(value))throw Error("fresh_32hex_nonce_required");return value;}
async function run(command,input=process.stdin,output=process.stdout,Session=ConsoleSession){
 command=parseCommand(command);
 const session=new Session({port:29069,timeoutMs:2500,historyTimeoutMs:4000,retainOutput:false,maxPendingOutputChars:1024*1024,closeDrainMs:250});
 const emit=value=>output.write(JSON.stringify(value)+"\n");
 try{
  await session.connect();emit({ready:true,port:29069,history_exported:false});
  const lines=readline.createInterface({input,crlfDelay:Infinity});
  for await(const line of lines){
   if(Buffer.byteLength(line)>1024)throw Error("bounded_request_required");
   const request=JSON.parse(line);
   if(request.op==="close"){await session.close();emit({closed:true});return;}
   if(request.op!=="inspect")throw Error("read_only_inspect_required");
   const nonce=parseNonce(request.nonce),prefix="[NETWORK50_UI_INSPECT] "+nonce+" ";
   const result=await session.send([{name:"console_send",arguments:{commands:command+" "+nonce}}],"",50,{responsePrefix:prefix});
   if(!result.expected_output_received||typeof result.matched_line!=="string"||!result.matched_line.startsWith(prefix))throw Error("fresh_inspect_reply_missing");
   const sample=JSON.parse(result.matched_line.slice(prefix.length));
   if(!sample||typeof sample!=="object"||Array.isArray(sample))throw Error("inspect_object_required");
   // The Python parent applies the strict public-field whitelist and records
   // only that object. Raw VConsole history/unrelated messages never leave here.
   emit({nonce,sample});
  }
 }finally{await session.close();}
}
module.exports={parseCommand,parseNonce,run};
if(require.main===module)run(process.argv[2]).catch(()=>{process.stdout.write('{"error":"readback_failed_no_raw_output_exported"}\n');process.exitCode=1;});
