'use strict';
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const root='design_refs/shop_ui_12h',dest=root+'/work/checkpoints/production_best',hash=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const files=['panorama/src/scripts/custom_game/commerce_remaining_5d5c1152eb.js','panorama/src/scripts/custom_game/common/commerce_components.js','panorama/src/scripts/custom_game/common/commerce_art_manifest.js','panorama/src/styles/custom_game/common/commerce_jade.css','panorama/src/layout/custom_game/commerce_resources.xml','panorama/src/layout/custom_game/survival_hud.xml'];
fs.mkdirSync(dest,{recursive:true});for(const f of files){fs.mkdirSync(path.dirname(dest+'/'+f),{recursive:true});fs.copyFileSync(f,dest+'/'+f);}
fs.cpSync('art/ui/sources/custom_game/commerce_jade_v1',dest+'/art/ui/sources/custom_game/commerce_jade_v1',{recursive:true});
const compiled=files.map(f=>f.replace('panorama/src/','panorama/').replace(/\.js$/,'.vjs_c').replace(/\.css$/,'.vcss_c').replace(/\.xml$/,'.vxml_c'));
function walk(dir){return fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(dir+'/'+e.name):[dir+'/'+e.name]);}
compiled.push(...walk('panorama/images/custom_game/commerce_jade_v1').filter(f=>f.endsWith('.vtex_c')));
for(const f of compiled){fs.mkdirSync(path.dirname(dest+'/'+f),{recursive:true});fs.copyFileSync(f,dest+'/'+f);}
fs.mkdirSync(dest+'/evidence',{recursive:true});
for(const name of ['native_before.png','native_final_normal.png','native_final_hover.png','native_final_item.png','native_final_hud_closed.png','native_baseline_capture.json','native_final_capture.json','verification.json','extended_qa.json'])fs.copyFileSync(root+'/work/production/'+name,dest+'/evidence/'+name);
for(const id of ['L21','L22','T23','T24'])fs.cpSync(root+'/work/candidates/'+id,dest+'/candidate_evidence/'+id,{recursive:true});
const data={best:'B17 + L21 + T23',at:new Date().toISOString(),files:files.map(f=>({path:f,sha256:hash(f)})),decisions:[{id:'L21',keep:true,improvement:'长说明改用全展示区软边遮罩，消除额外硬矩形；仍看得到商品',cost:'长说明覆盖更多商品，只有长说明启用'},{id:'L22',keep:false,improvement:'文字对比度更强',cost:'94%深色遮挡明显压过商品，84%已足够'},{id:'T23',keep:true,improvement:'53x48原券图内嵌96px，减少放大模糊，保持原图映射；独立投影跟随实际展示比例',cost:'该旧图仍有自带背景，需将来提供高分辨率透明原资源'},{id:'T24',keep:false,improvement:'128px券图轮廓更大',cost:'模糊和自带矩形更明显'}]};
fs.writeFileSync(dest+'/manifest.json',JSON.stringify(data,null,2));fs.writeFileSync(root+'/work/best.json',JSON.stringify(data,null,2));
fs.writeFileSync(dest+'/compiled_manifest.json',JSON.stringify({best:data.best,at:data.at,files:compiled.map(f=>({path:f,sha256:hash(f)}))},null,2));
if(!fs.readFileSync(root+'/Decisions.md','utf8').includes('10_production_adaptation'))fs.appendFileSync(root+'/Decisions.md','\n## 10_production_adaptation · 保留 B17 + L21 + T23\n\n'+data.decisions.map(d=>`- ${d.id}：${d.keep?'保留':'淘汰'}；改善：${d.improvement}；代价：${d.cost}。证据 work/candidates/${d.id}/normal.png、hover.png、card_hover.png。`).join('\n')+'\n\n确认的264×224展示区和256×192标准图区域不变。仅低清历史缩略图使用其内部96×96 inset。共24个实质候选，最新T24淘汰。\n');
console.log('PRODUCTION_BEST_SAVED '+data.best);
