"use strict";
// Exercise the complete current HUD IIFE with its real combat readers and
// geometry. Native Panorama layout/clicks are mocked; this is not a screenshot.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const fixturePath = path.join(__dirname, "test_topnav_refresh_context.cjs");
let fixtureText = fs.readFileSync(fixturePath, "utf8");
const boundary = fixtureText.indexOf("function run(code) {");
assert(boundary > 0, "complete HUD fixture boundary exists");
fixtureText = fixtureText.slice(0, boundary);
// This regression uses current production geometry, not a historical checkpoint.
fixtureText = fixtureText.replace(/^const before = fs\.readFileSync[^\n]*$/m, "const before = '';");
const fixtureReturn = "return {state,counters,cfg,map,ctx,Panel,skill,health,hpFill,mpFill,warnings,sent,originals,load,advance,emit,inspect,semantic,setAbilities};";
assert(fixtureText.includes(fixtureReturn), "native fixture exposes its owned state");
fixtureText = fixtureText.replace(fixtureReturn, fixtureReturn.replace("return {", "return {env,"));
const constructorStart = "this.paneltype = type; this.id = id;";
assert(fixtureText.includes(constructorStart), "native fixture panel constructor exists");
fixtureText = fixtureText.replace(constructorStart,
    "(counters.createdPanelTypes ||= []).push(type); " + constructorStart);
const harness = Function("require", "__dirname", "process", fixtureText + "\nreturn {fixture, source};")
    (require, __dirname, {argv: ["node", "worker_multiselect_layout_fixture"]});

function xy(panel) {
    assert(panel && panel.style.position, "panel has explicit geometry");
    const values = panel.style.position.split(/\s+/).slice(0, 2).map(parseFloat);
    assert(values.every(Number.isFinite), "position uses finite native pixel values");
    return values;
}
function rect(panel, geometry) {
    const [x, y] = xy(panel);
    const width = parseFloat(panel.style.width), height = parseFloat(panel.style.height);
    assert(Number.isFinite(width) && Number.isFinite(height), "panel has fixed dimensions");
    return {x: geometry.x + x * geometry.scale, y: geometry.y + y * geometry.scale,
        bottom: geometry.y + (y + height) * geometry.scale, width, height};
}
function near(actual, expected, message) {
    assert(Math.abs(actual - expected) < 0.001, message + ": " + actual + " vs " + expected);
}

const results = [];
for (const [width, height, uiScale] of [[1280, 720, 1], [1920, 1080, 1], [2560, 1440, 1], [2560, 1440, 1.25]]) {
    const f = harness.fixture(harness.source);
    f.ctx.actuallayoutwidth = width;
    f.ctx.actuallayoutheight = height;
    f.ctx.actualuiscale_x = f.ctx.actualuiscale_y = uiScale;
    const viewportHeight = height / uiScale;
    let selectedCount = 1;
    const applyCalls = [];
    f.cfg.SurvivalMultiSelectionPortraits = {
        IsActive: () => selectedCount > 1,
        Apply(group, size, portraitHeight) { applyCalls.push({group, size, portraitHeight}); }
    };
    f.env.Entities.GetUnitName = id => id === 22 ? "npc_survival_lumberjack_1" : "npc_dota_hero_axe";
    f.env.Entities.IsHero = id => id !== 22;
    f.env.Entities.IsBuilding = () => false;
    f.setAbilities(22, [2201]);
    f.state.names[2201] = "ability_fuse_lumberjack_1";
    // Model the native sibling identity without replacing the adapter's own
    // paging/click tests in test_multiselect_portraits.cjs.
    f.map.multiunit = new f.Panel("Panel", "multiunit", f.map.center_block);
    const nativeSkill = f.map.abilities.children[0];
    const nativeClickTarget = nativeSkill.FindChildTraverse("AbilityButton");
    const originalClick = () => "native-click-preserved";
    nativeClickTarget.SetPanelEvent("onactivate", originalClick);
    const originalGridParent = f.map.multiunit.GetParent();
    f.advance(2000);

    function owned(id) {
        const panel = f.ctx.GetParent().FindChildTraverse(id);
        assert(panel, "owned panel exists: " + id);
        return panel;
    }
    function sample(count) {
        selectedCount = count;
        f.state.unit = 22;
        f.emit("dota_player_update_selected_unit", {PlayerID: 0});
        f.advance(100);
        assert.deepEqual(f.warnings, [], "complete IIFE renders worker selection without warnings");
        const hud = f.inspect(), g = hud.geometry;
        assert.equal(hud.nativeReady, true);
        assert.equal(g.height, 260, "single and multiple workers reserve the same compact HUD height");
        near(g.y + g.height * g.scale, viewportHeight, "worker HUD reaches the viewport bottom");
        const right = rect(owned("HandoffCenterPlate"), g);
        near(right.bottom, viewportHeight, "action plate reaches the viewport bottom");
        const abilityY = g.y + xy(f.map.AbilitiesAndStatBranch)[1] * g.scale;
        const attackY = g.y + xy(owned("HandoffStatRow_attack"))[1] * g.scale;
        const speedY = g.y + xy(owned("HandoffStatRow_attack_speed"))[1] * g.scale;
        assert.equal(owned("HandoffStatRow_attack").visible, true);
        assert.equal(owned("HandoffStatRow_attack_speed").visible, true);
        assert.equal(owned("HandoffPortraitFrame").style.visibility, "collapse", "ornamental border stays hidden for workers");
        const latestApply = applyCalls.at(-1);
        assert.strictEqual(latestApply.group, f.map.PortraitGroup);
        assert.equal(latestApply.size, 264, "native portrait camera retains its square width");
        for (const id of ["PortraitContainer", "portraitHUD"]) {
            assert.equal(f.map[id].style.width, "264px");
            assert.equal(f.map[id].style.height, "264px", "native camera canvas is not stretched");
        }
        if (count > 1) {
            const plate = owned("HandoffWorkerPortraitPlate"), left = rect(plate, g);
            assert.equal(plate.style.visibility, "visible");
            assert.equal(plate.style.backgroundColor, "#071f29", "unused portrait rows have a solid background");
            assert.equal(plate.style.overflow, "clip");
            assert.equal(plate.style.borderRadius, "14px 14px 0px 0px");
            near(left.y, right.y, "portrait and action plates share their top edge");
            near(left.bottom, right.bottom, "portrait and action plates share their bottom edge");
            assert.equal(left.width, 294);
            assert.equal(left.height, 237);
            assert.deepEqual(xy(f.map.PortraitGroup), [29, 23]);
            assert.equal(f.map.PortraitGroup.style.height, "237px", "portrait grid uses the full filled height");
            assert.equal(latestApply.portraitHeight, 237, "adapter receives the full portrait grid height");
        }
        assert.strictEqual(f.map.abilities.children[0], nativeSkill, "native skill identity stays intact");
        assert.strictEqual(nativeClickTarget.events.onactivate, originalClick, "native skill activation is preserved");
        assert.strictEqual(f.map.multiunit.GetParent(), originalGridParent, "native portrait grid is never reparented");
        return {count, abilityY, attackY, speedY, height: g.height, scale: g.scale, rightTop: right.y, rightBottom: right.bottom};
    }

    const first = sample(1);
    for (const count of [2, 4, 9, 12, 13, 2, 1, 13, 1]) {
        const current = sample(count);
        for (const key of ["abilityY", "attackY", "speedY", "height", "scale", "rightTop", "rightBottom"])
            near(current[key], first[key], "selection size does not move " + key);
        results.push({viewport: [width, height], uiScale, ...current});
    }

    sample(13);
    const plate = owned("HandoffWorkerPortraitPlate"), childCount = f.counters.createdPanelTypes.length;
    const portraitBeforeRepair = {...f.map.PortraitGroup.style};
    const cameraBeforeRepair = {...f.map.portraitHUD.style};
    // Reproduce engine-written group dimensions; the bounded repair must use
    // the same compact group as the selection-change path.
    f.map.PortraitGroup.style.position = "29px 49px 0px";
    f.map.PortraitGroup.style.height = "264px";
    const schedulesBefore = f.counters.schedules;
    f.advance(1100);
    assert.deepEqual(f.map.PortraitGroup.style, portraitBeforeRepair, "one-second repair preserves the compact 237px worker group");
    assert.deepEqual(f.map.portraitHUD.style, cameraBeforeRepair, "repair retains the original square portrait camera");
    assert.equal(f.counters.schedules - schedulesBefore, 11, "worker presentation shares the existing 100ms HUD tick");
    assert.equal(f.counters.createdPanelTypes.length, childCount, "steady selection and repair reuse the existing plate and slices");
    assert.strictEqual(owned("HandoffWorkerPortraitPlate"), plate);
    assert.deepEqual(f.warnings, []);

    selectedCount = 1;
    f.state.unit = 7;
    f.emit("dota_player_update_selected_unit", {PlayerID: 0});
    f.advance(100);
    assert.equal(owned("HandoffPortraitFrame").style.visibility, "visible", "hero restores the original portrait frame");
    assert.equal(plate.style.visibility, "collapse", "hero hides the worker-specific filled plate");
    assert.deepEqual(xy(f.map.PortraitGroup), [29, 49], "hero restores its original portrait anchor");
    assert.equal(f.map.PortraitGroup.style.height, "264px");
    assert.equal(applyCalls.at(-1).portraitHeight, undefined, "hero uses the original square adapter contract");
    assert(!f.counters.createdPanelTypes.some(type => /scene|portrait/i.test(type)), "selection rendering adds no 3D scene or portrait panels");
    assert.deepEqual(f.warnings, []);
}
console.log("WORKER_MULTISELECT_LAYOUT_PASS: complete current HUD IIFE; single/multiple 1/2/4/9/12/13; 3 viewports and UI scaling; fixed ability/stats height; filled plates flush to viewport; square camera/click identity; bounded repair; original hero frame restored; no new scene/timer loop; " + results.length + " transitions");
