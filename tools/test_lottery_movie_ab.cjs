'use strict';
// Control-flow/finite-work checks only. Native video must be visually reviewed.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),path=require('node:path');
const root=process.cwd(),source=fs.readFileSync('panorama/src/scripts/custom_game/lottery_cinematic_v1.js','utf8');
const layout=fs.readFileSync('panorama/src/layout/custom_game/lottery_movie_ab_direct.xml','utf8');
const movieURI='file://{resources}/videos/custom_game/lottery_cinematic_v1/map.webm';
const layoutURI='file://{resources}/layout/custom_game/lottery_movie_ab_direct.xml';
assert.match(layout,/<Panel\s[^>]*>[\s\S]*<MoviePanel\s/);
assert.match(layout,/id="LotteryCinematicMovie"/);assert(layout.includes('src="'+movieURI+'"'));assert(layout.includes('autoplay="onload"'));
for(const relative of ['scripts/custom_game/lottery_cinematic_v1.js','layout/custom_game/lottery_movie_ab_direct.xml']){
 const a=fs.readFileSync(path.join(root,'panorama/src',relative),'utf8').replace(/\r\n/g,'\n');
 const b=fs.readFileSync(path.resolve(root,'../../../content/dota_addons/Survival/panorama',relative),'utf8').replace(/\r\n/g,'\n');
 assert.equal(a,b,'Both repository source mirrors must match');
}
function fixture(options={}){
 const nodes=new Map(),jobs=new Map(),logs=[],commands=[],cfg={},history=[];
 const metrics={created:0,lookups:0,classReads:0,layouts:0,images:0,peakJobs:0,media:[],skip:0};let now=0,serial=0;
 class Panel{
  constructor(type,parent,id){Object.assign(this,{type,parent,id,alive:true,visible:true,enabled:true,style:{},children:[],events:{},classes:new Set()});if(parent)parent.children.push(this);nodes.set(id,this);metrics.created++;}
  IsValid(){return this.alive}AddClass(x){this.classes.add(x)}RemoveClass(x){this.classes.delete(x)}SetHasClass(x,v){v?this.AddClass(x):this.RemoveClass(x)}
  BHasClass(x){metrics.classReads++;return x==='MovieError'&&this.type==='Movie'&&!!options.nativeError}
  SetPanelEvent(k,v){this.events[k]=v}SetControls(){}SetRepeat(){}SetPlaybackVolume(){}SetScaling(){}Stop(){}
  SetMovie(uri){this.uri=uri;metrics.media.push(uri);if(options.setupFailure)throw Error('synthetic failure')}
  Play(){this.played=true}SetImage(){metrics.images++}
  DeleteAsync(){this.alive=false;this.children.forEach(c=>c.DeleteAsync());if(nodes.get(this.id)===this)nodes.delete(this.id)}
  BLoadLayout(uri){metrics.layouts++;assert.equal(uri,layoutURI);if(options.layoutFailure)return false;new Panel('MoviePanel',this,'LotteryCinematicMovie').uri=movieURI;return true}
  FindChildTraverse(id){metrics.lookups++;return this.children.find(c=>c.id===id)||null}
 }
 const window=new Panel('Panel',null,'LotteryWindow');window.actuallayoutwidth=1280;window.actuallayoutheight=720;
 new Panel('Button',window,'LotteryRefreshButton');
 const $=name=>nodes.get(name.slice(1));$.CreatePanel=(t,p,id)=>new Panel(t,p,id);
 $.Schedule=(delay,fn)=>{const id=++serial;const job={at:now+delay,fn};jobs.set(id,job);history.push(job);metrics.peakJobs=Math.max(metrics.peakJobs,jobs.size);return id};
 $.CancelScheduled=id=>jobs.delete(id);$.Msg=line=>logs.push(line);
 cfg.SurvivalLottery={Open(){throw Error('AB cannot open/read/draw')},SkipCinematic(){metrics.skip++}};
 const context={$,GameUI:{CustomUIConfig:()=>cfg},Game:{IsInToolsMode:()=>false,AddCommand:(name,fn)=>commands.push({name,fn})},GameEvents:{SendCustomGameEventToServer(){throw Error('No server calls')}}};
 function load(){vm.runInNewContext(source,context);return cfg.LotteryCinematic}
 function advance(seconds){const end=now+seconds;for(;;){const next=[...jobs.entries()].filter(([,j])=>j.at<=end).sort((a,b)=>a[1].at-b[1].at)[0];if(!next)break;now=next[1].at;jobs.delete(next[0]);next[1].fn()}now=end}
 return {api:load(),load,nodes,jobs,logs,commands,metrics,history,advance};
}
const cases=[];
for(const mode of ['wrapper','direct']){
 const f=fixture();assert.equal(f.commands.filter(c=>c.name.startsWith('lottery_film_ab_')).length,2);
 assert(f.api.PreviewPlayerAB(mode));const player=f.nodes.get('LotteryCinematicMovie');assert.equal(player.type,mode==='wrapper'?'Movie':'MoviePanel');assert.equal(player.uri,movieURI);
 const creates=f.metrics.created,lookups=f.metrics.lookups;f.advance(7.2);
 assert.equal(f.metrics.created,creates);assert.equal(f.metrics.lookups,lookups);assert.equal(f.logs.filter(l=>l.includes('stage=sample')).length,6);
 assert.equal(f.metrics.images,0);assert.equal(f.jobs.size,0);assert.equal(player.alive,false);assert(!f.nodes.has('LotteryMovieABHost'));
 assert(f.logs.some(l=>l.includes('stage=complete')&&l.includes('outcome=visual_review_required')));
 assert.equal(f.metrics.classReads,mode==='wrapper'?6:0);assert.equal(f.metrics.lookups,mode==='direct'?1:0);assert(f.metrics.peakJobs<=7);
 cases.push({mode,samples:6,native_class_reads:f.metrics.classReads,initial_child_lookup:f.metrics.lookups,peak_timers:f.metrics.peakJobs});
}
{
 const f=fixture({nativeError:true});f.api.PreviewPlayerAB('wrapper');f.advance(8);
 assert.equal(f.logs.filter(l=>l.includes('stage=error')).length,1);assert.equal(f.metrics.images,0);
 assert(f.logs.some(l=>l.includes('outcome=native_error fallback=false')));cases.push({case:'native_error_logged_once_no_fallback'});
}
for(const options of [{setupFailure:true},{layoutFailure:true}]){
 const f=fixture(options);assert.equal(f.api.PreviewPlayerAB(options.layoutFailure?'direct':'wrapper'),false);
 assert.equal(f.jobs.size,0);assert(!f.nodes.has('LotteryMovieABHost'));assert.equal(f.metrics.images,0);
 assert(f.logs.some(l=>l.includes('outcome=setup_error')));
}
cases.push({case:'setup_failure_cleans_host_and_never_claims_video_success'});
{
 const f=fixture();const initial=f.metrics.created;assert.equal(f.api.PreviewPlayerAB('https://example.invalid'),false);assert.equal(f.metrics.created,initial);
 f.nodes.get('LotteryRefreshButton').enabled=false;assert.equal(f.api.PreviewPlayerAB('direct'),false);f.nodes.get('LotteryRefreshButton').enabled=true;
 f.api.PreviewPlayerAB('direct');const first=f.nodes.get('LotteryCinematicMovie');assert.equal(f.api.PreviewPlayerAB('wrapper'),false);assert.equal(first,f.nodes.get('LotteryCinematicMovie'));
 const stale=f.history.map(x=>x.fn);f.api.Cancel();f.api.PreviewPlayerAB('wrapper');stale.forEach(fn=>fn());assert(f.nodes.get('LotteryCinematicMovie').alive);f.advance(8);
 assert.equal(f.logs.filter(l=>l.includes('stage=complete')).length,1);assert.equal(f.metrics.images,0);cases.push({case:'invalid_busy_reentry_and_stale_generation_safe'});
}
{
 const f=fixture();f.api.PreviewPlayerAB('direct');f.nodes.get('LotteryCinematicSkip').events.onactivate();f.advance(9);
 assert.equal(f.metrics.skip,0);assert.equal(f.jobs.size,0);assert(f.logs.some(l=>l.includes('stage=aborted')));assert(!f.logs.some(l=>l.includes('stage=complete')));
 f.api.PreviewPlayerAB('direct');const stale=f.history.map(x=>x.fn);f.load();stale.forEach(fn=>fn());assert.equal(f.jobs.size,0);assert(!f.nodes.has('LotteryMovieABHost'));
 cases.push({case:'skip_dispose_retire_without_result_consumer'});
}
console.log(JSON.stringify({status:'LOTTERY_MOVIE_AB_CONTROL_FLOW_PASS',cases,native_video_evidence:false,reward_requests:0,scope:'fixed candidate diagnostic only; defaults unchanged, native visual comparison pending'}));
