const assert = require('assert'), fs = require('fs'), vm = require('vm');
const sourcePath = 'panorama/src/scripts/custom_game/production_progress.js';
const model = require('../' + sourcePath);
const options = Array.from({length: 8}, (_, i) => ({training_id: 'worker_' + (i + 1), level: i + 1, name: '伐木工', count: 0, max_count: 3, queued_count: 0, available: 1, cost_wood: 10, train_duration: 1}));
const initial = model.TrainingSlots(options);
assert.deepEqual(initial, ['worker_1', 'worker_2', 'worker_3', 'worker_4']);
options[0].queued_count = 3;
assert.deepEqual(model.TrainingSlots(options), initial, 'reserved slots stay visible');
options[0].count = 3;
const hidden = model.TrainingSlots(options);
assert.deepEqual(hidden, ['worker_2', 'worker_3', 'worker_4', 'worker_5'], 'completed levels are replaced immediately in ascending order');
assert.deepEqual(model.TrainingSlots(options), hidden, 'repeated renders retain ascending entries without requiring selection');
options[1].count = 3;
assert.deepEqual(model.TrainingSlots(options), ['worker_3', 'worker_4', 'worker_5', 'worker_6']);
const indexed = Object.fromEntries(options.map((v, i) => [i + 1, v]));
assert.deepEqual(model.TrainingSlots(indexed), ['worker_3', 'worker_4', 'worker_5', 'worker_6'], 'Lua numeric-key tables are normalized');
assert.deepEqual(model.Progress({finish_at: 12, duration: 2}, 11), {remaining: 1, fraction: .5});
assert.deepEqual(model.Progress({finish_at: 12, duration: 2}, 13), {remaining: 0, fraction: 1});

const nodes = {}, callbacks = {}, scheduled = [], sent = [], runtime = {}, dispatched = [];
let unit = 10, time = 10, modal = false, hitEntities = [{entityIndex: 10}], mouseHandler;
function panel(id, parent, type = 'Panel') {
    const p = {id, parent, type, style: {}, visible: true, classes: new Set(), children: [], handlers: {}, text: '',
        IsValid() { return true; }, SetImage(uri) { this.image = uri; }, FindChildTraverse(key) { return nodes[key] || null; },
        AddClass(c) { this.classes.add(c); }, SetHasClass(c, value) { value ? this.classes.add(c) : this.classes.delete(c); },
        RemoveAndDeleteChildren() { this.children = []; }, SetPanelEvent(event, handler) { this.handlers[event] = handler; }};
    if (parent) parent.children.push(p);
    if (id) nodes[id] = p;
    return p;
}
const ctx = panel('Context'); panel('SurvivalProductionPanel', ctx); panel('SurvivalResearchAutoMarkers', ctx);
const cfg = {SurvivalUILayers: {Top: () => modal}, SurvivalSelectionResolver: {ResolveDisplayUnit: () => unit},
    SurvivalInputDispatcher: {RegisterMouseHandler: (name, handler) => mouseHandler = handler}};
const env = {console, $, GameUI: {CustomUIConfig: () => cfg, GetScreenEntities: () => hitEntities, GetCursorPosition: () => [100, 100]},
    Game: {GetLocalPlayerID: () => 0, GetGameTime: () => time}, Players: {GetLocalPlayerPortraitUnit: () => unit},
    Entities: {GetUnitName: id => id === 10 || id === 11 ? 'building_main_city' : id === 20 ? 'building_research_lab' : id === 21 ? 'building_advanced_research_lab' : 'hero'},
    CustomNetTables: {GetTableValue: (name, key) => runtime[key]},
    GameEvents: {Subscribe: (name, callback) => {callbacks[name] = callback;}, SendCustomGameEventToServer: (name, payload) => sent.push({name, payload})}};
function $(id) { return nodes[id.slice(1)]; }
$.GetContextPanel = () => ctx; $.CreatePanel = (type, parent, id) => panel(id, parent, type);
$.DispatchEvent = (...args) => dispatched.push(args); $.Schedule = (delay, fn) => scheduled.push(fn);
vm.runInNewContext(fs.readFileSync(sourcePath, 'utf8'), env);
const hud = cfg.SurvivalProductionHUD, g = {x: 350, y: 700, scale: .5, heroWidth: 453, centerWidth: 498};
const freshOptions = () => options.map(v => ({...v, count: 0, queued_count: 0}));
function snapshot(training, extra = {}) { callbacks.ui_selected_unit_stats_snapshot({success: 1, player_id: 0, entindex: unit, training, ...extra}); }
function refresh(entries = []) { return hud.Refresh(g, unit, true, entries); }
refresh(); assert.equal(sent.at(-1).name, 'ui_selected_unit_stats_request');
snapshot({options: freshOptions(), queued: []}); refresh();
assert.equal(nodes.ProductionQueue.text, '等待 0/6', 'missing capacity metadata defaults to seven total tasks');
assert.equal(nodes.SurvivalProductionPanel.visible, true);
assert.deepEqual(Array.from(hud.Inspect().slots), ['worker_1', 'worker_2', 'worker_3', 'worker_4']);
nodes.ProductionTrainingSlot0.handlers.onactivate();
assert.equal(sent.at(-1).name, 'ui_worker_train_request');
assert.equal(sent.at(-1).payload.source_entindex, 10); assert.equal(sent.at(-1).payload.training_id, 'worker_1');
assert.match(sent.at(-1).payload.request_id, /^production_train_/);
const reserved = freshOptions(); reserved[0].queued_count = 3; reserved[0].available = 0; reserved[0].reason = 'training_max_count_reached';
snapshot({options: reserved, queued: []});
const beforeDisabled = sent.length; nodes.ProductionTrainingSlot0.handlers.onactivate();
assert.equal(sent.length, beforeDisabled, 'reserved capacity prevents extra UI requests');
assert.equal(nodes.ProductionTrainingSlot0.visible, true);
reserved[0].count = 3;
snapshot({options: reserved, queued: []}); refresh();
assert.equal(nodes.ProductionTrainingSlot0.visible, true);
assert.deepEqual(Array.from(hud.Inspect().slots), ['worker_2', 'worker_3', 'worker_4', 'worker_5'], 'completion immediately hides the capped level and adds the next level');
refresh();
assert.deepEqual(Array.from(hud.Inspect().slots), ['worker_2', 'worker_3', 'worker_4', 'worker_5']);
assert.equal(mouseHandler, undefined, 'no special world-click observer is needed to replenish entries');
reserved[1].count = 3; snapshot({options: reserved, queued: []});
assert.deepEqual(Array.from(hud.Inspect().slots), ['worker_3', 'worker_4', 'worker_5', 'worker_6'], 'two completed levels never leave LV5/LV6 ahead of LV3/LV4');
callbacks.dota_player_update_selected_unit({PlayerID: 1});
while (scheduled.length) scheduled.shift()();
assert.deepEqual(Array.from(hud.Inspect().slots), ['worker_3', 'worker_4', 'worker_5', 'worker_6']);
const activeJob = {training_id: 'worker_3', level: 3, name: '伐木工', duration: 2, started_at: 10, finish_at: 12};
snapshot({options: reserved, active_job: activeJob, queued: [{level: 4}], queue_capacity: 7}, {refresh_sequence: 2});
time = 11; refresh();
assert.equal(nodes.ProductionRemaining.text, '1s'); assert.equal(nodes.ProductionProgressFill.style.width, '50.0%');
refresh(); assert.equal(nodes.ProductionProgressFill.style.width, '50.0%', 'paused game time preserves progress');
callbacks.ui_selected_unit_stats_snapshot({success: 1, entindex: 10, refresh_sequence: 3, attack: 5});
assert.equal(nodes.ProductionRemaining.text, '1s', 'combat-only pushes preserve production fields');
assert.equal(nodes.SurvivalProductionPanel.visible, true);
callbacks.ui_selected_unit_stats_snapshot({success: 1, entindex: 10, refresh_sequence: 1, training: {options: []}});
assert.equal(nodes.ProductionRemaining.text, '1s', 'older snapshots do not overwrite the active queue');
assert.equal(nodes.ProductionQueue.text, '等待 1/6');
assert.equal(nodes.ProductionQueueSlot0.level.text, 'LV4');
assert.equal(nodes.ProductionQueueSlot1.classes.has('Empty'), true, 'waiting queue keeps six empty/occupied icon frames');
snapshot({options: reserved, active_job: activeJob, queued: [3,4,5,6,7,8].map(level => ({level})), queue_capacity: 7}, {refresh_sequence: 4});
assert.equal(nodes.ProductionQueue.text, '等待 6/6');
assert.equal(nodes.ProductionQueueSlot5.visible, true);
assert.equal(nodes.ProductionQueueSlot5.level.text, 'LV8', 'the sixth training wait cell renders its own task');
assert.equal(nodes.ProductionQueueSlot5.workerIcon.image, 'file://{images}/spellicons/survival/native/train_lumberjack_08.png');
assert.equal(nodes.ProductionQueueSlot5.workerIcon.visible, true);
assert.equal(nodes.ProductionQueueSlot5.icon.visible, false);
assert.equal(nodes.ProductionQueueSlot5.classes.has('Empty'), false);
assert.equal(nodes.ProductionQueueSlot5.style.width, '58px', 'adding the sixth cell retains readable icon size');
assert.equal(nodes.ProductionTrainingSlot4, undefined, 'training level entrance count remains exactly four');

unit = 11; refresh(); snapshot({options: freshOptions(), queued: []});
assert.deepEqual(Array.from(hud.Inspect().slots), ['worker_1', 'worker_2', 'worker_3', 'worker_4'], 'cities retain independent entry slots');
unit = 99; refresh(); assert.equal(nodes.SurvivalProductionPanel.visible, false, 'nonproduction units have no panel');
unit = 20; refresh();
runtime[201] = {owner_entindex: 20, technology_group: 'worker_attack', auto_research_available: 1, auto_research_enabled: 1};
const research = {researching: 1, display_name: '伐木效率', ability_name: 'ability_research_worker_attack', target_level: 2, started_at: 10, finish_at: 12, duration: 2, auto_enabled: 1, auto_research: {worker_attack: 1}};
snapshot(undefined, {research});
refresh([{ability: 201, name: 'ability_research_worker_attack'}]);
assert.equal(nodes.ProductionTitle.text, '科技研究'); assert.equal(nodes.ProductionMode.text, '自动研究');
assert.equal(nodes.ProductionRemaining.text, '1s'); assert.equal(nodes.ProductionResearchAuto0.visible, true);
assert.equal(nodes.ProductionCurrentIcon.abilityname, 'ability_research_worker_attack');
assert.equal(nodes.ProductionQueueSlot0.visible, true, 'research also displays six waiting positions');
const waiting = [
    {technology_group: 'worker_attack', display_name: '伐木效率', target_level: 3, ability_name: 'ability_research_worker_attack'},
    {technology_group: 'tower_attack', display_name: '箭塔攻击', target_level: 1, ability_name: 'ability_research_tower_attack'}
];
snapshot(undefined, {research: {...research, queued: waiting, queue_count: 3, queue_capacity: 7}});
assert.equal(nodes.ProductionQueue.text, '等待 2/6');
assert.equal(nodes.ProductionQueueSlot0.level.text, 'LV3');
assert.equal(nodes.ProductionQueueSlot1.icon.abilityname, 'ability_research_tower_attack');
assert.equal(nodes.ProductionQueueSlot2.classes.has('Empty'), true);
const fullResearchWaiting = waiting.concat([
    {technology_group: 'tower_speed', target_level: 4, ability_name: 'ability_research_tower_speed'},
    {technology_group: 'worker_speed', target_level: 5, ability_name: 'ability_research_worker_speed'},
    {technology_group: 'worker_attack', target_level: 6, ability_name: 'ability_research_worker_attack'},
    {technology_group: 'tower_attack', target_level: 2, ability_name: 'ability_research_tower_attack'}
]);
snapshot(undefined, {research: {...research, queued: fullResearchWaiting, queue_count: 7, queue_capacity: 7}});
assert.equal(nodes.ProductionQueue.text, '等待 6/6');
assert.equal(nodes.ProductionQueueSlot5.visible, true);
assert.equal(nodes.ProductionQueueSlot5.level.text, 'LV2', 'the sixth research wait cell renders its target level');
assert.equal(nodes.ProductionQueueSlot5.icon.abilityname, 'ability_research_tower_attack');
assert.equal(nodes.ProductionQueueSlot5.classes.has('Empty'), false);
const sixthCellRight = Number(nodes.ProductionQueueSlot5.style.position.split('px')[0]) + Number(nodes.ProductionQueueSlot5.style.width.replace('px',''));
assert(sixthCellRight < Number(nodes.SurvivalProductionPanel.style.width.replace('px','')), 'six full-size waiting cells fit the panel width');

runtime[201].available = 0;
assert.equal(hud.QueueResearch(201, 20), true, 'a busy research ability can add another queue task');
assert.equal(sent.at(-1).name, 'ui_research_queue_request');
assert.equal(sent.at(-1).payload.source_entindex, 20);
assert.equal(sent.at(-1).payload.technology_group, 'worker_attack');
assert.equal(hud.QueueResearch(201, 11), false, 'queue source must be the selected laboratory');
modal = true; assert.equal(hud.QueueResearch(201, 20), false); modal = false;
snapshot(undefined, {research: {...research, researching: 0, blocked_head: waiting[0], blocked_reason: 'wood_not_enough', queued: [waiting[1]], queue_capacity: 7}});
assert.equal(nodes.ProductionJobName.text, '等待研究：伐木效率 LV3');
assert.equal(nodes.ProductionRemaining.text, '等待');
assert.equal(nodes.ProductionCurrentIcon.abilityname, 'ability_research_worker_attack');
assert.equal(nodes.ProductionQueue.text, '等待 1/6', 'the blocked head occupies the current position, not a waiting slot');
assert.equal(nodes.ProductionFooter.text, '木材不足 · 开始时扣费');
snapshot(undefined, {research: {...research, researching: 0, blocked_head: waiting[0], blocked_reason: '木材不足；开始研究时扣费', queued: []}});
assert.equal(nodes.ProductionFooter.text, '木材不足；开始研究时扣费', 'server cost-timing text is not repeated');
snapshot(undefined, {research});

runtime[201].auto_research_available = 0;
assert.equal(hud.ToggleResearch(201, 20), true, 'shared-lab owner max-level metadata cannot block another player auto request');
assert.equal(sent.at(-1).name, 'ui_shop_auto_research_toggle_request'); assert.equal(sent.at(-1).payload.technology_group, 'worker_attack');
assert.equal(hud.ToggleResearch(201, 11), false, 'right-click cannot target an unselected source');
modal = true; assert.equal(hud.ToggleResearch(201, 20), false); modal = false;
snapshot(undefined, {research: {...research, auto_enabled: 0, auto_research: {}}});
refresh([{ability: 201, name: 'ability_research_worker_attack'}]);
assert.equal(nodes.ProductionResearchAuto0.visible, false, 'building owner auto state cannot leak into private viewer markers');
time = 12; snapshot(undefined, {research: {...research, researching: 0, next_start_at: 13}});
assert.equal(nodes.ProductionJobName.text, '下一次自动研究'); assert.equal(nodes.ProductionRemaining.text, '1s');
time = 13; refresh(); assert.equal(nodes.ProductionJobName.text, '自动待命 · 等待资源或前置条件');
time = 13.5; snapshot(undefined, {research: {...research, started_at: 13, finish_at: 15, target_level: 3}});
assert.equal(nodes.ProductionRemaining.text, '2s'); assert.equal(nodes.ProductionProgressFill.style.width, '25.0%', 'research duration remains independent of the one-second restart delay');
// A shared laboratory must render the viewer's complete technology details,
// never reuse its owner's levels, price, busy state or automation flag.
const ownerRuntime = {ability_name: 'ability_research_lumberjack_speed', current_level: 9,
    cost_wood: 9999, auto_research_enabled: 1, technology_group: 'lumberjack_speed'};
let personalRuntime = hud.GetResearchRuntime(201, 20, ownerRuntime);
assert.equal(personalRuntime.current_level, '—');
assert.equal(personalRuntime.status_text, '正在同步科技信息');
assert.equal(personalRuntime.cost_wood, 0, 'owner price must not flash before private snapshot arrives');
const viewerRuntime = {research_upgrade: 1, current_level: 2, next_level: 3,
    cost_wood: 300, cost_gold: 10, auto_research_enabled: 0, available: 1,
    technology_group: 'lumberjack_speed', fields: [{label: 'viewer', value: 2}]};
snapshot(undefined, {research: {...research, abilities_by_name: {ability_research_lumberjack_speed: viewerRuntime}}});
personalRuntime = hud.GetResearchRuntime(201, 20, ownerRuntime);
assert.equal(personalRuntime.current_level, 2); assert.equal(personalRuntime.cost_wood, 300);
assert.equal(personalRuntime.auto_research_enabled, 0); assert.equal(personalRuntime.fields[0].value, 2);
assert.equal(ownerRuntime.current_level, 9, 'public runtime remains unchanged');
const ordinaryRuntime = {ability_name: 'ability_upgrade_tower', current_level: 9};
assert.strictEqual(hud.GetResearchRuntime(202, 20, ordinaryRuntime), ordinaryRuntime);
const tooltipSource = fs.readFileSync('panorama/src/scripts/custom_game/ability_tooltip.js', 'utf8');
const reader = tooltipSource.slice(tooltipSource.indexOf('    function readTooltipTable('), tooltipSource.indexOf('    function cancelChecks('));
const readerEnv = {bindingSnapshot: null, selectedUnit: () => 20, GameUI: env.GameUI,
    CustomNetTables: {GetTableValue: () => ownerRuntime}};
vm.runInNewContext(reader, readerEnv);
assert.equal(readerEnv.readTooltipTable('survival_ability_runtime', '201').current_level, 2);
readerEnv.bindingSnapshot = {unit: 20, tables: {}};
assert.equal(readerEnv.readTooltipTable('survival_ability_runtime', '201').cost_wood, 300);
assert.strictEqual(readerEnv.readTooltipTable('unrelated', 'x'), ownerRuntime);
const statusSource = tooltipSource.slice(tooltipSource.indexOf('    function researchStatus('), tooltipSource.indexOf('    function addField('));
const statusEnv = {localize: (key, fallback) => fallback}; vm.runInNewContext(statusSource, statusEnv);
for (const code of ['queue_available', 'queue_waiting_prerequisite', 'research_queue_full', 'queued_max_level']) {
    assert.equal(statusEnv.researchStatus({research_status_code: code, status_text: '个人队列状态'}), '个人队列状态');
}
const combatSource = fs.readFileSync('panorama/src/scripts/custom_game/combat_stats.js', 'utf8');
const executeSource = combatSource.slice(combatSource.indexOf('    function executeAbility('), combatSource.indexOf('    GameUI.CustomUIConfig().SurvivalAbilityInput ='));
let routedQueueCalls = 0;
const routedCfg = {SurvivalProductionHUD: {QueueResearch: (ability, source) => {assert.equal(ability, 201); assert.equal(source, 20); routedQueueCalls++; return true;}}};
const routedEnv = {abilityRuntime: () => ({ability_name: 'ability_research_worker_attack', available: 0}), casterForAbility: () => 20,
    GameUI: {CustomUIConfig: () => routedCfg}, $: {Msg: () => {}}, Abilities: {GetAbilityName: () => 'ability_research_worker_attack'}};
vm.runInNewContext(executeSource, routedEnv);
assert.equal(routedEnv.executeAbility(201), true, 'shared central click/hotkey path reaches queue before native disabled-state rejection');
assert.equal(routedQueueCalls, 1);
routedEnv.abilityRuntime = () => ({ability_name: 'ability_upgrade_tower', available: 0});
assert.equal(routedEnv.executeAbility(201), false, 'non-research disabled actions retain their existing rejection');
const takeoverSource = fs.readFileSync('panorama/src/scripts/custom_game/hud_takeover.js', 'utf8');
const activateSource = takeoverSource.slice(takeoverSource.indexOf('    function activate(entry)'), takeoverSource.indexOf('    function ensureSlot('));
const takeoverEnv = {config: routedCfg, selectedUnit: () => 20}; vm.runInNewContext(activateSource, takeoverEnv);
takeoverEnv.activate({name: 'ability_research_worker_attack', ability: 201});
assert.equal(routedQueueCalls, 2, 'fallback input uses the same research queue admission route');
assert.equal(nodes.SurvivalProductionPanel.style.transform, 'scale3d(0.575,0.575,1)');
hud.Refresh({...g, scale: .32}, unit, true, []);
assert.equal(nodes.SurvivalProductionPanel.style.transform, 'scale3d(0.575,0.575,1)', 'dense native ability rows cannot shrink production labels below the readable panel scale');
assert.equal(nodes.SurvivalProductionPanel.__survivalWindowWidth, 345);
assert.equal(nodes.SurvivalProductionPanel.__survivalWindowHeight, 155.25);
ctx.actualuiscale_x=2;ctx.actualuiscale_y=1.5;
hud.Refresh({...g,scale:.32},unit,true,[]);
assert.equal(nodes.SurvivalProductionPanel.__survivalWindowWidth,690,'published physical width includes both the panel transform and viewport scale');
assert.equal(nodes.SurvivalProductionPanel.__survivalWindowHeight,232.875,'published physical height includes viewport scaling exactly once');
ctx.actualuiscale_x=1;ctx.actualuiscale_y=1;
// Exercise the real advanced-laboratory unit name and its dense native HUD geometry.
const geometry = require('../panorama/src/scripts/custom_game/geometry_remaining_5d5c1152eb.js');
const advancedGeometry = geometry(1920,1080,10);
snapshot(undefined,{research:{...research,queued:waiting,queue_capacity:7}});
unit=21;hud.Refresh(advancedGeometry,unit,true,[]);
const longTechnologyName='高阶伐木工训练及全军远程攻击强化科技';
const advancedResearch={...research,display_name:longTechnologyName,queued:fullResearchWaiting,queue_count:7,queue_capacity:7};
snapshot(undefined,{research:advancedResearch});
assert.equal(nodes.ProductionTitle.text,'高级科技研究');
assert.equal(nodes.ProductionQueue.text,'等待 6/6');
assert.equal(nodes.ProductionQueueSlot5.visible,true);
assert.equal(nodes.ProductionQueueSlot5.level.text,'LV2');
assert.equal(nodes.ProductionJobName.text,'正在研究：'+longTechnologyName+' LV2','long technology names retain their full text');
nodes.ProductionJobName.handlers.onmouseover();
assert(dispatched.at(-1)[2].includes(longTechnologyName),'hover exposes the complete name if a long title exceeds its two-line area');
const css = fs.readFileSync('panorama/src/styles/custom_game/production_progress.css','utf8');
assert(!/text-overflow:\s*shrink/.test(css),'readability must not be silently reduced by text-overflow shrink');
assert(/\.ProductionJobName\s*\{[^}]*white-space:\s*normal/.test(css),'job names use a multiline region');
const fontSize = name => Number(css.match(new RegExp('\\.'+name+'\\s*\\{[^}]*font-size:\\s*(\\d+)px'))[1]);
const displayScale=Number(nodes.SurvivalProductionPanel.style.transform.match(/scale3d\(([^,]+)/)[1]);
for(const [name,oldFont] of [['ProductionTitle',34],['ProductionJobName',31],['ProductionRemaining',32],['ProductionQueue',26],['ProductionTrainingCost',24]]) {
    const increase=fontSize(name)*displayScale/(oldFont*Math.max(advancedGeometry.scale,.5));
    assert(increase>=1.2&&increase<=1.26, name+' gains 20-26% actual screen font size, including dense advanced-lab layouts');
}
assert(Number(nodes.ProductionJobName.style.height.replace('px',''))>=fontSize('ProductionJobName')*2,'job row reserves height for two full-size text lines');
const panelPos=nodes.SurvivalProductionPanel.style.position.split(' ').map(parseFloat);
const panelHeight=Number(nodes.SurvivalProductionPanel.style.height.replace('px',''));
assert(panelPos[1]+panelHeight*displayScale<advancedGeometry.y,'wider production panel stays above the portrait nameplate');
assert.equal(nodes.SurvivalProductionPanel.__survivalWindowHeight,panelHeight*displayScale,'world occlusion follows the actual enlarged display bounds');
callbacks.ui_selected_unit_stats_snapshot({success:1,player_id:1,entindex:21,research:{...research,queued:[],queue_capacity:7}});
assert.equal(nodes.ProductionQueue.text,'等待 6/6','another player cannot overwrite the viewer private advanced-lab queue');
unit=20;refresh();
assert.equal(nodes.ProductionTitle.text,'科技研究');
assert.equal(nodes.ProductionQueue.text,'等待 2/6','switching laboratories restores that laboratory private queue');
// Use the actual shared resource formatter; full prices remain in the hover tooltip.
const bootstrap=fs.readFileSync('panorama/src/scripts/custom_game/ui_bootstrap.js','utf8');
vm.runInNewContext(bootstrap.slice(bootstrap.indexOf('    function trimmedNumber('),bootstrap.indexOf('    $.Msg("[SURVIVAL_CRASH_ISOLATION]')),env);
unit=11;refresh();
const expensive=freshOptions();expensive[0].cost_wood=123456789;
snapshot({options:expensive,queued:[],queue_capacity:7});
const costLabel=nodes.ProductionTrainingSlot0.children.find(child=>child.classes.has('ProductionTrainingCost'));
assert.equal(costLabel.text,'木 1.2亿','large prices use the shared compact number format instead of shrinking the cost font');
nodes.ProductionTrainingSlot0.handlers.onmouseover();
assert(dispatched.at(-1)[2].includes('123456789'),'full authoritative cost remains available in the training tooltip');
assert(Number(costLabel.style.width.replace('px',''))>=120,'training prices retain enough width at the minimum panel size');
const card=nodes.ProductionTrainingSlot0;
const textRows=['ProductionTrainingCount','ProductionTrainingCost','ProductionTrainingLock'].map(name=>card.children.find(child=>child.classes.has(name)));
for(let index=0;index<textRows.length-1;index++) {
    const bottom=parseFloat(textRows[index].style.position.split(' ')[1])+parseFloat(textRows[index].style.height);
    assert(bottom<=parseFloat(textRows[index+1].style.position.split(' ')[1]),'larger count/cost/action rows must not overlap');
}
assert(parseFloat(textRows[2].style.position.split(' ')[1])+parseFloat(textRows[2].style.height)<=parseFloat(card.style.height),'the last enlarged text row fits inside the card');
console.log('PRODUCTION_HUD_PASS: queue routing and private snapshots, six waiting cells plus current task, ordinary/advanced parity, full long-name tooltip, readable compact costs, larger physical text and exact occlusion');