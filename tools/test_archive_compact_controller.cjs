"use strict";
const fs=require("node:fs"),vm=require("node:vm"),path=require("node:path");
const fixturePath=path.resolve("tools/tests/archive_lifecycle.test.cjs"),fixture=fs.readFileSync(fixturePath,"utf8").split("const api=load();")[0];
const checks=String.raw`
const cp=require('node:child_process'),CAPI=require('../../panorama/src/scripts/custom_game/common/compact_archive_model.js');
vm.runInNewContext(fs.readFileSync(path.join(project,'panorama/src/scripts/custom_game/common/ui_static_catalog.js'),'utf8'),context);
vm.runInNewContext(fs.readFileSync(path.join(project,'panorama/src/scripts/custom_game/archive_v10_semantics.js'),'utf8'),context);
const real=JSON.parse(cp.execFileSync('C:/Program Files/lua/bin/lua5.1.exe',['scripts/vscripts/tests/test_compact_archive_projection.lua','emit'],{cwd:project,encoding:'utf8',maxBuffer:8*1024*1024}).trim());
cfg.SurvivalCompactArchiveModel=CAPI;cfg.ArchiveHandoff.Unlocked=(item,category)=>cfg.ArchiveV10Semantics.State(item,category);
let builds=0,deltaCalls=0,deltaCards=0,children=0,walks=0,mutations=0;const handles=[];
const oldChildren=Panel.prototype.Children,oldWalk=Panel.prototype.FindChildTraverse,oldSet=Panel.prototype.SetHasClass;
Panel.prototype.Children=function(){children++;return oldChildren.call(this);};Panel.prototype.FindChildTraverse=function(id){walks++;return oldWalk.call(this,id);};Panel.prototype.SetHasClass=function(c,on){mutations++;return oldSet.call(this,c,on);};
cfg.SurvivalArchiveV10Factory=()=>({Render(){builds++;return true;},Update(data,category,entries){deltaCalls++;deltaCards+=entries.length;return true;},Leave(){},Dispose(){}});cfg.SurvivalArchiveV10={};
cfg.SurvivalCompactRuntime={ErrorText:code=>code,CreateView(key,options){const h={key,options,opens:0,closes:0,disposes:0,Open(){this.opens++;},Dispose(){this.disposes++;},Close(){this.closes++;},Resync(){},SendIntent(){return {sent:true,request_token:1};}};handles.push(h);return h;}};
function state(){const values={};return {put(ops){const ids=new Set();for(const op of ops){const row=values[op.record]||(values[op.record]={});if(op.remove)delete row[op.field];else row[op.field]=op.value;ids.add(op.record);}return [...ids];},read:(id,field)=>values[id]&&values[id][field]};}
function commit(handle,category,full=true){const s=state(),changed=s.put(real.pages[category].ops);handle.options.onCommit({full,revision:1},changed,s.read);return s;}
const api=load();advance(100);assert.equal(requests.length,0,'closed initialization must not prefetch any catalogue');assert.equal(handles.length,0);
api.Open();assert.equal(handles.length,1);assert.equal(handles[0].key,'archive:clear');assert.equal(handles[0].opens,1);const s=commit(handles[0],'clear');assert.equal(cards().length,176);const fullBuilds=builds;
const C=cfg.SurvivalUICatalog,field=Object.fromEntries(C.Data.fields.map(f=>[f.name,f.id])),first=real.pages.clear.expected.rows[0],record=C.ByKey['archive:clear:'+first.id];
children=walks=mutations=0;deltaCards=0;handles[0].options.onCommit({full:false,revision:2},s.put([{record,field:field.count,value:1}]),s.read);
assert.equal(builds,fullBuilds,'one count delta must not enter full Render');assert.equal(deltaCards,1);assert.equal(children,0,'the controller delta must not enumerate native card children');assert.equal(walks,0,'cached panels must not walk the complete panel tree');
const legacy=listeners.find(x=>x.name==='survival_archive_snapshot').fn,beforeDelta=deltaCalls;children=walks=mutations=0;
for(let i=0;i<400;i++)legacy(snapshot(1000+i,[]));advance(100);assert.equal(requests.length,0);assert.equal(deltaCalls,beforeDelta);assert.equal(children,0);assert.equal(walks,0);assert.equal(mutations,0);
api.SelectCategory('commerce_goods');assert.equal(handles.length,2);assert.equal(handles[0].disposes,1);const goods=commit(handles[1],'commerce_goods'),second=real.pages.commerce_goods;const before=builds;deltaCards=0;children=walks=0;
handles[1].options.onCommit({full:false,revision:2},goods.put(second.delta.ops),goods.read);assert.equal(builds,before);assert.equal(deltaCards,1);assert.equal(children,0);assert.equal(walks,0);
api.Close();const closedBuilds=builds,closedDeltas=deltaCalls;handles[1].options.onCommit({full:true,revision:10},[],goods.read);advance(100);assert.equal(builds,closedBuilds);assert.equal(deltaCalls,closedDeltas);assert.equal(requests.length,0);
api.Open();assert.equal(handles.length,3);assert.equal(handles[2].key,'archive:commerce_goods');assert.equal(handles[2].opens,1,'reopen asks for a fresh authoritative full');api.Dispose();
console.log('ARCHIVE_COMPACT_CONTROLLER_PASS '+JSON.stringify({realClearRows:176,currentCategoryOpens:3,initialPrefetch:0,deltaCards:1,deltaNativeWalks:0,deltaNativeChildren:0,closedRenders:0,duplicateLegacyRenders:0,nativeFPSMeasured:false}));
`;
vm.runInNewContext(fixture+checks,{require:require("node:module").createRequire(fixturePath),__dirname:path.dirname(fixturePath),console},{filename:"archive_compact_controller_real_model.cjs"});
