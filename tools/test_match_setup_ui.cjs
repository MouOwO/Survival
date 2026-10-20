"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const {harness, loading, ready, assertHidden, assertShown} = require("./test_startup_loading_ui.js");

const setup = (overrides = {}) => ({mode_selected: false, mode_id: "", selector_player_id: 0,
    mode_options: [{mode_id: "pure", display_name: "纯净模式", description: "本局不应用存档加成"},
        {mode_id: "standard", display_name: "常规模式", description: "使用已有存档加成"},
        {mode_id: "fishing", display_name: "摸鱼模式", description: "不应显示在按钮中"}], ...overrides});
const sent = (ui, name) => ui.requests.filter(request => request.name === name);
const click = panel => panel.events.onactivate();
function mode(ui, id) {
    const names = {pure: "纯净模式", standard: "常规模式", fishing: "摸鱼模式"};
    const button = ui.nodes.MatchModeOptions.children.find(row => row.children[0].text === names[id]);
    assert(button, "rendered mode button exists: " + id);
    return button;
}
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
        assertShown(noSnapshot, "post-team phase without a snapshot must cover the game until server admission");
        assert.equal(noSnapshot.authoredFirstFrame.rootVisible, true, "XML covers even before the first script render");
        assert.equal(noSnapshot.authoredFirstFrame.surfaceVisible, true);
        assert.equal(noSnapshot.requests.length, 0, "engine phase is not authentication or an invented readiness handshake");
        assert.equal(noSnapshot.nodes.StartupLoadingPercent.text, "0%", "engine phase does not fabricate progress");
        noSnapshot.setState(ready({admission_complete: true}));
        assertHidden(noSnapshot, "real admitted state is required to release the loading cover");
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
    assertShown(ui, "visual interpolation never asserts player readiness or releases pending admission");
}
{
    const startup=ready({admission_complete:true,profiles_ready:false,
        setup:setup({difficulty_options:wave().difficulty_options})});
    const ui=harness({startupState:startup,hud:true,loadSharedUI:true});ui.advance(.11);
    const modal=ui.config.SurvivalUI.ModalManager.Get("survival_difficulty");
    const modes=ui.nodes.MatchModeOptions.children;
    assert.equal(modes.length,3);
    assert.equal(ui.nodes.DifficultySelectionDialog.style.width,"275px");
    assert.equal(ui.nodes.DifficultySelectionDialog.style.height,"246px");
    assert(ui.nodes.DifficultySelectionDialog.BHasClass("MatchSetupMode"));
    for(const name of ["DifficultySelectionFooter","DifficultySelectionCurrent","DifficultySelectionMode",
        "DifficultySelectionConfirmHost","DifficultySelectionConfirm"]) assert.equal(ui.nodes[name],undefined,name+" is removed");
    for(const mode of modes){assert.equal(mode.children.length,1);assert(mode.children[0].BHasClass("MatchModeOptionName"));}
    assert.equal(mode(ui,"pure").children[0].text,"纯净模式");assert.equal(mode(ui,"standard").children[0].text,"常规模式");
    assert.equal(mode(ui,"fishing").children[0].text,"摸鱼模式");
    assert(!ui.nodes.DifficultySelectionHint.visible);assert.equal(ui.nodes.DifficultySelectionError.text,"");
    click(mode(ui,"pure"));click(mode(ui,"pure"));click(mode(ui,"standard"));
    assert.equal(sent(ui,"survival_loading_mode_select").length,1,"single click submits, duplicate and other-mode clicks cannot race");
    assert.deepEqual(JSON.parse(JSON.stringify(sent(ui,"survival_loading_mode_select")[0].payload)),
        {session_id:"match-123",mode_id:"pure"});
    assert(mode(ui,"pure").BHasClass("UISelected")&&mode(ui,"pure").BHasClass("UIBusy"));
    assert(modes.every(row=>row.enabled===false));assert.equal(ui.nodes.DifficultySelectionError.text,"");
    assert.equal(ui.nodes.DifficultySelectionDialog.style.height,"246px","pending mode keeps the compact name-only layout");
    assert(ui.config.SurvivalUILayers.HandleEscape("survival_difficulty"));
    assert(!modal.IsOpen()&&ui.nodes.DifficultySelectionResume.visible);
    assert(ui.nodes.DifficultySelectionResume.BHasClass("DifficultySelectionResume"));
    ui.setStartup({...startup});assert(!modal.IsOpen());
    click(ui.nodes.DifficultySelectionResume);
    assert(modal.IsOpen()&&!ui.nodes.DifficultySelectionResume.visible);
    assert(mode(ui,"pure").BHasClass("UISelected")&&mode(ui,"pure").BHasClass("UIBusy"));
    assert.equal(ui.nodes.DifficultySelectionDialog.style.height,"246px");
    click(mode(ui,"standard"));assert.equal(sent(ui,"survival_loading_mode_select").length,1,"resuming pending mode cannot submit again");
    click(ui.nodes.DifficultySelectionOverlay.children.find(row=>row.BHasClass("UIModalHitArea")));
    assert(modal.IsOpen(),"outside click cannot dismiss mandatory setup");
    ui.emit("survival_loading_mode_result",{success:1,session_id:"old-match",mode_id:"pure"});
    assert(ui.nodes.MatchModeOptions.visible&&mode(ui,"pure").BHasClass("UIBusy"));
    let closes=0;const close=modal.Close;modal.Close=function(){closes++;return close.apply(this,arguments);};
    ui.emit("survival_loading_mode_result",{success:1,session_id:"match-123",mode_id:"pure"});
    assert.equal(closes,0,"mode acknowledgement changes phase without closing the modal");
    assert(modal.IsOpen()&&!ui.nodes.MatchModeOptions.visible);
    assert.equal(ui.config.SurvivalUI.ModalManager.Get("survival_difficulty"),modal);
    assert.equal(ui.nodes.DifficultySelectionTitle.text,"难度选择");assert.equal(rows(ui).length,10);
    assert.equal(ui.nodes.DifficultySelectionDialog.style.width,"275px");
    assert.equal(ui.nodes.DifficultySelectionDialog.style.height,"670px");
    assert(!ui.nodes.DifficultySelectionDialog.BHasClass("MatchSetupMode"));
    assert(ui.nodes.DifficultySelectionHint.visible&&ui.nodes.DifficultySelectionHint.text.includes("通关进度"));
    click(rows(ui)[1]);assert(!rows(ui)[1].BHasClass("UISelected"));
    assert.equal(sent(ui,"ui_difficulty_select_request").length,0,"unready profile blocks difficulty even after successful mode");
    click(mode(ui,"standard"));assert.equal(sent(ui,"survival_loading_mode_select").length,1,"retired mode row cannot return from difficulty");
    ui.setStartup({...startup,setup:{...startup.setup,mode_selected:true,mode_id:"pure",error:"profile_load_failed"}});
    assert(ui.nodes.DifficultySelectionError.text.includes("玩家档案读取失败"));assert(ui.nodes.MatchSetupRetryHost.visible);
    click(ui.nodes.MatchSetupRetry);click(ui.nodes.MatchSetupRetry);
    assert.equal(sent(ui,"survival_loading_retry").length,1);assert.equal(sent(ui,"survival_loading_retry")[0].payload.session_id,"match-123");
    assert.equal(sent(ui,"survival_loading_client_ready").length,0);
    ui.setStartup({...startup,profiles_ready:true,setup:{...startup.setup,mode_selected:true,mode_id:"pure"}});
    assert(!ui.nodes.MatchSetupRetryHost.visible&&ui.nodes.DifficultySelectionHint.visible);
    assert(ui.nodes.DifficultySelectionHint.text.includes("队伍上限 N2")&&!ui.nodes.DifficultySelectionHint.text.includes("正在读取"));
    assert(rows(ui)[1].enabled&&!rows(ui)[1].BHasClass("UISelected"));
    assert.equal(sent(ui,"ui_difficulty_select_request").length,0,"profile readiness never submits an earlier blocked click");
    click(rows(ui)[1]);click(rows(ui)[1]);assert.equal(sent(ui,"ui_difficulty_select_request").length,1);
    assert.equal(sent(ui,"ui_difficulty_select_request")[0].payload.difficulty_id,"N2");
    ui.emit("ui_difficulty_select_result",{success:1});assert(!modal.IsOpen(),"authoritative success acknowledgement completes difficulty selection");
    ui.setState(snapshot(1,wave()));assert(!modal.IsOpen(),"an earlier wave snapshot cannot reopen acknowledged difficulty selection");
    ui.setState(snapshot(2,wave({status:"countdown",difficulty_selected:true})));assert(!modal.IsOpen());
}
{
    const startup=ready({admission_complete:true,profiles_ready:true,
        setup:setup({difficulty_options:wave().difficulty_options})});
    const ui=harness({startupState:startup,hud:true,loadSharedUI:true});ui.advance(.11);
    const modes=ui.nodes.MatchModeOptions.children;
    assert.equal(ui.nodes.DifficultySelectionDialog.style.height,"246px");
    click(mode(ui,"pure"));ui.advance(2);
    ui.emit("survival_loading_mode_result",{success:0,error:"mode_not_found",session_id:"match-123"});
    assert(ui.nodes.DifficultySelectionError.text.includes("该模式不可用"));
    assert(ui.nodes.DifficultySelectionError.visible);
    assert.equal(ui.nodes.DifficultySelectionDialog.style.height,"304px","mode errors have room for the retry message");
    assert(modes.every(row=>row.enabled&&!row.BHasClass("UIBusy")));
    click(mode(ui,"standard"));click(mode(ui,"pure"));assert.equal(sent(ui,"survival_loading_mode_select").length,2,"mode rejection enables one-click retry");
    assert.equal(ui.nodes.DifficultySelectionError.text,"");assert(!ui.nodes.DifficultySelectionError.visible);
    assert.equal(ui.nodes.DifficultySelectionDialog.style.height,"246px","retry clears the notice and restores compact height");
    ui.advance(10.01);assert(modes.every(row=>row.enabled===false),"old request timeout cannot release newer mode request");
    assert.equal(ui.nodes.DifficultySelectionDialog.style.height,"246px");
    ui.advance(2.1);assert(modes.every(row=>row.enabled));
    assert(ui.nodes.DifficultySelectionError.text.includes("选择未完成")&&ui.nodes.DifficultySelectionError.text.includes("重试"));
    assert(ui.nodes.DifficultySelectionError.visible);
    assert.equal(ui.nodes.DifficultySelectionDialog.style.height,"304px","timeout expands the popup for its actionable error");
    assert.equal(sent(ui,"survival_loading_mode_select").length,2,"mode timeout cannot silently retry");
    click(mode(ui,"pure"));click(mode(ui,"pure"));click(mode(ui,"standard"));assert.equal(sent(ui,"survival_loading_mode_select").length,3);
    assert.equal(ui.nodes.DifficultySelectionError.text,"");assert(!ui.nodes.DifficultySelectionError.visible);
    assert.equal(ui.nodes.DifficultySelectionDialog.style.height,"246px");
    ui.emit("survival_loading_mode_result",{success:0,error:"match_session_mismatch",session_id:"match-123"});
    assert(ui.nodes.DifficultySelectionError.text.includes("游戏状态已更新"));
    assert(ui.nodes.DifficultySelectionError.visible);
    assert.equal(ui.nodes.DifficultySelectionDialog.style.height,"304px");
    assert(modes.every(row=>row.enabled));
}
{
    const startup=ready({admission_complete:true,profiles_ready:true,setup:setup()});
    const ui=harness({startupState:startup,hud:true,localId:1,loadSharedUI:true});ui.advance(.11);
    click(mode(ui,"pure"));click(mode(ui,"standard"));
    click(mode(ui,"fishing"));
    assert.equal(sent(ui,"survival_loading_mode_select").length,0);
    assert(ui.nodes.DifficultySelectionHint.visible&&ui.nodes.DifficultySelectionHint.text.includes("等待房主"));
    assert.equal(ui.nodes.DifficultySelectionDialog.style.width,"275px");
    assert.equal(ui.nodes.DifficultySelectionDialog.style.height,"304px","guest waiting hint expands the compact mode popup");
    assert(ui.nodes.DifficultySelectionDialog.BHasClass("MatchSetupMode"));
    assert.equal(ui.nodes.DifficultySelectionError.text,"");assert(!ui.nodes.DifficultySelectionError.visible);
}
{
    const startup=ready({admission_complete:true,profiles_ready:true,setup:setup()});
    const ui=harness({startupState:startup,hud:true,loadSharedUI:true});ui.advance(.11);
    click(mode(ui,"pure"));ui.advance(1);
    ui.config.SurvivalUILayers.HandleEscape("survival_difficulty");
    ui.setStartup({...startup,session_id:"new-session"});
    const modes=ui.nodes.MatchModeOptions.children;
    assert(ui.config.SurvivalUI.ModalManager.Get("survival_difficulty").IsOpen());
    assert(modes.every(row=>row.enabled&&!row.BHasClass("UISelected")&&!row.BHasClass("UIBusy")));
    assert.equal(ui.nodes.DifficultySelectionDialog.style.height,"246px");
    ui.emit("survival_loading_mode_result",{success:1,mode_id:"pure",session_id:"match-123"});
    assert(ui.nodes.MatchModeOptions.visible,"old-session success cannot select new-session mode");
    click(mode(ui,"standard"));assert.equal(sent(ui,"survival_loading_mode_select").length,2);
    assert.equal(sent(ui,"survival_loading_mode_select")[1].payload.session_id,"new-session");
    ui.emit("survival_loading_mode_result",{success:0,error:"mode_not_found",session_id:"match-123"});
    ui.advance(11.01);assert(modes.every(row=>row.enabled===false),"old-session timeout and rejection cannot release new pending mode");
    ui.emit("survival_loading_mode_result",{success:1,mode_id:"standard",session_id:"new-session"});
    assert(!ui.nodes.MatchModeOptions.visible);
    assert.equal(ui.nodes.DifficultySelectionDialog.style.height,"670px");
    assert(!ui.nodes.DifficultySelectionDialog.BHasClass("MatchSetupMode"));
    ui.setStartup({...startup,session_id:"third-session",admission_complete:false});
    assert(ui.nodes.DifficultySelectionOverlay.BHasClass("DifficultySelectionHidden"));
    click(mode(ui,"pure"));assert.equal(sent(ui,"survival_loading_mode_select").length,2,"retired hidden row cannot bypass admission");
}

{
    const startup=ready({admission_complete:true,profiles_ready:false,
        setup:setup({difficulty_options:wave().difficulty_options})});
    const ui=harness({startupState:startup,hud:true,loadSharedUI:true});ui.advance(.11);
    const modal=ui.config.SurvivalUI.ModalManager.Get("survival_difficulty"),modes=ui.nodes.MatchModeOptions.children;
    click(mode(ui,"fishing"));click(mode(ui,"fishing"));click(mode(ui,"pure"));
    assert.equal(sent(ui,"survival_loading_mode_select").length,1);
    assert.equal(sent(ui,"survival_loading_mode_select")[0].payload.mode_id,"fishing");
    assert(mode(ui,"fishing").BHasClass("UIBusy")&&modes.every(mode=>!mode.enabled));
    ui.emit("survival_loading_mode_result",{success:1,mode_id:"fishing",session_id:"old-match"});
    assert(modal.IsOpen()&&mode(ui,"fishing").BHasClass("UIBusy"),"old-session fishing result cannot finish setup");
    ui.emit("survival_loading_mode_result",{success:0,error:"mode_not_found",session_id:"match-123"});
    assert(modal.IsOpen()&&ui.nodes.DifficultySelectionError.visible&&mode(ui,"fishing").enabled);
    click(mode(ui,"fishing"));click(mode(ui,"standard"));
    assert.equal(sent(ui,"survival_loading_mode_select").length,2,"fishing retry is deliberate and guarded");
    ui.emit("survival_loading_mode_result",{success:1,mode_id:"fishing",session_id:"match-123"});
    assert(!modal.IsOpen()&&!ui.nodes.MatchModeOptions.visible&&!ui.nodes.DifficultySelectionButtons.visible);
    assert(ui.nodes.DifficultySelectionOverlay.BHasClass("DifficultySelectionHidden"));
    assert.equal(rows(ui).length,0,"fishing acknowledgement never creates difficulty options, even before profiles are ready");
    assert(!ui.nodes.DifficultySelectionResume.visible);
    ui.setStartup({...startup,setup:{...startup.setup,mode_selected:true,mode_id:"fishing",error:"profile_load_failed"}});
    assert(!modal.IsOpen(),"fishing profile preparation cannot turn into difficulty selection");
    ui.setStartup({...startup,profiles_ready:true,setup:{...startup.setup,mode_selected:true,mode_id:"fishing"}});
    ui.setState(snapshot(1,wave({status:"fishing",game_mode:"fishing",difficulty_selected:false,total_waves:0})));
    ui.advance(13);click(mode(ui,"pure"));click(mode(ui,"fishing"));
    assert(!modal.IsOpen()&&!ui.nodes.DifficultySelectionResume.visible);
    assert.equal(ui.nodes.WaveNumber.text,"摸鱼模式");assert.equal(ui.nodes.WaveState.text,"自动挂机");
    assert.equal(ui.nodes.WaveTimer.text,"");
    assert.equal(sent(ui,"ui_difficulty_select_request").length,0,"fishing never fabricates a difficulty request");
    assert.equal(sent(ui,"survival_loading_mode_select").length,2,"retired mode callbacks and timeouts cannot restart fishing setup");
    ui.setStartup({...startup,session_id:"new-fishing-match"});
    assert(modal.IsOpen()&&ui.nodes.MatchModeOptions.visible,"a new session starts its own mode selection");
    assert(modes.every(mode=>mode.enabled&&!mode.BHasClass("UIBusy")));
}
{
    for(const localId of [0,1]){
        const startup=ready({admission_complete:true,profiles_ready:true,
            setup:setup({mode_selected:true,mode_id:"fishing",difficulty_options:wave().difficulty_options})});
        const ui=harness({startupState:startup,hud:true,localId,loadSharedUI:true});ui.advance(.11);
        assert(ui.nodes.DifficultySelectionOverlay.BHasClass("DifficultySelectionHidden"));
        assert(!ui.nodes.DifficultySelectionDialog.visible&&rows(ui).length===0,"authoritative fishing stays out of difficulty for all players");
        assert(!ui.requests.some(request=>request.name==="ui_difficulty_select_request"||request.name==="survival_loading_mode_select"));
    }
    const legacy=harness({state:snapshot(1,wave({game_mode:"fishing",status:"fishing",difficulty_selected:false})),hud:true,loadSharedUI:true});legacy.advance(.11);
    assert(legacy.nodes.DifficultySelectionOverlay.BHasClass("DifficultySelectionHidden"));
    assert.equal(rows(legacy).length,0,"wave-only snapshots also skip difficulty in fishing mode");
}
{
    const startup=ready({admission_complete:true,profiles_ready:true,setup:setup({mode_options:setup().mode_options.slice(0,2)})});
    const ui=harness({startupState:startup,hud:true,loadSharedUI:true});ui.advance(.11);
    assert.equal(ui.nodes.MatchModeOptions.children.length,2);
    assert.equal(ui.nodes.DifficultySelectionDialog.style.height,"190px","old two-mode snapshots retain their compact layout");
}
{
    const ui = harness({state: snapshot(1, wave()), hud: true, loadSharedUI: true});
    ui.root.actuallayoutwidth=1920; ui.root.actuallayoutheight=1080; ui.advance(0.3);
    assert.equal(rows(ui).length, 10);
    assert.equal(ui.nodes.DifficultySelectionDialog.style.width, "275px");
    assert.equal(ui.nodes.DifficultySelectionDialog.style.transform, "scale3d(1,1,1)", "small window cannot enlarge through shared Fit");
    ui.root.actuallayoutwidth=1280; ui.root.actuallayoutheight=720; ui.advance(0.3);
    assert.equal(ui.nodes.DifficultySelectionDialog.style.transform, "scale3d("+(2/3)+","+(2/3)+",1)");
    assert(ui.nodes.DifficultySelectionHint.visible&&ui.nodes.DifficultySelectionHint.text.includes("队伍上限 N2"));
    assert.equal(rows(ui)[0].children[0].children.at(-1).text, "", "unlocked cards omit redundant availability text");
    assert(!rows(ui)[0].children[0].children.at(-1).visible);
    click(rows(ui)[2]);
    assert.equal(sent(ui, "ui_difficulty_select_request").length, 0, "locked difficulty cannot submit");
    assert(rows(ui)[2].children[0].children.at(-1).text.includes("通关 N2"));
    const modal = ui.config.SurvivalUI.ModalManager.Get("survival_difficulty");
    click(rows(ui)[1]); click(rows(ui)[0]);
    assert.equal(sent(ui, "ui_difficulty_select_request").length, 1, "first valid click submits and blocks other clicks");
    assert(rows(ui)[1].BHasClass("UISelected"));
    assert(ui.config.SurvivalUILayers.HandleEscape("survival_difficulty"));
    assert(!modal.IsOpen() && ui.nodes.DifficultySelectionResume.visible);
    ui.setState(snapshot(2, wave())); ui.advance(0.5);
    assert(!modal.IsOpen());
    click(ui.nodes.DifficultySelectionResume);
    assert(modal.IsOpen() && rows(ui)[1].BHasClass("UISelected") && !rows(ui)[0].enabled);
    assert.equal(sent(ui, "ui_difficulty_select_request").length, 1, "resume cannot submit pending selection again");
    for (const code of ["difficulty_selector_required", "difficulty_not_unlocked", "player_not_ready",
        "profile_not_loaded", "mode_not_selected", "difficulty_locked", "difficulty_not_found"]) {
        ui.emit("ui_difficulty_select_result", {success: 0, error: code});
        assert(ui.nodes.DifficultySelectionError.text && !ui.nodes.DifficultySelectionError.text.includes(code));
        assert(rows(ui)[0].enabled, "rejection unlocks valid rows for a deliberate retry");
    }
    const updated=wave(); updated.difficulty_options[1].unlocked=false;
    ui.setState(snapshot(3, updated));
    assert(!rows(ui)[1].enabled && !rows(ui)[1].BHasClass("UISelected"));
    click(rows(ui)[1]); assert.equal(sent(ui, "ui_difficulty_select_request").length, 1);
    click(rows(ui)[0]);
    assert.equal(sent(ui, "ui_difficulty_select_request").length, 2);
    ui.emit("ui_difficulty_select_result", {success: 1});
    assert(!modal.IsOpen(), "authoritative success acknowledgement closes the mandatory selection");
    ui.setState(snapshot(4, wave({status: "countdown", difficulty_selected: true, difficulty_id: "N1"})));
    assert(!modal.IsOpen() && ui.nodes.DifficultySelectionOverlay.BHasClass("DifficultySelectionHidden"));
    click(rows(ui)[0]); assert.equal(sent(ui, "ui_difficulty_select_request").length, 2);
}
{
    const ui=harness({state:snapshot(1,wave()),hud:true,loadSharedUI:true});ui.advance(0.11);
    click(rows(ui)[1]); ui.advance(2);
    ui.emit("ui_difficulty_select_result",{success:0,error:"profile_not_loaded"});
    click(rows(ui)[0]); ui.advance(10.01);
    assert(!rows(ui)[0].enabled,"old request timeout cannot release a newer pending request");
    assert.equal(sent(ui,"ui_difficulty_select_request").length,2);
    ui.advance(2.1);
    assert(rows(ui)[0].enabled && ui.nodes.DifficultySelectionError.text.includes("重试"));
    assert.equal(sent(ui,"ui_difficulty_select_request").length,2,"timeout never silently retries a choice");
    click(rows(ui)[1]); click(rows(ui)[1]);
    assert.equal(sent(ui,"ui_difficulty_select_request").length,3,"explicit retry is still one click and one request");
}
{
    const ui = harness({state: snapshot(1, wave()), hud: true, loadSharedUI: true, localId: 1});
    ui.advance(0.11); click(rows(ui)[0]);
    assert.equal(sent(ui, "ui_difficulty_select_request").length, 0);
    assert(ui.nodes.DifficultySelectionHint.visible && ui.nodes.DifficultySelectionHint.text.includes("等待房主"));
    ui.setState(snapshot(2, wave({mode_selected: false})));
    assert(ui.nodes.DifficultySelectionOverlay.BHasClass("DifficultySelectionHidden"));
}
console.log("MATCH_SETUP_UI_PASS: compact name-only mode and difficulty, one-click submission in both phases, profile/host/lock guards, failure/timeout retry, Escape resume and authoritative completion");
