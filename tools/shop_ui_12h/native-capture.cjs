'use strict';
const fs=require('fs'),path=require('path'),{spawnSync}=require('child_process');
const root=path.resolve('design_refs/shop_ui_12h'),consoleTool=path.resolve('tools/map_c6/console.cjs');
function command(c,ms=800){const r=spawnSync(process.execPath,[consoleTool,c,String(ms)],{encoding:'utf8'});if(r.status!==0)throw Error('Native command failed: '+c);return r.stdout;}
function shot(name){const out=command('screenshot',900),m=out.match(/Screenshot written to: screenshots[\\/]([^\r\n]+)/);if(!m)throw Error('Native screenshot path missing');const file=m[1].trim(),src=path.resolve('../../../game/dota/screenshots',file),dest=root+'/work/production/'+name+'.png';const r=spawnSync(process.execPath,['tools/shop_ui_12h/tga.cjs',src,dest],{encoding:'utf8'});if(r.status!==0)throw Error(r.stderr);console.log('NATIVE_CAPTURE '+name+' '+file);return {name,file,at:new Date().toISOString()};}
const mode=process.argv[2]||'final';
const state=spawnSync(process.execPath,[consoleTool,'--file',root+'/work/phase_test.json','--timeout-ms','800'],{encoding:'utf8'}).stdout;
if(!state.includes('[SHOP_STATE] 10'))throw Error('Native capture requires active game state 10; no best screenshot is overwritten');
const shots=[];
if(mode==='baseline') {const c=JSON.parse(fs.readFileSync('output/commerce_ui_12h/native_before_probe/command.json','utf8'));command(c.open,1900);shots.push(shot('native_before'));}
else {const c=JSON.parse(fs.readFileSync(root+'/work/native_commands.json','utf8'));command(c.open,1300);command(c.technology,800);command(c.normal,700);shots.push(shot('native_final_normal'));command(c.hover,700);shots.push(shot('native_final_hover'));command(c.item,700);shots.push(shot('native_final_item'));command(c.close,700);shots.push(shot('native_final_hud_closed'));}
fs.writeFileSync(root+'/work/production/native_'+mode+'_capture.json',JSON.stringify({kind:'real_Dota2_Tools_screenshot',viewport:[1280,800],state:10,scope:'Actual authenticated catalog, no checkout. Hover is Tools forced state. Other resolutions are browser preview only.',shots},null,2));
