"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const source = fs.readFileSync("panorama/src/scripts/custom_game/survival_ui.js", "utf8");
const seam = "    CustomNetTables.SubscribeNetTableListener(tableName";
assert(source.includes(seam));
const instrumented = source.replace(seam, `
    __test({start: scheduleInitialBuilderSelection,
        poll: function () { recoverInitialBuilderSelection("hud_poll", 20, initialBuilderSelectionSerial); }});
    return;
` + seam);
function setup(playerId, selectedInitially = [], withMove = true) {
    let api, identity, replicated = false, selected = selectedInitially;
    const jobs = [], camera = [], selections = [];
    const builder = 100 + playerId;
    const $ = () => null;
    $.Schedule = (delay, fn) => jobs.push(fn);
    $.Msg = () => {};
    const ui = {
        SelectUnit: id => { selections.push(id); selected = [id]; },
        SetCameraTargetPosition: position => camera.push(position),
    };
    if (withMove) ui.MoveCameraToEntity = id => camera.push(id);
    vm.runInNewContext(instrumented, {
        $, __test: value => { api = value; },
        Game: {GetLocalPlayerID: () => playerId}, GameUI: ui,
        GameEvents: {SendCustomGameEventToServer: () => {}},
        CustomNetTables: {GetTableValue: (name, key) => {
            assert.equal(name, "survival_builder_identity");
            assert.equal(key, "player_" + playerId);
            return identity;
        }},
        Entities: {
            IsValidEntity: id => (id === builder && replicated) || id === 9,
            GetUnitName: () => "playable_unit",
            GetAbsOrigin: id => [id, 500, 400],
        },
        Players: {GetSelectedEntities: () => selected,
            GetLocalPlayerPortraitUnit: () => selected[0] ?? -1},
    });
    return {api, camera, selections, builder,
        identity: () => { identity = {entindex: builder}; },
        replicate: () => { replicated = true; },
        drain: () => { let count = 0; while (jobs.length) { assert(++count < 100); jobs.shift()(); } },
    };
}
for (const player of [0,1,2,3]) {
    const ui = setup(player);
    ui.api.start("hud_ready"); ui.drain();
    assert.equal(ui.camera.length, 0);
    ui.identity(); ui.api.start("identity_update"); ui.drain();
    assert.equal(ui.camera.length, 0, "do not focus an entity before client replication");
    ui.replicate(); ui.api.poll();
    assert.deepEqual(ui.selections, [ui.builder]);
    assert.deepEqual(ui.camera, [ui.builder], "late guest entity gets its own initial camera focus");
    ui.api.start("builder_ready"); ui.api.poll(); ui.drain();
    assert.equal(ui.camera.length, 1, "duplicate events must not repeatedly steal the camera");
}
{
    const ui = setup(1, [101]); ui.identity(); ui.replicate(); ui.api.start("event_already_selected");
    assert.deepEqual(ui.camera, [101], "already selected builder still needs the initial camera move");
    assert.equal(ui.selections.length, 0);
}
{
    const ui = setup(2, [9]); ui.identity(); ui.replicate(); ui.api.start("late_hud");
    assert.equal(ui.camera.length, 0, "preserve an explicit other-unit selection");
}
{
    const ui = setup(3, [], false); ui.identity(); ui.replicate(); ui.api.start("fallback");
    assert.equal(JSON.stringify(ui.camera), JSON.stringify([[103,500,400]]));
}
console.log("INITIAL_BUILDER_CAMERA_PASS: four clients, late identity/entity, selected-builder focus, one-shot behavior, user selection and camera fallback");
