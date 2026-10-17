'use strict';
const assert=require('node:assert/strict'),fs=require('fs'),vm=require('vm');
const nodes=new Map(),subscriptions=new Map(),requests=[],timers=[],root={IsValid:()=>true};
let created=0,deleted=0,changes=0;
class Panel{
 constructor(type,parent,id){this.type=type;this.parent=parent;this.id=id;this.children=[];this.classes=new Set();this.style={};this.visible=true;this._text='';this.scrollTop=0;created++;if(parent?.children)parent.children.push(this);if(id)nodes.set(id,this);}
 IsValid(){return !this.deleted;}GetParent(){return this.parent;}SetParent(parent){this.parent=parent;parent.children.push(this);}
 AddClass(cls){for(const c of cls.split(' '))this.classes.add(c);}SetHasClass(cls,on){on?this.classes.add(cls):this.classes.delete(cls);changes++;}BHasClass(cls){return this.classes.has(cls);}
 DeleteAsync(){this.deleted=true;deleted++;for(const child of this.children)child.DeleteAsync();}get text(){return this._text;}set text(value){this._text=String(value);changes++;}
}
const cfg={},parent=new Panel('Panel',null,'parent'),mySteam='76561198000000042';
const context=vm.createContext({GameUI:{CustomUIConfig:()=>cfg},Game:{GetPlayerInfo:()=>({player_steamid:mySteam}),GetLocalPlayerID:()=>0},
 $:{GetContextPanel:()=>root,CreatePanel:(...a)=>new Panel(...a),Schedule:(delay,callback)=>{const timer={delay,callback};timers.push(timer);return timer;},CancelScheduled:timer=>{timer.cancelled=true;}},
 GameEvents:{Subscribe:(name,fn)=>{subscriptions.set(name,fn);return name;},Unsubscribe:name=>subscriptions.delete(name),SendCustomGameEventToServer:(name,payload)=>requests.push({name,payload})}});
function load(){vm.runInContext(fs.readFileSync('panorama/src/scripts/custom_game/endless_leaderboard.js','utf8'),context);return cfg.SurvivalEndlessLeaderboard;}
const api=load();api.Show(parent);assert.equal(requests.length,0,'Mount/Show never fetch data');api.Open();assert.equal(requests.length,1);assert.equal(requests[0].name,'survival_leaderboard_request');
function emit(payload){subscriptions.get('survival_leaderboard_result')(payload);}
function fixture(count=100,selfRank=42){return Array.from({length:count},(_,index)=>({rank:index+1,steam_id:index+1===selfRank?mySteam:'765611980'+String(1000+index).padStart(8,'0'),best_floor:1000-index,endless_score:100000-index*17}));}
function send(rows,revision='v1',extra={}){const request_id=requests.at(-1).payload.request_id;emit({request_id,phase:'begin',total:rows.length,revision,self_steam_id:mySteam,...extra});for(const row of rows)emit({request_id,phase:'row',revision,row});emit({request_id,phase:'end',revision,self_steam_id:mySteam,...extra});}
send(fixture());assert.equal(api.Inspect().total,100);assert.equal(api.Inspect().selfRank,42);assert.equal(api.Inspect().rowPanelCount,100);assert(nodes.get('EndlessLeaderboardRow_42').BHasClass('EndlessLeaderboardOwn'));assert.equal(nodes.get('EndlessLeaderboardFooter').text,'您的排名：第 42 名');
for(let rank=1;rank<=100;rank++)assert.equal(nodes.get('EndlessLeaderboardRow_'+rank).GetParent().id,rank<=3?'EndlessLeaderboardPinned':'EndlessLeaderboardScroll','Top 3 are outside the scrolling panel');
const first=nodes.get('EndlessLeaderboardRow_1'),own=nodes.get('EndlessLeaderboardRow_42'),scroll=nodes.get('EndlessLeaderboardScroll');scroll.scrollTop=800;
const stable=api.Inspect(),allocations=created,oldDeleted=deleted,oldChanges=changes;
api.Hide();api.Show(parent);api.Open();assert.equal(requests.length,2);emit({request_id:requests.at(-1).payload.request_id,phase:'unchanged',revision:'v1',self_steam_id:mySteam});
assert.equal(api.Inspect().renderCount,stable.renderCount);assert.equal(api.Inspect().patchCount,stable.patchCount);assert.equal(created,allocations);assert.equal(deleted,oldDeleted);assert.equal(changes,oldChanges);assert.equal(scroll.scrollTop,800);assert.equal(nodes.get('EndlessLeaderboardRow_1'),first);assert.equal(nodes.get('EndlessLeaderboardRow_42'),own);
api.Open();send(fixture(),'same-visible-different-revision');assert.equal(api.Inspect().renderCount,stable.renderCount,'New revision with identical visible rows does not repaint');assert.equal(scroll.scrollTop,800);
const changed=fixture();[changed[0].steam_id,changed[1].steam_id]=[changed[1].steam_id,changed[0].steam_id];changed[41].endless_score+=100;
api.Open();send(changed,'v2');assert.equal(nodes.get('EndlessLeaderboardRow_1'),first);assert.equal(nodes.get('EndlessLeaderboardRow_42'),own);assert.equal(first.GetParent().id,'EndlessLeaderboardPinned');assert.equal(created,allocations);assert.equal(deleted,oldDeleted);assert.equal(scroll.scrollTop,800);assert.equal(nodes.get('EndlessLeaderboardAvatar_1').steamid,changed[0].steam_id,'Pinned personnel can change when authoritative ranking changes');
api.Open();send(fixture(7,-1),'v3');assert.equal(api.Inspect().selfRank,0);assert.equal(nodes.get('EndlessLeaderboardFooter').text,'您未上榜');assert.equal(nodes.get('EndlessLeaderboardRow_8').visible,false);assert(!nodes.get('EndlessLeaderboardRow_42').visible);
api.Open();send([{rank:1,entry_id:'a32c62f0-a618-40e4-b553-b22a80a1383a',steam_id:'',display_name:'玩家资料待同步',best_floor:987,endless_score:345}], 'legacy');assert.equal(api.Inspect().total,1,'Legacy profiles without public identity retain their real position');assert.equal(nodes.get('EndlessLeaderboardName_1').visible,false);assert.equal(nodes.get('EndlessLeaderboardFallbackName_1').visible,true);assert.equal(nodes.get('EndlessLeaderboardAvatar_1').steamid,'0');
const lastGood=JSON.stringify(api.Inspect().rows);api.Open();const stale=requests.at(-1).payload.request_id;api.Open();emit({request_id:stale,phase:'begin',total:0,revision:'stale'});emit({request_id:stale,phase:'end',revision:'stale'});assert.equal(JSON.stringify(api.Inspect().rows),lastGood,'Stale request cannot replace the active request');
const latest=requests.at(-1).payload.request_id;emit({request_id:latest,phase:'begin',total:2,revision:'incomplete'});emit({request_id:latest,phase:'row',revision:'incomplete',row:fixture(1)[0]});emit({request_id:latest,phase:'end',revision:'incomplete'});assert.equal(JSON.stringify(api.Inspect().rows),lastGood,'Partial snapshots never replace complete cache');
api.Open();emit({request_id:requests.at(-1).payload.request_id,phase:'error',message:'raw private server error'});assert.equal(JSON.stringify(api.Inspect().rows),lastGood);assert(!nodes.get('EndlessLeaderboardFooter').text.includes('private'));
api.Open();send([],'empty');assert.equal(api.Inspect().total,0);assert.equal(nodes.get('EndlessLeaderboardEmpty').visible,true);assert.equal(nodes.get('EndlessLeaderboardFooter').text,'您未上榜');
api.Open();const timeout=timers.at(-1);timeout.callback();assert.equal(api.Inspect().pending,false);assert.equal(requests.at(-1).payload.known_revision,'empty');
const requestCount=requests.length;for(let i=0;i<1000;i++){api.Show(parent);api.Mount(parent);}assert.equal(requests.length,requestCount,'Resource/UI refresh cannot produce requests');
api.Dispose();assert.equal(subscriptions.size,0);const deadCreated=created;api.Open();api.Show(parent);assert.equal(created,deadCreated);assert.equal(requests.length,requestCount);
const maxSteam='76561202255233023';context.Game.GetPlayerInfo=()=>({player_steamid:maxSteam});
const maxApi=load();maxApi.Show(parent);maxApi.Open();send([{rank:1,steam_id:maxSteam,best_floor:777,endless_score:98765}],'steam32_max',{self_steam_id:maxSteam});
assert.equal(maxApi.Inspect().total,1,'Steam64 uint32 account maximum remains valid without numeric precision loss');assert.equal(maxApi.Inspect().selfRank,1);assert(nodes.get('EndlessLeaderboardRow_1').BHasClass('EndlessLeaderboardOwn'));assert.equal(nodes.get('EndlessLeaderboardName_1').steamid,maxSteam);maxApi.Dispose();
context.Game.GetPlayerInfo=()=>({player_steamid:''});const anonymousApi=load();anonymousApi.Show(parent);anonymousApi.Open();
send([{rank:1,entry_id:'a32c62f0-a618-40e4-b553-b22a80a1383a',steam_id:'',best_floor:123,endless_score:456}],'anonymous_without_local_identity',{self_steam_id:''});
assert.equal(anonymousApi.Inspect().selfRank,0,'An anonymous ranking row must not match a missing local identity');assert(!nodes.get('EndlessLeaderboardRow_1').BHasClass('EndlessLeaderboardOwn'));assert.equal(nodes.get('EndlessLeaderboardFooter').text,'您未上榜');anonymousApi.Dispose();assert.equal(subscriptions.size,0);
console.log('ENDLESS_LEADERBOARD_UI_PASS: 100 rows; fixed top 3; full Steam64 uint32 range and anonymous identity; exact unchanged zero mutations; same-content new revision; rank/cell reuse; no-list/legacy/empty; stale/incomplete/error/timeout; no polling; disposal.');
