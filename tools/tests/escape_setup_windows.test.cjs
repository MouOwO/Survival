"use strict";
const assert = require("node:assert/strict");
const {harness, ready} = require("../test_startup_loading_ui.js");
const options = [{difficulty_id: "N1", unlocked: true}, {difficulty_id: "N2", unlocked: true}];
const setup = {mode_selected: false, selector_player_id: 0, difficulty_options: options,
    mode_options: [{mode_id: "pure", display_name: "纯净模式"}, {mode_id: "standard", display_name: "常规模式"}]};
const click = panel => panel.events.onactivate();
const rows = ui => ui.nodes.DifficultySelectionButtons.children;
{
    const startup = ready({admission_complete: true, profiles_ready: true, setup});
    const ui = harness({startupState: startup, hud: true, loadSharedUI: true});
    ui.advance(0.11);
    const modal = ui.config.SurvivalUI.ModalManager.Get("survival_difficulty");
    click(ui.nodes.MatchModeOptions.children[0]);
    ui.config.SurvivalUILayers.HandleEscape("survival_difficulty");
    assert(!modal.IsOpen());
    assert(ui.nodes.DifficultySelectionOverlay.BHasClass("DifficultySelectionHidden"));
    assert(ui.nodes.DifficultySelectionResume.visible);
    assert.equal(ui.nodes.DifficultySelectionResume.children[0].text, "继续选择模式");
    assert(!ui.requests.some(request => request.name === "survival_loading_mode_select"));
    ui.setStartup({...startup}); ui.advance(0.5);
    assert(!modal.IsOpen(), "same-phase updates do not reopen the popup");
    click(ui.nodes.DifficultySelectionResume);
    assert(modal.IsOpen()); assert(!ui.nodes.DifficultySelectionResume.visible);
    assert(ui.nodes.MatchModeOptions.children[0].BHasClass("UISelected"));
    click(ui.nodes.DifficultySelectionConfirm);
    assert.equal(ui.requests.filter(request => request.name === "survival_loading_mode_select").length, 1);
    ui.setStartup({...startup, setup: {...setup, mode_selected: true, mode_id: "pure"}});
    assert(modal.IsOpen(), "next setup phase remains usable");
    assert.equal(ui.nodes.DifficultySelectionTitle.text, "难度选择");
}
{
    const wave = {status: "selecting_difficulty", mode_selected: true, game_mode: "pure", selector_player_id: 0,
        difficulty_selected: false, difficulty_options: options};
    const ui = harness({state: {sequence: 1, wave, resources: {}}, hud: true, loadSharedUI: true});
    ui.advance(0.11);
    const modal = ui.config.SurvivalUI.ModalManager.Get("survival_difficulty");
    click(rows(ui)[1]);
    ui.config.SurvivalUILayers.HandleEscape("survival_difficulty");
    assert(!modal.IsOpen()); assert(ui.nodes.DifficultySelectionResume.visible);
    ui.setState({sequence: 2, wave, resources: {gold: 100}}); ui.advance(0.5);
    assert(!modal.IsOpen());
    click(ui.nodes.DifficultySelectionResume);
    assert(modal.IsOpen()); assert(rows(ui)[1].BHasClass("UISelected"));
    click(ui.nodes.DifficultySelectionConfirm);
    const requests = ui.requests.filter(request => request.name === "ui_difficulty_select_request");
    assert.equal(requests.length, 1); assert.equal(requests[0].payload.difficulty_id, "N2");
    ui.setState({sequence: 3, wave: {...wave, difficulty_selected: true, status: "countdown"}, resources: {}});
    assert(!modal.IsOpen()); assert(!ui.nodes.DifficultySelectionResume.visible);
}
{
    const startup = ready({admission_complete: true, profiles_ready: true, setup});
    const ui = harness({startupState: startup, hud: true, loadSharedUI: true}); ui.advance(0.11);
    ui.config.SurvivalUILayers.HandleEscape("survival_difficulty");
    ui.setStartup({...startup, session_id: "new-session"});
    assert(ui.config.SurvivalUI.ModalManager.Get("survival_difficulty").IsOpen(), "new match is not dismissed by the old one");
    assert(!ui.nodes.DifficultySelectionResume.visible);
}
{
    // A native modal may leave inline visibility behind when its old closure is
    // discarded on reload. A completed match snapshot must hide that old panel.
    const wave={status:"countdown",mode_selected:true,game_mode:"standard",difficulty_selected:true};
    const ui=harness({state:{sequence:1,wave,resources:{}},hud:true,loadSharedUI:true});
    ui.advance(0.11);
    ui.nodes.DifficultySelectionOverlay.visible=true;
    ui.nodes.DifficultySelectionDialog.visible=true;
    ui.config.SurvivalUILayers.Open("survival_difficulty",ui.nodes.DifficultySelectionDialog,function(){});
    ui.setState({sequence:2,wave,resources:{}});
    assert.equal(ui.nodes.DifficultySelectionOverlay.visible,false,"completed choice clears stale native scrim visibility");
    assert.equal(ui.nodes.DifficultySelectionDialog.visible,false,"completed choice clears stale native dialog visibility");
    assert.equal(ui.config.SurvivalUILayers.Top(),null,"completed match removes an orphaned mandatory layer");
    assert(!ui.requests.some(r=>r.name==="ui_difficulty_select_request"),"visibility recovery does not select a difficulty");
}
console.log("ESCAPE_SETUP_WINDOWS_PASS: mode/difficulty hide and resume preserve drafts, same-phase updates stay hidden, completed choices remove resume, new session reopens");
