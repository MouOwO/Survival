"use strict";
const assert=require('node:assert/strict'),cp=require('node:child_process'),fs=require('node:fs'),vm=require('node:vm');
const api=require('../panorama/src/scripts/custom_game/common/compact_production_model.js');
const fixture=JSON.parse(cp.execFileSync('C:/Program Files/lua/bin/lua5.1.exe',['scripts/vscripts/tests/test_compact_production.lua','emit'],{encoding:'utf8',maxBuffer:16*1024*1024}).trim());
const C={fields:fixture.fields,records:fixture.records,auxiliary:{production:fixture.seed}};
const F=Object.fromEntries(C.fields.map(row=>[row.name,row.id])),R=Object.fromEntries(C.records.map(row=>[row.key,row.id]));
function store(){const data={};return{put(ops){const ids=new Set();for(const op of ops){const row=data[op.record]||(data[op.record]={});if(op.remove)delete row[op.field];else row[op.field]=op.value;ids.add(op.record);}return[...ids];},read:(id,field)=>data[id]&&data[id][field]};}
let tests=0;function test(name,fn){fn();tests++;console.log('ok',name);}
test('actual tracker and serial queue reconstruct all eight training options',()=>{
 const m=api.Create(C),s=store();m.Select(10,1);const result=m.Apply({full:true},s.put(fixture.initial_ops),s.read);
 assert.equal(result.known,true);assert.equal(result.snapshot.training.options.length,8);
 for(let n=0;n<8;n++){const actual=result.snapshot.training.options[n],expected=fixture.initial_expected.training.options[n];for(const key of Object.keys(expected))assert.deepEqual(actual[key],expected[key],`option ${n} ${key}`);}
 const before=m.Inspect().record_visits;for(let n=0;n<1000;n++)m.Apply({full:false},[],s.read);assert.equal(m.Inspect().record_visits,before);
});
test('authoritative receipt retains original local request ID and current queue state',()=>{
 const m=api.Create(C),s=store();m.Select(10,1);m.Apply({full:true},s.put(fixture.initial_ops),s.read);m.BindIntent(1,'production_train_original',10);
 const result=m.Apply({full:false},s.put(fixture.trained_ops),s.read);assert.equal(result.receipts.length,1);const ack=result.receipts[0];assert.equal(ack.request_id,'production_train_original');assert.equal(ack.operation,'worker_train');assert.equal(ack.success,1);assert.equal(ack.training,result.snapshot.training);
 const expected=fixture.trained_expected.training;for(const key of ['queue_revision','queue_capacity','queue_count','blocked_reason'])assert.equal(ack.training[key],expected[key]);
 for(const key of ['training_id','level','name','duration','started_at','finish_at'])assert.equal(ack.training.active_job[key],expected.active_job[key],key);
 assert.equal(m.Apply({full:true},[],s.read).receipts.length,0,'replayed full does not repeat receipt');
});
test('private research tooltip prices, prerequisites, queue and exact IEEE64 values survive',()=>{
 const m=api.Create(C),s=store();m.Select(30,2);const result=m.Apply({full:true},s.put(fixture.research_ops),s.read);assert.equal(result.known,true);
 const expected=fixture.research_expected.research,actual=result.snapshot.research;
 for(const name of Object.keys(expected.abilities_by_name)){const a=actual.abilities_by_name[name],b=expected.abilities_by_name[name];assert.ok(a,name);for(const key of ['available','prerequisite_met','current_level','next_level','max_level','research_status_code','status_text','cost_wood','cost_gold','upgrade_description','research_effect_description','current_effect_text','next_effect_text','research_effect_current','research_effect_next','fields','auto_research_available','auto_research_enabled'])assert.deepEqual(a[key],b[key],`${name}.${key}`);}
 for(const key of ['started_at','finish_at','duration','next_start_at','researching','queue_count','queue_capacity','research_group','target_level'])assert.equal(actual[key],expected[key],key);
 assert.equal(actual.queued.length,1);assert.equal(actual.queued[0].technology_group,expected.queued[0].technology_group);
 assert.equal(typeof actual.active_job.job_id,'number','UI cancellation uses a scoped handle, not truncated business string');
});
test('A-B-A rejects prior selection and four owners have separate dynamic state',()=>{
 const models=Array.from({length:4},()=>api.Create(C)),stores=models.map(()=>store());
 for(let n=0;n<4;n++){models[n].Select(10,1);models[n].Apply({full:true},stores[n].put(fixture.initial_ops),stores[n].read);}
 models[0].Select(10,3);assert.equal(models[0].Apply({full:true},[],stores[0].read).stale,true);
 assert.equal(models[1].Snapshot().entindex,10);assert.equal(models[1].Inspect().selection,1);
 const before=models[1].Inspect().record_visits;models[2].Select(30,2);models[2].Apply({full:true},stores[2].put(fixture.research_ops),stores[2].read);assert.equal(models[1].Inspect().record_visits,before);
});
test('actual production controller waits for ready, sends latest selection once and binds compact train receipt',()=>{
 const nodes={},callbacks={},native=[],inputs=[],intents=[];let unit=10,ready=false,viewCallback,open=false,token=0,writes=0;
 function panel(type,parent,id){const p={id,style:new Proxy({},{set(target,key,value){writes++;target[key]=value;return true;}}),children:[],handlers:{},classes:new Set(),IsValid:()=>true,FindChildTraverse:key=>nodes[key],AddClass(n){this.classes.add(n);},SetHasClass(n,v){writes++;v?this.classes.add(n):this.classes.delete(n);},RemoveAndDeleteChildren(){this.children=[];},SetPanelEvent(n,fn){this.handlers[n]=fn;},SetImage(u){writes++;this.image=u;}};
  let shown=true,label='';Object.defineProperties(p,{visible:{get:()=>shown,set(v){writes++;shown=v;}},text:{get:()=>label,set(v){writes++;label=v;}}});if(parent)parent.children.push(p);if(id)nodes[id]=p;return p;}
 const ctx=panel('Panel',null,'ctx');panel('Panel',ctx,'SurvivalProductionPanel');panel('Panel',ctx,'SurvivalResearchAutoMarkers');
 const cfg={SurvivalUICatalog:C,SurvivalCompactProductionModel:api,SurvivalSelectionResolver:{ResolveDisplayUnit:()=>unit},SurvivalUILayers:{Top:()=>false},SurvivalCompactRuntime:{
  CreateView(key,cb){assert.equal(key,'production');viewCallback=cb;return{
   Open(){open=true;},Close(){open=false;},Dispose(){open=false;},Inspect:()=>({ready}),
   SendInput(code,args){assert.ok(open);inputs.push({code,args});return{sent:true};},
   SendIntent(action,args){intents.push({action,args});return{sent:true,request_token:++token};}
  };}
 }};
 const $=()=>{};$.GetContextPanel=()=>ctx;$.CreatePanel=panel;$.DispatchEvent=()=>{};$.Schedule=()=>{};
 const env={$,GameUI:{CustomUIConfig:()=>cfg},Game:{GetLocalPlayerID:()=>0,GetGameTime:()=>100.125},Players:{GetLocalPlayerPortraitUnit:()=>unit},Entities:{GetUnitName:id=>id===10?'building_main_city':id===30?'building_advanced_research_lab':'hero'},CustomNetTables:{GetTableValue:()=>({})},GameEvents:{Subscribe:(name,fn)=>callbacks[name]=fn,SendCustomGameEventToServer:(...args)=>native.push(args)}};
 const source=fs.readFileSync('panorama/src/scripts/custom_game/production_progress.js','utf8');vm.runInNewContext(source,env);
 const geometry={x:350,y:700,scale:.5,height:330,minimapSize:220,heroWidth:453,centerWidth:498},refresh=()=>cfg.SurvivalProductionHUD.Refresh(geometry,unit,true,[]);
 refresh();unit=30;refresh();unit=10;refresh();assert.equal(inputs.length,0);assert.equal(native.length,0);
 ready=true;const bootstrap=store();bootstrap.put([{record:R['production:state'],field:F.production_entity,value:0},{record:R['production:state'],field:F.production_selection,value:1},{record:R['production:state'],field:F.known,value:0}]);viewCallback.onCommit({full:true},[R['production:state']],bootstrap.read);
 assert.equal(inputs.length,1);assert.equal(inputs[0].args.production_entity,10);assert.equal(inputs[0].args.production_selection,3);
 const s=store(),initial=fixture.initial_ops.map(op=>op.record===R['production:state']&&op.field===F.production_selection?{...op,value:3}:op);
 viewCallback.onCommit({full:true},s.put(initial),s.read);assert.equal(nodes.SurvivalProductionPanel.visible,true);
 const beforeWrites=writes;for(let n=0;n<1000;n++)refresh();assert.equal(inputs.length,1);assert.equal(native.length,0);assert.equal(writes,beforeWrites,'steady paused/idle HUD refresh has zero production native writes');
 nodes.ProductionTrainingSlot0.handlers.onactivate();assert.equal(intents.length,1);assert.equal(intents[0].action,'production_train');assert.equal(intents[0].args.entity,10);assert.equal(intents[0].args.selection,3);assert.equal(intents[0].args.definition_record,R['production:training:train_lumberjack_01']);
 const trained=fixture.trained_ops.map(op=>op.field===F.production_selection?{...op,value:3}:op);viewCallback.onCommit({full:false},s.put(trained),s.read);assert.equal(cfg.SurvivalProductionHUD.Inspect().snapshot.training.active_job.training_id,'train_lumberjack_01');
 const before=cfg.SurvivalProductionSelectionSerial;vm.runInNewContext(source,env);refresh();assert.ok(cfg.SurvivalProductionSelectionSerial>before,'script reload never reuses the prior server selection generation');assert.equal(native.length,0);
});
console.log(`PASS ${tests} production model tests (${fixture.draft_registry?'explicit draft metadata; final immutable catalogue retest required':'actual runtime registry'})`);
console.log(JSON.stringify({status:'synthetic_calibrated_not_native',metrics:fixture.metrics}));
