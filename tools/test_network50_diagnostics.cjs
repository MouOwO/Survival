"use strict";
const fs=require("node:fs"),vm=require("node:vm"),assert=require("node:assert/strict");
const source=fs.readFileSync("panorama/src/scripts/custom_game/common/network50_diagnostics.js","utf8");
function fixture(options={}){
 const callbacks={},messages=[],calls=[];let playing=true;
 const runtime={Inspect:()=>({ready:true,views:7,counters:{received:96}})},cfg={SurvivalCompactRuntime:runtime,
  SurvivalCompactHUDSource:{Snapshot:()=>({wave:{status:"countdown",current_wave:0,alive:0,player_defeated:0}})}};
 const game={IsInToolsMode:()=>true,AddCommand:(name,fn)=>{callbacks[name]=fn;},GetGameTime:()=>100,IsGamePaused:()=>false,
  GameStateIs:state=>{calls.push(state);if(options.throws)throw Error("private error text");return options.numeric?1:state===37?playing:!playing;}};
 if(options.noAPI)delete game.GameStateIs;
 const env={Game:game,GameUI:{CustomUIConfig:()=>cfg},$:{GetContextPanel:()=>({IsValid:()=>true}),Msg:value=>messages.push(value)}};
 if(!options.noEnum)env.DOTA_GameState={DOTA_GAMERULES_STATE_GAME_IN_PROGRESS:37,DOTA_GAMERULES_STATE_POST_GAME:options.sameEnum?37:99};
 vm.runInNewContext(source,env);
 const callback=callbacks[cfg.SurvivalNetwork50Diagnostics.Command];
 return{cfg,calls,read(nonce="a".repeat(32)){callback(nonce);return JSON.parse(messages[messages.length-1].slice(("[NETWORK50_UI_INSPECT] "+nonce+" ").length));},finish(){playing=false;}};
}
const live=fixture();let before=live.read();assert.equal(before.engine.game_in_progress,true);assert.equal(before.engine.post_game,false);
live.finish();const after=live.read("b".repeat(32));assert.equal(after.wave.status,"countdown");assert.equal(after.wave.defeated,0);
assert.equal(after.engine.game_in_progress,false);assert.equal(after.engine.post_game,true);assert.deepEqual(live.calls,[37,99,37,99],"fresh native calls for each nonce, never cached HUD or hardcoded enum IDs");
for(const options of[{noAPI:true},{noEnum:true},{sameEnum:true},{numeric:true},{throws:true}]){
 const row=fixture(options).read();assert.equal(row.engine.game_in_progress,null);assert.equal(row.engine.post_game,null);assert.ok(!JSON.stringify(row).includes("private"));
}
const disposed=fixture();disposed.cfg.SurvivalCompactRuntime={};const row=disposed.read();assert.equal(row.active,false);assert.equal(disposed.calls.length,0);
console.log("NETWORK50_DIAGNOSTICS_PASS fresh native enum queries; cached live HUD with POST_GAME rejected by engine; unknown/throw/nonboolean fail closed; disposed context inert; no native process used");
