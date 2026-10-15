"use strict";
const assert = require("node:assert/strict");
const {harness, ready} = require("./test_startup_loading_ui.js");
const options = [{mode_id: "pure", display_name: "纯净模式"}, {mode_id: "standard", display_name: "常规模式"},
    {mode_id: "fishing", display_name: "摸鱼模式", description: "按钮只显示名字"}];
const difficulties = [{difficulty_id: "N1", unlocked: true}, {difficulty_id: "N2", unlocked: false}];
const setup = patch => ({mode_selected: false, selector_player_id: 0, mode_options: options, difficulty_options: difficulties, ...patch});
const click = panel => panel.events.onactivate();
const sent = (ui, name) => ui.requests.filter(request => request.name === name);
const modes = ui => ui.nodes.MatchModeOptions.children;
function boot({localId = 0, profilesReady = false, selectedMode} = {}) {
    const startup = ready({admission_complete: true, profiles_ready: profilesReady,
        setup: setup(selectedMode ? {mode_selected: true, mode_id: selectedMode} : {})});
    const ui = harness({startupState: startup, hud: true, loadSharedUI: true, localId}); ui.advance(.11);
    return {ui, startup};
}
function noDifficulty(ui) {
    assert(ui.nodes.DifficultySelectionOverlay.BHasClass("DifficultySelectionHidden"));
    assert(!ui.nodes.DifficultySelectionDialog.visible && !ui.nodes.DifficultySelectionButtons.visible);
    assert(!ui.nodes.DifficultySelectionResume || !ui.nodes.DifficultySelectionResume.visible);
    assert.equal(sent(ui, "ui_difficulty_select_request").length, 0, "Fishing never submits a difficulty");
}
{
    const {ui, startup} = boot(), modal = ui.config.SurvivalUI.ModalManager.Get("survival_difficulty");
    assert.deepEqual(modes(ui).map(mode => mode.children[0].text), ["纯净模式", "常规模式", "摸鱼模式"]);
    assert(modes(ui).every(mode => mode.children.length === 1), "Each mode has only its name");
    assert.equal(ui.nodes.DifficultySelectionDialog.style.width, "275px");
    assert.equal(ui.nodes.DifficultySelectionDialog.style.height, "246px");
    ui.root.actuallayoutwidth = 1280; ui.root.actuallayoutheight = 720; ui.advance(.3);
    assert.equal(ui.nodes.DifficultySelectionDialog.style.transform, "scale3d(" + (2 / 3) + "," + (2 / 3) + ",1)");
    click(modes(ui)[2]); click(modes(ui)[2]); click(modes(ui)[0]);
    assert.deepEqual(JSON.parse(JSON.stringify(sent(ui, "survival_loading_mode_select").map(request => request.payload))),
        [{session_id: "match-123", mode_id: "fishing"}]);
    assert(modes(ui)[2].BHasClass("UIBusy") && modes(ui).every(mode => !mode.enabled));
    ui.emit("survival_loading_mode_result", {success: 1, session_id: "old-match", mode_id: "fishing"});
    assert(modal.IsOpen(), "Old-session acknowledgement is ignored");
    ui.emit("survival_loading_mode_result", {success: 0, session_id: "match-123", error: "mode_not_found"});
    assert(ui.nodes.DifficultySelectionError.visible && modes(ui)[2].enabled);
    assert.equal(ui.nodes.DifficultySelectionDialog.style.height, "304px");
    click(modes(ui)[2]); click(modes(ui)[1]);
    assert.equal(sent(ui, "survival_loading_mode_select").length, 2, "One explicit retry is allowed");
    assert.equal(ui.nodes.DifficultySelectionDialog.style.height, "246px");
    ui.emit("survival_loading_mode_result", {success: 1, session_id: "match-123", mode_id: "fishing"});
    noDifficulty(ui); assert(!modal.IsOpen() && !ui.nodes.MatchModeOptions.visible);
    ui.setStartup({...startup, setup: setup({mode_selected: true, mode_id: "fishing", error: "profile_load_failed"})});
    noDifficulty(ui);
    ui.setStartup({...startup, profiles_ready: true, setup: setup({mode_selected: true, mode_id: "fishing"})});
    ui.setState({sequence: 1, resources: {}, wave: {status: "fishing", mode_selected: true, game_mode: "fishing", difficulty_selected: false}});
    ui.advance(13); click(modes(ui)[0]); noDifficulty(ui);
    assert.equal(sent(ui, "survival_loading_mode_select").length, 2, "Old callbacks and timeouts cannot reopen setup");
}
{
    const {ui} = boot({localId: 1});
    assert(modes(ui).every(mode => !mode.enabled));
    modes(ui).forEach(click);
    assert.equal(sent(ui, "survival_loading_mode_select").length, 0, "Guests cannot select fishing or another mode");
}
for (const localId of [0, 1]) {
    const {ui} = boot({localId, selectedMode: "fishing"}); noDifficulty(ui);
    assert.equal(sent(ui, "survival_loading_mode_select").length, 0, "Authoritative fishing startup needs no new choice");
}
{
    const ui = harness({hud: true, loadSharedUI: true, state: {sequence: 1, resources: {}, wave: {
        status: "fishing", mode_selected: true, game_mode: "fishing", difficulty_selected: false, difficulty_options: difficulties}}});
    ui.advance(.11); noDifficulty(ui);
}
for (const [index, mode] of [[0, "pure"], [1, "standard"]]) {
    const {ui} = boot({profilesReady: true}); click(modes(ui)[index]);
    ui.emit("survival_loading_mode_result", {success: 1, session_id: "match-123", mode_id: mode});
    assert.equal(ui.nodes.DifficultySelectionTitle.text, "难度选择");
    assert.equal(ui.nodes.DifficultySelectionDialog.style.height, "670px");
    assert(ui.nodes.DifficultySelectionButtons.visible && !ui.nodes.MatchModeOptions.visible);
    assert.equal(sent(ui, "ui_difficulty_select_request").length, 0, "Combat mode still waits for a deliberate difficulty click");
    click(ui.nodes.DifficultySelectionButtons.children[0]);
    assert.equal(sent(ui, "ui_difficulty_select_request").length, 1);
}
console.log("FISHING_MODE_UI_PASS: three names, single-click/session/host guards, retry, fishing ACK/startup/wave-only skip difficulty, combat modes unchanged");
