"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path"),vm=require("node:vm"),cp=require("node:child_process");
const root=path.resolve(__dirname,".."),api=require("../panorama/src/scripts/custom_game/common/compact_archive_model.js"),wire=require("../panorama/src/scripts/custom_game/common/compact_wire.js"),cfg={};
vm.runInNewContext(fs.readFileSync(path.join(root,"panorama/src/scripts/custom_game/common/ui_static_catalog.js"),"utf8"),{GameUI:{CustomUIConfig:()=>cfg}});
const C=cfg.SurvivalUICatalog,fixture=JSON.parse(cp.execFileSync(process.env.LUA51||"C:/Program Files/lua/bin/lua5.1.exe",["scripts/vscripts/tests/test_compact_archive_projection.lua","emit"],{cwd:root,encoding:"utf8",maxBuffer:8*1024*1024}).trim().split(/\r?\n/).at(-1));
assert.equal(C.Data.sha256,fixture.schema);
const schema=wire.CompileLookup(C,1),binding={schema:1,schema_sha256:C.Data.sha256,session:1,epoch:1,view:101};let tests=0,checkedRows=0;
function test(name,fn){fn();tests++;console.log("ok",name);}
function exactExpected(page){const out=structuredClone(page.expected);for(const f of page.floats||[]){let target=out;for(let n=0;n<f.path.length-1;n++)target=target[Array.isArray(target)?f.path[n]-1:f.path[n]];const b=Buffer.alloc(8);b.writeUInt32BE(f.hi,0);b.writeUInt32BE(f.lo,4);target[Array.isArray(target)?f.path.at(-1)-1:f.path.at(-1)]=b.readDoubleBE(0);}return out;}
function comparable(v){return JSON.parse(JSON.stringify(v));}
function create(category){const model=api.Create(C,category);let last;const client=wire.NewClient(schema,binding,{onCommit(tx,changed,read){last=model.Apply(tx,changed,read);}});return {model,client,result:()=>last};}
test("real 945 rows and every header roundtrip through <=49 native-byte frames",()=>{
 for(const [category,page] of Object.entries(fixture.pages)){const {model,client,result}=create(category);for(const packet of page.packets){assert.ok(packet.d.length<=24);assert.ok(25+packet.d.length<=49);const r=client.Accept(packet);assert.equal(r.error,undefined,category+":"+r.error);}
  assert.deepEqual(comparable(result().snapshot),exactExpected(page),category);checkedRows+=page.expected.rows.length;
  for(let n=0;n<1000;n++){const r=model.Apply({full:false,revision:n+2},[],client.Read);assert.equal(r.metrics.row_visits,0);assert.equal(r.metrics.probability_visits,0);assert.equal(r.metrics.header_visits,0);}
  if(page.delta){const before=result().snapshot.rows,first=before[1];for(const packet of page.delta.packets)assert.equal(client.Accept(packet).error,undefined);assert.equal(result().metrics.row_visits,1);assert.equal(result().snapshot.rows,before);assert.equal(result().snapshot.rows[1],first);assert.deepEqual(comparable(result().snapshot.rows[0]),page.delta.expected);}
  if(page.social_delta){for(const packet of page.social_delta.packets)assert.equal(client.Accept(packet).error,undefined);assert.deepEqual(comparable(result().snapshot),exactExpected(page.social_delta));assert.equal(result().metrics.row_visits,1);assert.ok(result().metrics.probability_visits<=5,"one non-exhausting count change must visit its five-item quality group");}
  model.Dispose();assert.throws(()=>model.Apply({full:false},[],client.Read),/archive_model_disposed/);client.Dispose();
 }assert.equal(checkedRows,945);
});
test("missing inventory remains unknown and has no fabricated owned count",()=>{
 const model=api.Create(C,"commerce_goods"),values=Object.create(null);for(const o of fixture.unknown.ops)(values[o.record]||(values[o.record]={}))[o.field]=o.value;
 const r=model.Apply({full:true,revision:1},Object.keys(values).map(Number),(id,field)=>values[id]&&values[id][field]);assert.equal(r.known,false);assert.deepEqual(comparable(r.snapshot),fixture.unknown.expected);assert.ok(r.snapshot.rows.some(row=>row.count_known===0&&row.count===undefined));
});
test("nonzero pass, levels, manual title, social exhaustion and filtered rows retain real presentation",()=>{
 for(const [category,page] of Object.entries(fixture.variants)){const model=api.Create(C,category),state=Object.create(null);for(const o of page.ops)(state[o.record]||(state[o.record]={}))[o.field]=o.value;
  const r=model.Apply({full:true,revision:1},Object.keys(state).map(Number),(id,field)=>state[id]&&state[id][field]);assert.deepEqual(comparable(r.snapshot),exactExpected(page),"variant:"+category);
 }
});
test("unknown sparse-zero mask and missing full reject before presentation",()=>{
 const model=api.Create(C,"clear"),F=Object.fromEntries(C.Data.fields.map(f=>[f.name,f.id])),rootId=C.ByKey["archive:category:clear"];
 assert.throws(()=>model.Apply({full:false},[],()=>undefined),/archive_full_required/);
 assert.throws(()=>model.Apply({full:true},[rootId],(_,f)=>f===F.known?1:f===F.zero_mask?123:undefined),/archive_zero_mask_unknown/);
});
console.log(JSON.stringify({status:"PASS_COMPACT_ARCHIVE_MODEL_SYNTHETIC_NOT_NATIVE",tests,rows:checkedRows,full_packets:fixture.full_packets,full_native_bytes:fixture.full_bytes,max_native_bytes:fixture.max_native_bytes,delta_packets:fixture.delta_packets,native_calls:0,network_calls:0,timers:0}));
