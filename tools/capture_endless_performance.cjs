'use strict';
const fs = require('node:fs');
const path = require('node:path');
const {connect} = require('./map_c6/console-session.cjs');
(async () => {
  const session = await connect({port:Number(process.env.DOTA2_VCON_GUI_PORT || 29001),timeoutMs:35000,historyTimeoutMs:35000,retainOutput:true});
  try {
    await session.send([{name:'dota_run_lua',arguments:{code:'require("core/scheduler_profile").start(20); require("tests/manual_endless_performance").run(20); print("ENDLESS_PERF_STARTED")'}}], 'ENDLESS_PERF_STARTED');
    await new Promise(resolve => setTimeout(resolve,23000));
    await session.send([{name:'dota_run_lua',arguments:{code:'require("tests/manual_endless_performance").stop(); require("core/scheduler_profile").stop("manual"); print("ENDLESS_PERF_FINISHED")'}}], 'ENDLESS_PERF_FINISHED');
    const output = session.rawOutput.split(/\r?\n/).filter(line => /ENDLESS_PERF|SCHEDULER_PERF|thinking for/.test(line)).join('\n');
    const dir=path.resolve(__dirname,'../output/endless_performance');
    fs.mkdirSync(dir,{recursive:true});
    fs.writeFileSync(path.join(dir,'capture-'+Date.now()+'.log'),output+'\n');
    console.log(output);
  } finally { await session.close(); }
})().catch(error => { console.error(error.message);process.exitCode=1; });
