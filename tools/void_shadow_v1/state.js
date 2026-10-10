/* Browser-only archive snapshot. Nothing here connects to a game, account, or server. */
'use strict';
const params=new URLSearchParams(location.search),state=params.get('state')||'normal';
window.previewState={page:'archive',category:'shadow',state,kind:'production_component_browser_preview',ready:false,fixtureNote:'Names, descriptions and actual holding limits come from archive_shadow_items.csv. Counts are explicit local samples from package/data_preview.json or named edge cases; no real archive is read or written.'};
function shadowFixture(){
 const sample=PREVIEW_FIXTURE.packagePreview||[];
 const rows=PREVIEW_FIXTURE.shadowRows.map((row,i)=>{
  const entry=sample[i]||{},count=entry.current;
  return {id:row.item_id,name:row.display_name,description:row.description,target:Number(row.max_owned),max_owned:Number(row.max_owned),quality:row.quality,icon_style:row.icon_style,count:count===null?undefined:count,count_known:count===null||count===undefined?0:1,unlocked:count>0?1:0};
 });
 if(state==='edges'){
  rows[0].count=0;rows[0].count_known=1;rows[0].unlocked=1;
  rows[1].count=undefined;rows[1].count_known=0;rows[1].unlocked=0;
  rows[2].target=null;rows[2].max_owned=null;rows[2].count=12;
  rows[3].count=123456789;rows[3].target=1234567890;rows[3].max_owned=1234567890;
  rows[4].count=0;rows[4].count_known=1;rows[4].unlocked=1;
  rows[5].count=null;rows[5].count_known=1;rows[5].unlocked=0;
  rows[6].name='用于完整名称 Tooltip 的非常长物品名称·虚空之影试验';
  rows[7].count='—';rows[7].count_known=1;rows[7].unlocked=0;
 }
 if(state==='extra')rows.push({...rows[0],id:'local_preview_shadow_extra_24',name:'显式本地第24项',count:1,count_known:1,unlocked:1});
 if(state==='empty')return [];
 if(state==='sparse')return rows.slice(0,1);
 return rows;
}
function closePreviewWindows(){
 for(const id of ['ArchiveEntry','TreasureEntry','DailyEntry','PassEntry','EndlessStatus','VIPScrim','VIPWindow','SurvivalWorldTitles'])if(nodes[id])nodes[id].visible=false;
 for(const name of ['SurvivalArchive','SurvivalTreasure','SurvivalDaily','SurvivalVIP'])if(cfg[name]&&cfg[name].Close)cfg[name].Close();
}
function archiveSnapshot(){
 const categories=PREVIEW_FIXTURE.archiveCats,rows=shadowFixture();
 window.previewFixtureRows=rows;
 const header={ok:1,sequence:100,chunk:1,chunks:1,categories,rows:[],category_id:'clear',currencies:{gold:2881,points:320,tickets:20},online:{coins:3000,map_seconds:7200,level:2,max_level:100},pending:0};
 emit('survival_archive_snapshot',header);
 cfg.SurvivalArchive.Toggle();
 cfg.SurvivalArchive.SelectCategory('shadow');
 if(!['loading','chunked'].includes(state))emit('survival_archive_snapshot',{...header,sequence:101,category_id:'shadow',rows});
 const balances={u_coin:20,shop_points:320,shop_gold:2881};
 cfg.SurvivalCommerceWallet={GetCatalog:()=>({balances}),Refresh:()=>{}};
 if(cfg.SurvivalPurpleShell)cfg.SurvivalPurpleShell.Refresh();
 emit('survival_commerce_result',{ok:true,action:'catalog',part:'end',balances,request_id:'LOCAL_BROWSER_ONLY'});
 window.previewState.rowsSource=rows.map(row=>({id:row.id,name:row.name,count:row.count===undefined?null:row.count,countKnown:row.count_known,cap:row.target===undefined?null:row.target}));
}
window.previewReady=(async()=>{
 await previewLoad();closePreviewWindows();archiveSnapshot();syncLayout();
 await new Promise(resolve=>setTimeout(resolve,300));syncLayout();
 await document.fonts.ready;
 await Promise.all([...document.images].filter(i=>!i.hidden).map(i=>i.decode().catch(()=>false)));
 window.previewState.ready=true;return true;
})().catch(error=>{previewErrors.push({scope:'void shadow preview',message:String(error),stack:error.stack});window.previewState.failure=String(error);return false;});
