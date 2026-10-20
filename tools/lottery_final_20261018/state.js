'use strict';
window.previewState={page:'lottery',ready:false,kind:'lottery_final_production_component_browser_preview',gameVerified:false,runtimeValues:'Ticket balances, points, ownership, unlocks and results are explicit local samples; item names/icons/descriptions/pity rules come from repository CSV.'};
let lotterySequence=100;
// Panorama opacity-mask is CSS mask-image in this offline adapter. Use the
// production SVG bytes unchanged, so its left-edge blend is actually rendered.
const lotterySyncLayout=window.syncLayout;
window.syncLayout=()=>{lotterySyncLayout();function visit(node){const value=node.style.opacityMask;if(value){node.el.style.maskImage=window.LOTTERY_PREVIEW_MASK_URI&&String(value).includes('lottery_final_v1/scene_blend.svg')?'url("'+LOTTERY_PREVIEW_MASK_URI+'")':cssValue(value);node.el.style.maskSize='100% 100%';node.el.style.maskRepeat='no-repeat';}node.Children().forEach(visit);}visit(root);};
previewGeometryModels.push('Production opacityMask maps to CSS mask-image using the same authored SVG alpha; native Source 2 compositing remains separately unverified.');
function lotteryPity(id){return PREVIEW_FIXTURE.lottery.pity.filter(x=>x.pool_id===id).map(x=>({...x,threshold:Number(x.threshold),batch_size:Number(x.threshold),quality:x.target_quality,label:'十连保底 '+String(x.target_quality).toUpperCase()}));}
window.lotteryPreviewSnapshot=(id='map',tickets=20,scope='main')=>{
 const raw=PREVIEW_FIXTURE.lottery,pools=raw.pools.map(x=>({...x,id:x.pool_id,single_cost:Number(x.single_cost),ten_cost:Number(x.ten_cost),ui_order:Number(x.ui_order),unlocked:true,ticket_name:x.ticket_content_id==='special_lottery_ticket'?'金色抽奖券':'普通抽奖券',tickets,pity:lotteryPity(x.pool_id),unlock_progress:Number(x.unlock_draws)||0,unlock_required:Number(x.unlock_draws)||0})),selected=pools.find(x=>x.id===id);if(!selected)throw Error('Unknown real CSV pool '+id);
 const items=raw.members.filter(x=>x.pool_id===id).map(m=>raw.items.find(x=>x.item_id===m.item_id)).filter(Boolean).map(x=>({...x,id:x.item_id,name:x.display_name,duplicate_points:Number(x.duplicate_points),exchange_points:Number(x.exchange_points),exchange_enabled:Number(x.exchange_enabled),max_owned:Number(x.max_owned),owned:0,owned_count:0,at_max_owned:0}));
 // Match systems/lottery_http_settlement.lua's authoritative public ordering.
 const quality={n:1,r:2,sr:3,ssr:4,ur:5};items.sort((a,b)=>(quality[b.quality]||0)-(quality[a.quality]||0)||(a.id<b.id?-1:a.id>b.id?1:0));
 return {ok:1,sequence:++lotterySequence,snapshot_scope:scope,selected_pool_id:id,selected_pool:selected,pools,items,shop_points:825,starjoy_points:320,pity:selected.pity};
};
window.lotteryPreviewSend=(id='map',tickets=20,scope='main')=>{const snapshot=lotteryPreviewSnapshot(id,tickets,scope);const request=[...previewCalls].reverse().find(x=>x.name==='ui_lottery_snapshot_request'&&x.payload.pool_id===id&&x.payload.snapshot_scope===scope);if(request&&request.payload.snapshot_request_id)snapshot.snapshot_request_id=request.payload.snapshot_request_id;emit('ui_lottery_snapshot',snapshot);syncLayout();return snapshot;};
window.lotteryPreviewSelect=async(id,tickets=20)=>{const source=nodes['LotteryGW2Pool_'+id];if(!source||!source.events.onactivate)throw Error('Missing production pool button '+id);source.events.onactivate();lotteryPreviewSend(id,tickets);await new Promise(resolve=>setTimeout(resolve,280));syncLayout();return cfg.SurvivalPurpleLottery.Inspect();};
window.previewReady=(async()=>{
 await previewLoad();
 const lottery=nodes.LotteryWindow;if(!lottery||!cfg.SurvivalLottery||!cfg.SurvivalPurpleLottery)throw Error('Active production lottery unavailable');
 // Keep only the real lottery and its ancestry in this isolated HUD capture.
 function retain(node){for(const child of node.Children()){if(child===lottery)continue;let contains=false;for(let p=lottery;p;p=p.GetParent())if(p===child)contains=true;if(contains)retain(child);else child.visible=false;}}retain(nodes.PreviewContext_survival_hud);
 const initial=new URLSearchParams(location.search).get('pool')||'map',tickets=Number(new URLSearchParams(location.search).get('tickets')??20);
 cfg.SurvivalLottery.Open();if(initial!=='map')cfg.SurvivalLottery.SelectPool(initial);lotteryPreviewSend(initial,tickets);
 syncLayout();await new Promise(resolve=>setTimeout(resolve,280));syncLayout();await document.fonts.ready;await Promise.all([...document.images].map(image=>image.decode().catch(()=>false)));previewState.ready=true;return true;
})().catch(error=>{previewErrors.push({scope:'lottery final fixture',message:String(error),stack:error.stack});previewState.failure=String(error);return false;});
