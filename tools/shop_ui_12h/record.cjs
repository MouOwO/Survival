'use strict';
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const base=path.resolve('design_refs/shop_ui_12h');
function record(group,best,entries){
 const dest=path.join(base,'work/checkpoints',group),candidate=path.join(base,'work/candidates',best);
 fs.mkdirSync(dest,{recursive:true});
 for(const name of ['config.json','assembly.html','overrides.css','normal.png','hover.png','card_normal.png','card_hover.png','header.png','sidebar.png'])fs.copyFileSync(path.join(candidate,name),path.join(dest,name));
 fs.cpSync(path.join(candidate,'assets'),path.join(dest,'assets'),{recursive:true});
 const info={group,best,entries,at:new Date().toISOString(),kind:'assembled_component_browser_preview',hash:crypto.createHash('sha256').update(fs.readFileSync(path.join(candidate,'normal.png'))).digest('hex')};
 fs.writeFileSync(path.join(dest,'decision.json'),JSON.stringify(info,null,2));
 fs.writeFileSync(path.join(base,'work/best.json'),JSON.stringify(info,null,2));
 fs.appendFileSync(path.join(base,'Decisions.md'),`\n## ${group} · 保留 ${best}\n\n`+entries.map(e=>`- ${e.id}：${e.result}；改善：${e.improvement}；代价/淘汰依据：${e.cost}。截图：work/candidates/${e.id}/normal.png、hover.png及100%局部。`).join('\n')+'\n');
 fs.appendFileSync(path.join(base,'Progress.md'),`\n${info.at}：${group} 实际查看组装与局部；当前最佳 ${best}，检查点 work/checkpoints/${group}。\n`);
 console.log('CHECKPOINT '+group+' best='+best);
}
module.exports=record;
if(require.main===module)record(...JSON.parse(process.argv[2]));
