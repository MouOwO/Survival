const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
class Panel{
 constructor(type,parent,id){this.id=id;this.type=type;this.parent=parent;this.children=[];this.classes=new Set();this.style={};this.visible=true;this.events={};if(parent)parent.children.push(this);if(id)nodes[id]=this;}
 IsValid(){return !this.deleted;}AddClass(c){this.classes.add(c);}RemoveClass(c){this.classes.delete(c);}SetHasClass(c,b){b?this.AddClass(c):this.RemoveClass(c);}
 SetPanelEvent(n,f){this.events[n]=f;}DeleteAsync(){this.deleted=true;}Stop(){this.stopped=true;}SetControls(x){this.controls=x;}SetRepeat(x){this.repeat=x;}SetPlaybackVolume(x){this.volume=x;}SetMovie(x){this.source=x;}Play(){if(failPlayback)throw Error('missing decoder');this.played=true;}
}
const nodes={},cfg={},jobs=[];let now=0,failPlayback=false;
new Panel('Panel',null,'LotteryWindow');new Panel('Panel',nodes.LotteryWindow,'LotteryMainCanvas');
const $=s=>nodes[s.slice(1)];$.CreatePanel=(t,p,id)=>new Panel(t,p,id);$.Schedule=(delay,fn)=>{let j={at:now+delay,fn};jobs.push(j);return j;};$.CancelScheduled=j=>j.cancelled=true;$.Msg=()=>{};
function advance(seconds){let end=now+seconds;for(;;){jobs.sort((a,b)=>a.at-b.at);let j=jobs[0];if(!j||j.at>end)break;jobs.shift();now=j.at;if(!j.cancelled)j.fn();}now=end;}
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/lottery_cinematic_v1.js','utf8'),{$,GameUI:{CustomUIConfig:()=>cfg}});
const c=cfg.LotteryCinematic;let done=0;
for(const pool of ['map','cultivation','dragon_knight','summer']){
 assert.equal(c.Play(pool,[{quality:'sr'},{quality:'ur'}],()=>done++),true);
 let movie=nodes.LotteryCinematicMovie;assert(movie.source.endsWith('/'+pool+'.webm'));assert(movie.played);assert.equal(movie.repeat,false);assert(movie.volume>0&&movie.volume<=1);
 advance(6.9);assert.equal(done,0);c.Cancel();advance(.5);assert.equal(done,0);assert(movie.stopped);
}
c.Play('cultivation',[],()=>done++);let old=nodes.LotteryCinematicMovie;c.Play('summer',[],()=>done++);assert(old.stopped);advance(7.1);assert.equal(done,1,'replacement run completes exactly once');assert(!nodes.LotteryCinematicSurface.visible);
c.Play('map',[],()=>done++);c.Finish();advance(8);assert.equal(done,2,'skip cannot cause a second completion');
c.Play('../../invalid',[],()=>{});assert(nodes.LotteryCinematicMovie.source.endsWith('/map.webm'));c.Cancel();
assert.equal(nodes.LotteryCinematicSurface.parent,nodes.LotteryWindow,'Movie must live outside the scaled controls canvas');
for(const [w,h] of [[1280,720],[1920,1080],[2560,1440],[3440,1440],[1024,768],[1080,1920]]){
 c.Play('map',[],()=>{});c.Resize(w,h);
 const m=nodes.LotteryCinematicMovie,mw=parseFloat(m.style.width),mh=parseFloat(m.style.height);
 assert(mw<=w+.01&&mh<=h+.01,'Entire movie must fit inside every viewport');
 assert(Math.abs(mw-w)<.01||Math.abs(mh-h)<.01,'Use the largest uncropped size');
 assert(Math.abs(mw/mh-16/9)<.00001,'Movie must preserve its aspect ratio');
 c.Cancel();
}
failPlayback=true;assert.equal(c.Play('map',[],()=>done++),false);advance(8);assert.equal(done,2);assert(!nodes.LotteryCinematicSurface.visible,'decoder failure releases the UI');
assert.equal(c.Highest([{quality:'N'},{quality:'SSR'},{quality:'r'}]),'ssr');
assert(!fs.readFileSync('panorama/src/scripts/custom_game/lottery_cinematic_v1.js','utf8').includes('SendCustomGameEventToServer'),'cinematics must never submit draws or grants');
console.log('LOTTERY_CINEMATIC_PASS: 4 themes, local media, cancel/reopen/skip once, stale timers, decoder fallback, truthful quality and no transactions.');
