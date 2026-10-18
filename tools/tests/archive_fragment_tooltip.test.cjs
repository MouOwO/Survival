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
// The real handoff loads before semantics; controller callbacks run afterwards.
const archiveLayout=fs.readFileSync(path.join(root,'panorama/src/layout/custom_game/archive.xml'),'utf8');
const helperPath='/archive_handoff_180de7e38b.js',semanticsPath='/archive_v10_semantics.js',controllerPath='/archive_180de7e38b_titles_compact_v6.js';
for(const name of[helperPath,semanticsPath,controllerPath])assert(archiveLayout.includes(name));
assert(archiveLayout.indexOf(helperPath)<archiveLayout.indexOf(semanticsPath));
assert(archiveLayout.indexOf(semanticsPath)<archiveLayout.indexOf(controllerPath));
assert.equal(ctx.cfg.ArchiveV10Semantics,undefined);
assert.equal(ctx.unlocked({count:1,target:1},'points'),true,'The early-loaded helper keeps its pre-semantics fallback');
ctx.GameUI={CustomUIConfig:()=>ctx.cfg};
vm.runInContext(fs.readFileSync(path.join(root,'panorama/src/scripts/custom_game/archive_v10_semantics.js'),'utf8'),ctx);
for(const [item,expected]of[
 [{count:0,target:1},false],[{count:1,max_owned:1},true],[{count:7,target:1},true],
 [{count:7,count_known:0,max_owned:1},null],
 [{count:7,count_known:0,max_owned:1,unlocked:1},null],
 [{count:7,quantity_unknown:1,target:1},null],[{max_owned:1},null],
 [{count:3,target:999999},true],[{count:3,count_known:0,target:999999},null],
 [{count:7,unlocked:0,target:1},false]
]){
 const row=Object.freeze({...item}),before=JSON.stringify(row);
 assert.equal(ctx.cfg.ArchiveV10Semantics.State(row,'points'),expected);
 assert.equal(ctx.unlocked(row,'points'),expected,'The actual handoff filter agrees with current points semantics');
 assert.equal(JSON.stringify(row),before,'Filtering never edits legacy excess or unknown server counts');
}
console.log('PASS: actual handoff points filtering resolves live semantics after load; unknown rows enter neither unlocked nor locked.');
assert.equal(ctx.effectMarkup('攻击+10',undefined,false),'<font color="#788b93">攻击+10</font>');
assert.equal(ctx.effectMarkup('攻击+10',undefined,null),'<font color="#788b93">攻击+10</font>');
assert.ok(ctx.effectMarkup('攻击+10',undefined,true).includes('#f0d48a'));
assert.ok(!ctx.effectMarkup('当前Lv1\nLv1 生命+3%\nLv2 攻击+5%',1,true).split('<br>')[2].includes('#f0d48a'));
console.log('PASS: all 14 archive categories, partial progress, activated upgrades, unknown inventory and tooltip colors.');

// Exercise the real tooltip path, including the shared palette's late color reset.
const panels={};
ctx.p=id=>panels[id]||(panels[id]={style:{},AddClass(){},RemoveClass(){},SetImage(){}});
ctx.tipDismiss={CanShow:()=>true,Shown(){}};ctx.hide=()=>{};ctx.position=()=>{};ctx.generation=1;ctx.assets={};ctx.cfg.SurvivalArchiveColors.body='#d8e0e8';
ctx.progress=()=> '0 / 1';
ctx.palette=()=>{ctx.p('ArchiveTooltipEffect').style.color='#d8e0e8';};
vm.runInContext(source.slice(source.indexOf('    function show('),source.indexOf('    function icon(')),ctx);
vm.runInContext(source.slice(source.indexOf('    function isAchievement('),source.indexOf('    function condition(')),ctx);
vm.runInContext(source.slice(source.indexOf('    function condition('),source.indexOf('    // Pixel-space positioning')),ctx);
const card={AddClass(){},GetParent(){return null;}};ctx.root=card;
ctx.show({id:'endless_7',name:'无尽存档7',completed:0,count:0,description:'墙生命加成+10%'},'endless',card,false);
assert.equal(panels.ArchiveTooltipEffect.style.color,'#788b93');
assert.equal(panels.ArchiveTooltipEffect.text,'墙生命加成+10%');
ctx.show({id:'clear_1',completed:1,count:1,description:'墙生命加成+10%'},'clear',card,false);
assert.equal(panels.ArchiveTooltipEffect.style.color,'#d8e0e8');
assert.ok(panels.ArchiveTooltipEffect.text.includes('#f0d48a'));
ctx.show({id:'fragment_1',level:1,description:'Lv1 生命+3%\nLv2 攻击+5%'},'fragment',card,false);
assert.ok(panels.ArchiveTooltipEffect.text.includes('#788b93')&&panels.ArchiveTooltipEffect.text.includes('#f0d48a'));
panels.ArchiveHint.text='神兽狩猎获得碎片 · 每20片晋升1级 · 每种每日20片，通行证40片';
ctx.show({id:'fragment_1',level:1,description:'Lv1 生命+3%'},'fragment',card,false);
assert.equal(panels.ArchiveTooltipCondition.text,panels.ArchiveHint.text,'compact cards retain hidden category earning and daily-limit rules in their tooltip');
panels.ArchiveCurrencySource.text='rendered source without line breaks';
panels.ArchiveCurrencySource.__archivePlainText='软妹币来源：实际在线每满1分钟+1\n不足一分钟累计计算\n通行证不翻倍';
ctx.show({id:'work_1',level:0,cost:1200,target:1,description:'墙生命+1000'},'work',card,false);
assert.equal(panels.ArchiveTooltipCondition.text,'点击激活 · 消耗 1200 软妹币\n'+panels.ArchiveCurrencySource.__archivePlainText,'currency rules preserve source line breaks instead of reading rendered markup');
ctx.show({name:'晋升兑换',description:'消耗200片，兑换下一阶碎片×1'},'',card,true);
assert.equal(panels.ArchiveTooltipState.visible,false);
assert.equal(panels.ArchiveTooltipProgressRow.visible,false);
assert.equal(panels.ArchiveTooltipCondition.visible,false);
assert.equal(panels.ArchiveTooltipDivider.visible,false);
assert.equal(panels.ArchiveTooltip.__archiveEffectOnly,true);
console.log('PASS: actual tooltip show path keeps locked effects dim after palette refresh and restores unlocked effects.');

vm.runInContext(source.slice(source.indexOf('    function progress('),source.indexOf('    function isAchievement(')),ctx);
assert.equal(ctx.cardProgress({count:3,target:999999},'points'),'拥有 ×3');
for(const [item,text]of[[{count:1,target:1},'已解锁'],[{count:0,max_owned:1},'未解锁'],[{count:7,count_known:0,unlocked:1,target:1},'状态待同步'],[{count:7,target:1},'已解锁']]){
 const row=Object.freeze({...item}),before=JSON.stringify(row);assert.equal(ctx.cardProgress(row,'points'),text);
 assert.equal(JSON.stringify(row),before,'Fallback captions never clamp historical inventory');
}
assert.equal(ctx.cardProgress({count:0,target:65},'friend'),'拥有 ×0');
assert.equal(ctx.cardProgress({count:4,count_known:0},'fishing'),'拥有 ×—');
assert.equal(ctx.cardProgress({count:20,level:1},'fragment'),'碎片 ×20');
assert.equal(ctx.cardProgress({level:2,target:5},'building'),'LV2 / 5');
assert.equal(ctx.cardProgress({count:3,target:5},'clear'),'3 / 5');
console.log('PASS: collection ownership, unknown inventory, fragment stock and artifact level captions.');

const controller=fs.readFileSync(path.join(root,'panorama/src/scripts/custom_game/archive_180de7e38b_titles_compact_v6.js'),'utf8');
const promotionMatch=controller.match(/^([ \t]*)promote\.SetPanelEvent\(\s*"onmouseover"\s*,\s*function\s*\(\s*\)\s*\{/m);
if(promotionMatch){
 const endToken='\n'+promotionMatch[1]+'});',end=controller.indexOf(endToken,promotionMatch.index);
 assert(end>promotionMatch.index,'A retained promotion callback must have a complete source body');
 let help;
 const promotionCtx={active:()=>true,valid:p=>!!p,rows:[{id:'fragment_05',name:'神兵-狂战斧'}],item:{promotion_target:'fragment_05',promotion_cost:10},promote:{SetPanelEvent(name,fn){this.hover=fn;}},A:{ShowEffectOnly(item){help=item;}}};
 vm.runInNewContext(controller.slice(promotionMatch.index,end+endToken.length),promotionCtx);promotionCtx.promote.hover();
 assert(help.description.includes('兑换狂战斧碎片×1'));assert(!help.description.includes('fragment_05'),'internal ids must not appear in player help');
 promotionCtx.rows=[];promotionCtx.promote.hover();assert(help.description.includes('下一阶神兵'));
 console.log('PASS: retained promotion help resolves configured names and hides internal ids.');
}else{
 // Promotion controls were retired; exercise the current real fragment-card
 // event and its actual tooltip guard instead of slicing a missing callback.
 const hoverSource=controller.match(/card\.SetPanelEvent\(\s*"onmouseover"\s*,\s*function\s*\(\s*\)\s*\{[^\n]+\}\);/);
 const tooltipSource=controller.match(/function tooltip\(item,\s*card\)\s*\{[^\n]+\}/);
 assert(hoverSource&&tooltipSource,'Current fragment cards retain a real tooltip event');
 const fragmentItem=Object.freeze({id:'fragment_05',name:'神兵-狂战斧',level:1,description:'Lv1 攻击+5%',promotion_target:'fragment_06',promotion_cost:10});
 const calls=[],fragmentCard={AddClass(){},GetParent(){return null;},SetPanelEvent(name,fn){assert.equal(name,'onmouseover');this.hover=fn;}};
 let fragmentActive=true;
 const fragmentCtx={active:()=>fragmentActive,valid:p=>!!p,current:'fragment',item:fragmentItem,card:fragmentCard,A:{Show(item,category,anchor){calls.push({item,category,anchor});ctx.show(item,category,anchor,false);}}};
 vm.createContext(fragmentCtx);vm.runInContext(tooltipSource[0],fragmentCtx);vm.runInContext(hoverSource[0],fragmentCtx);fragmentCard.hover();
 assert.equal(calls.length,1);assert.equal(calls[0].item,fragmentItem);assert.equal(calls[0].category,'fragment');assert.equal(calls[0].anchor,fragmentCard);
 assert.equal(panels.ArchiveTooltipName.text,fragmentItem.name);assert(panels.ArchiveTooltipEffect.text.includes('攻击'));
 assert(panels.ArchiveTooltipCondition.text.includes('神兽狩猎'),'Current card hover retains actual earning and daily-limit rules');
 const displayed=[panels.ArchiveTooltipName.text,panels.ArchiveTooltipEffect.text,panels.ArchiveTooltipCondition.text].join('\n');
 assert(!displayed.includes('fragment_05')&&!displayed.includes('fragment_06'),'Current fragment help never substitutes internal ids for player text');
 fragmentActive=false;fragmentCard.hover();assert.equal(calls.length,1,'Retired card hover cannot reopen the tooltip');
 console.log('PASS: current real fragment-card hover preserves configured name/effects/rules, omits internal ids and obeys its active guard.');
}
