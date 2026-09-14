const fs=require('fs'),vm=require('vm'),assert=require('assert');
const source=fs.readFileSync('panorama/src/scripts/custom_game/ability_tooltip.js','utf8');
const sizing=source.slice(source.indexOf('    function visualWindowSize('),source.indexOf('    function officialAbilityAnchor('));
const cursorCode=source.slice(source.indexOf('    function proxyCursorState('),source.indexOf('    function rectContainsCursor('));
let cursor=[0,0];const env={GameUI:{GetCursorPosition:()=>cursor}};vm.runInNewContext(sizing+cursorCode,env);
const geometry=require('../panorama/src/scripts/custom_game/geometry_remaining_5d5c1152eb.js');
for(const[w,h]of [[1280,720],[1920,1080],[2560,1440]])for(const count of [4,10,16]){
 const g=geometry(w,h,count),size=116*g.scale;
 const panel={actuallayoutwidth:116,actuallayoutheight:116,__survivalWindowWidth:size,__survivalWindowHeight:size,GetPositionWithinWindow:()=>({x:200,y:500})};
 cursor=[200+size/2,500+size/2];assert(env.proxyCursorState(panel).inside);
 cursor=[200+size/2,500+size+1];assert(!env.proxyCursorState(panel).inside,'below visual slot must not hover');
 cursor=[200+size+1,500+size/2];assert(!env.proxyCursorState(panel).inside);
 cursor=[200+size/2,500+size+25*g.scale];assert(!env.proxyCursorState(panel).inside,'health bar must not hover');
}
assert.equal(env.visualWindowSize({actuallayoutwidth:70},'width'),70,'other UI keeps native dimensions');
console.log('ABILITY_HOVER_BOUNDS_PASS: scaled icon interior/bottom/right/healthbar at 3 resolutions and 3 skill counts');
