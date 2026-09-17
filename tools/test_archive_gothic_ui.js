"use strict";
// Reuse the archive's real snapshot/click harness, then exercise skin-specific states.
const fs = require("fs"), vm = require("vm");
vm.runInNewContext(fs.readFileSync("tools/test_archive_ui.js", "utf8") + `
panels.ArchiveTab_building.events.onactivate();receive(Object.assign(packet(19,"building",1,1,buildingRows),{buildings:{faith:6000,earned_today:4000,daily_cap:4000,per_clear:400}}));
assert.equal(panels.ArchiveFaith.text, "信仰值：6000");
assert(!panels.ArchiveFaith.classes.has("ArchiveHidden"));
assert(panels.ArchiveContent.classes.has("ArchiveBuildingPage"));
const ownedArt = panels.ArchiveGrid.children[0].children[0];
assert.equal(ownedArt.children[0].itemname, "item_octarine_core");
const maxArt = panels.ArchiveGrid.children[1].children[0];
assert(maxArt.classes.has("ArchiveMaxed"));
assert(!maxArt.classes.has("ArchiveCompleted"), "maxed buildings keep their artwork lit");
receive(Object.assign(packet(20,"building",1,1,[
    {id:"building_09",name:"雷神之锤",count:0,level:0,target:5,cost:3000,can_upgrade:0},
    {id:"future_building",name:"新增建筑",count:0,target:5,cost:3000,can_upgrade:0}
]), {buildings:{faith:0,earned_today:0,daily_cap:4000,per_clear:400}}));
assert.equal(panels.ArchiveFaith.text, "信仰值：0", "zero balance is shown");
const lockedArt = panels.ArchiveGrid.children[0].children[0];
assert(lockedArt.classes.has("ArchiveUnowned"));
assert.equal(lockedArt.children[0].itemname, "item_mjollnir");
assert(panels.ArchiveGrid.children[1].children[0].classes.has("KitArt_03"), "unknown definitions keep a fallback");
panels.ArchiveTab_fishing.events.onactivate();
assert(panels.ArchiveFaith.classes.has("ArchiveHidden"), "balance is hidden immediately when leaving buildings");
assert.equal(panels.ArchiveFaith.text, "");
assert.equal(panels.ArchiveHint.text, "", "previous page hints are cleared during loading");
assert(!panels.ArchiveContent.classes.has("ArchiveBuildingPage"));
console.log("ARCHIVE_GOTHIC_UI_PASS: item art, maxed/unowned states, fallback, faith balance and page reset");
`, { require, console });
