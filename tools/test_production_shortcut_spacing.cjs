const assert = require('assert');
const geometry = require('../panorama/src/scripts/custom_game/geometry_remaining_5d5c1152eb.js');
const production = require('../panorama/src/scripts/custom_game/production_progress.js');
const shortcuts = require('../panorama/src/scripts/custom_game/minimap_shortcuts.js');
for (const [w,h] of [[842,441],[962,409],[800,600],[1024,768],[1280,720],[1366,768],[1600,900],[1672,941],[1920,1080],[1920,1200],[2560,1440],[3440,1440]]) {
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
            assert(p.scale >= anchor.productionQueueScale * (training ? .75 : 1) - .000001,
                `${w}x${h}: training uses three-quarter size while research retains its readable scale`);
            if (training) {
                const research=production.PanelGeometry(anchor,false);
                assert(Math.abs(rect.width-research.width*research.scale*.75)<.001,
                    `${w}x${h}: the training panel occupies three quarters of the research panel width`);
            }
            if (p.mode === 'above') {
                assert(Math.abs(p.y+rect.height+14-(anchor.y-126*anchor.scale))<.001);
                assert(!shortcuts.Overlaps(rect,{x:anchor.x,y:anchor.y,width:anchor.width*anchor.scale,height:anchor.height*anchor.scale}));
                assert(p.y>=8 && p.x+rect.width<=w-8);
            } else {
                assert.equal(p.mode,'left');
                assert(Math.abs(p.x+rect.width+14-anchor.productionAnchorX)<.001);
                assert(Math.abs(p.y+rect.height-(h-6))<.001);
            }
            assert(anchor.x+anchor.width*anchor.scale<=w-6);
        }
    }
}
// The smaller city queue can fit beside the action row even when the full
// research panel cannot. This must use displayed size before choosing a dock.
for (const [w,h] of [[1280,720],[1366,768],[1920,1200]]) {
    const anchor=geometry(w,h,3,true,false,{production:true});
    const before=JSON.stringify(anchor);
    const training=production.PanelGeometry(anchor,true);
    const research=production.PanelGeometry(anchor,false);
    assert.equal(training.mode,'left',`${w}x${h}: the city queue fits beside its skills`);
    assert.equal(research.mode,'above',`${w}x${h}: full-size research retains its existing dock`);
    assert(Math.abs(training.scale-anchor.productionQueueScale*.75)<1e-9);
    assert(Math.abs(research.scale-anchor.productionQueueScale)<1e-9);
    assert.equal(JSON.stringify(anchor),before,'production never moves shared skill, title or buff anchors');
}

// Model the real HUD path: Panorama reports physical measurements and the root
// divides by actualuiscale before passing the logical viewport to geometry.
let scaledCases=0;
for (const [physicalWidth,physicalHeight] of [[1280,720],[1366,768],[1600,900],[1920,1080],[1920,1200],[2560,1440]]) {
    for (const uiScale of [.75,1,1.25,1.5,1.75,2]) {
        const ctx={actuallayoutwidth:physicalWidth,actuallayoutheight:physicalHeight,
            actualuiscale_x:uiScale,actualuiscale_y:uiScale};
        const w=ctx.actuallayoutwidth/ctx.actualuiscale_x,h=ctx.actuallayoutheight/ctx.actualuiscale_y;
        const anchor=geometry(w,h,3,true,false,{production:true});
        const available=anchor.productionAnchorX-anchor.productionLeft-14;
        const originalShortcuts=shortcuts.Layout(w,h,anchor);
        for (const training of [true,false]) {
            const p=production.PanelGeometry(anchor,training);
            const expectedWidth=600*anchor.productionQueueScale*(training ? .75 : 1);
            assert.equal(p.mode,expectedWidth<=available?'left':'above',
                `${physicalWidth}x${physicalHeight}@${uiScale}: actual panel footprint selects the dock`);
            const rect={x:p.x,y:p.y,width:p.width*p.scale,height:p.height*p.scale};
            const keys=shortcuts.Layout(w,h,anchor,[rect]);
            assert.equal(keys.x,originalShortcuts.x);assert.equal(keys.y,originalShortcuts.y);
            assert(!shortcuts.Overlaps(keys,rect),'scaled queue clears minimap shortcuts');
            assert(!shortcuts.Overlaps(rect,{x:anchor.x,y:anchor.y,width:anchor.width*anchor.scale,height:anchor.height*anchor.scale}),
                'scaled queue clears the native action bar');
            assert(p.x*uiScale>=8*uiScale && (p.x+rect.width)*uiScale<=physicalWidth-8*uiScale+.001);
            assert(p.y*uiScale>=8*uiScale && (p.y+rect.height)*uiScale<=physicalHeight+.001);
            if(p.mode==='above') assert(Math.abs(p.y+rect.height+14-(anchor.y-126*anchor.scale))<.001,
                'fallback retains the debuff clearance');
            scaledCases++;
        }
    }
}

const boundary=geometry(1366,768,3,true,false,{production:true});
const trainingWidth=600*boundary.productionQueueScale*.75;
for(const spare of [-.01,0,.01]) {
    const anchor={...boundary,productionLeft:100,productionAnchorX:114+trainingWidth+spare};
    const p=production.PanelGeometry(anchor,true);
    assert.equal(p.mode,spare<0?'above':'left','the exact three-quarter-size fit is the dock boundary');
    assert.equal(production.PanelGeometry(anchor,false).mode,'above','training never shrinks the research panel');
}
console.log(`PRODUCTION_DISPLAYED_FOOTPRINT_PASS: 3 training/research regressions, ${scaledCases} physical viewport/UI-scale cases, exact fit and bounded fallback`);
const fs=require('fs'),vm=require('vm');
const source=fs.readFileSync('panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js','utf8');
let name='';
const env={Entities:{GetUnitName:()=>name},cfg:{}};
vm.runInNewContext(source.slice(source.indexOf('    function statVisibility('),source.indexOf('    function buildingPresentation(')),env);
for(name of ['building_main_city','building_research_lab','building_advanced_research_lab']) assert(env.statVisibility(1).production);
for(name of ['building_wall','building_arrow_tower','npc_dota_hero_ogre_magi']) assert(!env.statVisibility(1).production);
console.log('PRODUCTION_SHORTCUT_SPACING_PASS: twelve viewport sizes, city and laboratories, stable shortcuts, readable side/above responsive queue and ability row, live unit classification');
