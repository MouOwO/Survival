'use strict';
// No raw console history, commands, credential strings or profile data leave here.
const readline=require('node:readline');
const crypto=require('node:crypto');
const {ConsoleSession}=require('../map_c6/console-session.cjs');
let session=null;
const input=readline.createInterface({input:process.stdin,crlfDelay:Infinity});
async function request(value){
  if(!value || !Number.isInteger(value.id) || !['probe','apply'].includes(value.op))
    return {id:value?.id,ok:false,error:'invalid_operation'};
  try{
    if(!session){
      session=new ConsoleSession({port:29003,timeoutMs:6000,historyTimeoutMs:12000,
        retainOutput:false,maxPendingOutputChars:65536});
      await session.connect();
    }
    const marker='WS4_LOCAL_CMD_'+crypto.randomBytes(12).toString('hex');
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
  }catch(_){
    if(session)await session.close().catch(()=>{});
    session=null;
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
