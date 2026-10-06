// Runs the production floating-gold UI with a moving camera and deterministic
// event batches. Counts API work; this is not a measurement of native FPS.
const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const source = fs.readFileSync('panorama/src/scripts/custom_game/gold_mine_income_numbers.js', 'utf8');
function scenario(events) {
    let now = 0, camera = 0, projections = 0, origins = 0, callbacks = [], handlers = {};
    const labels = [], container = {actualuiscale_x: 1, actualuiscale_y: 1};
    const $ = () => container;
    $.Schedule = (_, callback) => callbacks.push(callback);
    $.CreatePanel = () => {
        const panel = {style: {}, AddClass() {}, IsValid() { return !this.deleted; },
            DeleteAsync() { this.deleted = true; }};
        labels.push(panel); return panel;
    };
    vm.runInNewContext(source, {$,
        GameUI: {CustomUIConfig: () => ({})},
        Game: {GetGameTime: () => now, GetLocalPlayerID: () => 0,
            WorldToScreenX: x => {projections++; return x + camera;},
            WorldToScreenY: y => {projections++; return y + camera;}},
        Players: {GetSelectedEntities: () => []},
        Entities: {IsValidEntity: () => true, GetAbsOrigin: () => {origins++; return [400, 400, 0];}},
        GameEvents: {Subscribe: (event, callback) => handlers[event] = callback, SendCustomGameEventToServer() {}},
    });
    for (let i = 0; i < events; i++) handlers.survival_gold_mine_income_number({
        target_entindex: 10, amount: events === 1 ? 1000 : 1,
    });
    const initialTransform = labels[0].style.transform;
    for (let frame = 1; frame <= 30; frame++) {
        now = frame / 60; camera = frame * 8;
        const due = callbacks; callbacks = []; due.forEach(callback => callback());
    }
    assert.notEqual(labels[0].style.transform, initialTransform, 'labels still follow the moving camera');
    assert.equal(labels.reduce((total, label) => total + Number(label.text.slice(1)), 0), 1000);
    const measured = {labels: labels.length, projections, origins};
    now = 1.1;
    const due = callbacks; callbacks = []; due.forEach(callback => callback());
    assert.equal(callbacks.length, 0, 'expired labels stop their frame loop');
    assert(labels.every(label => label.deleted));
    return measured;
}
const perHit = scenario(1000), batched = scenario(1);
assert.equal(perHit.labels, 1000); assert.equal(batched.labels, 1);
assert(batched.projections < perHit.projections / 900);
console.log('HARVEST_CAMERA_PROJECTION_PASS', JSON.stringify({perHit, batched}));
