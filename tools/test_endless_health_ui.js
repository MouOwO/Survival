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

// Exercise the production formatter with logical (scaled) health, including
// endless values far beyond the engine's own health representation.
const bootstrap = fs.readFileSync('panorama/src/scripts/custom_game/ui_bootstrap.js', 'utf8');
const cfg = {};
context.GameUI = { CustomUIConfig: () => cfg };
vm.runInContext(bootstrap.slice(bootstrap.indexOf('    function trimmedNumber('),
    bootstrap.indexOf('    $.Msg("[SURVIVAL_CRASH_ISOLATION]')), context);
const formatter = cfg.SurvivalNumberFormatter;
assert.equal(formatter.Compact, formatter.Format, 'HUD and stats share the same units');
context.formatNumber = formatter.Format;
for (const [value, expected] of [
    [0, '0'], [9999.94, '9999.9'], [9999.96, '1万'], [10000, '1万'],
    [99999400, '9999.9万'], [99999600, '1亿'], [123456789, '1.2亿'],
    [9.99996e11, '1兆'], [1e12, '1兆'], [1.2345e12, '1.2兆'],
    ['1000000000000', '1兆'], [-1.2345e12, '-1.2兆'], [-0.01, '0'],
    [1e16, '1京'], [1e20, '1垓'], [1e24, '1秭'], [1e28, '1穰'],
    [1e32, '1沟'], [1e36, '1涧'], [1e40, '1正'], [1e44, '1载'],
    [9.99996e47, '1e48'], [1e48, '1e48'], [1.2345e80, '1.2e80'],
    [Infinity, '—'], [-Infinity, '—'], ['invalid', '—']
]) assert.equal(formatter.Format(value), expected, 'format ' + value);
assert(formatter.Format(Number.MAX_VALUE).length <= 10, 'finite huge values stay short');
health = 5e7; maxHealth = 1e8;
state = { health_scale: '20000' };
context.refreshHeroVitals(13);
assert.equal(text.SurvivalHeroHealthText, '1兆 / 2兆');
assert.equal(text.SurvivalHeroHealthFill, '50%', 'compact labels do not change health fraction');
state = { health_scale: '7.63e36' };
context.refreshHeroVitals(13);
assert.equal(text.SurvivalHeroHealthText, '3.8载 / 7.6载');
state = { health_scale: '1e70' };
context.refreshHeroVitals(13);
assert.equal(text.SurvivalHeroHealthText, '5e77 / 1e78');
assert.equal(text.SurvivalHeroHealthFill, '50%');
console.log('ENDLESS_HEALTH_UI_PASS');
