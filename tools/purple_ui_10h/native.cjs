'use strict';
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process');
const args=process.argv.slice(2),arg=(name,fallback)=>{const i=args.indexOf(name);return i<0?fallback:args[i+1];};
let command=arg('--command');const capture=arg('--capture'),menu=arg('--menu');
function send(text){return cp.execFileSync(process.execPath,['tools/map_c6/console.cjs',text,'--timeout-ms','1800'],{encoding:'utf8',maxBuffer:4*1024*1024});}
if(menu){
  if(!/^(archive|shop|commerce|daily_rewards|treasure|lottery|close|inspect|battlefield|archive_category_(clear|shadow|points|starjoy_points|gift|fragment|pet|endless|friend|ex|beast|map_level|work|building|fishing|boss|titles))$/.test(menu))throw Error('Unknown review menu');
  const matches=[...send('find survival_purple_review_').matchAll(/survival_purple_review_(\d+)/g)].map(m=>Number(m[1]));
  if(!matches.length)throw Error('No native review command');
  command='survival_purple_review_'+Math.max(...matches)+' '+menu;
}
if(command)process.stdout.write(send(command).slice(-12000));
if(capture){
  if(!/^[a-z0-9_]+$/.test(capture))throw Error('Invalid capture name');
  const output='design_refs/purple_ui_10h/work/native/'+capture+'.png';
  if(fs.existsSync(output))throw Error('Capture already exists: '+output);
  const response=send('screenshot'),match=response.match(/Screenshot written to: screenshots[\\/]([^\r\n]+)/);
  if(!match)throw Error('Engine did not return a screenshot path: '+response.slice(-2000));
  const file=path.resolve('../../../game/dota/screenshots',match[1].trim());
  cp.execFileSync(process.execPath,['tools/shop_ui_12h/tga.cjs',file,output],{stdio:'inherit'});
  const record={at:new Date().toISOString(),kind:'actual_game_capture',command:command||null,input:file,output};
  fs.writeFileSync(output.replace('.png','.json'),JSON.stringify(record,null,2));
  console.log('PURPLE_NATIVE_CAPTURE '+output);
}
