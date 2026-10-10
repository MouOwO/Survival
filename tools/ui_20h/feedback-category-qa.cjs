'use strict';
const fs=require('fs'),assert=require('assert'),{browser}=require('../shop_ui_12h/cdp.cjs');
const base='design_refs/ui_20h/work/feedback10',categories=fs.readFileSync('data/csv/存档系统/archive_categories.csv','utf8').split(/\r?\n/).filter(line=>/^"/.test(line)).map(line=>line.split(',').map(s=>s.replaceAll('"',''))).filter(row=>row[4]==='1').map(row=>({id:row[0],name:row[1]}));categories.push({id:'titles',name:'称号'});
(async()=>{const b=await browser(),records=[];try{
 await b.go('design_refs/ui_20h/work/preview/index.html','?page=archive');
 for(let i=0;i<categories.length;i++){
  const category=categories[i];await b.run(`(()=>{const categories=${JSON.stringify(categories)};emit('survival_archive_snapshot',{ok:1,category_id:'clear',sequence:100,chunk:1,chunks:1,categories,rows:[]});nodes['ArchiveTab_${category.id}'].events.onactivate();emit('survival_archive_snapshot',{ok:1,category_id:'${category.id}',sequence:${200+i},chunk:1,chunks:1,categories,pending:0,title_preview:1,rows:[0,1].map(n=>({id:'test_${category.id}_'+n,name:'${category.name} '+n,description:'攻击力提升 2%\\n攻击速度提升 10%',count:n,target:10,level:n,unlocked:n,icon_type:'item',icon:'${category.id}'==='titles'?'file://{images}/custom_game/titles/peak_clean_letters.png':'item_skadi',cost:10,can_upgrade:1,max_level:5,upgrade_cost:10,equipped:0,preview_only:1}))});syncFlows();return true;})()`);
  const data=await b.run(`(()=>{const cards=nodes.ArchiveGrid.Children().filter(p=>p.BHasClass('ArchiveCard')&&p.visible);return {count:cards.length,category:cfg.ArchiveHandoff.snapshot.category_id,names:cards.map(p=>p.el.querySelector('.ArchiveItemName,.ArchiveTitleName')?.textContent),cards:cards.map(p=>({width:p.actuallayoutwidth,height:p.actuallayoutheight}))};})()`);
  assert.equal(data.count,2);assert.equal(data.category,category.id);assert(data.names.every(Boolean));
  await b.shot(base+'/categories/'+category.id+'.png');
  if(category.id==='titles'){const events=await b.run('previewCalls=[];nodes.ArchiveGrid.Children().filter(p=>p.BHasClass("ArchiveCard")&&p.visible)[1].events.onactivate();previewCalls');assert.equal(events.length,1);assert.equal(events[0].name,'survival_archive_title_equip');assert.equal(events[0].payload.title_id,'test_titles_1');}
  records.push({...category,...data});
 }
 fs.writeFileSync(base+'/categories/report.json',JSON.stringify({scope:'Actual compact archive controller with explicit category fixtures; no server actions',records},null,2));console.log('ARCHIVE_CATEGORY_QA_PASS '+records.length+' pages and title equip event');
}finally{b.close();}})().catch(e=>{console.error(e);process.exitCode=1});
