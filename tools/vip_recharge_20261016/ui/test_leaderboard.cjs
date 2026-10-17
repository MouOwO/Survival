'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const nodes=new Map(),subscriptions=new Map(),requests=[],timers=[],cfg={},root={IsValid:()=>true};let changes=0,created=0;
class Panel{
 constructor(type,parent,id){this.type=type;this.parent=parent;this.id=id;this.children=[];this.style={};this.classes=new Set();this.visible=true;created++;if(parent?.children)parent.children.push(this);if(id)nodes.set(id,this);}
 IsValid(){return true;}GetParent(){return this.parent;}SetParent(parent){this.parent=parent;parent.children.push(this);}AddClass(cls){cls.split(' ').forEach(x=>this.classes.add(x));}SetHasClass(cls,on){on?this.classes.add(cls):this.classes.delete(cls);changes++;}BHasClass(cls){return this.classes.has(cls);}SetImage(uri){this.image=uri;changes++;}SetScaling(){}get text(){return this._text||'';}set text(v){this._text=String(v);changes++;}DeleteAsync(){}
}
const player='76561198000000042',context=vm.createContext({GameUI:{CustomUIConfig:()=>cfg},Game:{GetPlayerInfo:()=>({player_steamid:player}),GetLocalPlayerID:()=>0},$:{GetContextPanel:()=>root,CreatePanel:(...a)=>new Panel(...a),Schedule:(delay,callback)=>{timers.push(callback);return timers.length;},CancelScheduled(){}},GameEvents:{Subscribe:(n,fn)=>{subscriptions.set(n,fn);return n;},SendCustomGameEventToServer:(n,p)=>requests.push(p)}});
for(const f of ['common/vip_badges.js','endless_leaderboard.js'])vm.runInContext(fs.readFileSync('panorama/src/scripts/custom_game/'+f,'utf8'),context);
const api=cfg.SurvivalEndlessLeaderboard;api.Show(new Panel('Panel',null,'parent'));
function emit(data){subscriptions.get('survival_leaderboard_result')({request_id:requests.at(-1).request_id,...data});}
function send(vip,medal,revision){api.Open();emit({phase:'begin',total:1,revision});const row={rank:1,steam_id:player,best_floor:300,endless_score:1000};if(vip!==undefined)row.vip_level=vip;if(medal!==undefined)row.vip_medal_level=medal;emit({phase:'row',revision,row});emit({phase:'end',revision});}
send(8,3,'v1');assert.equal(api.Inspect().total,1);const level=nodes.get('EndlessLeaderboardVIP_1'),medal=nodes.get('EndlessLeaderboardMedal_1');assert.equal(level.__survivalVIPBadge.number.text,'8');assert.equal(medal.text,'勋 3');assert(level.visible&&medal.visible);assert(nodes.get('EndlessLeaderboardRow_1').BHasClass('EndlessLeaderboardOwn'));
const count=created,previous=api.Inspect(),writes=changes;api.Open();emit({phase:'unchanged',revision:'v1'});assert.equal(created,count);assert.equal(changes,writes);assert.equal(api.Inspect().renderCount,previous.renderCount);assert.equal(api.Inspect().patchCount,previous.patchCount,'Unchanged snapshots never repaint badge panels');
send(9,3,'v2');assert.equal(level.__survivalVIPBadge.number.text,'9');assert.equal(medal.text,'勋 3','Recharge never fabricates a newly purchased medal');assert.equal(created,count);
send(9,0,'v3');assert(level.visible);assert(!medal.visible,'No purchased medal stays hidden even with VIP9');
send(0,3,'v4');assert(!level.visible&&medal.visible,'An actually owned medal is not inferred from recharge level');
for(const [vip,badMedal] of [[13,0],[1,11],[null,0],[true,0],[1,-1]]){const old=JSON.stringify(api.Inspect().rows);send(vip,badMedal,'bad_'+String(vip)+'_'+badMedal);assert.equal(JSON.stringify(api.Inspect().rows),old,'Invalid field cannot overwrite the complete cache');}
send(undefined,undefined,'legacy');assert.equal(api.Inspect().total,1);assert(!level.visible&&!medal.visible,'Old server snapshots remain compatible without invented badges');
console.log('VIP_LEADERBOARD_PASS: authoritative level and medal independent; purchase/recharge separation; cached panels; unchanged zero mutations; validation and legacy compatibility.');
