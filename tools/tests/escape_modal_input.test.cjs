"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

const layerSource = fs.readFileSync("panorama/src/scripts/custom_game/ui_layers.js", "utf8");
const bootstrapSource = fs.readFileSync("panorama/src/scripts/custom_game/ui_bootstrap.js", "utf8");

function fixture({ bootstrapFirst = false } = {}) {
    let now = 10000, focused = null, nativeKey = null;
    const cfg = {}, jobs = [], binds = new Map(), commands = new Map(), closed = [];
    const nativeCallbacks = [];
    class Panel {
        constructor(id, parent, type = "Panel") {
            this.id = id; this.parent = parent; this.paneltype = type;
            this.children = []; this.style = {}; this.classes = new Set(); this.events = new Map();
            this.valid = true; this.visible = true; this.focusCalls = 0;
            if (parent) parent.children.push(this);
        }
        IsValid() { return this.valid; }
        GetParent() { return this.parent; }
        GetChildCount() { return this.children.length; }
        GetChild(index) { return this.children[index]; }
        BHasClass(name) { return this.classes.has(name); }
        BHasKeyFocus() { return focused === this; }
        BHasDescendantKeyFocus() {
            return this.children.some(child => child.BHasKeyFocus() || child.BHasDescendantKeyFocus());
        }
        SetAcceptsFocus(value) { this.acceptsFocus = value; }
        SetFocus() { focused = this; this.focusCalls++; }
        FindChildTraverse(id) {
            if (this.id === id) return this;
            for (const child of this.children) {
                const found = child.FindChildTraverse(id);
                if (found) return found;
            }
            return null;
        }
    }
    const root = new Panel("Hud"), context = new Panel("Context", root);
    const $ = selector => context.FindChildTraverse(selector.replace(/^#/, ""));
    $.GetContextPanel = () => context;
    $.Msg = $.Warning = () => {};
    $.Localize = value => value;
    $.Schedule = (delay, fn) => { jobs.push({ delay, fn }); return jobs.length; };
    $.CancelScheduled = () => {};
    $.RegisterEventHandler = (name, panel, fn) => {
        const callbacks = panel.events.get(name) || [];
        callbacks.push(fn); panel.events.set(name, callbacks);
    };
    const sandbox = {
        $, Date: { now: () => now },
        Game: {
            GetLocalPlayerID: () => 0, GetGameTime: () => 0,
            AddCommand: (name, fn) => commands.set(name, fn),
            CreateCustomKeyBind: (key, command) => binds.set(key, command)
        },
        GameUI: {
            CustomUIConfig: () => cfg,
            SetKeyPressedCallback(fn) { nativeKey = fn; nativeCallbacks.push(fn); },
            SetMouseCallback: () => {}, SetDefaultUIEnabled: () => {},
            SelectUnit: () => {}, MoveCameraToEntity: () => {}
        },
        Players: {
            GetPlayerHeroEntityIndex: () => -1,
            GetSelectedEntities: () => [], GetLocalPlayerPortraitUnit: () => -1
        },
        Entities: {
            IsValidEntity: () => false, IsAlive: () => false,
            GetPlayerOwnerID: () => -1, GetUnitName: () => "", GetAbility: () => -1
        },
        Abilities: {},
        CustomNetTables: { GetTableValue: () => null },
        GameEvents: { Subscribe: () => {}, SendCustomGameEventToServer: () => {} }
    };
    const runtime = vm.createContext(sandbox);
    const loadLayers = () => vm.runInContext(layerSource, runtime, { filename: "ui_layers.js" });
    const loadBootstrap = () => vm.runInContext(bootstrapSource, runtime, { filename: "ui_bootstrap.js" });
    if (bootstrapFirst) { loadBootstrap(); loadLayers(); }
    else { loadLayers(); loadBootstrap(); }
    function open(id, options = {}) {
        const panel = options.panel || new Panel(id, context);
        const close = reason => {
            closed.push({ id, reason });
            if (!options.veto) cfg.SurvivalUILayers.Close(id);
        };
        cfg.SurvivalUILayers.Open(id, panel, close);
        return { id, panel, close };
    }
    function cancel(panel) {
        const callbacks = panel.events.get("Cancelled") || [];
        assert(callbacks.length, "production Open must install Panorama Cancelled handling");
        return callbacks.map(fn => fn()).at(-1);
    }
    return {
        cfg, jobs, binds, closed, open, cancel, Panel, context, nativeCallbacks,
        key: (key, down = true) => nativeKey(key, down),
        advance: (ms = 100) => { now += ms; },
        loadLayers, loadBootstrap, focus: panel => { focused = panel; }, focused: () => focused
    };
}

{
    const h = fixture(), layers = h.cfg.SurvivalUILayers;
    const lower = h.open("lower"), upper = h.open("upper");
    let gridInputs = 0, abilityInputs = 0;
    h.cfg.SurvivalInputDispatcher.RegisterKeyHandler("grid_probe", (key, down) => {
        if (down && /^(ESC|ESCAPE)$/i.test(key)) { gridInputs++; return true; }
        return false;
    }, 100);
    h.cfg.SurvivalInputDispatcher.RegisterKeyHandler("ability_probe", (key, down) => {
        if (down && /^(ESC|ESCAPE)$/i.test(key)) { abilityInputs++; return true; }
        return false;
    }, 60);
    assert.equal(h.key("escape"), true);
    assert.deepEqual(h.closed.map(entry => entry.id), ["upper"]);
    assert.equal(layers.Top(), "lower");
    h.advance(2000);
    assert.equal(h.key("ESCAPE"), true, "holding Escape consumes repeats without another close");
    assert.equal(h.key("Q"), false, "unrelated keys pass through");
    assert.equal(h.closed.length, 1);
    assert.equal(gridInputs, 0); assert.equal(abilityInputs, 0);
    assert.equal(h.key("ESCAPE", false), true);
    assert.equal(h.key("ESC"), true, "release immediately enables the next physical press");
    assert.deepEqual(h.closed.map(entry => entry.id), ["upper", "lower"]);
    assert.equal(layers.Top(), null);
    assert.equal(h.cancel(upper.panel), false, "a stale focused window cannot close another layer");
    assert.equal(lower.panel.focusCalls, 1);
}

for (const order of ["native_first", "cancelled_first"]) {
    const h = fixture(), lower = h.open("lower"), upper = h.open("upper");
    if (order === "native_first") {
        assert.equal(h.key("ESCAPE"), true);
        h.advance(20);
        assert.equal(h.cancel(lower.panel), true, "a second event reaching the exposed window is coalesced");
        assert.equal(h.cancel(upper.panel), false);
    } else {
        assert.equal(h.cancel(upper.panel), true);
        h.advance(20);
        assert.equal(h.key("ESCAPE"), true, "native input arriving after Cancelled must only mark that press held");
        assert.equal(h.cancel(lower.panel), true);
    }
    assert.deepEqual(h.closed.map(entry => entry.id), ["upper"], order);
    h.advance(1000);
    assert.equal(h.key("ESCAPE"), true);
    assert.equal(h.closed.length, 1);
    h.key("ESCAPE", 0);
    assert.equal(h.key(27, true), true);
    assert.deepEqual(h.closed.map(entry => entry.id), ["upper", "lower"]);
}

{
    const h = fixture();
    h.open("lower");
    const upper = h.open("upper");
    assert.equal(h.cancel(upper.panel), true);
    h.advance(150);
    assert.equal(h.key("ESCAPE"), true);
    assert.deepEqual(h.closed.map(entry => entry.id), ["upper"],
        "slow close processing must not turn Cancelled/native delivery of one press into two closes");
    h.key("ESCAPE", false);
    assert.equal(h.key("ESCAPE"), true);
    assert.deepEqual(h.closed.map(entry => entry.id), ["upper", "lower"]);
}

{
    const h = fixture({ bootstrapFirst: true });
    assert.equal(h.key("ESCAPE"), false, "an empty modal stack leaves native Escape available");
    assert.equal(h.key("ESCAPE", false), false);
    assert.equal(h.cfg.SurvivalUILayers.HandleEscape(), false);
    assert.equal(h.binds.has("ESCAPE") || h.binds.has("ESC"), false, "central Escape never overrides a native keybind");
    h.open("lower");
    const upper = h.open("upper");
    assert.equal(h.cfg.SurvivalUILayers.HandleEscape("lower"), false);
    assert.equal(h.cfg.SurvivalUILayers.Top(), "upper", "an expected ID protects a covered modal");
    h.cfg.SurvivalUILayers.Close("upper");
    assert.equal(h.cancel(upper.panel), false, "a delayed callback from a closed modal protects the lower modal");
    assert.equal(h.cfg.SurvivalUILayers.Top(), "lower");
}

{
    const h = fixture(), layers = h.cfg.SurvivalUILayers;
    const popup = h.open("popup");
    const search = new h.Panel("Search", popup.panel, "TextEntry");
    h.focus(search);
    const scheduled = h.jobs.length;
    layers.Open(popup.id, popup.panel, popup.close);
    h.loadLayers();
    assert.equal(h.focused(), search, "repeated Open preserves a focused child");
    assert.equal(popup.panel.focusCalls, 1);
    assert.equal(popup.panel.events.get("Cancelled").length, 1, "repeated Open binds Cancelled only once");
    assert.equal(h.jobs.length, scheduled, "layer input and focus handling add no polling");
    assert.equal(h.key("ESCAPE"), true);
    h.open("replacement");
    layers.BindInput(h.cfg.SurvivalInputDispatcher);
    assert.equal(h.key("ESCAPE"), true);
    assert.equal(layers.Top(), "replacement", "rebinding the same dispatcher does not reset a held press");
    const oldDispatcher = h.cfg.SurvivalInputDispatcher;
    h.loadBootstrap();
    assert.notEqual(h.cfg.SurvivalInputDispatcher, oldDispatcher);
    assert.equal(h.cfg.SurvivalUILayers, layers);
    assert.equal(h.nativeCallbacks.length, 2, "a new HUD replaces the native callback");
    assert.equal(h.key("ESCAPE"), true, "the replacement dispatcher receives modal input and resets old key state");
    assert.equal(layers.Top(), null);
    assert.deepEqual(h.closed.map(entry => entry.id), ["popup", "replacement"]);
}

{
    const h = fixture();
    h.open("lower");
    h.open("veto", { veto: true });
    let underlying = 0;
    h.cfg.SurvivalInputDispatcher.RegisterKeyHandler("underlying", () => { underlying++; return true; }, 100);
    assert.equal(h.key("ESCAPE"), true, "a vetoed top modal still consumes Escape");
    assert.equal(h.cfg.SurvivalUILayers.Top(), "veto");
    assert.equal(underlying, 0);
    assert.deepEqual(h.closed.map(entry => entry.id), ["veto"]);
}

console.log("ESCAPE_MODAL_INPUT_PASS: real bootstrap priority, top-only close, held key, both Cancelled/native orders, release, expected IDs, pass-through, rebind and focus");
