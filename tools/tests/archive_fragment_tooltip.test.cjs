const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const path=require('node:path'),root=path.resolve(__dirname,'../..');
const source=fs.readFileSync(path.join(root,'panorama/src/scripts/custom_game/archive_handoff_180de7e38b.js'),'utf8');
const ctx={cfg:{SurvivalArchiveColors:{number:'#f0d48a'}}};vm.createContext(ctx);
vm.runInContext(source.slice(source.indexOf('function formatArchiveEffects'),source.indexOf('    function show(')),ctx);
const config=fs.readFileSync(path.join(root,'scripts/vscripts/config/generated/archive_fragment_levels.lua'),'utf8');
const rows=[...config.matchAll(/fragment_id = "([^"]+)", level = (\d+),[^\n]*?description = "([^"]+)"/g)];
assert.ok(rows.length>0);
for(const [,id,level,description] of rows){
 const input='Lv'+level+' '+description;
 for(const owned of [0,1,5,10,Number(level)-1,Number(level)]){
  const html=ctx.effectMarkup(input,owned);
  assert.ok(!html.includes('<br>'),id+' must keep the level and effect together');
  if(Number(level)>owned){
   assert.equal(html,'<font color="#788b93">LV'+level+' '+description+'</font>');
   assert.ok(!html.includes('#f0d48a'),'Locked numbers must also be dim');
  } else {
   assert.ok(html.startsWith('<font color="#e1e8e8">LV'));
   assert.ok(html.includes('#f0d48a'),'Unlocked values retain gold');
  }
 }
}
assert.equal(ctx.effectMarkup('Lv1 效果+3%',undefined),ctx.effectMarkup('Lv1 效果+3%'),'Other categories do not acquire unlock styling');
assert.equal(ctx.effectMarkup('Lv1 效果+3%','bad'),ctx.effectMarkup('Lv1 效果+3%',0),'Unknown level must not light rewards');
const rowsHtml=ctx.effectMarkup('当前Lv1\nLv1 生命+3%\nLv2 攻击+5%',1).split('<br>');
assert.ok(rowsHtml[1].includes('#e1e8e8')&&rowsHtml[2].includes('#788b93'));
assert.ok(ctx.effectMarkup('Lv1 <tag>&效果+1',0).includes('&lt;tag&gt;&amp;'));
console.log('PASS: '+rows.length+' fragment level rows, unlock thresholds, dim numeric values, row layout and escaping.');

vm.runInContext(source.slice(source.indexOf('    function unlocked('),source.indexOf('    function progress(')),ctx);
for(const category of ['clear','endless','boss','map_level']){
 assert.equal(ctx.unlocked({count:3,target:5,completed:0},category),false);
 assert.equal(ctx.unlocked({count:5,target:5,completed:1},category),true);
}
for(const category of ['fragment','building','work']){
 assert.equal(ctx.unlocked({count:10,level:0,completed:0},category),false);
 assert.equal(ctx.unlocked({count:0,level:1,completed:0},category),true);
}
for(const category of ['shadow','points','pet','friend','ex','beast','fishing']){
 assert.equal(ctx.unlocked({count:0,count_known:1},category),false);
 assert.equal(ctx.unlocked({count:1,count_known:1},category),true);
}
assert.equal(ctx.unlocked({count:10,count_known:0},'fishing'),null);
assert.equal(ctx.unlocked({count:99,unlocked:0},'friend'),false);
assert.equal(ctx.effectMarkup('攻击+10',undefined,false),'<font color="#788b93">攻击+10</font>');
assert.equal(ctx.effectMarkup('攻击+10',undefined,null),'<font color="#788b93">攻击+10</font>');
assert.ok(ctx.effectMarkup('攻击+10',undefined,true).includes('#f0d48a'));
assert.ok(!ctx.effectMarkup('当前Lv1\nLv1 生命+3%\nLv2 攻击+5%',1,true).split('<br>')[2].includes('#f0d48a'));
console.log('PASS: all 14 archive categories, partial progress, activated upgrades, unknown inventory and tooltip colors.');

// Exercise the real tooltip path, including the shared palette's late color reset.
const panels={};
ctx.p=id=>panels[id]||(panels[id]={style:{},AddClass(){},RemoveClass(){},SetImage(){}});
ctx.hide=()=>{};ctx.position=()=>{};ctx.generation=1;ctx.assets={};ctx.cfg.SurvivalArchiveColors.body='#d8e0e8';
ctx.progress=()=> '0 / 1';
ctx.palette=()=>{ctx.p('ArchiveTooltipEffect').style.color='#d8e0e8';};
vm.runInContext(source.slice(source.indexOf('    function show('),source.indexOf('    function icon(')),ctx);
vm.runInContext(source.slice(source.indexOf('    function isAchievement('),source.indexOf('    function condition(')),ctx);
const card={AddClass(){}};
ctx.show({id:'endless_7',name:'无尽存档7',completed:0,count:0,description:'墙生命加成+10%'},'endless',card,false);
assert.equal(panels.ArchiveTooltipEffect.style.color,'#788b93');
assert.equal(panels.ArchiveTooltipEffect.text,'墙生命加成+10%');
ctx.show({id:'clear_1',completed:1,count:1,description:'墙生命加成+10%'},'clear',card,false);
assert.equal(panels.ArchiveTooltipEffect.style.color,'#d8e0e8');
assert.ok(panels.ArchiveTooltipEffect.text.includes('#f0d48a'));
ctx.show({id:'fragment_1',level:1,description:'Lv1 生命+3%\nLv2 攻击+5%'},'fragment',card,false);
assert.ok(panels.ArchiveTooltipEffect.text.includes('#788b93')&&panels.ArchiveTooltipEffect.text.includes('#f0d48a'));
console.log('PASS: actual tooltip show path keeps locked effects dim after palette refresh and restores unlocked effects.');

vm.runInContext(source.slice(source.indexOf('    function progress('),source.indexOf('    function isAchievement(')),ctx);
assert.equal(ctx.cardProgress({count:3,target:999999},'points'),'拥有 ×3');
assert.equal(ctx.cardProgress({count:0,target:65},'friend'),'拥有 ×0');
assert.equal(ctx.cardProgress({count:4,count_known:0},'fishing'),'拥有 ×—');
assert.equal(ctx.cardProgress({count:20,level:1},'fragment'),'碎片 ×20');
assert.equal(ctx.cardProgress({level:2,target:5},'building'),'LV2 / 5');
assert.equal(ctx.cardProgress({count:3,target:5},'clear'),'3 / 5');
console.log('PASS: collection ownership, unknown inventory, fragment stock and artifact level captions.');
