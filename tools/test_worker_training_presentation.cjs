"use strict";
// Exercise the actual Panorama controller with a small native-panel fixture.
// No Dota process, network traffic, timers, or gameplay state are touched.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const sourcePath = process.argv[2] || path.join(__dirname, "../panorama/src/scripts/custom_game/production_progress.js");
const source = fs.readFileSync(sourcePath, "utf8");
const model = require(path.resolve(sourcePath));

function options() {
    return Array.from({length: 8}, (_, index) => ({
        training_id: "train_lumberjack_0" + (index + 1), level: index + 1,
        name: "伐木工LV" + (index + 1), count: 0, max_count: index ? 3 : 5,
        queued_count: 0, available: 1, prerequisite_met: 1,
        cost_wood: [10, 100, 500, 1000, 5000, 30000, 150000, 400000][index],
        train_duration: 1, population: 1
    }));
}

function fixture() {
    const nodes = {}, callbacks = {}, sent = [], dispatched = [], scheduled = [];
    let unit = 10, time = 10, modal = false;
    function panel(type, parent, id) {
        const result = {id: id || "", type, parent, children: [], style: {},
            visible: true, text: "", classes: new Set(), handlers: {},
            IsValid() { return true; },
            FindChildTraverse(key) { return nodes[key] || null; },
            AddClass(name) { this.classes.add(name); },
            SetHasClass(name, enabled) { enabled ? this.classes.add(name) : this.classes.delete(name); },
            RemoveAndDeleteChildren() { this.children = []; },
            SetPanelEvent(name, callback) { this.handlers[name] = callback; },
            SetImage(uri) { this.image = uri; }
        };
        if (parent) parent.children.push(result);
        if (id) nodes[id] = result;
        return result;
    }
    const ctx = panel("Panel", null, "Context");
    panel("Panel", ctx, "SurvivalProductionPanel");
    panel("Panel", ctx, "SurvivalResearchAutoMarkers");
    const cfg = {SurvivalUILayers: {Top: () => modal},
        SurvivalSelectionResolver: {ResolveDisplayUnit: () => unit},
        SurvivalNumberFormatter: {Format: value => Number(value) >= 10000 ? "1.2亿" : String(value)}};
    const $ = id => nodes[id.slice(1)];
    $.GetContextPanel = () => ctx;
    $.CreatePanel = panel;
    $.DispatchEvent = (...args) => dispatched.push(args);
    $.Schedule = (delay, callback) => scheduled.push(callback);
    vm.runInNewContext(source, {
        $, GameUI: {CustomUIConfig: () => cfg},
        Game: {GetLocalPlayerID: () => 0, GetGameTime: () => time},
        Players: {GetLocalPlayerPortraitUnit: () => unit},
        Entities: {GetUnitName: id => id === 10 || id === 11 ? "building_main_city" : id === 20 ? "building_research_lab" : "hero"},
        CustomNetTables: {GetTableValue: () => null},
        GameEvents: {Subscribe: (name, callback) => callbacks[name] = callback,
            SendCustomGameEventToServer: (name, payload) => sent.push({name, payload})}
    }, {filename: sourcePath});
    const geometry = {x: 350, y: 700, scale: .5, height: 330, minimapSize: 220,
        heroWidth: 453, centerWidth: 498};
    return {nodes, callbacks, sent, dispatched, cfg, ctx,
        refresh() { return cfg.SurvivalProductionHUD.Refresh(geometry, unit, true, []); },
        snapshot(data) { callbacks.ui_selected_unit_stats_snapshot({success: 1, player_id: 0, entindex: unit, ...data}); },
        select(value) { unit = value; this.refresh(); },
        setTime(value) { time = value; },
        setModal(value) { modal = value; }
    };
}

function allDescendants(panel) {
    return panel.children.flatMap(child => [child, ...allDescendants(child)]);
}
function visible(panel) {
    return !!panel && panel.visible !== false && panel.style.visibility !== "collapse"
        && (!panel.parent || visible(panel.parent));
}
function byClass(panel, name) {
    return allDescendants(panel).filter(child => child.classes.has(name));
}

const available = options();
assert.deepEqual(model.TrainingSlots(available), available.slice(0, 4).map(option => option.training_id));
available[0].queued_count = 5;
assert.deepEqual(model.TrainingSlots(available), available.slice(1, 5).map(option => option.training_id),
    "all five places reserved by active and waiting jobs immediately remove the LV1 entrance");
available[0].count = 2; available[0].queued_count = 2;
assert.equal(model.TrainingSlots(available)[0], available[0].training_id,
    "two alive and two queued leave one of five places available");
available[0].queued_count = 3;
assert.equal(model.TrainingSlots(available)[0], available[1].training_id,
    "alive plus queued places are counted together");
available[0].count = 0; available[0].queued_count = 4;
assert.equal(model.TrainingSlots(available)[0], available[0].training_id,
    "queued_count already contains the active job and must not count it twice");
available[0].pending_count = 1;
assert.equal(model.TrainingSlots(available)[0], available[1].training_id,
    "a single unconfirmed local request reserves the last free place");
available[0].pending_count = 0;
available[0].max_count = 0; available[0].queued_count = 0;
assert.equal(model.TrainingSlots(available)[0], available[1].training_id,
    "a zero cap has no training place and must not be presented as unlimited");
available[0].max_count = -1; available[0].queued_count = 100;
assert.equal(model.TrainingSlots(available)[0], available[0].training_id, "uncapped options remain visible");

const f = fixture();
f.refresh();
f.snapshot({training: {options: options(), queued: [], queue_capacity: 7}});
f.refresh();
const root = f.nodes.SurvivalProductionPanel;
assert(visible(root));
for (const id of ["ProductionTitle", "ProductionJobName", "ProductionCurrentWorkerIcon", "ProductionFooter"]) {
    assert(!visible(f.nodes[id]), id + " is removed from the worker-training presentation");
}
for (const card of byClass(root, "ProductionTrainingSlot").filter(visible)) {
    const abilityIcon = byClass(card, "ProductionTrainingIcon").find(visible);
    assert.equal(abilityIcon.style.position, "0px 0px 0px", "the skill art starts at the button origin");
    assert.equal(abilityIcon.style.width, card.style.width, "the skill art fills the complete button width");
    assert.equal(abilityIcon.style.height, card.style.height, "the skill art fills the complete button height");
    assert.equal(byClass(card, "ProductionTrainingLevel").filter(visible).length, 0,
        "the annotated LV caption is not rendered on training cards");
    assert.equal(byClass(card, "ProductionTrainingLock").filter(visible).length, 0,
        "the annotated training/lock caption is not rendered on training cards");
    const cost = byClass(card, "ProductionTrainingCost").find(visible);
    assert(cost && /^\d/.test(cost.text) && !/木|材/.test(cost.text),
        "the cost label contains only the amount");
    const icons = allDescendants(card).filter(child => visible(child) && child.type === "Image");
    assert(icons.some(icon => /^file:\/\/\{images\}\/custom_game\/hud_resources_v2\/wood\.svg$/.test(icon.image || "")),
        "every visible training card renders the native wood Image");
}

const tiers = fixture(), tierHues = new Set(), tierBorders = new Set();
tiers.refresh();
for (const firstLevel of [1, 5]) {
    const tierOptions = options();
    tierOptions.filter(option => option.level < firstLevel).forEach(option => { option.count = option.max_count; });
    tiers.snapshot({training: {options: tierOptions, queued: [], queue_capacity: 7}});tiers.refresh();
    for (const card of byClass(tiers.nodes.SurvivalProductionPanel, "ProductionTrainingSlot").filter(visible)) {
        tierHues.add(byClass(card, "ProductionTrainingIcon").find(visible).style.hueRotation);
        tierBorders.add(card.style.borderColor);
    }
}
assert.equal(tierHues.size, 8, "all eight training levels have distinct icon colors");
assert.equal(tierBorders.size, 8, "all eight training levels have matching distinct border colors");

const currentCell = f.nodes.ProductionTrainingCurrentCell;
assert(currentCell, "training owns an explicit first current-task cell");
assert(visible(currentCell), "the current-task frame is visible before waiting positions");
const active = {training_id: "train_lumberjack_01", level: 1, name: "伐木工LV1",
    duration: 2, started_at: 10, finish_at: 12, job_id: "current"};
const waiting = Array.from({length: 6}, (_, index) => ({
    training_id: "train_lumberjack_0" + (index + 2), level: index + 2, job_id: "waiting_" + index
}));
f.snapshot({training: {options: options(), active_job: active, queued: waiting, queue_capacity: 7}});
f.setTime(11); f.refresh();
assert.equal(f.nodes.ProductionRemaining.text, "1s");
assert.equal(f.nodes.ProductionProgressFill.style.width, "50.0%");
assert.equal(currentCell.job && currentCell.job.job_id, active.job_id,
    "the first cell references the active task");
assert(currentCell.classes.has("Current"), "the active first cell has the current-task highlight");
currentCell.handlers.onmouseover();
assert.match(f.dispatched.at(-1)[2], /正在训练/);
assert.equal(f.nodes.ProductionQueueSlot0.job.job_id, waiting[0].job_id,
    "the second cell starts with the first waiting task");
assert.equal(f.nodes.ProductionQueueSlot5.job.job_id, waiting[5].job_id,
    "six waiting places remain available after the current task");
assert.equal(f.nodes.ProductionQueue.text, "等待 6/6", "the active task is not included in the waiting count");
const coordinate = panel => panel.style.position.split(" ").map(parseFloat);
assert(coordinate(currentCell)[0] < coordinate(f.nodes.ProductionQueueSlot0)[0],
    "the current task is left of all waiting tasks");
const last = f.nodes.ProductionQueueSlot5;
assert(coordinate(last)[0] + parseFloat(last.style.width) <= parseFloat(root.style.width),
    "all seven task cells fit within the panel");
const ids = [currentCell, ...Array.from({length: 6}, (_, index) => f.nodes["ProductionQueueSlot" + index])]
    .map(cell => cell.job && cell.job.job_id);
assert.equal(new Set(ids).size, 7, "no active task is duplicated in the waiting slots");

// An unfunded queue head belongs in the current position, but has no progress.
f.snapshot({training: {options: options(), blocked_head: active, blocked_reason: "wood_not_enough",
    queued: [waiting[0]], queue_capacity: 7}});
f.refresh();
assert.equal(currentCell.job && currentCell.job.job_id, active.job_id);
assert(!currentCell.classes.has("Current"), "the unfunded head is not styled as actively training");
assert.equal(f.nodes.ProductionQueueSlot0.job.job_id, waiting[0].job_id);
assert.equal(f.nodes.ProductionQueue.text, "等待 1/6");
assert.equal(f.nodes.ProductionProgressTrack.visible, false);
assert.equal(f.nodes.ProductionRemaining.text, "等待");

// A delayed server snapshot must not leave a sixth LV1 click available.
const rapid = fixture(); rapid.refresh();
rapid.snapshot({training: {options: options(), queued: [], queue_capacity: 7}});
for (let index = 0; index < 5; index++) rapid.nodes.ProductionTrainingSlot0.handlers.onactivate();
const requests = rapid.sent.filter(event => event.name === "ui_worker_train_request");
assert.equal(requests.length, 5);
assert(requests.every(event => event.payload.training_id === "train_lumberjack_01"));
assert.equal(Array.from(rapid.cfg.SurvivalProductionHUD.Inspect().slots)[0], "train_lumberjack_02",
    "the fifth click immediately hides LV1 before any server response");

function trainingAt(queued, revision) {
    const entries = options(); entries[0].queued_count = queued;
    return {options: entries, queued: [], queue_capacity: 7, queue_revision: revision};
}
function trainRequests(view) {
    return view.sent.filter(event => event.name === "ui_worker_train_request");
}
function reply(view, request, success, training, source = 10) {
    view.callbacks.ui_operation_result({operation: "worker_train", success: success ? 1 : 0,
        request_id: request.payload.request_id, source_entindex: source, training,
        error: success ? "" : "wood_not_enough"});
}

// A rejection returns the authoritative reservation to four; it must reveal
// the fifth free place rather than leaving the optimistic cap stuck forever.
reply(rapid, requests[4], false, trainingAt(4, 5));
assert.equal(Array.from(rapid.cfg.SurvivalProductionHUD.Inspect().slots)[0], "train_lumberjack_01",
    "a rejected fifth request restores its unoccupied place");
rapid.nodes.ProductionTrainingSlot0.handlers.onactivate();
assert.equal(Array.from(rapid.cfg.SurvivalProductionHUD.Inspect().slots)[0], "train_lumberjack_02",
    "retrying the free fifth place removes the entrance again");
const retried = trainRequests(rapid).at(-1);
reply(rapid, retried, true, trainingAt(5, 6));
assert.equal(Array.from(rapid.cfg.SurvivalProductionHUD.Inspect().slots)[0], "train_lumberjack_02",
    "the confirmed fifth place stays hidden after the receipt");
rapid.snapshot({training: trainingAt(4, 5)});
assert.equal(Array.from(rapid.cfg.SurvivalProductionHUD.Inspect().slots)[0], "train_lumberjack_02",
    "an older snapshot cannot resurrect a fully reserved entrance");

// Snapshots may overtake operation receipts. Existing reservations, accepted
// clicks, and unconfirmed local clicks must each contribute only once.
const ordered = fixture(); ordered.refresh(); ordered.snapshot({training: trainingAt(2, 2)});
ordered.nodes.ProductionTrainingSlot0.handlers.onactivate();
ordered.nodes.ProductionTrainingSlot0.handlers.onactivate();
const orderedRequests = trainRequests(ordered);
ordered.snapshot({training: trainingAt(4, 4)});
assert.equal(Array.from(ordered.cfg.SurvivalProductionHUD.Inspect().slots)[0], "train_lumberjack_01",
    "an ahead-of-receipt snapshot of four reservations must not add the same two pending clicks again");
reply(ordered, orderedRequests[0], true, trainingAt(3, 3));
assert.equal(Array.from(ordered.cfg.SurvivalProductionHUD.Inspect().slots)[0], "train_lumberjack_01",
    "an older first-click receipt preserves the latest four-place snapshot");
reply(ordered, orderedRequests[1], true, trainingAt(4, 4));
ordered.nodes.ProductionTrainingSlot0.handlers.onactivate();
assert.equal(Array.from(ordered.cfg.SurvivalProductionHUD.Inspect().slots)[0], "train_lumberjack_02",
    "the remaining fifth place can still be requested exactly once");

// Pending reservations belong to the requested city, even when the selection
// changes before that city's operation result arrives.
const cities = fixture(); cities.refresh(); cities.snapshot({training: trainingAt(4, 10)});
cities.nodes.ProductionTrainingSlot0.handlers.onactivate();
const city10Request = trainRequests(cities)[0];
cities.select(11); cities.snapshot({training: trainingAt(0, 1)});
assert.equal(Array.from(cities.cfg.SurvivalProductionHUD.Inspect().slots)[0], "train_lumberjack_01",
    "city 10 pending requests never reserve city 11 places");
reply(cities, city10Request, true, trainingAt(5, 11), 10);
assert.equal(Array.from(cities.cfg.SurvivalProductionHUD.Inspect().slots)[0], "train_lumberjack_01",
    "an unselected city's receipt does not change the selected city's entrances");
cities.select(10);
assert.equal(Array.from(cities.cfg.SurvivalProductionHUD.Inspect().slots)[0], "train_lumberjack_02",
    "returning to the city restores its confirmed fully reserved entrance list");

// Research retains the existing dedicated active row and all six cancelable
// waiting cells; compact training must not leave these controls hidden.
f.select(20);
f.snapshot({research: {researching: 1, display_name: "伐木效率", level: 2,
    ability_name: "ability_research_worker_attack", started_at: 10, finish_at: 12, duration: 2,
    active_job: {job_id: "research_active", technology_group: "worker_attack"},
    queued: waiting.map((entry, index) => ({job_id: "research_" + index,
        technology_group: "worker_attack", target_level: index + 3,
        ability_name: "ability_research_worker_attack"})), queue_capacity: 7}});
f.refresh();
assert(!visible(currentCell), "the compact training-current cell is absent from research");
for (const id of ["ProductionTitle", "ProductionJobName", "ProductionFooter", "ProductionCurrentIcon"]) {
    assert(visible(f.nodes[id]), id + " returns when switching to research");
}
assert.equal(f.nodes.ProductionQueue.text, "等待 6/6");
f.nodes.ProductionQueueSlot5.handlers.onactivate();
assert.equal(f.sent.at(-1).name, "ui_research_cancel_request");
assert.equal(f.sent.at(-1).payload.job_id, "research_5");

console.log("WORKER_TRAINING_PRESENTATION_PASS: reservation thresholds; annotated captions removed; wood icons; current plus six waiting cells; blocked head; immediate fifth-click replacement; rejection recovery; receipt/snapshot order; city isolation; research cancellation preserved");
