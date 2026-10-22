"use strict";
// Exercise the real authored HUD, shared components, and survival_ui controller.
const assert = require("node:assert/strict");
const path = require("node:path");
const {harness, ready} = require(path.resolve("tools/test_startup_loading_ui.js"));
const modes = [
    {mode_id: "pure", display_name: "纯净模式"},
    {mode_id: "standard", display_name: "常规模式"},
    {mode_id: "fishing", display_name: "摸鱼模式"},
    {mode_id: "rich", display_name: "丰饶模式", unlocked: 1},
    {mode_id: "cold", display_name: "极寒模式", unlocked: 1}
];
const difficulties = (cap, total = 10) => Array.from({length: total}, (_, index) => ({
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
for (const [mode, total] of [["rich", 30], ["cold", 50]]) {
    const configured = difficulties(total, total);
    const invalid = ["N0", "N01", "n1", "N-1", "N1.5", "N1x"].map(difficulty_id => ({difficulty_id, unlocked: 1}));
    const state = startup({mode_id: mode, difficulty_access_policy: "all_configured",
        max_difficulty_id: "N" + total, difficulty_limit_player_ids: [],
        difficulty_options: configured,
        difficulty_options_by_mode: {[mode]: [...invalid, ...configured.slice().reverse()]}});
    const ui = boot({startupState: state});
    assert.equal(rows(ui).length, total, mode + " displays every configured difficulty and rejects malformed IDs");
    assert(rows(ui).every((row, index) => row.__difficultyId === "N" + (index + 1) && row.enabled),
        "canonical high difficulty IDs are sorted numerically and remain selectable");
    assert(!rows(ui).some(row => row.__difficultyId === "N" + (total + 1)), "the UI never invents unadvertised difficulties");
    assert(ui.nodes.DifficultySelectionHint.text.includes("全难度开放至 N" + total));
    ui.nodes.DifficultySelectionHint.events.onmouseover();
    const tooltip = ui.dispatched.filter(event => event[0] === "DOTAShowTextTooltip").at(-1)[2];
    assert(tooltip.includes("全部已配置难度已开放") && !tooltip.includes("最低通关进度"),
        "the all-configured policy describes the active server rule");
    click(rows(ui)[total - 1]);
    assert.equal(sent(ui).length, 1);
    assert.equal(sent(ui)[0].payload.difficulty_id, "N" + total, "high difficulty requests use the selected real ID");
    const viewer = boot({startupState: state, localId: 1});
    assert(rows(viewer).every(row => !row.enabled), "opening all tiers never grants non-host selection authority");
    click(rows(viewer)[total - 1]); assert.equal(sent(viewer).length, 0);
}
{
    const configured = difficulties(49, 50);
    const state = startup({mode_id: "cold", difficulty_access_policy: "all_configured",
        difficulty_options_by_mode: {cold: configured}});
    const ui = boot({startupState: state});
    const last = rows(ui)[49];
    assert(!last.enabled, "the policy label cannot override a locked server option");
    const availability = last.children[0].children.find(node => node.BHasClass("DifficultyOptionAvailability"));
    assert.equal(availability.text, "全员通关 N49 解锁", "higher-tier prerequisite text keeps the entire difficulty number");
    click(last); assert.equal(sent(ui).length, 0);
    ui.setStartup(startup({mode_id: "cold", difficulty_access_policy: "all_configured", can_confirm_difficulty: false,
        difficulty_options_by_mode: {cold: difficulties(50, 50)}}));
    assert(rows(ui).every(row => !row.enabled), "opening all tiers still waits for the server readiness gate");
    click(rows(ui)[49]); assert.equal(sent(ui).length, 0);
}
{
    const configured = difficulties(30, 30);
    configured[29].temporary_config = 1;
    configured[29].source_difficulty_id = "N30";
    const ui = boot({startupState: startup({mode_id: "rich", difficulty_options_by_mode: {rich: configured}})});
    const availability = rows(ui)[29].children[0].children.find(node => node.BHasClass("DifficultyOptionAvailability"));
    assert.equal(availability.text, "临时配置 · 沿用 N30", "temporary high-tier profiles display their full source ID");
    ui.nodes.DifficultySelectionHint.events.onmouseover();
    assert(ui.dispatched.filter(event => event[0] === "DOTAShowTextTooltip").at(-1)[2].includes("最低通关进度"),
        "servers without the all-configured policy retain their progression explanation");
}
{
    const wave = {status: "selecting_difficulty", mode_selected: true, game_mode: "cold", selector_player_id: 0,
        difficulty_selected: false, can_confirm_difficulty: true, difficulty_access_policy: "all_configured",
        difficulty_options: difficulties(50, 50)};
    const ui = boot({state: {sequence: 1, resources: {}, wave}});
    assert.equal(rows(ui).length, 50);
    assert(ui.nodes.DifficultySelectionHint.text.includes("全难度开放至 N50"), "wave-only snapshots forward the same policy");
    click(rows(ui)[49]); assert.equal(sent(ui)[0].payload.difficulty_id, "N50");
}
console.log("DIFFICULTY_STARTUP_SELECTION_PASS: preloaded team permissions, configured N30/N50 tiers, canonical IDs, policy hints, host/readiness guards, immediate ACK and wave-only compatibility");
