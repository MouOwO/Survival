"use strict";
const fs=require("fs"),path=require("path"),assert=require("assert");
const manifest=JSON.parse(fs.readFileSync("output/ui_refresh_audit_20261013/ability_anchor_checkpoint.json","utf8"));
const base=path.resolve(manifest.checkpoint),dir="panorama/src/scripts/custom_game/";
const currentTopnav=fs.readFileSync(dir+"topnav_remaining_5d5c1152eb.js","utf8");
const currentProduction=fs.readFileSync(dir+"production_progress.js","utf8");
const oldTopnav=fs.readFileSync(path.join(base,"topnav_remaining_5d5c1152eb.js"),"utf8");
const oldProduction=fs.readFileSync(path.join(base,"production_progress.js"),"utf8");
const geometry=require("../"+dir+"geometry_remaining_5d5c1152eb.js");
const oldGeometry=require(path.join(base,"geometry_remaining_5d5c1152eb.js"));
const production=require("../"+dir+"production_progress.js");
const oldModel=require(path.join(base,"production_progress.js"));
const shortcuts=require("../"+dir+"minimap_shortcuts.js");
const negative=process.argv.includes("--negative-control");
const testedGeometry=negative?oldGeometry:geometry;
const testedTopnav=negative?oldTopnav:currentTopnav;
const testedProduction=negative?oldProduction:currentProduction;
const testedModel=negative?oldModel:production;
let fixtureText=fs.readFileSync(path.join(__dirname,"test_topnav_refresh_context.cjs"),"utf8");
fixtureText=fixtureText.slice(0,fixtureText.indexOf("function run(code) {"));
const ownedReturn="return {state,counters,cfg,map,ctx,Panel,skill,health,hpFill,mpFill,warnings,sent,originals,load,advance,emit,inspect,semantic,setAbilities};";
assert(fixtureText.includes(ownedReturn));fixtureText=fixtureText.replace(ownedReturn,ownedReturn.replace("return {","return {env,"));
const harness=Function("require","__dirname","process",fixtureText+"\nreturn {fixture};")(require,__dirname,{argv:["node","fixture"]});
const close=(actual,expected,label,tolerance=.002)=>assert(Math.abs(actual-expected)<=tolerance,label+`: ${actual} != ${expected}`);
const widths=[[800,600],[842,441],[962,409],[1024,768],[1280,720],[1366,768],[1600,900],[1672,941],[1920,1080],[2560,1440],[3440,1440],[800,300],[800,240],[800,140],[640,360]];
const modes=[{worker:true,lumberjack:true},{worker:true,repairer:true},{building:true,tower:true},{building:true,production:true},{monster:true},{}];
let checks=0;const geometryRows=[];
for(const [w,h]of widths){
    const oldHero=oldGeometry(w,h,4,false,false,{}),expected=oldHero.x+503*oldHero.scale;
    for(const mode of modes)for(const count of [0,1,4,7,10,16,32]){
        const g=testedGeometry(w,h,count,!!mode.building,false,mode);
        const offset=g.actionOffset===undefined?g.heroWidth+10:g.actionOffset;
        close(g.x+offset*g.scale,expected,`${w}x${h}/${JSON.stringify(mode)}/${count} stable shared skill origin`);
        assert(g.scale>0&&Number.isFinite(g.scale));
        assert(g.x+g.width*g.scale<=w-13.99,"right-side capacity fits the viewport");
        if(!mode.building&&!mode.worker){
            close(g.x+29*g.scale,oldHero.x+29*oldHero.scale,"accepted selected-hero portrait x remains unchanged");
            close(g.y+49*g.scale,oldHero.y+49*oldHero.scale,"accepted selected-hero portrait y remains unchanged");
        }
        if(mode.production)for(const training of [false,true]){
            const q=testedModel.PanelGeometry(g,training);assert(q);
            const rect={x:q.x,y:q.y,width:q.width*q.scale,height:q.height*q.scale};
            const originalKeys=shortcuts.Layout(w,h,g),keys=shortcuts.Layout(w,h,g,[rect]);
            close(keys.x,originalKeys.x,"production preserves shortcut x");close(keys.y,originalKeys.y,"production preserves shortcut y");
            assert(!shortcuts.Overlaps(keys,rect));
            assert(!shortcuts.Overlaps(rect,{x:g.x,y:g.y,width:g.width*g.scale,height:g.height*g.scale}));
            assert(q.x>=8&&q.y>=8&&q.x+rect.width<=w-7.99&&q.y+rect.height<=h-5.99);
            if(q.mode==="above")close(q.y+rect.height+14,g.y-126*g.scale,"above attachment clears title/buff/debuff attachments");
            else close(q.x+rect.width+14,g.productionAnchorX,"side attachment uses stable production origin");
            close(q.scale,g.productionQueueScale,"all tested heights retain full readable queue scale");
            if(q.scrollable){assert.equal(q.contentHeight,training?426:270);assert(q.height<q.contentHeight);}
            for(const top of [-126,-82,-50])assert(!shortcuts.Overlaps(rect,{x:g.actionX,y:g.y+top*g.scale,width:Math.max(48,(g.centerWidth-20)*g.scale),height:(top===-50?48:40)*g.scale}),"queue clears existing title/buff/debuff rectangle");
            if(count===10)geometryRows.push({viewport:[w,h],training,skillX:expected,queueMode:q.mode,queueScale:q.scale,scrollable:!!q.scrollable,queueRect:rect});
        }
        checks++;
    }
}

function fixture(topnav,geometryFn,productionCode,viewport){
    const f=harness.fixture(topnav),[w,h,sx=1,sy=sx]=viewport;
    f.Panel.prototype.RemoveAndDeleteChildren=function(){for(const child of this.children.slice())child.DeleteAsync();};
    f.cfg.HandoffGeometry=geometryFn;
    f.ctx.actuallayoutwidth=w;f.ctx.actuallayoutheight=h;f.ctx.actualuiscale_x=sx;f.ctx.actualuiscale_y=sy;
    const names={7:"npc_dota_hero_axe",20:"building_arrow_tower",21:"building_arrow_tower",22:"npc_survival_lumberjack_1",23:"building_advanced_research_lab",24:"building_main_city",25:"npc_survival_repairer"};
    f.env.Entities.GetUnitName=id=>names[id]||"npc_dota_hero_axe";
    f.env.Entities.IsHero=id=>/^npc_dota_hero_/.test(names[id]||"");
    f.env.Entities.IsBuilding=id=>/^building_/.test(names[id]||"");
    for(let i=8;i<32;i++)f.skill("Ability"+i);
    function skills(id,count,kind){const ids=Array.from({length:count},(_,i)=>id*100+i);f.setAbilities(id,ids);
        ids.forEach((ability,i)=>{f.state.names[ability]=kind==="worker"?"ability_fuse_lumberjack_"+(i+1):kind==="repairer"?"ability_repairer_suicide":kind==="research"?"ability_research_group_"+i:"ability_"+ability;});}
    skills(7,4);skills(20,4);skills(21,7);skills(22,1,"worker");skills(23,10,"research");skills(24,4);skills(25,1,"repairer");
    new f.Panel("Panel","SurvivalProductionPanel",f.ctx);new f.Panel("Panel","SurvivalResearchAutoMarkers",f.ctx);
    const getTable=f.env.CustomNetTables.GetTableValue;
    f.env.CustomNetTables.GetTableValue=(table,key)=>table==="survival_ability_runtime"?f.state.runtime[key]:getTable(table,key);
    require("vm").runInContext(productionCode,f.env,{filename:"complete_production.js"});
    f.advance(1000);
    function snapshot(unit,data,seq=100){f.emit("ui_selected_unit_stats_snapshot",{success:1,player_id:0,entindex:unit,refresh_sequence:seq,...data});}
    const options=Array.from({length:5},(_,i)=>({training_id:"worker_"+(i+1),level:i+1,count:0,max_count:3,available:1,prerequisite_met:1,cost_wood:10}));
    snapshot(24,{training:{options,active_job:{training_id:"worker_1",started_at:0,finish_at:100,duration:100},queued:Array.from({length:6},(_,i)=>({level:i+2})),queue_capacity:7}});
    const queued=Array.from({length:6},(_,i)=>({job_id:"job_"+i,technology_group:"g"+i,ability_name:"ability_research_group_"+i,target_level:i+1}));
    snapshot(23,{research:{researching:0,queued,queue_capacity:7,auto_research:{g0:1}}});
    f.state.runtime[2300].technology_group="g0";
    function select(unit){f.state.unit=unit;f.emit("dota_player_update_selected_unit",{PlayerID:0});f.advance(100);return capture();}
    function capture(){const info=f.inspect(),g=info.geometry;
        const outer=f.map.lower_hud,branch=f.map.AbilitiesAndStatBranch;
        const outerX=parseFloat(outer.style.position),branchX=parseFloat(branch.style.position);
        const writtenScale=Number(/^scale3d\(([^,]+)/.exec(outer.style.transform)[1]);
        const q=f.ctx.FindChildTraverse("SurvivalProductionPanel");
        return {unit:f.state.unit,abilities:info.abilities,firstX:(outerX+branchX*writtenScale)*sx,
            portraitX:(outerX+29*writtenScale)*sx,geometry:g,
            panelVisible:q.visible,panelPosition:q.style.position,panelWidth:q.__survivalWindowWidth,
            panelHeight:q.__survivalWindowHeight,rows:f.map.abilities.children.map(p=>({id:p.id,width:p.style.width,
                visibility:p.visible===false||p.style.visibility==="collapse"?"collapse":"visible",opacity:p.style.opacity,hittest:p.hittest})),
            queueText:f.ctx.FindChildTraverse("ProductionQueue")?.text,
            progress:f.ctx.FindChildTraverse("ProductionProgressFill")?.style.width,
            slots:Array.from(f.cfg.SurvivalProductionHUD.Inspect().slots)};}
    return {...f,skills,snapshot,select,capture,queued,options};
}
const scenarios=[];
for(const viewport of [[800,140],[800,240],[800,300],[640,360],[800,600],[1024,768],[1280,720],[1672,941],[1920,1080],[2560,1440,1.25]]){
    const f=fixture(testedTopnav,testedGeometry,testedProduction,viewport),trace=[];
    const old=fixture(oldTopnav,oldGeometry,oldProduction,viewport);
    const reference=f.select(7).firstX;
    old.select(7); // Match the original renderer's game-time advancement.
    for(let round=0;round<3;round++)for(const unit of [7,20,21,22,23,24,25,7]){
        const a=f.select(unit),b=old.select(unit);close(a.firstX,reference,"complete IIFE repeated selection preserves first slot",.015);
        for(const key of ["abilities","rows","panelVisible","queueText","progress","slots"])
            assert.deepEqual(a[key],b[key],"full old/new render/business data unchanged: "+key);
        assert.strictEqual(f.map.abilities.GetParent(),f.map.AbilitiesAndStatBranch,"native ability parent is never moved");trace.push(a);
    }
    f.skills(23,0,"research");const pending=f.select(23);close(pending.firstX,reference,"pending empty native list retains action origin",.015);
    f.skills(23,32,"research");f.emit("dota_ability_changed",{PlayerID:0});f.advance(100);const full=f.capture();
    close(full.firstX,reference,"actual 32-skill arrival cannot move the first slot",.015);assert.equal(full.abilities.length,32);
    f.state.completed.add(2301);f.advance(100);const completed=f.capture();
    close(completed.firstX,reference,"completed skill compacts inside stable row",.015);
    assert.equal(completed.rows[1].width,"0px");assert(!completed.abilities.includes("ability_research_group_1"));
    assert.equal(completed.rows[1].hittest,false);f.state.completed.delete(2301);f.advance(100);
    assert.equal(f.capture().rows[1].width,"116px");
    const scene=f.select(23);assert.equal(scene.queueText,"等待 6/6");
    const marker=f.ctx.FindChildTraverse("ProductionResearchAuto0");
    assert(marker&&marker.visible,"existing automatic research marker remains visible");
    close(parseFloat(marker.style.position)*(viewport[2]||1),reference,"automatic research marker aligns with the actual first slot",.015);
    const q=f.ctx.FindChildTraverse("SurvivalProductionPanel"),xy=String(q.style.position).split(/\s+/).map(parseFloat);
    const model=testedModel.PanelGeometry(scene.geometry,false);close(xy[0],model.x,"actual queue x matches model");close(xy[1],model.y,"actual queue y matches model");
    close(q.__survivalWindowWidth,model.width*model.scale*(viewport[2]||1),"exact world-overlay occlusion width");
    close(q.__survivalWindowHeight,model.height*model.scale*(viewport[3]||viewport[2]||1),"exact world-overlay occlusion viewport height");
    assert.equal(q.style.overflow,model.scrollable?"squish scroll":"clip","short-height viewport scrolls controls at readable scale");
    if(model.scrollable){assert.equal(Number.parseFloat(q.style.height),model.height);assert.equal(model.contentHeight,270);}
    const outer=f.map.lower_hud,rootXY=String(outer.style.position).split(/\s+/).map(parseFloat);
    const nativeScale=Number(/^scale3d\(([^,]+)/.exec(outer.style.transform)[1]);
    const queueRect={x:xy[0],y:xy[1],width:model.width*model.scale,height:model.height*model.scale};
    for(const node of [f.map.buffs,f.map.debuffs]){const pos=String(node.style.position).split(/\s+/).map(parseFloat);
        const rect={x:rootXY[0]+pos[0]*nativeScale,y:rootXY[1]+pos[1]*nativeScale,width:parseFloat(node.style.width)*nativeScale,height:parseFloat(node.style.height)*nativeScale};
        assert(!shortcuts.Overlaps(queueRect,rect),"actual native buff/debuff assignment is clear of queue viewport");}
    const title=f.ctx.FindChildTraverse("HandoffBuildingTitleBounds"),titleXY=String(title.style.position).split(/\s+/).map(parseFloat);
    const titleScale=Number(/^scale3d\(([^,]+)/.exec(title.style.transform)[1]);
    assert(!shortcuts.Overlaps(queueRect,{x:titleXY[0],y:titleXY[1],width:parseFloat(title.style.width)*titleScale,height:parseFloat(title.style.height)*titleScale}),"actual title assignment is clear of queue viewport");
    f.ctx.FindChildTraverse("ProductionQueueSlot0").events.onactivate();
    assert.equal(f.sent.at(-1).name,"ui_research_cancel_request");assert.equal(f.sent.at(-1).payload.source_entindex,23);assert.equal(f.sent.at(-1).payload.job_id,"job_0");
    f.select(24);f.ctx.FindChildTraverse("ProductionTrainingSlot0").events.onactivate();
    assert.equal(f.sent.at(-1).name,"ui_worker_train_request");assert.equal(f.sent.at(-1).payload.source_entindex,24);assert.equal(f.sent.at(-1).payload.training_id,"worker_1");
    f.snapshot(24,{training:{options:f.options.map((entry,i)=>({...entry,count:i===0?3:0})),queued:[],queue_capacity:7}},101);
    assert.deepEqual(f.capture().slots,["worker_2","worker_3","worker_4","worker_5"]);
    f.select(7);assert.equal(f.capture().panelVisible,false,"leaving a production source hides the queue");
    f.select(23);f.load();f.advance(500);close(f.capture().firstX,reference,"complete HUD hot reload preserves fixed origin",.015);
    const previousProduction=f.cfg.SurvivalProductionGeneration;
    require("vm").runInContext(testedProduction,f.env,{filename:"complete_production_reload.js"});
    assert.equal(f.cfg.SurvivalProductionGeneration,previousProduction+1);
    f.snapshot(23,{research:{researching:0,queued:f.queued,queue_capacity:7,auto_research:{g0:1}}},200);
    f.select(23);close(f.capture().firstX,reference,"production reload and private snapshot keep fixed origin",.015);
    assert.equal(f.capture().queueText,"等待 6/6");assert(f.capture().panelVisible);
    assert.deepEqual(f.warnings,[]);
    // Authoritative resource snapshots and the normal 10Hz refresh keep dynamic
    // values active without rewriting stable position/width each tick.
    let positionWrites=0,widthWrites=0;for(const panel of [f.map.lower_hud,f.map.AbilitiesAndStatBranch,f.map.abilities]){
        const nativeStyle=panel.style;panel.style=new Proxy(nativeStyle,{set(target,key,value){if(key==="position")positionWrites++;if(key==="width")widthWrites++;target[key]=value;return true;}});}
    for(let i=0;i<20;i++){f.emit("survival_ui_private_snapshot",{sequence:2000+i,resources:{wood:100+i,gold:50,population:1,max_population:20}});f.advance(100);}
    assert.equal(positionWrites,0,"static row positions are not rewritten on each resource/timer tick");assert.equal(widthWrites,0);
    scenarios.push({viewport,referenceFirstX:reference,repeatSelections:trace.length,pendingX:pending.firstX,full32X:full.firstX,
        productionMode:model.mode,scrollable:!!model.scrollable,titleBuffDebuffClear:true,exactOcclusion:true,hotReload:true,completedAndTrainingRollover:true,stablePositionWrites:positionWrites,stableWidthWrites:widthWrites});
}
const evidence={scope:"Complete actual topnav and production IIFEs plus actual combat enumeration helpers in VM, pure geometry over 15 viewports including 140px height without skipped cases; mocked native assignments, not Source 2 pixels or FPS",
    checkpoint:manifest.checkpoint,productionChanged:["geometry_remaining_5d5c1152eb.js","topnav_remaining_5d5c1152eb.js","production_progress.js"],
    geometryChecks:checks,geometryRows,scenarios,baselineNegativeControl:"Original full source reproduces cross-selection horizontal movement and fails the same stable-origin assertion",
    visualDifference:"At insufficient left-column width only the existing production queue moves above the action bar, preserving its readable preferred scale and title/buff/debuff gap; an insufficient vertical extent scrolls the existing controls within a precisely bounded viewport; full HUD layout/portrait/shortcut anchors are retained"};
if(process.argv.includes("--write-evidence"))fs.writeFileSync("output/ui_refresh_audit_20261013/ability_anchor_vm_evidence.json",JSON.stringify(evidence,null,2)+"\n");
console.log("ABILITY_ANCHOR_STABILITY_PASS: "+checks+" geometry cases, "+scenarios.length+" complete-IIFE viewports; selection/0->32/completion/hot reload fixed first slot, original portrait anchor, readable side/above queue, exact occlusion and preserved input; zero stable row position/width rewrites. VM counts only.");
