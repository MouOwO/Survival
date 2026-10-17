'use strict';
const fs=require('node:fs'),path=require('node:path'),Module=require('node:module'),assert=require('node:assert/strict');
const filename='panorama/src/scripts/custom_game/startup_loading.js';
const current=fs.readFileSync(process.argv[2]||filename,'utf8');
const before=fs.readFileSync('output/ui_refresh_audit_20261013/startup_hidden_idle_v1_before_20261013/startup_loading.js','utf8');
const beforeXml=fs.readFileSync('design_refs/dawnward_loading_20261015/baseline/sources/panorama/src/layout/custom_game/startup_loading.xml','utf8');
// Reuse the existing authored-XML/native-API harness and execute the whole
// actual production IIFE. Instrument only mock setters/getters, not production.
const fixtureFile=path.join(__dirname,'test_startup_loading_ui.js');
const original=fs.readFileSync(fixtureFile,'utf8');const seam=original.indexOf('// LAN may replicate');assert(seam>0);
let fixture=original.slice(0,seam).replace('const script = fs.readFileSync','let script = fs.readFileSync');
fixture=fixture.replace('    const nodes = {}, requests', '    const counts={style:0,text:0,classes:0,visible:0,table:0,localPlayer:0,schedule:0};\n    const nodes = {}, requests');
fixture=fixture.replace('this.style = {};','this.style = new Proxy({}, {set:(obj,key,value)=>{counts.style++;obj[key]=value;return true;}});\n            let text;Object.defineProperty(this,"text",{get:()=>text,set:value=>{counts.text++;text=value;}});');
fixture=fixture.replace('set: value => { this._visible = value;', 'set: value => { counts.visible++;this._visible = value;');
fixture=fixture.replace('SetHasClass(value, enabled) { enabled ?', 'SetHasClass(value, enabled) { counts.classes++;enabled ?');
fixture=fixture.replace('$.Schedule = (delay, fn) => scheduled.push({at: now + delay, fn});','$.Schedule = (delay, fn) => {counts.schedule++;return scheduled.push({at: now + delay, fn});};');
fixture=fixture.replace('GetLocalPlayerID: () => localId,','GetLocalPlayerID: () => {counts.localPlayer++;return localId;},');
fixture=fixture.replace(/GetTableValue: name => ([\s\S]*?),\r?\n            SubscribeNetTableListener:/,'GetTableValue: name => (counts.table++, $1),\n            SubscribeNetTableListener:');
fixture=fixture.replace('        nodes, root, authoredRoot, requests, messages, config, nativeRuleCalls, nativePlayerInfoCalls,','        counts, env, nodes, root, authoredRoot, requests, messages, config, nativeRuleCalls, nativePlayerInfoCalls,');
const helper=new Module(fixtureFile,module);helper.filename=fixtureFile;helper.paths=Module._nodeModulePaths(__dirname);
helper._compile(fixture+'\nmodule.exports={harness,ready,loading,SetSource:value=>script=value};',fixtureFile);
const {harness,ready,loading,SetSource}=helper.exports;
function make(source,options={}){SetSource(source);return harness(source===before?{...options,authoredXml:beforeXml}:options);}
function delta(a,b){return Object.fromEntries(Object.keys(a).map(k=>[k,a[k]-b[k]]));}
function semantics(ui){const ids=['StartupLoadingPercent'];
 return {visible:ui.root.visible,surface:ui.nodes.StartupLoadingSurface.visible,retired:ui.nodes.StartupLoadingBackground.image==='',text:ids.map(id=>[id,ui.nodes[id]&&ui.nodes[id].text]),requests:ui.requests.map(r=>({name:r.name,payload:JSON.parse(JSON.stringify(r.payload))}))};}
function stable(source){const ui=make(source,{sharedConfig:{},engineWrapper:true,state:ready({admission_complete:true})});ui.imageLoaded();ui.advance(2);
 assert.equal(ui.root.visible,false);const c={...ui.counts};ui.advance(10);return {ui,counts:delta(ui.counts,c)};}
const old=stable(before),updated=stable(current);
assert(old.counts.text>200,'actual old full IIFE repaints hidden labels during0.5s poll');
assert.equal(updated.counts.text,0,'released hidden page has no fine text rendering');
assert(updated.counts.style<old.counts.style/5,'keep bounded hidden visibility repairs, reduce actual DOM setter calls');
assert(updated.counts.localPlayer<old.counts.localPlayer/5,'retired fast path avoids repeated roster/phase/player reads');
assert.equal(updated.counts.table,old.counts.table,'0.5s real session snapshot watchdog remains');
assert.deepEqual(semantics(updated.ui),semantics(old.ui),'stable admission, image retirement, progress and requests unchanged despite intentionally removed decorative text');
function behavior(source){const u=make(source,{engineWrapper:true,state:loading()});u.imageLoaded();u.advance(.5);const stages=[semantics(u)];
 u.setState(ready({admission_complete:true}));u.advance(1);stages.push(semantics(u));
 u.setState(undefined);u.advance(.5);stages.push(semantics(u));
 u.setState(loading({session_id:'new-match-456',progress:26}));u.advance(.5);stages.push(semantics(u));
 u.imageLoaded();u.advance(.5);stages.push(semantics(u));
 u.setState(ready({session_id:'new-match-456',admission_complete:true}));u.advance(.5);stages.push(semantics(u));
 u.setLocalId(1);u.advance(.5);stages.push(semantics(u));
 return {u,stages};}
const control=behavior(before),candidate=behavior(current);
assert.deepEqual(candidate.stages,control.stages,'auth/image handshake,new session,missing packet,progress and local-player safety match actual old IIFE');
const recovery=stable(current).ui;
recovery.root.visible=true;recovery.root.hittest=true;recovery.advance(.5);assert.equal(recovery.root.visible,false);assert.equal(recovery.root.hittest,false,'external wrapper reopening repairs on next original poll');
recovery.root._visible=undefined;recovery.root.hittestchildren=undefined;recovery.advance(.5);assert.equal(recovery.root.visible,false);assert.equal(recovery.root.hittestchildren,false,'unknown native properties require successful original repair, never a guessed cache hit');
const textCount=recovery.counts.text;recovery.nodes.StartupLoadingSurface.style.opacity='1';recovery.advance(5);assert.equal(recovery.nodes.StartupLoadingSurface.style.opacity,'0','unreadable surface style repair remains bounded5s');assert.equal(recovery.counts.text,textCount);
recovery.env.CustomNetTables.GetTableValue=()=>{throw Error('transient table API failure');};recovery.advance(.5);assert.equal(recovery.root.visible,false,'failed read retains release without authentication guesses');
const restored=make(current,{sharedConfig:updated.ui.config,engineWrapper:true});restored.advance(2);assert.equal(restored.root.visible,false,'new phase context honors actual same-session completion memo');
restored.setState(loading({session_id:'another-world'}));assert.equal(restored.root.visible,true,'valid different world event wakes immediately');
for(const ui of [updated.ui,candidate.u,recovery,restored])assert.deepEqual(ui.nativeRuleCalls,[],'never introduce unsafe native GameRules reads');
const evidence={scope:'Complete actual old/new startup IIFE + existing authored XML VM harness; counters are mocked native/DOM calls, not runtime CPU cost or FPS',stable_seconds:10,before:old.counts,after:updated.counts,session_snapshot_watchdog_seconds:.5,hidden_style_repair_seconds:5,external_wrapper_recovery_seconds:.5,auth_progress_request_semantics_unchanged:true,removed_party_and_status_text_excluded_from_comparison:true};
if(process.env.STARTUP_IDLE_EVIDENCE)fs.writeFileSync(process.env.STARTUP_IDLE_EVIDENCE,JSON.stringify(evidence,null,2)+'\n');
console.log('STARTUP_LOADING_IDLE_PASS '+JSON.stringify(evidence));
