"use strict";
// Exercise the real seed with real public configs and a virtual NPC corpus.
// Invalid #base targets must fail before any outside read; no process/game IO.
const assert=require('node:assert/strict'),cp=require('node:child_process');
const lua='C:/Program Files/lua/bin/lua5.1.exe';
const actual=JSON.parse(cp.execFileSync(lua,['tools/selected_stats_static_seed.lua'],{encoding:'utf8'}));
assert.ok(actual.sources.includes('scripts/npc/npc_archive_challenges_units.txt'));
assert.ok(actual.sources.includes('scripts/npc/npc_tools_native_lane_pilot.txt'));
assert.equal(new Set(actual.sources).size,actual.sources.length);
function run(units,extra={}){
 const files={'scripts/npc/npc_units_custom.txt':units,'scripts/npc/npc_heroes_custom.txt':'"DOTAHeroes" {}',...extra};
 const fields=Object.entries(files).map(([k,v])=>'['+JSON.stringify(k)+']='+JSON.stringify(v)).join(',');
 const code=`package.path='scripts/vscripts/?.lua;'..package.path
 local files={${fields}};local count,outside=0,0
 io.open=function(path,mode)count=count+1;local raw=files[path];if not raw then outside=outside+1;error('UNAPPROVED_IO:'..path)end
 return{read=function()return raw end,close=function()end}end
 local ok,reason=pcall(assert(loadfile('tools/selected_stats_static_seed.lua')))
 print(require('core/json_encoder').encode({harness=true,ok=ok,reason=ok and ''or tostring(reason),reads=count,outside=outside}))`;
 const rows=cp.execFileSync(lua,['-'],{input:code,encoding:'utf8'}).trim().split(/\r?\n/).map(line=>JSON.parse(line));
 return {result:rows.at(-1),seed:rows.length>1?rows[0]:null};
}
let tests=1;
const cycle=run('#base "sub/one.txt"\n"DOTAUnits" {}',{'scripts/npc/sub/one.txt':'#base "../two.txt"','scripts/npc/two.txt':'#base "sub/one.txt"'});
assert.equal(cycle.result.ok,true);assert.equal(cycle.result.reads,4);assert.equal(cycle.result.outside,0);assert.ok(cycle.seed.sources.includes('scripts/npc/two.txt'));tests++;
for(const reference of ['/outside.txt','C:\\outside.txt','../../outside.txt','sub/../../../outside.txt','sub/private.lua']){
 const {result}=run('#base '+JSON.stringify(reference));assert.equal(result.ok,false,reference);assert.equal(result.outside,0,reference);assert.match(result.reason,/npc_(absolute_reference_refused|reference_escape_refused|subtree_required)/);tests++;
}
console.log(JSON.stringify({status:'PASS_REAL_SELECTED_STATIC_CORPUS_SEED',tests,real_numeric_paths:actual.numeric_paths.length,real_text_paths:actual.text_paths.length,real_text_values:actual.text_values.length,real_public_npc_sources:actual.sources.filter(x=>x.startsWith('scripts/npc/')).length,network_calls:0,transactions:0}));
