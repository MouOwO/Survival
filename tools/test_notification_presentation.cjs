'use strict';
const assert = require('node:assert/strict'), fs = require('node:fs'), vm = require('node:vm');
const source = fs.readFileSync('panorama/src/scripts/custom_game/survival_ui.js', 'utf8');
const scheduled = [], nativeErrors = [], container = {children: []};
function create(type, parent) {
    const entry = {type, children: [], classes: new Set(), valid: true,
        AddClass(name) {this.classes.add(name);},
        SetHasClass(name, on) {on ? this.classes.add(name) : this.classes.delete(name);},
        IsValid() {return this.valid;},
        DeleteAsync(delay) {this.deleteDelay = delay; this.valid = false;}};
    parent.children.push(entry); return entry;
}
const context = {playerId: 1, notificationItems: [], panel: () => container,
    GameEvents: {SendEventClientSide: (event, payload) => nativeErrors.push({event, payload})},
    $: {CreatePanel: create, Schedule: (delay, callback) => scheduled.push({delay, callback})}};
vm.runInNewContext(source.slice(source.indexOf('    function showNotification('),
    source.indexOf('    function sendClientDiagnostic(')), context);
const show = context.showNotification;
show({audience: 'player', player_id: 0, message: '其他玩家科技'});
show(null); show({message: '  '});
assert.equal(container.children.length, 0, 'foreign private/empty notices do not render');

assert.equal(nativeErrors.length, 0, 'foreign/empty notices cannot send native errors');
const actionCases = [
    ['木材不足', '木材不足'], ['金币不足', '金币不足'], ['人口不足', '人口不足'],
    ['wood_not_enough', '木材不足'], ['not_enough_wood', '木材不足'], ['insufficient_wood', '木材不足'],
    ['gold_not_enough', '金币不足'], ['not_enough_gold', '金币不足'], ['insufficient_gold', '金币不足'],
    ['population_not_enough', '人口不足'], ['not_enough_population', '人口不足'], ['insufficient_population', '人口不足'],
    ['合体木材不足，需要 100 木材', '木材不足'],
    ['升级金币不足，需要 200 金币', '金币不足'],
    ['训练人口不足，需要 3 人口', '人口不足'],
    ['research_queue_full', '研究队列已满'], ['technology_queue_full', '研究队列已满'],
    ['研究队列已满', '研究队列已满'], ['队列研究已满', '研究队列已满'],
    ['研究队列已满（1个研究中＋6个等待）', '研究队列已满'],
];
for (const [message, expected] of actionCases) {
    const priorNative = nativeErrors.length, priorItems = container.children.length, priorTimers = scheduled.length;
    show({audience: 'player', player_id: 1, message, level: 'error'});
    assert.equal(nativeErrors.length, priorNative + 1, message + ' sends exactly one native error');
    assert.equal(nativeErrors.at(-1).event, 'dota_hud_error_message');
    assert.equal(nativeErrors.at(-1).payload.reason, 80);
    assert.equal(nativeErrors.at(-1).payload.message, expected);
    assert.equal(container.children.length, priorItems, 'native action error creates no custom card');
    assert.equal(scheduled.length, priorTimers, 'native action error needs no custom fade timer');
}
const privateNativeCount = nativeErrors.length;
show({audience: 'player', player_id: 0, message: '木材不足', level: 'error'});
show({audience: 'player', player_id: 0, message: '研究队列已满', level: 'error'});
assert.equal(nativeErrors.length, privateNativeCount, 'another player resource failure stays private');
const priorPanelLookup = context.panel;
context.panel = () => null;
show({audience: 'player', player_id: 1, message: '金币不足', level: 'error'});
assert.equal(nativeErrors.length, privateNativeCount + 1, 'native feedback works when custom notice container is unavailable');
context.panel = priorPanelLookup;
show({audience: 'all', player_id: 0, message: '木材不足', level: 'error'});
assert.equal(nativeErrors.length, privateNativeCount + 1, 'broadcast remains a visible custom notice');
assert(container.children.at(-1).classes.has('NotificationBroadcast'));
assert(container.children.at(-1).classes.has('error'));

show({audience: 'player', player_id: 1, kind: 'research_success', subject: '提高采金效率',
    ability_icon: 'ability_upgrade_gold_mine_efficiency', message: '研究提高采金效率科技成功'});
let entry = container.children.at(-1);
assert.equal(entry.children[0].abilityname, 'ability_upgrade_gold_mine_efficiency');
assert.equal(entry.children.filter(child => child.type === 'Label').map(child => child.text).join(''),
    '研究 提高采金效率 科技成功');
assert(entry.children.some(child => child.classes.has('NotificationSubject')));
assert.equal(scheduled.at(-1).delay, 3.5);
assert.equal(entry.hittestchildren, false);
show({audience: 'all', player_id: 0, actor_name: '玩家甲', hero_name: 'npc_dota_hero_monkey_king',
    kind: 'fishing_reward', message: '玩家甲 钓到了：金币（100）'});
entry = container.children.at(-1);
assert(entry.classes.has('NotificationBroadcast'));
assert.equal(entry.children[0].heroname, 'npc_dota_hero_monkey_king');
assert.equal(entry.children.filter(child => child.type === 'Label').map(child => child.text).join(''),
    '玩家甲 钓到了：金币（100）');
assert.equal(scheduled.at(-1).delay, 5);
const old = container.children[0];
for (let index = 0; index < 10; index++) show({audience: 'player', player_id: 1, message: '当前技能不可用', level: 'error'});
assert.equal(context.notificationItems.length, 4, 'notification bursts are bounded');
assert.equal(old.valid, false);
assert(container.children.at(-1).classes.has('error'));
scheduled.at(-1).callback();
assert(container.children.at(-1).classes.has('NotificationDismissed'));
assert.equal(container.children.at(-1).deleteDelay, 0.25, 'exit fades before deletion');
console.log('NOTIFICATION_PRESENTATION_PASS: private native resource/queue errors, aliases/details, exactly once/no card/no timer, missing container, research/reward/broadcast and normal error stack/fade');
