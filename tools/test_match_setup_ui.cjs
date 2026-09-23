"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const {harness, loading, ready, assertHidden, assertShown} = require("./test_startup_loading_ui.js");

const setup = (overrides = {}) => ({mode_selected: false, mode_id: "", selector_player_id: 0,
    mode_options: [{mode_id: "pure", display_name: "纯净模式", description: "本局不应用存档加成"},
        {mode_id: "standard", display_name: "常规模式", description: "使用已有存档加成"}], ...overrides});
const sent = (ui, name) => ui.requests.filter(request => request.name === name);
const click = panel => panel.events.onactivate();
function rows(ui) { return ui.nodes.DifficultySelectionButtons.children.filter(panel => panel.BHasClass("DifficultyOptionButton")); }
function wave(overrides = {}) {
    return {status: "selecting_difficulty", mode_selected: true, game_mode: "pure", selector_player_id: 0,
        difficulty_selected: false, difficulty_options: Array.from({length: 10}, (_, index) => ({
            difficulty_id: "N" + (index + 1), display_name: "挑战 " + (index + 1), total_waves: 30,
            unlocked: index === 0 ? true : index === 1 ? 1 : 0,
            unlock_hint: index > 1 ? "通关 N" + index + " 解锁" : ""})), ...overrides};
}
const snapshot = (sequence, value) => ({sequence, resources: {}, wave: value});

// Admission is independent of mode selection and mode-specific profile I/O.
{
    const config = {};
    const ui = harness({state: loading({setup: setup(), admission_complete: false}), sharedConfig: config, engineWrapper: true});
    ui.imageLoaded();
    assert.equal(ui.nodes.StartupModeOverlay, undefined, "no setup UI is rendered during loading");
    assert.equal(sent(ui, "survival_loading_client_ready").length, 1, "unselected mode does not block admission handshake");
    ui.setState(ready({setup: setup(), admission_complete: false}));
    assertShown(ui, "all_ready is not admission when the server explicitly provides admission_complete");
    ui.setState(ready({setup: setup(), admission_complete: true, profiles_ready: false}));
    assertHidden(ui, "authentication/resources admit player before mode-specific profile loading");
    ui.advance(2);
    const transitions = ui.messages.filter(message => message.startsWith("[STARTUP_VISIBILITY] "))
        .map(message => JSON.parse(message.slice("[STARTUP_VISIBILITY] ".length)));
    assert.deepEqual(transitions.map(event => event.visible), [true, false], "visibility diagnostic emits transitions only, never per tick");
    assert.equal(transitions[1].admission_complete, true);
    ui.setState(loading({setup: setup({mode_selected: true, mode_id: "pure"}), admission_complete: true,
        phase: "error", error: "profile_load_failed"}));
    assertHidden(ui, "in-game profile failures never reopen loading");
    const phase = harness({sharedConfig: config, engineWrapper: true});
    phase.advance(30);
    assertHidden(phase, "authoritative admission memo survives missing phase snapshot without one-second flashback");
    phase.setState(loading({session_id: "next-match", admission_complete: false}));
    assertShown(phase, "a genuinely new match still loads normally");
    const fresh = harness({state: loading({admission_complete: true, setup: setup(), error: "profile_load_failed"}), engineWrapper: true});
    assertHidden(fresh, "fresh game instance trusts permanent admission even when profiles are pending or failed");
    const identityGap = harness({state: ready({admission_complete: true}), localId: -1, engineWrapper: true});
    assertHidden(identityGap, "permanent admission does not flash while the HUD obtains the local identity");
    identityGap.setLocalId(0); identityGap.advance(0.5); assertHidden(identityGap, "identified admitted player stays hidden");
    const outsider = harness({state: ready({admission_complete: true}), localId: 2, engineWrapper: true});
    assertShown(outsider, "admission does not release a known player outside the frozen roster");
    for (const enginePhase of [3, 4, 8]) {
        const noSnapshot = harness({enginePhase, engineWrapper: true});
        noSnapshot.advance(30);
        assertHidden(noSnapshot, "engine has entered game: fresh phase without nettable or shared cache never flashes loading");
        assert.equal(noSnapshot.requests.length, 0, "engine phase is not authentication or an invented readiness handshake");
        assert.equal(noSnapshot.nodes.StartupLoadingPercent.text, "0%", "engine phase does not fabricate progress");
        noSnapshot.setState(ready({admission_complete: true}));
        assertHidden(noSnapshot, "real admitted state replaces presentation-only hiding");
        noSnapshot.setLocalId(2); noSnapshot.advance(0.5);
        assertShown(noSnapshot, "explicit late join denial remains visible after engine entered game");
    }
    const denied = harness({enginePhase: 8, state: loading({admission_complete: false, error: "backend_authentication_failed"})});
    assertShown(denied, "explicit non-admitted authentication failure remains actionable");
}
{
    const css = fs.readFileSync("panorama/src/styles/custom_game/startup_loading.css", "utf8");
    const fillRule = css.match(/\.StartupLoadingProgressFill\s*\{([^}]+)\}/)[1];
    assert(/transition-property:\s*width/.test(fillRule) && /transition-duration:\s*0\.1s/.test(fillRule),
        "engine interpolates real target width over 0.1 seconds and retargets interrupted transitions");
    const ui = harness({state: loading({assets: {progress: 50, complete: false, failed: 0},
        players: [{player_id: 0, authenticated: true, client_ready: false, ready: false}]})});
    assert.equal(ui.nodes.StartupLoadingProgressFill.style.width, "50.0%");
    ui.setState(loading({assets: {progress: 50, complete: false, failed: 0},
        players: [{player_id: 0, authenticated: true, client_ready: true, ready: false}]}));
    assert.equal(ui.nodes.StartupLoadingProgressFill.style.width, "70.0%");
    ui.setState(loading({assets: {progress: 25, complete: false, failed: 0},
        players: [{player_id: 0, authenticated: true, client_ready: true, ready: false}]}));
    assert.equal(ui.nodes.StartupLoadingProgressFill.style.width, "55.0%", "latest real target replaces in-flight animation in either direction");
    assert.equal(ui.nodes.StartupLoadingPercent.text, "55%");
    assert.equal(ui.nodes.StartupLoadingStatus.text, "加载中……", "visual interpolation never asserts player readiness");
}
{
    const startup = ready({admission_complete: true, profiles_ready: false,
        setup: setup({difficulty_options: wave().difficulty_options})});
    // No HERO_READY / wave snapshot yet: setup contains enough real unlock data.
    const ui = harness({startupState: startup, hud: true, loadSharedUI: true});
    ui.advance(0.11);
    assert.equal(ui.nodes.MatchModeOptions.children.length, 2);
    assert.equal(ui.nodes.DifficultySelectionConfirm.enabled, false);
    const modal = ui.config.SurvivalUI.ModalManager.Get("survival_difficulty");
    ui.config.SurvivalUILayers.CloseTop(); assert(modal.IsOpen(), "Escape cannot dismiss in-game setup");
    click(ui.nodes.DifficultySelectionOverlay.children.find(panel => panel.BHasClass("UIModalHitArea")));
    assert(modal.IsOpen(), "outside click cannot dismiss in-game setup");
    click(ui.nodes.MatchModeOptions.children[0]);
    assert.equal(sent(ui, "survival_loading_mode_select").length, 0);
    click(ui.nodes.DifficultySelectionConfirm); click(ui.nodes.DifficultySelectionConfirm);
    assert.equal(sent(ui, "survival_loading_mode_select").length, 1);
    assert.deepEqual(JSON.parse(JSON.stringify(sent(ui, "survival_loading_mode_select")[0].payload)),
        {session_id: "match-123", mode_id: "pure"});
    ui.emit("survival_loading_mode_result", {success: 1, session_id: "old-match", mode_id: "pure"});
    assert.equal(ui.nodes.MatchModeOptions.visible, true, "old-session acknowledgements cannot advance setup");
    ui.emit("survival_loading_mode_result", {success: 1, mode_id: "pure"});
    assert.equal(ui.nodes.MatchModeOptions.visible, false, "server acknowledgement immediately changes the same dialog");
    assert.equal(ui.nodes.DifficultySelectionTitle.text, "难度选择");
    assert.equal(rows(ui).length, 10, "real admission unlock options render before any wave snapshot");
    assert.equal(ui.config.SurvivalUI.ModalManager.Get("survival_difficulty"), modal);
    assert(modal.IsOpen(), "mode -> difficulty never closes or replaces the modal");
    click(rows(ui)[1]);
    assert(rows(ui)[1].BHasClass("UISelected"), "profile I/O permits local difficulty draft");
    assert.equal(ui.nodes.DifficultySelectionConfirm.enabled, false);
    click(ui.nodes.DifficultySelectionConfirm);
    assert.equal(sent(ui, "ui_difficulty_select_request").length, 0, "profile I/O still blocks confirmation");
    ui.setStartup({...startup, setup: {...startup.setup, mode_selected: true, mode_id: "pure", error: "profile_load_failed"}});
    assert(ui.nodes.DifficultySelectionError.text.includes("玩家档案读取失败"));
    assert.equal(ui.nodes.MatchSetupRetryHost.visible, true);
    click(ui.nodes.MatchSetupRetry); click(ui.nodes.MatchSetupRetry);
    assert.equal(sent(ui, "survival_loading_retry").length, 1, "profile retry is explicit and rate-limited");
    assert.equal(sent(ui, "survival_loading_retry")[0].payload.session_id, "match-123");
    assert.equal(sent(ui, "survival_loading_client_ready").length, 0, "in-game profile retry never restarts admission handshake");
    ui.setStartup({...startup, profiles_ready: true, setup: {...startup.setup, mode_selected: true, mode_id: "pure"}});
    assert.equal(ui.nodes.MatchSetupRetryHost.visible, false);
    assert.equal(ui.nodes.DifficultySelectionConfirm.enabled, true, "actual profiles_ready enables confirmation without losing draft");
    click(ui.nodes.DifficultySelectionConfirm);
    assert.equal(sent(ui, "ui_difficulty_select_request")[0].payload.difficulty_id, "N2");
    ui.emit("ui_difficulty_select_result", {success: 1});
    assert(modal.IsOpen(), "difficulty still awaits authoritative selection state");
    ui.setState(snapshot(1, wave({status: "countdown", difficulty_selected: true})));
    assert(!modal.IsOpen());
}
{
    const startup = ready({admission_complete: true, profiles_ready: false, setup: setup()});
    const ui = harness({startupState: startup, hud: true, localId: 1, loadSharedUI: true}); ui.advance(0.11);
    click(ui.nodes.MatchModeOptions.children[0]); click(ui.nodes.DifficultySelectionConfirm);
    assert.equal(sent(ui, "survival_loading_mode_select").length, 0);
    assert(ui.nodes.DifficultySelectionHint.text.includes("等待房主"));
    ui.setLocalId(0); ui.advance(0.5);
    click(ui.nodes.MatchModeOptions.children[1]); click(ui.nodes.DifficultySelectionConfirm);
    ui.emit("survival_loading_mode_result", {success: 0, error: "match_session_mismatch"});
    assert(ui.nodes.DifficultySelectionError.text.includes("游戏状态已更新"));
    assert.equal(ui.nodes.DifficultySelectionConfirm.enabled, true);
    ui.setStartup({...startup, session_id: "another-session"});
    assert.equal(ui.nodes.DifficultySelectionCurrent.text, "当前选择：尚未选择");
    assert.equal(ui.nodes.DifficultySelectionConfirm.enabled, false);
    ui.setStartup({...startup, session_id: "another-session", admission_complete: false});
    assert(ui.nodes.DifficultySelectionOverlay.BHasClass("DifficultySelectionHidden"), "HUD setup never precedes server admission");
}
{
    const ui = harness({state: snapshot(1, wave()), hud: true, loadSharedUI: true});
    ui.advance(0.11);
    assert.equal(rows(ui).length, 10);
    assert(ui.nodes.DifficultySelectionMode.text.includes("纯净模式"));
    assert.equal(ui.nodes.DifficultySelectionConfirm.enabled, false);
    const modal = ui.config.SurvivalUI.ModalManager.Get("survival_difficulty");
    ui.config.SurvivalUILayers.CloseTop(); assert(modal.IsOpen(), "difficulty cannot be closed with Escape");
    click(rows(ui)[2]); assert.equal(ui.nodes.DifficultySelectionConfirm.enabled, false, "locked row cannot be selected");
    assert(rows(ui)[2].children[0].children.at(-1).text.includes("通关 N2"));
    click(rows(ui)[1]);
    assert.equal(sent(ui, "ui_difficulty_select_request").length, 0);
    assert(rows(ui)[1].BHasClass("UISelected"));
    click(ui.nodes.DifficultySelectionConfirm); click(ui.nodes.DifficultySelectionConfirm);
    assert.equal(sent(ui, "ui_difficulty_select_request").length, 1);
    assert.equal(sent(ui, "ui_difficulty_select_request")[0].payload.difficulty_id, "N2");
    for (const code of ["difficulty_selector_required", "difficulty_not_unlocked", "player_not_ready",
        "profile_not_loaded", "mode_not_selected", "difficulty_locked", "difficulty_not_found"]) {
        ui.emit("ui_difficulty_select_result", {success: 0, error: code});
        assert(ui.nodes.DifficultySelectionError.text && !ui.nodes.DifficultySelectionError.text.includes(code));
    }
    const updated = wave(); updated.difficulty_options[1].unlocked = false;
    ui.setState(snapshot(2, updated));
    assert.equal(ui.nodes.DifficultySelectionConfirm.enabled, false, "server relock revokes local draft");
    assert.equal(ui.nodes.DifficultySelectionCurrent.text, "当前选择：尚未选择");
    click(rows(ui)[0]); click(ui.nodes.DifficultySelectionConfirm);
    ui.emit("ui_difficulty_select_result", {success: 1});
    assert(modal.IsOpen(), "result event waits for confirmed wave snapshot");
    ui.setState(snapshot(3, wave({status: "countdown", difficulty_selected: true, difficulty_id: "N1"})));
    assert(!modal.IsOpen());
    assert(ui.nodes.DifficultySelectionOverlay.BHasClass("DifficultySelectionHidden"));
}
{
    const ui = harness({state: snapshot(1, wave()), hud: true, loadSharedUI: true, localId: 1});
    ui.advance(0.11); click(rows(ui)[0]); click(ui.nodes.DifficultySelectionConfirm);
    assert.equal(sent(ui, "ui_difficulty_select_request").length, 0, "non-selector never submits a draft");
    assert(ui.nodes.DifficultySelectionHint.text.includes("等待房主"));
    ui.setState(snapshot(2, wave({mode_selected: false})));
    assert(ui.nodes.DifficultySelectionOverlay.BHasClass("DifficultySelectionHidden"), "difficulty does not precede mode setup");
}
console.log("MATCH_SETUP_UI_PASS: real shared mandatory modals; admission -> in-game mode -> immediate difficulty; profiles gate confirmation; no loading flashback; host-only draft/confirm; ten rows; bool/numeric locks; relock and session reset; localized errors; no duplicate requests");
