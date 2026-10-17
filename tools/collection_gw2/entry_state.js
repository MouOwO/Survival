'use strict';
window.previewState={kind:'collection_entry_actual_topnav_browser_preview',notGameCapture:true,nativeFixture:true,outboundStubs:true,ready:false};
$.Warning=(...args)=>previewErrors.push({scope:'Panorama warning',message:args.map(String).join(' ')});
// Engine hierarchy stand-ins, never production panels or a live game connection.
function nativeFixture(){
 const make=(parent,id,type='Panel')=>new Panel(type,parent,id);
 const lower=make(root,'lower_hud'),center=make(lower,'center_with_stats'),block=make(center,'center_block'),portrait=make(block,'PortraitGroup');
 make(make(portrait,'PortraitContainer'),'portraitHUD');make(make(block,'AbilitiesAndStatBranch'),'abilities','DOTAAbilityList');make(block,'inventory','DOTAInventory');make(make(make(root,'minimap_container'),'minimap_block'),'minimap','DOTAMinimap');
 for(const id of ['DashboardButton','SettingsRebornButton','SharedUnitsButton','SharedContentButton','CombatLogButton'])make(root,id,'Button');
 Entities.IsValidEntity=entity=>entity===42;Entities.GetUnitName=entity=>entity===42?'npc_dota_hero_juggernaut':'';Entities.IsHero=entity=>entity===42;Entities.IsBuilding=()=>false;Entities.GetTeamNumber=()=>2;Entities.GetAbility=()=>-1;Entities.GetItemInSlot=()=>-1;
 cfg.SurvivalShopUnlocks={shop:true};
 netData.survival_ui_state={player_0:{sequence:100,resources:{gold:2881,wood:1200,population:7,max_population:10},wave:{current_wave:8,next_wave:9,timer:93,difficulty_selected:1,difficulty_id:'N3',alive:12,alive_limit:100}}};
 window.entryNativeFixture={panels:['lower_hud','center_with_stats','center_block','PortraitGroup','PortraitContainer','portraitHUD','AbilitiesAndStatBranch','abilities','inventory','minimap_container','minimap_block','minimap'],selectedEntity:42,snapshotSequence:100};
}
let entrySequence=200;
window.entrySnapshot=category=>({ok:1,sequence:++entrySequence,chunk:1,chunks:1,category_id:category,categories:COLLECTION_GW2_FIXTURE.categories,rows:COLLECTION_GW2_FIXTURE.pages[category]||[],social:COLLECTION_GW2_FIXTURE.social[category],pending:0,upgrade_pending:0,currencies:{gold:2881,points:320,tickets:20}});
window.entrySend=category=>{if(!COLLECTION_GW2_FIXTURE.social[category])throw Error('Unknown fixture pool: '+category);emit('survival_archive_snapshot',entrySnapshot(category));syncLayout();};
window.entryExecute=relative=>{const previous=currentContext;currentContext=nodes.PreviewContext_survival_hud;try{window.eval(PREVIEW_SOURCES[relative]+'\n//# sourceURL='+relative);}finally{currentContext=previous;}syncLayout();};
window.previewReady=(async()=>{
 nativeFixture();await previewLoad();
 for(const id of ['ArchiveEntry','TreasureEntry','DailyEntry','PassEntry','EndlessStatus','VIPScrim','VIPWindow','SurvivalWorldTitles'])if(nodes[id])nodes[id].visible=false;
 for(const name of ['SurvivalArchive','SurvivalTreasure','SurvivalDaily','SurvivalVIP'])if(cfg[name]?.Close)cfg[name].Close();
 for(let attempts=0;attempts<50;attempts++){syncLayout();if(previewMessages.some(message=>message.includes('[HANDOFF_PRESENTED]'))&&nodes.HandoffNav_collection)break;await new Promise(resolve=>setTimeout(resolve,100));}
 if(!previewMessages.some(message=>message.includes('[HANDOFF_PRESENTED]')))throw Error('Real topnav never passed native fixture stable reveal: '+JSON.stringify(previewErrors));
 if(!nodes.HandoffNav_collection)throw Error('Collection entry did not acquire real HUD neighbors');
 cfg.SurvivalCollectionNav.Refresh();syncLayout();await document.fonts.ready;await Promise.all([...document.images].map(image=>image.decode().catch(()=>false)));previewState.ready=true;return true;
})().catch(error=>{previewErrors.push({scope:'entry preview',message:String(error),stack:error.stack});previewState.failure=String(error);return false;});
