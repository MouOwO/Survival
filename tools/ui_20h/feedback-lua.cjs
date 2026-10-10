'use strict';
const fs=require('fs'),cp=require('child_process');
const code=process.argv[2];if(!code)throw Error('Lua code required');
const file='output/ui_20h/feedback_read.json';fs.writeFileSync(file,JSON.stringify([{name:'dota_run_lua',arguments:{code}}]));
const result=cp.spawnSync(process.execPath,['tools/map_c6/console.cjs','--file',file,'--timeout-ms','1200'],{encoding:'utf8'});process.stdout.write(result.stdout||'');if(result.status!==0)throw Error(result.stderr);
