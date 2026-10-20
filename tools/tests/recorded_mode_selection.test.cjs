'use strict';
const assert=require('node:assert/strict');
const {harness,ready}=require('../test_startup_loading_ui.js');
const names={pure:'纯净模式',standard:'常规模式',fishing:'摸鱼模式',rich:'丰饶模式',cold:'极寒模式',scourge:'天灾模式'};
const modes=Object.entries(names).map(([mode_id,display_name])=>({mode_id,display_name,unlocked:1}));
const options=count=>Array.from({length:count},(_,i)=>({difficulty_id:'N'+(i+1),display_name:'N'+(i+1),unlocked:1}));
for(const [mode,count] of [['cold',4],['scourge',2]]){
 const setup={mode_selected:false,mode_id:'',selector_player_id:0,mode_options:modes,
  difficulty_options:options(10),difficulty_options_by_mode:{standard:options(10),cold:options(4),scourge:options(2)}};
 const state=ready({admission_complete:true,profiles_ready:true,setup});
 const ui=harness({startupState:state,hud:true,loadSharedUI:true});ui.advance(.11);
 assert.equal(ui.nodes.MatchModeOptions.children.length,6,'The active HUD renders all six authoritative mode choices');
 assert.equal(ui.nodes.DifficultySelectionDialog.style.height,'414px','The popup grows to fit all six buttons');
 const button=ui.nodes.MatchModeOptions.children[Object.keys(names).indexOf(mode)];
 assert.equal(button.children[0].text,names[mode]);assert(button.enabled);
 button.events.onactivate();button.events.onactivate();
 const requests=ui.requests.filter(r=>r.name==='survival_loading_mode_select');
 assert.equal(requests.length,1);assert.equal(requests[0].payload.mode_id,mode);
 ui.emit('survival_loading_mode_result',{success:1,mode_id:mode,session_id:'match-123'});
 ui.setStartup(ready({admission_complete:true,profiles_ready:true,setup:{...setup,mode_selected:true,mode_id:mode,difficulty_options:options(count)}}));
 assert.equal(ui.nodes.MatchModeOptions.visible,false);
 assert.equal(ui.nodes.DifficultySelectionButtons.children.length,count,'Only configured difficulties are offered');
 assert(ui.nodes.DifficultySelectionHint.text.includes(names[mode]));
 assert(ui.nodes.DifficultySelectionHint.text.includes('N'+count));
 assert.equal(ui.requests.filter(r=>/draw|purchase|checkout|archive/.test(r.name)).length,0);
}
console.log('RECORDED_MODE_SELECTION_PASS: six choices, real cold/scourge requests, single confirmation, fitted popup and independent difficulty lists');
