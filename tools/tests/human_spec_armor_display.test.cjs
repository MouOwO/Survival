const assert = require('assert');
const {setup} = require('../test_combat_stats_callbacks.cjs');

// Render through the actual selected-unit callback. Only the armor text may
// lose its fraction; the source snapshot and damage/attack-speed displays stay
// precise, including older cached snapshots without armor_display.
const t = setup({config: {SurvivalNumberFormatter: {Format: value => String(value)}}});
t.select(7, 'npc_survival_wave_monster');
const labels = {};
for (const id of ['CombatArmorValue', 'HeroTooltipArmor', 'CombatAttackValue', 'CombatAttackSpeedValue']) {
    labels[id] = new t.Panel(id, t.context, 'Label');
}
for (const [index, value] of [117.6, 2698.8, 0, -0.1, '117.999'].entries()) {
    const snapshot = {entindex: 7, refresh_version: index + 1, armor: value,
        attack_min: 2473.9, attack_max: 2473.9, attack_speed_percentage: 250};
    t.api.updateSnapshot(snapshot);
    assert.equal(labels.CombatArmorValue.text, String(Math.floor(Number(value))));
    assert.equal(labels.HeroTooltipArmor.text, labels.CombatArmorValue.text);
    assert.equal(labels.CombatAttackValue.text, '2473.9');
    assert.equal(labels.CombatAttackSpeedValue.text, '250%');
    assert.strictEqual(snapshot.armor, value, 'rendering must leave logical armor untouched');
}
console.log('HUMAN_SPEC_ARMOR_DISPLAY_PASS: selected-unit and tooltip floor armor while preserving logical stats');
