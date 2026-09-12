const fs = require('fs');
const vm = require('vm');
const assert = require('assert');
const source = fs.readFileSync('panorama/src/scripts/custom_game/combat_stats.js', 'utf8');
const start = source.indexOf('    function refreshHeroVitals(unit) {');
const end = source.indexOf('    function refreshHeroVitalsTick()', start);
assert(start >= 0 && end > start);
let state = null;
let health = 100000000;
let maxHealth = health;
const text = {};
const context = {
    Entities: { GetMaxHealth: () => maxHealth, GetHealth: () => health, GetMaxMana: () => 0, GetMana: () => 0 },
    CustomNetTables: { GetTableValue: () => state },
    selectedUnitSnapshot: null, heroPanelState: {},
    formatNumber: value => String(value),
    setText: (key, value) => { text[key] = value; },
    panel: key => key, setWidth: (key, value) => { text[key] = value; }
};
vm.createContext(context);
vm.runInContext(source.slice(start, end), context);
state = { health_scale: '80' };
context.refreshHeroVitals(12);
assert.equal(text.SurvivalHeroHealthText, '8000000000 / 8000000000');
health = 50000000;
context.refreshHeroVitals(12);
assert.equal(text.SurvivalHeroHealthText, '4000000000 / 8000000000');
assert.equal(text.SurvivalHeroHealthFill, '50%');
state = { health_scale: '7.63e36' };
context.refreshHeroVitals(12);
assert(!/Infinity|NaN/.test(text.SurvivalHeroHealthText));
assert.equal(text.SurvivalHeroHealthFill, '50%');
state = null;
context.selectedUnitSnapshot = { entindex: 12, health_scale: '80' };
context.refreshHeroVitals(12);
assert.equal(text.SurvivalHeroHealthText, '4000000000 / 8000000000');
health = 50; maxHealth = 100;
context.refreshHeroVitals(13);
assert.equal(text.SurvivalHeroHealthText, '50 / 100', 'switching to ordinary units never reuses scale');
state = { removed: 1, health_scale: '80' };
context.refreshHeroVitals(13);
assert.equal(text.SurvivalHeroHealthText, '50 / 100');
console.log('ENDLESS_HEALTH_UI_PASS');
