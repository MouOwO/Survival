'use strict';

const assert = require('node:assert/strict');
const {createHarness} = require('./fixtures/menus_v10_harness.cjs');

const h = createHarness(), {cfg, root} = h, Panel = root.constructor;
// Load the actual effect formatter as well as both renderers: this failure
// requires a whole-view font pass followed by a reused tooltip's next hover.
for (const file of [
    'archive_theme_tokens.js', 'archive_handoff_assets.js',
    'archive_handoff_180de7e38b.js', 'archive_parchment_data.js',
    'archive_v10_semantics.js', 'common/archive_tooltip.js',
    'common/archive_font_v36.js'
]) h.load(file);
require('./fixtures/archive_font_images.cjs').ready(h);

const canvas = new Panel('Panel', root, 'ArchiveFontRefreshCanvas');
const menu = new Panel('Label', canvas, 'ArchiveFontRefreshMenu');
menu.text = '通关存档';
Object.assign(menu.style, {fontSize:'21px', color:'#e0e3d2', width:'180px', height:'29px'});
const source = new Panel('Button', canvas, 'ArchiveFontRefreshCard');
source.style.position = '100px 100px 0px';
const names = {clear:'通关存档', fragment:'神兵碎片', fishing:'钓鱼存档', building:'存档神器'};
const tip = cfg.SurvivalArchiveTooltip.Create({
    parent:canvas, root, idPrefix:'ArchiveFontRefreshTooltip',
    getBounds:()=>[1200, 900], categoryName:category=>names[category],
    currencySourceText:category=>category === 'building' ? '信仰值来源：通关每次+400' : ''
});
const font = cfg.SurvivalArchiveFontV36;
h.setCursor(1100, 850);

const clear = Object.freeze({id:'clear_n2_3', name:'常规 N2（3次）', description:'木材+120', count:0, target:3, completed:0});
const fragment = Object.freeze({id:'fragment_01', name:'神兵-梦焰', description:'LV1 英雄生命加成+5%\nLV2 英雄护甲加成+5%', count:20, target:999, level:1});
const fishing = Object.freeze({id:'star_blessing_007', name:'星子', description:'墙伤害格挡+5', count:40, max_owned:300, count_known:1});
const building = Object.freeze({id:'building_02', name:'大剑', description:'造成伤害攻击+10×等级', count:0, level:0, target:5, cost:3000, completed:0});
const before = JSON.stringify([clear, fragment, fishing, building]);

function current(item, category, quantity, metric) {
    assert.equal(tip.Inspect().itemId, item.id);
    assert.equal(tip.Inspect().category, category);
    assert.equal(tip.elements.Title.text, item.name, 'The hovered item owns its title');
    assert.equal(tip.elements.Quantity.text, quantity, 'The hovered category owns its quantity');
    assert.equal(tip.elements.MetricCaption.text, metric, 'The hovered category owns its metric');
    assert.equal(tip.elements.Effect.html, true, 'The real effect formatter retains native rich text');
    for (const [role, label] of Object.entries(tip.elements)) {
        if (label.paneltype !== 'Label') continue;
        const glyphs = label.FindChildTraverse('ArchiveFontV36Glyphs');
        assert(!glyphs || !glyphs.IsValid() || glyphs.visible === false,
            role + ' cannot paint a previous hover through a glyph child');
        assert.equal(label.style.color, label.__archiveTooltipStyle.color,
            role + ' keeps the tooltip renderer\'s current native color');
        assert.notEqual(label.style.color, '#ffffff00', role + ' cannot remain transparent');
    }
}

assert(tip.Show(clear, 'clear', source));
assert.equal(tip.elements.Effect.text, '<font color="#788b93">木材+120</font>');
font.Scope(canvas);
current(clear, 'clear', '0/3', '累计通关次数');
const menuRun = menu.FindChildTraverse('ArchiveFontV36Glyphs');
assert(menuRun && menuRun.visible, 'Ordinary menu labels still use their existing atlas');
assert.equal(menu.style.color, '#ffffff00');
const menuGlyph = menuRun.Children()[0];

assert(tip.Show(fragment, 'fragment', source));
current(fragment, 'fragment', '20/999', '持有碎片');
const fragmentEffects = tip.elements.Effect.text;
assert(fragmentEffects.includes('<font color="#e1e8e8">LV<font color="#f0d48a">1</font>'), 'The owned fragment level retains its bright styling');
assert(fragmentEffects.includes('<br><font color="#788b93">LV2 英雄护甲加成+5%</font>'), 'The next fragment level remains a separate dim row');
assert(!fragmentEffects.includes('木材'), 'The previous achievement never leaks into fragment effects');
font.Scope(canvas);
current(fragment, 'fragment', '20/999', '持有碎片');

assert(tip.Show(fishing, 'fishing', source));
current(fishing, 'fishing', '40/300', '拥有数量');
assert.equal(tip.elements.State.text, '钓鱼存档 · 已拥有');
assert.equal(tip.elements.Effect.text, '墙伤害格挡<font color="#f0d48a">+5</font>');
assert.equal(tip.elements.Condition.text, '', 'Fishing clears the fragment-level condition');
font.Scope(canvas);

assert(tip.Show(building, 'building', source));
current(building, 'building', 'LV0/5', '建筑等级');
assert.equal(tip.elements.Effect.text, '<font color="#788b93">造成伤害攻击+10×等级</font>');
assert.equal(tip.elements.Condition.text, '点击升级 · 消耗 3000 信仰值\n信仰值来源：通关每次+400');

// Native HUD reloads can retain a tooltip already converted by the old script.
// Use the real atlas renderer to create that legacy state; only the class is
// temporarily removed so this setup does not reproduce any cleanup algorithm.
function legacyGlyphs(roles) {
    return roles.map(role=>{
        const label = tip.elements[role];
        label.RemoveClass('ArchiveSharedTooltipText');
        try { font.Render(label); } finally { label.AddClass('ArchiveSharedTooltipText'); }
        const run = label.FindChildTraverse('ArchiveFontV36Glyphs');
        assert(run && run.visible, role + ' has a real legacy atlas run');
        assert.equal(label.style.color, '#ffffff00');
        return run;
    });
}

assert(tip.Show(clear, 'clear', source));
const retained = legacyGlyphs(['Title', 'Effect', 'MetricCaption', 'Quantity']);
assert(tip.Show(fragment, 'fragment', source));
current(fragment, 'fragment', '20/999', '持有碎片');
for (const run of retained) assert(!run.IsValid() || run.visible === false, 'Next hover retires every legacy run');
assert.equal(tip.elements.Effect.text, fragmentEffects, 'Cleanup leaves the real current rich text intact');

assert(tip.Show(fishing, 'fishing', source));
const hiddenLegacy = legacyGlyphs(['Title', 'Effect', 'Quantity']);
tip.Hide();
assert.equal(tip.IsVisible(), false);
font.Scope(canvas);
for (const run of hiddenLegacy) assert(!run.IsValid() || run.visible === false, 'A font pass repairs retained hidden tooltip labels too');
assert(tip.Show(building, 'building', source));
current(building, 'building', 'LV0/5', '建筑等级');
font.Scope(canvas);
current(building, 'building', 'LV0/5', '建筑等级');
assert.equal(menuRun.Children()[0], menuGlyph, 'Tooltip repair does not rebuild a stable menu glyph run');

const richMenu = new Panel('Label', canvas, 'ArchiveFontRefreshRichMenu');
richMenu.text = '属性<font color="#ffcc00">+10</font>';
Object.assign(richMenu.style, {fontSize:'18px', color:'#e0e3d2', width:'200px', height:'29px'});
font.Render(richMenu);
assert(richMenu.FindChildTraverse('ArchiveFontV36Glyphs').Children().some(glyph=>glyph.style.washColor === '#ffcc00'), 'Ordinary atlas labels retain inline effect colors');

assert.equal(JSON.stringify([clear, fragment, fishing, building]), before, 'Presentation never changes the archive snapshots');
tip.Dispose();
assert.equal(cfg.SurvivalTooltipDismiss.Inspect().owners, 0);
assert.equal(h.sent.length, 0, 'Font repair never emits a game or account mutation');
console.log('ARCHIVE_TOOLTIP_FONT_REFRESH_PASS: real font/tooltip/formatter integration; category switching; hidden refresh; legacy glyph recovery; current quantities and colors; ordinary atlas and rich-text preservation');
