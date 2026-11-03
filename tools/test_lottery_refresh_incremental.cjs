"use strict";
// Real cache/controller functions in the existing native-panel fixture. These
// are bridge-call counts, not measurements of native rendering time or FPS.
const fs=require("node:fs"),vm=require("node:vm"),path=require("node:path");
let suite=fs.readFileSync("tools/test_lottery_ui.js","utf8").split("ui.Open();assert.equal")[0];
suite=suite.replace("vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/lottery_ui.js','utf8'),env);",String.raw`
Panel.prototype.Children=function(){return this.children;};
Panel.prototype.DeleteAsync=function(){this.deleted=true;if(this.parent)this.parent.children=this.parent.children.filter(c=>c!==this);};
Panel.prototype.MoveChildBefore=function(child,before){this.children.splice(this.children.indexOf(child),1);this.children.splice(this.children.indexOf(before),0,child);};
Panel.prototype.FindChildTraverse=function(id){return nodes[id]||null;};
const loading={session_id:'refresh-session',setup:{mode_id:'standard'}},netListeners=[];
env.Game={GetLocalPlayerInfo:()=>({player_steamid:'39734272'}),GetLocalPlayerID:()=>0,IsInToolsMode:()=>false};
env.CustomNetTables={GetTableValue:()=>loading,SubscribeNetTableListener:(name,fn)=>{netListeners.push(fn);return netListeners.length;},UnsubscribeNetTableListener:()=>{}};
['reference_windows','ui_snapshot_cache','lottery_catalog_seed','common/lottery_cache','lottery_scene_transition','lottery_handoff_bb9968eef7','remaining_5d5c1152eb','lottery_ui_remaining_5d5c1152eb'].forEach(function(file){vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/'+file+'.js','utf8'),env);});
`);
suite+=String.raw`
root.actuallayoutwidth=1920;root.actuallayoutheight=1080;root.actualuiscale_x=1;root.actualuiscale_y=1;
const calls={snapshot:0,catalogClone:0,write:0,walk:0,presentation:0};
const cache=config.SurvivalLotteryCache,memo=config.SurvivalLotteryCacheState;
const originalSnapshot=cache.Snapshot;cache.Snapshot=function(id){calls.snapshot++;return originalSnapshot(id);};
env.JSON={parse:JSON.parse,stringify(value,...rest){if(Object.values(memo.catalog).includes(value))calls.catalogClone++;return JSON.stringify(value,...rest);}};
for(const method of ['Children','FindChildTraverse']){const original=Panel.prototype[method];Panel.prototype[method]=function(...args){calls.walk++;return original.apply(this,args);};}
for(const method of ['AddClass','RemoveClass','SetHasClass','SetPanelEvent','SetImage','RemoveAndDeleteChildren','SetParent','MoveChildBefore']){
 const original=Panel.prototype[method];if(original)Panel.prototype[method]=function(...args){calls.write++;return original.apply(this,args);};
}
for(const key of ['text','visible','enabled','hittest','hittestchildren'])Object.defineProperty(Panel.prototype,key,{configurable:true,get(){return this['__metric_'+key];},set(value){calls.write++;this['__metric_'+key]=value;}});
for(const node of Object.values(nodes)){
 for(const key of ['text','visible','enabled','hittest','hittestchildren']){const value=node[key];delete node[key];node['__metric_'+key]=value;}
 node.style=new Proxy(node.style,{set(target,key,value){calls.write++;target[key]=value;return true;}});
}
config.SurvivalPurpleLottery={Version:'lottery_current_20261018',Owns(owner){return owner===root;},IsAlive(){return true;},IsReady(){return true;},Open(){},Close(){},Apply(){calls.presentation++;},Snapshot(){calls.presentation++;},Pools(){calls.presentation++;},Compact(){calls.presentation++;},Fit(){return true;}};
const ids=['map','cultivation','dragon_knight','summer'],serials={};
function dynamic(id,tickets=20){const base=memo.catalog[id];return {
 selected_pool_id:id,selected_pool:{id,revision:base.selected_pool.revision,tickets,unlocked:true,unlock_progress:100},
 pools:ids.map(id=>({id,tickets:20,unlocked:true})),items:base.items.map(item=>({id:item.id,owned_count:0,owned:false,at_max_owned:false})),
 shop_points:100,session_id:loading.session_id,account_id:'39734272',profile_mode:'standard',config_hash:memo.configHash,catalog_md5:memo.md5,
 snapshot_scope:'cache',cache_sequence:serials[id]=(serials[id]||0)+1
};}
function emit(id,tickets){events.ui_lottery_snapshot(dynamic(id,tickets));}
function reset(){for(const key of Object.keys(calls))calls[key]=0;}
function zero(label){assert.deepEqual(calls,{snapshot:0,catalogClone:0,write:0,walk:0,presentation:0},label);}
for(const id of ids)emit(id);
reset();for(let i=0;i<100;i++)for(const id of ids)emit(id);zero('400 hidden same-content packets never materialize a view or cross the panel bridge');
ui.Open();assert.equal(calls.snapshot,1,'opening reads exactly one latest selected view');assert.equal(calls.catalogClone,1,'one cold display clone for the actual open');assert(calls.write>0);assert(nodes.LotteryTicketValue.text.includes('20'));
reset();emit('summer',42);zero('a different pool is rejected before Snapshot and all native layout work');
reset();for(let i=0;i<100;i++)emit('map');cache.Refresh();zero('fresh delivery sequences with identical contents and an unchanged cache notification do no display work');
reset();emit('map',21);assert.equal(calls.snapshot,1);assert.equal(calls.catalogClone,1);assert(calls.write>0);assert(nodes.LotteryTicketValue.text.includes('21'));
reset();ui.Close();reset();emit('map',77);emit('summer',55);zero('real hidden balance changes update only the shared authority');
ui.Open();assert.equal(calls.snapshot,1);assert.equal(calls.catalogClone,1);assert(nodes.LotteryTicketValue.text.includes('77'),'reopen uses the newest hidden balance');
reset();const stale=dynamic('map',1);loading.session_id='replacement-session';netListeners.forEach(fn=>fn('survival_loading','state',loading));
assert.equal(cache.IsAuthoritative('map'),false);reset();events.ui_lottery_snapshot(stale);zero('old session packets cannot repaint the replacement session');
serials.map=0;emit('map',33);assert.equal(calls.snapshot,1);assert(nodes.LotteryTicketValue.text.includes('33'));assert(cache.IsAuthoritative('map'));
reset();ui.Close();reset();const requestCount=requests.length;
ui.Open();nodes.LotterySkipAnimation.checked=true;ui.SetSkipAnimation();ui.DrawSingle();const draw=requests.filter(row=>row.n==='ui_lottery_draw_request').at(-1).p;
ui.Close();reset();events.ui_lottery_result({ok:1,request_id:draw.request_id,pool_id:'map',count:1,results:results(1),snapshot:dynamic('map',32)});zero('a delayed hidden transaction retains data and history without painting cards');
ui.Open();assert(nodes.LotteryTicketValue.text.includes('32'));assert.equal(nodes.LotteryItemList.children.length,1,'the stored hidden result is rendered on reopening');
ui.CloseResult();reset();ui.DrawSingle();const unchanged=requests.filter(row=>row.n==='ui_lottery_draw_request').at(-1).p;
events.ui_lottery_result({ok:1,request_id:unchanged.request_id,pool_id:'map',count:1,results:results(1),snapshot:dynamic('map',32)});
assert.equal(nodes.LotteryItemList.children.length,1,'unchanged wallet data still builds a new acknowledged result exactly once');
ui.Dispose();reset();emit('map',99);cache.Refresh();zero('disposing removes the controller listener without stopping the shared cache');
const totalItems=ids.reduce((n,id)=>n+memo.catalog[id].items.length,0);
console.log('LOTTERY_REFRESH_INCREMENTAL_PASS '+JSON.stringify({catalogItems:totalItems,pools:ids.length,hiddenPackets:400,stableSelectedPackets:100,stableNativeWrites:0,stableCatalogClones:0,otherPoolCatalogClones:0,openCatalogClones:1,nativeFPSMeasured:false}));
`;
vm.runInNewContext(suite,{require:require("node:module").createRequire(path.resolve("tools/test_lottery_ui.js")),console},{filename:"lottery_refresh_incremental_behavior.cjs"});
