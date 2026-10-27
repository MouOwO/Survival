"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");
const {makeFixture} = require("./survival_shop_nav_20261017/fixture.cjs");

test("the actual market modal highlights its navigation entry and blocks background activation", () => {
    const market = fs.readFileSync("panorama/src/scripts/custom_game/black_lion_market.js", "utf8");
    assert.match(market, /ModalShell\.Adopt\(\{id:"commerce"/);
    const f = makeFixture(); f.stack.push("commerce"); f.advance(1200);
    assert.equal(f.entry("shop").BHasClass("HandoffNavActive"), true);
    assert.equal(f.entry("archive").BHasClass("HandoffNavActive"), false);
    for (const id of ["archive", "lottery", "benefit", "shop"]) f.click(f.entry(id));
    assert.deepEqual(f.actions, [], "the highlight fix does not bypass the modal navigation guard");
    f.stack.pop(); f.advance(1200);
    assert.equal(f.entry("shop").BHasClass("HandoffNavActive"), false);
    f.click(f.entry("shop")); assert.deepEqual(f.actions, ["shop"]);
});

test("wallet result and cash checkout layers retain their market navigation owner", () => {
    const f = makeFixture();
    for (const id of ["commerce_result", "payment_shop"]) {
        f.stack.push(id); f.advance(1200);
        assert.equal(f.entry("shop").BHasClass("HandoffNavActive"), true, id);
        f.click(f.entry("shop")); assert.deepEqual(f.actions, []);
        f.stack.pop(); f.advance(1200);
        assert.equal(f.entry("shop").BHasClass("HandoffNavActive"), false);
    }
});

test("moving from a market dialog to another window transfers the single selected entry", () => {
    const f = makeFixture(); f.stack.push("commerce"); f.advance(1200);
    f.stack.pop(); f.stack.push("archive"); f.advance(1200);
    assert.equal(f.entry("shop").BHasClass("HandoffNavActive"), false);
    assert.equal(f.entry("archive").BHasClass("HandoffNavActive"), true);
});
