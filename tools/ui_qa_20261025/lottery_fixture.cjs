'use strict';
// Executed only inside the network-blocked Chrome fixture. The real cache's
// catalogue transfer validates these explicit layout samples before rendering.
function seedLotteryLayout(kind){
 const cache=cfg.SurvivalLotteryCache,memo=cfg.SurvivalLotteryCacheState;
 if(!cache||!memo||!memo.catalog)throw Error('Real lottery cache unavailable');
 const data={schema:1,snapshots:Object.values(memo.catalog).map(x=>structuredClone(x))};
 for(const page of data.snapshots){
  if(kind==='empty')page.items=[];
  else if(kind==='long')for(const item of page.items)item.description=Array.from({length:50},(_,i)=>'第'+(i+1)+'行：同一实际奖励的明确长正文滚动样例。').join('\n');
  else throw Error('Unsupported explicit layout fixture');
 }
 const raw=JSON.stringify(data),md5=cache.MD5(raw),hash='f'.repeat(64),chunks=Math.ceil(raw.length/3400),sequence=Number(memo.catalogSequence||0)+1,owner=memo.identity||{};
 for(let chunk=1;chunk<=chunks;chunk++)emit('ui_lottery_catalog',{ok:true,account_id:owner.account||'',session_id:owner.session||'',profile_mode:owner.mode||'',catalog_sequence:sequence,transfer_id:'LOCAL_UIQA_LAYOUT_'+sequence,catalog_md5:md5,config_hash:hash,chunk,chunks,catalog_chunk:raw.slice((chunk-1)*3400,chunk*3400)});
 if(cache.Catalog().md5!==md5)throw Error('Real lottery cache rejected layout fixture');
 cfg.SurvivalLottery.Close();cfg.SurvivalLottery.Open();cfg.SurvivalLottery.Feature('details');syncLayout();
 return {kind,transport:'real_local_catalogue_event_with_verified_MD5',md5,chunks,items:data.snapshots.reduce((n,p)=>n+p.items.length,0),descriptionOnly:kind==='long',noTransactions:true};
}
module.exports={seedLotteryLayout};
