"use strict";
// Shipping passive controller: compact ingress, no legacy request or rewards.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync('panorama/src/scripts/custom_game/vip_window.js','utf8');
let callbacks=[],opens=0,disposes=0,sends=0;
const cfg={SurvivalUICatalog:{ByKey:{'vip:state':88},FieldIds:{known:1,count:2}},
 SurvivalCompactRuntime:{CreateView(key,o){assert.equal(key,'vip');callbacks.push(o.onCommit);return{Open(){opens++;},Dispose(){disposes++;}};}}};
const context={IsValid:()=>true,FindChildTraverse:()=>null};
const env={GameUI:{CustomUIConfig:()=>cfg},$:{GetContextPanel:()=>context},
 GameEvents:{Subscribe(){throw Error('compact controller must not register legacy data');},SendCustomGameEventToServer(){sends++;}}};
function load(){vm.runInNewContext(source,env);}
function feed(callback,known,level){callback({full:true},[88],(id,field)=>{assert.equal(id,88);return field===1?known:level;});}
load();assert.equal(opens,1);assert.equal(sends,0);assert.equal(cfg.SurvivalVIPStatus.Inspect().known,false);
feed(callbacks[0],1,5);assert.equal(cfg.SurvivalVIPStatus.Inspect().level,5);
for(let n=0;n<1000;n++)feed(callbacks[0],1,5);
assert.equal(opens,1);assert.equal(sends,0);
feed(callbacks[0],0);assert.equal(cfg.SurvivalVIPStatus.Inspect().known,false);
feed(callbacks[0],1,3);load();assert.equal(disposes,1);assert.equal(opens,2);
feed(callbacks[0],1,12);assert.equal(cfg.SurvivalVIPStatus.Inspect().level,3,'retired callback cannot overwrite replacement');
feed(callbacks[1],1,4);assert.equal(cfg.SurvivalVIPStatus.Inspect().level,4);
cfg.SurvivalVIPStatus.Dispose();feed(callbacks[1],1,9);assert.equal(cfg.SurvivalVIPStatus.Inspect().level,4);
assert.equal(disposes,2);assert.equal(sends,0);
console.log('COMPACT_VIP_CONTROLLER_PASS original passive grade,unknown,reload/disposed callbacks,0 legacy requests/claims; no native FPS');
