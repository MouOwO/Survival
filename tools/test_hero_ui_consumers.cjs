"use strict";
// Reproduce the complete current author-source reference audit. This does not
// inspect generated catalogue text, compiled blobs, logs or account data.
const fs = require("node:fs"), path = require("node:path"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, ".."), source = path.join(root, "panorama/src");
const ignored = new Set(["ui_static_catalog.js", "portrait_palette.js", "monster_portrait_scenes.js"]);
const files = [];
function walk(directory) {
    for (const row of fs.readdirSync(directory, {withFileTypes:true})) {
        const filename = path.join(directory, row.name);
        if (row.isSymbolicLink()) continue;
        if (row.isDirectory()) walk(filename);
        else if (/\.(?:js|xml)$/.test(row.name) && !ignored.has(row.name)) files.push(filename);
    }
}
walk(source);
const oldEvents = new Set(["ui_hero_summon_state", "ui_hero_altar_open", "ui_hero_summon_operation_result"]);
const oldRequests = new Set(["ui_hero_summon_snapshot_request", "ui_hero_summon_request"]);
const legacyConsumers = [], legacySenders = [], shopConsumers = [];
for (const filename of files) {
    const text = fs.readFileSync(filename, "utf8"), relative = path.relative(root, filename).replace(/\\/g, "/");
    for (const match of text.matchAll(/GameEvents\.Subscribe\(\s*["']([^"']+)["']/g)) {
        if (oldEvents.has(match[1])) legacyConsumers.push(relative + ":" + match[1]);
        if (match[1] === "ui_shop_unlock_state") shopConsumers.push(relative);
    }
    for (const match of text.matchAll(/GameEvents\.SendCustomGameEventToServer\(\s*["']([^"']+)["']/g)) {
        if (oldRequests.has(match[1])) legacySenders.push(relative + ":" + match[1]);
    }
}
assert.deepEqual(legacyConsumers, [], "a new real consumer must be migrated before suppressing its old auto stream");
assert.deepEqual(legacySenders, [], "a new real requester must not silently depend on the dormant old stream");
assert.deepEqual(shopConsumers.sort(), ["panorama/src/scripts/custom_game/shop_remaining_5d5c1152eb.js", "panorama/src/scripts/custom_game/shop_ui.js"]);
const xml = fs.readFileSync(path.join(source, "layout/custom_game/survival_hud.xml"), "utf8");
assert.match(xml, /scripts\/custom_game\/shop_remaining_5d5c1152eb\.js/);
const hud = fs.readFileSync(path.join(source, "scripts/custom_game/survival_ui.js"), "utf8");
assert.match(hud, /shopApi\.SetUnlocks\(unlocks\)/, "the actual HUD unlock consumer remains live");
const native = fs.readFileSync(path.join(root, "scripts/vscripts/systems/hero_summon_projection.lua"), "utf8");
for (const ability of ["doom", "shadow_fiend", "axe", "drow_ranger", "monkey_king", "blademaster"])
    assert.ok(native.includes('"ability_summon_' + ability + '"'), "real altar ability must retain its authority");
for (const filename of ["hud_takeover.js", "combat_stats.js", "ability_tooltip.js"])
    assert.ok(fs.readFileSync(path.join(source, "scripts/custom_game", filename), "utf8").includes("SurvivalHeroSummonAvailability"), "private paid-access guard must remain connected");
console.log("HERO_UI_CONSUMERS_PASS author source files=" + files.length + " dormantHeroConsumers=0 dormantHeroSenders=0 shopConsumers=2 loadedShop=remaining nativeAltarAbilities=6 privateGuards=3; no native/FPS claim");
