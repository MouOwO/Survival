"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const test = require("node:test");
const source = fs.readFileSync("panorama/src/scripts/custom_game/ui_layers.js", "utf8");
const components = fs.readFileSync("panorama/src/scripts/custom_game/common/ui_components.js", "utf8");

function fixture() {
    class Panel {
        constructor(id, parent, z = "0") {
            this.id = id; this.parent = parent; this.children = [];
            this.style = {zIndex: z}; this.valid = true; this.visible = true;
            this.hittest = true; this.hittestchildren = true; this.focuses = 0;
            this.classes = new Set(); this.events = {};
            if (parent) parent.children.push(this);
        }
        IsValid() { return this.valid; }
        GetParent() { return this.parent; }
        SetAcceptsFocus() {}
        SetFocus() { this.focuses++; }
        AddClass(name) { this.classes.add(name); }
        RemoveClass(name) { this.classes.delete(name); }
        BHasClass(name) { return this.classes.has(name); }
        SetHasClass(name, enabled) { if (enabled) this.AddClass(name); else this.RemoveClass(name); }
        SetPanelEvent(name, fn) { this.events[name] = fn; }
        GetChildCount() { return this.children.length; }
        GetChild(index) { return this.children[index]; }
    }
    const root = new Panel("NativeRoot", null, "10");
    const payment = new Panel("PaymentHUD", root, "11");
    const archive = new Panel("ArchiveHUD", root, "12");
    let context = payment;
    const cfg = {}, keyCallbacks = [], diagnostics = [], closed = [], jobs = new Map(), panelCallbacks = [];
    let jobSerial = 0;
    cfg.SurvivalUIRegistry = {tokens: {colors: {surface_ivory: "#fff", border_champagne: "#ccc"}}, assets: {}};
    cfg.SurvivalInputDispatcher = {RegisterKeyHandler(id, fn) { keyCallbacks.push(fn); }};
    const $ = {
        GetContextPanel: () => context,
        CreatePanel: (type, parent, id) => new Panel(id, parent),
        RegisterEventHandler(name, panel, fn) { panelCallbacks.push({name, panel, fn}); }, Msg(message) { diagnostics.push(message); },
        Schedule(delay, fn) { const id = ++jobSerial; jobs.set(id, fn); return id; },
        CancelScheduled(id) { jobs.delete(id); }
    };
    const sandbox = vm.createContext({$, Date, GameUI: {CustomUIConfig: () => cfg},
        CustomNetTables: {}, GameEvents: {Subscribe() { return 1; }, Unsubscribe() {}}});
    function load(owner = payment) {
        context = owner;
        vm.runInContext(source, sandbox, {filename: "ui_layers.js"});
        return cfg.SurvivalUILayers;
    }
    function remove(owner) {
        owner.valid = false;
        owner.children.forEach(remove);
    }
    function loadComponents(owner = payment) {
        context = owner;
        vm.runInContext(components, sandbox, {filename: "ui_components.js"});
        return cfg.SurvivalUI;
    }
    function loadProduction(name) {
        vm.runInContext(fs.readFileSync("panorama/src/scripts/custom_game/" + name, "utf8"), sandbox, {filename: name});
    }
    function modal(id, owner = archive, options = {}) {
        const panel = new Panel(id, owner, "21"), scrim = new Panel(id + "Scrim", owner, "20");
        const state = {opened: false};
        function close(reason) {
            if (options.mandatory && reason !== "escape") return false;
            if (options.throwOnClose) throw new Error("PRIVATE_CALLBACK_DETAIL_DO_NOT_LOG");
            closed.push({id, reason}); state.opened = false;
            panel.visible = false; scrim.visible = false;
            cfg.SurvivalUILayers.Close(id);
            return true;
        }
        return {
            panel, scrim, state,
            open() {
                state.opened = true; panel.visible = true; scrim.visible = true;
                cfg.SurvivalUILayers.Open(id, panel, close, {scrim, click: scrim});
            }
        };
    }
    return {Panel, root, payment, archive, cfg, load, loadComponents, loadProduction, remove, modal, closed, diagnostics, keyCallbacks, panelCallbacks, jobs};
}

test("repeated includes in independent live HUDs retain the same stack and focus", () => {
    const f = fixture(), layers = f.load(), window = f.modal("archive");
    window.open(); const focuses = window.panel.focuses;
    assert.equal(f.load(f.archive), layers);
    assert.equal(layers.Top(), "archive");
    assert.equal(window.panel.visible, true);
    assert.equal(window.panel.focuses, focuses);
    assert.deepEqual(f.closed, []);
});

test("removing the first HUD transfers another live HUD's modal without closing or refocusing it", () => {
    const f = fixture(), old = f.load(), window = f.modal("archive");
    window.open(); assert.equal(f.root.style.zIndex, "100000");
    f.remove(f.payment);
    const next = f.load(new f.Panel("ReplacementPaymentHUD", f.root, "13"));
    assert.notEqual(next, old);
    assert.equal(next.Top(), "archive");
    assert.equal(old.IsAlive(), false);
    assert.equal(window.state.opened, true, "an unrelated live controller retains its open state");
    for (const panel of [window.panel, window.scrim]) {
        assert.equal(panel.visible, true); assert.equal(panel.hittest, true);
    }
    assert.equal(window.panel.focuses, 1, "a transfer does not steal focus again");
    assert.deepEqual(f.closed, []);
    next.HandleEscape("archive");
    assert.equal(window.state.opened, false, "the retained callback closes through the new stack");
    assert.equal(f.root.style.zIndex, "10");
    assert.equal(f.archive.style.zIndex, "12");
    assert.equal(window.panel.style.zIndex, "21");
    assert.deepEqual(f.closed.map(value => value.id), ["archive"]);
});

test("retirement closes stacked selectors from top down through their accepted close path", () => {
    const f = fixture(), old = f.load();
    const archive = f.modal("archive"), difficulty = f.modal("difficulty", f.archive, {mandatory: true});
    archive.open(); difficulty.open(); old.Dispose();
    assert.deepEqual(f.closed, [{id: "difficulty", reason: "escape"}, {id: "archive", reason: "escape"}]);
    assert.equal(archive.state.opened, false); assert.equal(difficulty.state.opened, false);
    assert.equal(old.Top(), null); assert.equal(old.IsAlive(), false);
    assert.equal(f.root.style.zIndex, "10");
});

test("a broken close callback cannot strand an input shield or leak native exception details", () => {
    const f = fixture(), old = f.load(), window = f.modal("commerce_result", f.archive, {throwOnClose: true});
    window.open(); f.remove(f.payment); old.Dispose(); const fresh = f.load(f.archive);
    assert.equal(fresh.Top(), null);
    assert.equal(window.panel.visible, false); assert.equal(window.scrim.visible, false);
    assert.equal(window.scrim.hittest, false);
    assert.equal(f.root.style.zIndex, "10");
    assert.equal(old.IsAlive(), false);
    assert.deepEqual(f.diagnostics, ["[SurvivalUILayers] RELOAD_CLOSE_CALLBACK_FAILED"]);
    assert(!f.diagnostics.join(" ").includes("PRIVATE_CALLBACK_DETAIL"));
});

test("the real shared shell retains another HUD's mandatory pending dialog and registry on owner reinit", () => {
    const f = fixture(); f.loadComponents(); const old = f.load();
    const panel = new f.Panel("Difficulty", f.archive), scrim = new f.Panel("DifficultyScrim", f.archive);
    const pending = {requestId: "local-fixture-pending", selectionsSent: 1};
    let closes = 0;
    const shell = f.cfg.SurvivalUI.ModalShell.Adopt({id: "difficulty", panel, scrim, root: f.archive,
        width: 400, height: 200, closePolicy: "mandatory", onClose() { closes++; shell.Close(); }});
    shell.Open(); assert.equal(f.jobs.size, 1);
    f.remove(f.payment);
    const owner = new f.Panel("ReplacementPaymentHUD", f.root);
    const nextUI = f.loadComponents(owner), nextLayers = f.load(owner);
    assert.equal(nextUI.ModalManager.Get("difficulty"), shell);
    assert.equal(nextLayers.Top(), "difficulty"); assert.equal(shell.IsOpen(), true);
    assert.equal(panel.visible, true); assert.equal(f.jobs.size, 1);
    assert.deepEqual(pending, {requestId: "local-fixture-pending", selectionsSent: 1});
    assert.equal(closes, 0); assert.equal(old.IsAlive(), false);
    scrim.events.onactivate(); assert.equal(shell.IsOpen(), true, "outside click cannot abandon a mandatory selection");
    nextLayers.HandleEscape("difficulty");
    assert.equal(shell.IsOpen(), false); assert.equal(f.jobs.size, 0); assert.equal(closes, 1);
    assert.equal(pending.selectionsSent, 1, "hide/resume never submits another selection");
    shell.Open(); assert.equal(nextLayers.Top(), "difficulty"); assert.equal(f.jobs.size, 1);
    shell.Close(); assert.equal(f.jobs.size, 0);
});

test("saved old APIs and key callbacks cannot close or reprioritize the replacement stack", () => {
    const f = fixture(), old = f.load(), staleKey = f.keyCallbacks[0];
    f.modal("archive").open(); f.remove(f.payment);
    const current = f.load(f.archive), fresh = f.modal("commerce"); fresh.open();
    const before = [f.root.style.zIndex, f.archive.style.zIndex, fresh.panel.style.zIndex];
    const binds = f.keyCallbacks.length, previousClosures = f.closed.length;
    old.Open("stale", fresh.panel, () => { throw new Error("must not execute"); });
    old.Close("commerce"); old.CloseTop(); old.Dispose();
    old.BindInput({RegisterKeyHandler() { throw new Error("must not bind"); }});
    assert.equal(old.HandleEscape("commerce"), false);
    assert.equal(staleKey("ESCAPE", true), false);
    assert.equal(staleKey("ESCAPE", false), false);
    assert.equal(old.Top(), null); assert.equal(f.keyCallbacks.length, binds);
    assert.equal(current.Top(), "commerce"); assert.equal(fresh.panel.visible, true);
    assert.equal(f.closed.length, previousClosures);
    assert.deepEqual([f.root.style.zIndex, f.archive.style.zIndex, fresh.panel.style.zIndex], before);
    current.CloseTop(); assert.equal(fresh.state.opened, false);
});

test("a queued Cancelled event from a deleted owner cannot close a new dialog with the same ID", () => {
    const f = fixture(); f.load(); const stale = f.modal("commerce", f.payment); stale.open();
    const staleCancel = f.panelCallbacks.find(value => value.panel === stale.panel).fn;
    f.remove(f.payment); const current = f.load(f.archive), fresh = f.modal("commerce"); fresh.open();
    assert.equal(current.Top(), "commerce");
    assert.equal(staleCancel(), false); assert.equal(fresh.state.opened, true);
    assert.equal(current.Top(), "commerce");
    const newCancel = f.panelCallbacks.find(value => value.panel === fresh.panel).fn;
    assert.equal(newCancel(), true); assert.equal(fresh.state.opened, false);
});

test("a retained live panel uses only its new cancellation handler after a manager transfer", () => {
    const f = fixture(); f.load(); const window = f.modal("archive"); window.open();
    const original = f.panelCallbacks.find(value => value.panel === window.panel).fn;
    f.remove(f.payment); const current = f.load(f.archive);
    const handlers = f.panelCallbacks.filter(value => value.panel === window.panel);
    assert.equal(handlers.length, 2);
    assert.equal(original(), false); assert.equal(window.state.opened, true);
    assert.equal(current.Top(), "archive");
    assert.equal(handlers[1].fn(), true); assert.equal(window.state.opened, false);
});

test("an old panel's queued cancellation cannot dismiss another panel with the same modal ID", () => {
    const f = fixture(), layers = f.load(), old = f.modal("commerce"), fresh = f.modal("commerce");
    old.open(); const callback = f.panelCallbacks.find(value => value.panel === old.panel).fn;
    fresh.open();
    assert.equal(callback(), false); assert.equal(fresh.state.opened, true);
    assert.equal(layers.Top(), "commerce");
});

test("replaced real shared controllers cannot reopen or close the new controller on a reused panel", () => {
    const f = fixture(); f.loadComponents(); const layers = f.load();
    const panel = new f.Panel("Commerce", f.archive), scrim = new f.Panel("CommerceScrim", f.archive);
    const props = {id: "commerce", panel, scrim, root: f.archive, width: 400, height: 200};
    const old = f.cfg.SurvivalUI.ModalShell.Adopt(props); old.Open();
    const next = f.cfg.SurvivalUI.ModalShell.Adopt(props); next.Open();
    assert.equal(old.IsOpen(), false); assert.equal(next.IsOpen(), true); assert.equal(f.jobs.size, 1);
    old.Open(); old.Close(); old.Dispose();
    assert.equal(old.RequestClose("escape"), false);
    assert.equal(next.IsOpen(), true); assert.equal(panel.visible, true); assert.equal(scrim.visible, true);
    assert.equal(layers.Top(), "commerce"); assert.equal(f.jobs.size, 1);
    next.Close(); assert.equal(f.jobs.size, 0);
});

test("explicit retirement is idempotent and a subsequent include creates one usable manager", () => {
    const f = fixture(), old = f.load(); f.modal("archive").open();
    old.Dispose(); old.Dispose(); assert.equal(f.closed.length, 1);
    const next = f.load(), window = f.modal("commerce"); window.open();
    assert.notEqual(next, old); assert.equal(next.IsAlive(), true);
    assert.equal(next.Top(), "commerce"); assert.equal(window.panel.visible, true);
    assert.equal(f.load(f.archive), next, "a further live include does not retire the new modal");
});

test("real result shell reopens after shared navigation without retiring its controller or pending intent", () => {
    const f = fixture(); f.loadComponents(); const layers = f.load();
    const pending = {sku: "local-wallet-fixture", id: "local-uncertain-request"};
    f.cfg.SurvivalCommercePending = pending;
    function sharedModal(id, owner) {
        const panel = new f.Panel(id, owner), scrim = new f.Panel(id + "Scrim", owner);
        const shell = f.cfg.SurvivalUI.ModalShell.Adopt({id, panel, scrim, root: owner,
            width: 1672, height: 941, onClose() { shell.Close(); }});
        return {panel, scrim, shell};
    }
    const exchange = sharedModal("commerce_result", f.payment);
    const targets = {treasure: ["SurvivalTreasure", "Toggle"], archive: ["SurvivalArchive", "Open"],
        lottery: ["SurvivalLottery", "Open"], commerce: ["SurvivalCommerceView", "Open"],
        daily_rewards: ["SurvivalDaily", "Open"]};
    const destinations = {};
    for (const [id, [key, method]] of Object.entries(targets)) {
        destinations[id] = sharedModal(id, f.archive);
        f.cfg[key] = {[method]() { destinations[id].shell.Open(); }};
    }
    f.loadProduction("common/purple_shell.js");
    for (let round = 0; round < 3; round++) for (const id of Object.keys(targets)) {
        exchange.shell.Open();
        assert.equal(layers.Top(), "commerce_result");
        assert.equal(exchange.panel.visible, true); assert.equal(exchange.scrim.visible, true);
        assert.equal(exchange.panel.BHasClass("UIClosed"), false);
        assert.equal(f.cfg.SurvivalPurpleShell.Navigate(id), true);
        assert.equal(layers.Top(), id); assert.equal(destinations[id].shell.IsOpen(), true);
        assert.equal(exchange.shell.IsOpen(), false); assert.equal(exchange.panel.visible, false);
        assert.equal(exchange.panel.BHasClass("UIClosed"), true);
        assert.equal(f.cfg.SurvivalUI.ModalManager.Get("commerce_result"), exchange.shell,
            "normal navigation preserves the reusable shared controller");
        assert.equal(f.cfg.SurvivalCommercePending, pending,
            "closing and reopening a result panel never replaces an uncertain transaction");
        layers.CloseTop(); assert.equal(f.jobs.size, 0, "closed menus retain no fit timers");
    }
    exchange.shell.Open(); assert.equal(layers.Top(), "commerce_result");
    assert.equal(exchange.shell.IsOpen(), true); assert.equal(f.jobs.size, 1);
    exchange.shell.Close(); assert.equal(f.jobs.size, 0);
});
