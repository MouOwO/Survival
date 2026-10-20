'use strict';
const fs=require('node:fs'),path=require('node:path'),{spawnSync}=require('node:child_process');
const root=path.resolve(__dirname,'../..'),lines=fs.readFileSync(path.resolve(root,'../../dota/console.log'),'utf8').split(/\r?\n/);
function command(label,expression){const line=lines.filter(x=>x.includes(label)).at(-1),match=line&&line.match(expression);if(!match)throw Error('Missing current UI inspection command '+label);return match[0];}
const commands=[];
if(process.argv.includes('--open-daily'))commands.push(command('[WINDOW_STYLE_REVIEW]',/survival_window_review_\d+/)+' benefit');
commands.push(command('[MONTHLY_UI_INSPECT_COMMAND]',/survival_monthly_ui_inspect_\d+/));
const result=spawnSync(process.execPath,[path.join(root,'tools/map_c6/console.cjs'),commands.join('\n'),'--timeout-ms','1200'],{encoding:'utf8',windowsHide:true,timeout:15000,cwd:root});
const safe=(result.stdout||'').split(/\r?\n/).filter(x=>x.includes('[MONTHLY_UI_STATE]'));
const state=safe.map(x=>JSON.parse(x.slice(x.indexOf('{')))).at(-1);
if(result.status!==0||!state)throw Error('Native monthly inspection did not complete');
fs.writeFileSync(path.join(root,'design_refs/daily_monthly_checkout_keep_open_20261017/live/state_'+Date.now()+'.json'),JSON.stringify(state,null,2));
console.log(JSON.stringify(state));
