"use strict";
// Execute the entire real entitlement HUD with counted native setters,
// deterministic wall/game clocks, NetTable broadcasts and context replacement.
const assert=require("node:assert/strict"),fs=require("node:fs"),vm=require("node:vm");
const source=fs.readFileSync("panorama/src/scripts/custom_game/commerce_actions.js","utf8");
function harness({barrier=0,wall=null,tools=false,registerFail=false}={}){
 let now=0,game=0,nextTask=0,nextListener=0;const tasks=[],listeners=new Map(),calls=[],tables={
  survival_commerce_actions:{"player_0":{barrier}},
  survival_commerce_wall:wall||{}},cfg={};
 const rootNodes=[],messages=[],commands=new Map(),commandAttempts=[],metrics={visible:0,text:0,refreshRuns:0,allReads:0};
 function makePanel(type,parent,id){
  const p={paneltype:type,id,parent,children:[],style:{},events:{},valid:true,_text:"",_visible:true,
   IsValid(){return this.valid;},SetPanelEvent(n,fn){this.events[n]=fn;},
   DeleteAsync(){this.valid=false;if(this.parent)this.parent.children=this.parent.children.filter(c=>c!==this);}};
  Object.defineProperty(p,"text",{get(){return this._text;},set(v){metrics.text++;this._text=v;}});
  Object.defineProperty(p,"visible",{get(){return this._visible;},set(v){metrics.visible++;this._visible=v;}});
  if(parent)parent.children.push(p);rootNodes.push(p);return p;
 }
 const context=makePanel("Panel",null,"ctx"),sentinel=makePanel("Panel",context,"OtherHud");
 const $={GetContextPanel:()=>context,CreatePanel:makePanel,Msg:text=>messages.push(text),
  Schedule(delay,fn){const t={id:++nextTask,at:now+delay,fn,cancelled:false};tasks.push(t);return t.id;},
  CancelScheduled(id){const t=tasks.find(t=>t.id===id);if(t)t.cancelled=true;}};
 const env={$,Game:{GetLocalPlayerID:()=>0,GetGameTime:()=>game,IsInToolsMode:()=>tools,
  AddCommand(name,fn){commandAttempts.push(name);if(registerFail)throw Error('registration rejected');commands.set(name,fn);}},
  GameUI:{CustomUIConfig:()=>cfg,GetCursorPosition:()=>[4,5],GetScreenWorldPosition:()=>[100,200,300]},
  Entities:{IsValidEntity:id=>id===100||id===101},
  CustomNetTables:{GetTableValue:(table,key)=>tables[table]?.[key],
   GetAllTableValues(table){metrics.allReads++;return Object.entries(tables[table]||{}).map(([key,value])=>({key,value}));},
   SubscribeNetTableListener(table,fn){const token=++nextListener;listeners.set(token,{table,fn});return token;},
   UnsubscribeNetTableListener(token){listeners.delete(token);}},
  GameEvents:{SendCustomGameEventToServer:(name,payload)=>calls.push({name,payload})}};
 const scope=vm.createContext(env);function reload(){vm.runInContext(source,scope);}reload();
 function advance(seconds,{paused=false}={}){
  const end=now+seconds;let iterations=0;
  for(;;){
   tasks.sort((a,b)=>a.at-b.at);if(!tasks.length||tasks[0].at>end)break;
   const t=tasks.shift();if(!paused)game+=t.at-now;now=t.at;
   if(!t.cancelled){metrics.refreshRuns++;t.fn();}assert(++iterations<10000,"bounded scheduler");
  }
  if(!paused)game+=end-now;now=end;
 }
 function change(table,key,value){if(value==null)delete tables[table][key];else tables[table][key]=value;
  for(const l of [...listeners.values()])if(l.table===table)l.fn(table,key,value);}
 return {cfg,tasks,listeners,calls,metrics,context,sentinel,reload,advance,change,messages,commands,commandAttempts,
  api:()=>cfg.SurvivalCommerceActions,
  root:()=>context.children.find(p=>p.id==="CommerceActions"&&p.valid),
  shield:()=>context.children.find(p=>p.id==="CommerceActions"&&p.valid).children[2],
  pending:()=>tasks.filter(t=>!t.cancelled).length};
}
{
 const h=harness();h.advance(0);const writes={...h.metrics},runs=h.metrics.refreshRuns;
 assert(!h.root().visible&&!h.shield().visible);assert.equal(h.pending(),0);
 h.advance(300);assert.equal(h.metrics.refreshRuns,runs,"hidden unowned shield never wakes a quarter-second timer");
 assert.equal(h.metrics.text,writes.text);assert.equal(h.metrics.visible,writes.visible);
 for(let i=0;i<1000;i++)h.change("survival_commerce_actions","player_0",{barrier:0});
 assert.equal(h.pending(),0,"ordinary local entitlement refreshes do not wake an unowned shield timer");
 for(let i=0;i<1000;i++)h.change("survival_commerce_wall","foreign_"+i,{player_id:1,ready_at:100,remaining:50});
 assert.equal(h.pending(),0,"foreign player shield traffic never schedules this HUD");
}
{
 const h=harness({barrier:1,wall:{
  "100":{player_id:0,ready_at:30,expires:10,remaining:900},
  "101":{player_id:1,ready_at:10000,expires:9000,remaining:1},
  "999":{player_id:0,ready_at:9999,expires:9000,remaining:1}}});
 h.advance(0);assert.equal(h.metrics.allReads,1,"activation reads existing own wall state once");
 assert.equal(h.shield().text,"次元护盾：900（10秒）");assert(h.api().Inspect().countdownPending);
 const writes=h.api().Inspect().counters.textWrites;h.advance(2,{paused:true});
 assert.equal(h.api().Inspect().counters.textWrites,writes,"paused countdown does not rewrite equal native text");
 h.advance(10.1);assert.match(h.shield().text,/次元护盾冷却：20秒/);
 h.advance(20);assert.equal(h.shield().text,"次元护盾：已就绪");assert.equal(h.pending(),0);
 const refreshes=h.api().Inspect().counters.refreshes;h.advance(300);
 assert.equal(h.api().Inspect().counters.refreshes,refreshes,"ready owned shield has no persistent timer");
}
{
 const h=harness({barrier:1});h.advance(0);
 const runs=h.api().Inspect().counters.refreshes;
 for(let i=1;i<=1000;i++)h.change("survival_commerce_wall","100",{player_id:0,ready_at:30,expires:10,remaining:i});
 assert.equal(h.pending(),1,"one pending refresh coalesces an entire native damage burst");
 h.advance(0);assert.equal(h.api().Inspect().counters.refreshes,runs+1);
 assert.equal(h.shield().text,"次元护盾：1000（10秒）","burst takes the latest depletion state");
 const writes=h.api().Inspect().counters.textWrites;
 for(let i=0;i<1000;i++)h.change("survival_commerce_wall","100",{player_id:0,ready_at:30,expires:10,remaining:1000});
 h.advance(0);assert.equal(h.api().Inspect().counters.textWrites,writes,"identical event data causes no native text writes");
 h.change("survival_commerce_actions","player_0",{barrier:0});h.advance(0);
 assert(!h.shield().visible&&!h.api().Inspect().countdownPending);assert.equal(h.pending(),0);
 h.change("survival_commerce_actions","player_0",{barrier:1});h.advance(0);
 assert.equal(h.shield().text,"次元护盾：1000（10秒）","re-acquisition reloads authoritative cached shield state");
 h.change("survival_commerce_wall","100",null);h.advance(0);
 assert.equal(h.shield().text,"次元护盾：已就绪");assert.equal(h.pending(),0,"removed current wall cancels countdown");
}
{
 const h=harness({barrier:1,wall:{"100":{player_id:0,ready_at:30,expires:10,remaining:50}}});h.advance(0);
 const old=h.api(),oldTimer=h.tasks.find(t=>!t.cancelled),oldAim=h.cfg.SurvivalCommerceAim;
 h.reload();h.advance(0);assert.notEqual(h.api(),old);assert.equal(h.listeners.size,2,"reload leaves one owned pair of subscriptions");
 const metrics={...h.metrics};oldTimer.fn();assert.equal(h.metrics.text,metrics.text,"stale callback cannot change new context");
 assert.equal(oldAim("pressed",0),false,"retired input handler is inert");
 assert(h.sentinel.valid&&h.sentinel.visible,"Dispose deletes only this owned HUD");
 h.context.valid=false;h.root().valid=false;const sent=h.calls.length;h.advance(5);
 assert.equal(h.cfg.SurvivalCommerceBlink(),false);assert.equal(h.calls.length,sent,"invalid context cannot cast");
}
{
 const h=harness();h.change("survival_commerce_actions","player_0",{barrier:0,blink:1,ultimate:1});h.advance(0);
 const blink=h.root().children.find(p=>p.children[0]?.text==="D · 侏儒瞬移");
 blink.events.onactivate();assert.equal(h.cfg.SurvivalCommerceAim("pressed",1),true);assert.equal(h.calls.length,0,"right-click cancel remains local");
 assert.equal(h.cfg.SurvivalCommerceBlink(),true);assert.equal(h.calls.length,1);
 assert.equal(h.calls[0].name,"survival_commerce_action");assert.deepEqual({...h.calls[0].payload},{action:"blink",x:100,y:200});
 assert.equal(h.pending(),0,"other entitlement input does not need a shield timer");
}
{
 const h=harness();assert.equal(h.commandAttempts.length,0,"non-Tools entitlement HUD registers no diagnostic command");
 const f=harness({tools:true,registerFail:true});f.advance(0);assert(!f.root().visible,"command registration failure preserves normal HUD setup");
 const t=harness({tools:true});t.advance(0);const api=t.api(),command=api.InspectCommand,fn=t.commands.get(command),nonce="b".repeat(32);
 assert(t.messages.some(m=>m.includes(command)&&m.includes("SurvivalCommerceActions.Inspect")),"advertisement includes exact known command and API");
 const state=JSON.stringify(api.Inspect()),metrics={...t.metrics},pending=t.pending(),sent=t.calls.length;
 let inspectCalls=0;const inspect=api.Inspect;
 api.Inspect=function(){inspectCalls++;return {...inspect(),account:"DO_NOT_PRINT_AUTH_SECRET",orders:["DO_NOT_PRINT_AUTH_SECRET"],
  counters:{...inspect().counters,auth_token:"DO_NOT_PRINT_AUTH_SECRET"}};};
 for(const args of [[],["z".repeat(32)],["a".repeat(31)],["a".repeat(33)],["DO_NOT_PRINT_AUTH_SECRET"],["wrong_command",nonce]])fn(...args);
 assert.equal(inspectCalls,0);fn(nonce);assert.equal(inspectCalls,1);
 fn(command,nonce);assert.equal(inspectCalls,2);
 const report=JSON.parse(t.messages.at(-1).slice(t.messages.at(-1).indexOf("{")));
 assert.equal(report.nonce,nonce);assert.equal(report.status,"ok");assert.equal(report.command,command);
 assert(!t.messages.some(m=>m.includes("DO_NOT_PRINT_AUTH_SECRET")),"private DTO extras never enter console output");
 api.Inspect=inspect;assert.equal(JSON.stringify(api.Inspect()),state);assert.deepEqual(t.metrics,metrics);
 assert.equal(t.pending(),pending);assert.equal(t.calls.length,sent,"inspect has no requests/timers/render side effects");
 t.reload();const fresh=t.api().InspectCommand;assert.notEqual(fresh,command);
 fn(nonce);assert.equal(JSON.parse(t.messages.at(-1).slice(t.messages.at(-1).indexOf("{"))).status,"inactive_context");
 t.commands.get(fresh)(nonce);assert.equal(JSON.parse(t.messages.at(-1).slice(t.messages.at(-1).indexOf("{"))).status,"ok");
}
console.log("COMMERCE_ACTIONS_LIFECYCLE_PASS: real idle/countdown/events/input/lifecycle plus Tools-only exact command, nonce rejection, privacy whitelist and read-only current-context inspect");
