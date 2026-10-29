'use strict';
const assert = require('node:assert/strict');
const {openRichNavigation} = require('./rich-navigation.cjs');
const layout = structuredClone(require('../../art/maps/mode_spawns/layout.json'));
layout.rich_navigation.open_rectangles = [];
const fixture = () => ({nav:Array(512*512).fill('1'), water:Array(129*129).fill('1'), heights:Array(129*129).fill('0')});
function tile(data, x, y, height=0) {
    const tx=(x+16384)/256, ty=(y+16384)/256, i=ty*129+tx;
    for(const v of [i,i+1,i+129,i+130]) {data.water[v]='0';data.heights[v]=String(height);}
    return i;
}
let data=fixture();tile(data,-2560,-10240);
assert.equal(openRichNavigation(layout,data.nav,data.water,data.heights).length,16);
assert.equal(openRichNavigation(layout,data.nav,data.water,data.heights).length,0,'idempotent');
data=fixture();const shore=tile(data,-2560,-10240);data.water[shore]='1';
assert.equal(openRichNavigation(layout,data.nav,data.water,data.heights).length,0,'shoreline');
data=fixture();const slope=tile(data,-2560,-10240);data.heights[slope]='1';
assert.equal(openRichNavigation(layout,data.nav,data.water,data.heights).length,0,'height transition');
data=fixture();tile(data,-2560,-10240,1);
assert.equal(openRichNavigation(layout,data.nav,data.water,data.heights).length,0,'raised lawn');
data=fixture();tile(data,13824,7936);
assert.equal(openRichNavigation(layout,data.nav,data.water,data.heights).length,0,'other mode');
data=fixture();tile(data,-2560,-10240);data.nav.fill('2');
assert.equal(openRichNavigation(layout,data.nav,data.water,data.heights).length,0,'special navigation flags');
data=fixture();tile(data,-2560,-10240,1);
layout.rich_navigation.open_rectangles=[[-2560,-10240,-2304,-9984]];
assert.equal(openRichNavigation(layout,data.nav,data.water,data.heights).length,0,'old road cannot override height protection');
data=fixture();layout.rich_navigation.dry_land_only=false;
assert.throws(()=>openRichNavigation(layout,data.nav,data.water,data.heights));
console.log('RICH_NAVIGATION_POLICY_PASS flat dry floor only; shoreline, slope, raised lawn, other modes protected; idempotent');
