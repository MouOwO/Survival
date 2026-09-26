"use strict";
const assert = require("assert");
const fs = require("fs");
const vm = require("vm");
const script = fs.readFileSync("panorama/src/scripts/custom_game/startup_loading.js", "utf8");
const xml = fs.readFileSync("panorama/src/layout/custom_game/startup_loading.xml", "utf8");
const loadingXml = fs.readFileSync("panorama/src/layout/custom_game/custom_loading_screen.xml", "utf8");
assert(!/<Panel\b[^>]*\bid=/.test(xml.match(/<Panel\b[^>]*>/)[0]), "Panorama layout root must not declare an id");

function harness(options = {}) {
    const nodes = {}, requests = [], scheduled = [], handlers = {}, subscriptions = [], messages = [], visibilityWrites = [], eventHandlers = {};
    const nativeRuleCalls = [], nativePlayerInfoCalls = [];
    const config = options.sharedConfig || {};
    let now = 0, state = options.state, startupState = options.startupState, localId = options.localId === undefined ? 0 : options.localId;
    class Panel {
        constructor(type, parent, id) {
            this.type = type; this.parent = parent; this.id = id; this.children = [];
            this.style = {}; this.classes = new Set(); this.events = {}; this.valid = true;
            this._visible = true;
            Object.defineProperty(this, "visible", {
                get: () => this._visible,
                set: value => { this._visible = value; visibilityWrites.push({panel: this, property: "visible", value}); }
            });
            Object.defineProperty(this.style, "visibility", {
                get: () => this._styleVisibility,
                set: value => { this._styleVisibility = value; visibilityWrites.push({panel: this, property: "visibility", value}); }
            });
            if (parent) parent.children.push(this); if (id) nodes[id] = this;
        }
        IsValid() { return this.valid; }
        AddClass(value) { this.classes.add(value); }
        RemoveClass(value) { this.classes.delete(value); }
        SetHasClass(value, enabled) { enabled ? this.classes.add(value) : this.classes.delete(value); }
        BHasClass(value) { return this.classes.has(value); }
        RemoveAndDeleteChildren() { this.children = []; }
        SetPanelEvent(name, handler) { this.events[name] = handler; }
        SetImage(path) { this.image = path; }
        GetParent() { return this.parent; }
        GetChildCount() { return this.children.length; }
        GetChild(index) { return this.children[index]; }
        SetAcceptsFocus() {}
        FindChildTraverse(id) {
            for (const child of this.children) {
                if (child.id === id) return child;
                const result = child.FindChildTraverse(id); if (result) return result;
            }
            return null;
        }
    }
    const viewport = new Panel("Panel", null, "Viewport");
    const wrapper = options.engineWrapper ? new Panel("Panel", viewport, "CustomLoadingScreenContainer") : null;
    if (options.nativeSetup) {
        const native = new Panel("Panel", viewport, "TeamSelectContainer");
        new Panel("Panel", native, "TeamsList");
        new Panel("Panel", native, "GameAndPlayersRoot").visible = false;
        new Panel("Panel", viewport, "Hud");
    }
    // Parse the authored panel tree, including unnamed wrappers. A flat map of
    // IDs misses the engine ContextPanel versus XML root visibility regression.
    const stack = [];
    let authoredRoot;
    let markup = (options.hud ? fs.readFileSync("panorama/src/layout/custom_game/survival_hud.xml", "utf8")
        : options.nativeLoading ? loadingXml : xml).replace(/<!--[\s\S]*?-->/g, "");
    if (options.omitPartyButton) markup = markup.replace(/<Button id="StartupPartyStart"[\s\S]*?<\/Button>/, "");
    if (options.omitRetryButton) markup = markup.replace(/<Button id="StartupLoadingRetry"[\s\S]*?<\/Button>/, "");
    for (const match of markup.matchAll(/<\/?(Panel|Image|Label|Button)\b[^>]*>/g)) {
        const tag = match[0];
        if (tag.startsWith("</")) { assert(stack.length); stack.pop(); continue; }
        const attributes = {};
        for (const attribute of tag.matchAll(/([\w-]+)="([^"]*)"/g)) attributes[attribute[1]] = attribute[2];
        const panel = new Panel(match[1], stack.at(-1) || wrapper || viewport, attributes.id || "");
        if (!authoredRoot) authoredRoot = panel;
        (attributes.class || "").split(/\s+/).filter(Boolean).forEach(value => panel.AddClass(value));
        if (attributes.visible !== undefined) panel.visible = attributes.visible !== "false";
        if (attributes.text !== undefined) panel.text = attributes.text;
        if (!tag.endsWith("/>")) stack.push(panel);
    }
    assert(authoredRoot && stack.length === 0, "authored XML panel tree must balance");
    const root = wrapper || authoredRoot;
    if (!options.hud) {
        assert.equal(nodes.StartupLoadingBackground.GetParent(), nodes.StartupLoadingSurface);
        assert.equal(nodes.StartupLoadingSurface.GetParent(), authoredRoot);
    }
    const initialVisibilityWriteCount = visibilityWrites.length;
    function $(id) { return nodes[id.slice(1)]; }
    $.GetContextPanel = () => root;
    $.Msg = text => messages.push(text);
    $.CreatePanel = (type, parent, id) => new Panel(type, parent, id);
    $.Schedule = (delay, fn) => scheduled.push({at: now + delay, fn});
    $.CancelScheduled = () => {};
    $.RegisterEventHandler = (name, panel, handler) => { handlers[name] = handler; };
    const env = {$};
    if (!options.noGameApis) {
        if (options.sharedConfig || options.loadSharedUI || options.hud) env.GameUI = {CustomUIConfig: () => config};
        env.Game = {
            GetLocalPlayerID: () => localId,
            GetLocalPlayerInfo: () => { nativePlayerInfoCalls.push("GetLocalPlayerInfo"); throw new Error("native player resource unavailable"); },
            GetPlayerInfo: () => { nativePlayerInfoCalls.push("GetPlayerInfo"); throw new Error("native player resource unavailable"); }
        };
        env.Game.GetGameTime = () => now;
        if (options.enginePhase !== undefined) {
            env.Game.GetState = () => options.enginePhase;
            env.DOTA_GameState = {DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP: 2, DOTA_GAMERULES_STATE_HERO_SELECTION: 3};
        }
        if (options.unavailableRules) {
            env.DOTA_GameState = {DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP: 2, DOTA_GAMERULES_STATE_HERO_SELECTION: 3};
            for (const name of ["GetState", "GameStateIsAfter"]) {
                env.Game[name] = () => { nativeRuleCalls.push(name); throw new Error("client GameRules unavailable"); };
            }
            if (options.legacyRulesApi) delete env.Game.GetState;
        }
        env.Entities = {IsValidEntity: () => false};
        env.Players = {GetSelectedEntities: () => [], GetLocalPlayerPortraitUnit: () => -1};
        env.GameEvents = {SendCustomGameEventToServer: (name, payload) => requests.push({name, payload}),
            Subscribe: (name, fn) => { eventHandlers[name] = fn; return name; },
            Unsubscribe: name => { delete eventHandlers[name]; }};
        env.CustomNetTables = {
            GetTableValue: name => name === (options.hud ? "survival_ui_state" : "survival_loading") ? state
                : options.hud && name === "survival_loading" ? startupState : undefined,
            SubscribeNetTableListener: (name, callback) => { subscriptions.push((table, key, value) => { if (table === name) callback(table, key, value); }); return subscriptions.length; },
            UnsubscribeNetTableListener: id => { subscriptions[id - 1] = null; }
        };
    }
    const context = vm.createContext(env);
    if (options.loadSharedUI) for (const file of ["common/ui_registry.js", "common/ui_components.js", "ui_layers.js"]) {
        vm.runInContext(fs.readFileSync("panorama/src/scripts/custom_game/" + file, "utf8"), context);
    }
    vm.runInContext(options.hud ? fs.readFileSync("panorama/src/scripts/custom_game/survival_ui.js", "utf8") : script, context);
    return {
        nodes, root, authoredRoot, requests, messages, config, nativeRuleCalls, nativePlayerInfoCalls,
        emit: (name, payload) => { if (eventHandlers[name]) eventHandlers[name](payload); },
        visibilityWrites: () => visibilityWrites.slice(initialVisibilityWriteCount),
        imageLoaded: () => handlers.ImageLoaded(),
        imageFailed: () => handlers.ImageFailedLoad(),
        setLocalId: id => { localId = id; },
        setState: value => { state = value; subscriptions.forEach(cb => cb && cb(options.hud ? "survival_ui_state" : "survival_loading", options.hud ? "player_" + localId : "state", value)); },
        setStartup: value => { startupState = value; subscriptions.forEach(cb => cb && cb("survival_loading", "state", value)); },
        retry: () => nodes.StartupLoadingRetry.events.onactivate(),
        advance(seconds) {
            const end = now + seconds;
            while (true) {
                scheduled.sort((a, b) => a.at - b.at);
                if (!scheduled.length || scheduled[0].at > end) break;
                const job = scheduled.shift(); now = job.at; job.fn();
            }
            now = end;
        }
    };
}

function loading(overrides = {}) {
    return {session_id: "match-123", started: true, phase: "loading", progress: 37,
        assets: {total: 10, ready: 4, failed: 0, progress: 40, complete: false},
        players: [{player_id: 0, authenticated: false, client_ready: false, ready: false, status: "authenticating"}],
        all_ready: false, ...overrides};
}
function readyPlayer(id) { return {player_id: id, authenticated: true, client_ready: true, ready: true, status: "ready"}; }
function ready(overrides = {}) { return loading({phase: "ready", progress: 100, all_ready: true,
    assets: {total: 10, ready: 10, failed: 0, progress: 100, complete: true}, players: [readyPlayer(0)], ...overrides}); }
// LAN may replicate loading state before native PlayerResource. A caught JS
// exception is not protection against the native null dereference, so count
// every attempted call, even ones hidden by try/catch.
for (const nativeLoading of [false, true]) {
    const ui = harness({nativeLoading, engineWrapper: true, localId: -1});
    ui.imageLoaded(); ui.advance(1);
    ui.setState(loading({players: [readyPlayer(0), {...readyPlayer(1), client_ready: false, ready: false}]}));
    ui.advance(1);
    assert.equal(ui.requests.length, 0, "unknown identity cannot acknowledge loading");
    ui.setLocalId(1); ui.advance(0.5);
    assert.equal(ui.requests.at(-1).name, "survival_loading_client_ready");
    assert.equal(ui.nodes.StartupLoadingPlayers.children[1].children[1].text, "玩家 2（你）");
    ui.setState(ready({players: [readyPlayer(0), readyPlayer(1)], admission_complete: true}));
    assertHidden(ui, "native player queries are unnecessary for admission");
    assert.deepEqual(ui.nativePlayerInfoCalls, [], "loading must never enter native player-info functions");
}
// A stale compiled/content layout on a joining PC must not abort initialization
// before it subscribes to the current server and acknowledges the actual image.
for (const nativeLoading of [false, true]) {
    for (const omitRetryButton of [false, true]) {
        const ui = harness({omitPartyButton: true, omitRetryButton, nativeLoading, engineWrapper: true,
            state: loading({phase: "party_waiting", selector_player_id: 0})});
        assertShown(ui, "legacy layout remains visible instead of aborting on null SetPanelEvent");
        assert(ui.nodes.StartupPartyStart && ui.nodes.StartupPartyStartText && ui.nodes.StartupLoadingRetry);
        assert.equal(ui.nodes.StartupPartyStart.enabled, true);
        ui.nodes.StartupPartyStart.events.onactivate();
        assert.equal(ui.requests.at(-1).name, "survival_party_start");
        ui.imageLoaded();
        assert.equal(ui.requests.at(-1).name, "survival_loading_client_ready");
        ui.setState(loading({phase: "party_waiting", selector_player_id: 1}));
        const sent = ui.requests.length;
        ui.nodes.StartupPartyStart.events.onactivate();
        assert.equal(ui.requests.length, sent, "compatibility controls must preserve host authority");
        ui.setState(ready({admission_complete: true}));
        assertHidden(ui, "legacy layout still obeys server admission");
    }
}
// Remote loading starts before the native client GameRules object exists.
// Count unsafe native calls even if application code catches the JS fixture
// exception: a real C++ access violation cannot be caught by JS try/catch.
for (const legacyRulesApi of [false, true]) {
    const config = {};
    const ui = harness({unavailableRules: true, legacyRulesApi, engineWrapper: true, sharedConfig: config});
    ui.imageLoaded(); ui.advance(25);
    assertShown(ui, "remote loading without a snapshot must remain pending");
    assert.equal(ui.requests.length, 0);
    ui.setState(loading()); ui.advance(1);
    ui.setState(ready({admission_complete: true}));
    assertHidden(ui, "server admission retires loading without native state calls");
    const next = harness({unavailableRules: true, legacyRulesApi, engineWrapper: true, sharedConfig: config});
    next.imageLoaded(); next.advance(25);
    assertHidden(next, "admitted phase retains no-flash presentation through missing snapshot");
    next.setState(loading({session_id: "remote-next-match", phase: "error", error: "backend_authentication_failed", admission_complete: false}));
    assertShown(next, "a new rejected session is not hidden by previous admission");
    ui.root.valid = false; ui.advance(1);
    assert.deepEqual(ui.nativeRuleCalls, []);
    assert.deepEqual(next.nativeRuleCalls, []);
}
{
    const ui = harness({state: loading(), enginePhase: 4});
    assertShown(ui, "engine phase alone cannot hide pending server admission");
}
// Deliberately do not implement CSS class selectors: an engine-owned wrapper
// can carry StartupLoadingHidden without being in the layout stylesheet scope.
function panelVisible(panel) { return panel.visible !== false && panel.style.visibility !== "collapse"; }
function visible(ui) { return panelVisible(ui.root) && panelVisible(ui.authoredRoot) && panelVisible(ui.nodes.StartupLoadingSurface); }
function assertHidden(ui, message) {
    for (const panel of new Set([ui.root, ui.authoredRoot, ui.nodes.StartupLoadingSurface])) {
        assert.equal(panel.visible, false, message + ": explicit panel visibility");
        assert.equal(panel.style.visibility, "collapse", message + ": explicit panel style");
    }
}
function assertShown(ui, message) {
    for (const panel of new Set([ui.root, ui.authoredRoot, ui.nodes.StartupLoadingSurface])) {
        assert.equal(panel.visible, true, message + ": explicit panel visibility");
        assert.equal(panel.style.visibility, "visible", message + ": explicit panel style");
    }
}
function noVisibleWrite(ui, offset, message) {
    const tracked = new Set([ui.root, ui.authoredRoot, ui.nodes.StartupLoadingSurface]);
    assert(!ui.visibilityWrites().slice(offset).some(write => tracked.has(write.panel)
        && (write.property === "visible" && write.value === true
            || write.property === "visibility" && write.value === "visible")), message);
}

{
    const ui = harness({state: loading({phase: "error", error: "backend_authentication_failed"}), engineWrapper: true});
    ui.imageLoaded(); assert(visible(ui));
    ui.setState(ready({all_ready: false, phase: "waiting", players: [readyPlayer(0),
        {...readyPlayer(1), authenticated: false, ready: false, status: "authenticating"}]}));
    assert(visible(ui)); assert.equal(ui.nodes.StartupLoadingStatus.text, "等待其他玩家");
    ui.setState(ready({players: [readyPlayer(0), readyPlayer(1)]}));
    assertHidden(ui, "all ready hides both the engine wrapper and authored root");
    ui.root.SetHasClass("StartupLoadingHidden", false);
    assert(!visible(ui), "release does not rely on CSS scope or class matching");
    ui.setState(loading({session_id: "next-match"}));
    assertShown(ui, "new server session restores both loading panels");
    ui.setState(ready({players: [{...readyPlayer(0), authenticated: false}]}));
    assert(visible(ui), "explicit visibility cannot bypass failed player authentication");
}

{
    const ui = harness({state: loading(), nativeSetup: true});
    assert.equal(ui.nodes.TeamSelectContainer.visible, false, "native sibling cannot cover the loading screen or expose Start");
    assert.equal(ui.nodes.Hud.visible, true, "unrelated HUD is never globally hidden");
    assert.equal(ui.nodes.StartupLoadingBackground.style.opacity, "0");
    ui.imageLoaded(); ui.advance(1);
    assert.equal(ui.nodes.StartupLoadingBackground.style.opacity, "1", "real ImageLoaded directly reveals the image even across context wrappers");
    const layoutDiagnostics = () => ui.messages.filter(message => message.startsWith("[STARTUP_UI] "));
    assert.equal(layoutDiagnostics().length, 2, "only one layout and one image diagnostic per instance");
    const messageCount = ui.messages.length;
    ui.advance(20); assert.equal(ui.messages.length, messageCount, "no runtime diagnostic flood");
    assert(layoutDiagnostics().every(message => !message.includes("match-123")), "layout diagnostics do not log session or request payloads");
    ui.setState(ready());
    assert.equal(ui.nodes.TeamSelectContainer.visible, true, "native visibility restores when the overlay releases");
    assert.equal(ui.nodes.GameAndPlayersRoot.visible, false, "previously hidden native panels remain hidden");
}
{
    for (const [error, text] of Object.entries({
        backend_authentication_failed: "服务端认证失败，请检查测试连接后重试。",
        profile_load_failed: "玩家档案读取失败，请检查连接后重试。",
        profile_load_timeout: "玩家档案读取超时，请重试。"
    })) {
        const ui = harness({state: loading({phase: "error", error})}); ui.imageLoaded();
        assert.equal(ui.nodes.StartupLoadingError.text, text);
        assert(visible(ui));
    }
}
{
    const ui = harness(); ui.imageLoaded(); ui.advance(22);
    assert(visible(ui)); assert.equal(ui.nodes.StartupLoadingPercent.text, "0%");
    assert.equal(ui.requests.length, 0, "without a server session no readiness is sent");
    assert(!ui.nodes.StartupLoadingErrorBox.BHasClass("StartupLoadingHidden"));
}
{
    const ui = harness({noGameApis: true}); ui.imageLoaded(); ui.advance(25);
    assert(visible(ui), "native loading phase can run before game APIs become available");
    assert.equal(ui.requests.length, 0);
}
{
    const ui = harness({state: loading()}); ui.advance(10);
    assert.equal(ui.requests.length, 0, "background success must precede client-ready");
    assert.equal(ui.nodes.StartupLoadingPercent.text, "24%", "40% of genuine resource work contributes 24%; time adds nothing");
    ui.imageLoaded(); assert.equal(ui.requests.length, 1);
    assert.equal(ui.requests[0].name, "survival_loading_client_ready");
    assert.deepEqual(Object.keys(ui.requests[0].payload), ["session_id"]);
    assert.equal(ui.requests[0].payload.session_id, "match-123");
    ui.advance(1); assert.equal(ui.requests.length, 1, "no every-frame handshake flood");
    assert(visible(ui)); assert.equal(ui.nodes.StartupLoadingStatus.text, "加载中……");
}
// Every phase creates a fresh JS/layout instance. The server's client_ready is
// proof of the earlier phase's real image handshake, so decorative image loads
// in the later instance must never show another full-screen loading overlay.
for (const phase of ["LoadingScreen", "GameSetup", "HeroSelection", "PregameStrategy", "Hud"]) {
    const ui = harness({state: ready(), engineWrapper: true, nativeLoading: phase === "LoadingScreen"});
    assert.notEqual(ui.root, ui.authoredRoot, phase + ": model the real engine wrapper");
    assertHidden(ui, phase + " already-released instance before any image event");
    assert.equal(ui.nodes.StartupLoadingPercent.text, "100%", phase + ": acknowledged client work remains complete");
    noVisibleWrite(ui, 0, phase + ": fresh ready context must never briefly make either panel visible");
    ui.imageFailed(); ui.imageLoaded(); ui.advance(25);
    assertHidden(ui, phase + " remains released after image events and timeouts");
    noVisibleWrite(ui, 0, phase + ": image callbacks must not flash a released panel");
    assert.equal(ui.requests.length, 0, phase + ": no redundant readiness handshake");
}
{
    const ui = harness({state: loading(), engineWrapper: true});
    ui.imageLoaded();
    assert.equal(ui.nodes.StartupLoadingSurface.style.opacity, "1");
    assert(ui.nodes.StartupLoadingBackground.image.includes("server_loading_background"));
    ui.setState(ready({admission_complete: true}));
    assert.equal(ui.nodes.StartupLoadingSurface.style.opacity, "0");
    assert.equal(ui.nodes.StartupLoadingSurface.hittest, false);
    assert.equal(ui.nodes.StartupLoadingBackground.image, "", "release clears the actual image resource, not only wrapper visibility");
    assert.equal(ui.nodes.StartupLoadingBackground.style.opacity, "0");
    // Reproduce the engine reactivating a phase wrapper without calling JS:
    // the script-owned inner surface and emptied image still cannot paint.
    [ui.root, ui.authoredRoot].forEach(panel => {
        panel.visible = true; panel.style.visibility = "visible"; panel.style.opacity = "1";
    });
    assert(!visible(ui), "reactivated engine wrappers cannot expose the retired inner surface");
    ui.imageLoaded(); ui.imageFailed();
    assert.equal(ui.nodes.StartupLoadingBackground.image, "");
    assert.equal(ui.nodes.StartupLoadingBackground.style.opacity, "0", "late image callbacks cannot revive retired art");
    assert.equal(ui.nodes.StartupLoadingSurface.visible, false);
    ui.advance(20); assertHidden(ui, "polls keep retired content non-painting");
    const requestCount = ui.requests.length;
    ui.setState(loading({session_id: "next-with-fresh-image", admission_complete: false}));
    assertShown(ui, "a new valid match restores the owned render surface");
    assert(ui.nodes.StartupLoadingBackground.image.includes("server_loading_background"));
    assert.equal(ui.requests.length, requestCount, "new match waits for its fresh image callback");
    ui.imageLoaded();
    assert.equal(ui.requests.length, requestCount + 1);
    assert.equal(ui.nodes.StartupLoadingBackground.style.opacity, "1");
}
{
    const config = {};
    const setup = harness({state: loading(), engineWrapper: true, sharedConfig: config});
    setup.imageLoaded(); setup.setState(ready());
    assertHidden(setup, "previous phase released");
    assert.equal(config.SurvivalStartupCompletion.session_id, "match-123");
    assert.equal(config.SurvivalStartupCompletion.player_id, 0);
    const hud = harness({state: ready(), localId: -1, engineWrapper: true, sharedConfig: config});
    assertHidden(hud, "fresh HUD can use matching phase completion while player ID is temporarily unavailable");
    noVisibleWrite(hud, 0, "matching cached phase completion must suppress even the first HUD frame");
    hud.imageFailed(); hud.advance(25); hud.setLocalId(0); hud.advance(0.5);
    assertHidden(hud, "same player identity confirms cached completion");
    noVisibleWrite(hud, 0, "image timeout and later player ID must not reopen cached completion");

    const outsider = harness({state: ready(), localId: 2, engineWrapper: true, sharedConfig: config});
    assertShown(outsider, "another player cannot inherit shared phase completion");
    assert.equal(outsider.nodes.StartupLoadingStatus.text, "本局已开始");
    const noState = harness({localId: 0, engineWrapper: true, nativeSetup: true, sharedConfig: config});
    assertHidden(noState, "matching prior phase waits briefly for the first snapshot without a flash");
    assert.equal(noState.nodes.StartupLoadingPercent.text, "0%", "presentation grace cannot restore cached readiness or progress");
    assert.equal(noState.nodes.TeamSelectContainer.visible, false,
        "hidden presentation grace must still block native setup controls");
    noState.imageLoaded(); noState.retry(); noState.advance(0.99);
    assertHidden(noState, "snapshot grace lasts less than one second");
    assert.equal(noState.requests.length, 0, "no known session means no handshake or retry, even with a completion memo");
    assert.equal(noState.nodes.TeamSelectContainer.visible, false);
    noVisibleWrite(noState, 0, "the first-snapshot grace must not briefly reopen either panel");
    noState.advance(0.01);
    assertShown(noState, "missing snapshot after one second restores a fail-closed loading screen");
    assert.equal(noState.nodes.TeamSelectContainer.visible, false);
    assert.equal(noState.requests.length, 0);

    const timely = harness({localId: -1, engineWrapper: true, nativeSetup: true, sharedConfig: config});
    assertHidden(timely, "a temporary player-ID gap also permits bounded snapshot grace");
    timely.advance(0.5); timely.setState(ready()); timely.advance(2);
    assertHidden(timely, "matching ready snapshot replaces grace with real released state");
    timely.setLocalId(0); timely.advance(0.5);
    noVisibleWrite(timely, 0, "same-session snapshot received during grace never flashes an overlay");
    assert.equal(timely.requests.length, 0, "already-acknowledged phase must not send a new handshake");
    assert.equal(timely.nodes.TeamSelectContainer.visible, true,
        "native setup restores only after actual session readiness is known");

    const rejected = harness({localId: 0, engineWrapper: true, nativeSetup: true, sharedConfig: config});
    assertHidden(rejected, "initial grace before identifying the new session");
    rejected.advance(0.25);
    rejected.setState(loading({session_id: "new-session-during-grace", phase: "error", error: "backend_authentication_failed"}));
    assertShown(rejected, "a new-session failure ends grace immediately, before one second");
    assert.equal(rejected.nodes.StartupLoadingError.text, "服务端认证失败，请检查测试连接后重试。");
    assert.equal(rejected.nodes.TeamSelectContainer.visible, false);
    assert.equal(rejected.requests.length, 0, "new session must not inherit the previous image acknowledgement");

    for (const options of [{localId: 2, sharedConfig: config}, {localId: 0, sharedConfig: {}}, {localId: 0}]) {
        const untrusted = harness({...options, engineWrapper: true, nativeSetup: true});
        assertShown(untrusted, "different player or missing completion memo cannot defer loading");
        assert.equal(untrusted.nodes.TeamSelectContainer.visible, false);
        assert.equal(untrusted.requests.length, 0);
    }
    const next = harness({state: loading({session_id: "next-match-auth", phase: "error",
        error: "backend_authentication_failed"}), localId: 0, engineWrapper: true, sharedConfig: config});
    assertShown(next, "new session cannot reuse shared completion");
    next.imageLoaded(); next.advance(20);
    assertShown(next, "new-session auth failure remains blocked despite old cache and loaded background");
    assert.equal(next.nodes.StartupLoadingError.text, "服务端认证失败，请检查测试连接后重试。");
}
{
    const unacknowledged = ready({all_ready: false, phase: "loading",
        players: [{...readyPlayer(0), client_ready: false, ready: false, status: "client_loading"}]});
    const ui = harness({state: unacknowledged, engineWrapper: true});
    ui.imageFailed(); ui.advance(16);
    assertShown(ui, "first unacknowledged image failure stays blocked");
    assert.equal(ui.nodes.StartupLoadingPercent.text, "80%", "unacknowledged UI contributes no client completion");
    assert.equal(ui.requests.length, 0, "failed image must not acknowledge readiness");
    ui.retry(); assert.equal(ui.requests[0].name, "survival_loading_retry");
    assert.equal(ui.requests[0].payload.session_id, "match-123");
    ui.imageLoaded();
    assert.equal(ui.requests.at(-1).name, "survival_loading_client_ready");
    assertShown(ui, "ImageLoaded alone cannot assert server acknowledgement");
    assert.equal(ui.nodes.StartupLoadingPercent.text, "80%");
    ui.setState(ready());
    assertHidden(ui, "current-session server acknowledgement completes the first UI");
}
{
    const ui = harness({state: loading()}); ui.imageFailed(); ui.advance(30);
    assert(visible(ui)); assert.equal(ui.requests.length, 0);
    assert.equal(ui.nodes.StartupLoadingDetail.text, "加载画面尚未准备完成");
    assert.equal(ui.nodes.StartupLoadingPercent.text, "24%");
}
{
    const ui = harness({state: ready({all_ready: false, phase: "waiting", progress: 80, players: [readyPlayer(0),
        {player_id: 1, authenticated: false, client_ready: false, ready: false, status: "authenticating"}]})});
    ui.imageLoaded(); assert(visible(ui));
    assert.equal(ui.nodes.StartupLoadingStatus.text, "等待其他玩家");
    assert.equal(ui.nodes.StartupLoadingPercent.text, "100%", "other players cannot hold personal completion below 100%");
    assert.equal(ui.nodes.StartupLoadingReadyCount.text, "1 / 2 已就绪");
    ui.setState(ready({players: [readyPlayer(0), readyPlayer(1)]})); assert(!visible(ui));
    ui.setState(loading({session_id: "new-session"})); assert(visible(ui));
    ui.imageLoaded(); // Retired artwork is genuinely reloaded for a new match.
    assert.equal(ui.requests.at(-1).payload.session_id, "new-session");
}
{
    const ui = harness({state: ready({players: [{...readyPlayer(0), authenticated: false}]})});
    ui.imageLoaded(); assert(visible(ui), "malformed all-ready cannot bypass authentication");
    ui.setState(ready({assets: {complete: true, failed: 1}})); assert(visible(ui));
    ui.setState(ready({players: [{...readyPlayer(0), status: "disconnected"}]})); assert(visible(ui));
    ui.setState(ready({error: "private-internal-database-detail"})); assert(visible(ui));
    assert(!ui.nodes.StartupLoadingError.text.includes("private"), "never display raw internal errors");
}
{
    const ui = harness({state: loading(), localId: -1}); ui.imageLoaded();
    assert.equal(ui.requests.length, 0);
    ui.setLocalId(0); ui.advance(0.5);
    assert.equal(ui.requests.length, 1, "handshake waits for the local player ID without querying native player info");
    assert.deepEqual(ui.nativePlayerInfoCalls, []);
}
{
    const ui = harness({state: loading({players: [{...readyPlayer(0),
        player_name: '<font color="red">untrusted</font>\nname'}]})});
    const name = ui.nodes.StartupLoadingPlayers.children[0].children[1];
    assert.equal(name.html, false, "nicknames are plain text labels");
    assert(!name.text.includes("\n"));
    assert(name.text.includes("untrusted"), "display name comes from the server roster");
    assert.deepEqual(ui.nativePlayerInfoCalls, []);
    ui.setState(loading({players: {"0": readyPlayer(0), "1": readyPlayer(1)}, progress: NaN, assets: {progress: NaN}}));
    assert.equal(ui.nodes.StartupLoadingPlayers.children.length, 2, "KV object roster is accepted");
    assert.equal(ui.nodes.StartupLoadingPercent.text, "40%", "invalid resource percentage contributes zero; server authentication and client acknowledgement each contribute 20");
}
{
    const ui = harness({state: loading({assets: {progress: 50, complete: false, failed: 0},
        players: [{...readyPlayer(0), ready: false, client_ready: false}]})});
    assert.equal(ui.nodes.StartupLoadingPercent.text, "50%", "resources 30 plus authenticated 20");
    ui.imageLoaded();
    assert.equal(ui.nodes.StartupLoadingPercent.text, "50%", "wait for actual current-session UI handshake acknowledgement");
    ui.setState(loading({assets: {progress: 50, complete: false, failed: 0},
        players: [{...readyPlayer(0), ready: false}]}));
    assert.equal(ui.nodes.StartupLoadingPercent.text, "70%", "resources 30 plus authentication 20 plus image/UI 20");
    ui.setLocalId(-1); ui.advance(0.5);
    assert.equal(ui.nodes.StartupLoadingPercent.text, "30%", "without a local player identity progress cannot claim 100%");
}
{
    const ui = harness({state: loading()}); ui.imageLoaded(); ui.root.valid = false; ui.advance(30);
    assert.equal(ui.requests.length, 1, "deleted phase UI stops sending handshakes");
}
{
    const ui = harness({state: ready(), localId: 2}); ui.imageLoaded(); ui.advance(25);
    assert(visible(ui), "a newly joined player outside the frozen roster cannot enter a running match");
    assert.equal(ui.nodes.StartupLoadingStatus.text, "本局已开始");
    assert.equal(ui.nodes.StartupLoadingError.text, "本局已开始，请重新加入下一局。");
    assert(ui.nodes.StartupLoadingRetry.BHasClass("StartupLoadingHidden"));
    ui.retry(); assert.equal(ui.requests.length, 0, "late-join terminal state cannot issue futile retries");
    ui.setLocalId(0); ui.advance(0.5);
    assert(!visible(ui), "reconnecting original roster member is admitted by server readiness");
}
{
    const ui = harness({state: loading(), engineWrapper: true});
    ui.imageLoaded(); ui.setState(ready());
    assertHidden(ui, "initial release");
    const offset = ui.visibilityWrites().length;
    ui.imageFailed(); ui.setState(undefined); ui.advance(0.5);
    ui.setState(null); ui.setState({}); ui.setState({session_id: 123});
    ui.setLocalId(-1); ui.advance(0.5); ui.setState(ready());
    ui.advance(25); ui.imageLoaded();
    assertHidden(ui, "released session tolerates image/nettable/player-ID transients");
    noVisibleWrite(ui, offset, "no intermediate render may reopen a released same-session panel");
    ui.setLocalId(0); ui.advance(0.5); assertHidden(ui, "original identity recovers");
    ui.setLocalId(2); ui.advance(0.5);
    assertShown(ui, "another local player cannot inherit the completed player's latch");
    assert.equal(ui.nodes.StartupLoadingStatus.text, "本局已开始");
    ui.setLocalId(0); ui.advance(0.5); assertHidden(ui, "original player still has its server-ready proof");
    ui.setState(loading({session_id: "new-auth-session", phase: "error", error: "backend_authentication_failed"}));
    assertShown(ui, "new session revokes previous readiness");
    assert.equal(ui.nodes.StartupLoadingError.text, "服务端认证失败，请检查测试连接后重试。");
    ui.imageLoaded(); ui.advance(25);
    assertShown(ui, "new-session authentication failure is never bypassed by the old completion latch");
}
{
    const ui = harness({state: loading({phase: "error", error: "asset_reload_required"})});
    ui.imageLoaded(); ui.advance(20);
    assert(visible(ui));
    assert.equal(ui.nodes.StartupLoadingStatus.text, "需要重新载入地图");
    assert.equal(ui.nodes.StartupLoadingError.text, "部分初始资源加载失败，请重新启动测试地图。");
    assert(ui.nodes.StartupLoadingRetry.BHasClass("StartupLoadingHidden"));
    assert.equal(ui.nodes.StartupLoadingRetry.enabled, false);
    ui.retry(); assert.equal(ui.requests.length, 0, "initial asset failure is not an endless retry loop");
    ui.setState(loading({session_id: "reloaded-session"}));
    assert(!ui.nodes.StartupLoadingRetry.BHasClass("StartupLoadingHidden"));
    assert.equal(ui.nodes.StartupLoadingStatus.text, "加载中……");
    assert.equal(ui.requests.at(-1).payload.session_id, "reloaded-session");
}
const manifest = fs.readFileSync("panorama/src/layout/custom_game/custom_ui_manifest.xml", "utf8");
for (const type of ["GameSetup", "HeroSelection", "PregameStrategy", "Hud"]) {
    assert(manifest.includes('type="' + type + '" layoutfile="file://{resources}/layout/custom_game/startup_loading.xml"'));
}
// The fixed engine entrypoint deliberately shares the exact layout, script and
// style with the manifest entrypoint. This avoids relying on Panel.layoutfile
// inclusion support during the native map-loading phase.
assert.equal(loadingXml, xml);
for (const [name, source] of [["startup_loading", xml], ["custom_loading_screen", loadingXml]]) {
    const authoredTag = source.match(/<Panel\b[^>]*>/)[0];
    assert(/\bvisible="false"/.test(authoredTag) && /\bStartupLoadingHidden\b/.test(authoredTag),
        name + ": XML must start hidden before its first JS render");
}
{
    const ui = harness({state: loading(), engineWrapper: true});
    const percent = ui.nodes.StartupLoadingPercent;
    const fill = ui.nodes.StartupLoadingProgressFill;
    function ancestorWithClass(panel, name) {
        for (let current = panel.GetParent(); current; current = current.GetParent()) {
            if (current.BHasClass(name)) return current;
        }
        return null;
    }
    const track = ancestorWithClass(percent, "StartupLoadingProgressTrack");
    assert(track, "progress number must be inside the progress track");
    assert.equal(ancestorWithClass(fill, "StartupLoadingProgressTrack"), track);
    assert.equal(ancestorWithClass(percent, "StartupLoadingProgressFill"), null,
        "number must not shrink or clip with fill width");
    assertShown(ui, "initial hidden XML explicitly opens for real pending work");
}
console.log("STARTUP_LOADING_UI_PASS: five fresh phases, nested wrapper visibility, bounded snapshot grace, no post-release flashes, session/player isolation, genuine image handshake, auth/resource gates, authoritative progress and in-track percentage");
module.exports = {harness, loading, ready, visible, assertHidden, assertShown};

{
    const state = loading({phase: "party_waiting", selector_player_id: 0,
        players: [{player_id: 0, status: "party_waiting"}, {player_id: 1, status: "party_waiting"}]});
    const host = harness({state}), guest = harness({state, localId: 1});
    assert.equal(host.nodes.StartupPartyStart.enabled, true);
    assert.equal(guest.nodes.StartupPartyStart.enabled, false);
    assert.equal(host.nodes.StartupLoadingPercent.text, "0%");
    assert.equal(host.nodes.StartupLoadingReadyCount.text, "2 人已加入");
    host.nodes.StartupPartyStart.events.onactivate();
    guest.nodes.StartupPartyStart.events.onactivate();
    assert(host.requests.some(r => r.name === "survival_party_start"));
    assert(!guest.requests.some(r => r.name === "survival_party_start"));
    host.advance(90);
    assertShown(host, "party room never auto-starts on timeout");
    host.setState(loading());
    assert(host.nodes.StartupPartyStart.BHasClass("StartupLoadingHidden"));
    console.log("STARTUP_PARTY_UI_PASS");
}
