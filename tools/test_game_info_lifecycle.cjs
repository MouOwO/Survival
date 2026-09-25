"use strict";

// Execute the shipped authoring script with a deterministic Panorama host. Counts
// below are UI operations, not a claim about in-game frame times.
const assert = require("assert");
const fs = require("fs");
const vm = require("vm");
const { execFileSync } = require("child_process");
const sourcePath = "panorama/src/scripts/custom_game/game_info_panel.js";

function fixture(source, options = {}) {
    let now = 0, serial = 0, currentRoot;
    const jobs = new Map(), listeners = new Map(), handlers = {}, requests = [];
    const stats = { callbacks: 0, scheduled: 0, created: 0, removed: 0, textWrites: 0, healthReads: 0 };
    const tables = { player_0: snapshot() };
    const cfg = { SurvivalInputDispatcher: { RegisterKeyHandler(id, fn) { handlers[id] = fn; } } };
    const health = { current: 120, maximum: 300 };
    class Panel {
        constructor(type, parent, id) {
            this.type = type; this.parent = parent; this.id = id;
            this.children = []; this.classes = new Set(); this.style = {};
            this.valid = true; this._text = "";
            if (parent) parent.children.push(this);
        }
        IsValid() { return this.valid; }
        AddClass(name) { this.classes.add(name); }
        SetHasClass(name, active) { active ? this.classes.add(name) : this.classes.delete(name); }
        RemoveAndDeleteChildren() {
            function remove(node) { stats.removed++; node.valid = false; node.children.forEach(remove); }
            this.children.forEach(remove); this.children = [];
        }
        FindChildTraverse(id) {
            if (this.id === id) return this;
            for (const child of this.children) { const match = child.FindChildTraverse(id); if (match) return match; }
            return null;
        }
        set text(value) { stats.textWrites++; this._text = value; }
        get text() { return this._text; }
    }
    function newRoot() {
        currentRoot = new Panel("Panel", null, "context");
        const panel = new Panel("Panel", currentRoot, "GameInfoPanel");
        new Panel("Panel", panel, "GameInfoBuildingColumn");
        new Panel("Panel", panel, "GameInfoHeroColumn");
        return currentRoot;
    }
    newRoot();
    const $ = selector => currentRoot.FindChildTraverse(selector.replace(/^#/, ""));
    $.GetContextPanel = () => currentRoot;
    $.CreatePanel = (type, parent, id) => { stats.created++; return new Panel(type, parent, id); };
    $.Schedule = (delay, callback) => {
        stats.scheduled++; const id = ++serial;
        jobs.set(id, { at: now + delay, callback }); return id;
    };
    $.CancelScheduled = id => jobs.delete(id);
    $.Msg = () => {};
    const env = {
        $, GameUI: { CustomUIConfig: () => cfg },
        Game: { GetLocalPlayerID: () => 0, GetGameTime: () => now },
        GameEvents: { SendCustomGameEventToServer(name, value) { requests.push({ name, value }); } },
        CustomNetTables: {
            GetTableValue: (_table, key) => tables[key],
            SubscribeNetTableListener(_table, callback) { const id = ++serial; listeners.set(id, callback); return id; }
        },
        Entities: {
            GetHealth(index) { assert(index >= 0); stats.healthReads++; return health.current; },
            GetMaxHealth(index) { assert(index >= 0); stats.healthReads++; return health.maximum; }
        }
    };
    if (!options.noUnsubscribe) env.CustomNetTables.UnsubscribeNetTableListener = id => listeners.delete(id);
    require("./load_shared_ui_test.cjs")(env, Panel, currentRoot);
    function load(replaceRoot = false) {
        if (replaceRoot) newRoot();
        vm.runInNewContext(source, env, { filename: sourcePath });
        return cfg.SurvivalGameInfo;
    }
    function advance(seconds) {
        const end = now + seconds;
        for (;;) {
            const next = [...jobs.entries()].filter(([, job]) => job.at <= end)
                .sort((left, right) => left[1].at - right[1].at || left[0] - right[0])[0];
            if (!next) break;
            assert(stats.callbacks < 100000, "unbounded timer loop");
            const [id, job] = next; jobs.delete(id); now = job.at;
            stats.callbacks++; job.callback();
        }
        now = end;
    }
    function publish(value, key = "player_0") {
        tables[key] = value;
        [...listeners.values()].forEach(fn => fn("survival_game_info", key, value));
    }
    function rows(group) {
        return $("#GameInfo" + (group === "hero" ? "Hero" : "Building") + "Column").children;
    }
    const api = load();
    return { api, cfg, stats, jobs, listeners, handlers, requests, health, load, advance, publish, rows,
        root: () => currentRoot, now: () => now };
}

function snapshot(gold = 15) {
    return { hero_entindex: 0, fields: {
        1: { id: "gold", label: "金币", value: gold, group: "building", order: 1 },
        2: { id: "hero_current_health", label: "生命", value: "70 / 300", group: "hero", order: 2 },
        3: { id: "hero_damage", label: "伤害", value: 24, suffix: " 点", group: "hero", order: 3 }
    } };
}

function measure(source) {
    const h = fixture(source);
    h.advance(60);
    const hiddenCallbacks = h.stats.callbacks;
    h.api.Open(); h.advance(0);
    const before = { ...h.stats };
    for (let index = 0; index < 100; index++) h.publish(snapshot(16 + index));
    h.advance(0);
    const snapshotBurst = {
        created: h.stats.created - before.created,
        removed: h.stats.removed - before.removed,
        textWrites: h.stats.textWrites - before.textWrites
    };
    h.api.Close();
    for (let index = 0; index < 20; index++) h.load(true);
    return { hiddenCallbacks60Seconds: hiddenCallbacks, snapshotBurst100: snapshotBurst,
        reloads20: { pendingTimers: h.jobs.size, tableListeners: h.listeners.size } };
}

if (process.argv.includes("--measure-head")) {
    const source = execFileSync("git", ["show", "HEAD:" + sourcePath], { encoding: "utf8" });
    console.log(JSON.stringify({ revision: "HEAD", ...measure(source) }));
    process.exit(0);
}

const source = fs.readFileSync(sourcePath, "utf8");
{
    const h = fixture(source);
    h.publish(null); h.api.Open();
    assert.equal(h.rows("building").length, 0, "joining before the first snapshot does not invent data");
    h.publish(snapshot(31)); h.advance(0);
    assert.equal(h.rows("building")[0].children[1].text, "31", "first snapshot after joining becomes visible next frame");
    const withoutHero = snapshot(32); withoutHero.hero_entindex = -1;
    h.publish(withoutHero); h.advance(0);
    assert.equal(h.rows("hero")[0].children[1].text, "70 / 300", "no live hero retains the server field value");
    h.api.Close();
    h.publish(snapshot(33)); h.api.Open();
    assert.equal(h.rows("building")[0].children[1].text, "33", "a hidden reconnect update is ready on the opening frame");
    assert.equal(h.rows("hero")[0].children[1].text, "120 / 300");
}
{
    const h = fixture(source);
    h.advance(60);
    assert.equal(h.jobs.size, 0, "a closed information window has no timer");
    assert.equal(h.stats.callbacks, 0, "closed means zero wakeups, not a slower poll");
    for (let index = 0; index < 100; index++) h.publish(snapshot(index));
    assert.equal(h.stats.created, 0, "closed snapshots are cached without creating rows");
    h.api.Open();
    assert.equal(h.rows("building")[0].children[1].text, "99", "initial opening renders the latest snapshot synchronously");
    assert.equal(h.rows("hero")[0].children[1].text, "120 / 300", "entity index zero is valid");
    for (let index = 0; index < 20; index++) h.api.Open();
    assert.equal(h.requests.length, 1, "already-open calls do not request another server snapshot");
    assert.equal(h.jobs.size, 1, "only the existing 0.25-second visible refresh is running");
    const originalRows = [...h.rows("building"), ...h.rows("hero")];
    const before = { ...h.stats };
    for (let index = 0; index < 100; index++) h.publish(snapshot(100 + index));
    h.advance(0);
    assert.equal(h.rows("building")[0].children[1].text, "199", "burst renders the newest value");
    assert.deepEqual([...h.rows("building"), ...h.rows("hero")], originalRows, "existing rows survive value-only updates");
    assert.equal(h.stats.created, before.created);
    assert.equal(h.stats.removed, before.removed);
    assert.equal(h.stats.textWrites - before.textWrites, 1, "one visible changed value gets one property write");
    const stableWrites = h.stats.textWrites;
    h.publish(snapshot(199)); h.advance(0.25);
    assert.equal(h.stats.textWrites, stableWrites, "unchanged values and health do not churn labels");
    h.health.current = 101;
    h.advance(0.249);
    assert.equal(h.rows("hero")[0].children[1].text, "120 / 300");
    h.advance(0.001);
    assert.equal(h.rows("hero")[0].children[1].text, "101 / 300", "visible health preserves the 0.25-second interval");
    h.publish(snapshot(500)); h.api.Close();
    assert.equal(h.jobs.size, 0, "closing cancels both a queued render and health refresh");
    const closedWrites = h.stats.textWrites;
    h.advance(60); h.publish(snapshot(700));
    assert.equal(h.stats.textWrites, closedWrites);
    h.api.Open();
    assert.equal(h.rows("building")[0].children[1].text, "700", "reopening cannot show an old queued snapshot");
    h.publish(snapshot(999), "player_1"); h.advance(0);
    assert.equal(h.rows("building")[0].children[1].text, "700", "other players' data is ignored");
}
{
    const h = fixture(source); h.api.Open();
    const next = snapshot();
    next.fields[1].group = "hero"; next.fields[1].order = 4;
    next.fields[3].visible = 0;
    next.fields[4] = { id: "wood", label: "木材", value: 0, order: 0 };
    h.publish(next); h.advance(0);
    assert.deepEqual(h.rows("building").map(row => row.children[0].text), ["木材："]);
    assert.deepEqual(h.rows("hero").map(row => row.children[0].text), ["生命：", "金币："], "field visibility, order and group changes rebuild correctly");
    const row = h.rows("building")[0];
    next.fields[4].label = "剩余木材"; next.fields[4].suffix = " 单位";
    h.publish(next); h.advance(0);
    assert.strictEqual(h.rows("building")[0], row, "label-only changes reuse the row");
    assert.equal(row.children[0].text, "剩余木材："); assert.equal(row.children[1].text, "0 单位");
    h.rows("building")[0].valid = false;
    h.publish(next); h.advance(0);
    assert(h.rows("building")[0].valid, "externally recreated or removed panels recover on the next snapshot");
}
{
    const h = fixture(source); h.api.Open();
    const lateTimer = [...h.jobs.values()][0].callback;
    h.api.Close(); h.api.Open(); lateTimer();
    assert.equal(h.jobs.size, 1, "a late cancelled callback cannot duplicate the next opening's timer");
    const oldApi = h.api, staleTableListener = [...h.listeners.values()][0];
    let api = h.api;
    for (let index = 0; index < 20; index++) {
        api = h.load(true); api.Open(); api.Close();
        assert.equal(h.listeners.size, 1, "Tools reload releases the previous NetTable subscription");
        assert.equal(h.jobs.size, 0);
    }
    const requests = h.requests.length;
    assert.equal(oldApi.Open(), false); oldApi.Refresh();
    staleTableListener("survival_game_info", "player_0", snapshot(888));
    assert.equal(h.requests.length, requests, "obsolete callbacks cannot make requests");
    assert.equal(h.jobs.size, 0);
    h.handlers.game_info("TAB", true);
    assert(api.IsOpen(), "TAB still opens the current generation");
    h.root().valid = false; h.advance(0.25);
    assert.equal(h.jobs.size, 0); assert.equal(h.listeners.size, 0, "destroyed context disposes its listener");
}
{
    const h = fixture(source, { noUnsubscribe: true });
    h.api.Open(); const oldApi = h.api;
    const api = h.load(true); api.Open();
    h.publish(snapshot(811)); h.advance(0);
    assert.equal(oldApi.IsOpen(), false);
    assert.equal(h.jobs.size, 1, "generation guards are safe even without the optional unsubscribe API");
    assert.equal(h.rows("building")[0].children[1].text, "811");
}
console.log(JSON.stringify({ revision: "working", ...measure(source) }));
console.log("GAME_INFO_LIFECYCLE_PASS: hidden idle, latest snapshots, stable rows, structural changes, visible health, owner isolation, cancel races and context replacement");
