const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),vm=require('node:vm'),assert=require('node:assert/strict');
const dir=process.argv[2];
const W=require(path.resolve('panorama/src/scripts/custom_game/common/compact_wire.js'));
const Model=require(path.resolve(dir||'panorama/src/scripts/custom_game/common','compact_selected_model.js'));
const cfg={};vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/common/ui_static_catalog.js','utf8'),{GameUI:{CustomUIConfig:()=>cfg}});
const C=cfg.SurvivalUICatalog, schema=W.CompileLookup(C.Data,1);
const vectors=JSON.parse(cp.execFileSync('C:/Program Files/lua/bin/lua5.1.exe',[process.env.ALIAS_LUA_FIXTURE||'scripts/vscripts/tests/test_selected_alias_equivalence.lua',...(dir?[dir]:[])],{encoding:'utf8'}));
let checks=0;
function decode(packets,derive){
 const receiver=W.NewReceiver(schema,{schema:1,schema_sha256:C.Data.sha256,session:900,epoch:1,view:5}),values=new Map();
 const model=Model.Create(C,{deriveAliases:derive});model.Select(100,1);
 let tx;
 for(const packet of packets)tx=receiver.Accept(packet);
 assert(tx&&!tx.pending);receiver.Commit(tx);
 for(const op of tx.changes)values.set(op.record+':'+op.field,op.value);
 const result=model.Apply(tx,Array.from(new Set(tx.changes.map(x=>x.record))),(r,f)=>values.get(r+':'+f));
 assert(result.known);checks++;
 return result;
}
for(const vector of vectors){
 const result=decode(vector.packets,true),legacy=decode(vector.legacy,false);
 for(const [key,expected] of Object.entries(vector.expected)){
  const actual=key==='minimum'||key==='maximum'?result.snapshot.stat_tooltips.attack[key]:result.snapshot.stat_tooltips.attributes[key];
  const buf=new ArrayBuffer(8),view=new DataView(buf);view.setFloat64(0,actual,false);
  const old=key==='minimum'||key==='maximum'?legacy.snapshot.stat_tooltips.attack[key]:legacy.snapshot.stat_tooltips.attributes[key];
  assert(Object.is(actual,old),'exact equivalence to legacy wire alias '+key);checks++;
  if(!vector.negative_zero){
   assert.equal(view.getUint32(0,false),expected.hi,'exact alias high bits '+key);
   assert.equal(view.getUint32(4,false),expected.lo,'exact alias low bits '+key);checks+=2;
  }else assert(Object.is(actual,0),'existing integer selected projection already normalizes negative zero');
 }
}
console.log(JSON.stringify({status:'INDEPENDENT_EXACT_ALIAS_BITS_PASS',checks,cases:vectors.length,actual_lua_projection:true,actual_js_model:true,native_calls:0}));
