'use strict';
// Explicit short diagnostic, never a frame-rate acceptance sample.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {ConsoleSession}=require('./map_c6/console-session.cjs');
const label=process.argv[2],timings=process.argv[3]==='timings';
if(!label||!/^[a-z0-9_]+$/.test(label))throw Error('Unique lowercase evidence label required');
const out=path.resolve(__dirname,'../output/four_operation_extreme_20261012',label+'.json');
if(fs.existsSync(out))throw Error('Evidence already exists');
const token='NATIVE_LUA_CALL_'+crypto.randomBytes(8).toString('hex');
const vscriptsRoot=path.resolve(__dirname,'../scripts/vscripts').replaceAll('\\','/');
(async()=>{const s=new ConsoleSession({timeoutMs:15000,historyTimeoutMs:60000});try{
  await s.connect();
  const start=await s.send([{name:'dota_run_lua',arguments:{code:"local previous=package.loaded['tests/manual_native_lua_callback_probe'];if previous then local ok,reason=previous.stop();assert(ok or reason=='not_started',tostring(reason));package.loaded['tests/manual_native_lua_callback_probe']=nil end;local p=require('tests/manual_native_lua_callback_probe');local ok,reason=p.start({seconds=5,max_calls=100000,vscripts_root="+JSON.stringify(vscriptsRoot)+",sample_timings="+(timings?'true':'false')+",sample_every=32});assert(ok,tostring(reason));print('"+token+"_START')"}}],token+'_START',100);
  console.log(start.output.trim());await new Promise(r=>setTimeout(r,6500));
  const code="local p=require('tests/manual_native_lua_callback_probe');local function safe(v) if type(v)~='table' then return v end;local n,max,array=0,0,true;for k in pairs(v) do n=n+1;if type(k)~='number' or k<1 or k~=math.floor(k) then array=false else max=math.max(max,k) end end;array=array and max==n;local r={};for k,x in pairs(v) do r[array and k or tostring(k)]=safe(x) end;return r end;local encoded=require('core/json_encoder').encode(safe(p.report()));local first,index=1,0;while first<=#encoded do local last=math.min(#encoded,first+1100);while last<#encoded and encoded:byte(last+1)>=128 and encoded:byte(last+1)<=191 do last=last-1 end;index=index+1;print('[LUA_CALL_CHUNK] '..require('core/json_encoder').encode({index=index,data=encoded:sub(first,last)}));first=last+1 end;print('"+token+"_REPORT')";
  const report=await s.send([{name:'dota_run_lua',arguments:{code}}],token+'_REPORT',100);
  const chunks=report.output.split(/\r?\n/).filter(x=>x.startsWith('[LUA_CALL_CHUNK] ')).map(x=>JSON.parse(x.slice(17)));
  if(!chunks.length||chunks.some((x,i)=>x.index!==i+1))throw Error('Native hook report incomplete');
  const result=JSON.parse(chunks.map(x=>x.data).join(''));fs.writeFileSync(out,JSON.stringify(result,null,2),{flag:'wx'});
  console.log(JSON.stringify({file:out,status:result.status,coverage:result.coverage,restore_status:result.restore_status,limits:result.limits}));
}finally{try{await s.send([{name:'dota_run_lua',arguments:{code:"local p=package.loaded['tests/manual_native_lua_callback_probe'];if p then p.stop('transport_cleanup') end;print('"+token+"_CLEAN')"}}],token+'_CLEAN',100);}catch(e){console.error('Native hook cleanup not acknowledged: '+e.message);}await s.close();}})().catch(e=>{console.error(e.message);process.exitCode=1;});
