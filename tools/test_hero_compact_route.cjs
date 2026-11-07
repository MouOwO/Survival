"use strict";
// Default reads production source; a candidate directory is optional before promotion.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),vm=require('node:vm'),assert=require('node:assert/strict');
const dir=process.argv[2],src=n=>dir?path.resolve(dir,n):path.resolve('panorama/src/scripts/custom_game/common',n);
const W=require(path.resolve('panorama/src/scripts/custom_game/common/compact_wire.js'));
const API=require(src('compact_ui_runtime.js')),Model=require(src('compact_selected_model.js'));
const cfg={};vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/common/ui_static_catalog.js','utf8'),{GameUI:{CustomUIConfig:()=>cfg}});
const C=cfg.SurvivalUICatalog,F=C.FieldIds,R=C.ByKey,schema=W.CompileLookup(C.Data,1);
const luaFixture=dir?path.resolve(dir,'test_hero_compact_route.lua'):path.resolve('scripts/vscripts/tests/test_hero_compact_route.lua');
assert.equal(API.BuildVersion,'compact_ui_runtime_20261107_hero_alias_session_v11','runtime reload must replace the prior capability implementation');
const data=JSON.parse(cp.execFileSync(process.env.LUA51||'C:/Program Files/lua/bin/lua5.1.exe',[luaFixture,...(dir?[dir]:[])],{encoding:'utf8',maxBuffer:8000000}).trim());
let checks=0;function check(v,m){assert.ok(v,m);checks++;}
function setup(id){
 let listener,loadListener,now=0,latest=null,commits=0;const sent=[],errors=[];
 const model=Model.Create(C,{deriveAliases:true});model.Select(100+id,id===0?2:1);
 const rt=API.CreateRuntime({wire:W,catalogue:C.Data,send:(name,p)=>{assert.equal(name,'cw');sent.push(p);},
 subscribe:(name,fn)=>{assert.equal(name,'cw');listener=fn;return 1;},unsubscribe(){},getLoading:()=>({admission_complete:1,profiles_ready:1,session_id:'hero_route_test'}),
 subscribeLoading(fn){loadListener=fn;return 2;},unsubscribeLoading(){},now:()=>now,schedule:(_,fn)=>fn,cancel(){}});
 const view=rt.CreateView('selected',{deriveAliases:true,onError:c=>errors.push(c),onCommit(tx,ids,read){
  const result=model.Apply(tx,ids,read);if(!result.known)return;
  latest=JSON.parse(JSON.stringify(result.snapshot));commits++;
  assert.equal(latest.stat_tooltips.attack.minimum,latest.attack_min||0);
  assert.equal(latest.stat_tooltips.attack.maximum,latest.attack_max===undefined?(latest.attack_min||0):latest.attack_max);
  for(const k of ['strength','agility','intellect'])assert.equal(latest.stat_tooltips.attributes[k],latest[k]||0);
  if(latest.entindex===100+id&&latest.weapon_growth_attack!==undefined){
   const v=latest.weapon_growth_attack/20;
   assert.equal(latest.attack_min,2000000+20*v,'atomic attack/growth tuple');
   assert.equal(latest.strength,900000+5*v,'atomic attribute/growth tuple');
  }
 }});view.Open();
 return{rt,view,model,sent,errors,feed(row){if(row.id===id){now=row.ms;listener(row.packet);}},get latest(){return latest;},get commits(){return commits;}};
}
const clients=Array.from({length:4},(_,id)=>setup(id));
for(let i=0;i<data.final_before_switch;i++)for(const t of clients)t.feed(data.packets[i]);
for(let id=0;id<4;id++){
 const t=clients[id];check(t.latest.refresh_version===data.stable_versions[String(id)],'exact final tail survives stale selection input');
 check(t.latest.entindex===100+id,'owner scope');check(t.errors.length===0,'valid bytes have no parser error');
 const controls=t.sent.filter(p=>W.PeekHeader(p).view===5);let tx;
 const receiver=W.NewReceiver(schema,{schema:1,schema_sha256:C.Data.sha256,session:900+id,epoch:1,view:5});
 for(const p of controls)tx=receiver.Accept(p);
 check(tx.changes.some(o=>o.field===F.types&&o.value===3),'actual runtime explicitly advertises capability 3');
}
const t=clients[0];t.model.Select(900,3);
for(let i=data.final_before_switch;i<data.invisible;i++)t.feed(data.packets[i]);
check(t.latest.entindex===900&&t.latest.attack_min===42,'nonhero selected snapshot is preserved');
t.model.Select(100,4);
for(let i=data.invisible;i<data.switched_back;i++)t.feed(data.packets[i]);
check(t.latest.entindex===100&&t.latest.refresh_version===data.stable_versions['0']+40,'switching back pulls current authority');
const previous=t.latest.refresh_version;
for(let i=data.switched_back;i<data.recovered;i++)t.feed(data.packets[i]);
check(t.latest.refresh_version===previous,'fresh full resync restores identical authority');
// Drop one actual multi-frame transaction fragment. It must not expose a partial tuple.
const lost=setup(0);for(let i=0;i<data.initial_end;i++)lost.feed(data.packets[i]);
const baseline=lost.latest.refresh_version,groups=new Map();
for(let i=data.initial_end;i<data.growth_end;i++){const r=data.packets[i];if(r.id!==0)continue;const h=W.PeekHeader(r.packet);const key=h.epoch+':'+h.revision;const list=groups.get(key)||[];list.push(r);groups.set(key,list);}
const group=[...groups.values()][0];check(group.length>1,'actual multipart delta exists');
group.slice(1).forEach(r=>lost.feed(r));check(lost.latest.refresh_version===baseline,'missing fragment exposes no partial delta');
const before=lost.commits;for(const r of [...groups.values()][1])lost.feed(r);
check(lost.commits===before,'dependent delta cannot bridge a lost predecessor');
check(lost.sent.filter(p=>W.PeekHeader(p).kind==='resync'&&W.PeekHeader(p).view===5).length===1,'loss requests one existing bounded resync');
lost.model.Select(100,4);for(let i=data.switched_back;i<data.recovered;i++)lost.feed(data.packets[i]);
check(lost.latest.refresh_version===previous,'actual server full response recovers missing transaction');
const count=lost.commits;lost.rt.Dispose();for(let i=data.initial_end;i<data.growth_end;i++)lost.feed(data.packets[i]);
check(lost.commits===count,'disposed runtime rejects old packets');
// Legacy mode does not silently derive user-authored/unrelated fixture values.
const legacy=Model.Create(C);legacy.Select(100,4);
check(data.measurements.modern.ops===7&&data.measurements.legacy.ops===12,'only exact aliases removed');
console.log(JSON.stringify({status:'REAL_LUA_TO_JS_COMPACT_HERO_PASS',lua_checks:data.checks,js_checks:checks,
 measurements:data.measurements,four_owner_max_frames_per_16ms:data.max_frames_per_dispatch_window,
 growth_frames:data.growth_end-data.initial_end,growth_simulated_ms:data.growth_simulated_ms,
 native_new_byte_measurement:false,native_fps_measurement:false}));
