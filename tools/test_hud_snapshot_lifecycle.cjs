"use strict";
// Run the complete HUD in the existing real panel tree fixture, without loading
// that fixture's unrelated startup-loading assertions or any Dota process.
const assert=require("node:assert/strict"),fs=require("node:fs"),vm=require("node:vm");
let fixtureSource=fs.readFileSync("tools/test_startup_loading_ui.js","utf8");
fixtureSource=fixtureSource.slice(0,fixtureSource.indexOf("// LAN may replicate loading state"));
assert(fixtureSource.includes("function harness")&&fixtureSource.includes("function ready"));
fixtureSource=fixtureSource.replace("const env = {$};","const env = {$, Date:{now:()=>now*1000}};");
fixtureSource=fixtureSource.replace("env.Game.GetGameTime = () => now;",`env.Game.GetGameTime = () => now;
 env.Game.IsInToolsMode = () => options.idleTools === true;
 env.Game.AddCommand = (name,fn) => {
  if(options.commandAttempts)options.commandAttempts.push(name);
  if(options.idleRegisterFail)throw Error('registration rejected');
  if(options.idleCommands)options.idleCommands.set(name,fn);
 };`);
fixtureSource=fixtureSource.replace("nodes, root, authoredRoot, requests, messages, config, nativeRuleCalls, nativePlayerInfoCalls,",
 "nodes, root, authoredRoot, requests, messages, config, nativeRuleCalls, nativePlayerInfoCalls, context, env, scheduled, eventHandlers,");
fixtureSource=fixtureSource.replace("requests.push({name, payload})","requests.push({name, payload, at:now})");
const loader={require,module:{exports:{}},exports:{},console};
vm.runInNewContext(fixtureSource+"\nmodule.exports={harness,ready};",loader);
const {harness,ready}=loader.module.exports;
const production=fs.readFileSync("panorama/src/scripts/custom_game/survival_ui.js","utf8");
function create({hasSnapshot=true,builder=true,admitted=true,tools=false,registerFail=false}={}){
 const snap={sequence:1,player_id:0,resources:{wood:100,gold:50,population:1,max_population:10},
  wave:{status:"countdown",difficulty_selected:true,mode_selected:true,difficulty_id:"N2",current_wave:1}};
 const commands=new Map(),commandAttempts=[];
 const h=harness({hud:true,state:hasSnapshot?snap:undefined,startupState:ready({admission_complete:admitted}),
  idleTools:tools,idleCommands:commands,commandAttempts,idleRegisterFail:registerFail});
 h.commands=commands;h.commandAttempts=commandAttempts;
 let identity=builder?{entindex:10}:null,selected=builder?[10]:[],reads=0;
 const nativeRead=h.env.CustomNetTables.GetTableValue;
 h.env.CustomNetTables.GetTableValue=(name,key)=>{reads++;return name==="survival_builder_identity"?identity:nativeRead(name,key);};
 h.env.Entities.IsValidEntity=id=>id===10||id===20;
 h.env.Entities.GetUnitName=id=>id===10?"npc_survival_builder_proxy":"npc_dota_hero_axe";
 h.env.Entities.GetAbsOrigin=()=>[100,200,0];
 h.env.Players.GetSelectedEntities=()=>selected;
 h.env.Players.GetLocalPlayerPortraitUnit=()=>selected[0]??-1;
 h.env.GameUI.SelectUnit=id=>{selected=[id];h.selectedCalls=(h.selectedCalls||0)+1;};
 h.reload=()=>vm.runInContext(production,h.context);
 h.sync=()=>h.config.SurvivalHUDSnapshotSync.Inspect();
 h.full=()=>h.requests.filter(r=>r.name==="ui_request_full_snapshot");
 h.reads=()=>reads;h.setIdentity=value=>identity=value;
 return h;
}
{
 const h=create();h.advance(.11);assert(h.sync().hasSnapshot&&h.sync().builderFinished);
 const requests=h.full().length,reads=h.reads(),writes=h.visibilityWrites().length;
 h.advance(180);
 assert.equal(h.full().length,requests,"healthy static snapshots never trigger a 2-second rebuild loop");
 assert(h.reads()-reads<=37,"stable fallback is one sparse startup read per five seconds");
 assert.equal(h.visibilityWrites().length,writes,"same startup snapshot never rewrites the closed mode/difficulty UI");
 h.emit("survival_ui_private_snapshot",{sequence:2,player_id:0,resources:{wood:987,gold:321},wave:{difficulty_selected:true,current_wave:5}});
 assert.equal(h.nodes.WoodValue.text,"987");assert.equal(h.nodes.GoldValue.text,"321","private data applies without waiting for watchdog");
 const applied=h.sync().counters.applied;
 h.emit("survival_ui_private_snapshot",{sequence:2,player_id:0,resources:{wood:1}});
 assert.equal(h.sync().counters.applied,applied,"duplicate delivery updates receipt but does not repaint");
 h.emit("survival_ui_private_snapshot",{sequence:999,player_id:1,resources:{wood:1}});
 assert.equal(h.nodes.WoodValue.text,"987","foreign personal packets cannot take over this HUD");
}
{
 const h=create({hasSnapshot:false,builder:false});h.advance(90);
 const requests=h.full();
 assert(requests.length>=2&&requests.length<=8,"missing initial data uses bounded retries with backoff");
 for(let i=1;i<requests.length;i++)assert(requests[i].at-requests[i-1].at>=3.4,"one request remains in flight until its timeout and backoff");
 const count=requests.length,steps=h.sync().counters.builderSteps;
 h.advance(180);
 assert.equal(h.full().length,count,"failed initial acquisition stops sending when its bounded recovery window ends");
 assert.equal(h.sync().counters.builderSteps,steps,"unavailable builder does not poll native identity indefinitely");
 h.setIdentity({entindex:10});h.emit("survival_select_unit",{reason:"builder_ready"});h.advance(.11);
 assert(h.sync().builderFinished,"late explicit builder readiness restarts one bounded recovery");
 assert.equal(h.selectedCalls,1);
 h.emit("survival_ui_private_snapshot",{sequence:2,resources:{wood:55},wave:{difficulty_selected:true}});
 assert.equal(h.nodes.WoodValue.text,"55","late authoritative data stays accepted after bounded acquisition stops");
}
{
 const h=create({hasSnapshot:false,builder:false,admitted:false});h.advance(5);
 assert.equal(h.sync().counters.builderSteps,0,"loading does not try to select an unavailable builder");
 h.setIdentity({entindex:10});h.setStartup(ready({admission_complete:true}));h.advance(.11);
 assert(h.sync().builderFinished,"admission event immediately wakes pending builder recovery");
}
{
 const h=create({hasSnapshot:false,builder:false});
 h.setStartup(ready({admission_complete:true,profiles_ready:false}));h.advance(90);
 const requests=h.full().length;
 h.setStartup(ready({admission_complete:true,profiles_ready:true}));h.advance(.11);
 assert(h.full().length>requests,"same-phase profile readiness renews the bounded missing-data recovery window");
}
{
 const h=create();h.advance(.11);
 const old=h.config.SurvivalHUDSnapshotSync,oldCounters={...old.Inspect().counters};
 h.reload();h.advance(.11);const fresh=h.config.SurvivalHUDSnapshotSync;
 assert.notEqual(old,fresh);assert(old.Inspect().disposed);
 const oldPolls=old.Inspect().counters.polls;
 h.advance(60);h.emit("survival_ui_private_snapshot",{sequence:2,resources:{wood:123},wave:{difficulty_selected:true}});
 assert.equal(old.Inspect().counters.polls,oldPolls,"old scheduled callbacks remain inert even if native cancellation is unavailable");
 assert.equal(h.nodes.WoodValue.text,"123","replacement context owns the single event listener");
 assert(fresh.Inspect().counters.polls<20,"reload leaves a single sparse watchdog");
 h.root.valid=false;const requests=h.full().length;h.advance(60);
 assert.equal(h.full().length,requests,"deleted context cannot send new recovery requests");
}
{
 const h=create({hasSnapshot:false,builder:false});h.advance(.11);
 const epoch=h.sync().epoch;
 h.setStartup(ready({session_id:"next-match",admission_complete:true}));
 h.setIdentity({entindex:10});
 h.emit("survival_ui_private_snapshot",{sequence:1,session_id:"next-match",player_id:0,resources:{wood:432},wave:{difficulty_selected:true}});
 h.advance(.11);
 assert(h.sync().epoch>epoch);assert.equal(h.nodes.WoodValue.text,"432","new session resets the applied sequence");
 h.emit("survival_ui_private_snapshot",{sequence:999,session_id:"match-123",resources:{wood:1}});
 assert.equal(h.nodes.WoodValue.text,"432","explicit retired-session packets remain inert");
 assert(h.sync().builderFinished,"old builder retry cannot consume the new epoch");
}
{
 const mode={mode_selected:false,mode_id:"",selector_player_id:0,
  mode_options:[{mode_id:"pure",display_name:"纯净模式"},{mode_id:"standard",display_name:"常规模式"}]};
 const wave={status:"selecting_difficulty",mode_selected:false,selector_player_id:0,
  difficulty_selected:false,difficulty_options:[{difficulty_id:"N1",display_name:"挑战1",unlocked:true}]};
 const h=harness({hud:true,loadSharedUI:true,state:{sequence:1,resources:{},wave},
  startupState:ready({admission_complete:true,profiles_ready:true,setup:mode})});
 h.advance(.11);
 h.nodes.MatchModeOptions.children[0].events.onactivate();
 const oldConfirm=h.nodes.DifficultySelectionConfirm.events.onactivate;
 oldConfirm();oldConfirm();
 assert.equal(h.requests.filter(r=>r.name==="survival_loading_mode_select").length,1,"mode confirmation still sends one original business request");
 h.emit("survival_loading_mode_result",{success:1,mode_id:"pure"});
 const difficulty=h.nodes.DifficultySelectionButtons.children.find(p=>p.BHasClass("DifficultyOptionButton"));
 difficulty.events.onactivate();h.nodes.DifficultySelectionConfirm.events.onactivate();
 assert.equal(h.requests.filter(r=>r.name==="ui_difficulty_select_request").length,1,"difficulty action keeps its original endpoint");
 h.emit("survival_ui_private_snapshot",{sequence:3,resources:{},wave:{...wave,mode_selected:true,difficulty_selected:true,difficulty_id:"N1"}});
 assert(h.nodes.DifficultySelectionOverlay.BHasClass("DifficultySelectionHidden"),"confirmed authoritative difficulty closes the same modal");
 vm.runInContext(production,h.context);const requests=h.requests.length;
 oldConfirm();assert.equal(h.requests.length,requests,"retired confirmation action cannot send into the replacement context");
}
{
 const h=create();assert.equal(h.commandAttempts.length,0,"non-Tools HUD registers no diagnostic command");
 const failing=create({tools:true,registerFail:true});failing.advance(.11);
 assert(failing.sync().hasSnapshot&&failing.sync().builderFinished,"registration failure cannot block the HUD");
 const t=create({tools:true});t.advance(.11);assert.equal(t.commands.size,1);
 const api=t.config.SurvivalHUDSnapshotSync,command=api.InspectCommand,fn=t.commands.get(command),nonce="a".repeat(32);
 assert(command&&t.messages.some(m=>m.includes(command)&&m.includes("SurvivalHUDSnapshotSync.Inspect")),"advertisement includes the exact command and API");
 const before=JSON.stringify(t.sync()),reads=t.reads(),requests=t.requests.length,jobs=t.scheduled.length;
 let inspectCalls=0;const inspect=api.Inspect;
 api.Inspect=function(){inspectCalls++;return {...inspect(),session:"DO_NOT_PRINT_AUTH_SECRET",resources:{secret:"DO_NOT_PRINT_AUTH_SECRET"},
  counters:{...inspect().counters,access_token:"DO_NOT_PRINT_AUTH_SECRET"}};};
 for(const args of [[],["z".repeat(32)],["a".repeat(31)],["a".repeat(33)],["DO_NOT_PRINT_AUTH_SECRET"],["wrong_command",nonce]])fn(...args);
 assert.equal(inspectCalls,0,"invalid nonce never invokes the inspection API");
 fn(nonce);assert.equal(inspectCalls,1,"valid command dynamically invokes current Inspect");
 fn(command,nonce);assert.equal(inspectCalls,2,"the native command-name prefix is accepted only when exact");
 const report=JSON.parse(t.messages.at(-1).slice(t.messages.at(-1).indexOf("{")));
 assert.equal(report.nonce,nonce);assert.equal(report.status,"ok");assert.equal(report.command,command);
 assert(!t.messages.some(m=>m.includes("DO_NOT_PRINT_AUTH_SECRET")),"only whitelisted counts/status are printed");
 api.Inspect=inspect;assert.equal(JSON.stringify(t.sync()),before);
 assert.equal(t.reads(),reads);assert.equal(t.requests.length,requests);assert.equal(t.scheduled.length,jobs,"inspect schedules nothing");
 t.reload();const fresh=t.config.SurvivalHUDSnapshotSync.InspectCommand;assert.notEqual(fresh,command);
 fn(nonce);assert.equal(JSON.parse(t.messages.at(-1).slice(t.messages.at(-1).indexOf("{"))).status,"inactive_context");
 t.commands.get(fresh)(nonce);assert.equal(JSON.parse(t.messages.at(-1).slice(t.messages.at(-1).indexOf("{"))).status,"ok","reload advertises a current-context entry");
}
console.log("HUD_SNAPSHOT_LIFECYCLE_PASS: full real HUD, 180s static/no resync, immediate private data, bounded in-flight/backoff, admission/builder wake, session/reload plus Tools-only strict nonce and read-only inspect");
