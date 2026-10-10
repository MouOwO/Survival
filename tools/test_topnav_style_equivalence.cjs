"use strict";
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync(process.argv[2]||'panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js','utf8');
function between(start,end){const a=source.indexOf(start),b=source.indexOf(end,a);assert(a>=0&&b>a,start);return source.slice(a,b);}
function fixture(){
 const counters={reads:0,writes:0,parses:0},trace=[];
 const env={generation:1,valid:p=>!!p&&p.alive,Date:{now(){throw Error('production comparison must not read clocks');}}};vm.createContext(env);
 vm.runInContext(between('    var styleNumericKinds=','    function cssNumber(')+between('    var nativeHotpathStats=','    function probeFindCached('),env);
 const parse=env.numericStyleValue;env.numericStyleValue=function(){counters.parses++;return parse.apply(this,arguments);};
 function panel(id,values={}){const p={id,values:{...values},alive:true};p.style=new Proxy(p.values,{get(o,k){counters.reads++;trace.push(['read',k]);return o[k];},set(o,k,v){trace.push(['write',k,v]);if(p.throwKey===k)throw p.failure;counters.writes++;o[k]=v;return true;}});return p;}
 const reset=()=>{for(const k in counters)counters[k]=0;trace.length=0;};
 return {env,counters,trace,panel,reset};
}
const f=fixture();let assertions=0;
function run(key,actual,expected,equivalent){
 const p=f.panel('test',{[key]:actual});f.reset();f.env.style(p,{[key]:expected});
 assert.equal(f.counters.reads,1,'one native getter: '+key);assert.equal(f.counters.writes,equivalent?0:1,`${key}: ${actual} -> ${expected}`);assertions++;
}
for(const key of ['width','height','minWidth','minHeight','maxWidth','maxHeight','fontSize','marginTop','marginRight','marginBottom','marginLeft','paddingTop','paddingRight','paddingBottom','paddingLeft']){
 for(const [a,b] of [['34.0px','34px'],[' 34.000px ','34px'],['.5%','0.50%'],['-0.0px','0px']])run(key,a,b,true);
 for(const [a,b] of [['0.0px','116px'],['116.0005px','116px'],['100%','100px'],['auto','0px'],['1e2px','100px'],['Infinitypx','1px'],['0','0px']])run(key,a,b,false);
}
for(const [k,a,b] of [['opacity','0.0','0'],['opacity','.5','0.50'],['transitionDuration','0.0s','0s'],['transitionDelay','10.000ms','10ms'],['position','0.0px  6px -2.000px','0px 6.0px -2px'],['position','0% 0px 0px','0.0% 0.0px 0.0px'],['margin','0.0px 0px 0px 0px','0px'],['padding','1.0px 2.0% 1px 2%','1px 2%'],['margin','1px 2px 3px 2px','1.0px 2px 3px'],['padding','1px 2px 3px 4px','1.0px 2.0px 3.0px 4.0px']])run(k,a,b,true);
for(const [k,a,b] of [['opacity','NaN','0'],['opacity','1e-8','0'],['opacity','0%','0'],['transitionDuration','1000ms','1s'],['transitionDuration','0.0s, 0.0s','0s'],['position','0px 0px','0px 0px 0px'],['position','0px 1px 0px','0px 0px 0px'],['margin','0px 0px 1px 0px','0px'],['padding','1px 2px 3px 4px','1px 2px 3px'],['width','calc(100% - 1px)',' calc(100% - 1px) '],['horizontalAlign','left ','left'],['unknown','1.0px','1px'],['width',undefined,'1px'],['minWidth','','1px']])run(k,a,b,false);
for(const [k,a,b] of [
 ['transform','scale3d(1,1,1)','none'],['transform','matrix3d(1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1)','none'],
 ['backgroundImage','none  / none none unset unset','none'],['border','unsetunsetunsetunset/ 0.0px 0.0px 0.0px 0.0px / none none none none ','0px'],
 ['overflow','noclip noclip','noclip'],['boxShadow','fill 0.0px 0.0px 0.0px 0.0px transparent','none'],['backgroundColor','#10252CFF','#10252c'],['border','0.0px','0px']
])run(k,a,b,true);
for(const [k,a,b] of [
 ['transform','scale3d(1.0000001,1,1)','none'],['transform','matrix3d(1,0,0,0,0,1,0,0,0,0,1,0,1,0,0,1)','none'],['transform','scale3d(0x1,1,1)','none'],['transform','matrix3d(1,,,0,0,1,0,0,0,0,1,0,0,0,0,1)','none'],
 ['backgroundImage','url("engine-restored.png") / none none unset unset','none'],['border','unsetunsetunsetunset/ 0.0px 1.0px 0.0px 0.0px / none none none none ','0px'],
 ['overflow','noclip clip','noclip'],['boxShadow','fill 0.0px 0.0px 1.0px 0.0px transparent','none'],['backgroundColor','#10252C80','#10252c'],
 ['horizontalAlign',null,'left'],['transitionDuration',null,'0s'],['border','0.0001px','0px']
])run(k,a,b,false);
const component=f.panel('component',{marginRight:null,margin:'0.0px 4.0px 0.0px 0.0px'});f.reset();f.env.style(component,{marginRight:'4px'});
assert.equal(f.counters.reads,2,'unreadable component uses one extra live shorthand read');assert.equal(f.counters.writes,0);
component.values.margin='0px 2px 0px 0px';f.env.style(component,{marginRight:'4px'});assert.equal(f.counters.writes,1,'real live shorthand change repairs component');
component.values.margin=undefined;f.env.style(component,{marginRight:'4px'});assert.equal(f.counters.writes,1,'readable component remains authoritative after a successful setter');
component.values.marginRight=null;f.reset();f.env.style(component,{marginRight:'4px'});
assert.equal(f.counters.reads,2);assert.equal(f.counters.writes,1,'both unreadable live component and shorthand retain the native setter');
run('unknown','anything','anything',true);run('width','auto','auto',true);
// A proved pair needs no repeated parsing, yet every call still reads native.
const p=f.panel('Ability0',{width:'116.0px'});f.reset();f.env.style(p,{width:'116px'});assert.equal(f.counters.parses,2);
for(let i=0;i<1000;i++)f.env.style(p,{width:'116px'});
assert.equal(f.counters.reads,1001);assert.equal(f.counters.writes,0);assert.equal(f.counters.parses,2);
p.values.width='0.0px';f.env.style(p,{width:'116px'});assert.equal(f.counters.writes,1);assert.equal(p.values.width,'116px','native reset repaired immediately');
f.env.style(p,{width:'117px'});assert.equal(p.values.width,'117px','desired change cannot reuse an earlier pair');
p.values.width='116.0px';f.env.style(p,{width:'116px'});const parseCount=f.counters.parses;f.env.generation++;f.env.style(p,{width:'116px'});assert.equal(f.counters.parses,parseCount+2,'reload invalidates panel-local proof');
const replacement=f.panel('Ability0',{width:'0.0px'});f.env.style(replacement,{width:'116px'});assert.equal(replacement.values.width,'116px','same ID new panel cannot inherit proof');
const failed=f.panel('unreadable',{height:undefined});f.reset();for(let i=0;i<100;i++){failed.values.height=undefined;f.env.style(failed,{height:'10px'});}assert.equal(f.counters.reads,100);assert.equal(f.counters.writes,100);assert.equal(f.counters.parses,2,'failed pair may avoid reparsing but never avoids setters');
const error={name:'sentinel'};failed.throwKey='height';failed.failure=error;assert.throws(()=>f.env.style(failed,{height:'12px'}),e=>e===error);failed.alive=false;f.reset();f.env.style(failed,{height:'12px'});assert.equal(f.counters.reads,0);assert.equal(f.counters.writes,0);
// Tools probe must execute exactly the same production decision and ordering.
function sequence(f,fn){const p=f.panel('Ability0',{width:'116.0px',height:'34.0px',minHeight:'34.0px',position:'0.0px 0px 0px',padding:'0px 0px 0px 0px',opacity:'0.0',transform:'scale3d(1,1,1)',horizontalAlign:undefined});const values={width:'116px',height:'34px',minHeight:'34px',position:'0px 0px 0px',padding:'0px',opacity:'0',transform:'none',horizontalAlign:'left'};f.reset();fn(p,values);fn(p,values);p.values.minHeight='0.0px';fn(p,values);return {trace:f.trace,reads:f.counters.reads,writes:f.counters.writes,values:p.values};}
const off=fixture(),on=fixture(),wrapped=on.env.probeStyle(on.env.style,1);assert.deepEqual(sequence(off,off.env.style),sequence(on,wrapped));
assert(on.env.nativeHotpathStats.style.equivalentSkips>0);assert(on.env.nativeHotpathStats.style.cachedEquivalentSkips>0);assert.equal(on.env.nativeHotpathStats.style.byProperty.minHeight.nativeWrites,1);
console.log(`TOPNAV_STYLE_EQUIVALENCE_PASS: ${assertions} numeric/compound/unknown cases, bounded live getter proofs, reset/reload/replacement/error safety, 1000 cached skips, exact Tools parity`);
