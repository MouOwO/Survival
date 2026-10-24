"use strict";
const assert = require("assert");
const fs = require("fs");
const vm = require("vm");
const script = fs.readFileSync("panorama/src/scripts/custom_game/player_web_auth.js", "utf8");
const xml = fs.readFileSync("panorama/src/layout/custom_game/startup_loading.xml", "utf8");
assert(xml.includes('scripts/custom_game/player_web_auth.js'));
assert(xml.includes('styles/custom_game/player_web_auth.css'));
assert(!xml.includes('id="PlayerWebAuth"'), "the optional component must not rewrite the frozen loading layout");
const session1 = "web_auth_fixture_match_1", session2 = "web_auth_fixture_match_2";
const uri = code => "https://pay.xiaofengnet.com/ws4-web/authorize?code=" + code;
function fixture(options = {}) {
    let localId = 0, state = {session_id: session1, players: [{player_id: 0, authenticated: false}]};
    const nodes = {}, events = {}, requests = [], opened = [], unsubscribed = [], hooks = {};
    class Panel {
        constructor(id) { this.id = id; this.valid = true; this.events = {}; this.classes = new Set(); this.text = ""; }
        IsValid() { return this.valid; }
        FindChildTraverse(id) { return nodes[id]; }
        SetPanelEvent(name, callback) { this.events[name] = callback; }
        AddClass(name) { this.classes.add(name); }
        SetHasClass(name, value) { if (value) this.classes.add(name); else this.classes.delete(name); }
    }
    const root = new Panel("root");
    nodes.StartupLoadingFooter = new Panel("StartupLoadingFooter");
    let tableCallback;
    const context = {
        $: {GetContextPanel: () => root, RegisterEventHandler: (name, panel, fn) => {
                if (options.unsupportedDeleteEvent) throw Error("First argument to RegisterEventHandler is not a valid event type");
                hooks[name] = fn;
            },
            CreatePanel: (type, parent, id) => {const node = new Panel(id); if (id) nodes[id] = node; return node;},
            DispatchEvent: (name, value) => opened.push({name, value})},
        Game: {GetLocalPlayerID: () => localId},
        GameEvents: {Subscribe: (name, callback) => {events[name] = callback; return 12;},
            Unsubscribe: id => unsubscribed.push(["event", id]),
            SendCustomGameEventToServer: (name, value) => requests.push({name, value})},
        CustomNetTables: {SubscribeNetTableListener: (name, fn) => {assert.strictEqual(name, "survival_loading"); tableCallback = fn; return 15;},
            UnsubscribeNetTableListener: id => unsubscribed.push(["table", id]), GetTableValue: () => state}
    };
    vm.runInNewContext(script, context);
    return {nodes, root, requests, opened, unsubscribed, hooks,
        loading(value) {state = value; tableCallback("survival_loading", "state", value);},
        personal(value) {events.survival_player_web_auth_state(value);},
        local(value) {localId = value;},
        shown() {return !nodes.PlayerWebAuth.classes.has("PlayerWebAuthHidden");},
        texts() {return Object.values(nodes).map(node => node.text).join(" ");}
    };
}
const f = fixture();
assert.strictEqual(f.shown(), false, "no public/loading snapshot can manufacture a private approval state");
assert.strictEqual(f.requests.length, 1);
assert.deepStrictEqual(JSON.parse(JSON.stringify(f.requests[0])), {name: "survival_player_web_auth_request", value: {session_id: session1}});
const pending = {session_id: session1, player_id: 0, status: "pending", user_code: "ABCD2345", verification_uri: uri("ABCD2345"),
    device_code: "private-device-should-never-render", access_token: "private-bearer-should-never-render"};
f.personal({...pending, player_id: 1});
f.personal({...pending, session_id: session2});
assert.strictEqual(f.shown(), false, "other-player and stale-match events are ignored");
f.personal(pending);
assert.strictEqual(f.shown(), true);
assert.strictEqual(f.nodes.PlayerWebAuthCode.text, "ABCD2345");
assert(!f.texts().includes("private-"));
f.nodes.PlayerWebAuthOpen.events.onactivate();
assert.deepStrictEqual(f.opened, [{name: "ExternalBrowserGoToURL", value: uri("ABCD2345")}]);
for (const bad of ["https://other.invalid/authorize?code=ABCD2345", uri("ABCD2345") + "&redirect=https://other.invalid", "javascript:alert(1)",
    "https://pay.xiaofengnet.com/ws4-web/authorize?code=OTHER234", uri("ABCD2345") + "#secret"]) {
    f.personal({...pending, verification_uri: bad});
    assert.strictEqual(f.nodes.PlayerWebAuthOpen.enabled, false);
    assert.strictEqual(f.nodes.PlayerWebAuthCode.text, "");
    f.nodes.PlayerWebAuthOpen.events.onactivate();
}
f.personal({...pending, user_code: '<img src="x">'});
f.nodes.PlayerWebAuthOpen.events.onactivate();
assert.strictEqual(f.opened.length, 1, "untrusted schemes, hosts, queries, fragments and codes cannot open a browser");
f.nodes.PlayerWebAuthRetry.events.onactivate();
assert.strictEqual(f.requests.length, 2);
assert.deepStrictEqual(Object.keys(f.requests[1].value), ["session_id"], "client requests never submit an account, PlayerID or a capability");
f.personal({...pending, status: "approved"});
assert.strictEqual(f.nodes.PlayerWebAuthCode.text, "");
assert.strictEqual(f.nodes.PlayerWebAuthOpen.enabled, false);
assert(f.nodes.PlayerWebAuthStatus.text.includes("校验账号"));
f.loading({session_id: session1, players: [{player_id: 0, authenticated: true}], admission_complete: false});
assert.strictEqual(f.shown(), false, "browser UI retires when ordinary account authentication completes");
f.loading({session_id: session2, players: [{player_id: 0, authenticated: false}]});
assert.strictEqual(f.shown(), false);
assert.strictEqual(f.nodes.PlayerWebAuthCode.text, "");
f.personal(pending);
assert.strictEqual(f.shown(), false, "an old approved match cannot revive the next match UI");
f.personal({...pending, session_id: session2});
assert.strictEqual(f.shown(), true);
f.loading({session_id: session2, players: [{player_id: 0, authenticated: false}], admission_complete: true});
assert.strictEqual(f.shown(), false);
const count = f.requests.length;
f.nodes.PlayerWebAuthRetry.events.onactivate();
assert.strictEqual(f.requests.length, count, "an admitted game cannot start a new authorization flow");
f.root.valid = false;
f.personal({...pending, session_id: session2});
assert.strictEqual(f.unsubscribed.length, 2);
f.hooks.PanelDeleted();
assert.strictEqual(f.unsubscribed.length, 2, "cleanup is idempotent");
const native = fixture({unsupportedDeleteEvent: true});
assert.strictEqual(native.requests.length, 1, "an unsupported optional native event cannot skip subscription setup");
native.personal(pending);
assert.strictEqual(native.shown(), true, "private authorization state still renders after native registration throws");
native.nodes.PlayerWebAuthOpen.events.onactivate();
assert.strictEqual(native.opened.length, 1);
native.root.valid = false;
native.loading({session_id: session1, players: [{player_id: 0, authenticated: false}]});
assert.strictEqual(native.unsubscribed.length, 2, "invalid-context callbacks retain cleanup without a native deletion hook");

// Diagnostics are a fixed, private enum tuple. They cannot revive a public
// short code, open a URL, or copy arbitrary server/body/credential text.
const diagnostic = fixture();
const failed = {...pending, status: "failed", diagnostic_revision: "WS4-WEB-04",
    diagnostic_phase: "start", diagnostic_stage: "http", diagnostic_status: 0,
    error: "private-response-body", diagnostic_detail: "private-native-exception"};
diagnostic.personal(failed);
assert.strictEqual(diagnostic.shown(), true);
assert(diagnostic.nodes.PlayerWebAuthStatus.text.endsWith("(WS4-WEB-04 / start / http / 0)"));
assert.strictEqual(diagnostic.nodes.PlayerWebAuthCode.text, "");
assert.strictEqual(diagnostic.nodes.PlayerWebAuthOpen.enabled, false);
diagnostic.nodes.PlayerWebAuthOpen.events.onactivate();
assert.strictEqual(diagnostic.opened.length, 0, "a diagnostic never grants browser navigation");
assert(!diagnostic.texts().includes("private-"));
for (const phase of ["start", "poll"]) {
    for (const stage of ["API", "create", "send", "http", "json", "fields", "timeout"]) {
        diagnostic.personal({...failed, diagnostic_phase: phase, diagnostic_stage: stage, diagnostic_status: 599});
        assert(diagnostic.nodes.PlayerWebAuthStatus.text.endsWith(`(WS4-WEB-04 / ${phase} / ${stage} / 599)`));
    }
}
for (const bad of [
    {diagnostic_revision: "private-version"}, {diagnostic_phase: "private-phase"},
    {diagnostic_stage: "private-stage"}, {diagnostic_phase: "toString"}, {diagnostic_stage: "__proto__"},
    {diagnostic_phase: {start: true}}, {diagnostic_stage: ["http"]},
    {diagnostic_status: "403"}, {diagnostic_status: -1}, {diagnostic_status: 600},
    {diagnostic_status: 200.5}, {diagnostic_status: NaN}, {diagnostic_status: Infinity},
    {diagnostic_status: null}, {diagnostic_status: {value: 403}}
]) {
    diagnostic.personal({...failed, ...bad});
    assert(!diagnostic.nodes.PlayerWebAuthStatus.text.includes("WS4-WEB-04"), "reject malformed diagnostic fields");
    assert(!diagnostic.texts().includes("private-"));
    assert.strictEqual(diagnostic.nodes.PlayerWebAuthOpen.enabled, false);
}
diagnostic.personal({...failed, player_id: 1});
diagnostic.personal({...failed, session_id: session2});
assert(!diagnostic.nodes.PlayerWebAuthStatus.text.includes("WS4-WEB-04"), "other-player and stale diagnostics are ignored");
for (const status of ["requesting", "pending", "approved", "expired"]) {
    diagnostic.personal({...failed, status});
    assert(!diagnostic.nodes.PlayerWebAuthStatus.text.includes("WS4-WEB-04"), "diagnostics belong only to failed state");
    assert.strictEqual(diagnostic.nodes.PlayerWebAuthCode.text, status === "pending" ? "ABCD2345" : "");
    assert.strictEqual(diagnostic.nodes.PlayerWebAuthOpen.enabled, status === "pending");
}
diagnostic.personal({...failed, status: "pending"});
diagnostic.nodes.PlayerWebAuthOpen.events.onactivate();
assert.deepStrictEqual(diagnostic.opened, [{name: "ExternalBrowserGoToURL", value: uri("ABCD2345")}],
    "a legitimate pending short code keeps its original strict navigation behavior");
console.log("PLAYER_WEB_AUTH_UI_PASS: private state, fixed origin, enum-only WS4-WEB-04 diagnostics, approval retirement and cleanup");
