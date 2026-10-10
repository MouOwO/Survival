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
  'renderCombatDebug', 'hideDeferredHudFeatures', 'collapseOfficialPanel', 'officialPanel',
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
const normal = fixture(false);
assert.equal(normal.clientCallbackProbe, null);
assert.equal(normal.customConfig.SurvivalClientCallbackProbe, undefined);
assert.equal(Object.keys(normal.commands).length, 0, 'no production commands or wrappers');

const tools = fixture(true);
const api = tools.customConfig.SurvivalClientCallbackProbe;
const original = tools.refreshOfficialUtilityHotkeys;
const originalEntries = tools.nativeAbilityEntries;
tools.refreshAbilities.signature = 'original';
assert.strictEqual(tools.refreshOfficialUtilityHotkeys, original, 'Tools load still defaults off');
assert.equal(api.Inspect().enabled, false);
assert.equal(api.CaptureToken(),0,'default-off diagnostic token');
tools.customConfig.SurvivalMainHUD={CacheInspect:()=>({square:{calls:7,hits:5}})};
tools.customConfig.SurvivalWorldHealthBars={ProbeInspect:()=>({observed:true,frames:3,projected:9})};
api.Start();
assert.equal(api.CaptureToken(),1);
assert.equal(api.Inspect().diagnostics.square.hits,5,'module diagnostics reach the existing report without new commands');
assert.equal(api.Inspect().diagnostics.worldBars.projected,9,'worldbar diagnostics share the existing capture/report command');

// A module's returned diagnostics can cross a native Panorama context boundary.
// Never write into that frozen/proxied object to append another module's fields.
const reportFixture=fixture(true), reportApi=reportFixture.customConfig.SurvivalClientCallbackProbe;
const foreignDiagnostics=Object.freeze({square:Object.freeze({calls:7,hits:5}),other:'preserved'});
const directWorld=Object.freeze({observed:true,frames:3,projected:9});
reportFixture.customConfig.SurvivalMainHUD={CacheInspect:()=>foreignDiagnostics};
reportFixture.customConfig.SurvivalWorldHealthBars={ProbeInspect(){
  assert.strictEqual(this,reportFixture.customConfig.SurvivalWorldHealthBars,'keep the API receiver');
  return directWorld;
}};
let reportDiagnostics=reportApi.Inspect().diagnostics;
assert.notStrictEqual(reportDiagnostics,foreignDiagnostics,'report diagnostics belong to the calling context');
assert.equal(reportDiagnostics.square.hits,5);
assert.equal(reportDiagnostics.other,'preserved','copy existing module diagnostic fields');
assert.equal(JSON.parse(JSON.stringify(reportDiagnostics)).worldBars.projected,9);
assert.equal(Object.hasOwn(foreignDiagnostics,'worldBars'),false,'frozen module return stays untouched');
assert.equal(reportDiagnostics.worldBarsProbe.returnType,'object');
let proxyWrites=0;
reportFixture.customConfig.SurvivalMainHUD={CacheInspect:()=>new Proxy(foreignDiagnostics,{
  set(){proxyWrites++;throw new Error('native proxy rejects additions');}
})};
reportDiagnostics=reportApi.Inspect().diagnostics;
assert.equal(proxyWrites,0,'foreign native proxy never receives a report property write');
assert.equal(JSON.parse(JSON.stringify(reportDiagnostics)).worldBars.frames,3);
delete reportFixture.customConfig.SurvivalWorldHealthBars;
reportDiagnostics=reportApi.Inspect().diagnostics;
assert.equal(reportDiagnostics.worldBars,null,'unavailable API remains explicitly enumerable');
assert.equal(reportDiagnostics.worldBarsProbe.reason,'api_unavailable');
assert.equal(reportDiagnostics.worldBarsProbe.apiType,'undefined');
reportFixture.customConfig.SurvivalWorldHealthBars={ProbeInspect:42};
assert.equal(reportApi.Inspect().diagnostics.worldBarsProbe.reason,'inspect_unavailable');
reportFixture.customConfig.SurvivalWorldHealthBars={ProbeInspect:()=>undefined};
reportDiagnostics=reportApi.Inspect().diagnostics;
assert.equal(JSON.parse(JSON.stringify(reportDiagnostics)).worldBars,null,'undefined return cannot silently erase the field');
assert.equal(reportDiagnostics.worldBarsProbe.returnType,'undefined');
assert.equal(reportDiagnostics.worldBarsProbe.reason,'inspect_return_undefined');
reportFixture.customConfig.SurvivalWorldHealthBars={ProbeInspect:()=>null};
assert.equal(reportApi.Inspect().diagnostics.worldBarsProbe.reason,'inspect_return_null');
reportFixture.customConfig.SurvivalWorldHealthBars={ProbeInspect(){throw new Error('x'.repeat(1000));}};
reportDiagnostics=reportApi.Inspect().diagnostics;
assert.equal(reportDiagnostics.worldBars,null);
assert.equal(reportDiagnostics.worldBarsProbe.reason,'inspect_failed');
assert.equal(reportDiagnostics.worldBarsProbe.error.length,240,'failed cross-context call has bounded evidence');
assert.equal(reportApi.Inspect().enabled,false,'inspection never starts a default-off capture');
assert.equal(reportFixture.scheduled.length,0,'reporting introduces no timer or retry');

assert.notStrictEqual(tools.refreshOfficialUtilityHotkeys, original);
assert.equal(tools.refreshAbilities.signature, 'original', 'preserve function properties on installation');
assert.strictEqual(tools.customConfig.HandoffCombat.NativeEntries, tools.nativeAbilityEntries);
const queuedWrapper = tools.refreshOfficialUtilityHotkeys;
assert.equal(tools.refreshOfficialUtilityHotkeys(), 'hotkeys');
tools.customConfig.HandoffCombat.Entries();
tools.customConfig.HandoffCombat.RefreshSelection();
tools.refreshAbilities();
assert.throws(() => tools.positionCosmeticPortrait(), /native failure/, 'native exceptions propagate');
let snapshot = api.Inspect();
const row = name => snapshot.rows.find(item => item.name === name);
assert.equal(row('refreshOfficialUtilityHotkeys').count, 1);
assert.equal(row('refreshOfficialUtilityHotkeys').ms, 12);
assert.equal(row('refreshOfficialUtilityHotkeys').selfMs, 2, 'subtract measured child time');
assert.equal(row('clearOfficialAbilityHotkeys').ms, 3);
assert.equal(row('resolveOfficialAbilityMappings').ms, 7);
assert.equal(row('positionCosmeticPortrait').count, 1, 'failed callbacks remain measured');
assert.equal(row('nativeAbilityEntries').count, 1, 'external aliases reach wrappers');
assert.equal(row('handoffRefreshSelection').count, 1);
assert.equal(row('updateStatsSnapshot').observed, false, 'zero callbacks explicitly mean unobserved');
assert.equal(tools.messages.length, 0, 'no callback-time log output');
assert(snapshot.slow.some(item => item.name === 'refreshOfficialUtilityHotkeys'));
snapshot = api.Stop();
assert.equal(api.CaptureToken(),0,'Stop disables diagnostics');
assert.strictEqual(tools.refreshOfficialUtilityHotkeys, original);
assert.strictEqual(tools.customConfig.HandoffCombat.NativeEntries, originalEntries);
assert.equal(tools.refreshAbilities.signature, 'new', 'preserve state changes on removal');
assert(snapshot.rows.every(item => !item.hooked));
queuedWrapper();
assert.equal(api.Inspect().rows.find(item => item.name === 'refreshOfficialUtilityHotkeys').count, 1,
  'already queued wrappers call through without measuring after Stop');

api.Start();
assert.equal(api.Inspect().rows.find(item => item.name === 'refreshOfficialUtilityHotkeys').count, 0,
  'new capture resets totals');
for (let i = 0; i < 25; i++) assert.throws(() => tools.positionCosmeticPortrait(), /native failure/);
assert.equal(api.Inspect().slow.length, 12, 'slow sample storage is bounded');
tools.commands.survival_client_callback_report_v2();
assert.equal(api.Inspect().enabled, false, 'report ends capture');
assert.equal(tools.messages.filter(line=>line.startsWith('[CLIENT_CALLBACK_PROBE] ')).length,1,'only one complete explicit report');
assert(tools.messages.every(line=>line.startsWith('[CLIENT_CALLBACK_PROBE] ')||line.startsWith('[CLIENT_CALLBACK_PROBE_CHUNK] ')));
assert(tools.messages.every(line=>Buffer.byteLength(line,'utf8')<=8192),'all explicit report lines stay below native console bound');
assert.equal(api.Inspect().rows.length, 38, 'fixed callback buckets include combat debug refresh');
assert(api.Inspect().clock.includes('integer'), 'clock resolution is explicit');

const scheduler = fixture(true);
const schedulerApi = scheduler.customConfig.SurvivalClientCallbackProbe;
const originalScheduler = scheduler.$.Schedule;
assert.strictEqual(scheduler.$.Schedule, originalScheduler, 'no scheduler wrapper before explicit Start');
let firstNativeCall = 0;
scheduler.$.Schedule(0, () => {firstNativeCall++;});
schedulerApi.Start();
assert.notStrictEqual(scheduler.$.Schedule, originalScheduler);
scheduler.scheduled.shift().callback();
assert.equal(firstNativeCall, 1);
assert.equal(schedulerApi.Inspect().schedule.count, 0, 'already queued native callbacks are unobserved');
vm.runInContext(`function worldTick(){now+=5;refreshOfficialUtilityHotkeys();$.Schedule(0,worldTick);}
  $.Schedule(0,worldTick);`, scheduler);
const firstJob = scheduler.scheduled.shift();
assert.equal(firstJob.handle, 2, 'native scheduled handle propagates');
firstJob.callback();
let scheduleReport = schedulerApi.Inspect().schedule;
assert.equal(scheduleReport.count, 1);
assert.equal(scheduleReport.ms, 17);
assert.equal(scheduleReport.selfMs, 5, 'schedule self time excludes measured local functions');
assert.equal(scheduleReport.rows.length, 1, 'recurring callback reuses source/name bucket');
assert(scheduleReport.rows[0].name.includes('worldTick'));
const snapshotCount = scheduleReport.rows[0].count;
scheduler.scheduled.shift().callback();
assert.equal(scheduleReport.rows[0].count, snapshotCount, 'Inspect returns detached row values');
assert.equal(schedulerApi.Inspect().schedule.count, 2);
const staleJob = scheduler.scheduled.shift();
schedulerApi.Stop();
assert.strictEqual(scheduler.$.Schedule, originalScheduler, 'Stop restores native Schedule');
staleJob.callback();
assert.equal(schedulerApi.Inspect().schedule.count, 2, 'post-stop queued wrappers call through');
const priorWindowJob = scheduler.scheduled.shift();
schedulerApi.Start();
priorWindowJob.callback();
assert.equal(schedulerApi.Inspect().schedule.count, 0, 'prior window native callback is not miscounted');
const priorWrapped = scheduler.scheduled.shift();
schedulerApi.Stop();schedulerApi.Start();
priorWrapped.callback();
assert.equal(schedulerApi.Inspect().schedule.count, 0, 'old wrapper never contaminates a new capture');
scheduler.scheduled.shift().callback();
assert.equal(schedulerApi.Inspect().schedule.count, 1, 'next reschedule is captured');
const cancelled = scheduler.$.Schedule(0, () => {throw new Error('must be cancelled');});
scheduler.$.CancelScheduled(cancelled);
assert(!scheduler.scheduled.some(job => job.handle === cancelled), 'native CancelScheduled still accepts returned handle');
scheduler.scheduled = [];
const receiver = {expected: true};
scheduler.$.Schedule(0, function argumentCallback(a, b) {
  assert.strictEqual(this, receiver);assert.equal(a + b, 7);scheduler.now += 3;
});
scheduler.scheduled.shift().callback.call(receiver, 3, 4);
scheduler.$.Schedule(0, function failingCallback() {scheduler.now += 11;throw new Error('scheduled failure');});
assert.throws(() => scheduler.scheduled.shift().callback(), /scheduled failure/);
assert(schedulerApi.Inspect().schedule.rows.some(item => item.name.includes('failingCallback') && item.count === 1));
vm.runInContext(`$.Schedule(0,function(){now+=1;});$.Schedule(0,function(){now+=1;});
  $.Schedule(0,function differentName(){now+=1;});`, scheduler);
scheduler.scheduled.splice(0).forEach(job => job.callback());
scheduleReport = schedulerApi.Inspect().schedule;
assert(scheduleReport.rows.some(item => item.name.includes('anonymous') && item.count === 2),
  'same anonymous source joins one bucket');
assert(scheduleReport.rows.some(item => item.name.includes('differentName') && item.count === 1),
  'different named callback has its own bucket');
for (let i = 0; i < 80; i++) vm.runInContext(`$.Schedule(0,function bucket${i}(){now+=1;});`, scheduler);
scheduler.scheduled.splice(0).forEach(job => job.callback());
scheduleReport = schedulerApi.Inspect().schedule;
assert.equal(scheduleReport.limit, 48);
assert.equal(scheduleReport.rows.length, 49, '48 distinct rows plus one overflow row');
assert(scheduleReport.overflowed > 0 && scheduleReport.rows.some(item => item.name === 'scheduled:overflow'));
const laterScheduler = function replacementSchedule() {};
scheduler.$.Schedule = laterScheduler;
schedulerApi.Stop();
assert.strictEqual(scheduler.$.Schedule, laterScheduler, 'Stop preserves external scheduler replacement');
assert.equal(schedulerApi.Inspect().schedule.hooked, false);
const blocked = fixture(true);
Object.defineProperty(blocked.$, 'Schedule', {writable: false});
blocked.customConfig.SurvivalClientCallbackProbe.Start();
assert.equal(blocked.customConfig.SurvivalClientCallbackProbe.Inspect().schedule.hooked, false);
assert(blocked.customConfig.SurvivalClientCallbackProbe.Inspect().schedule.error,
  'an unavailable hook is explicit rather than reported as zero cost');
blocked.customConfig.SurvivalClientCallbackProbe.Stop();

const moduleFixture = fixture(true), moduleApi = moduleFixture.customConfig.SurvivalClientCallbackProbe;
moduleFixture.privateCallback = function() {moduleFixture.now += 7;return 'module';};
const privateOriginal = moduleFixture.privateCallback;
const moduleDescriptors = [{name:'refresh',get:() => moduleFixture.privateCallback,set:fn => moduleFixture.privateCallback=fn}];
assert.equal(moduleApi.RegisterModule('topnav',moduleDescriptors), true);
assert.strictEqual(moduleFixture.privateCallback,privateOriginal, 'module registration stays off');
assert.equal(moduleApi.RegisterModule('topnav',moduleDescriptors), true, 'module replacement does not duplicate rows');
assert.equal(moduleApi.Inspect().rows.length,39);
moduleApi.Start();
assert.equal(moduleApi.RegisterModule('late',moduleDescriptors), false, 'do not change the target set while measuring');
assert.equal(moduleFixture.privateCallback(),'module');
const moduleRow = moduleApi.Inspect().rows.find(item => item.name === 'topnav.refresh');
assert.equal(moduleRow.count,1);assert.equal(moduleRow.ms,7);
moduleApi.Stop();assert.strictEqual(moduleFixture.privateCallback,privateOriginal);
assert.equal(moduleApi.RegisterModule('huge',Array.from({length:58},(_,i) => ({...moduleDescriptors[0],name:String(i)}))),false,
  '97 total local/module buckets exceed the 96-entry bound');

// Reproduce the real native registry contract: duplicate names throw and old
// registrations persist. Stable aliases must resolve the latest API; a unique
// command must also work when a prior context's native callback is unusable.
const sharedCommands = {survival_client_callback_probe: () => {throw new Error('dead legacy context');}};
const sharedConfig = {};
const firstContext = fixture(true, {config: sharedConfig, commands: sharedCommands, rejectDuplicates: true});
const firstApi = firstContext.customConfig.SurvivalClientCallbackProbe;
const alias = sharedCommands.survival_client_callback_probe_v2;
const uniqueFirst = firstApi.Commands.start;
assert(!firstContext.registrationMessages.some(item => item.includes('COMMAND_ERROR')),
  'already existing legacy base commands are never registered again');
assert(firstContext.registrationMessages.some(item => item.includes(uniqueFirst)), 'unique discovery is explicit');
alias();assert.equal(firstApi.Inspect().enabled, true);
const secondContext = fixture(true, {config: sharedConfig, commands: sharedCommands, rejectDuplicates: true, generation: 5});
const secondApi = secondContext.customConfig.SurvivalClientCallbackProbe;
assert.notEqual(secondApi.Commands.start, uniqueFirst, 'unique command is different even with identical Date.now');
assert.strictEqual(sharedCommands.survival_client_callback_probe_v2, alias, 'register stable alias only once');
assert(!secondContext.registrationMessages.some(item => item.includes('COMMAND_ERROR')),
  'persistent registry avoids duplicate native AddCommand calls');
const newNativeEntries = sharedConfig.HandoffCombat.NativeEntries;
firstApi.Stop();
assert.strictEqual(sharedConfig.HandoffCombat.NativeEntries, newNativeEntries,
  'shutdown of an old capture cannot restore old aliases into a replacement HUD');
alias();assert.equal(secondApi.Inspect().enabled, true, 'old live alias starts the current API');
assert.equal(firstApi.Inspect().enabled, false);
sharedCommands.survival_client_callback_report_v2();
assert.equal(secondApi.Inspect().enabled, false);
assert(firstContext.messages.at(-1).includes(secondApi.CommandId), 'old live alias reports current context identity');
sharedCommands.survival_client_callback_probe_v2 = () => {throw new Error('dead native binding');};
sharedCommands[secondApi.Commands.start]();
assert.equal(secondApi.Inspect().enabled, true, 'new unique entry bypasses dead stable native callback');
sharedCommands[secondApi.Commands.report]();
assert.equal(secondApi.Inspect().enabled, false);
assert.equal(secondApi.Inspect().probeVersion, 2);
secondContext.contextActive = () => false;
sharedCommands[secondApi.Commands.start]();
assert.equal(secondApi.Inspect().enabled, false, 'inactive contexts cannot start a new capture');
assert(secondContext.messages.at(-1).includes('start_failed'), 'failed Start cannot falsely print started');

// A surviving native registry with a missing CustomUIConfig marker is handled
// without aborting initialization. The unique fallback remains usable.
const missingMarker = fixture(true, {commands: sharedCommands, rejectDuplicates: true, generation: 6});
assert(missingMarker.registrationMessages.some(item => item.includes('COMMAND_ERROR')));
assert(missingMarker.customConfig.SurvivalClientCallbackProbe, 'duplicate error does not abort installer');
sharedCommands[missingMarker.customConfig.SurvivalClientCallbackProbe.Commands.start]();
assert.equal(missingMarker.customConfig.SurvivalClientCallbackProbe.Inspect().enabled, true);
missingMarker.customConfig.SurvivalClientCallbackProbe.Stop();
console.log('CLIENT_CALLBACK_PROBE_PASS: opt-in, frozen/native-proxy module reports and explicit missing worldbar evidence, nested/self timing, native scheduler, bounded output, restore, duplicate native registry, latest API aliases, unique hot-reload fallback, inactive Start and replacement ownership');

const detailed=fixture(true),dcfg=detailed.customConfig,dapi=dcfg.SurvivalClientCallbackProbe;
const owner={Refresh:function(){assert.strictEqual(this,owner);detailed.now+=3;return 'portrait';},RefreshLocalHeroPortrait:function(){detailed.now+=2;return 'corner';}};
dcfg.SurvivalPortraitPresentation=owner;
dcfg.SurvivalProductionHUD={Refresh:function(){detailed.now+=4;return 'production';}};
const originalPortrait=owner.Refresh;assert.strictEqual(owner.Refresh,originalPortrait,'detail modules default off');dapi.Start();assert.equal(owner.Refresh(),'portrait');assert.equal(owner.RefreshLocalHeroPortrait(),'corner');assert.equal(dcfg.SurvivalProductionHUD.Refresh(),'production');
let dr=dapi.Inspect();assert.equal(dr.rows.find(r=>r.name==='hudDetail.portraitRefresh').count,1);assert.equal(dr.rows.find(r=>r.name==='hudDetail.heroCornerRefresh').ms,2);assert.equal(dr.rows.find(r=>r.name==='hudDetail.productionRefresh').ms,4);assert.equal(dr.rows.find(r=>r.name==='hudDetail.minimapShortcutsRefresh').observed,false,'missing API is unobserved, not a claimed measured zero');
const newOwner={Refresh:()=> 'new module'};dcfg.SurvivalProductionHUD=newOwner;dapi.Stop();assert.strictEqual(owner.Refresh,originalPortrait);assert.equal(newOwner.Refresh(),'new module','Stop cannot restore stale callbacks into a replacement module');
console.log('HUD_DETAIL_PROBE_PASS: shared default-off capture, APIs loaded after installer, correct receiver/count/time, absent APIs explicit-unobserved, replacement ownership and restore');
