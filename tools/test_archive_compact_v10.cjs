"use strict";
const fs=require("node:fs"),vm=require("node:vm"),path=require("node:path"),fixturePath=path.resolve("tools/tests/archive_v10_lifecycle.test.cjs");
const fixture=fs.readFileSync(fixturePath,"utf8").split("const shadowRows =")[0];
const checks=String.raw`
const cp=require('node:child_process'),model=require('../../panorama/src/scripts/custom_game/common/compact_archive_model.js'),handles=[];
vm.runInContext(fs.readFileSync(path.join(sourceRoot,'common/ui_static_catalog.js'),'utf8'),context);
const real=JSON.parse(cp.execFileSync('C:/Program Files/lua/bin/lua5.1.exe',['scripts/vscripts/tests/test_compact_archive_projection.lua','emit'],{cwd:repo,encoding:'utf8',maxBuffer:8*1024*1024}));
cfg.SurvivalCompactArchiveModel=model;cfg.SurvivalCompactRuntime={ErrorText:code=>code,CreateView(key,options){const handle={options,Open(){},Dispose(){},Resync(){},SendIntent(){return {sent:true,request_token:1};}};handles.push(handle);return handle;}};
const api=load();advance(10);assert.equal(requests.length,0);api.Open();
const values={};function put(ops){const ids=new Set();for(const op of ops){const row=values[op.record]||(values[op.record]={});if(op.remove)delete row[op.field];else row[op.field]=op.value;ids.add(op.record);}return [...ids];}const read=(id,field)=>values[id]&&values[id][field];
handles[0].options.onCommit({full:true,revision:1},put(real.pages.clear.ops),read);const all=cards();assert.equal(all.length,176);const kept=all[1].__v10.host,first=all[0],id=cfg.SurvivalUICatalog.ByKey['archive:clear:'+first.__archiveItem.id],field=cfg.SurvivalUICatalog.Data.fields.find(f=>f.name==='count').id;
let children=0,walks=0,created=0;const allowed=new Set();function allow(p){allowed.add(p);p.children.forEach(allow);}allow(first);const getChildren=Panel.prototype.Children,walk=Panel.prototype.FindChildTraverse;Panel.prototype.Children=function(){children++;assert(allowed.has(this),'a delta may inspect only its changed card descendants, not grid or other cards');return getChildren.call(this);};Panel.prototype.FindChildTraverse=function(id){walks++;return walk.call(this,id);};const previousCreate=context.$.CreatePanel;context.$.CreatePanel=function(...args){created++;return previousCreate(...args);};
handles[0].options.onCommit({full:false,revision:2},put([{record:id,field,value:1}]),read);assert.equal(created,0,'K update retains all runtime components');assert.equal(walks,0,'K update never walks the complete root tree');assert.equal(first.__v10.count.text,'1/'+first.__archiveItem.target);assert.equal(all[1].__v10.host,kept);
console.log('ARCHIVE_COMPACT_ACTUAL_V10_PASS '+JSON.stringify({realRows:176,deltaRows:1,createdPanels:created,rootWalks:walks,boundedCardChildReads:children,unchangedIdentity:true,nativeFPSMeasured:false}));
`;
vm.runInNewContext(fixture+checks,{require:require("node:module").createRequire(fixturePath),__dirname:path.dirname(fixturePath),console},{filename:"archive_compact_v10_loaded_graph.cjs"});
