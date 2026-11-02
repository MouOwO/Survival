'use strict';
// Actual production module; synthetic Movie/classes/timers, no native pixels/FPS.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('panorama/src/scripts/custom_game/lottery_cinematic_v1.js','utf8');
const css=fs.readFileSync('panorama/src/styles/custom_game/lottery_cinematic_v1.css','utf8');
function fixture(options={}){
 const nodes=new Map(),jobs=new Map(),history=new Map(),cfg={},messages=[];
 const metrics={created:0,classReads:0,peakJobs:0,canceled:0,stops:0,deletes:0,images:[],lookups:0,commands:[]};
 let now=0,serial=0,syncFailure=false;
 class Panel{
  constructor(type,id,parent){this.type=type;this.id=id;this.parent=parent;this.alive=true;this.visible=true;this.classes=new Set();this.children=[];this.style={};this.events={};if(parent)parent.children.push(this);nodes.set(id,this);metrics.created++;}
  IsValid(){return this.alive}
  AddClass(name){this.classes.add(name)}
  RemoveClass(name){this.classes.delete(name)}
  SetHasClass(name,value){value?this.classes.add(name):this.classes.delete(name)}
  BHasClass(name){metrics.classReads++;if(!this.alive)throw Error('released');return this.classes.has(name)}
  SetPanelEvent(name,fn){this.events[name]=fn}
  SetControls(){} SetRepeat(){} SetPlaybackVolume(){} SetScaling(){}
  SetImage(uri){this.image=uri;metrics.images.push(uri)}
  SetMovie(uri){this.uri=uri;if(syncFailure)throw Error('synthetic synchronous playback failure')}
  Play(){this.played=true}
  Stop(){metrics.stops++}
  DeleteAsync(){metrics.deletes++;this.alive=false;if(nodes.get(this.id)===this)nodes.delete(this.id);for(const child of this.children)child.DeleteAsync(0)}
 }
 const root=new Panel('Panel','LotteryWindow');root.actuallayoutwidth=1600;root.actuallayoutheight=900;
 const $=id=>{metrics.lookups++;return nodes.get(id.slice(1))};
 $.CreatePanel=(type,parent,id)=>new Panel(type,id,parent);
 $.Schedule=(delay,fn)=>{const id=++serial,job={id,due:now+delay,fn};jobs.set(id,job);history.set(id,job);metrics.peakJobs=Math.max(metrics.peakJobs,jobs.size);return id};
 $.CancelScheduled=id=>{assert(jobs.has(id),'Do not repeatedly cancel already-executed timers');metrics.canceled++;jobs.delete(id)};
 $.Msg=(...args)=>messages.push(args.join(''));
 const context={$,GameUI:{CustomUIConfig:()=>cfg},GameEvents:{SendCustomGameEventToServer(){throw Error('Presentation must not draw/grant rewards')}}};
 if(options.tools!==undefined)context.Game={IsInToolsMode:()=>options.tools,AddCommand:(name,fn)=>metrics.commands.push({name,fn})};
 function load(){vm.runInNewContext(source,context,{filename:'lottery_cinematic_v1.js'});return cfg.LotteryCinematic}
 function advance(seconds){const end=now+seconds;for(;;){const next=[...jobs.values()].filter(j=>j.due<=end).sort((a,b)=>a.due-b.due||a.id-b.id)[0];if(!next)break;now=next.due;jobs.delete(next.id);next.fn()}now=end}
 return {cfg,metrics,nodes,jobs,history,root,messages,load,advance,setFailure:value=>syncFailure=value};
}
function failAsync(f){const movie=f.nodes.get('LotteryCinematicMovie');movie.classes.add('MovieError');f.advance(.11);assert(!movie.alive,'Failed native Movie must be retired');return f.nodes.get('LotteryCinematicFallback')}
const rows=[];
// A healthy video retains the original URI/7.05s deadline, no fallback prewarm.
{
 const f=fixture(),api=f.load();let done=0;
 assert(api.Play('summer',[{quality:'ur'}],()=>done++));
 assert.equal(f.nodes.get('LotteryCinematicMovie').uri,'file://{resources}/videos/custom_game/lottery_cinematic_v1/summer.webm');
 f.advance(7);assert.equal(done,0);assert.equal(f.metrics.classReads,70);assert.equal(f.metrics.images.length,0);
 f.advance(.1);assert.equal(done,1);assert.equal(f.jobs.size,0);api.Finish();assert.equal(done,1);assert(f.metrics.peakJobs<=2);
 rows.push({case:'healthy_video',checks:f.metrics.classReads,peak_timers:f.metrics.peakJobs});
}
// Actual async native class failure must enter a CSS timeline before results.
{
 const f=fixture(),api=f.load();let done=0;api.Play('summer',[],()=>done++);
 const oldCallbacks=[...f.history.values()].map(j=>j.fn),before=f.metrics.created;
 const fallback=failAsync(f);assert(fallback.visible);assert(fallback.classes.has('LCFallbackActive'));
 assert.equal(f.metrics.created-before,5);assert.equal(done,0);assert.equal(f.metrics.images[0],'file://{images}/custom_game/lottery_cinematic_v1/summer.png');
 const reads=f.metrics.classReads;f.advance(3.4);assert.equal(done,0);assert.equal(f.metrics.classReads,reads,'No JS frame pump during CSS animation');
 f.advance(.4);assert.equal(done,1);assert.equal(fallback.visible,false);
 oldCallbacks.forEach(fn=>fn());assert.equal(done,1);assert.equal(f.jobs.size,0);assert(f.metrics.peakJobs<=2);
 rows.push({case:'async_error_theme_animation_then_result',new_nodes:5,peak_timers:f.metrics.peakJobs});
}
// Sync decoder failure also animates; same theme reuses texture and five nodes.
{
 const f=fixture(),api=f.load();f.setFailure(true);let done=0;
 assert(api.Play('map',[],()=>done++));f.advance(.02);assert(f.nodes.get('LotteryCinematicFallback').classes.has('LCFallbackActive'));
 f.advance(3.7);assert.equal(done,1);const created=f.metrics.created,images=f.metrics.images.length;
 const reads=f.metrics.classReads;
 api.Play('map',[],()=>done++);f.advance(3.7);assert.equal(done,2);assert.equal(f.metrics.created-created,0,'Known failed pool must not create another native Movie');
 assert.equal(f.metrics.classReads,reads,'Known failed pool needs no decoder polling');
 assert.equal(f.metrics.images.length,images,'Same current texture must not be rewritten');
 api.Play('dragon_knight',[],()=>done++);assert.equal(f.metrics.images.length,images+1);api.Cancel();assert.equal(done,2);
 rows.push({case:'sync_error_reuse_one_current_theme'});
}
// Skip dispatches the existing consumer action once; close cancels without grant.
{
 const f=fixture(),api=f.load();let results=0;f.cfg.SurvivalLottery={SkipCinematic(){results++}};
 api.Play('cultivation',[],()=>results++);failAsync(f);const skip=f.nodes.get('LotteryCinematicSkip');
 skip.events.onactivate();skip.events.onactivate();f.advance(20);assert.equal(results,1);assert.equal(f.jobs.size,0);
 api.Play('map',[],()=>results++);failAsync(f);api.Cancel();f.advance(20);assert.equal(results,1);
 rows.push({case:'skip_once_and_close_no_callback'});
}
// Native child loss retires the one remembered fallback layer before rebuilding.
{
 const f=fixture(),api=f.load();f.setFailure(true);api.Play('summer',[],()=>{});
 const layer=f.nodes.get('LotteryCinematicFallback');api.Cancel();
 f.nodes.get('LotteryFallbackTheme').alive=false;
 api.Play('summer',[],()=>{});assert.equal(layer.alive,false);
 assert.notEqual(f.nodes.get('LotteryCinematicFallback'),layer);
 api.Cancel();assert.equal(f.jobs.size,0);
 rows.push({case:'invalid_fallback_child_retires_old_layer'});
}
// Replacing a play or module invalidates all old callbacks and retires old UI.
{
 const f=fixture(),old=f.load();let first=0,second=0;
 old.Play('map',[],()=>first++);failAsync(f);const stale=[...f.history.values()].map(j=>j.fn);
 old.Play('summer',[],()=>second++);stale.forEach(fn=>fn());assert.equal(first,0);assert.equal(second,0);
 failAsync(f);f.advance(3.8);assert.equal(second,1);
 old.Play('map',[],()=>first++);assert(!f.nodes.has('LotteryCinematicMovie'),'Cached failed map uses theme directly');const oldPending=[...f.jobs.values()].map(j=>j.fn),fresh=f.load();
 fresh.Play('summer',[],()=>second++);oldPending.forEach(fn=>fn());assert.equal(first,0);f.advance(7.1);assert.equal(second,2);assert.equal(f.jobs.size,0);
 rows.push({case:'replacement_dispose_stale_callbacks'});
}
// Only the failed pool is bypassed, and module replacement retries fresh media.
{
 const f=fixture(),api=f.load();let done=0;
 for(const pool of ['map','cultivation','dragon_knight','summer']){
  api.Play(pool,[],()=>done++);assert(f.nodes.has('LotteryCinematicMovie'),'Another pool keeps its original video');
  failAsync(f);f.advance(3.8);
  const created=f.metrics.created,reads=f.metrics.classReads;
  api.Play(pool,[],()=>done++);f.advance(3.8);
  assert.equal(f.metrics.created,created);assert.equal(f.metrics.classReads,reads);assert.equal(f.jobs.size,0);
 }
 assert.equal(done,8);const fresh=f.load();fresh.Play('map',[],()=>done++);
 assert(f.nodes.has('LotteryCinematicMovie'),'New module must not retain a previous game decoder failure');
 f.advance(7.1);assert.equal(done,9);
 rows.push({case:'four_pool_failure_index_repeat_zero_movie_and_poll_module_reset',cached_movie_creations:0,cached_native_class_reads:0});
}
// New direct preview is Tools-only at both registration and invocation.
{
 const regular=fixture({tools:false}),api=regular.load(),created=regular.metrics.created;
 assert.equal(api.PreviewNative('summer'),false);assert.equal(regular.metrics.created,created);
 assert.equal(regular.metrics.commands.filter(c=>c.name.startsWith('lottery_film_native_')).length,0);
 const f=fixture({tools:true});f.load();const native=f.metrics.commands.filter(c=>c.name.startsWith('lottery_film_native_'));
 assert.equal(native.length,4);native.find(c=>c.name.startsWith('lottery_film_native_summer_')).fn();
 assert.equal(f.nodes.has('LotteryCinematicMovie'),false);f.advance(.02);assert(f.nodes.get('LotteryCinematicFallback').classes.has('LCFallbackActive'));
 f.advance(3.7);assert.equal(f.nodes.get('LotteryCinematicSurface').visible,false);assert.equal(f.jobs.size,0);
 rows.push({case:'tools_only_direct_native_preview_without_movie_or_rewards'});
}
// Ordinary-client visual-only previews expose bounded nonsecret phase evidence.
{
 const f=fixture({tools:false}),api=f.load();f.setFailure(true);
 api.Preview('map');f.advance(3.8);
 assert(f.messages.includes('[LOTTERY_CINEMATIC] stage=preview pool=map'));
 assert(f.messages.includes('[LOTTERY_CINEMATIC] stage=fallback pool=map reason=sync_error preview=true'));
 assert(f.messages.includes('[LOTTERY_CINEMATIC] stage=complete pool=map preview=true'));
 const reads=f.metrics.classReads,created=f.metrics.created;
 api.Preview('map');f.advance(3.8);
 assert(f.messages.includes('[LOTTERY_CINEMATIC] stage=fallback pool=map reason=circuit_open preview=true'));
 assert.equal(f.metrics.classReads,reads);assert.equal(f.metrics.created,created);
 assert.equal(f.messages.filter(m=>m==='[LOTTERY_CINEMATIC] stage=complete pool=map preview=true').length,2);
 rows.push({case:'ordinary_zero_transaction_preview_phase_logs_and_cached_theme'});
}
assert(css.includes('#LotteryCinematicMovie #ErrorMessage { visibility:collapse; }'));
for(const name of ['LCThemeReveal','LCHaloReveal','LCRingConverge','LCFlareReveal']){
 assert(css.includes("@keyframes '"+name+"'"));assert(css.includes('animation-name:'+name));
}
assert(css.includes('transform:scale3d(')&&css.includes('animation-duration:3.6s'));
console.log(JSON.stringify({status:'LOTTERY_CINEMATIC_FALLBACK_PASS',scope:'production functions and CSS timeline declarations; not native rendered animation or video playback',cases:rows,native_calls:0,reward_requests:0}));
