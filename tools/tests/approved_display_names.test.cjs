"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const test = require("node:test");
const plan = JSON.parse(fs.readFileSync("data/presentation/approved_names_20261030.json","utf8"));
const source = fs.readFileSync("panorama/src/scripts/custom_game/common/item_resources.js","utf8");
function fixture() {
    const cfg={};const context=vm.createContext({GameUI:{CustomUIConfig:()=>cfg}});
    vm.runInContext(source,context);return {cfg,context,resources:cfg.SurvivalItemResources};
}
function freeze(value){if(value&&typeof value==="object"){Object.values(value).forEach(freeze);Object.freeze(value);}return value;}

test("120 character IDs use their approved names without rewriting raw records",()=>{
    const {resources:R}=fixture();let reviewed=0;
    for(const pool of ["ex","wife","friend"])for(let i=1;i<=40;i++){
        const id=pool+"_"+String(i).padStart(2,"0");
        const raw=freeze({id,name:"旧目录人物名",resource_id:"lottery_attribute_crystal",count:3,quality:"SSR"});
        assert.equal(R.DisplayName(raw,raw.name),plan.names[id],id);assert.equal(raw.name,"旧目录人物名");reviewed++;
    }
    assert.equal(reviewed,120);
});
test("ambiguous short names and repeated work labels require stable IDs",()=>{
    const {resources:R}=fixture();
    for(const id of ["friend_26","friend_39","ex_27","wife_19","work_01","work_18"])
        assert.equal(R.DisplayName({id,name:"旧重名"}),plan.names[id]);
    assert.notEqual(R.DisplayName({id:"friend_26"}),R.DisplayName({id:"friend_39"}));
    assert.notEqual(R.DisplayName({id:"ex_27"}),R.DisplayName({id:"wife_19"}));
    assert.equal(R.DisplayText("唐三"),"唐三");assert.equal(R.DisplayText("祈"),"祈");
    assert.equal(R.DisplayText("唐三累计3件，祈累计2件"),"唐三累计3件，祈累计2件");
});
test("offer SKU owns its permanent and quantity title ahead of a base item",()=>{
    const {resources:R}=fixture();
    for(const [sku,title] of Object.entries(plan.offer_names)) {
        const raw={sku,id:"lottery_muramasa",title:"后台旧商品名",price:900,currency:"shop_points"};
        assert.equal(R.DisplayName(raw,raw.title),title,sku);assert.equal(raw.price,900);
    }
});
test("borrowed artwork identity never overrides a semantic display name",()=>{
    const {resources:R}=fixture();const raw={id:"friend_26",resource_id:"lottery_attribute_crystal",name:"唐三"};
    assert.equal(R.Lookup(raw).id,"lottery_attribute_crystal","art lookup contract retained");
    assert.equal(R.DisplayName(raw,raw.name),plan.names.friend_26);
    assert.equal(R.DisplayName({id:"unknown",resource_id:"friend_26",name:"未登记物品"}),"未登记物品");
});
test("unknown records retain server text and common fallback remains usable",()=>{
    const {resources:R}=fixture();assert.equal(R.DisplayName({id:"unknown",name:"新的服务器物品"}),"新的服务器物品");
    assert.equal(R.DisplayName("not_registered","备用标题"),"备用标题");
    assert.equal(R.DisplayName(null,""),"");assert.equal(R.DisplayText(null),"");
});
test("unambiguous long prose aliases change labels without changing numbers or markup",()=>{
    const {resources:R}=fixture();const raw='<font color="#ff0000">妖刀村正</font> ×2；虚空之影 N15，价格5000';
    const shown=R.DisplayText(raw);assert(shown.includes(plan.names.lottery_muramasa));assert(shown.includes("破碎之影"));
    assert(shown.includes('<font color="#ff0000">'));assert(shown.includes("×2"));assert(shown.includes("N15"));assert(shown.includes("5000"));
    assert(raw.includes("妖刀村正"));
});
test("user-preserved hunt, cage and fragment identities keep approved names",()=>{
    const {resources:R}=fixture();const ids=[...plan.preserved.fragment_ids,...plan.preserved.cage_material_ids,...plan.preserved.challenge_ids];
    for(const id of ids)assert.equal(R.DisplayName({id,name:"旧目录名称"}),plan.names[id],id);
    assert.equal(R.DisplayText("阿尔萨斯"),"阿尔萨斯");assert.equal(R.DisplayText("霜之哀伤"),"霜之哀伤");
});
test("category and daily namespaces cannot override ordinary entry IDs",()=>{
    const {resources:R}=fixture();assert.equal(plan.names.clear,undefined);
    assert.equal(R.DisplayName({id:"clear"},"通关条目备用名"),"通关条目备用名");
    assert.equal(R.DisplayName({id:"social_beast"},"旧技能名"),plan.names.social_beast);
});
test("frozen authenticated catalog and completed receipt documents remain byte-identical",()=>{
    const {resources:R}=fixture();const raw=freeze({catalog_md5:"a".repeat(32),config_hash:"b".repeat(64),catalog_sequence:9,
        products:[{sku:"video_p042",title:"妖刀村正·永久",price:5000,enabled:false,ownership_id:"commerce_p042"}],
        receipt:{id:"friend_26",name:"唐三",paid:true,count:2}});
    const before=JSON.stringify(raw);R.DisplayName(raw.products[0],raw.products[0].title);R.DisplayName(raw.receipt,raw.receipt.name);
    R.DisplayText(raw.products[0].title);assert.equal(JSON.stringify(raw),before);
});
test("name-only hot reload invalidates the adapter with an independent name hash",()=>{
    const {cfg,context,resources:R}=fixture();
    const changed=source.replace('nameHash="'+R.displayNameHash+'"','nameHash="'+'c'.repeat(64)+'"')
        .replace('"work_01":"凝视"','"work_01":"测试新名"');
    vm.runInContext(changed,context);assert.notEqual(cfg.SurvivalItemResources,R);
    assert.equal(cfg.SurvivalItemResources.sourceHash,R.sourceHash);
    assert.equal(cfg.SurvivalItemResources.DisplayName({id:"work_01"}),"测试新名");
});
test("approved stackable tiers inherit their base item names",()=>{
    const {resources:R}=fixture();
    for(const [id,name] of Object.entries(plan.names))if(/^(zongzi|ember)_(base|\d+)$/.test(id)){
        assert.equal(R.DisplayName({id,name:"旧名"}),name);
        assert(name.includes(id.startsWith("zongzi")?"青叶粽":"传承余烬"),id);
    }
});
test("real lottery history and reward-card consumers display approved IDs from old receipts",()=>{
    const {cfg,context}=fixture();cfg.SurvivalUI={};
    function panel(type,parent){const p={type,parent,children:[],classes:new Set(),style:{},text:"",
        AddClass(c){this.classes.add(c);},BHasClass(c){return this.classes.has(c);},SetHasClass(c,on){if(on)this.classes.add(c);else this.classes.delete(c);},
        Children(){return this.children;},GetParent(){return this.parent;},SetScaling(){},SetPanelEvent(){}};
        if(parent)parent.children.push(p);return p;}
    context.$={CreatePanel:panel};
    vm.runInContext(fs.readFileSync("panorama/src/scripts/custom_game/remaining_5d5c1152eb.js","utf8"),context);
    const record=freeze({id:"lottery_muramasa",name:"妖刀村正",quality:"UR",quantity:2,duplicate:true,converted_points:100,converted_currency:"shop_points"});
    const host=panel("Panel",null);
    cfg.RemainingHandoff.History(host,[{time:"20:00",items:[record]}],parent=>panel("Image",parent),()=>{},()=>{});
    const all=p=>[p,...p.children.flatMap(all)];const historyName=all(host).find(p=>p.classes.has("RHHistoryName"));
    assert(historyName.text.startsWith(plan.names.lottery_muramasa));assert(historyName.text.includes("100 商城积分"));
    const card=panel("Panel",null);cfg.RemainingHandoff.RewardCard(card,record);
    assert.equal(all(card).find(p=>p.classes.has("RHRewardName")).text,plan.names.lottery_muramasa);
    assert.equal(record.name,"妖刀村正");
});
