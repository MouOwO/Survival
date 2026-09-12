const assert=require('assert'),layout=require('./geometry.js');
for(const [w,h] of [[1768,992],[1280,720],[1920,1080],[1024,768],[3440,1440]]){
 const base=layout(w,h,3),px=base.x+29*base.scale,py=base.y+49*base.scale;
 for(const n of [0,1,3,4,7,10,11,12,16,24,32]){
  const g=layout(w,h,n);
  assert(Math.abs(g.x+29*g.scale-px)<1e-7,'Portrait X changes');
  assert(Math.abs(g.y+49*g.scale-py)<1e-7,'Portrait Y changes');
  assert(g.scale>0&&g.x+g.width*g.scale<=w-13.9&&g.y>=0);
  assert.equal(g.slot,116);assert.equal(g.centerWidth-g.barWidth,30);
  assert.equal(g.count,n);assert(g.x>=g.minimapSize+12);
 }
}
console.log('STAGE3_GEOMETRY_PASS: fixed portrait origin, square shared slots, bars expand together, bounds at five viewports / 0–32 abilities; geometry only, no extra gameplay skills');
