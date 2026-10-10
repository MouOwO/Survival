'use strict';
const fs=require('fs'),path=require('path'),cp=require('child_process'),crypto=require('crypto');
const content=path.resolve('../../../content/dota_addons/Survival');
const git=args=>cp.execFileSync('git',['-C',content,'-c','safe.directory='+content.replaceAll('\\','/'),...args],{maxBuffer:32*1024*1024});
const keep=new Set(['panorama/layout/custom_game/archive.xml','panorama/layout/custom_game/survival_hud.xml','panorama/scripts/custom_game/production_progress.js','panorama/styles/custom_game/production_progress.css']);
const backup='output/ui_20h/reconcile_'+Date.now(),records=[];
function save(file,bytes){fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,bytes);}
const plan=JSON.parse(fs.readFileSync('design_refs/ui_20h/work/feedback10/reconcile_plan.json','utf8'));
if(git(['rev-parse','HEAD']).toString().trim()!==plan.contentHead)throw Error('Content HEAD changed');
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
for(const item of plan.items){
 if(sha(fs.readFileSync(path.join(content,item.file)))!==item.currentHash||sha(fs.readFileSync(item.file.replace('panorama/','panorama/src/')))!==item.gameHash)throw Error('Intervening edit '+item.file);
 if(sha(git(['show','HEAD:'+item.file]))!==item.targetHeadHash)throw Error('Upstream bytes changed '+item.file);
}
const dirty=plan.items.filter(item=>!item.alreadyHead).map(item=>item.file);
for(const file of dirty){
 if(!file.startsWith('panorama/')||keep.has(file))continue;
 let bytes=git(['show','HEAD:'+file]);
 let code=bytes.toString();
 if(file.endsWith('/daily_remaining_5d5c1152eb.js'))code=code.replace(/\}\)\(\);\s*$/, "if(cfg.SurvivalJade){cfg.SurvivalJade.Action(p('DailyClaim'));cfg.SurvivalJade.Action(p('DailyBack'));cfg.SurvivalJade.Tooltip(p('DailyTooltip'));}\n})();\n");
 if(file.endsWith('/lottery_ui_remaining_5d5c1152eb.js'))code=code.replace(/\}\)\(\);\s*$/, 'var jade=GameUI.CustomUIConfig().SurvivalJade;if(jade){jade.Action($("#LotteryInfoConfirm"));jade.Action($("#LotteryConfirm"));}\n})();\n');
 bytes=Buffer.from(code);
 const gameFile=file.replace('panorama/','panorama/src/');
 for(const target of [gameFile,path.join(content,file)]){
  if(fs.existsSync(target))save(backup+'/'+(target===gameFile?'game/':'content/')+file,fs.readFileSync(target));
  save(target,target===gameFile?bytes:Buffer.from(code.replaceAll('\r\n','\n').replaceAll('\n','\r\n')));
 }
 records.push({file,policy:code===git(['show','HEAD:'+file]).toString()?'retain content HEAD':'content HEAD plus passive Jade decoration',sha256:crypto.createHash('sha256').update(bytes).digest('hex')});
}
save(backup+'/manifest.json',JSON.stringify({contentHead:git(['rev-parse','HEAD']).toString().trim(),intentional:[...keep],records},null,2));
save('design_refs/ui_20h/work/feedback10/content_reconciliation.json',JSON.stringify({backup,records},null,2));
console.log('CONTENT_UPSTREAM_PRESERVED '+records.length+' files; UI decorations merged separately');
