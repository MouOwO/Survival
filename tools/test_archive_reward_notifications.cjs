const fs = require('fs');
const vm = require('vm');
const assert = require('assert');
const source = fs.readFileSync('panorama/src/scripts/custom_game/survival_ui.js', 'utf8');
const start = source.indexOf('    function showNotification(payload) {');
const end = source.indexOf('    function sendClientDiagnostic(', start);
assert(start >= 0 && end > start);
const nodes = [], scheduled = [], nativeErrors = [];
class Panel {
    constructor(type) { this.type = type; this.classes = []; this.valid = true; nodes.push(this); }
    AddClass(value) { this.classes.push(value); }
    SetHasClass(value, enabled) { if (enabled) this.AddClass(value); }
    IsValid() { return this.valid; }
    DeleteAsync() { this.valid = false; }
}
const container = new Panel('container');
const context = {
    playerId: 0, notificationItems: [],
    panel: name => name === 'NotificationContainer' ? container : null,
    $: {CreatePanel: type => new Panel(type)},
    scheduleHUD: (delay, callback) => scheduled.push({delay, callback}),
    lifecycleConfig: {}, lifecycleContext: {},
    GameEvents: {SendEventClientSide: (name, value) => nativeErrors.push({name,value})},
};
vm.createContext(context);
vm.runInContext(source.slice(start,end), context);
function show(payload) {
    const before = nodes.length;
    context.showNotification(Object.assign({player_id:0, audience:'player', level:'success'}, payload));
    return nodes.slice(before).filter(node => node.type === 'Label' && node.classes.includes('NotificationText'));
}
const colored = '获得 <font color="#b680ee">深渊碎片</font> ×2';
let labels = show({kind:'archive_reward',rich_text:true,message:colored});
assert.strictEqual(labels.length,1);
assert.strictEqual(labels[0].html,true);
assert.strictEqual(labels[0].text,colored);
for (const payload of [
    {kind:'archive_reward',rich_text:false,message:colored},
    {kind:'message',rich_text:true,message:colored},
    {message:'<br>普通通知'},
]) {
    labels=show(payload);
    assert.strictEqual(labels.length,1);
    assert.strictEqual(labels[0].html,false,'only committed archive reward notifications opt into markup');
}
assert.strictEqual(show({player_id:1,kind:'archive_reward',rich_text:true,message:colored}).length,0);
assert.strictEqual(show({kind:'archive_reward',rich_text:true,message:' '}).length,0);
labels=show({kind:'research_success',subject:'箭塔攻击',message:'研究成功'});
assert.deepStrictEqual(labels.map(node=>node.text),['研究 ','箭塔攻击',' 科技成功']);
assert(labels.every(node=>node.html===false));
show({level:'error',message:'金币不足'});
assert.strictEqual(nativeErrors.at(-1).name,'dota_hud_error_message');
assert.strictEqual(nativeErrors.at(-1).value.message,'金币不足');
console.log('ARCHIVE_REWARD_NOTIFICATION_UI_PASS: acknowledged quality markup, plain-message isolation, ownership, research and native errors');
