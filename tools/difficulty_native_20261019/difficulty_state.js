'use strict';
// Explicit local startup fixture. Outbound events remain the adapter's in-memory log.
const params=new URLSearchParams(location.search),cap=Number(params.get('cap')||6),mode=params.get('mode')||'standard';
const options=limit=>Array.from({length:10},(_,i)=>({difficulty_id:'N'+(i+1),unlocked:i<limit?1:0,unlock_hint:i<limit?'':'队伍所有玩家通关 N'+i+' 后解锁'}));
window.difficultyFixture={session_id:'offline_native_difficulty',phase:'admitted',admission_complete:true,all_ready:true,profiles_ready:false,
 setup:{mode_selected:true,mode_id:mode,selector_player_id:0,can_confirm_difficulty:true,difficulty_data_ready:true,difficulty_selected:false,difficulty_id:'',max_difficulty_id:'N'+cap,difficulty_limit_player_ids:[1,2],difficulty_options:options(cap),difficulty_options_by_mode:{standard:options(cap),pure:options(cap),rich:options(Math.max(1,cap-1))}}};
window.previewState={kind:'actual_difficulty_production_component_preview',gameVerified:false,ready:false,fixture:'Team progress, player IDs, mode and pending profile are explicit local samples. No game, account or service connection.'};
window.previewReady=(async()=>{
 emitNet('survival_loading','state',difficultyFixture);
 await previewLoad();
 const keep=nodes.DifficultySelectionOverlay;
 function retain(n){for(const child of n.Children()){if(child===keep)continue;let contains=false;for(let p=keep;p;p=p.GetParent())if(p===child)contains=true;if(contains)retain(child);else child.visible=false;}}
 retain(nodes.PreviewContext_survival_hud);
 syncLayout();await new Promise(resolve=>setTimeout(resolve,160));syncLayout();
 const rows=nodes.DifficultySelectionButtons.Children().filter(n=>n.BHasClass('DifficultyOptionButton'));
 // A genuine click enters the production pending state without a server response.
 // This shows the actual selected styling and busy guard for an unlocked N4 row.
 const selected=rows[Math.min(3,cap-1)];if(selected)selected.events.onactivate();
 syncLayout();await document.fonts.ready;await Promise.all([...document.images].map(i=>i.decode().catch(()=>false)));
 previewState.ready=true;return true;
})().catch(error=>{previewErrors.push({scope:'difficulty fixture',message:String(error),stack:error.stack});return false;});
