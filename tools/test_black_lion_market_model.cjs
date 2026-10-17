"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const model = require("../panorama/src/scripts/custom_game/black_lion_market_model.js");
const expected = [
    ["home","首页"],["bundles","礼包"],["promotions","促销"],["vip","VIP"],["all","全部商品"]
];
assert.deepEqual(model.Groups({products:[]}).map(g => [g.id,g.label]),expected);
assert.deepEqual(model.Groups().map(g => g.count),[0,0,0,0,0]);
for(const category_id of ["item","technology","weapon","rebirth","challenge","future_category","__proto__"]){
    assert.equal(model.GroupFor({category_id}),"all");
}
assert.equal(model.GroupFor({category_id:"bundles",product_type:"bundle"}),"bundles");
assert.equal(model.GroupFor({category_id:"vip"}),"vip");
assert.equal(model.GroupFor(null),"all");assert.equal(model.GroupFor({}),"all");
function freeze(value) {
    if (value && typeof value === "object") { Object.values(value).forEach(freeze); Object.freeze(value); }
    return value;
}
const catalog = freeze({
    products:[
        {sku:"one",category_id:"item",product_type:"single",purchase_method:"wallet",currency:"shop_points",price:100,enabled:true},
        {sku:"two",category_id:"technology",product_type:"single",purchase_method:"cash",currency:"u_coin",u_coin_price:6800,amount_fen:680,u_coin_per_yuan:1000,enabled:true,original_price:8500},
        {sku:"three",category_id:"weapon",product_type:"single",enabled:false},
        {sku:"four",category_id:"rebirth",product_type:"single",purchase_method:"wallet",currency:"shop_points",price:50,enabled:true},
        {sku:"five",category_id:"challenge",product_type:"single",purchase_method:"wallet",currency:"shop_points",price:60,enabled:true},
        {sku:"six",category_id:"bundles",product_type:"bundle",purchase_method:"cash",amount_fen:777,enabled:true},
        {sku:"seven",category_id:"server_new",product_type:"single",purchase_method:"wallet",currency:"shop_points",price:1,enabled:true},
        {sku:"eight",category_id:"bundles",product_type:"bundle",purchase_method:"cash",amount_fen:777,enabled:false,required_vip_level:5,disabled_reason:"vip_level_insufficient"}
    ],
    categories:[{id:"item",label:"服务端道具材料"},{id:"bundles",label:"服务端礼包"},{id:"server_new",label:"服务端新增种类"}]
});
const original = JSON.stringify(catalog);
assert.deepEqual(model.Groups(catalog).map(g => g.count),[7,1,1,1,7],"Counts include purchasable/eligible-exchange products and explicit VIP restrictions, not unavailable rows");
assert.deepEqual(model.Groups({products:{"2":catalog.products[2],"0":catalog.products[0],"1":catalog.products[1]}}).map(g => g.count),[2,0,1,0,2],"Panorama numeric tables are accepted");
assert.equal(model.TypeLabel(catalog.products[0],catalog),"服务端道具材料 · 单品");
assert.equal(model.TypeLabel(catalog.products[5],catalog),"服务端礼包 · 礼包");
assert.equal(model.TypeLabel(catalog.products[6],catalog),"服务端新增种类 · 单品");
assert.equal(model.TypeLabel({category_id:"unlisted",product_type:"single"},catalog),"道具 · 单品");
assert.equal(model.TypeLabel({},catalog),"道具 · 单品");
assert.equal(model.ChannelLabel(catalog.products[0]),"商城积分兑换");
assert.equal(model.ChannelLabel({purchase_method:"wallet",currency:"shop_gold"}),"购买渠道待同步");
assert.equal(model.ChannelLabel(catalog.products[1]),"人民币直购（U币计价）","U-coin pricing never means wallet deduction");
assert.equal(model.ChannelLabel({purchase_method:"cash",amount_fen:5000}),"人民币直购");
assert.equal(model.ChannelLabel({purchase_method:"cash",u_coin_price:50000}),"人民币直购（U币计价）");
assert.equal(model.ChannelLabel({purchase_method:"wallet",currency:"u_coin"}),"购买渠道待同步","Unsupported wallet currency is not cash authorization");
for (const item of [null,{}, {currency:"u_coin",price:1000}, {amount_fen:100}, {purchase_method:"other",currency:"shop_points"}, {purchase_method:"wallet",currency:"new_currency"}]) {
    assert.equal(model.ChannelLabel(item),"购买渠道待同步");
}
assert.equal(JSON.stringify(catalog),original,"Presentation must leave SKU, category, price and purchase fields unchanged");
const mutable=model.Groups(catalog);mutable[0].count=999;
assert.equal(model.Groups(catalog)[0].count,7,"Returned group counters are independent objects");
const cfg = {};
vm.runInNewContext(fs.readFileSync(require.resolve("../panorama/src/scripts/custom_game/black_lion_market_model.js"),"utf8"),{GameUI:{CustomUIConfig:() => cfg}});
assert.equal(cfg.SurvivalBlackLionMarketModel.GroupFor({category_id:"weapon"}),"all","Panorama export is available without CommonJS");
console.log("BLACK_LION_MARKET_MODEL_PASS: five groups, server types, safe channel labels, numeric tables and immutable commerce data");
