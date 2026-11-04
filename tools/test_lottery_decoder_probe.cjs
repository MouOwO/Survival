'use strict';
// Synthetic API control-flow checks only. No native decoder evidence is created.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),path=require('node:path');
const base=process.cwd(),relative='panorama/src/scripts/custom_game/lottery_cinematic_v1.js';
const source=fs.readFileSync(path.join(base,relative),'utf8');
assert.equal(source.replace(/\r\n/g,'\n'),fs.readFileSync(path.resolve(base,'../../../content/dota_addons/Survival/panorama/scripts/custom_game/lottery_cinematic_v1.js'),'utf8').replace(/\r\n/g,'\n'));
const URI='file://{resources}/styles/custom_game/lottery_cinematic_v1.vcss_c';
function fixture(options={}){
 const nodes=new Map(),jobs=new Map(),logs=[],commands=[],cfg={},metrics={media:[],fallbacks:0,skip:0,peak:0};let time=0,serial=0;
 class Panel{
  constructor(type,parent,id){this.type=type;this.parent=parent;this.id=id;this.visible=true;this.enabled=true;this.alive=true;this.style={};this.classes=new Set();this.children=[];this.events={};if(parent)parent.children.push(this);nodes.set(id,this)}
  IsValid(){return this.alive}AddClass(x){this.classes.add(x)}RemoveClass(x){this.classes.delete(x)}SetHasClass(x,v){v?this.AddClass(x):this.RemoveClass(x)}
  BHasClass(x){if(this.type==='Movie'&&this.uri===URI&&options.classReadThrows)throw Error('synthetic class getter');return x==='MovieError'&&this.uri===URI&&!!options.asyncFailure}
  SetPanelEvent(k,v){this.events[k]=v}SetControls(){}SetRepeat(){}SetPlaybackVolume(){}SetScaling(){}
  SetMovie(uri){this.uri=uri;metrics.media.push(uri);if(uri===URI&&options.syncFailure)throw Error('synthetic API failure')}
  Play(){this.played=true}Stop(){}DeleteAsync(){this.alive=false;this.children.forEach(p=>p.DeleteAsync());if(nodes.get(this.id)===this)nodes.delete(this.id)}
  SetImage(){metrics.fallbacks++}
 }
 const root=new Panel('Panel',null,'LotteryWindow');root.actuallayoutwidth=1280;root.actuallayoutheight=720;
 new Panel('Button',root,'LotteryRefreshButton');
 const $=id=>nodes.get(id.slice(1));$.CreatePanel=(type,parent,id)=>new Panel(type,parent,id);
 $.Schedule=(delay,fn)=>{const id=++serial;jobs.set(id,{at:time+delay,fn});metrics.peak=Math.max(metrics.peak,jobs.size);return id};
 $.CancelScheduled=id=>jobs.delete(id);$.Msg=message=>logs.push(message);
 cfg.SurvivalLottery={SkipCinematic(){metrics.skip++},Open(){throw Error('Probe must not open/read/draw')}};
 vm.runInNewContext(source,{$,GameUI:{CustomUIConfig:()=>cfg},Game:{IsInToolsMode:()=>false,AddCommand:(name,fn)=>commands.push({name,fn})},GameEvents:{SendCustomGameEventToServer(){throw Error('No server request permitted')}}});
 function advance(seconds){const until=time+seconds;for(;;){const next=[...jobs.entries()].filter(([,v])=>v.at<=until).sort((a,b)=>a[1].at-b[1].at||a[0]-b[0])[0];if(!next)break;time=next[1].at;jobs.delete(next[0]);next[1].fn()}time=until}
 return {api:cfg.LotteryCinematic,nodes,jobs,logs,commands,metrics,advance};
}
{
 const f=fixture({syncFailure:true}),cmd=f.commands.filter(c=>c.name.startsWith('lottery_film_decoder_probe_map_'));
 assert.equal(cmd.length,1);assert(cmd[0].fn());assert.deepEqual(f.metrics.media,[URI]);assert.equal(f.metrics.fallbacks,1);
 assert(f.logs.some(x=>x.includes('stage=error')&&x.includes('api=SetMovie')));f.advance(3.8);
 assert(f.logs.some(x=>x.includes('stage=complete')&&x.includes('outcome=sync_error')));assert.equal(f.jobs.size,0);
 assert(!f.logs.some(x=>x.includes('[LOTTERY_CINEMATIC] stage=preview')));assert.equal(f.metrics.skip,0);assert(f.metrics.peak<=2);
}
{
 const f=fixture({asyncFailure:true});assert(f.api.PreviewDecoderProbe('https://ignored.invalid/anything'));assert.equal(f.metrics.media[0],URI);
 f.advance(.11);assert(f.logs.some(x=>x.includes('stage=error')&&x.includes('native_class=MovieError')));
 assert.equal(f.metrics.fallbacks,1);f.advance(3.8);assert(f.logs.some(x=>x.includes('outcome=native_error')));assert.equal(f.jobs.size,0);
}
{
 const f=fixture();assert(f.api.PreviewDecoderProbe());f.advance(7.1);
 assert.equal(f.metrics.fallbacks,0);assert(f.logs.some(x=>x.includes('stage=complete')&&x.includes('outcome=inconclusive')));
 assert(!f.logs.some(x=>x.includes('stage=error')));
}
{
 const f=fixture({classReadThrows:true});f.api.PreviewDecoderProbe();f.advance(.11);
 assert.equal(f.metrics.fallbacks,0);assert(f.logs.some(x=>x.includes('cause=panel_or_class_read')));assert(!f.logs.some(x=>x.includes('outcome=native_error')));
}
{
 const f=fixture({asyncFailure:true});f.api.PreviewDecoderProbe();const skip=f.nodes.get('LotteryCinematicSkip');skip.events.onactivate();f.advance(10);
 assert.equal(f.metrics.skip,0);assert.equal(f.metrics.fallbacks,0);assert(f.logs.some(x=>x.includes('stage=aborted')));assert(!f.logs.some(x=>x.includes('stage=complete')));
}
{
 const f=fixture();f.nodes.get('LotteryRefreshButton').enabled=false;assert.equal(f.api.PreviewDecoderProbe(),false);assert.equal(f.metrics.media.length,0);
 f.nodes.get('LotteryRefreshButton').enabled=true;f.api.Play('summer',[],()=>{});const movie=f.nodes.get('LotteryCinematicMovie');
 assert.equal(f.api.PreviewDecoderProbe(),false);assert.equal(f.nodes.get('LotteryCinematicMovie'),movie);f.api.Cancel();assert.equal(f.jobs.size,0);
}
// Run the existing full cinema regression against the actual byte string, with
// its original CSS. Its synthetic model is not promoted into native evidence.
const legacy=fs.readFileSync('tools/test_lottery_cinematic_fallback.cjs','utf8').replace(
 "const source=fs.readFileSync('panorama/src/scripts/custom_game/lottery_cinematic_v1.js','utf8');",
 'const source='+JSON.stringify(source)+';');
vm.runInNewContext(legacy,{require,console},{filename:'actual_cinema_regression.cjs'});
console.log('DECODER_PROBE_PASS: fixed installed resource, synthetic sync/native-class paths, unknown=not admitted, cancel/idle guards, no requests; not native evidence');
