'use strict';
const fs=require('node:fs'),path=require('node:path');
const {connect}=require('./map_c6/console-session.cjs');
const lua=code=>({name:'dota_run_lua',arguments:{code}});
const command=commands=>({name:'console_send',arguments:{commands}});
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
(async()=>{
  const session=await connect({port:29001,timeoutMs:10000,historyTimeoutMs:15000});
  const directory=path.resolve(__dirname,'../output/live_combat_diagnosis/'+Date.now());
  fs.mkdirSync(directory,{recursive:true});
  let ready=false,oldShowFps=0;
  try{
    const value=await session.send([command('cl_showfps')],'',500);
    const parsed=value.output.match(/"cl_showfps"\s*=\s*"?(\d+)/);
    if(parsed)oldShowFps=Number(parsed[1]);
    await session.send([lua('require("tests/manual_live_combat_diagnosis").prepare()')],'LIVE_DIAG_READY');ready=true;
    await session.send([command('survival_live_diag_20261010 begin')],'LIVE_DIAG_BEGIN');
    await sleep(2500);
    await session.send([command('cl_showfps 1\ncl_resetfps\nvprof_off\nvprof_on\nvprof_reset')],'',500);
    console.log('LIVE_NATIVE_CAPTURE_RUNNING');
    await sleep(20000);
    await session.send([command('cl_printfps\nengine_frametime_print_report\nvprof_generate_report\nvprof_off')],'',1500);
    await session.send([command('survival_live_diag_20261010 report')],'LIVE_DIAG_REPORT');
    console.log('LIVE_SERVER_CAPTURE_RUNNING');
    await session.send([command('survival_live_diag_20261010 server')],'',500);
    await sleep(22000);
    await session.send([command('survival_live_diag_20261010 report')],'LIVE_DIAG_REPORT');
    fs.writeFileSync(path.join(directory,'capture.log'),session.rawOutput);
    console.log(session.rawOutput.split(/\r?\n/).filter(line=>/LIVE_DIAG|EXTREME_PERF|frames:|Average.*fps|Peak.*frame|thinking for|Frame time|RenderGPU|Client|frame time/.test(line)).join('\n'));
    console.log('ARTIFACT '+directory);
  }finally{
    if(ready)await session.send([command('survival_live_diag_20261010 cleanup')],'LIVE_DIAG_CLEAN');
    await session.send([command('cl_showfps '+oldShowFps+'\nvprof_off')],'',500);
    await session.close();
  }
})().catch(error=>{console.error(error.message);process.exitCode=1;});
