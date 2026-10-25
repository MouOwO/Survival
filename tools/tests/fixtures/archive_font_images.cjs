'use strict';
// Explicit engine boundary fixture: deliver native image event names. This does
// not claim to emulate actual Dota loading, GPU residency, or event timing.
const assert = require('node:assert/strict');
function images(h) {
    const marker = h.root.FindChildTraverse('ArchiveFontV36Readiness');
    assert(marker && marker.IsValid(), 'Font owns its load-observation panel');
    return marker.Children();
}
function ready(h) {
    const pages = images(h);
    assert.equal(pages.length, 2);
    pages.forEach(page => page.handlers.ImageLoaded());
    return pages;
}
module.exports = {images, ready};
