const fs = require('fs'), vm = require('vm'), assert = require('assert');
const path = require('path');
const repo = path.resolve(__dirname, '../..');
const base = (process.argv[2] || path.resolve(repo, '../../../content/dota_addons/Survival/panorama')) + path.sep;
const source = fs.readFileSync(base + 'scripts/custom_game/survival_lobby.js', 'utf8');
const xml = fs.readFileSync(base + 'layout/custom_game/survival_lobby.xml', 'utf8');
const css = fs.readFileSync(base + 'styles/custom_game/survival_lobby.css', 'utf8');
let checks = 0;
function check(condition, message) { assert.ok(condition, message); checks++; }
// Interpret the actual layout hierarchy, inline styles and matching CSS rules.
// A writable root.visible property alone cannot model native HUD hosting.
function declarations(value) {
    const result = {};
    for (const part of value.split(';')) {
        const colon = part.indexOf(':');
        if (colon >= 0) result[part.slice(0, colon).trim()] = part.slice(colon + 1).trim();
    }
    return result;
}
const cssRules = [...css.matchAll(/([^{}]+)\{([^{}]*)\}/g)].map(m => ({selectors: m[1].trim().split(','), style: declarations(m[2])}));
function matches(panel, selector) {
    selector = selector.trim();
    if (!selector || /[\s:>]/.test(selector)) return false;
    const parts = [...selector.matchAll(/([.#])([A-Za-z0-9_-]+)/g)];
    return parts.length > 0 && parts.map(m => m[0]).join('') === selector
        && parts.every(m => m[1] === '#' ? panel.id === m[2] : panel.classes[m[2]]);
}
function computedStyle(panel) {
    const value = {};
    for (const rule of cssRules) if (rule.selectors.some(s => matches(panel, s))) Object.assign(value, rule.style);
    return Object.assign(value, panel.style);
}
function visible(panel) {
    for (let item = panel; item; item = item.parent) {
        if (!item.valid || !item.visible || ['collapse', 'hidden'].includes(computedStyle(item).visibility)) return false;
    }
    return true;
}
function harness(mapInfo = {map_name: 'ws4_lobby'}, clock = 1, options = {}) {
    const ids = {}, sent = [], subscriptions = {}, subscriptionIds = new Map(), unsubscribed = [], scheduled = [], browser = [], localEvents = [];
    let serial = 0;
    class Panel {
        constructor(id, parent) {
            this.id = id; this.parent = parent || null; this.children = []; this.classes = {}; this.style = {};
            this.handlers = {}; this.text = ''; this.visible = true; this.enabled = true; this.valid = true;
            this.hittest = true; this.hittestchildren = true;
            if (parent) parent.children.push(this); if (id) ids[id] = this;
        }
        FindChildTraverse(id) {
            for (const child of this.children) {
                if (child.id === id) return child;
                const found = child.FindChildTraverse(id); if (found) return found;
            }
            return null;
        }
        AddClass(c) { this.classes[c] = true; }
        SetHasClass(c, b) { this.classes[c] = !!b; }
        RemoveAndDeleteChildren() { this.children = []; }
        SetPanelEvent(e, f) { this.handlers[e] = f; }
        IsValid() { return this.valid; }
    }
    let root;
    const stack = [];
    for (const tag of xml.matchAll(/<(\/?)(Panel|Label|Button|TextEntry)\b([^>]*?)(\/?)>/g)) {
        if (tag[1]) { stack.pop(); continue; }
        const attrs = Object.fromEntries([...tag[3].matchAll(/([A-Za-z_][\w-]*)="([^"]*)"/g)].map(m => [m[1], m[2]]));
        const item = new Panel(attrs.id || (root ? '' : 'root'), stack.at(-1));
        if (!root) root = item;
        for (const name of (attrs.class || '').split(/\s+/).filter(Boolean)) item.AddClass(name);
        for (const name of ['visible', 'enabled', 'hittest', 'hittestchildren']) if (attrs[name]) item[name] = attrs[name] === 'true';
        item.style = declarations(attrs.style || ''); item.text = attrs.text || '';
        if (!tag[4]) stack.push(item);
    }
    if (options.missing) ids[options.missing].valid = false;
    const context = {
        Game: {GetMapInfo() { if (mapInfo instanceof Error) throw mapInfo; return mapInfo; }, GetLocalPlayerID() { return 0; }, Time() { if (options.throwTime) throw Error('clock unavailable'); return clock; }},
        GameEvents: {
            SendCustomGameEventToServer(name, payload) { sent.push({name, payload}); },
            Subscribe(name, fn) {
                if (options.throwSubscribe) throw Error('events unavailable');
                const id = ++serial; subscriptions[name] = fn; subscriptionIds.set(id, {name, fn}); return id;
            },
            Unsubscribe(id) {
                unsubscribed.push(id); const item = subscriptionIds.get(id);
                if (item && subscriptions[item.name] === item.fn) delete subscriptions[item.name]; subscriptionIds.delete(id);
            },
            SendEventClientSide(name, payload) { localEvents.push({name, payload}); if (options.throwLocal) throw Error('native API unavailable'); }
        },
        $: {GetContextPanel() { return root; }, CreatePanel(type, parent, id) { return new Panel(id, parent); }, Schedule(seconds, fn) { scheduled.push({seconds, fn}); }, DispatchEvent(name, uri) { browser.push({name, uri}); }}
    };
    if (!options.skipScript) vm.runInNewContext(source, context, {filename: 'survival_lobby.js'});
    return {root, ids, sent, subscriptions, unsubscribed, scheduled, browser, localEvents, context,
        advance(n) { clock += n; }, setMap(value) { mapInfo = value; },
        monitor(count = 1) { for (let i = 0; i < count; i++) { const next = scheduled.shift(); assert.ok(next, 'monitor scheduled'); next.fn(); } },
        visible(id = 'SurvivalLobbyOverlay') { return visible(ids[id]); },
        receive(s) { subscriptions.survival_lobby_state(s); }, receiveAuth(s) { subscriptions.survival_player_web_auth_state(s); }, receiveConnect(s) { subscriptions.survival_lobby_connect(s); },
        click(id) { if (ids[id].handlers.onactivate) ids[id].handlers.onactivate(); },
        pointerClick(id) {
            const item = ids[id];
            if (!visible(item) || !item.enabled || !item.hittest) return false;
            for (let parent = item.parent; parent; parent = parent.parent) if (!parent.hittestchildren) return false;
            if (!item.handlers.onactivate) return false; item.handlers.onactivate(); return true;
        }
    };
}
const unstarted = harness(undefined, 1, {skipScript: true});
check(unstarted.ids.SurvivalLobbyOverlay.parent === unstarted.root, 'visual overlay is a distinct direct child of host context');
check(unstarted.ids.LobbyCard.parent === unstarted.ids.SurvivalLobbyOverlay && unstarted.root.children.length === 1, 'all lobby content is inside independently hidden overlay');
check(unstarted.ids.SurvivalLobbyOverlay.style.visibility === 'collapse', 'real XML defaults child to inline collapse before script');
check(cssRules.some(rule => rule.selectors.includes('.SurvivalLobbyRoot') && rule.style.visibility === 'collapse'), 'real CSS independently defaults visual child to collapse');
check(!computedStyle(unstarted.root)['background-color'] && !computedStyle(unstarted.root)['background-image'], 'host context has no painted background');
check(!unstarted.root.hittest && !unstarted.root.hittestchildren, 'real XML context cannot capture default input');
unstarted.root.visible = true;
check(!unstarted.visible() && !unstarted.pointerClick('LobbyRefresh'), 'native host forcing root visible cannot expose unexecuted lobby XML');
for (const info of [{map_name: 'template_map'}, {map_name: 'ws4_entry'}, {map_name: 'template_map', map_display_name: 'ws4_lobby'}, null, new Error('not mounted')]) {
    const h = harness(info);
    h.root.visible = true;
    check(!h.visible(), 'ordinary/unknown map stays collapsed even when native host forces context visible');
    check(!h.root.hittest && !h.root.hittestchildren && !h.pointerClick('LobbyRefresh'), 'ordinary map does not intercept HUD input');
    check(h.sent.length === 0, 'ordinary map sends no requests');
    check(Object.keys(h.subscriptions).length === 0, 'ordinary map has no subscriptions');
}
let h = harness();
check(h.visible() && !h.root.hittest && h.root.hittestchildren && h.ids.SurvivalLobbyOverlay.hittest, 'only verified lobby inner panel is visible and receives input');
check(h.sent.length === 1 && h.sent[0].payload.action === 'refresh', 'initial refresh only');
check(!h.ids.LobbyStart.enabled && !h.ids.LobbyCreate.enabled, 'unknown service actions disabled');
check(h.ids.LobbyPlayers.children.length === 4, 'four empty slots');
const baseState = {ok: true, authenticated: true, phase: 'open', room_id: '', revision: 1, capacity: 4, players: [], rooms: [], worker_available: true, self_is_host: false, self_ready: false};
h.receive({...baseState, authenticated: false});
check(!h.ids.LobbyCreate.enabled, 'unauthenticated creation disabled');
h.advance(1); h.click('LobbyCreate');
check(h.sent.length === 1, 'unauthenticated click sends nothing');
h.receive({...baseState, worker_available: false});
check(h.ids.LobbyStatusTitle.text === '暂无可用服务器', 'no worker clearly unavailable');
check(!h.ids.LobbyStart.enabled, 'no worker cannot start');
h.receive({...baseState, rooms: [{id: 'room-A', name: '<b>Room</b>', count: 2, capacity: 4}, {id: 'bad;exec', name: 'bad', count: 0}]});
check(h.ids.LobbyCreate.enabled, 'authenticated service permits room creation');
check(h.ids.LobbyRoomList.children.length === 1, 'invalid remote id ignored');
check(h.ids.LobbyRoomList.children[0].children[0].html === false, 'room labels plain text');
check(!h.ids.LobbyRoomList.children[0].handlers.onactivate, 'own room list cannot join by room ID');
const inviteCode = 'AbcdEF12_34-xyZa';
h.advance(1); h.ids.LobbyInviteInput.text = ' ' + inviteCode + ' '; h.click('LobbyJoin');
check(h.sent.at(-1).payload.action === 'join' && h.sent.at(-1).payload.invite_code === inviteCode, 'join sends case-sensitive invite code');
check(Object.keys(h.sent.at(-1).payload).sort().join(',') === 'action,invite_code', 'join sends no room ID, revision, or identity');
check(h.ids.LobbyInviteInput.text === '', 'submitted invite input cleared');
h.receive({...baseState}); h.advance(1); h.ids.LobbyInviteInput.text = 'room-B;connect evil'; h.click('LobbyJoin');
check(h.sent.at(-1).payload.invite_code === inviteCode, 'invalid invite never sent');
check(h.ids.LobbyStatusDetail.text === '请输入房主发送的有效邀请码。', 'invalid invite explained');
const ready = [{name: 'Host', ready: true, is_host: true}, {name: 'Peer', ready: true, is_host: false}];
h.receive({...baseState, room_id: 'room-A', revision: 2, players: ready, self_is_host: false, self_ready: true});
check(!h.ids.LobbyStart.enabled, 'peer cannot start even everyone ready');
check(h.ids.LobbyReadyText.text === '取消准备', 'server self ready controls label');
h.receive({...baseState, room_id: 'room-A', revision: 3, players: ready, self_is_host: true, self_ready: true, worker_available: false});
check(!h.ids.LobbyStart.enabled, 'host cannot start without worker');
h.receive({...baseState, room_id: 'room-A', revision: 4, players: [ready[0], {...ready[1], ready: false}], self_is_host: true});
check(!h.ids.LobbyStart.enabled, 'host waits for every player');
h.receive({...baseState, room_id: 'room-A', revision: 5, players: [], self_is_host: true});
check(!h.ids.LobbyStart.enabled, 'empty room never starts');
h.receive({...baseState, room_id: 'room-A', revision: 6, players: ready, self_is_host: true, self_ready: true});
check(h.ids.LobbyStart.enabled, 'authenticated host with ready players and worker may start');
h.advance(1); h.click('LobbyStart');
check(h.sent.at(-1).payload.action === 'start' && h.sent.at(-1).payload.revision === 6, 'start sends current revision');
check(!h.ids.LobbyStart.enabled, 'action locked until response');
h.receive({...baseState, room_id: 'room-A', revision: 5, players: ready, self_is_host: false});
check(h.ids.LobbyReadyText.text === '取消准备', 'stale same-room revision ignored');
h.receive({...baseState, room_id: 'room-A', revision: 7, phase: 'started', players: ready, self_is_host: true});
check(h.ids.LobbyReconnect.enabled && !h.ids.LobbyStart.enabled && !h.ids.LobbyReady.enabled, 'started room offers reconnect only');
h.advance(1); h.click('LobbyReconnect');
check(h.sent.at(-1).payload.action === 'reconnect', 'reconnect delegates to server');
check(!source.includes('SendToConsole') && !source.includes('connect.command') && !source.includes('ticket'), 'UI has no console or ticket plumbing');
h.receive({...baseState, room_id: 'room-A', revision: 8, players: {1: ready[0], 2: ready[1]}, self_is_host: true, self_ready: true});
check(h.ids.LobbyPlayers.children[1].children[1].text === 'Peer', 'Lua numeric object player list supported');
h.advance(17); h.monitor(10);
check(!h.ids.LobbyStart.enabled, 'stale service state cannot start');
check(h.ids.LobbyStatusTitle.text === '大厅服务暂不可用', 'stale service visibly unavailable');
h.receive({...baseState, error: 'SECRET_BEARER_TOKEN', ticket: 'SECRET_TICKET', connect: {command: 'SECRET_CONNECT'}});
check(h.ids.LobbyStatusDetail.text === '操作未完成，请刷新后重试。', 'unknown error not echoed');
h.receive({...baseState, error: '__proto__'});
check(h.ids.LobbyStatusDetail.text === '操作未完成，请刷新后重试。', 'prototype names never accepted as error labels');
h = harness({map_display_name: 'ws4_lobby'}, -30);
check(h.sent.length === 1, 'negative entry clock still sends initial refresh');
check(xml.includes('本局不保存') && xml.includes('云商店不可用') && xml.includes('最多 4 人'), 'trial limits visible');
check((xml.match(/id="LobbyStart"/g) || []).length === 1, 'single start control');
h.receive({...baseState, phase: 'UNKNOWN_NEW_PHASE', room_id: 'room-A', players: ready, self_is_host: true});
check(!h.ids.LobbyStart.enabled && !h.ids.LobbyReady.enabled, 'unknown phase disables mutation');
check(h.ids.LobbyStatusTitle.text === '大厅服务暂不可用', 'unknown phase is unavailable');
for (const phase of ['starting', 'allocated']) {
    h.receive({...baseState, phase, room_id: 'room-A', revision: 2, players: ready, self_is_host: true});
    check(!h.ids.LobbyReconnect.enabled, 'allocation is not a reconnect destination');
    check(!h.ids.LobbyReconnect.classes.ReconnectAvailable, 'allocation never claims a server is ready');
}
h = harness();
h.receive({...baseState, room_id: 'room-A', revision: 1, players: ready, self_is_host: false, invite_code: inviteCode});
check(!h.ids.LobbyInvite.enabled && !h.ids.LobbyInviteBar.visible, 'non-host cannot request or view invite');
check(h.ids.LobbyInviteCode.text !== inviteCode, 'other player invite is not rendered');
h.receive({...baseState, room_id: 'room-A', revision: 2, players: ready, self_is_host: true, worker_available: false});
check(h.ids.LobbyInvite.enabled && h.ids.LobbyInviteBar.visible, 'host may invite before worker available');
h.advance(1); h.click('LobbyInvite');
check(h.sent.at(-1).payload.action === 'invite' && h.sent.at(-1).payload.revision === 2, 'invite uses room revision');
check(Object.keys(h.sent.at(-1).payload).sort().join(',') === 'action,revision,room_id', 'invite contains no extra identity or credential');
h.receive({...baseState, room_id: 'room-A', revision: 2, players: ready, self_is_host: true, invite_code: inviteCode});
check(h.ids.LobbyInviteCode.text === inviteCode, 'host sees validated single-use invite');
h.advance(601);
h.receive({...baseState, room_id: 'room-A', revision: 2, players: ready, self_is_host: true, invite_code: inviteCode});
check(h.ids.LobbyInviteCode.text !== inviteCode, 'polling same invite does not extend ten-minute display');
h.receive({...baseState, room_id: 'room-A', revision: 3, players: ready, self_is_host: true, invite_code: 'Different_123456'});
check(h.ids.LobbyInviteCode.text === 'Different_123456', 'fresh code replaces expired invite');
h.receive({...baseState, room_id: 'room-A', revision: 4, players: ready, self_is_host: true, invite_code: ''});
check(h.ids.LobbyInviteCode.text !== 'Different_123456', 'server removal clears consumed invite');
h.receive({...baseState, room_id: 'room-A', revision: 5, phase: 'interrupted', players: ready, self_is_host: true});
check(!h.ids.LobbyStart.enabled && !h.ids.LobbyReady.enabled && !h.ids.LobbyReconnect.enabled && !h.ids.LobbyInvite.enabled, 'interrupted room has no battle mutation');
check(h.ids.LobbyLeave.enabled && h.ids.LobbyStatusTitle.text === '本局已中断', 'interrupted owner can close via leave');
h.receive({...baseState, room_id: 'room-A', revision: 6, phase: 'interrupted', players: ready, self_is_host: false});
check(!h.ids.LobbyLeave.enabled, 'non-owner cannot close interrupted room');
h.receive({...baseState, room_id: 'room-A', revision: 7, phase: 'closed', players: ready, self_is_host: true});
check(h.ids.LobbyCreate.enabled && !h.ids.LobbyStart.enabled, 'closed room permits fresh creation only');
check(h.ids.LobbyPlayers.children.every(row => row.children[1].text === '空位'), 'closed room no longer shows current members');

const userCode = 'ABCD-1234';
const authUri = 'https://pay.xiaofengnet.com/ws4-web/authorize?code=' + userCode;
const pending = {status: 'pending', player_id: 0, user_code: userCode, verification_uri: authUri, expires_in: 600};
h = harness(); h.receive({...baseState, authenticated: false});
check(h.ids.LobbyAuthPanel.visible && !h.ids.LobbyAuthOpen.enabled, 'auth shown while awaiting real code');
h.receiveAuth({...pending, player_id: 1});
check(!h.ids.LobbyAuthOpen.enabled, 'other player auth state ignored');
h.receiveAuth(pending);
check(h.ids.LobbyAuthOpen.enabled && h.ids.LobbyAuthCode.text === userCode, 'valid private code displayed');
h.click('LobbyAuthOpen');
check(h.browser.length === 1 && h.browser[0].name === 'ExternalBrowserGoToURL' && h.browser[0].uri === authUri, 'browser opens only fixed official authorization URI');
check(!h.ids.LobbyCreate.enabled, 'pending browser code does not authenticate lobby');
const attacks = [
    'http://pay.xiaofengnet.com/ws4-web/authorize?code=' + userCode,
    'https://pay.xiaofengnet.com.evil.test/ws4-web/authorize?code=' + userCode,
    authUri + '&device_code=SECRET_DEVICE',
    authUri + '#SECRET_FRAGMENT',
    'javascript:alert(1)',
    'https://pay.xiaofengnet.com/ws4-web/authorize?code=DIFFERENT',
    authUri + '\n',
    'https://pay.xiaofengnet.com/ws4-web/authorize?code=%41BCD-1234'
];
for (const uri of attacks) {
    h.receiveAuth({...pending, verification_uri: uri});
    const count = h.browser.length; h.click('LobbyAuthOpen');
    check(!h.ids.LobbyAuthOpen.enabled && h.ids.LobbyAuthCode.text === '', 'invalid authorization URI not rendered');
    check(h.browser.length === count, 'invalid URI cannot dispatch browser');
}
for (const code of ['lowercase', 'A'.repeat(17), 'A B C D', 'AAAA&token=X', 'ABCDEF\n', 'ABCDEF\r']) {
    h.receiveAuth({...pending, user_code: code, verification_uri: 'https://pay.xiaofengnet.com/ws4-web/authorize?code=' + code});
    check(!h.ids.LobbyAuthOpen.enabled, 'malformed user code disabled');
}
h.receiveAuth({...pending, status: 'approved', device_code: 'SECRET_DEVICE', token: 'SECRET_TOKEN'});
check(!h.ids.LobbyAuthOpen.enabled && h.ids.LobbyAuthCode.text === '', 'approved state clears code and browser action');
check(!h.ids.LobbyCreate.enabled, 'auth approved event alone cannot grant lobby access');
h.receive({...baseState, authenticated: true});
check(!h.ids.LobbyAuthPanel.visible && !h.ids.LobbyAuthOpen.enabled, 'server-confirmed lobby auth hides browser controls');
h.receive({...baseState, authenticated: false});
h.receiveAuth({...pending, user_code: 'EFGH-5678', verification_uri: 'https://pay.xiaofengnet.com/ws4-web/authorize?code=EFGH-5678', expires_in: 0});
check(!h.ids.LobbyAuthOpen.enabled && h.ids.LobbyAuthStatus.text.includes('过期'), 'expired code cannot launch browser');
h.receiveAuth({...pending, status: 'failed', diagnostic_revision: 'WS4-WEB-04', diagnostic_phase: 'start', diagnostic_stage: 'create', diagnostic_status: 0, error: 'SECRET_ERROR'});
check(h.ids.LobbyAuthStatus.text.includes('WS4-WEB-04 / start / create / 0'), 'allowlisted public diagnostic preserved');
check(!h.ids.LobbyAuthStatus.text.includes('SECRET_ERROR'), 'arbitrary auth error never displayed');
h.receiveAuth({...pending, status: 'failed', diagnostic_revision: 'WS4-WEB-04', diagnostic_phase: 'start', diagnostic_stage: 'SECRET_STAGE', diagnostic_status: 0});
check(!h.ids.LobbyAuthStatus.text.includes('SECRET_STAGE') && !h.ids.LobbyAuthStatus.text.includes('WS4-WEB-04'), 'unrecognized diagnostic omitted');
check(h.sent.every(event => event.payload.action !== 'refresh_auth'), 'UI never requests an auth retry or refresh_auth action');

const buildSha = 'a1'.repeat(32);
const connectFields = {address: '127.0.0.1:27015', match_id: 'match_test_1234', build_sha256: buildSha};
const allocatedState = {...baseState, room_id: 'room-A', phase: 'started', players: ready, self_is_host: true};
for (const phase of ['open', 'lobby', 'idle', 'ready', 'starting', 'allocated', 'connecting', 'interrupted', 'closed', 'UNKNOWN_PHASE']) {
    const test = harness(); test.receive({...allocatedState, phase}); test.receiveConnect(connectFields);
    check(test.localEvents.length === 0, 'non-started/running phase cannot dispatch a local connection');
}
h = harness(); h.receiveConnect(connectFields);
check(h.localEvents.length === 0, 'no server state cannot dispatch');
h.receive({...allocatedState, authenticated: false}); h.receiveConnect(connectFields);
check(h.localEvents.length === 0, 'unauthenticated state cannot dispatch');
h.receive({...allocatedState, room_id: ''}); h.receiveConnect(connectFields);
check(h.localEvents.length === 0, 'missing current room cannot dispatch');
h.receive(allocatedState); h.advance(17); h.receiveConnect(connectFields);
check(h.localEvents.length === 0, 'stale allocated state cannot dispatch');
h.receive(allocatedState); h.receiveConnect(connectFields);
check(h.localEvents.length === 1, 'fresh allocated state may dispatch after earlier refusals');
check(h.localEvents[0].name === 'survival_lobby_connect_local', 'only fixed local event is used');
check(Object.keys(h.localEvents[0].payload).sort().join(',') === 'address,build_sha256,match_id', 'local event contains exactly data fields');
check(h.localEvents[0].payload.address === connectFields.address && h.localEvents[0].payload.match_id === connectFields.match_id && h.localEvents[0].payload.build_sha256 === buildSha, 'validated values preserved without command construction');
h.receiveConnect(connectFields);
check(h.localEvents.length === 1, 'identical duplicate blocked');
h.receiveConnect({...connectFields, match_id: 'match_test_next'});
check(h.localEvents.length === 2, 'a different match may dispatch');
h.receiveConnect(connectFields);
check(h.localEvents.length === 2, 'an older match remains blocked after a newer event');
h.receiveConnect({...connectFields, address: '192.0.2.1:27015'});
check(h.localEvents.length === 2, 'same match cannot redirect to another endpoint');

const addresses = [
    '127.0.0.1:27015;quit', '127.0.0.1:27015\n', '127.0.0.1:27015\r\n',
    '127.0.0.1:27015\0', '127.0.0.1:27015 quit', ' 127.0.0.1:27015', '127.0.0.1:27015 ',
    '127.0.0.1:27015%0aquit', '127.00.0.1:27015', '0127.0.0.1:27015', '127.0.0.1:027015',
    '127.0.0.1:01024', '256.0.0.1:27015', '-1.0.0.1:27015', '127.0.0.1:1023',
    '127.0.0.1:65536', '127.0.0.1:1e4', '127.0.0.1:27015.0', '127.0.0.1:',
    '127.1:27015', 'localhost:27015', '[::1]:27015', 'connect 127.0.0.1:27015',
    '127.0.0.1:27015@evil.test', '127.0.0.1:27015/quit', '127.0.0.1:27015"',
    '127.0.0.1:27015\\quit', '127。0。0。1:27015', '', null, 27015
];
for (const address of addresses) {
    const test = harness(); test.receive(allocatedState); test.receiveConnect({...connectFields, address});
    check(test.localEvents.length === 0, 'non-canonical or injected address rejected');
    test.receiveConnect(connectFields);
    check(test.localEvents.length === 1, 'invalid address did not poison valid match latch');
}
for (const address of ['0.0.0.0:1024', '255.255.255.255:65535', '192.0.2.1:27015']) {
    const test = harness(); test.receive(allocatedState); test.receiveConnect({...connectFields, address});
    check(test.localEvents.length === 1 && test.localEvents[0].payload.address === address, 'canonical IPv4 and boundary ports accepted for native VM pin check');
}
for (const match_id of ['short', 'A'.repeat(129), 'match_test_1234\n', 'match_test_1234\r', 'match;quit', 'match.with.dot', 'match test 1234', '', null, 12345678]) {
    const test = harness(); test.receive(allocatedState); test.receiveConnect({...connectFields, match_id});
    check(test.localEvents.length === 0, 'invalid match identifier rejected');
}
for (const build_sha256 of ['a'.repeat(63), 'a'.repeat(65), 'g'.repeat(64), 'A'.repeat(64), buildSha + '\n', '', null, 123]) {
    const test = harness(); test.receive(allocatedState); test.receiveConnect({...connectFields, build_sha256});
    check(test.localEvents.length === 0, 'invalid or non-canonical build digest rejected');
}
for (const raw of [null, [], {}, {address: connectFields.address, match_id: connectFields.match_id}, {...connectFields, command: 'quit'}, {...connectFields, ticket: 'SECRET'}, Object.create(connectFields)]) {
    const test = harness(); test.receive(allocatedState); test.receiveConnect(raw);
    check(test.localEvents.length === 0, 'unexpected fields and inherited fields rejected');
}
for (const phase of ['started', 'running']) {
    const test = harness(); test.receive({...allocatedState, phase, ok: false, worker_available: false}); test.receiveConnect(connectFields);
    check(test.localEvents.length === 1, 'authenticated assigned room does not depend on idle-pool availability');
}
h = harness(undefined, 1, {throwLocal: true}); h.receive(allocatedState); h.receiveConnect(connectFields); h.receiveConnect(connectFields);
check(h.localEvents.length === 1, 'native dispatch error still latches duplicate instead of looping');
h = harness(); h.receive(allocatedState); delete h.context.GameEvents.SendEventClientSide; h.receiveConnect(connectFields);
check(h.localEvents.length === 0, 'missing native event API fails closed');
h = harness(); h.receive(allocatedState); h.receiveConnect({...connectFields, match_id: '__proto__'}); h.receiveConnect({...connectFields, match_id: '__proto__'});
check(h.localEvents.length === 1, 'prototype-like valid identifier has safe duplicate tracking');
h = harness(); h.receive(allocatedState);
for (let i = 0; i < 130; i++) h.receiveConnect({...connectFields, match_id: 'bounded_match_' + i});
check(h.localEvents.length === 128, 'duplicate cache and accepted match count are bounded');
// Native host behavior and lifecycle regressions use real nested DOM/CSS semantics.
for (const name of ['maps/ws4_lobby.vpk']) {
    const test = harness({map_name: name});
    check(test.visible() && test.sent.length === 1, 'only exact supported native map path enables inner panel');
}
for (const name of ['', 'WS4_LOBBY', 'prefix_ws4_lobby', 'ws4_lobby_extra', 'maps/ws4_lobby', 'maps/ws4_lobby.vpk;quit', '../ws4_lobby']) {
    const test = harness({map_name: name, map_display_name: 'ws4_lobby'});
    test.root.visible = true; test.monitor(3);
    check(!test.visible() && test.sent.length === 0 && !Object.keys(test.subscriptions).length, 'untrusted or ambiguous map names cannot expose lobby');
}
for (const missing of ['SurvivalLobbyOverlay', 'LobbyStart', 'LobbyAuthOpen', 'LobbyInviteInput']) {
    const test = harness(undefined, 1, {missing});
    check(!test.visible() && test.sent.length === 0 && !Object.keys(test.subscriptions).length, 'incomplete layout remains hidden without requests or bindings');
    test.ids[missing].valid = true; test.monitor();
    check(test.visible() && test.sent.length === 1 && Object.keys(test.subscriptions).length === 3, 'fully created lobby layout mounts once after scheduled retry');
}
for (const options of [{throwSubscribe: true}, {throwTime: true}]) {
    const test = harness(undefined, 1, options);
    test.root.visible = true;
    check(!test.visible() && !test.root.hittestchildren && test.sent.length === 0, 'initial native API failure leaves transparent inactive context');
}
h = harness();
check(h.pointerClick('LobbyRefresh'), 'verified lobby buttons accept native-style pointer activation');
const oldState = h.subscriptions.survival_lobby_state;
const oldAuth = h.subscriptions.survival_player_web_auth_state;
const oldConnect = h.subscriptions.survival_lobby_connect;
const oldClick = h.ids.LobbyRefresh.handlers.onactivate;
h.receive(allocatedState); h.receiveAuth(pending);
const beforeLeave = h.sent.length;
h.setMap({map_name: 'template_map'}); h.monitor();
h.root.visible = true;
check(!h.visible() && !h.root.hittestchildren && !h.ids.SurvivalLobbyOverlay.hittest, 'paused game clock does not prevent map monitor collapsing ordinary HUD overlay');
check(Object.keys(h.subscriptions).length === 0 && h.unsubscribed.length === 3, 'leaving lobby unsubscribes every service event');
check(!h.pointerClick('LobbyRefresh'), 'host-visible wrapper still cannot intercept ordinary HUD pointer input');
oldState(allocatedState); oldAuth(pending); oldConnect(connectFields); oldClick();
check(h.sent.length === beforeLeave && !h.localEvents.length && !h.browser.length && !h.visible(), 'in-flight old callbacks cannot reopen or act outside lobby');
h.setMap({map_name: 'ws4_lobby'}); h.monitor();
check(h.visible() && h.sent.length === beforeLeave + 1 && Object.keys(h.subscriptions).length === 3, 'return to lobby creates one fresh mount and refresh');
check(!h.ids.LobbyStart.enabled && h.ids.LobbyAuthCode.text === '', 'new lobby mount discards old identity room and authorization display');
h.advance(1);
oldState(allocatedState); oldAuth(pending); oldConnect(connectFields); oldClick();
check(!h.ids.LobbyStart.enabled && !h.localEvents.length && h.ids.LobbyAuthCode.text === '' && h.sent.length === beforeLeave + 1, 'previous mount callbacks remain invalid even after returning to lobby');
for (const action of ['state', 'auth', 'connect', 'refresh', 'browser']) {
    const test = harness(); test.receive(allocatedState); test.receiveAuth(pending);
    if (action === 'browser') { test.receive({...baseState, authenticated: false}); test.receiveAuth(pending); check(test.ids.LobbyAuthOpen.enabled, 'valid browser action exists before map changes'); }
    test.advance(1);
    const before = test.sent.length; test.setMap(new Error('map API unavailable'));
    if (action === 'state') test.receive(allocatedState);
    if (action === 'auth') test.receiveAuth(pending);
    if (action === 'connect') test.receiveConnect(connectFields);
    if (action === 'refresh') test.click('LobbyRefresh');
    if (action === 'browser') test.click('LobbyAuthOpen');
    check(!test.visible() && test.sent.length === before && !test.browser.length && !test.localEvents.length, 'every event/action gates map before monitor or side effect');
}
const clockFailure = {};
const clockTest = harness(undefined, 1, clockFailure);
clockFailure.throwTime = true; clockTest.monitor(10);
check(!clockTest.visible() && !Object.keys(clockTest.subscriptions).length, 'active native clock exception collapses child and removes service callbacks');
h = harness({map_name: 'template_map'});
h.setMap({map_name: 'ws4_lobby'}); h.monitor();
check(h.visible() && h.sent.length === 1, 'initial ordinary map can later enter verified lobby without script reload');
h.setMap(new Error('temporarily unavailable')); h.monitor();
check(!h.visible() && !Object.keys(h.subscriptions).length, 'active map API exception promptly hides and unmounts lobby');
h.root.valid = false; const queued = h.scheduled.length; h.monitor();
check(h.scheduled.length === queued - 1 && !h.visible(), 'destroyed context stops scheduled lifecycle');
const result = {status: 'PASS', checks, source_sha256: require('crypto').createHash('sha256').update(source).digest('hex'), scope: 'Actual XML hierarchy/inline defaults and CSS visibility with mocked Panorama lifecycle/events; no game launched; native visuals NOT_RUN'};
console.log(JSON.stringify(result, null, 2));
