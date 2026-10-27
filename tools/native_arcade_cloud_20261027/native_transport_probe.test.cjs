'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../../panorama/src/scripts/custom_game/native_transport_probe.js'), 'utf8');
const SEND = 'survival_native_transport_probe', POLL = SEND + '_poll';
const REQUEST = SEND + '_request', REPLY = SEND + '_reply';
const nonce = n => Number(n).toString(16).padStart(32, '0');
const ECHO = Buffer.from('native echo only').toString('base64url');
const reply = (id=1, changes={}) => ({ok:true,revision:'WS4-NATIVE-PROBE-01',nonce:nonce(id),echo_b64:ECHO,
    player_id:0,account_id:'42',match_session_id:'native_probe_session_01',...changes});
function harness(options = {}) {
    const cfg = {}, commands = new Map(), registrations = [], listeners = new Map(), logs = [], sent = [];
    let now = 1000000, player = 0, map = 'template_map', serial = 0, valid = true;
    let account = 42, steam = '[U:1:42]', session = 'native_probe_session_01';
    const panelHooks=new Set();
    let root, currentDelete;
    const context = vm.createContext({GameUI:{CustomUIConfig:() => cfg},
        Game:{GetLocalPlayerID:() => player,GetMapInfo:() => ({map_name:map}),
            GetPlayerInfo:() => ({player_steamid:steam}),
            AddCommand:(name, fn, help, flags) => {
                registrations.push({name,help,flags});
                if (options.registrationThrows) throw Error('native duplicate');
                assert(!commands.has(name), 'there is only one native binding per fixed command');
                commands.set(name,fn);
            }},
        Players:{GetSteamAccountID:() => account},
        CustomNetTables:{GetTableValue:(table,key) => {assert.equal(table,'survival_loading');assert.equal(key,'state');return {session_id:session};}},
        GameEvents:{Subscribe:(name,fn) => {const id=++serial;listeners.set(id,{name,fn});return id;},
            Unsubscribe:id => listeners.delete(id),
            SendCustomGameEventToServer:(name,payload) => {
                sent.push({name,payload:JSON.parse(JSON.stringify(payload))});
                if(options.sendThrows) throw Error('native send lost');
            }},
        $:{GetContextPanel:() => root,Msg:line => logs.push(JSON.parse(line.replace('[WS4-NATIVE-TRANSPORT-PROBE] ',''))),
            RegisterEventHandler:(name,panel,fn) => {assert.equal(name,'PanelDeleted');currentDelete=fn;panelHooks.add(fn);},
            UnregisterEventHandler:(name,panel,fn) => {assert.equal(name,'PanelDeleted');panelHooks.delete(fn);}},
        Date:{now:() => now},console});
    function load() { valid=true;root={IsValid:() => valid};vm.runInContext(source,context);return cfg.SurvivalNativeTransportProbe; }
    load();
    return {cfg,commands,registrations,listeners,logs,sent,load,panelHooks,
        api:() => cfg.SurvivalNativeTransportProbe,
        command:(name,...args) => commands.get(name)(...args),
        emit:value => [...listeners.values()].filter(x=>x.name===REPLY).forEach(x=>x.fn(value)),
        rawListeners:() => [...listeners.values()].map(x=>x.fn),
        advance:n => {now+=n;},setClock:n => {now=n;},
        player:n => {player=n;},map:n => {map=n;},account:(n,s) => {account=n;if(s!==undefined)steam=s;},
        session:s => {session=s;},invalidate:() => {valid=false;},deleted:() => currentDelete()};
}
test('only two fixed flags0 commands; no mount network; private exact echo is evidence, not permission', () => {
    const h=harness();assert.deepEqual(h.registrations.map(x=>[x.name,x.flags]),[[SEND,0],[POLL,0]]);
    assert.equal(h.sent.length,0);assert.equal(h.listeners.size,1);
    h.command(SEND,nonce(1),ECHO);
    assert.deepEqual(h.sent,[{name:REQUEST,payload:{nonce:nonce(1),echo_b64:ECHO}}]);
    h.emit(reply());
    assert.deepEqual(h.logs.at(-1),{kind:'WS4_NATIVE_TRANSPORT_PROBE',scope:'echo_only',status:'reply',nonce:nonce(1),echo_b64:ECHO,ok:true});
    h.command(POLL,POLL,nonce(1));assert.equal(h.logs.at(-1).status,'reply');assert.equal(h.sent.length,1);
});
test('arguments reject arbitrary command text, extra parameters and unsafe or oversized base64url', () => {
    const h=harness();
    for(const args of [[nonce(1)], [nonce(1),ECHO,'extra'],[nonce(1),ECHO+';quit'],
        ['a'.repeat(31),ECHO],['A'.repeat(32),ECHO],['x'.repeat(32),ECHO],['0'.repeat(32),123],
        [nonce(1),''],[nonce(1),'AB=='],[nonce(1),'AAF='],[nonce(1),'A==='
        ],[nonce(1),'A'.repeat(196)],[nonce(1),'AA-_='],[nonce(1),'AAAA\n'],[nonce(1),'中文']]) h.command(SEND,...args);
    assert.equal(h.sent.length,0);assert(h.logs.every(row=>row.status==='invalid_request'));
    assert(!JSON.stringify(h.logs).includes('quit'));
    h.command(SEND,SEND,nonce(2),'A'.repeat(192));assert.equal(h.sent.length,1);
    h.command(SEND,nonce(3),'a_-A');h.command(SEND,nonce(4),'A');assert.equal(h.sent.length,3);
});
test('unknown, mismatched, extra-field, failed and replayed replies never become evidence', () => {
    const h=harness();h.command(SEND,nonce(1),ECHO);const before=h.logs.length;
    for(const value of [reply(2),reply(1,{ok:false}),reply(1,{echo_b64:'AAAA'}),reply(1,{ok:1}),
        reply(1,{extra:'untrusted'}),reply(1,{player_id:1}),reply(1,{account_id:'43'}),
        reply(1,{account_id:42}),reply(1,{match_session_id:'native_other_session'}),
        reply(1,{revision:'other'}),null]) h.emit(value);
    assert.equal(h.logs.length,before);
    const received=reply();h.emit(received);h.emit(received);
    assert.equal(h.logs.length,before+1);h.command(SEND,nonce(1),ECHO);assert.equal(h.sent.length,1);
    h.command(SEND,nonce(1),'AAAA');assert.equal(h.logs.at(-1).status,'nonce_conflict');
});
test('ten attempts per rolling 30 seconds survive hot reload and polling sends nothing', () => {
    const h=harness();for(let n=1;n<=10;n++)h.command(SEND,nonce(n),ECHO);
    h.command(SEND,nonce(11),ECHO);assert.equal(h.sent.length,10);assert.equal(h.logs.at(-1).status,'rate_limited');
    h.load();h.command(SEND,nonce(12),ECHO);h.command(POLL,nonce(10));assert.equal(h.sent.length,10);
    h.advance(29999);h.command(SEND,nonce(13),ECHO);assert.equal(h.sent.length,10);
    h.advance(1);h.command(SEND,nonce(14),ECHO);assert.equal(h.sent.length,11);
    assert.equal(h.registrations.length,2);
});
test('native command bindings dispatch to the new owner while retired API and events stay inert', () => {
    const h=harness(),old=h.api(),oldReplies=h.rawListeners();h.command(SEND,nonce(1),ECHO);
    h.load();const fresh=h.api();assert.notEqual(old,fresh);assert.equal(h.listeners.size,1);
    assert.equal(old.Send(nonce(2),ECHO),false);oldReplies.forEach(fn=>fn(reply()));
    assert(!h.logs.some(row=>row.status==='reply'));
    old.Dispose();assert.equal(h.api(),fresh);h.command(SEND,nonce(3),ECHO);assert.equal(h.sent.length,2);
    for(let n=0;n<100;n++)h.load();assert.equal(h.registrations.length,2);assert.equal(h.listeners.size,1);assert.equal(h.panelHooks.size,1);
});
test('Dispose and root deletion unsubscribe and clear pending; stale owners cannot send', () => {
    const h=harness(),old=h.api();h.command(SEND,nonce(1),ECHO);h.deleted();
    assert.equal(h.listeners.size,0);assert.equal(h.panelHooks.size,0);assert.equal(h.api(),null);assert.equal(old.Inspect().records,0);
    h.command(SEND,nonce(2),ECHO);assert.equal(h.sent.length,1);
    const other=harness();other.invalidate();other.command(SEND,nonce(3),ECHO);assert.equal(other.sent.length,0);
});
test('slot/map changes cannot accept or expose an earlier echo, and foreign registry/owner are not used', () => {
    const invalid=harness();
    for(const id of [NaN,Infinity,undefined,'0',-1,24,0.5]){
        invalid.player(id);invalid.command(SEND,nonce(99),ECHO);
        assert.equal(invalid.sent.length,0,'an invalid native player slot must not send even an echo request');
    }
    const h=harness();h.command(SEND,nonce(1),ECHO);h.player(1);h.emit(reply());
    h.command(POLL,nonce(1));assert.equal(h.logs.at(-1).status,'missing');
    h.map('dota');h.command(SEND,nonce(2),ECHO);assert.equal(h.sent.length,1);
    h.map('maps/template_map.vpk');h.command(SEND,nonce(3),ECHO);assert.equal(h.sent.length,2);
    h.cfg.SurvivalNativeTransportProbe={};h.command(SEND,nonce(4),ECHO);assert.equal(h.sent.length,2);
    const guarded=harness();guarded.cfg.SurvivalNativeTransportProbeCommandsV1={version:99};guarded.load();
    guarded.command(SEND,nonce(5),ECHO);assert.equal(guarded.sent.length,0);
});
test('reply timeout, bounded records and clock rollback fail closed without HTTP or auto retry', () => {
    const h=harness();h.command(SEND,nonce(1),ECHO);h.advance(30000);h.emit(reply());
    h.command(POLL,nonce(1));assert.equal(h.logs.at(-1).status,'timeout');
    for(let batch=0;batch<5;batch++){for(let n=0;n<10;n++)h.command(SEND,nonce(2+batch*10+n),ECHO);h.advance(30000);}
    assert(h.api().Inspect().records<=20);assert.equal(h.sent.length,51);
    h.setClock(1);h.command(SEND,nonce(100),ECHO);h.load();h.command(SEND,nonce(101),ECHO);assert.equal(h.sent.length,51);
});
test('local account/session are checked without logging identity; Steam64 precision and mismatches fail closed', () => {
    const h=harness();h.command(SEND,nonce(1),ECHO);h.session('native_probe_session_02');h.emit(reply());
    h.command(POLL,nonce(1));assert.equal(h.logs.at(-1).status,'missing');
    h.account(43,'[U:1:42]');h.command(SEND,nonce(2),ECHO);assert.equal(h.sent.length,1);
    h.account(undefined,'76561197960265770');h.session('native_probe_session_01');
    h.command(SEND,nonce(3),ECHO);h.emit(reply(3));assert.equal(h.logs.at(-1).status,'reply');
    h.account(4294967295,'76561202255233023');h.command(SEND,nonce(4),ECHO);
    h.emit(reply(4,{account_id:'4294967295'}));assert.equal(h.logs.at(-1).status,'reply');
    assert(h.logs.every(row=>!('account_id' in row)&&!('player_id' in row)&&!('match_session_id' in row)));
    h.session('bad');h.command(SEND,nonce(5),ECHO);assert.equal(h.sent.length,3);
});
test('failed native sends consume the nonce and registration failure has at most two attempts per command', () => {
    const h=harness({sendThrows:true});h.command(SEND,nonce(1),ECHO);h.command(SEND,nonce(1),ECHO);
    assert.equal(h.sent.length,1);assert(h.logs.some(row=>row.status==='send_failed'));
    const failed=harness({registrationThrows:true});for(let i=0;i<20;i++)failed.load();
    assert.equal(failed.registrations.length,4);assert.equal(failed.listeners.size,1);assert.equal(failed.sent.length,0);
});
