const assert = require('assert');
const geometry = require('../panorama/src/scripts/custom_game/geometry_remaining_5d5c1152eb.js');
const production = require('../panorama/src/scripts/custom_game/production_progress.js');
const shortcuts = require('../panorama/src/scripts/custom_game/minimap_shortcuts.js');
for (const [w,h] of [[842,441],[962,409],[800,600],[1024,768],[1280,720],[1672,941],[1920,1080],[2560,1440],[3440,1440]]) {
    for (const count of [3,6,10]) {
        const plain=geometry(w,h,count,true,false,{wall:false,tower:false});
        const anchor=geometry(w,h,count,true,false,{wall:false,tower:false,production:true});
        const original=shortcuts.Layout(w,h,plain);
        for (const training of [false,true]) {
            const p=production.PanelGeometry(anchor,training);
            const rect={x:p.x,y:p.y,width:p.width*p.scale,height:p.height*p.scale};
            const keys=shortcuts.Layout(w,h,anchor,[rect]);
            assert.equal(keys.y,original.y,`${w}x${h}: opening production must not lift shortcuts`);
            assert.equal(keys.x,original.x);
            assert(!shortcuts.Overlaps(keys,rect));
            assert(p.x>=keys.x+keys.width+13.99);
            assert(Math.abs(p.x+rect.width+14-anchor.x)<.001);
            assert(Math.abs(p.y+rect.height-(h-6))<.001);
            assert(anchor.x+anchor.width*anchor.scale<=w-6);
        }
    }
}
const fs=require('fs'),vm=require('vm');
const source=fs.readFileSync('panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js','utf8');
let name='';
const env={Entities:{GetUnitName:()=>name},cfg:{}};
vm.runInNewContext(source.slice(source.indexOf('    function statVisibility('),source.indexOf('    function buildingPresentation(')),env);
for(name of ['building_main_city','building_research_lab','building_advanced_research_lab']) assert(env.statVisibility(1).production);
for(name of ['building_wall','building_arrow_tower','npc_dota_hero_ogre_magi']) assert(!env.statVisibility(1).production);
console.log('PRODUCTION_SHORTCUT_SPACING_PASS: nine viewport sizes, city and laboratories, stable shortcuts, aligned queue and ability row, live unit classification');
