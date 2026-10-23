'use strict';
// No raw console history, commands, credential strings or profile data leave here.
const readline=require('node:readline');
const crypto=require('node:crypto');
const {ConsoleSession}=require('../map_c6/console-session.cjs');
let session=null;
let listenRequested=false;
let listenRejected=false;
const input=readline.createInterface({input:process.stdin,crlfDelay:Infinity});
async function request(value){
  if(!value || !Number.isInteger(value.id) || !['probe','apply','listen'].includes(value.op))
    return {id:value?.id,ok:false,error:'invalid_operation'};
  if(value.op==='listen' && listenRejected)return {id:value.id,ok:false,error:'listen_map_request_rejected'};
  if(value.op==='listen' && listenRequested)return {id:value.id,ok:true,state:{status:'listen_map_requested'}};
  try{
    if(!session){
      session=new ConsoleSession({port:29003,timeoutMs:6000,historyTimeoutMs:12000,
        retainOutput:false,maxPendingOutputChars:65536});
      await session.connect();
    }
    const marker='WS4_LOCAL_CMD_'+crypto.randomBytes(12).toString('hex');
    if(value.op==='listen'){
      const result=await session.send([{name:'console_send',arguments:{commands:
        'map template_map gamemode=15 customgamemode=survival_ws4_local loopback=false nomapvalidation=1\necho '+marker}}],marker,150);
      listenRequested=result.sent>=1 || result.expected_output_received===true;
      if(/invalid map name|[Cc]ouldn.t find map|[Uu]nknown command/.test(result.output)){
        listenRejected=true;
        return {id:value.id,ok:false,error:'listen_map_request_rejected'};
      }
      if(!listenRequested)return {id:value.id,ok:false,error:'listen_map_request_incomplete'};
      return {id:value.id,ok:true,state:{status:'listen_map_requested'}};
    }
    const file=value.op==='apply'?'apply':'probe';
    const r=await session.send([{name:'console_send',arguments:{commands:
      'script_reload_code ws4_local_launcher/'+file+'.lua\necho '+marker}}],marker,150);
    const lines=r.output.split(/\r?\n/).filter(s=>s.startsWith('WS4_LOCAL_STATUS:'));
    if(!r.expected_output_received || !lines.length)
      return {id:value.id,ok:false,error:'waiting_for_tools_map'};
    const raw=JSON.parse(lines.at(-1).slice('WS4_LOCAL_STATUS:'.length));
    const state={};
    for(const name of ['status','phase','error'])
      if(typeof raw[name]==='string' && /^[A-Za-z0-9_]{1,83}$/.test(raw[name]))state[name]=raw[name];
    for(const name of ['players','authenticated','profiles'])
      if(Number.isInteger(raw[name]) && raw[name]>=0 && raw[name]<=4)state[name]=raw[name];
    for(const name of ['admission_complete','profiles_ready','credential_applied'])
      if(typeof raw[name]==='boolean')state[name]=raw[name];
    return {id:value.id,ok:true,state};
  }catch(error){
    // A lost echo after the map CMND was written must not reload the room.
    if(value.op==='listen' && error.sent>=1)listenRequested=true;
    if(session)await session.close().catch(()=>{});
    session=null;
    if(value.op==='listen' && listenRequested)return {id:value.id,ok:true,state:{status:'listen_map_requested'}};
    return {id:value.id,ok:false,error:'console_unavailable'};
  }
}
(async()=>{
  for await(const line of input){
    let value;try{value=JSON.parse(line);}catch(_){value={};}
    process.stdout.write(JSON.stringify(await request(value))+'\n');
  }
  if(session)await session.close();
})().catch(()=>{process.exitCode=1;});
