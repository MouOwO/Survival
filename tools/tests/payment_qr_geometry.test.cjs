"use strict";
const fs = require("node:fs"), vm = require("node:vm");
const test = require("node:test"), assert = require("node:assert/strict");
const source = fs.readFileSync("panorama/src/scripts/custom_game/payment_test.js", "utf8");
// Execute the actual nested renderer and its actual layout helpers, without financial requests.
const start = source.indexOf("    function drawQR(matrix) {"), end = source.indexOf("    function render() {", start);
assert(start >= 0 && end > start);
const helpers = ["valid", "paint", "rect"].map(name => {
    const line = source.split(/\r?\n/).find(value => value.trim().startsWith("function " + name + "("));
    assert(line, "Missing actual renderer helper " + name); return line;
}).join("\n");
function harness() {
    let parent, created = 0, failAt = Infinity;
    class Panel {
        constructor(owner = null) { this.parent = owner; this.children = []; this.style = {}; this.deleted = false; this.clears = 0; if (owner) owner.children.push(this); }
        IsValid() { return !this.deleted; }
        GetParent() { return this.parent; }
        Children() { return this.children; }
        RemoveAndDeleteChildren() { this.clears++; if (this.failClear) throw Error("test_panel_clear_failed"); this.children.forEach(child => { child.deleted = true; child.parent = null; }); this.children = []; }
    }
    parent = new Panel();
    const $ = id => { assert.equal(id, "#PaymentQR"); return parent; };
    $.CreatePanel = (type, owner, id) => { assert.equal(type, "Panel"); assert.equal(id, ""); if (++created === failAt) throw Error("test_panel_creation_failed"); return new Panel(owner); };
    const api = vm.runInNewContext("(function(){var lastMatrix='',qrCache=null;\n" + helpers + "\n" + source.slice(start, end)
        + "\nreturn {draw:drawQR,cached:function(){return lastMatrix;}};}())", {$});
    return {api, get parent() { return parent; }, get created() { return created; }, failNext(offset = 1) { failAt = created + offset; },
        recover() { failAt = Infinity; }, replaceParent() { parent = new Panel(); return parent; }, Panel};
}
function matrix(size, distribution = 0) {
    const bits = Array.from({length:size}, (_, y) => Array.from({length:size}, (_, x) => {
        if (x < 4 || y < 4 || x >= size - 4 || y >= size - 4) return "0";
        return (distribution === 0 ? (x + y) % 2 : distribution === 1 ? y % 2 : (x * 17 + y * 11) % 7 < 3) ? "1" : "0";
    }));
    for (const [left, top] of [[4,4], [size - 11,4], [4,size - 11]]) {
        for (let y = -1; y <= 7; y++) for (let x = -1; x <= 7; x++) {
            if (left + x < 0 || top + y < 0 || left + x >= size || top + y >= size) continue;
            bits[top + y][left + x] = x >= 0 && x < 7 && y >= 0 && y < 7
                && (x === 0 || x === 6 || y === 0 || y === 6 || x >= 2 && x <= 4 && y >= 2 && y <= 4) ? "1" : "0";
        }
    }
    return bits.map(row => row.join("")).join("|");
}
function rectangles(parent) {
    return parent.Children().map(panel => {
        assert.equal(panel.GetParent(), parent); assert.equal(panel.style.backgroundColor, "#000000");
        assert.equal(panel.style.flowChildren, "none"); assert.equal(panel.style.ignoreParentFlow, "true");
        assert.equal(panel.style.margin, "0px"); assert.equal(panel.style.padding, "0px"); assert.equal(panel.style.border, "0px");
        assert.equal(panel.hittest, false); assert.equal(panel.hittestchildren, false); assert.equal(panel.Children().length, 0, "There are no flow row wrappers");
        const p = /^(\d+)px (\d+)px 0px$/.exec(panel.style.position); assert(p);
        return {x:Number(p[1]), y:Number(p[2]), w:parseInt(panel.style.width), h:parseInt(panel.style.height)};
    });
}
function checkPixels(parent, value) {
    const rows = value.split("|"), size = rows.length, cell = Math.max(3, Math.floor(216 / size)), pixels = size * cell;
    assert.equal(parent.style.width, pixels + "px"); assert.equal(parent.style.height, pixels + "px");
    assert.equal(parent.style.backgroundColor, "#ffffff"); assert.equal(parent.style.flowChildren, "none");
    assert.equal(parent.style.padding, "0px"); assert.equal(parent.style.border, "0px");
    const raster = new Uint8Array(pixels * pixels), rects = rectangles(parent);
    for (const r of rects) {
        assert.equal(r.x % cell, 0); assert.equal(r.y % cell, 0); assert.equal(r.w % cell, 0); assert.equal(r.h, cell);
        assert(r.x >= 0 && r.y >= 0 && r.x + r.w <= pixels && r.y + r.h <= pixels);
        for (let y = r.y; y < r.y + r.h; y++) for (let x = r.x; x < r.x + r.w; x++) {
            assert.equal(raster[y * pixels + x], 0, "Black geometry never overlaps"); raster[y * pixels + x] = 1;
        }
    }
    for (let y = 0; y < pixels; y++) for (let x = 0; x < pixels; x++)
        assert.equal(raster[y * pixels + x], Number(rows[Math.floor(y / cell)][Math.floor(x / cell)]), "Every painted pixel must equal its source bit");
    // The four-module backend quiet zone remains white; the renderer adds no cropping or new border.
    for (let y = 0; y < pixels; y++) for (let x = 0; x < pixels; x++)
        if (x < 4 * cell || y < 4 * cell || x >= pixels - 4 * cell || y >= pixels - 4 * cell) assert.equal(raster[y * pixels + x], 0);
    return {rects, rows, cell};
}
test("Actual QR renderer reconstructs every source bit for all supported QR sizes and different run distributions", () => {
    const h = harness();
    for (let size = 29; size <= 65; size += 4) for (let distribution = 0; distribution < 3; distribution++) {
        const value = matrix(size, distribution); assert.equal(h.api.draw(value), true); checkPixels(h.parent, value);
    }
});
test("Fractional scale .9 exposes the old flow rounding error while absolute finder endpoints remain identical", () => {
    const scale = .9, round = value => Math.ceil(value * scale);
    assert.deepEqual([round(35), round(5) + round(25) + round(5), round(5) * 4 + round(15), round(5) * 7], [32,33,34,35]);
    const h = harness(), value = matrix(41); assert.equal(h.api.draw(value), true);
    const {rects, cell} = checkPixels(h.parent, value); assert.equal(cell, 5);
    for (let y = 4; y < 11; y++) {
        const runs = rects.filter(r => r.y === y * cell && r.x >= 4 * cell && r.x + r.w <= 11 * cell);
        assert.equal(Math.min(...runs.map(r => r.x)), 4 * cell);
        assert.equal(Math.max(...runs.map(r => r.x + r.w)), 11 * cell);
        assert.equal(Math.ceil(Math.max(...runs.map(r => r.x + r.w)) * scale), Math.ceil(55 * scale), "No per-run accumulation");
    }
});
test("Global endpoint quantization preserves the matrix at fractional scales without flow accumulation", () => {
    const h = harness(), value = matrix(41, 2); h.api.draw(value);
    const {rects, rows, cell} = checkPixels(h.parent, value), size = rows.length;
    // This is a geometry model, not a claim that Node reproduces the native Panorama rasterizer.
    for (const scale of [.75,.9,1,1.25]) {
        const edge = n => Math.round(n * cell * scale), width = edge(size), actual = new Uint8Array(width * width), expected = new Uint8Array(width * width);
        for (const r of rects) for (let y = Math.round(r.y * scale); y < Math.round((r.y + r.h) * scale); y++)
            for (let x = Math.round(r.x * scale); x < Math.round((r.x + r.w) * scale); x++) actual[y * width + x] = 1;
        for (let by = 0; by < size; by++) for (let bx = 0; bx < size; bx++) if (rows[by][bx] === "1")
            for (let y = edge(by); y < edge(by + 1); y++) for (let x = edge(bx); x < edge(bx + 1); x++) expected[y * width + x] = 1;
        assert.deepEqual(actual, expected);
    }
});
test("Identical matrices reuse only complete children owned by the current actual canvas", () => {
    const h = harness(), value = matrix(33); h.api.draw(value); const count = h.created, first = h.parent.Children()[0];
    h.parent.style.visibility = "collapse"; assert.equal(h.api.draw(value), true); assert.equal(h.created, count); assert.equal(h.parent.style.visibility, "visible");
    h.parent.RemoveAndDeleteChildren(); assert.equal(h.api.draw(value), true); assert(h.created > count); assert(!h.parent.Children().includes(first)); checkPixels(h.parent, value);
    const old = h.parent, oldCount = h.created; h.replaceParent(); assert.equal(h.api.draw(value), true); assert(h.created > oldCount); checkPixels(h.parent, value);
    assert(h.parent.Children().every(p => p.GetParent() === h.parent && p.GetParent() !== old));
    h.parent.Children()[0].parent = old; const before = h.created; assert.equal(h.api.draw(value), true); assert(h.created > before); checkPixels(h.parent, value);
});
test("Invalid input clears stale geometry and cannot leave the previous matrix cached", () => {
    const h = harness(), value = matrix(29);
    for (const bad of [null, "", value.replace("1", "x"), "0".repeat(29), Array(28).fill("0".repeat(28)).join("|"), Array(66).fill("0".repeat(66)).join("|"), value + "|", value.replace("|", "")]) {
        assert.equal(h.api.draw(value), true); assert(h.parent.Children().length > 0);
        assert.equal(h.api.draw(bad), false); assert.equal(h.parent.Children().length, 0); assert.equal(h.parent.style.visibility, "collapse"); assert.equal(h.api.cached(), "");
    }
    assert.equal(h.api.draw(value), true); checkPixels(h.parent, value);
});
test("A partial native panel creation failure is never cached complete and the same matrix can retry", () => {
    const h = harness(), value = matrix(37); h.failNext(3); assert.equal(h.api.draw(value), false);
    assert.equal(h.api.cached(), ""); assert.equal(h.parent.Children().length, 0); assert.equal(h.parent.style.visibility, "collapse");
    h.recover(); assert.equal(h.api.draw(value), true); assert.equal(h.api.cached(), value); checkPixels(h.parent, value);
});
test("A native cleanup failure keeps old geometry hidden and cannot mark a new matrix complete", () => {
    const h = harness(), a = matrix(29), b = matrix(37); h.api.draw(a);
    const count = h.created; h.parent.failClear = true; assert.equal(h.api.draw(b), false);
    assert.equal(h.created, count); assert.equal(h.api.cached(), ""); assert.equal(h.parent.style.visibility, "collapse");
    h.parent.failClear = false; assert.equal(h.api.draw(b), true); checkPixels(h.parent, b);
});
test("Matrix changes replace every old child, invalid owners fail closed, and an all-white input never fakes a child cache", () => {
    const h = harness(), a = matrix(29), b = matrix(65, 1); h.api.draw(a); const oldChildren = h.parent.Children().slice();
    h.api.draw(b); assert(oldChildren.every(p => !p.IsValid())); checkPixels(h.parent, b);
    h.parent.deleted = true; const count = h.created; assert.equal(h.api.draw(b), false); assert.equal(h.created, count); assert.equal(h.api.cached(), "");
    h.replaceParent(); const blank = Array(29).fill("0".repeat(29)).join("|"); assert.equal(h.api.draw(blank), true); assert.equal(h.parent.Children().length, 0);
    const clears = h.parent.clears; assert.equal(h.api.draw(blank), true); assert(h.parent.clears > clears, "An empty canvas cannot satisfy the complete-child cache");
});
