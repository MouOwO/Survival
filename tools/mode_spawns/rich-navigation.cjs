'use strict';
const assert = require('node:assert/strict');
const inside = (b, p) => p[0] >= b[0] && p[0] < b[2] && p[1] >= b[1] && p[1] < b[3];

// Only the flat, dry approach floor can gain new navigation. Raised lawns,
// height transitions, water and shoreline keep their authored mask.
function openRichNavigation(layout, nav, water, heights) {
    assert.equal(nav.length, 512 * 512);
    assert.equal(water.length, 129 * 129);
    assert.equal(heights.length, 129 * 129);
    const policy = layout.rich_navigation;
    assert.equal(policy.dry_land_only, true);
    const rich = layout.modes.rich;
    if (policy.open_flat_dry_floor) assert(Number.isFinite(policy.flat_floor_height));
    const changed = [];
    for (let y = 0; y < 512; y++) for (let x = 0; x < 512; x++) {
        const index = y * 512 + x, p = [-16352 + x * 64, -16352 + y * 64];
        if (String(nav[index]) !== '1' || !inside(rich.bounds, p)) continue;
        const tx = Math.floor(x / 4), ty = Math.floor(y / 4), i = ty * 129 + tx;
        const corners = [i, i + 1, i + 129, i + 130];
        if (!corners.every(v => String(water[v]) === '0')) continue;
        const oldRoad = policy.open_rectangles.some(b => inside(b, p));
        const flatFloor = policy.open_flat_dry_floor
            && corners.every(v => Number(heights[v]) === policy.flat_floor_height);
        if (!(policy.open_flat_dry_floor ? flatFloor : oldRoad)) continue;
        nav[index] = '0'; changed.push(index);
    }
    return changed;
}
module.exports = {openRichNavigation};
