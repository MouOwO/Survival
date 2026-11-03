"use strict";
const assert=require('node:assert/strict'),cp=require('node:child_process'),fs=require('node:fs');
const fixture=JSON.parse(cp.execFileSync('C:/Program Files/lua/bin/lua5.1.exe',['scripts/vscripts/tests/test_compact_public_beta.lua','emit'],{encoding:'utf8',maxBuffer:12*1024*1024}).trim());
const api=require('../panorama/src/scripts/custom_game/common/compact_public_beta_model.js'),original=require('../panorama/src/scripts/custom_game/public_beta_gift.js');
const C={fields:fixture.fields,records:fixture.records,auxiliary:{public_beta:fixture.seed}},F=Object.fromEntries(C.fields.map(x=>[x.name,x.id])),R=Object.fromEntries(C.records.map(x=>[x.key,x.id]));
function store(){const rows={};return{put(ops){const changed=new Set();for(const op of ops){const row=rows[op.record]||(rows[op.record]={});if(op.remove)delete row[op.field];else row[op.field]=op.value;changed.add(op.record);}return[...changed];},read:(id,field)=>rows[id]&&rows[id][field]};}
const scope={active:true,ready:true,loading_identity:'unit_test_loading_namespace_A',session:41};
let tests=0;function test(name,fn){fn();tests++;console.log('ok',name);}
test('real archive reward and ACK/profile authority reconstruct original pure model without inventory edits',()=>{
 const memo={},m=api.Create(C,{memo,scope:()=>scope}),s=store(),state=original.Initial();
 let out=m.Apply({full:true},s.put(fixture.initial),s.read);assert(original.Accept(state,out.snapshot));assert.equal(out.snapshot.ticket_id,'special_lottery_ticket');assert.equal(out.snapshot.ticket_count,2);assert(original.Eligible(state));
 assert(original.Begin(state,'beta_original_request_1',0));m.BindIntent(1,'beta_original_request_1');out=m.Apply({full:false},s.put(fixture.claimed),s.read);assert.equal(out.snapshot.claim_result.request_id,'beta_original_request_1');assert(original.Accept(state,out.snapshot));assert.equal(state.confirmed,true);assert.equal(state.pending,null);assert.equal(out.snapshot.inventory,undefined);
 out=m.Apply({full:true},s.put(fixture.next_day),s.read);assert(original.Accept(state,out.snapshot));assert(original.Begin(state,'beta_original_request_2',1));m.BindIntent(2,'beta_original_request_2');
 out=m.Apply({full:false},s.put(fixture.waiting),s.read);assert(original.Accept(state,out.snapshot));assert(state.pending);assert.equal(state.confirmed,false);
 out=m.Apply({full:false},s.put(fixture.ack_only),s.read);assert(original.Accept(state,out.snapshot));assert(state.pending,'ACK without applied authoritative profile cannot clear the intent');
 out=m.Apply({full:false},s.put(fixture.terminal),s.read);assert(original.Accept(state,out.snapshot));assert.equal(state.pending,null);assert.equal(state.confirmed,true);assert.equal(out.snapshot.revision,Number(fixture.revision_exact));
});
test('retained token memo survives UI reload; archived session alias changes are monotonic and retire old payloads',()=>{
 const memo={},m=api.Create(C,{memo,scope:()=>scope}),s=store();m.Apply({full:true},s.put(fixture.initial),s.read);m.BindIntent(1,'beta_retained_request_1');
 const replacement=api.Create(C,{memo,scope:()=>scope});let out=replacement.Apply({full:true},s.put(fixture.recovery),s.read);assert.equal(out.snapshot.claim_result.request_id,'beta_retained_request_1');assert(replacement.HasRequest('beta_retained_request_1'));
 const state=original.Initial();assert(original.Accept(state,out.snapshot));const old=out.snapshot;
 out=replacement.Apply({full:true},s.put(fixture.restarted),s.read);assert(original.Accept(state,out.snapshot));assert.notEqual(out.snapshot.login_key,old.login_key);assert.equal(replacement.HasRequest('beta_retained_request_1'),false);assert.equal(original.Accept(state,{...old,sequence:old.sequence+1000}),false);
});
test('same short transport alias in a different loading world cannot reuse login or nonce bindings',()=>{
 let identity={...scope};const memo={},m=api.Create(C,{memo,scope:()=>identity}),s=store();let out=m.Apply({full:true},s.put(fixture.initial),s.read);const old=out.snapshot.login_key;m.BindIntent(1,'beta_old_world_request');
 identity={...scope,loading_identity:'unit_test_loading_namespace_B'};out=m.Apply({full:true},[],s.read);assert.notEqual(out.snapshot.login_key,old);assert.equal(m.HasRequest('beta_old_world_request'),false);
 identity={...scope,ready:false};assert.throws(()=>m.Apply({full:true},[],s.read),/scope_unknown/);
 identity={...scope,active:false};assert.throws(()=>m.Apply({full:true},[],s.read),/scope_unknown/);
 identity={...scope};s.put([{record:R['public_beta:state'],field:F.public_beta_flags,remove:true}]);assert.throws(()=>m.Apply({full:true},[],s.read),/flags_unknown/);
 s.put([{record:R['public_beta:state'],field:F.public_beta_flags,value:3},{record:R['public_beta:state'],field:F.source_revision_hi,value:2097152}]);assert.throws(()=>m.Apply({full:true},[],s.read),/integer_unknown/);
});
test('shipping controller uses only compact intent, recovers pending across reload and synchronizes legacy pending conservatively',()=>{
 const legacy=fs.readFileSync('tools/test_public_beta_gift_ui.cjs','utf8').replace(/\r\n/g,'\n');let prefix=legacy.slice(0,legacy.indexOf('test("no query'));
 prefix=prefix.replace('function fixture() {','function fixture(configure) {').replace('    load();\n    return {','    if(configure)configure(cfg);load();\n    return {');
 const boot=new Function('require',prefix+'\nreturn fixture;')(require);
 let callback,token=0,opens=0,resyncs=0;const intents=[];
 const f=boot(cfg=>{cfg.SurvivalUICatalog=C;cfg.SurvivalCompactPublicBetaModel=api;cfg.SurvivalCompactRuntime={ScopeIdentity:()=>scope,CreateView(key,cb){assert.equal(key,'public_beta');callback=cb;return{Open(){opens++;return{sent:true};},Close(){},Dispose(){},Resync(){resyncs++;return{sent:true};},SendIntent(action,args){intents.push({action,args});return{sent:true,request_token:++token};}};}};});
 f.admit();f.tick();assert.equal(opens,1);assert.equal(f.queries().length,0);const s=store();callback.onCommit({full:true},s.put(fixture.initial),s.read);assert.equal(f.inspect().open,true);
 f.click();assert.equal(intents.length,1);assert.equal(intents[0].action,'public_beta_claim');assert.deepEqual(Object.keys(intents[0].args),[]);assert.equal(f.claims().length,0);const nonce=f.inspect().pending.request_id;
 f.load();assert.equal(f.inspect().open,false);callback.onCommit({full:true},s.put(fixture.recovery),s.read);assert.equal(f.inspect().pending,null);assert.equal(f.inspect().confirmed,true);assert.equal(intents.length,1,'reload does not replay the consume');
 f.cfg.SurvivalPublicBetaGiftState.pending={request_id:'legacy_unmapped_nonce_1',day_key:fixture.initial_day,started_at:0};f.cfg.SurvivalPublicBetaGiftState.confirmed=false;f.load();
 const sequence=s.read(R['public_beta:state'],F.count);s.put([{record:R['public_beta:state'],field:F.count,value:sequence+1}]);callback.onCommit({full:true},[],s.read);assert.equal(f.inspect().pending,null);assert.equal(f.inspect().confirmed,false,'legacy migration synchronizes claimed without inventing matching success');assert.equal(intents.length,1);
 assert.match(nonce,/^beta_/);f.cfg.SurvivalPublicBetaGift.Dispose();
});
console.log(JSON.stringify({status:'PASS_COMPACT_PUBLIC_BETA_SYNTHETIC_NOT_NATIVE',tests,draft_registry:fixture.draft_registry,metrics:fixture.metrics}));
