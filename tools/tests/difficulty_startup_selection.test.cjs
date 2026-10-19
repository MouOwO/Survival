"use strict";
// Exercise the real authored HUD, shared components, and survival_ui controller.
const assert = require("node:assert/strict");
const path = require("node:path");
const {harness, ready} = require(path.resolve("tools/test_startup_loading_ui.js"));
const modes = [
    {mode_id: "pure", display_name: "纯净模式"},
    {mode_id: "standard", display_name: "常规模式"},
    {mode_id: "fishing", display_name: "摸鱼模式"},
    {mode_id: "rich", display_name: "丰饶模式", unlocked: 1}
];
const difficulties = cap => Array.from({length: 10}, (_, index) => ({
    difficulty_id: "N" + (index + 1), display_name: "N" + (index + 1),
    unlocked: index < cap ? 1 : 0,
    unlock_hint: index < cap ? "" : "队伍所有玩家通关 N" + index + " 后解锁"
}));
const startup = (setup = {}, patch = {}) => ready({admission_complete: true, profiles_ready: false,
    setup: {mode_selected: true, mode_id: "standard", selector_player_id: 0,
        mode_options: modes, difficulty_data_ready: true, can_confirm_difficulty: true,
        difficulty_selected: false, difficulty_id: "", max_difficulty_id: "N6",
        difficulty_limit_player_ids: [1], difficulty_options: difficulties(6),
        difficulty_options_by_mode: {standard: difficulties(6), pure: difficulties(6), rich: difficulties(5)},
        ...setup}, ...patch});
const boot = options => {
    const ui = harness({hud: true, loadSharedUI: true, ...options});
    ui.advance(.11); return ui;
};
const rows = ui => ui.nodes.DifficultySelectionButtons.children;
const click = node => node.events.onactivate();
const sent = ui => ui.requests.filter(request => request.name === "ui_difficulty_select_request");
const closed = ui => {
    assert(ui.nodes.DifficultySelectionOverlay.BHasClass("DifficultySelectionHidden"));
    assert(!ui.nodes.DifficultySelectionDialog.visible);
    assert(!ui.nodes.DifficultySelectionResume || !ui.nodes.DifficultySelectionResume.visible);
    assert(!ui.config.SurvivalUI.ModalManager.Get("survival_difficulty").IsOpen());
};
{
    // The server's setup-only permission supersedes a still-waiting profile and
    // older full-wave snapshot, and an advanced host cannot bypass the team cap.
    const state = startup();
    const ui = boot({startupState: state, state: {sequence: 1, resources: {}, wave: {
        status: "selecting_difficulty", mode_selected: true, game_mode: "standard",
        selector_player_id: 0, difficulty_selected: false, can_confirm_difficulty: false,
        difficulty_options: difficulties(10)}}});
    assert.equal(rows(ui).length, 10);
    assert(rows(ui).slice(0, 6).every(row => row.enabled), "auth progression is clickable while mode profiles are pending");
    assert(rows(ui).slice(6).every(row => !row.enabled), "team cap overrides a stale advanced-host wave snapshot");
    click(rows(ui)[6]); assert.equal(sent(ui).length, 0);
    click(rows(ui)[5]); click(rows(ui)[5]);
    assert.equal(sent(ui).length, 1, "one deliberate click records the difficulty exactly once");
    assert.equal(sent(ui)[0].payload.difficulty_id, "N6");
    ui.emit("ui_difficulty_select_result", {success: 1, difficulty_id: "N6", total_waves: 30});
    closed(ui);
    assert(!ui.nodes.DifficultySelectionOverlay.BHasClass("DifficultyPending"), "success clears the pending state without a full snapshot");
    // The login/private-snapshot gate is still closed for more than the old
    // request timeout. A stale startup false must not undo the successful ACK.
    ui.setStartup({...state}); ui.advance(13);
    closed(ui);
    assert.equal(sent(ui).length, 1);
    assert(!String(ui.nodes.DifficultySelectionError.text || "").includes("确认尚未完成"));
}
{
    const ui = boot({startupState: startup({mode_id: "rich", difficulty_options: difficulties(10)})});
    assert(rows(ui).slice(0, 5).every(row => row.enabled));
    assert(!rows(ui)[5].enabled, "rich uses its preloaded independent progression rather than the standard list");
    click(rows(ui)[5]); assert.equal(sent(ui).length, 0);
    click(rows(ui)[4]); assert.equal(sent(ui)[0].payload.difficulty_id, "N5");
}
{
    const ui = boot({startupState: startup(), localId: 1});
    assert(rows(ui).every(row => !row.enabled), "non-host viewers see the team limit without receiving selection authority");
    rows(ui).forEach(click); assert.equal(sent(ui).length, 0);
    ui.setStartup(startup({difficulty_selected: true, difficulty_id: "N6"}));
    closed(ui);
}
{
    const ui = boot({startupState: startup({can_confirm_difficulty: false}, {profiles_ready: true})});
    assert(rows(ui).every(row => !row.enabled), "explicit closed setup gate overrides a loaded legacy profile flag");
    rows(ui).forEach(click); assert.equal(sent(ui).length, 0);
}
{
    const ui = boot({startupState: startup()});
    assert(rows(ui)[5].enabled);
    ui.setStartup(startup({max_difficulty_id: "N5", difficulty_options: difficulties(5),
        difficulty_options_by_mode: {standard: difficulties(5), pure: difficulties(5), rich: difficulties(5)}}));
    assert.equal(rows(ui).length, 10);
    assert(!rows(ui)[5].enabled, "an authoritative lower teammate limit updates an already visible dialog");
    click(rows(ui)[5]); assert.equal(sent(ui).length, 0);
}
{
    // Older wave-only servers remain usable without new startup fields.
    const wave = {status: "selecting_difficulty", mode_selected: true, game_mode: "pure", selector_player_id: 0,
        difficulty_selected: false, can_confirm_difficulty: true, difficulty_options: difficulties(5)};
    const ui = boot({state: {sequence: 1, resources: {}, wave}});
    assert(rows(ui).slice(0, 5).every(row => row.enabled));
    click(rows(ui)[0]); assert.equal(sent(ui)[0].payload.difficulty_id, "N1");
}
console.log("DIFFICULTY_STARTUP_SELECTION_PASS: preloaded mode/team permissions, profile-independent confirmation, immediate ACK completion, host/lock guards and wave-only compatibility");
