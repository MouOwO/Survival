'use strict';
const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const source = fs.readFileSync('panorama/src/scripts/custom_game/combat_stats.js', 'utf8');
let deletes = 0, creates = 0;
const labels = {}, lists = [];
function makeList() {
  const list = { children: [], GetChildCount() { return this.children.length; },
    RemoveAndDeleteChildren() { deletes++; this.children = []; } };
  lists.push(list); return list;
}
let list = makeList();
const environment = { JSON, Number, String, Object, Array,
  panel: id => id === 'HeroTechnologyList' ? list : (labels[id] ||= { text: '' }),
  setText: (id, value) => { labels[id] ||= {}; labels[id].text = String(value); },
  formatNumber: value => String(value || 0),
  $: { CreatePanel(type, parent, id) {
    creates++; const node = { type, id, children: [], AddClass() {} };
    parent.children.push(node); return node;
  } } };
vm.runInNewContext(source.slice(source.indexOf('    function asArray('), source.indexOf('    function attackText(')), environment);
const snapshot = { total_damage: 1, last_damage: 1, hit_count: 1,
  technology_stats: { final: { hero: { attack_flat: 10 } } },
  technologies: [{ group: 'attack', name: '英雄攻击', level: 3, effect: '攻击 +30' }] };
environment.renderCombatDebug(snapshot);
assert.equal(creates, 4); const row = list.children[0];
for (let i = 2; i <= 1001; i++) {
  environment.renderCombatDebug({ ...snapshot, total_damage: i * 9e15, last_damage: 9e15, hit_count: i,
    technologies: { 1: { ...snapshot.technologies[0] } } });
}
assert.equal(deletes, 1, 'damage-only packets cannot rebuild technology panels');
assert.equal(creates, 4); assert.equal(list.children[0], row);
assert.match(labels.HeroCombatLastDamage.text, /1001/);
environment.renderCombatDebug({ ...snapshot, technologies: [{ ...snapshot.technologies[0], level: 4, effect: '攻击 +40' }] });
assert.equal(deletes, 2); assert.equal(list.children[0].children[1].text, 'Lv.4');
list = makeList(); environment.renderCombatDebug(snapshot);
assert.equal(list.GetChildCount(), 1, 'replacement native list must render even with identical data');
list.children = []; environment.renderCombatDebug(snapshot);
assert.equal(list.GetChildCount(), 1, 'removed children must be repaired');
environment.renderCombatDebug({ ...snapshot, technology_stats: null, technologies: [] });
assert.equal(labels.HeroCombatTechnologySummary.text, '');
assert.equal(list.children[0].text, '暂无已激活科技');
const finalDeletes = deletes; environment.renderCombatDebug({ ...snapshot, technologies: [] });
assert.equal(deletes, finalDeletes, 'empty list is also stable');
console.log('COMBAT_DEBUG_INCREMENTAL_PASS 1000 combat packets reuse technology panels; changed/replaced/empty lists update');
