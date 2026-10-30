"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const test = require("node:test");
const source = fs.readFileSync("panorama/src/scripts/custom_game/public_beta_gift.js", "utf8");
const model = require("../panorama/src/scripts/custom_game/public_beta_gift.js");
const components = fs.readFileSync("panorama/src/scripts/custom_game/common/ui_components.js", "utf8");
const layers = fs.readFileSync("panorama/src/scripts/custom_game/ui_layers.js", "utf8");

// Execute the shipping controller and real modal/input owners. This checks
// receipt races and lifecycle ownership; native layout pixels are separate.
function fixture() {
    const nodes = {}, jobs = new Map(), events = new Map(), tables = new Map(), sends = [];
    let serial = 0, stamp = 1800000000000, admission = false, sequence = 0;
    function panel(type, parent, id) {
        const p = {id, type, parent, children:[], style:{}, classes:new Set(), events:{}, visible:true,
            valid:true, hittest:false, hittestchildren:true, enabled:true, text:"",
            actuallayoutwidth:1920, actuallayoutheight:1080, actualuiscale_x:1, actualuiscale_y:1,
            IsValid(){return this.valid;}, GetParent(){return this.parent;}, Children(){return this.children;},
            GetChildCount(){return this.children.length;}, GetChild(i){return this.children[i];},
            AddClass(c){this.classes.add(c);}, RemoveClass(c){this.classes.delete(c);}, BHasClass(c){return this.classes.has(c);},
            SetHasClass(c,on){if(on)this.classes.add(c);else this.classes.delete(c);}, SetAcceptsFocus(){}, SetFocus(){},
            SetPanelEvent(name,fn){this.events[name]=fn;},
            FindChildTraverse(key){if(this.id===key)return this;for(const child of this.children){const r=child.FindChildTraverse(key);if(r)return r;}return null;}
        };
        if(parent)parent.children.push(p); if(id)nodes[id]=p; return p;
    }
    const native = panel("Panel",null,"Native"), context = panel("Panel",native,"Context");
    const root = panel("Panel",context,"PublicBetaGiftWindow");
    panel("Button",context,"PublicBetaGiftScrim");
    for(const id of ["PublicBetaGiftClaim","PublicBetaGiftClaimText","PublicBetaGiftReward","PublicBetaGiftQuantity",
        "PublicBetaGiftRewardCaption","PublicBetaGiftNotice","PublicBetaGiftClose","PublicBetaGiftReceipt"]) panel("Panel",root,id);
    const cfg = {SurvivalUIRegistry:{tokens:{colors:{surface_ivory:"#fff",border_champagne:"#aaa"}},assets:{}}};
    const $ = {GetContextPanel:()=>context, CreatePanel:panel, RegisterEventHandler(){},
        Schedule(delay,fn){const id=++serial;jobs.set(id,{delay,fn});return id;}, CancelScheduled:id=>jobs.delete(id)};
    const sandbox = vm.createContext({$, Date:{now:()=>stamp}, GameUI:{CustomUIConfig:()=>cfg},
        CustomNetTables:{GetTableValue:()=>({admission_complete:admission?1:0}),
            SubscribeNetTableListener(name,fn){const id=++serial;tables.set(id,fn);return id;},UnsubscribeNetTableListener:id=>tables.delete(id)},
        GameEvents:{Subscribe(name,fn){const id=++serial;events.set(id,{name,fn});return id;},Unsubscribe:id=>events.delete(id),
            SendCustomGameEventToServer(name,data){sends.push({name,data:JSON.parse(JSON.stringify(data))});}}});
    vm.runInContext(layers,sandbox); vm.runInContext(components,sandbox);
    function load(){vm.runInContext(source,sandbox,{filename:"public_beta_gift.js"});}
    function tick(ms=250){stamp+=ms;const job=[...jobs].find(([,v])=>v.fn.name==="loop");assert(job,"one live controller loop");jobs.delete(job[0]);job[1].fn();}
    function snapshot(overrides={}) {
        const payload={ok:1,login_key:"login_a",sequence:++sequence,revision:10,active:1,
            day_key:"2026-10-30",eligible:1,claimed:0,claim_pending:0,ticket_id:"special_lottery_ticket",ticket_count:2,...overrides};
        for(const event of [...events.values()])if(event.name==="survival_public_beta_gift_snapshot")event.fn(payload);
        return payload;
    }
    load();
    return {cfg,nodes,jobs,events,tables,sends,load,tick,snapshot,
        admit(value=true){admission=value;for(const fn of tables.values())fn();},
        click(){nodes.PublicBetaGiftClaim.events.onactivate();},
        close(){nodes.PublicBetaGiftClose.events.onactivate();},
        inspect(){return cfg.SurvivalPublicBetaGift.Inspect();},
        claims(){return sends.filter(x=>x.name==="survival_public_beta_gift_claim");},
        queries(){return sends.filter(x=>x.name==="survival_public_beta_gift_request");},
        nonce(){return this.claims().at(-1).data.request_id;},
        eligible(){this.admit();this.tick();this.snapshot();}
    };
}

test("no query or popup before admission, cached eligible snapshot waits",()=>{
    const f=fixture();f.snapshot();assert.equal(f.inspect().open,false);assert.equal(f.queries().length,0);
    f.admit();f.tick();assert.equal(f.inspect().open,true);assert.equal(f.queries().length,1);
});
test("unloaded profile cannot open and retries query without writing",()=>{
    const f=fixture();f.admit();f.tick();f.snapshot({ok:0});f.tick(6000);
    assert.equal(f.inspect().open,false);assert.equal(f.claims().length,0);assert.equal(f.queries().length,2);
});
test("eligible player automatically sees the approved fixed reward",()=>{
    const f=fixture();f.eligible();assert.equal(f.inspect().open,true);
    assert.equal(f.nodes.PublicBetaGiftReward.text,"金色抽奖券");assert.equal(f.nodes.PublicBetaGiftQuantity.visible,true);
});
test("claim submits nonce only and duplicate clicks cannot submit",()=>{
    const f=fixture();f.eligible();f.click();f.click();assert.equal(f.claims().length,1);
    assert.deepEqual(Object.keys(f.claims()[0].data),["request_id"]);
    assert.match(f.nonce(),/^[A-Za-z0-9_-]{8,64}$/);assert.equal(f.nodes.PublicBetaGiftClaim.enabled,false);
});
test("uncorrelated and nonterminal acknowledgements never display paid",()=>{
    const f=fixture();f.eligible();f.click();
    f.snapshot({claimed:1,claim_result:{request_id:"other_nonce",ok:1,terminal:1,pending:0,day_key:"2026-10-30"}});
    assert.equal(f.inspect().confirmed,false);assert(f.inspect().pending);
    f.snapshot({claimed:1,claim_result:{request_id:f.nonce(),ok:1,terminal:0,pending:1,day_key:"2026-10-30"}});
    assert.equal(f.inspect().confirmed,false);assert.equal(f.nodes.PublicBetaGiftClaim.enabled,false);
});
test("ACK alone without a refreshed claimed profile keeps the request pending",()=>{
    const f=fixture();f.eligible();f.click();f.snapshot({claimed:0,claim_result:{request_id:f.nonce(),ok:1,terminal:1,pending:0,day_key:"2026-10-30"}});
    assert(f.inspect().pending);assert.equal(f.inspect().confirmed,false);
});
test("matching terminal receipt plus refreshed claimed state shows paid once",()=>{
    const f=fixture();f.eligible();f.click();f.snapshot({claimed:1,eligible:0,revision:11,
        claim_result:{request_id:f.nonce(),ok:1,terminal:1,pending:0,day_key:"2026-10-30"}});
    assert.equal(f.inspect().pending,null);assert.equal(f.inspect().confirmed,true);
    assert.equal(f.nodes.PublicBetaGiftReward.text,"今日好礼已到账");assert.equal(f.nodes.PublicBetaGiftClaimText.text,"开始游戏");
    f.click();assert.equal(f.inspect().open,false);assert.equal(f.claims().length,1);
});
test("terminal failure permits an explicit retry with a new nonce",()=>{
    const f=fixture();f.eligible();f.click();const old=f.nonce();
    f.snapshot({claim_result:{request_id:old,ok:0,terminal:1,pending:0,error:"PRIVATE_INTERNAL_ERROR"}});
    assert.equal(f.inspect().pending,null);assert.equal(f.nodes.PublicBetaGiftClaim.enabled,true);
    assert.equal(f.nodes.PublicBetaGiftClaimText.text,"重试领取");assert(!f.nodes.PublicBetaGiftNotice.text.includes("PRIVATE"));
    f.click();assert.equal(f.claims().length,2);assert.notEqual(f.nonce(),old);
});
test("timeout queries status and cannot automatically replay a claim",()=>{
    const f=fixture();f.eligible();f.click();f.tick(11000);assert(f.queries().length>=2);
    assert.equal(f.claims().length,1);assert.equal(f.nodes.PublicBetaGiftClaimText.text,"正在确认…");
});
test("closing suppresses further popup pushes in the same login",()=>{
    const f=fixture();f.eligible();f.close();f.snapshot();f.tick();assert.equal(f.inspect().open,false);assert.equal(f.inspect().dismissed,true);
});
test("pending survives hot reload, never claims twice, and waits for fresh snapshot",()=>{
    const f=fixture();f.eligible();f.click();const nonce=f.nonce();f.load();assert.equal(f.inspect().open,false);
    f.snapshot({claim_pending:1});assert.equal(f.inspect().pending.request_id,nonce);assert.equal(f.inspect().open,true);
    assert.equal(f.claims().length,1);assert.equal(f.events.size,1);assert.equal(f.tables.size,1);
});
test("closed pending hot reload stays closed, receipt is still consumed",()=>{
    const f=fixture();f.eligible();f.click();const nonce=f.nonce();f.close();f.load();
    f.snapshot({claimed:1,eligible:0,revision:11,claim_result:{request_id:nonce,ok:1,terminal:1,pending:0,day_key:"2026-10-30"}});
    assert.equal(f.inspect().open,false);assert.equal(f.inspect().confirmed,true);assert.equal(f.claims().length,1);
});
test("new login resets dismissal, old-world responses cannot reopen stale state",()=>{
    const f=fixture();f.eligible();f.close();f.snapshot({login_key:"login_b",sequence:1,revision:10});assert.equal(f.inspect().open,true);
    f.snapshot({login_key:"login_a",sequence:50});assert.equal(f.inspect().login_key,"login_b");
});
test("old sequences, days, revisions and invalid configured rewards are rejected",()=>{
    const state=model.Initial();const good={ok:1,login_key:"a",sequence:1,revision:10,day_key:"2026-10-30",ticket_id:"special_lottery_ticket",ticket_count:2};
    assert(model.Accept(state,good));for(const changed of [{sequence:1},{sequence:2,revision:9},{sequence:2,day_key:"2026-10-29"},{sequence:2,ticket_count:3},{sequence:2,ticket_id:"new_ticket"}])
        assert.equal(model.Accept(state,{...good,...changed}),false);
    assert.equal(state.sequence,1);
});
test("late previous-day receipt cannot report today's reward paid",()=>{
    const f=fixture();f.eligible();f.click();const nonce=f.nonce();f.snapshot({day_key:"2026-10-31",revision:11,
        claim_result:{request_id:nonce,ok:1,terminal:1,pending:0,day_key:"2026-10-30"}});
    assert.equal(f.inspect().confirmed,false);assert.equal(f.inspect().pending,null);assert.equal(f.nodes.PublicBetaGiftReward.text,"金色抽奖券");
});
test("server integer day keys compare numerically across digit boundaries",()=>{
    const state=model.Initial();const row={ok:1,login_key:"a",sequence:1,revision:0,day_key:"9999",ticket_id:"special_lottery_ticket",ticket_count:2};
    assert(model.Accept(state,row));assert(model.Accept(state,{...row,sequence:2,day_key:"10000"}));
    assert.equal(model.Accept(state,{...row,sequence:3,day_key:"9999"}),false);
});
test("a concurrent already-claimed rejection closes pending without a false paid receipt",()=>{
    const f=fixture();f.eligible();f.click();f.snapshot({claimed:1,eligible:0,
        claim_result:{request_id:f.nonce(),ok:0,terminal:1,pending:0,day_key:"2026-10-30"}});
    assert.equal(f.inspect().pending,null);assert.equal(f.inspect().confirmed,false);
    assert.equal(f.nodes.PublicBetaGiftReward.text,"今日好礼已领取");
    assert.equal(f.nodes.PublicBetaGiftNotice.text,"好运相伴，共赴新程");
});
test("an already claimed login does not automatically open",()=>{
    const f=fixture();f.admit();f.tick();f.snapshot({claimed:1,eligible:0});assert.equal(f.inspect().open,false);
});
test("activity disabled or loading cover restored releases input",()=>{
    const f=fixture();f.eligible();f.snapshot({active:0});assert.equal(f.inspect().open,false);
    f.snapshot();assert.equal(f.inspect().open,true);f.admit(false);assert.equal(f.inspect().open,false);
});
test("automatic popup waits for another modal and ignores retired guide state",()=>{
    const f=fixture();const other={IsValid:()=>true,GetParent:()=>null,SetAcceptsFocus(){},SetFocus(){},style:{}};
    f.cfg.SurvivalUILayers.Open("other",other,()=>{});f.eligible();assert.equal(f.inspect().open,false);
    f.cfg.SurvivalUILayers.Close("other");f.cfg.SurvivalOnboarding={Inspect:()=>({shown:true})};f.tick();assert.equal(f.inspect().open,true);
});
test("dispose removes event listeners, timers and modal input",()=>{
    const f=fixture();f.eligible();f.cfg.SurvivalPublicBetaGift.Dispose();assert.equal(f.events.size,0);assert.equal(f.tables.size,0);
    assert.equal(f.jobs.size,0);assert.equal(f.cfg.SurvivalUILayers.Top(),null);assert.equal(f.nodes.PublicBetaGiftWindow.visible,false);
});
