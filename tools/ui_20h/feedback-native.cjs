'use strict';
const fs=require('fs'),path=require('path'),cp=require('child_process');
const command=JSON.parse(fs.readFileSync('output/ui_20h/native_probe/command.json','utf8').replace(/^\uFEFF/,''));
const tool='tools/map_c6/console.cjs',base='design_refs/ui_20h/work/feedback10/native';
function send(s){const r=cp.spawnSync(process.execPath,[tool,s,'900'],{encoding:'utf8'});if(r.status!==0)throw Error(r.stderr);return r.stdout;}
function shot(name){const result=send('screenshot'),m=result.match(/Screenshot written to: screenshots[\\/]([^\r\n]+)/);if(!m)throw Error('Screenshot missing');const tga=path.resolve('../../../game/dota/screenshots',m[1].trim()),out=base+'/'+name+'.png';fs.mkdirSync(base,{recursive:true});cp.execFileSync(process.execPath,['tools/shop_ui_12h/tga.cjs',tga,out]);console.log('ACTUAL_GAME_CAPTURE '+out);}
const [action,arg]=process.argv.slice(2);
if(action==='shot')shot(arg);else{const result=send(command.command+' '+[action==='archive'?'archiveopen':action,arg].filter(Boolean).join(' '));if(action==='geometry'){fs.mkdirSync(base,{recursive:true});fs.writeFileSync(base+'/geometry.log',result);const m=result.match(/\[UI20_LAYOUT\] (.+)/);if(m){const data=JSON.parse(m[1]),labels=[];function walk(n){if(n.text!==undefined)labels.push({text:n.text,font:n.font,family:n.fontFamily,xy:n.xy,width:n.width,height:n.height,position:n.position});n.children?.forEach(walk);}walk(data.header);if(data.card)walk(data.card);console.log(JSON.stringify(labels,null,2));}else console.log(result.slice(-1000));}else console.log(result.slice(-3500));}
