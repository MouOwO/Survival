'use strict';
// Local ToolsMode UI review and engine screenshot capture. No archive writes.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process');
const repo=path.resolve(__dirname,'../..'),args=process.argv.slice(2);
const arg=(name,fallback)=>{const i=args.indexOf(name);if(i<0)return fallback;const v=args[i+1];if(v===undefined||v.startsWith('--'))throw Error('Missing value: '+name);return v;};
const command=arg('--command'),capture=arg('--capture'),menu=arg('--menu'),voidAction=arg('--void-action');
const commands=[];
function send(text){return cp.execFileSync(process.execPath,[path.join(repo,'tools/map_c6/console.cjs'),text,'--timeout-ms','1800'],{cwd:repo,windowsHide:true,encoding:'utf8',maxBuffer:4*1024*1024});}
function reviewCommand(prefix){
  const matches=[...send('find '+prefix).matchAll(new RegExp(prefix+'(\\d+)','g'))].map(m=>Number(m[1])).filter(Number.isSafeInteger);
  if(!matches.length)throw Error('No current native review command: '+prefix+' (Dota Workshop Tools and the compiled UI must be loaded).');
  return prefix+Math.max(...matches);
}
if(command)commands.push(command);
if(menu){
  if(!/^(archive|shop|commerce|daily_rewards|treasure|lottery|close|inspect|battlefield|archive_category_(clear|shadow|points|starjoy_points|gift|fragment|pet|endless|friend|ex|beast|map_level|work|building|fishing|boss|titles))$/.test(menu))throw Error('Unknown review menu');
  commands.push(reviewCommand('survival_purple_review_')+' '+menu);
}
if(voidAction){
  if(!/^(inspect|hide|close|hover shadow_\d{2}|filter (all|unlocked|locked))$/.test(voidAction))throw Error('Unknown void review action');
  // This command is registered and guarded by the production UI in ToolsMode only.
  // Refuse to substitute script injection or a server-side data mutation if absent.
  commands.push(reviewCommand('survival_void_v1_review_')+' '+voidAction);
}
for(const text of commands)process.stdout.write(send(text).slice(-12000));
if(capture){
  if(!/^[a-z0-9_]+$/.test(capture))throw Error('Invalid capture name');
  const relative='design_refs/void_shadow_v1/work/native/'+capture+'.png',output=path.join(repo,relative);
  if(fs.existsSync(output)||fs.existsSync(output.replace(/\.png$/,'.json')))throw Error('Capture already exists: '+relative);
  const response=send('screenshot'),match=response.match(/Screenshot written to: screenshots[\\/]([^\r\n]+)/);
  if(!match)throw Error('Engine did not return a screenshot path: '+response.slice(-2000));
  const screenshotRoot=path.resolve(repo,'../../../game/dota/screenshots'),file=path.resolve(screenshotRoot,match[1].trim());
  if(!file.toLowerCase().startsWith((screenshotRoot+path.sep).toLowerCase()))throw Error('Unexpected screenshot path');
  cp.execFileSync(process.execPath,[path.join(repo,'tools/shop_ui_12h/tga.cjs'),file,output],{cwd:repo,windowsHide:true,stdio:'inherit'});
  const record={at:new Date().toISOString(),kind:'actual_game_capture',commands,input:file,output:relative,voidAction:voidAction||null,validation:'Captured by the Source 2 screenshot command; not an attachment or browser preview'};
  fs.writeFileSync(output.replace(/\.png$/,'.json'),JSON.stringify(record,null,2)+'\n',{flag:'wx'});
  console.log('VOID_NATIVE_CAPTURE '+relative);
}
