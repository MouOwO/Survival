'use strict';
const fs=require('node:fs'),path=require('node:path');
const {ConsoleSession}=require('../map_c6/console-session.cjs');
async function main(){
 const session=new ConsoleSession({timeoutMs:5000,historyTimeoutMs:15000,retainOutput:false});
 let result;
 try{
  await session.connect();
  const requests=JSON.parse(fs.readFileSync('design_refs/shop_functional_20261016/native_readonly_probe.json','utf8'));
  const response=await session.send(requests,'[SHOP_FUNCTION_NATIVE] done=1',0);
  const lines=response.output.split(/\r?\n/).filter(s=>s.includes('[SHOP_FUNCTION_NATIVE]'));
  result={status:'PASS',kind:'read_only_native_game_and_require_metadata',lines};
 }catch(error){
  result={status:'BLOCKED',kind:'read_only_native_game_and_require_metadata',reason:String(error.message).replace(/SURVIVAL_CONSOLE_SESSION_READY_[0-9a-f]+/g,'<nonce>')};
 }finally{await session.close();}
 const out=path.resolve('design_refs/shop_functional_20261016/native_readonly_result.json');
 fs.writeFileSync(out,JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));
}
main().catch(()=>{console.error('Native metadata probe failed');process.exitCode=1;});
