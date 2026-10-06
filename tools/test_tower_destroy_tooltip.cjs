const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync('panorama/src/scripts/custom_game/ability_tooltip.js', 'utf8');
const start = source.indexOf('    function render(');
const end = source.indexOf('        setText("CustomAbilityDescription", description);', start);
assert(start >= 0 && end > start);
const render = source.slice(start, end) + 'setText("CustomAbilityDescription", description); return true; }';
const name = '销毁防御塔', desc = '销毁本单位，不返还成长所消耗资源';
for (const useRuntime of [false, true]) {
    const texts = {};
    const env = {
        managedUpgrade: () => true, isSelectedCombatHero: () => false,
        localize: () => 'RAW_OR_STALE_LOCALIZATION',
        localizedAbilityDescription: () => 'STALE DESCRIPTION',
        readTooltipTable: table => table === 'survival_tooltips' ? {name, desc}
            : table === 'survival_ability_runtime' && useRuntime ? {display_name: name, upgrade_description: desc} : {},
        byId: () => ({RemoveClass() {}}), setText: (id, value) => texts[id] = value,
        GameUI: {CustomUIConfig: () => ({})},
        Abilities: {GetLevel: () => 1, GetBehavior: () => 4}
    };
    vm.runInNewContext(render, env);
    assert(env.render(1, 'ability_destroy_arrow_tower', {}));
    assert.equal(texts.CustomAbilityTitle, name);
    assert.equal(texts.CustomAbilityDescription, desc);
}
console.log('TOWER_DESTROY_TOOLTIP_PASS: exact Chinese title/description with runtime and CSV fallback');
