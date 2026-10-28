"use strict";
const assert = require("node:assert/strict");
const model = require("../../panorama/src/scripts/custom_game/black_lion_market_model.js");
const priced = [{sku:"expensive",currency:"shop_points",price:5000},
    {sku:"zongzi",currency:"shop_points",price:60},
    {sku:"ordinary",currency:"CNY",price:300},
    {sku:"gold",currency:"CNY",price:600},
    {sku:"ember",currency:"shop_points",price:60},
    {sku:"gold_coins",purchase_method:"cash",currency:"u_coin",u_coin_price:600,amount_fen:600},
    {sku:"unknown"}];
for (const group of ["home","all","promotions","bundles","vip"]) {
    assert.deepEqual(model.SortProducts(priced,group).map(p=>p.sku),
        ["ordinary","gold","zongzi","ember","gold_coins","expensive","unknown"]);
}
assert.equal(priced[0].sku,"expensive");
console.log("COMMERCE_PRICE_SORT_PASS: all sections, price units, stable ties, missing prices, immutable source");
