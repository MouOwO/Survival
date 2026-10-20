'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {createHarness} = require('./fixtures/menus_v10_harness.cjs');
const root = path.resolve(__dirname, '../..');
const h = createHarness(), {cfg, nodes} = h;
const ids = ['DailyClaim', 'DailyMakeup', 'PassPurchase', 'DailyRules'];
const actionIds = [...ids, 'DailyClose', 'DailyGW2Close'];
const cleared = [];
let legacyHoverCalls = 0;

// Current native Dota client exposes Panel.ClearPropertyFromCode. Model only
// its removal of a named inline override; CSS painting still belongs to Dota.
Object.getPrototypeOf(h.root).ClearPropertyFromCode = function (name) {
    this.check();
    assert(['brightness', 'saturation'].includes(name));
    cleared.push({id:this.id, name});
    delete this.style[name];
};
for (const id of ids) {
    nodes[id].style.brightness = '1';
    nodes[id].style.saturation = '1';
}
// XML action panels can survive a native script reload with old tooltip events.
// Seed those before mounting the current renderer; replacements must retire both.
for (const id of actionIds.filter(id => nodes[id])) {
    nodes[id].__dailyGW2Tooltip = {title:'过期按钮提示', body:'旧脚本遗留内容'};
    for (const event of ['onmouseover', 'onmouseout']) nodes[id].SetPanelEvent(event, () => {
        legacyHoverCalls++;
        if (nodes.DailyGW2Tooltip) nodes.DailyGW2Tooltip.visible = true;
    });
}
for (const source of ['common/ui_registry.js', 'common/ui_components.js', 'ui_layers.js',
    'archive_theme_tokens.js', 'archive_parchment_data.js', 'archive_handoff_180de7e38b.js',
    'archive_v10_semantics.js', 'common/archive_tooltip.js', 'daily_gw2_data.js',
    'daily_remaining_5d5c1152eb.js']) h.load(source);
cfg.SurvivalDaily.Open(false);

function noInlineFeedback() {
    for (const id of ids) for (const property of ['brightness', 'saturation']) {
        assert(nodes[id].style[property] === undefined || nodes[id].style[property] === '',
            id + ' leaves ' + property + ' to CSS instead of masking native hover/press states');
    }
}
noInlineFeedback();
for (const id of ids) for (const name of ['brightness', 'saturation'])
    assert(cleared.some(row => row.id === id && row.name === name), 'A surviving old native panel is migrated: ' + id + '.' + name);

// Resolve only the two feedback properties from the actual stylesheet. This
// small selector evaluator checks precedence and disabled/busy conflicts, not
// native cursor input, transitions, shader painting or screenshot appearance.
const css = fs.readFileSync(path.join(root, 'panorama/src/styles/custom_game/daily_gw2.css'), 'utf8')
    .replace(/\/\*[\s\S]*?\*\//g, '');
const rules = [...css.matchAll(/([^{}]+)\{([^{}]*)\}/g)].flatMap((match, order) =>
    match[1].split(',').map(selector => ({selector:selector.trim(), order,
        declarations:Object.fromEntries([...match[2].matchAll(/([\w-]+)\s*:\s*([^;]+)/g)]
            .map(pair => [pair[1], pair[2].trim()]))})));
function matches(rule, button, state) {
    const compound = rule.selector.split(/\s+/).at(-1);
    if (!compound.includes('.DailyGW2Button')) return false;
    const tokens = compound.match(/[.#:][\w-]+/g) || [];
    assert.equal(tokens.join(''), compound, 'Feedback selector is supported explicitly: ' + compound);
    return tokens.every(token => token[0] === '.' ? button.BHasClass(token.slice(1)) : token[0] === '#' ? button.id === token.slice(1) :
        token === ':enabled' ? button.enabled !== false : token === ':disabled' ? button.enabled === false :
        token === ':hover' ? !!state.hover : token === ':active' ? !!state.active : false);
}
function feedback(button, state = {}) {
    const result = {brightness:1, saturation:1};
    for (const property of Object.keys(result)) {
        const matching = rules.filter(rule => property in rule.declarations && matches(rule, button, state))
            .sort((a, b) => {
                const score = rule => (rule.selector.match(/#/g) || []).length * 100 +
                    (rule.selector.match(/[.:]/g) || []).length * 10;
                return score(a) - score(b) || a.order - b.order;
            });
        if (matching.length) result[property] = Number(matching.at(-1).declarations[property]);
        const inline = button.style[property];
        if (inline !== undefined && inline !== '') result[property] = Number(inline);
        assert(Number.isFinite(result[property]));
    }
    return result;
}
let sequence = 0;
const base = {ok:true, today:25004, period_id:'button-feedback', count:0, ordinary_status:'claimable',
    has_pass:1, purchase_enabled:1, pending:0, price:'20元', duration_days:30, makeup_days:30,
    missed:[25003], specials:[{id:'daily_ancient_tree', day:14, name:'古树眷顾', description:'开局木材+300', owned:0}],
    calendar_current_day:1, calendar_start_count:0,
    calendar28:Array.from({length:28}, (_, index) => ({day:index + 1, status:index ? 'not_open' : 'claimable',
        is_today:index ? 0 : 1, rewards:[{id:'daily_growth_gem', name:'成长宝石', count:3, description:'正式奖励'}]}))};
function send(extra = {}) { h.emit('survival_daily_snapshot', {...base, ...extra, sequence:++sequence}); }
send();
for (const id of ids) {
    const button = nodes[id];
    assert.equal(button.enabled, true, id + ' is eligible in the ready fixture');
    const normal = feedback(button), hover = feedback(button, {hover:true}), pressed = feedback(button, {hover:true, active:true});
    assert(hover.brightness > normal.brightness, id + ' has a visible enabled hover brightness increase');
    assert(pressed.brightness < normal.brightness, id + ' has a distinct pressed brightness decrease');
    assert.deepEqual(feedback(button), normal, 'Releasing and leaving restores the normal CSS state');
}

// Operation buttons have no tooltip. Card and item tooltips still work, while
// moving onto a button actively retires any already-visible reward description.
const requestsBeforeHover = h.sent.length;
function noActionTooltip() {
    for (const id of actionIds) {
        const button = nodes[id];
        assert(button, 'The operation button still exists: ' + id);
        nodes.DailyGW2Day_1.events.onmouseover(); h.flushFinite();
        assert.equal(nodes.DailyGW2Tooltip.visible, true, 'The actual reward card still opens its description');
        assert.equal(typeof button.events.onmouseover, 'function');
        assert.equal(typeof button.events.onmouseout, 'function');
        button.events.onmouseover(); h.flushFinite();
        assert.equal(nodes.DailyGW2Tooltip.visible, false, id + ' hides a previous reward tooltip instead of displaying an action description');
        button.events.onmouseout(); h.flushFinite();
        assert.equal(nodes.DailyGW2Tooltip.visible, false, id + ' has no stale mouseout tooltip');
    }
    assert.equal(legacyHoverCalls, 0, 'Surviving old native action handlers are replaced, not merely omitted by the new renderer');
    assert.equal(cfg.SurvivalDaily.Inspect().open, true, 'Hovering controls does not close the reward calendar');
}
noActionTooltip();
const monthly = nodes.DailyGW2Special_daily_ancient_tree;
const descendants = panel => panel.Children().flatMap(child => [child, ...descendants(child)]);
const itemSlot = descendants(monthly).find(node => node.BHasClass('DailyGW2PassReward'));
itemSlot.events.onmouseover(); h.flushFinite();
assert.equal(nodes.DailyGW2Tooltip.visible, true, 'The monthly item slot retains its full reward tooltip');
assert(nodes.DailyGW2TooltipTitle.text.includes('古树眷顾'));
itemSlot.events.onmouseout(); h.flushFinite();
assert.equal(nodes.DailyGW2Tooltip.visible, false);
assert.equal(h.sent.length, requestsBeforeHover, 'Hover and press styling never submit a reward or purchase');

const migrationCalls = cleared.length;
for (let index = 0; index < 3; index++) { send({count:index}); noInlineFeedback(); }
assert.equal(cleared.length, migrationCalls, 'Routine snapshots do not repeat the one-time inline migration');
noActionTooltip();
send({pending:1});
const pendingRequests = h.sent.length;
for (const id of ['DailyClaim', 'DailyMakeup', 'PassPurchase']) {
    const button = nodes[id];
    assert.equal(button.enabled, false);
    const normal = feedback(button);
    assert(normal.brightness < 1 && normal.saturation < 1);
    assert.deepEqual(feedback(button, {hover:true}), normal, 'Disabled hover stays disabled');
    assert.deepEqual(feedback(button, {hover:true, active:true}), normal, 'Disabled press stays disabled');
    button.events.onactivate();
}
assert.equal(h.sent.length, pendingRequests, 'Pending buttons reject direct stale activation callbacks');
noInlineFeedback();

send();
const busyRequests = h.sent.length, rulesHidden = nodes.DailyRulesText.BHasClass('ArchiveHidden');
for (const id of ids) {
    const button = nodes[id];
    cfg.SurvivalUI.State.Set(button, {enabled:true, busy:true});
    const normal = feedback(button);
    assert(normal.brightness < 1 && normal.saturation < 1, 'A busy action keeps its disabled feedback');
    assert.deepEqual(feedback(button, {hover:true, active:true}), normal, 'Busy state wins over hover and press');
    button.events.onactivate();
    cfg.SurvivalUI.State.Set(button, {busy:false});
}
assert.equal(h.sent.length, busyRequests, 'Busy feedback cannot bypass the shared activation guard');
assert.equal(nodes.DailyRulesText.BHasClass('ArchiveHidden'), rulesHidden);
send(); noInlineFeedback();
cfg.SurvivalDaily.Close(); cfg.SurvivalDaily.Open(false); noInlineFeedback();
noActionTooltip();
h.load('daily_remaining_5d5c1152eb.js');
send(); noInlineFeedback(); noActionTooltip();
cfg.SurvivalDaily.Dispose();
console.log('DAILY_BUTTON_FEEDBACK_PASS: actual CSS cascade without inline masking, one-time legacy migration, distinct enabled hover/press, disabled/busy guards, no action tooltips across snapshots/reopen/reload, preserved reward card/item tooltips; native appearance requires game capture');
