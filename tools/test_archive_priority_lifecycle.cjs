"use strict";
const fs=require("node:fs"),vm=require("node:vm"),path=require("node:path");
// Exercise the entire loaded production controller, real category callbacks,
// cache receiver and lifecycle timers, using the existing native-panel fixture.
const fixturePath=path.resolve("tools/tests/archive_lifecycle.test.cjs");
const fixture=fs.readFileSync(fixturePath,"utf8").split("const api=load();")[0];
const checks=String.raw`
const api=load(),handler=listeners.find(l=>l.name==='survival_archive_snapshot').fn;
const categories=[{id:'clear',name:'通关存档'},{id:'shadow',name:'虚空之影'},{id:'points',name:'积分道具'}];
const row=id=>({id,name:id,count:0,target:10,completed:0});
function page(category,sequence,extra={}){return snapshot(sequence,[row(category)],{categories,category_id:category,...extra});}
function requestsSince(n){return requests.slice(n).filter(r=>r.name==='survival_archive_request');}
function noRequests(n,label){assert.equal(requests.length,n,label);}
advance(.2);assert.equal(requests.length,1);assert.equal(requests[0].payload.prefetch,1);
handler(page('clear',1));handler(page('shadow',2));api.Open();
let before=requests.length;api.SelectCategory('shadow');
assert.equal(requestsSince(before).length,1);assert.equal(requests.at(-1).payload.prefetch,0);assert.equal(requests.at(-1).payload.category_id,'shadow');assert.equal(requests.at(-1).payload.resync,undefined);
before=requests.length;for(let i=0;i<100;i++){api.SelectCategory('shadow');handler(page('shadow',2));}advance(1);noRequests(before,'same tab, duplicate packets and settled timers never repeat priority requests');
api.SelectCategory('clear');assert.equal(requests.at(-1).payload.category_id,'clear');
before=requests.length;api.SelectCategory('points');assert.equal(requestsSince(before).length,1);assert.equal(requests.at(-1).payload.prefetch,0,'a cold category change also sends exactly one normal priority notification');
handler(page('points',10,{chunks:3,chunk:1}));before=requests.length;
const deadlineTimers=timers.filter(t=>!t.ran&&!t.cancelled&&t.at>=time+7.9).length;
for(let i=0;i<100;i++)handler(page('points',10,{chunks:3,chunk:1}));
assert.equal(timers.filter(t=>!t.ran&&!t.cancelled&&t.at>=time+7.9).length,deadlineTimers,'duplicate chunks cannot add deadlines');
advance(3);noRequests(before,'a progressing partial page suppresses the 0.75 second full-prefetch retry');
handler(page('points',11,{chunks:3,chunk:1}));advance(4.9);noRequests(before,'a newer partial batch does not extend the absolute page-load deadline');
advance(.31);assert.equal(requestsSince(before).filter(r=>r.payload.resync===1).length,1,'a real eight-second timeout sends one targeted full request');assert.equal(requests.at(-1).payload.category_id,'points');
handler(page('points',12,{chunks:3,chunk:2}));handler(page('points',12,{chunks:3,chunk:3}));handler(page('points',12,{chunks:3,chunk:1}));
before=requests.length;advance(12);noRequests(before,'an interleaved completed page cancels its retry and deadline');
handler(page('points',13,{delta:1,base_sequence:999,rows:[{path:['rows','1','count'],value:2}]}));advance(.21);
assert.equal(requests.at(-1).payload.resync,1,'a confirmed baseline gap also requests a targeted full');assert.equal(requests.at(-1).payload.category_id,'points');
handler(page('points',14));before=requests.length;
handler(page('shadow',20,{chunks:2,chunk:1}));advance(8.3);noRequests(before,'a missing background fragment is marked dirty without refetching the visible or closed pages');
api.SelectCategory('shadow');assert.equal(requestsSince(before).length,1);assert.equal(requests.at(-1).payload.prefetch,0);assert.equal(requests.at(-1).payload.resync,1,'selecting that dirty cached page repairs only its own baseline');
handler(page('shadow',21));before=requests.length;
handler(page('shadow',22,{chunks:2,chunk:1}));api.Close();before=requests.length;advance(10);noRequests(before,'closing keeps assembly failure from starting background request loops');
api.Open();assert.equal(requests.at(-1).payload.resync,1);handler(page('shadow',23));
handler(page('shadow',24,{chunks:2,chunk:1}));api.Dispose();before=requests.length;advance(20);handler(page('shadow',25));noRequests(before,'old batch deadlines and subscribers have no authority after disposal');
console.log('ARCHIVE_PRIORITY_LIFECYCLE_PASS '+JSON.stringify({cachedCategoryChangeRequests:1,coldCategoryChangeRequests:1,repeatedTabRequests:0,partialPageRetryRequests:0,deadlineSeconds:8,targetedFullRecovery:true,backgroundTimeoutRequests:0,disposedRequests:0,nativeFPSMeasured:false}));
`;
vm.runInNewContext(fixture+checks,{require:require("node:module").createRequire(fixturePath),__dirname:path.dirname(fixturePath),console},{filename:"archive_priority_lifecycle_behavior.cjs"});
