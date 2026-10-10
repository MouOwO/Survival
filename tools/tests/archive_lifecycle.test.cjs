const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const path=require('node:path'),project=path.resolve(__dirname,'../..');
const source=fs.readFileSync(path.join(project,'panorama/src/scripts/custom_game/archive_180de7e38b_titles_compact_v6.js'),'utf8');
const requests=[],timers=[],listeners=[],unsubscribed=[],warmFactories=[];
let root,nodes,modalDisposals=0,purpleDisposals=0,time=0;
class Panel{
 constructor(type,parent,id=''){this.paneltype=type;this.id=id;this.parent=parent;this.children=[];this.classes=new Set();this.style={};this.events={};this.visible=true;this.enabled=true;if(parent){parent.check();parent.children.push(this);}if(id)nodes[id]=this;}
 check(){assert(!this.deleted,'native method accessed a deleted panel: '+this.id);}
 IsValid(){return !this.deleted;}AddClass(c){this.check();this.classes.add(c);}RemoveClass(c){this.check();this.classes.delete(c);}SetHasClass(c,on){on?this.AddClass(c):this.RemoveClass(c);}BHasClass(c){this.check();return this.classes.has(c);}
 Children(){this.check();return this.children;}FindChildTraverse(id){this.check();if(this.id===id)return this;for(const child of this.children){if(child.IsValid()){const found=child.FindChildTraverse(id);if(found)return found;}}return null;}
 RemoveAndDeleteChildren(){this.check();for(const child of this.children.slice())child.DeleteAsync();}DeleteAsync(){for(const child of this.children.slice())child.DeleteAsync();this.deleted=true;if(this.parent)this.parent.children=this.parent.children.filter(p=>p!==this);}
 SetPanelEvent(name,fn){this.check();this.events[name]=fn;}SetImage(){}ScrollToTop(){this.check();}
}
function fixture(keepRoot=false){nodes={};if(!keepRoot)root=new Panel('Panel',null,'ArchiveRoot');for(const id of ['ArchiveWindow','ArchiveScrim','ArchiveHeader','ArchiveTitle','ArchiveClose','ArchiveContent','ArchiveTabs','ArchiveGrid','ArchiveFilters','ArchiveFilter_all','ArchiveFilter_unlocked','ArchiveFilter_locked','ArchiveFilterAllLabel','ArchiveTooltip','ArchiveDraw','ArchiveTickets','ArchiveDrawResult','ArchiveDrawBar','ArchiveFaith','ArchiveCurrencySource','ArchiveEmpty','ArchivePageTitle','ArchiveSummary','ArchiveContext','ArchiveHint','ArchiveStatus','EndlessStatus'])new Panel('Panel',root,id);}
fixture();
const cfg={ArchiveHandoffAssets:{'icon_check_light.png':'check','icon_lock_light.png':'lock'},SurvivalArchiveColors:{number:'#ffd800'},SurvivalUI:{ModalShell:{Adopt(){return {Open(){},Close(){},Dispose(){modalDisposals++;}};}},NavToggle:{Adopt(){}},ActionButton:{Adopt(){}},Tooltip:{Adopt(){}}},SurvivalPurpleShell:{Adopt(){return {Dispose(){purpleDisposals++;}};}},ArchiveHandoff:{Init(){},Hide(){},HideCardText(){},Observe(data){this.snapshot=data;},Unlocked(item){return Number(item.completed)===1;},Icon(){},Card(){},NavIcon(){},ApplyPalette(){},Show(){}},SurvivalSnapshotCache:{Warm(){}}};
vm.runInNewContext(fs.readFileSync(path.join(project,'panorama/src/scripts/custom_game/ui_snapshot_cache.js'),'utf8'),{GameUI:{CustomUIConfig:()=>cfg}});cfg.SurvivalSnapshotCache.Warm=(key,fn)=>warmFactories.push(fn);cfg.ArchiveHandoff.Icon=host=>host.check();
const $=id=>nodes[id.slice(1)];$.GetContextPanel=()=>root;$.CreatePanel=(type,parent,id)=>new Panel(type,parent,id);$.RegisterEventHandler=()=>{};$.Schedule=(delay,fn)=>{const timer={at:time+delay,fn,cancelled:false};timers.push(timer);return timer;};$.CancelScheduled=id=>{id.cancelled=true;};
const context={GameUI:{CustomUIConfig:()=>cfg},Game:{GetLocalPlayerID:()=>0},$,GameEvents:{Subscribe(name,fn){listeners.push({name,fn});return listeners.length;},Unsubscribe:id=>unsubscribed.push(id),SendCustomGameEventToServer(name,payload){requests.push({name,payload});}}};
function load(){vm.runInNewContext(source,context);return cfg.SurvivalArchive;}
function advance(seconds){const target=time+seconds;for(;;){const timer=timers.filter(t=>!t.ran&&!t.cancelled&&t.at<=target).sort((a,b)=>a.at-b.at)[0];if(!timer)break;time=timer.at;timer.ran=true;timer.fn();}time=target;}
function snapshot(sequence,rows,extra={}){return {ok:1,category_id:'clear',sequence,chunk:1,chunks:1,categories:[{id:'clear',name:'通关存档'},{id:'shadow',name:'虚空之影'}],rows,...extra};}
function cards(){return nodes.ArchiveGrid.children.filter(p=>p.BHasClass('ArchiveCard')&&p.visible);}
const api=load();advance(.2);api.Open();const handler=listeners.find(l=>l.name==='survival_archive_snapshot').fn;
const before=requests.length;
const realCategories=['clear','shadow','points','starjoy_points','gift','fragment','pet','endless','friend','ex','beast','building','boss','fishing','map_level','work','titles'];
for(let i=0;i<realCategories.length;i++)handler(snapshot(100+i,[{path:['revision'],value:3435}],{category_id:realCategories[i],delta:1,base_sequence:1}));
advance(.25);
assert.equal(requests.length-before,1,'17 missing delta baselines coalesce into one full archive request');
advance(.75);assert.equal(requests.length-before,2,'a silently throttled request is retried while the open view lacks a baseline');
handler(snapshot(200,Array.from({length:44},(_,i)=>({id:'clear_'+i,name:'记录'+i,count:0,target:10,completed:0}))));
assert.equal(cards().length,44,'the authoritative full response restores all actual records');assert.equal(nodes.ArchiveTabs.children.length,2);
realCategories.slice(1).forEach((id,i)=>handler(snapshot(210+i,[],{category_id:id})));
const settled=requests.length;advance(3);assert.equal(requests.length,settled,'receiving the real full category baselines ends retries');
handler(snapshot(201,[{path:['rows','1','count'],value:3}],{delta:1,base_sequence:200}));assert.equal(cfg.ArchiveHandoff.snapshot.rows[0].count,3);
const oldApi=api,oldHandler=handler,oldCard=cards()[0];load();assert.equal(oldApi.IsOpen(),false);assert.equal(modalDisposals,1);assert.equal(purpleDisposals,1);assert.equal(unsubscribed.length,3);
cfg.SurvivalArchive.Open();const latest=listeners.filter(l=>l.name==='survival_archive_snapshot').at(-1).fn;latest(snapshot(300,[{id:'new',name:'实际新记录',count:1,target:10,completed:0}]));
const newCards=cards().length,requestCount=requests.length;oldHandler(snapshot(999,[]));oldApi.Refresh(true);oldCard.events.onmouseover();advance(.25);
assert.equal(cards().length,newCards,'a retired subscriber cannot clear replacement categories/cards');assert.equal(cfg.ArchiveHandoff.snapshot.rows[0].id,'new');assert.equal(requests.length,requestCount,'retired subscriptions, APIs and timers cannot emit requests');
const activeApi=cfg.SurvivalArchive,pending=timers.filter(t=>!t.ran).slice(),deletedWarmHost=nodes.ArchiveGrid;root.DeleteAsync();assert.doesNotThrow(()=>{latest(snapshot(1000,[]));pending.forEach(t=>t.fn());warmFactories.forEach(fn=>fn(deletedWarmHost));activeApi.Close();activeApi.Dispose();activeApi.Dispose();});assert.equal(activeApi.IsOpen(),false);assert.equal(unsubscribed.length,6);
fixture();load();cfg.SurvivalArchive.Open();listeners.filter(l=>l.name==='survival_archive_snapshot').at(-1).fn(snapshot(1100,[{id:'replacement',name:'真实替换记录',count:0,target:1}]));assert.equal(cards().length,1);
const childReloadApi=cfg.SurvivalArchive,childReloadHandler=listeners.filter(l=>l.name==='survival_archive_snapshot').at(-1).fn;root.RemoveAndDeleteChildren();fixture(true);assert(root.IsValid());const beforeChildReload=requests.length;childReloadHandler(snapshot(1200,[]));childReloadApi.Refresh(true);assert.equal(requests.length,beforeChildReload,'a surviving root with a deleted marker cannot lend authority to its replacement children');load();cfg.SurvivalArchive.Open();listeners.filter(l=>l.name==='survival_archive_snapshot').at(-1).fn(snapshot(1300,[{id:'children_replaced',name:'重载后的真实记录',count:0,target:1}]));assert.equal(cards().length,1);assert.equal(unsubscribed.length,9);
console.log('ARCHIVE_LIFECYCLE_PASS: 17-way delta baseline miss coalesced, silent-throttle retry, real 44-row restore, incremental changes, retired event/API/card/timer/warm isolation, deleted-root and surviving-root child reload');
