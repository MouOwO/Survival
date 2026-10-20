"use strict";
const assert = require("node:assert/strict");
const {harness, ready} = require("../test_startup_loading_ui.js");
const names = {standard:"常规模式", rich:"丰饶模式", cold:"极寒模式", scourge:"天灾模式", fishing:"摸鱼模式", pure:"纯净模式"};
function startup(changes = {}) {
    return ready({admission_complete:true, profiles_ready:true, setup:{mode_selected:false, selector_player_id:0,
        mode_options:Object.keys(names).map(mode_id => ({mode_id, display_name:names[mode_id], unlocked:1,
            ...(changes[mode_id] || {})}))}});
}
const capped = {daily_earned:20, daily_limit:20, daily_remaining:0, daily_capped:1};
const ui = harness({startupState:startup({standard:capped, pure:capped, cold:capped}), hud:true, loadSharedUI:true});
ui.advance(0.11);
const button = mode => ui.nodes.MatchModeOptions.children.find(row => row.children[0].text === names[mode]);
const requests = () => ui.requests.filter(row => row.name === "survival_loading_mode_select");
for (const mode of ["standard", "pure", "cold"]) {
    assert.equal(button(mode).enabled, false, mode + " is disabled at its authenticated acquisition cap");
    assert(button(mode).BHasClass("UIDisabled") && button(mode).BHasClass("MatchModeOptionLocked"));
    button(mode).events.onmouseover();
    assert.equal(ui.dispatched.at(-1)[2], "今日奖励已达上限");
    button(mode).events.onactivate();
}
assert.equal(requests().length, 0, "capped modes cannot issue a request");
assert(button("rich").enabled && button("scourge").enabled && button("fishing").enabled,
    "one capped reward does not disable other mode/online rewards");
ui.setStartup(startup({standard:{daily_pending:1}}));
assert.equal(button("standard").enabled, false, "server midnight reauthentication gates the mode");
button("standard").events.onmouseover();
assert.equal(ui.dispatched.at(-1)[2], "正在更新今日奖励额度……");
button("standard").events.onactivate();
assert.equal(requests().length, 0);
ui.setStartup(startup({standard:{daily_remaining:1, daily_capped:0}}));
assert.equal(button("standard").enabled, true, "an authoritative new-day snapshot restores entry");
button("standard").events.onactivate();
assert.equal(requests().length, 1);
ui.emit("survival_loading_mode_result", {success:0, error:"mode_daily_limit_reached", session_id:"match-123"});
assert.equal(ui.nodes.DifficultySelectionError.text, "今日奖励已达上限",
    "a cap reached after rendering still has a clear server rejection");
console.log("DAILY_CAP_MODE_SELECTION_PASS: cap grey state, tooltip, click guard, independent modes and authoritative refresh");
