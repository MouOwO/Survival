"use strict";
const assert=require('node:assert/strict'),cp=require('node:child_process');
const W=require('../panorama/src/scripts/custom_game/common/compact_grid_bulk_wire.js');
const fixture=JSON.parse(cp.execFileSync('C:/Program Files/lua/bin/lua5.1.exe',['scripts/vscripts/tests/test_compact_grid_bulk_wire.lua','emit'],{encoding:'utf8'}).trim());
const raw=Array.from({length:2304},(_,n)=>String.fromCharCode(n*37%256)).join('');
let tests=0;function test(name,fn){fn();tests++;console.log('ok',name);}
test('actual Lua and JS four-fragment packets are byte-identical; all-private binding fields round trip',()=>{
 const actual=W.Encode(fixture.binding,fixture.scope,raw);assert.deepEqual(actual.packets,fixture.packets);assert.equal(actual.report.max_value_bytes,896);
 const r=W.NewReceiver(fixture.binding,{scope:3});let result;for(const p of [...fixture.packets].reverse())result=r.Accept(p);assert.equal(result.raw,raw);assert.equal(result.header.base_revision,1);assert.equal(r.Inspect().complete,true);
 assert.equal(r.Accept(fixture.packets[0]).stale,true);assert.deepEqual(W.Encode(fixture.largest,4294967295,String.fromCharCode(170).repeat(16384)).packets,fixture.large);
});
test('canonical base64/varint, view, scope and actual packet bounds reject malformed frames',()=>{
 const enc=s=>({d:Buffer.from(s,'binary').toString('base64url')}),base=Buffer.from(fixture.packets[0].d,'base64url').toString('binary');
 for(const packet of [{d:fixture.packets[0].d,other:1},{d:'A'.repeat(897)},{d:'='},{d:'AB'},enc(String.fromCharCode(33,128,0)+base.slice(2)),enc(base.slice(0,4)+String.fromCharCode(5)+base.slice(5)),enc(base.slice(0,6)+String.fromCharCode(0)+base.slice(7))])assert.throws(()=>W.Decode(packet));
 assert.throws(()=>W.Encode(fixture.binding,3,'x'.repeat(16385)),/raw_limit/);assert.throws(()=>W.Encode(fixture.binding,3,'\u4e00'),/raw_byte/);
 const bad=enc(String.fromCharCode(33,128,0)+base.slice(2,-2));const lua=cp.execFileSync('C:/Program Files/lua/bin/lua5.1.exe',['scripts/vscripts/tests/test_compact_grid_bulk_wire.lua','decode',bad.d],{encoding:'utf8'});assert.match(lua,/noncanonical_varint/);
});
test('fragment conflict, missing base/owner/scope, bounded memory and failure resync are one-shot',()=>{
 let errors=0;const r=W.NewReceiver(fixture.binding,{scope:3,onError(){errors++;}});assert(r.Accept(fixture.packets[0]).pending);
 const decoded=W.Decode(fixture.packets[0]),bytes=Buffer.from(fixture.packets[0].d,'base64url');bytes[bytes.length-1]^=1;
 assert(r.Accept({d:bytes.toString('base64url')}).error);assert(r.Accept(fixture.packets[1]).error);assert.equal(errors,1);assert.equal(r.Inspect().buffered_bytes,0);
 for(const values of [{session:8},{epoch:3},{revision:2}]){const receiver=W.NewReceiver({...fixture.binding,...values});assert(receiver.Accept(fixture.packets[0]).error);}
 assert(W.NewReceiver(fixture.binding,{scope:4}).Accept(fixture.packets[0]).error);
 const limited=W.NewReceiver(fixture.binding);for(let n=1;n<=32;n++){const body=Buffer.from(fixture.packets[0].d,'base64url');body[7]=n;body[8]=32;const result=limited.Accept({d:body.toString('base64url')});if(result.error)break;}assert(limited.Inspect().failed);assert.equal(limited.Inspect().buffered_bytes,0);
});
test('assembly owns only a temporary deadline; close/dispose/expired generation cancels work',()=>{
 let timer,errors=0,cancelled=0;const r=W.NewReceiver(fixture.binding,{now:()=>0,schedule(ms,fn){assert.equal(ms,5000);timer=fn;return 7;},cancel(){cancelled++;},onError(){errors++;}});
 assert.equal(r.Inspect().timer_active,false);r.Accept(fixture.packets[0]);assert.equal(r.Inspect().timer_active,true);const stale=timer;r.Dispose();stale();assert.equal(errors,0);assert.equal(cancelled,1);assert.equal(r.Inspect().buffered_bytes,0);
 const e=W.NewReceiver(fixture.binding,{now:()=>0,onError(){errors++;}});e.Accept(fixture.packets[0]);assert(e.Expire(5000).error);assert.equal(errors,1);assert.equal(e.Inspect().timer_active,false);
});
console.log(JSON.stringify({status:'PASS_GRID_BULK_CODEC_SYNTHETIC_NOT_NATIVE',tests,report:fixture.report}));
