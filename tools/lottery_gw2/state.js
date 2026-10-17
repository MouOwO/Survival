/* Isolated lottery snapshots; every outbound event remains an in-memory record. */
'use strict';
const lotteryParams=new URLSearchParams(location.search),lotteryMode=lotteryParams.get('state')||window.LOTTERY_GW2_DEFAULT_MODE||'normal',lotteryStart=lotteryParams.get('pool')||'map';
window.previewState={page:'lottery',state:lotteryMode,pool:lotteryStart,ready:false,notGameCapture:true,fixtureNote:LOTTERY_GW2_FIXTURE.runtimeValues};
let lotterySequence=100,lotteryRequestCursor=0;
window.lotteryPreviewSnapshot=(poolId,scope='main',requestId)=>{
 const raw=LOTTERY_GW2_FIXTURE;
 const pools=raw.pools.map(row=>({...row,id:row.pool_id,single_cost:Number(row.single_cost),ten_cost:Number(row.ten_cost),ui_order:Number(row.ui_order),unlocked:!(lotteryMode==='locked'&&row.pool_id==='cultivation'),ticket_name:row.ticket_content_id==='special_lottery_ticket'?'金色抽奖券':'抽奖券',tickets:lotteryMode==='insufficient'?0:20,unlock_progress:lotteryMode==='locked'?99:100,unlock_required:Number(row.unlock_draws)||0}));
 const selected=pools.find(row=>row.id===poolId);if(!selected)throw Error('Unknown formal pool '+poolId);
 if(lotteryMode==='zero'){selected.single_cost=0;selected.ten_cost=0;selected.tickets=0;}
 const items=raw.members.filter(member=>member.pool_id===poolId).map(member=>raw.items.find(row=>row.item_id===member.item_id)).filter(Boolean).map((row,index)=>({...row,id:row.item_id,name:row.display_name,duplicate_points:Number(row.duplicate_points),exchange_points:Number(row.exchange_points),exchange_enabled:Number(row.exchange_enabled),max_owned:Number(row.max_owned),owned:index%4===0?1:0,owned_count:index%4===0?Math.min(1,Number(row.max_owned)||1):0,at_max_owned:index%4===0?1:0}));
 if(lotteryMode==='unknown')for(const row of items)for(const key of ['owned_count','owned','max_owned','duration_text','duplicate_points'])delete row[key];
 if(lotteryMode==='long'&&items[0]){items[0].name+=' · 本地超长名称边界样例';items[0].description=(items[0].description+'\n').repeat(40);}
 selected.pity=raw.pity.filter(row=>row.pool_id===poolId).map(row=>({...row,threshold:Number(row.threshold),quality:row.target_quality,batch_size:Number(row.threshold),label:'十连保底 '+String(row.target_quality).toUpperCase()}));
 selected.update_notice=structuredClone(raw.updates.find(row=>row.pool_id===poolId)||{});
 return {snapshot_scope:scope,snapshot_request_id:requestId,cache_sequence:++lotterySequence,selected_pool_id:poolId,selected_pool:selected,pools,items:lotteryMode==='empty'?[]:items,starjoy_points:320,pity:selected.pity};
};
window.lotteryPreviewSend=(poolId,scope='main',requestId)=>{emit('ui_lottery_snapshot',lotteryPreviewSnapshot(poolId,scope,requestId));syncLayout();};
window.lotteryPreviewFlushDetails=()=>{
 const pending=previewCalls.slice(lotteryRequestCursor);lotteryRequestCursor=previewCalls.length;
 for(const call of pending)if(call.name==='ui_lottery_snapshot_request'&&call.payload.snapshot_scope==='details')lotteryPreviewSend(call.payload.pool_id,'details',call.payload.snapshot_request_id);
};
window.lotteryPreviewSelect=async poolId=>{
 const button=nodes['LotteryGW2Pool_'+poolId];if(!button?.events.onactivate)throw Error('Missing actual pool control '+poolId);button.events.onactivate();
 if(cfg.SurvivalPurpleLottery.Inspect().mode==='details')lotteryPreviewFlushDetails();else if(cfg.SurvivalPurpleLottery.Inspect().mode!=='history')lotteryPreviewSend(poolId);
 previewState.pool=poolId;await new Promise(resolve=>setTimeout(resolve,240));syncLayout();return cfg.SurvivalPurpleLottery.Inspect();
};
window.lotteryPreviewFeature=async name=>{cfg.SurvivalLottery.Feature(name);lotteryPreviewFlushDetails();syncLayout();await new Promise(resolve=>setTimeout(resolve,120));syncLayout();return cfg.SurvivalPurpleLottery.Inspect();};
window.lotteryPreviewResult=(count=10,poolId=previewState.pool)=>{
 const rows=lotteryPreviewSnapshot(poolId).items,results=rows.slice(0,count).map(row=>({...row,count:1,quantity:1}));
 nodes.LotterySkipAnimation.checked=true;cfg.SurvivalLottery.SetSkipAnimation();
 const packet={ok:1,pool_id:poolId,count:results.length,results,request_id:'ISOLATED_LOTTERY_RESULT_'+(++lotterySequence),snapshot:lotteryPreviewSnapshot(poolId)};
 emit('ui_lottery_result',packet);cfg.SurvivalLottery.SkipReveal();syncLayout();return packet;
};
window.previewReady=(async()=>{
 await previewLoad();
 // Render only the authentic lottery branch of the HUD XML. Unrelated HUD
 // panels stay hidden and their scripts are excluded by the build allowlist.
 for(let branch=nodes.LotteryWindow;branch&&branch!==root;branch=branch.GetParent())for(const sibling of branch.GetParent()?.Children()||[])if(sibling!==branch)sibling.visible=false;
 cfg.SurvivalLottery.Open();if(lotteryStart!=='map')cfg.SurvivalLottery.SelectPool(lotteryStart);lotteryPreviewSend(lotteryStart);
 if(['details','unknown','long','empty'].includes(lotteryMode))await lotteryPreviewFeature('details');
 if(lotteryMode==='notice')await lotteryPreviewFeature('announcement');
 if(lotteryMode==='history'){lotteryPreviewResult(3,lotteryStart);cfg.SurvivalLottery.CloseResult();await lotteryPreviewFeature('history');}
 if(lotteryMode==='result')lotteryPreviewResult(10,lotteryStart);
 syncLayout();await new Promise(resolve=>setTimeout(resolve,260));syncLayout();await document.fonts.ready;await Promise.all([...document.images].map(image=>image.decode().catch(()=>false)));previewState.ready=true;return true;
})().catch(error=>{previewErrors.push({scope:'lottery preview',message:String(error),stack:error.stack});previewState.failure=String(error);return false;});
