"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const {csv} = require("./shop_ui_12h/catalog.cjs");
const root = path.resolve(__dirname,"..");
const source = fs.readFileSync(path.join(root,"panorama/src/scripts/custom_game/lottery_gw2_data.js"),"utf8");
const cfg = {};
vm.runInNewContext(source,{GameUI:{CustomUIConfig:() => cfg}});
const model = cfg.LotteryGW2Data.preview;
const plain = value => JSON.parse(JSON.stringify(value));
function freeze(value) {
    if (value && typeof value === "object") { Object.values(value).forEach(freeze); Object.freeze(value); }
    return value;
}
assert(model && typeof model.Groups === "function" && typeof model.Quantity === "function" && typeof model.RuleText === "function");
const original = {};
vm.runInNewContext(source.split("// Display-only projection of the server's selected-pool snapshot.")[0],{GameUI:{CustomUIConfig:() => original}});
assert.deepEqual(plain(cfg.LotteryGW2Data.assets),plain(original.LotteryGW2Data.assets),"Every original asset is retained unchanged");
const load = name => csv(path.join(root,"data/csv/抽奖系统",name+".csv"));
const definitions = new Map(load("lottery_item_definitions").filter(row => row.enabled === "1").map(row => [row.item_id,row]));
const memberships = load("lottery_pool_items").filter(row => row.enabled === "1");
const updates = new Map(load("lottery_pool_updates").map(row => [row.pool_id,row]));
const pity = load("lottery_pity_rules").filter(row => row.enabled === "1");
const expected = {
    map:{n:10,r:5,sr:5,ssr:10},
    cultivation:{r:5,sr:5,ssr:9,ur:7},
    dragon_knight:{r:5,sr:5,ssr:10,ur:6},
    summer:{r:5,sr:5,ssr:8,ur:5}
};
for (const poolId of Object.keys(expected)) {
    const items = memberships.filter(row => row.pool_id === poolId).flatMap(member => {
        const members = member.item_id === "*" ? [...definitions.values()] : [definitions.get(member.item_id)];
        return members.filter(Boolean).map(row => ({id:row.item_id,name:row.display_name,quality:row.quality,icon:row.icon,icon_type:row.icon_type,max_owned:Number(row.max_owned),owned_count:0}));
    });
    const selectedPool = {id:poolId,update_notice:updates.get(poolId),pity:pity.filter(row => row.pool_id === poolId).map(row => ({quality:row.target_quality,trigger_mode:row.trigger_mode,batch_size:Number(row.threshold)}))};
    freeze(items);freeze(selectedPool);
    const before = JSON.stringify({items,selectedPool});
    const groups = model.Groups(items,selectedPool);
    assert.deepEqual(Object.fromEntries(groups.map(group => [group.id,group.count])),expected[poolId],"Enabled real memberships form the entire pool: "+poolId);
    assert.deepEqual(plain(groups.map(group => group.items.length)),Object.values(expected[poolId]));
    assert.equal(groups.reduce((total,group) => total+group.count,0),items.length);
    if (poolId === "map") {
        assert.deepEqual(Object.fromEntries(groups.map(group => [group.id,group.percent])),{n:69.5,r:25,sr:4,ssr:1.5});
    } else {
        assert(groups.every(group => !Object.hasOwn(group,"percent")),"Unpublished special-pool probabilities stay absent: "+poolId);
    }
    assert.match(model.RuleText(selectedPool),poolId === "map" || poolId === "cultivation" ? /十连保底 SSR/ : /十连保底 UR/);
    assert.match(model.RuleText(selectedPool),/连续十次单抽不触发/);
    assert(!model.RuleText(selectedPool).includes("%"),"A batch guarantee is not a single-draw probability");
    assert.equal(JSON.stringify({items,selectedPool}),before,"Grouping cannot change the real server projection");
}
const repeated = freeze([{id:"same",quality:"UR"},{id:"same",quality:"n"},{id:"same",quality:"unknown_server_quality"},{id:"same"}]);
const duplicateGroups = model.Groups(repeated,{});
assert.deepEqual(plain(duplicateGroups.map(group => [group.id,group.count])),[["n",1],["ur",1],["unknown",2]]);
assert.equal(duplicateGroups.reduce((sum,group) => sum+group.items.length,0),4,"Repeated IDs must never lose a visible entry");
assert.equal(duplicateGroups[0].items[0],repeated[1],"Grouping only references the original item metadata");
assert.deepEqual(plain(model.Groups()),[]);
assert.deepEqual(plain(model.Groups({"2":{quality:"sr"},"1":{quality:"r"},"0":{quality:"n"}},{}).map(group => group.id)),["n","r","sr"]);
assert.equal(model.Quantity({owned_count:0,max_owned:1}),"0/1");
assert.equal(model.Quantity({owned_count:"2",max_owned:"5"}),"2/5");
assert.equal(model.Quantity({owned_count:2}),"2");
assert.equal(model.Quantity({owned_count:6,max_owned:5}),"6/5","Do not clamp real quantities to a fabricated value");
for (const owned_count of [undefined,null,"",false,-1,NaN,Infinity,"bad",1.5]) assert.equal(model.Quantity({owned_count,max_owned:1}),"—");
for (const max_owned of [undefined,null,"",false,0,-1,NaN,Infinity,"bad",1.5]) assert.equal(model.Quantity({owned_count:2,max_owned}),"2");
const one = [{quality:"ssr"}];
for (const notice of [undefined,null,"",{},"SSR：150%","SSR：-1%","SSR：1.5% SSR：2%","SSR：1.5% 私有权重","ssr:1.5%","SSR：015%","概率SSR：1.5%","SSR：1.5% R：2500%"]){
    assert(!Object.hasOwn(model.Groups(one,{update_notice:{single_draw_probabilities:notice},quality_weights:{ssr:150}})[0],"percent"),"Only a complete strict published notice may be parsed: "+String(notice));
}
assert.equal(model.Groups(one,{update_notice:{single_draw_probabilities:"SSR: 0%"}})[0].percent,0,"A published zero is not unknown");
assert(!Object.hasOwn(model.Groups(one,{quality_weights:{ssr:150},single_draw_probabilities:"SSR：1.5%"})[0],"percent"),"Do not fall back to weight data or an unofficial field");
assert.equal(model.RuleText(),"保底规则待同步");
assert.equal(model.RuleText({pity:[]}),"当前奖池无已公布的批量保底");
assert.equal(model.RuleText({pity:[{quality:"ur",batch_size:10,trigger_mode:"cumulative"}]}),"当前奖池无已公布的批量保底","Unknown trigger modes must not become ten-pull guarantees");
console.log("LOTTERY_POOL_PREVIEW_MODEL_PASS: four formal pools, strict public notice only, batch guarantees, quantities, unknown quality and duplicate IDs");
