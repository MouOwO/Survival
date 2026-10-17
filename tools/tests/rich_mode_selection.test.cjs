"use strict";
const assert = require("node:assert/strict");
const {harness, ready} = require("../test_startup_loading_ui.js");
const unlockHint = "通关常规模式 N10 后解锁";
const difficulties = Array.from({length: 10}, (_, index) => ({difficulty_id: "N" + (index + 1),
    unlocked: index < 5 ? 1 : 0, unlock_hint: "通关 N" + index + " 解锁"}));
const modes = rich => [{mode_id: "pure", display_name: "纯净模式"},
    {mode_id: "standard", display_name: "常规模式"}, {mode_id: "fishing", display_name: "摸鱼模式"},
    {mode_id: "rich", display_name: "丰饶模式", ...rich}];
const startup = (rich, overrides = {}) => ready({admission_complete: true, profiles_ready: true,
    setup: {mode_selected: false, selector_player_id: 0, difficulty_options: difficulties,
        mode_options: modes(rich)}, ...overrides});
const modeRequests = ui => ui.requests.filter(request => request.name === "survival_loading_mode_select");
const difficultyRequests = ui => ui.requests.filter(request => request.name === "ui_difficulty_select_request");
const richButton = ui => ui.nodes.MatchModeOptions.children[3];
const click = button => button.events.onactivate();

{
    const ui = harness({startupState: startup({unlocked: 1, pending: 1}, {profiles_ready: false}), hud: true, loadSharedUI: true});
    ui.advance(0.11);
    assert.equal(ui.nodes.MatchModeOptions.children.length, 4);
    assert.equal(ui.nodes.DifficultySelectionDialog.style.height, "302px", "the fourth mode expands the compact popup by one row");
    assert.equal(richButton(ui).children.length, 1, "mode rows retain only the mode name");
    assert.equal(richButton(ui).children[0].text, "丰饶模式");
    assert.equal(richButton(ui).enabled, false, "pending profile eligibility cannot unlock rich mode");
    richButton(ui).events.onmouseover();
    assert.equal(ui.dispatched.at(-1)[0], "DOTAShowTextTooltip");
    assert.equal(ui.dispatched.at(-1)[2], "正在读取解锁进度……");
    click(richButton(ui)); assert.equal(modeRequests(ui).length, 0);

    ui.setStartup(startup({unlocked: 0, unlock_hint: unlockHint}));
    assert(richButton(ui).BHasClass("MatchModeOptionLocked"));
    assert(richButton(ui).BHasClass("UIDisabled"));
    richButton(ui).events.onmouseover();
    assert.equal(ui.dispatched.at(-1)[2], unlockHint, "the locked row explains the normal N10 condition using the native tooltip");
    richButton(ui).events.onmouseout();
    assert.equal(ui.dispatched.at(-1)[0], "DOTAHideTextTooltip");
    click(richButton(ui)); assert.equal(modeRequests(ui).length, 0);
    assert(ui.nodes.MatchModeOptions.children.slice(0, 3).every(button => button.enabled), "legacy modes remain selectable without eligibility fields");

    ui.setStartup(startup({}));
    assert.equal(richButton(ui).enabled, false, "missing rich eligibility fails closed");
    click(richButton(ui)); assert.equal(modeRequests(ui).length, 0);

    ui.setStartup(startup({unlocked: 1}));
    assert.equal(richButton(ui).enabled, true);
    assert(!richButton(ui).BHasClass("MatchModeOptionLocked"));
    const beforeHover = ui.dispatched.length;
    richButton(ui).events.onmouseover();
    assert.equal(ui.dispatched.length, beforeHover, "unlocked rows do not show stale unlock rules");
    click(richButton(ui)); click(richButton(ui)); click(ui.nodes.MatchModeOptions.children[1]);
    assert.equal(modeRequests(ui).length, 1, "one click confirms rich mode and pending state prevents repeat requests");
    assert.equal(modeRequests(ui)[0].payload.mode_id, "rich");
    assert.equal(modeRequests(ui)[0].payload.session_id, "match-123");
    assert(richButton(ui).BHasClass("UISelected") && richButton(ui).BHasClass("UIBusy"));

    ui.emit("survival_loading_mode_result", {success: 1, mode_id: "rich", session_id: "match-123"});
    assert.equal(ui.nodes.DifficultySelectionTitle.text, "难度选择");
    assert.equal(ui.nodes.MatchModeOptions.visible, false);
    assert.equal(ui.nodes.DifficultySelectionButtons.children.length, 10);
    assert.equal(ui.nodes.DifficultySelectionDialog.style.height, "670px");
    const rows = ui.nodes.DifficultySelectionButtons.children;
    assert(rows.slice(0, 5).every(button => button.enabled), "rich N1 through N5 are available from the server snapshot");
    assert.equal(rows[5].enabled, false);
    assert.equal(rows[5].children[0].children[2].text, "通关 N5 解锁");
    click(rows[5]); assert.equal(difficultyRequests(ui).length, 0, "rich N6 cannot bypass its previous-difficulty requirement");
    click(rows[4]); click(rows[4]);
    assert.equal(difficultyRequests(ui).length, 1);
    assert.equal(difficultyRequests(ui)[0].payload.difficulty_id, "N5");
    assert.equal(ui.nodes.DifficultySelectionConfirm, undefined, "rich uses immediate difficulty selection without a confirm button");
}
{
    const ui = harness({startupState: startup({unlocked: 1}), hud: true, loadSharedUI: true, localId: 1});
    ui.advance(0.11); click(richButton(ui));
    assert.equal(richButton(ui).enabled, false);
    assert.equal(modeRequests(ui).length, 0, "only the selector may choose rich mode");
    assert.equal(ui.nodes.DifficultySelectionHint.text, "等待房主选择模式");
}
for (const [error, expected] of Object.entries({
    mode_not_unlocked: "通关常规模式 N10 后解锁丰饶模式。",
    rich_mode_locked: "通关常规模式 N10 后解锁丰饶模式。",
    rich_progression_pending: "正在读取解锁进度，请稍候。"
})) {
    const ui = harness({startupState: startup({unlocked: 1}), hud: true, loadSharedUI: true});
    ui.advance(0.11); click(richButton(ui));
    ui.emit("survival_loading_mode_result", {success: 0, error, session_id: "match-123"});
    assert.equal(ui.nodes.DifficultySelectionError.text, expected);
    assert.equal(ui.nodes.DifficultySelectionDialog.style.height, "360px", "server rejection retains room for the unlock error");
    ui.setStartup(startup({unlocked: 0, unlock_hint: unlockHint}));
    assert(!richButton(ui).BHasClass("UISelected"), "new authoritative eligibility clears the rejected selection");
    click(richButton(ui)); assert.equal(modeRequests(ui).length, 1);
}
console.log("RICH_MODE_SELECTION_PASS: native unlock hint, safe profile wait, immediate selection, ten difficulties and previous-clear gates");
