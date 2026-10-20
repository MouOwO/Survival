'use strict';
const assert=require('node:assert/strict');
const {harness,ready}=require('../test_startup_loading_ui.js');
const names={pure:'纯净模式',standard:'常规模式',fishing:'摸鱼模式',rich:'丰饶模式',cold:'极寒模式',scourge:'天灾模式'};
const modes=Object.entries(names).map(([mode_id,display_name])=>({mode_id,display_name,unlocked:1}));
const displayOrder=['standard','rich','cold','scourge','fishing','pure'];
const modeButton=(ui,mode)=>ui.nodes.MatchModeOptions.children.find(button=>button.children[0].text===names[mode]);
const requests=ui=>ui.requests.filter(r=>r.name==='survival_loading_mode_select');
const options=count=>Array.from({length:count},(_,i)=>({difficulty_id:'N'+(i+1),display_name:'N'+(i+1),unlocked:1}));
for(const [mode,count] of [['cold',10],['scourge',10]]){
 const setup={mode_selected:false,mode_id:'',selector_player_id:0,mode_options:modes,
  difficulty_options:options(10),difficulty_options_by_mode:{standard:options(10),cold:options(10),scourge:options(10)}};
 const state=ready({admission_complete:true,profiles_ready:true,setup});
 const ui=harness({startupState:state,hud:true,loadSharedUI:true});ui.advance(.11);
 assert.equal(ui.nodes.MatchModeOptions.children.length,6,'The active HUD renders all six authoritative mode choices');
 assert.equal(ui.nodes.DifficultySelectionDialog.style.height,'414px','The popup grows to fit all six buttons');
 assert.deepEqual(ui.nodes.MatchModeOptions.children.map(button=>button.children[0].text),displayOrder.map(id=>names[id]),
  'Regular is first, progression modes follow their unlock chain and pure is last');
 const originalRows=ui.nodes.MatchModeOptions.children.slice();
 ui.setStartup(ready({admission_complete:true,profiles_ready:true,setup:{...setup,mode_options:[...modes].reverse()}}));
 originalRows.forEach((row,index)=>assert.equal(ui.nodes.MatchModeOptions.children[index],row,
  'An unordered network snapshot preserves the sorted rows and their pending state'));
 const button=modeButton(ui,mode);
 assert.equal(button.children[0].text,names[mode]);assert(button.enabled);
 button.events.onactivate();button.events.onactivate();
 assert.equal(requests(ui).length,1);assert.equal(requests(ui)[0].payload.mode_id,mode);
 ui.emit('survival_loading_mode_result',{success:1,mode_id:mode,session_id:'match-123'});
 ui.setStartup(ready({admission_complete:true,profiles_ready:true,setup:{...setup,mode_selected:true,mode_id:mode,difficulty_options:options(count)}}));
 assert.equal(ui.nodes.MatchModeOptions.visible,false);
 assert.equal(ui.nodes.DifficultySelectionButtons.children.length,count,'Only configured difficulties are offered');
 assert(ui.nodes.DifficultySelectionHint.text.includes(names[mode]));
 assert(ui.nodes.DifficultySelectionHint.text.includes('N'+count));
 assert.equal(ui.requests.filter(r=>/draw|purchase|checkout|archive/.test(r.name)).length,0);
}
{
 const modeOptions=modes.map(({mode_id,display_name})=>({mode_id,display_name}));
 const setup={mode_selected:false,selector_player_id:0,mode_options:modeOptions};
 const state=ready({admission_complete:true,profiles_ready:true,setup});
 const ui=harness({startupState:state,hud:true,loadSharedUI:true});ui.advance(.11);
 for(const mode of ['rich','cold','scourge']){
  const button=modeButton(ui,mode);
  assert.equal(button.enabled,false,'Missing progression permission cannot unlock '+mode);
  button.events.onactivate();assert.equal(requests(ui).length,0);
 }
 for(const mode of ['standard','fishing','pure'])assert(modeButton(ui,mode).enabled,'Legacy mode snapshots remain compatible');
 ui.setStartup(ready({admission_complete:true,profiles_ready:false,setup:{...setup,
  mode_options:modeOptions.map(option=>option.mode_id==='cold'?{...option,unlocked:1,pending:1}:option)}}));
 const cold=modeButton(ui,'cold');assert.equal(cold.enabled,false);
 cold.events.onmouseover();assert.equal(ui.dispatched.at(-1)[2],'正在读取解锁进度……');
 cold.events.onactivate();assert.equal(requests(ui).length,0,'A pending authenticated profile cannot be bypassed');
}
for(const mode of ['cold','scourge']){
 for(const responseHint of [undefined,'队伍所有玩家通关前一模式 N10 后解锁']){
  const unlockHint=mode==='cold'?'服务端要求丰饶 N10':'服务端要求极寒 N10';
  const setup={mode_selected:false,selector_player_id:0,mode_options:modes.map(option=>option.mode_id===mode?{...option,unlock_hint:unlockHint}:option)};
  const ui=harness({startupState:ready({admission_complete:true,profiles_ready:true,setup}),hud:true,loadSharedUI:true});ui.advance(.11);
  modeButton(ui,mode).events.onactivate();assert.equal(requests(ui).length,1);
  ui.emit('survival_loading_mode_result',{success:0,error:'mode_not_unlocked',unlock_hint:responseHint,session_id:'match-123'});
  assert.equal(ui.nodes.DifficultySelectionError.text,responseHint||unlockHint,'Rejections describe the selected mode using the authoritative unlock hint');
  ui.setStartup(ready({admission_complete:true,profiles_ready:true,setup:{...setup,
   mode_options:setup.mode_options.map(option=>option.mode_id===mode?{...option,unlocked:0}:option)}}));
  const button=modeButton(ui,mode);assert.equal(button.enabled,false);assert(!button.BHasClass('UISelected'));
  button.events.onmouseover();assert.equal(ui.dispatched.at(-1)[2],unlockHint);
  button.events.onactivate();assert.equal(requests(ui).length,1,'A rejection followed by a locked snapshot cannot resend');
 }
}
for(const [mode,source] of [['cold','N4'],['scourge','N2']]){
 const sourceTier=Number(source.slice(1));
 const description='临时配置：沿用'+names[mode]+' '+source+' 的波次与怪物属性。';
 const difficulties=options(10).map((option,index)=>({...option,unlocked:index<5?1:0,
  temporary_config:index>=sourceTier?1:0,source_difficulty_id:index>=sourceTier?source:option.difficulty_id,
  description:index>=sourceTier?description:'独立录入属性',unlock_hint:index<5?'':'队伍所有玩家：'+names[mode]+' N5 通关后解锁 N6–N10'}));
 const setup={mode_selected:true,mode_id:mode,selector_player_id:0,can_confirm_difficulty:true,difficulty_data_ready:true,
  mode_options:modes,difficulty_options:difficulties,difficulty_options_by_mode:{[mode]:difficulties}};
 const ui=harness({startupState:ready({admission_complete:true,profiles_ready:true,setup}),hud:true,loadSharedUI:true});ui.advance(.11);
 const rows=ui.nodes.DifficultySelectionButtons.children;
 assert.equal(rows.length,10);
 assert.equal(rows[0].children[0].children[2].visible,false,'Recorded unlocked tiers remain uncluttered');
 const temporary=rows[sourceTier];
 assert.equal(temporary.enabled,true);
 assert.equal(temporary.children[0].children[2].visible,true);
 assert.equal(temporary.children[0].children[2].text,'临时配置 · 沿用 '+source,'Temporary balance is visible before selecting');
 assert.equal(temporary.children[0].children[1].style.horizontalAlign,'left','Tier code leaves space for its temporary source label');
 temporary.events.onmouseover();assert.equal(ui.dispatched.at(-1)[2],description);
 rows[5].events.onmouseover();
 assert(ui.dispatched.at(-1)[2].includes(difficulties[5].unlock_hint)&&ui.dispatched.at(-1)[2].includes(description),
  'Locked temporary tiers explain both their real progression gate and source configuration');
 rows[5].events.onactivate();assert(!ui.requests.some(request=>request.name==='ui_difficulty_select_request'));
 temporary.events.onactivate();
 const difficultyRequests=ui.requests.filter(request=>request.name==='ui_difficulty_select_request');
 assert.equal(difficultyRequests.length,1);
 assert.equal(difficultyRequests[0].payload.difficulty_id,'N'+(sourceTier+1),'The requested tier retains its own identity rather than its balance source');
}
console.log('RECORDED_MODE_SELECTION_PASS: ordered modes, authenticated gates, ten-tier lists, visible temporary sources, full hints and actual selected-tier requests');
