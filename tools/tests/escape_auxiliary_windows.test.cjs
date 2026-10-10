"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

class FakeUILayers {
    constructor() { this.stack = []; this.opens = []; }
    Open(id, panel, close) {
        this.Close(id);
        this.stack.push({ id, panel, close });
        this.opens.push(id);
    }
    Close(id) { this.stack = this.stack.filter(entry => entry.id !== id); }
    CloseTop() {
        const top = this.stack.at(-1);
        if (top) top.close();
    }
    Top() { return this.stack.at(-1)?.id || null; }
}

function fixture() {
    const jobs = new Map(), subscriptions = new Map(), requests = [], keys = {};
    let serial = 0;
    class Panel {
        constructor(type, parent, id) {
            this.type = type; this.parent = parent; this.id = id;
            this.children = []; this.classes = new Set(); this.style = {};
            this.visible = true; this.valid = true; this.events = {};
            if (parent) parent.children.push(this);
        }
        IsValid() { return this.valid; }
        AddClass(name) { this.classes.add(name); }
        RemoveClass(name) { this.classes.delete(name); }
        SetHasClass(name, active) { active ? this.classes.add(name) : this.classes.delete(name); }
        SetPanelEvent(name, callback) { this.events[name] = callback; }
        FindChildTraverse(id) {
            if (this.id === id) return this;
            for (const child of this.children) {
                const found = child.FindChildTraverse(id);
                if (found) return found;
            }
            return null;
        }
        RemoveAndDeleteChildren() { this.children = []; }
    }
    const root = new Panel("Panel", null, "Context");
    for (const id of ["GameInfoPanel", "GameInfoBuildingColumn", "GameInfoHeroColumn",
        "SurvivalPortraitCameraEditor", "PortraitCameraEditorValues", "PortraitCameraEditorStatus",
        "SurvivalJuggernautPortraitOverlay", "SurvivalJuggernautPortraitScene",
        "SurvivalTowerPortraitOverlay", "SurvivalAbilityCalibrationPanel"]) {
        new Panel("Panel", root, id);
    }
    const cfg = {
        SurvivalUILayers: new FakeUILayers(),
        SurvivalInputDispatcher: { RegisterKeyHandler(id, fn) { keys[id] = fn; } },
        SurvivalHudTakeover: { abilities: false }
    };
    const $ = selector => root.FindChildTraverse(selector.replace(/^#/, ""));
    $.GetContextPanel = () => root;
    $.CreatePanel = (type, parent, id) => new Panel(type, parent, id);
    $.Schedule = (delay, fn) => { const id = ++serial; jobs.set(id, { delay, fn }); return id; };
    $.CancelScheduled = id => jobs.delete(id);
    $.Msg = $.Warning = () => {};
    const env = {
        $, GameUI: { CustomUIConfig: () => cfg },
        Game: { GetLocalPlayerID: () => 0, GetGameTime: () => 0 },
        GameEvents: { SendCustomGameEventToServer(name, data) { requests.push({ name, data }); } },
        CustomNetTables: {
            GetTableValue: () => null,
            SubscribeNetTableListener(name, fn) { const id = ++serial; subscriptions.set(id, fn); return id; },
            UnsubscribeNetTableListener(id) { subscriptions.delete(id); }
        },
        Entities: {}, Abilities: {}
    };
    require("../load_shared_ui_test.cjs")(env, Panel, root);
    function load(name) {
        let source = fs.readFileSync("panorama/src/scripts/custom_game/" + name + ".js", "utf8");
        if (name === "hud_takeover") {
            // Keep the real calibration API and native restore path. Suppress
            // unrelated startup subscriptions/ticks after the API is installed.
            const seam = "    CustomNetTables.SubscribeNetTableListener(";
            assert(source.includes(seam));
            source = source.replace(seam, "    updateCalibrationPanel(null, null, null); return;\n" + seam);
        }
        vm.runInNewContext(source, env, { filename: name + ".js" });
    }
    return { cfg, load, root, jobs, subscriptions, requests, keys, panel: id => root.FindChildTraverse(id) };
}

{
    const h = fixture();
    h.load("game_info_panel");
    const info = h.cfg.SurvivalGameInfo, layers = h.cfg.SurvivalUILayers;
    info.Open();
    assert.equal(layers.Top(), "game_info");
    assert.equal(h.jobs.size, 1, "uses only the existing visible data refresh");
    info.Open();
    assert.equal(layers.opens.length, 1, "already-open API calls do not reorder the modal");
    layers.CloseTop();
    assert.equal(info.IsOpen(), false);
    assert.equal(h.panel("GameInfoPanel").hittest, false);
    assert.equal(layers.Top(), null);
    assert.equal(h.jobs.size, 0);
    assert.equal(h.requests.at(-1).data.open, 0, "modal close ends the server subscription");
    info.Open();
    h.load("game_info_panel");
    assert.equal(layers.Top(), null, "reload disposes the previous modal lease");
    h.cfg.SurvivalGameInfo.Open();
    info.Dispose();
    assert.equal(layers.Top(), "game_info", "retired disposal cannot remove the current window");
    h.cfg.SurvivalGameInfo.Dispose();
    assert.equal(layers.Top(), null);
    assert.equal(h.jobs.size, 0);
    assert.equal(h.subscriptions.size, 0);
}

{
    const h = fixture();
    h.load("game_info_panel");
    h.load("portrait_camera_editor");
    const layers = h.cfg.SurvivalUILayers;
    h.cfg.SurvivalGameInfo.Open();
    h.cfg.SurvivalPortraitCameraEditor.Toggle();
    assert.equal(layers.Top(), "portrait_camera_editor");
    layers.CloseTop();
    assert.equal(layers.Top(), "game_info", "only the current auxiliary popup closes");
    assert.equal(h.cfg.SurvivalGameInfo.IsOpen(), true);
    for (const id of ["SurvivalPortraitCameraEditor", "SurvivalJuggernautPortraitOverlay",
        "SurvivalJuggernautPortraitScene"]) assert.equal(h.panel(id).visible, false);
    assert.equal(h.panel("SurvivalTowerPortraitOverlay").visible, true);
    h.cfg.SurvivalPortraitCameraEditor.Toggle();
    h.load("portrait_camera_editor");
    assert.equal(layers.Top(), "game_info", "editor initialization releases its prior lease");
    h.cfg.SurvivalGameInfo.Close();
}

{
    const h = fixture();
    h.cfg.SurvivalAbilityCalibrationState = { visible: true };
    h.load("hud_takeover");
    const layers = h.cfg.SurvivalUILayers, calibration = h.cfg.SurvivalAbilityTakeover;
    assert.equal(layers.Top(), "ability_calibration", "persisted visible calibration is registered on load");
    calibration.SetCalibrationVisible(true);
    assert.equal(layers.opens.length, 1, "refreshes never move an existing calibration window above another popup");
    layers.Open("other_popup", h.root, () => layers.Close("other_popup"));
    calibration.SetCalibrationAlignment("center");
    calibration.NudgeCalibration(2, 3);
    calibration.ResetCalibration();
    assert.equal(layers.Top(), "other_popup");
    layers.CloseTop();
    layers.CloseTop();
    assert.equal(calibration.IsCalibrationVisible(), false);
    assert(h.panel("SurvivalAbilityCalibrationPanel").classes.has("Hidden"));
    for (const reopen of [() => calibration.SetCalibrationAlignment("center"),
        () => calibration.NudgeCalibration(1, 1), () => calibration.ResetCalibration()]) {
        reopen();
        assert.equal(layers.Top(), "ability_calibration", "adjustment APIs register implicit opens");
        layers.CloseTop();
        assert.equal(layers.Top(), null);
    }
    assert.equal(h.jobs.size, 0, "modal registration adds no input polling");
    assert.deepEqual(Object.keys(h.keys), [], "calibration adds no key handler");
}

console.log("ESCAPE_AUXILIARY_WINDOWS_PASS: top-only close callbacks, game-info disposal, preview cleanup, calibration restore and implicit opens without reordering");
