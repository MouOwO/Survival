const fs = require('fs');
const vm = require('vm');
const assert = require('assert');
const file = process.argv[2] || 'panorama/src/scripts/custom_game/combat_stats.js';
const source = fs.readFileSync(file, 'utf8');
const begin = source.indexOf('    function installClientCallbackProbe()');
const end = source.indexOf('    // NetTable is the single regular synchronization path.', begin);
assert(begin >= 0 && end > begin, 'extract the actual production Tools installer');
const code = source.slice(begin, end);
const helpersBegin = source.indexOf('    function registerToolsProbeCommandOnce(');
const helpersEnd = source.indexOf('    if (typeof Game !== "undefined"', helpersBegin);
assert(helpersBegin >= 0 && helpersEnd > helpersBegin);
const helpers = source.slice(helpersBegin, helpersEnd);
const names = [
  'hideDeferredHudFeatures', 'collapseOfficialPanel', 'officialPanel', 'renderCombatDebug',
  'refreshOfficialUtilityHotkeys', 'clearOfficialAbilityHotkeys',
  'resolveOfficialAbilityMappings', 'refreshAbilityHotkeysIfChanged',
  'positionCosmeticPortrait', 'updateCosmeticPortrait', 'refreshHeroPanel',
  'refreshHeroVitalsTick', 'refreshAbilities', 'beginUnitNameTransition',
  'writeOfficialAttackText', 'writeOfficialSecondaryStats', 'nativeAbilityEntries',
  'visibleAbilityEntries', 'applyAbilityRuntime', 'refreshOfficialAbilityRuntime', 'update',
  'setOfficialUnitName', 'ensureOfficialUnitNameOverlay', 'updateOfficialStatsVisibility',
  'transitionCosmeticPortrait', 'hideCosmeticPortrait', 'resolveUnitDisplayName',
  'displayNameWithTreeLevel', 'refreshHeroVitals', 'requestSelectedUnitStats', 'unitAbilityCount',
];
function fixture(tools, options = {}) {
  const env = {
    customConfig: options.config || {}, clientCallbackProbe: null, lifecycleGeneration: options.generation || 4,
    contextActive: () => true, now: 1000, count: 0, commands: {}, messages: [], scheduled: [], nextHandle: 0,
    Game: {IsInToolsMode: () => tools, AddCommand: (name, callback) => {
      if (options.rejectDuplicates && env.commands[name]) throw new Error(`ConCommand with that name already exists: ${name}`);
      env.commands[name] = callback;
    }},
    $: {Msg: (...parts) => env.messages.push(parts.join('')),
      Schedule: (delay, callback) => {const handle = ++env.nextHandle;env.scheduled.push({delay,callback,handle});return handle;},
      CancelScheduled: handle => {env.scheduled = env.scheduled.filter(job => job.handle !== handle);}},
  };
  env.commands = options.commands || {};
  env.GameUI = {CustomUIConfig: () => env.customConfig};
  env.Date = {now: () => env.now};
  vm.createContext(env);
  vm.runInContext(names.map(name => `function ${name}(){count++;now+=2;return '${name}';}`).join('\n'), env);
  vm.runInContext(`
    function clearOfficialAbilityHotkeys(){now+=3;return 'clear';}
    function resolveOfficialAbilityMappings(){now+=7;return 'mapping';}
    function refreshOfficialUtilityHotkeys(){
      clearOfficialAbilityHotkeys();resolveOfficialAbilityMappings();now+=2;return 'hotkeys';
    }
    function positionCosmeticPortrait(){now+=11;throw new Error('native failure');}
    function refreshAbilities(){refreshAbilities.signature='new';now+=2;}
    function visibleAbilityEntries(){return nativeAbilityEntries();}
    customConfig.HandoffCombat={
      NativeEntries:nativeAbilityEntries,Entries:visibleAbilityEntries,ApplyRuntime:applyAbilityRuntime,
      RefreshSelection:function(){return refreshHeroPanel();}
    };
    customConfig.HandoffBoundValuesChanged=function(){now+=4;return 'mirror';};
  `, env);
  vm.runInContext(helpers + code, env);
  env.installClientCallbackProbe();
  env.registrationMessages = env.messages.splice(0);
  return env;
}
const topnavSource=fs.readFileSync(process.argv[3]||'panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js','utf8');
function between(s,first,last){const a=s.indexOf(first),b=s.indexOf(last,a+first.length);assert(a>=0&&b>a,first);return s.slice(a,b);}
function nativeFixture(tools=true){
 const e=fixture(tools),api=e.customConfig.SurvivalClientCallbackProbe,counters={reads:0,writes:0,parentReads:0,queries:0,clocks:0},trace=[];
 class Panel{
  constructor(id,parent=null){this.id=id;this.parent=parent;this.children=[];this.alive=true;this.values={};this.throwProperty='';if(parent)parent.children.push(this);
   this.style=new Proxy(this.values,{get:(o,k)=>{counters.reads++;e.now++;trace.push(['read',k]);let v=o[k];if(typeof v==='string'){
    if(/^-?\d+(?:\.\d+)?px$/.test(v))return Number.parseFloat(v).toFixed(1)+'px';
    if(k==='position'&&/px/.test(v))return v.split(/\s+/).map(x=>Number.parseFloat(x).toFixed(1)+'px').join('  ');
    if(k==='transform'&&v==='none')return 'scale3d(1.0, 1.0, 1.0)';
    if(k==='opacity'&&v==='0')return '0.0';
   }return v;},set:(o,k,v)=>{trace.push(['write',k,v]);if(k===this.throwProperty)throw new Error('native style failure');counters.writes++;e.now++;o[k]=v;return true;}});
  }
  IsValid(){return this.alive;}GetParent(){counters.parentReads++;return this.parent;}
  FindChildTraverse(id){counters.queries++;const seek=p=>{for(const c of p.children){if(c.id===id)return c;const found=seek(c);if(found)return found;}return null;};return seek(this);}
  detach(){if(this.parent)this.parent.children=this.parent.children.filter(p=>p!==this);this.parent=null;}
 }
 e.Date={now:()=>{counters.clocks++;return e.now;}};e.cfg=e.customConfig;e.generation=1;e.valid=p=>!!(p&&p.IsValid());e.root=new Panel('root');
 vm.runInContext(between(topnavSource,'    function findCached(','    function cssNumber(')+between(topnavSource,'    function child(','    function refreshInventoryPresentation('),e);
 const registration=between(topnavSource,'    if(Game.IsInToolsMode && Game.IsInToolsMode() && cfg.SurvivalClientCallbackProbe','    if(Game.IsInToolsMode && Game.IsInToolsMode() && Game.AddCommand)');
 for(const match of registration.matchAll(/get:function\(\)\{return (\w+);/g)){const name=match[1];if(!e[name])e[name]=function(){};}
 e.customConfig.SurvivalMainHUD={CacheInspect:e.inspectSquareCache};vm.runInContext(registration,e);
 const reset=()=>{for(const k of Object.keys(counters))counters[k]=0;trace.length=0;};
 return {e,api,counters,trace,Panel,reset};
}
const off=nativeFixture(),originalStyle=off.e.style,originalFind=off.e.findCached;
assert.strictEqual(off.e.style,originalStyle);assert.strictEqual(off.e.findCached,originalFind);
assert.equal(off.e.inspectSquareCache().nativeHotpaths.observed,false);
const offPanel=new off.Panel('off');off.reset();off.e.style(offPanel,{width:'116px'});off.e.findCached(off.e.root,'missing');
assert.equal(off.counters.clocks,0,'default-off helpers add no timing, capture-token or diagnostic branches');
assert.equal(off.e.inspectSquareCache().nativeHotpaths.reason,'capture_not_started');
assert.equal(off.e.scheduled.length,0,'probe setup adds no timer');
const notTools=nativeFixture(false);assert.equal(notTools.api,undefined);notTools.reset();notTools.e.style(new notTools.Panel('off'),{width:'116px'});assert.equal(notTools.counters.clocks,0);
function styleRun(f){const p=new f.Panel('Ability0');Object.assign(p.values,{width:'116px',height:'104px',position:'6px 6px 0px',transform:'none',opacity:'0',fontSize:'25px',visibility:'visible',backgroundColor:'red'});
 const values={width:'116px',height:'104px',position:'6px 6px 0px',transform:'none',opacity:'0',fontSize:'25px',visibility:'visible',backgroundColor:'blue'};
 f.reset();f.e.style(p,values);return {p,counts:{reads:f.counters.reads,writes:f.counters.writes},trace:[...f.trace]};}
assert.equal(off.e.probeNumericStyleEquivalent('116.0005px','116px'),false,'real subpixel change is not formatting equivalence');assert.equal(off.e.probeNumericStyleEquivalent('116%','116px'),false);assert.equal(off.e.probeNumericStyleEquivalent('auto','auto'),false);assert.equal(off.e.probeNumericStyleEquivalent('1e-8','0'),false);assert.equal(off.e.probeNumericStyleEquivalent('0.0s','0s'),true);
const beforeStyle=styleRun(off),on=nativeFixture(),onOriginalStyle=on.e.style,onOriginalFind=on.e.findCached;on.api.Start();const afterStyle=styleRun(on);
assert.deepEqual(afterStyle.counts,beforeStyle.counts,'capturing keeps exactly the original native read/write count');
assert.deepEqual(afterStyle.trace,beforeStyle.trace,'capturing preserves getter/setter order and assigned values');
assert(on.api.Inspect().rows.length < 64,"fixed targets stay below the existing64 limit");let diagnostics=on.api.Inspect().diagnostics.nativeHotpaths,style=diagnostics.style;
assert.equal(style.calls,1);assert.equal(style.attempts,8);assert.equal(style.reads,8);assert.equal(style.nativeWrites,1);assert.equal(style.numericEquivalentWrites,0);assert.equal(style.equivalentSkips,6);
assert.equal(style.byProperty.width.equivalentSkips,1);assert.equal(style.byProperty.position.equivalentSkips,1);assert.equal(style.byProperty.transform.equivalentSkips,1);assert.equal(style.byProperty.opacity.equivalentSkips,1);
assert.equal(style.byProperty.visibility.nativeWrites,0);assert.equal(style.byProperty.backgroundColor.nativeWrites,1);assert.equal(style.byProperty.backgroundColor.numericEquivalentWrites,0);
assert(style.equivalentSkipSamples.some(s=>s.actual==='116.0px'&&s.expected==='116px'),'native normalization has an explicit bounded sample');
const row=on.api.Inspect().rows.find(r=>r.name==='topnav.style');assert.equal(row.count,1);assert.equal(row.ms,afterStyle.counts.reads+afterStyle.counts.writes,'actual instrumented helper times exactly the native getter/setter work');
on.e.style(null,{width:'1px'});assert.equal(style.invalidPanels,1);assert.equal(style.attempts,8);
const fail=new on.Panel('throw');fail.throwProperty='width';assert.throws(()=>on.e.style(fail,{width:'2px'}),/native style failure/);
assert.equal(style.failedWrites,1);assert.equal(style.nativeWrites,1,'failed setter is not reported as a successful native write');
for(let i=0;i<70;i++){afterStyle.p.values['unknown_'+i]='1.0px';on.e.style(afterStyle.p,{['unknown_'+i]:'1px',width:'116px',transform:'none'});}
assert.equal(Object.keys(style.byProperty).length,32,'fixed property buckets with overflow; no unknown-key accumulation');assert.equal(style.byProperty.other.nativeWrites,70);assert.equal(style.samples.length,12,'samples stay bounded');
function findRun(f){f.reset();const root=new f.Panel('lookup'),well=new f.Panel('ButtonWell',root);assert.strictEqual(f.e.findCached(root,'ButtonWell'),well);assert.strictEqual(f.e.findCached(root,'ButtonWell'),well);
 assert.equal(f.e.findCached(root,'AbilityImage'),null);assert.equal(f.e.findCached(root,'AbilityImage'),null);const image=new f.Panel('AbilityImage',root);assert.strictEqual(f.e.findCached(root,'AbilityImage'),image,'late ability discovery remains immediate');
 assert.equal(f.e.findCached(root,'Optional',true),null);assert.equal(f.e.findCached(root,'Optional',true),null);const optional=new f.Panel('Optional',root);assert.equal(f.e.findCached(root,'Optional',true),null);f.e.now+=501;assert.strictEqual(f.e.findCached(root,'Optional',true),optional,'optional retry still has the exact old half-second bound');
 well.detach();const replaced=new f.Panel('ButtonWell',root);assert.strictEqual(f.e.findCached(root,'ButtonWell'),replaced,'valid detached node does not mask replacement');assert.equal(f.e.findCached(null,'ButtonWell'),null);
 return {queries:f.counters.queries,parentReads:f.counters.parentReads};}
const beforeFind=findRun(off),afterFind=findRun(on);assert.deepEqual(afterFind,beforeFind,'lookup instrumentation preserves all native query/parent reads');
diagnostics=on.api.Inspect().diagnostics.nativeHotpaths;const lookup=diagnostics.findCached;
assert.equal(lookup.calls,11);assert.equal(lookup.lookups,7);assert.equal(lookup.positiveHits,1);assert.equal(lookup.optionalNegativeHits,2);assert.equal(lookup.invalidParents,1);assert.equal(lookup.staleLinks,1);assert.equal(lookup.pathReads,afterFind.parentReads);assert.equal(lookup.lookups,afterFind.queries);
const styleWrapper=on.e.style,findWrapper=on.e.findCached,stopReport=on.api.Stop();assert.equal(stopReport.enabled,false);assert.equal(on.api.CaptureToken(),0);assert.strictEqual(on.e.style,onOriginalStyle,'Stop restores the original style helper');assert.strictEqual(on.e.findCached,onOriginalFind,'Stop restores the original lookup helper');
const callsAtStop=stopReport.diagnostics.nativeHotpaths.style.calls;styleWrapper(afterStyle.p,{width:'116px'});findWrapper(on.e.root,'missing');assert.equal(on.api.Inspect().diagnostics.nativeHotpaths.style.calls,callsAtStop,'queued old wrapper uses original behavior after Stop');
assert.equal(on.e.scheduled.length,0,'capture adds no polling task');assert.equal(on.e.messages.length,0,'no per-call log');
on.api.Start();diagnostics=on.api.Inspect().diagnostics.nativeHotpaths;assert.equal(diagnostics.captureToken,2);assert.equal(diagnostics.style.calls,0);assert.equal(diagnostics.findCached.calls,0,'new capture resets every counter');
const replacement=function(){return 'owner replaced';};on.e.style=replacement;on.api.Stop();assert.strictEqual(on.e.style,replacement,'Stop never overwrites owner replacement during capture');
assert.equal(on.api.RegisterModule('bad',[{name:'capture',get:()=>()=>{},set(){},capture:42}]),false,'invalid capture factory cannot be registered');
const mismatch=nativeFixture();mismatch.api.Start();const mismatchPanel=new mismatch.Panel('Ability0');
Object.assign(mismatchPanel.values,{width:'116px'});mismatch.reset();mismatch.e.style(mismatchPanel,{width:'116px',horizontalAlign:'left'});
let mismatchStyle=mismatch.api.Inspect().diagnostics.nativeHotpaths.style;
assert.equal(mismatch.counters.reads,2,'first mismatch sampling uses existing getter only');assert.equal(mismatch.counters.writes,1,'equivalent width is skipped; unreadable alignment retains its setter');
assert.equal(mismatchStyle.byProperty.width.equivalentSkips,1);
assert.equal(mismatchStyle.byProperty.width.firstMismatch.actual,'116.0px');assert.equal(mismatchStyle.byProperty.width.firstMismatch.expected,'116px');assert.equal(mismatchStyle.byProperty.width.firstMismatch.actualType,'string');
assert.equal(mismatchStyle.byProperty.horizontalAlign.firstMismatch.actual,'undefined');assert.equal(mismatchStyle.byProperty.horizontalAlign.firstMismatch.actualType,'undefined');assert.equal(mismatchStyle.byProperty.horizontalAlign.firstMismatch.expectedType,'string');
mismatchPanel.values.width='72px';mismatch.e.style(mismatchPanel,{width:'116px'});assert.equal(mismatchStyle.byProperty.width.firstMismatch.actual,'116.0px','each property retains only its first mismatch');
mismatch.e.style(mismatchPanel,{backgroundImage:'x'.repeat(1000)});assert.equal(mismatchStyle.byProperty.backgroundImage.firstMismatch.expected.length,160,'per-property sample remains bounded');
mismatch.api.Stop();
// An unreadable component can use its actual readable shorthand. Capture must
// count that extra live getter without changing production decision or order.
function shorthandRun(f){const p=new f.Panel('margin');Object.assign(p.values,{marginRight:null,margin:'0.0px 4.0px 0.0px 0.0px'});f.reset();f.e.style(p,{marginRight:'4px'});return {reads:f.counters.reads,writes:f.counters.writes,trace:[...f.trace]};}
const shorthandOff=nativeFixture(),shorthandOn=nativeFixture();shorthandOn.api.Start();
const plainShorthand=shorthandRun(shorthandOff),observedShorthand=shorthandRun(shorthandOn);
assert.deepEqual(observedShorthand,plainShorthand,'live shorthand proof has exact production/capture parity');
assert.equal(observedShorthand.reads,2);assert.equal(observedShorthand.writes,0);
const shorthandStyle=shorthandOn.api.Inspect().diagnostics.nativeHotpaths.style;
assert.equal(shorthandStyle.reads,2);assert.equal(shorthandStyle.byProperty.marginRight.reads,2);assert.equal(shorthandStyle.nativeWrites,0);
shorthandOn.api.Stop();
console.log('TOPNAV_NATIVE_HELPER_PROBE_PASS: default off zero clock/hooks, exact native getter/setter and lookup behavior, fixed property buckets, normalization samples, exception/Stop/reload safety');
