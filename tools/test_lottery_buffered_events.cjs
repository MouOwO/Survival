'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const candidate=process.env.SURVIVAL_MOVIE_CANDIDATE_DIR;
const source=fs.readFileSync(candidate?path.join(candidate,'lottery_cinematic_v1.js'):'panorama/src/scripts/custom_game/lottery_cinematic_v1.js','utf8'),I='VideoPlayerInitalized',E='VideoPlayerEnded';
const layoutDirectory=candidate||'panorama/src/layout/custom_game';
function fixture(options={}){
 const nodes=new Map(),jobs=new Map(),history=[],logs=[],commands=[],cfg={},metrics={classReads:0,registrations:0,layouts:0,lookups:0,images:0,peakJobs:0,network:0,mediaSet:0};
 let now=0,serial=0,layoutMode='ok',idle=true,releases=0;
 class Panel{
  constructor(type,parent,id){Object.assign(this,{type,parent,id,alive:true,visible:true,style:{},children:[],events:{},nativeEvents:{},classes:new Set()});if(parent)parent.children.push(this);nodes.set(id,this)}
  IsValid(){return this.alive}AddClass(x){this.classes.add(x)}RemoveClass(x){this.classes.delete(x)}SetHasClass(x,v){v?this.classes.add(x):this.classes.delete(x)}
  BHasClass(x){metrics.classReads++;return this.classes.has(x)}SetPanelEvent(k,v){this.events[k]=v}
  SetControls(){}SetRepeat(){}SetPlaybackVolume(){}SetScaling(){}SetImage(uri){this.uri=uri;metrics.images++}
  SetMovie(uri){metrics.mediaSet++;this.uri=uri}Play(){}Stop(){}
  DeleteAsync(){this.alive=false;this.children.forEach(c=>c.DeleteAsync());if(nodes.get(this.id)===this)nodes.delete(this.id)}
  BLoadLayout(uri){
   metrics.layouts++;if(layoutMode==='throw')throw Error('layout');if(layoutMode==='false')return false;if(layoutMode==='missing')return true;
   const name=uri.split('/').at(-1);assert(/^lottery_movie_(map|cultivation|dragon_knight|summer|bad_media_probe)\.xml$/.test(name));
   const xml=fs.readFileSync(path.join(layoutDirectory,name),'utf8');assert(/<Panel\s[^>]*>[\s\S]*<MoviePanel\s/.test(xml));assert(xml.includes('loadbehavior="buffer-async"')&&xml.includes('autoplay="onload"'));
   const child=new Panel('MoviePanel',this,'LotteryCinematicMovie');child.uri=/src="([^"]+)"/.exec(xml)[1];return true;
  }
  FindChildTraverse(id){metrics.lookups++;return this.children.find(p=>p.id===id)||null}
 }
 const root=new Panel('Panel',null,'LotteryWindow');root.actuallayoutwidth=1600;root.actuallayoutheight=900;
 const $=id=>nodes.get(id.slice(1));$.CreatePanel=(t,p,id)=>new Panel(t,p,id);$.Msg=x=>logs.push(x);
 $.Schedule=(delay,fn)=>{const id=++serial,j={id,at:now+delay,fn};jobs.set(id,j);history.push(j);metrics.peakJobs=Math.max(metrics.peakJobs,jobs.size);return id};
 $.CancelScheduled=id=>{assert(jobs.has(id),'Never cancel an already executed deadline');jobs.delete(id)};
 $.RegisterEventHandler=(name,panel,callback)=>{assert([I,E].includes(name));assert.equal(panel.type,'MoviePanel');metrics.registrations++;panel.nativeEvents[name]=callback;if(options.syncEnd&&name===E)callback({});};
 $.RegisterForUnhandledEvent=()=>{throw Error('Global media event handler forbidden')};
 cfg.SurvivalLottery={CanPreviewCinematic:()=>idle,OpenForCinematicPreview(){idle=false;return{Release(){idle=true;releases++}}}};
 const env={$,Date:{now:()=>now*1000},GameUI:{CustomUIConfig:()=>cfg},Game:{IsInToolsMode:()=>false,AddCommand:(n,fn)=>commands.push({n,fn})},GameEvents:{SendCustomGameEventToServer(){metrics.network++;throw Error('No network in presentation')}}};
 function load(){vm.runInNewContext(source,env);return cfg.LotteryCinematic}
 function advance(seconds){const end=now+seconds;for(;;){const j=[...jobs.values()].filter(x=>x.at<=end).sort((a,b)=>a.at-b.at||a.id-b.id)[0];if(!j)break;now=j.at;jobs.delete(j.id);j.fn()}now=end}
 function emit(name,panel=nodes.get('LotteryCinematicMovie')){assert(panel&&panel.nativeEvents[name]);panel.nativeEvents[name]({})}
 return {api:load(),load,advance,emit,nodes,jobs,history,logs,commands,cfg,metrics,setLayoutMode:x=>layoutMode=x,get releases(){return releases},get idle(){return idle}};
}
const rows=[];const row=name=>rows.push(name);
{
 const f=fixture();let done=0;
 for(const pool of ['map','cultivation','dragon_knight','summer']){
  assert(f.api.Play(pool,[],()=>done++));const m=f.nodes.get('LotteryCinematicMovie');assert.equal(m.uri,'file://{resources}/videos/custom_game/lottery_cinematic_v1/'+pool+'.webm');assert(!f.nodes.has('LotteryCinematicFallback'));
  assert.equal(f.jobs.size,2);f.emit(I);assert.equal(f.jobs.size,1);f.advance(7);const before=done;f.emit(E);f.emit(E,m);assert.equal(done,before+1);assert.equal(f.jobs.size,0);assert(!m.alive);f.api.Finish();assert.equal(done,before+1);
 }
 assert.equal(f.metrics.registrations,8);assert.equal(f.metrics.lookups,4);assert.equal(f.metrics.classReads,0);assert.equal(f.metrics.images,0);assert.equal(f.metrics.mediaSet,0);assert.equal(f.metrics.network,0);assert(f.metrics.peakJobs<=2);row('four_real_xml_pools_two_child_events_no_polling_no_normal_fallback');
}
{
 const f=fixture();let done=0;f.api.Play('map',[],()=>done++);const dead=f.nodes.get('LotteryCinematicMovie');f.emit(E);assert(!dead.alive);assert(!f.nodes.has('LotteryCinematicFallback'));assert.equal(done,1);f.emit(I,dead);f.emit(E,dead);f.advance(20);assert.equal(done,1);assert.equal(f.jobs.size,0);assert(f.logs.some(x=>x.includes('reason=ended_before_initialized')));row('native_bad_media_returns_received_results_immediately_once');
}
{
 const f=fixture();let done=0;f.api.Play('summer',[],()=>done++);f.emit(I);f.advance(2);f.emit(E);assert.equal(done,1);assert.equal(f.metrics.images,0);assert(f.logs.some(x=>x.includes('reason=early_end')));row('premature_end_returns_results_without_second_animation');
}
for(const kind of ['startup','completion','deleted_child']){
 const f=fixture();let done=0;f.api.Play('map',[],()=>done++);if(kind==='completion')f.emit(I);if(kind==='deleted_child')f.nodes.get('LotteryCinematicMovie').DeleteAsync();
 f.advance(kind==='completion'?12:5);assert(!f.nodes.has('LotteryCinematicFallback'));assert.equal(done,1);assert.equal(f.jobs.size,0);row(kind+'_watchdog_returns_results_without_deadlock');
}
{
 const f=fixture();let done=0;f.api.Play('map',[],()=>done++);f.advance(4.8);f.emit(I);f.advance(7);f.emit(E);assert.equal(done,1);assert.equal(f.metrics.images,0);assert.equal(f.jobs.size,0);row('late_but_valid_initialization_finishes_before_absolute_deadline');
}
for(const failure of ['false','throw','missing']){
 const f=fixture();f.setLayoutMode(failure);let done=0;assert(f.api.Play('map',[],()=>done++));assert(!f.nodes.has('LotteryBufferedMovieHost'));assert.equal(done,1);assert.equal(f.jobs.size,0);assert.equal(f.metrics.images,0);f.setLayoutMode('ok');f.api.Play('map',[],()=>done++);f.emit(I);f.advance(7);f.emit(E);assert.equal(done,2);row('setup_'+failure+'_immediate_result_and_next_draw_recovers');
}
{
 const f=fixture({syncEnd:true});let done=0;assert(f.api.Play('map',[],()=>done++));assert(!f.nodes.has('LotteryCinematicFallback'));assert.equal(done,1);assert.equal(f.jobs.size,0);assert.equal(f.metrics.images,0);f.advance(20);assert.equal(done,1);row('synchronous_end_during_registration_completes_once_no_watchdogs');
}
{
 const f=fixture();let done=0,last=null;
 for(let i=0;i<3;i++){f.api.Play('map',Array.from({length:10},()=>({quality:'sr'})),()=>done++);const m=f.nodes.get('LotteryCinematicMovie');assert.notEqual(m,last);f.emit(I);f.advance(7);f.emit(E);assert.equal(done,i+1);assert.equal(f.jobs.size,0);last=m}row('three_consecutive_presentations_fresh_native_children');
}
{
 const f=fixture();let first=0,second=0,skips=0;f.cfg.SurvivalLottery.SkipCinematic=()=>skips++;
 f.api.Play('map',[],()=>first++);const old=f.nodes.get('LotteryCinematicMovie'),stale=f.history.map(j=>j.fn);const skip=f.nodes.get('LotteryCinematicSkip');skip.events.onactivate();skip.events.onactivate();f.emit(I,old);f.emit(E,old);stale.forEach(fn=>fn());assert.equal(skips,1);assert.equal(first,0);
 f.api.Play('summer',[],()=>second++);f.emit(I);f.emit(E,old);f.advance(7);f.emit(E);assert.equal(second,1);f.api.Play('map',[],()=>first++);const old2=f.nodes.get('LotteryCinematicMovie');f.api=f.load();f.emit(I,old2);f.emit(E,old2);f.advance(20);assert.equal(first,0);assert.equal(f.jobs.size,0);row('skip_cancel_reload_stale_native_callbacks_and_timers');
}
{
 const f=fixture();assert(f.api.PreviewBufferedDecoderProbe());assert(f.nodes.get('LotteryCinematicMovie').uri.endsWith('/bad_media_probe.webm'));assert.equal(f.api.Preview('map'),false);f.emit(E);assert.equal(f.releases,1);assert(f.idle);assert.equal(f.jobs.size,0);assert.equal(f.metrics.images,0);assert(f.logs.some(x=>x.includes('action=return_to_preview_idle')));assert(!f.logs.some(x=>x.includes('action=return_to_received_results')));
 f.api.Preview('map');f.api.Cancel();assert.equal(f.releases,2);f.api.Preview('map');f.api.Dispose();assert.equal(f.releases,3);assert.equal(f.jobs.size,0);row('preview_bad_media_cancel_dispose_release_lease_once');
}
{
 const f=fixture();assert(f.api.PreviewDecoderProbe());const m=f.nodes.get('LotteryCinematicMovie');assert.equal(m.type,'Movie');assert.equal(m.uri,'file://{resources}/styles/custom_game/lottery_cinematic_v1.vcss_c');m.classes.add('MovieError');f.advance(.11);f.advance(3.7);assert(f.logs.some(x=>x.includes('native_class=MovieError')));assert.equal(f.jobs.size,0);row('legacy_wrapper_probe_preserved');
}
console.log(JSON.stringify({status:'EVENT_CANDIDATE_LIFECYCLE_PASS',cases:rows,count:rows.length,native_test:false,production_acceptance:false}));
