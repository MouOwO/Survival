/* Actual collection controller, local sample snapshots and a minimal HUD fixture. */
'use strict';
const collectionParams=new URLSearchParams(location.search),collectionMode=collectionParams.get('state')||'normal',collectionStart=collectionParams.get('category')||'ex';
window.previewState={page:'collection',category:collectionStart,state:collectionMode,ready:false,kind:'collection_gw2_production_component_browser_preview',notGameCapture:true,fixtureNote:COLLECTION_GW2_FIXTURE.runtimeValues};
window.collectionPreviewPages=JSON.parse(JSON.stringify(COLLECTION_GW2_FIXTURE.pages));
let collectionSequence=100;
window.collectionPreviewSnapshot=category=>({ok:1,sequence:++collectionSequence,chunk:1,chunks:1,category_id:category,categories:COLLECTION_GW2_FIXTURE.categories,rows:collectionPreviewPages[category]||[],social:COLLECTION_GW2_FIXTURE.social[category],pending:0,upgrade_pending:0,currencies:{gold:2881,points:320,tickets:20}});
window.collectionPreviewSend=category=>{if(category==='wife')throw Error('The unconfigured wife tab must never receive a fabricated pool.');emit('survival_archive_snapshot',collectionPreviewSnapshot(category));syncLayout();};
window.collectionPreviewSelect=async category=>{nodes['CollectionGW2Tab_'+category].events.onactivate();if(category!=='wife')collectionPreviewSend(category);previewState.category=category;await new Promise(resolve=>setTimeout(resolve,160));syncLayout();return cfg.SurvivalCollection.Inspect();};
window.collectionPreviewSearch=value=>{nodes.CollectionGW2Search.el.value=value;nodes.CollectionGW2Search.el.dispatchEvent(new Event('input',{bubbles:true}));syncLayout();return cfg.SurvivalCollection.Inspect();};
function collectionNavFixture(){
 const owner=new Panel('Panel',root,'PreviewContext_collection_nav');owner.AddClass('PreviewContext');
 const hud=new Panel('Panel',owner,'HandoffHUD');hud.style.width='100%';hud.style.height='100%';hud.hittest=false;hud.hittestchildren=true;
 const top=new Panel('Panel',hud,'HandoffTop');top.style.width='630px';top.style.height='94px';top.style.position='8px 6px 0px';
 const archive=new Panel('Button',top,'HandoffNav_archive');archive.style.width='56px';archive.style.height='86px';archive.style.position='130px 6px 0px';archive.hittest=false;
 const effects=new Panel('Panel',top,'HandoffCombatEffects');effects.style.width='96px';effects.style.height='86px';effects.style.position='522px 6px 0px';effects.hittest=false;
 cfg.HandoffGeneration=1;
 const previous=currentContext;currentContext=owner;
 const rel='scripts/custom_game/collection_nav.js';try{window.eval(PREVIEW_SOURCES[rel]+'\n//# sourceURL='+rel);previewScriptResults.push({rel,ok:true,fixture:'minimal_HandoffTop'});}finally{currentContext=previous;}
 window.collectionNavFixtureInfo={kind:'minimal_HandoffTop_geometry_fixture',notFullHud:true,originalTopnavExecuted:false};
}
window.previewReady=(async()=>{
 await previewLoad();
 for(const id of ['ArchiveEntry','TreasureEntry','DailyEntry','PassEntry','EndlessStatus','VIPScrim','VIPWindow','SurvivalWorldTitles'])if(nodes[id])nodes[id].visible=false;
 for(const name of ['SurvivalArchive','SurvivalTreasure','SurvivalDaily','SurvivalVIP'])if(cfg[name]&&cfg[name].Close)cfg[name].Close();
 if(collectionMode==='empty')collectionPreviewPages[collectionStart]=[];
 if(collectionMode==='unknown')for(const rows of Object.values(collectionPreviewPages))for(const row of rows){delete row.count;row.count_known=0;}
 if(collectionMode==='long')for(const rows of Object.values(collectionPreviewPages)){rows[0].name+='·本地超长名称边界样例';rows[0].description=(rows[0].description+'\n').repeat(50);}
 collectionNavFixture();cfg.SurvivalCollection.Open(collectionStart);if(collectionStart!=='wife')collectionPreviewSend(collectionStart);
 cfg.SurvivalCollectionNav.Refresh();syncLayout();await new Promise(resolve=>setTimeout(resolve,260));syncLayout();
 await document.fonts.ready;await Promise.all([...document.images].map(image=>image.decode().catch(()=>false)));
 previewState.ready=true;return true;
})().catch(error=>{previewErrors.push({scope:'collection preview',message:String(error),stack:error.stack});previewState.failure=String(error);return false;});
