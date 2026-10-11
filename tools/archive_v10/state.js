/* Browser-only archive snapshots. Does not connect to accounts, saves or game. */
'use strict';
const params=new URLSearchParams(location.search),state=params.get('state')||'normal',startCategory=params.get('category')||'shadow';
window.previewState={page:'archive',category:startCategory,state,kind:'production_component_browser_preview',ready:false,fixtureNote:PREVIEW_FIXTURE.v10.runtimeValues};
window.previewFixturePages=JSON.parse(JSON.stringify(PREVIEW_FIXTURE.v10.pages));
let previewSequence=100;
window.previewSnapshot=(category,rows)=>({ok:1,sequence:++previewSequence,chunk:1,chunks:1,categories:PREVIEW_FIXTURE.v10.categories,rows:rows||previewFixturePages[category]||[],category_id:category,currencies:{gold:2881,points:320,tickets:20},online:{coins:30000,actual_seconds:10800,map_seconds:10800,level:2,max_level:100},buildings:{faith:30000,earned_today:2,daily_cap:50,per_clear:1},social:PREVIEW_FIXTURE.v10.social[category],starjoy:{points:500,level:3},fishing:{known:1},pending:0,upgrade_pending:0,has_pass:0});
function fixtures(){
 const rows=previewFixturePages.shadow;
 if(state==='edges'){
  rows[0].count=0;rows[0].count_known=1;rows[0].unlocked=1;
  delete rows[1].count;rows[1].count_known=0;
  rows[2].target=null;rows[2].max_owned=null;rows[2].count=12;
  rows[3].count=rows[3].target;rows[3].count_known=1;
  rows[4].count=rows[4].target+10;rows[4].count_known=1;
  rows[5].count='—';rows[5].count_known=0;
  rows[6].name='用于完整名称 Tooltip 的非常长正式物品名称·本地边界试验';
  rows[6].description='长 Tooltip 边界测试，正文采用正式效果重复，仅用于本地验收。\n'+(rows[6].description+'\n').repeat(40);
 }
 if(state==='extra')for(let i=0;i<50;i++)rows.push({...rows[i%23],id:'local_edge_extra_'+i,name:'本地容量试验 '+(i+24),count:1});
 if(state==='empty')previewFixturePages[startCategory]=[];
 if(state==='unknown')for(const item of rows){delete item.count;item.count_known=0;}
}
window.previewSelect=async category=>{
 cfg.SurvivalArchive.SelectCategory(category);
 emit('survival_archive_snapshot',previewSnapshot(category));syncLayout();
 await new Promise(resolve=>setTimeout(resolve,140));syncLayout();
 previewState.category=category;
 return cfg.SurvivalArchiveV10&&cfg.SurvivalArchiveV10.Inspect?cfg.SurvivalArchiveV10.Inspect():null;
};
window.previewReady=(async()=>{
 await previewLoad();fixtures();
 for(const id of ['ArchiveEntry','TreasureEntry','DailyEntry','PassEntry','EndlessStatus','VIPScrim','VIPWindow','SurvivalWorldTitles'])if(nodes[id])nodes[id].visible=false;
 for(const name of ['SurvivalArchive','SurvivalTreasure','SurvivalDaily','SurvivalVIP'])if(cfg[name]&&cfg[name].Close)cfg[name].Close();
 cfg.SurvivalCommerceWallet={GetCatalog:()=>({balances:{u_coin:20,shop_points:320,shop_gold:2881}}),Refresh:()=>{}};
 emit('survival_archive_snapshot',previewSnapshot('clear'));
 cfg.SurvivalArchive.Toggle();
 await previewSelect(startCategory);
 syncLayout();await new Promise(resolve=>setTimeout(resolve,250));syncLayout();
 await document.fonts.ready;
 await Promise.all([...document.images].filter(i=>!i.hidden).map(i=>i.decode().catch(()=>false)));
 previewState.ready=true;return true;
})().catch(error=>{previewErrors.push({scope:'archive V10 preview',message:String(error),stack:error.stack});previewState.failure=String(error);return false;});
