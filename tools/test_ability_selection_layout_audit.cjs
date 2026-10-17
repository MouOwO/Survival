"use strict";
// Read-only audit of the complete loaded topnav IIFE, using the existing real
// combat enumeration helpers/native fixture. Desired coordinates are not a
// Source 2 screenshot or a native layout measurement.
const fs=require("fs"),path=require("path"),assert=require("assert");
const fixturePath=path.join(__dirname,"test_topnav_refresh_context.cjs");
let fixtureText=fs.readFileSync(fixturePath,"utf8");
const end=fixtureText.indexOf("function run(code) {");
assert(end>0,"existing full-script fixture boundary must exist");
fixtureText=fixtureText.slice(0,end);
const ownedReturn="return {state,counters,cfg,map,ctx,Panel,skill,health,hpFill,mpFill,warnings,sent,originals,load,advance,emit,inspect,semantic,setAbilities};";
assert(fixtureText.includes(ownedReturn));
// Expose the native mock identity table, never alter a production function.
fixtureText=fixtureText.replace(ownedReturn,ownedReturn.replace("return {","return {env,"));
const harness=Function("require","__dirname","process",fixtureText+"\nreturn {fixture,source,before};")
    (require,__dirname,{argv:["node","fixture"]});

const preserved=JSON.parse(fs.readFileSync("output/ui_refresh_audit_20261013/ability_anchor_checkpoint.json","utf8"));
const originalGeometry=require(path.resolve(preserved.checkpoint,"geometry_remaining_5d5c1152eb.js"));
const originalTopnav=fs.readFileSync(path.join(preserved.checkpoint,"topnav_remaining_5d5c1152eb.js"),"utf8");
function run(code){
    const f=harness.fixture(code), samples=[];
    f.cfg.HandoffGeometry=originalGeometry;
    f.ctx.actuallayoutwidth=1672;f.ctx.actuallayoutheight=941;
    f.ctx.actualuiscale_x=f.ctx.actualuiscale_y=1;
    const names={7:"npc_dota_hero_axe",20:"building_arrow_tower",21:"building_arrow_tower",22:"npc_survival_lumberjack_1",23:"building_advanced_research_lab"};
    f.env.Entities.GetUnitName=id=>names[id]||"npc_dota_hero_axe";
    f.env.Entities.IsHero=id=>/^npc_dota_hero_/.test(names[id]||"");
    f.env.Entities.IsBuilding=id=>/^building_/.test(names[id]||"");
    for(let i=8;i<12;i++)f.skill("Ability"+i);
    function skills(id,count,worker=false){const ids=Array.from({length:count},(_,i)=>id*100+i);
        f.setAbilities(id,ids);if(worker)ids.forEach((ability,i)=>f.state.names[ability]="ability_fuse_lumberjack_"+(i+1));}
    skills(7,4);skills(20,4);skills(21,7);skills(22,1,true);skills(23,10);
    function sample(label,unit){f.state.unit=unit;f.emit("dota_player_update_selected_unit",{PlayerID:0});f.advance(100);
        const current=f.inspect(),g=current.geometry,branch=f.map.AbilitiesAndStatBranch;
        const branchX=parseFloat(branch.style.position);
        samples.push({label,unit,abilityCount:current.abilities.length,scale:g.scale,
            hudX:g.x,hudWidth:g.width,heroWidth:g.heroWidth,centerWidth:g.centerWidth,
            desiredFirstAbilityX:g.x+branchX*g.scale,
            rowPosition:f.map.abilities.style.position,rowWidth:f.map.abilities.style.width,
            branchPosition:branch.style.position,branchWidth:branch.style.width,
            nativeParent:f.map.abilities.GetParent().id,
            slotWidths:f.map.abilities.children.map(p=>({id:p.id,width:p.style.width,visibility:p.visible===false||p.style.visibility==="collapse"?"collapse":"visible"}))});
        assert.deepEqual(f.warnings,[]);assert.strictEqual(f.map.abilities.GetParent(),f.map.AbilitiesAndStatBranch);
    }
    f.advance(1000);
    for(let round=0;round<5;round++)for(const [label,unit] of [["hero4",7],["tower4",20],["tower7",21],["worker1",22],["research10",23],["hero4_restored",7]])sample(label,unit);
    // Reproduce new selection arriving before its authoritative native skill list.
    skills(23,0);sample("research_native_slots_pending",23);skills(23,10);sample("research_native_slots_arrive",23);
    // Passive hotkey metadata has no effect on the parent row geometry.
    sample("hero4_before_passive",7);f.state.runtime[700].passive=true;sample("hero4_after_passive",7);
    return {samples,warnings:f.warnings};
}
const current=run(originalTopnav),baseline=run(harness.before);
assert.deepEqual(current.samples,baseline.samples,"the preserved pre-enumeration-cache HUD has exactly the same layout shifts");
const first=current.samples.slice(0,6);
assert(Math.abs(first[0].desiredFirstAbilityX-first[1].desiredFirstAbilityX)>50,"hero-to-tower moves the row by its current geometry policy");
assert.notEqual(first[1].desiredFirstAbilityX,first[2].desiredFirstAbilityX,"different tower skill counts re-center the entire row");
for(let round=1;round<5;round++)assert.deepEqual(current.samples.slice(round*6,round*6+6),first,"repeated selection has deterministic coordinates without accumulating native-parent drift");
const pending=current.samples.find(x=>x.label==="research_native_slots_pending"),arrive=current.samples.find(x=>x.label==="research_native_slots_arrive");
assert.notEqual(pending.desiredFirstAbilityX,arrive.desiredFirstAbilityX,"late actual skill replication causes a second layout position update");
const [passiveBefore,passiveAfter]=current.samples.slice(-2);
assert.equal(passiveBefore.desiredFirstAbilityX,passiveAfter.desiredFirstAbilityX,"passive hotkey suppression does not alter native row coordinates");
assert.equal(passiveBefore.branchWidth,passiveAfter.branchWidth);
const evidence={scope:"Preserved complete pre-fix topnav IIFEs and actual combat enumeration helpers in VM; desired assigned coordinate math only, not a native screenshot or FPS attribution",
    viewport:[1672,941],production_changed:false,old_and_current_layout_identical:true,
    deterministic_repeat_rounds:5,first_round:first,
    pending_native_skill_list:pending,arrived_native_skill_list:arrive,
    passive_hotkey_geometry_unchanged:true,all_samples:current.samples};
fs.mkdirSync("output/ui_refresh_audit_20261013",{recursive:true});
fs.writeFileSync("output/ui_refresh_audit_20261013/ability_selection_layout_vm.json",JSON.stringify(evidence,null,2)+"\n");
console.log("ABILITY_SELECTION_LAYOUT_AUDIT_PASS "+JSON.stringify(first.map(({label,abilityCount,desiredFirstAbilityX})=>({label,abilityCount,desiredFirstAbilityX})))+"; late research "+pending.desiredFirstAbilityX+" -> "+arrive.desiredFirstAbilityX+"; preserved pre-fix geometry audit reproduced, no production changes");
