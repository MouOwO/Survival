"use strict";
// Execute the shipping controller, including real input and state callbacks.
// This fixture proves logic/geometry only; native Panorama rendering is separate.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const path = require("node:path");
const sourcePath = process.argv[2] || path.join(__dirname,"../panorama/src/scripts/custom_game/onboarding.js");
const source = fs.readFileSync(sourcePath,"utf8");
const model = require(path.resolve(sourcePath));

assert.deepEqual(model.Masks({width:100,height:80},{x:20,y:10,width:40,height:30}),[
    {x:0,y:0,width:100,height:10},{x:0,y:40,width:100,height:40},
    {x:0,y:10,width:20,height:30},{x:60,y:10,width:40,height:30}
]);
assert.equal(model.TargetContains([20,10,0],{x:0,y:0,z:0,width:40,height:20}),true);
assert.equal(model.TargetContains([20.01,10,0],{x:0,y:0,z:0,width:40,height:20}),false);
assert.equal(model.TargetContains([0,0,0],{x:0,y:0,z:0,width:NaN,height:20}),false);

function fixture() {
    const nodes = {}, sends = [], selected = [], camera = [], scheduled = new Map(), handlers = {}, subscriptions = new Map();
    let stamp = 100000, serial = 0, listenerSerial = 0, admitted = false, cursor = [0,0], world = [0,0,48];
    let production = {unit:20,visible:true,slots:["train_lumberjack_02","train_lumberjack_01"]};
    const modalStack = []; let modalCloses = 0;
    function panel(type,parent,id) {
        const result = {type,id,parent,children:[],visible:true,hittest:false,hittestchildren:true,
            style:{},text:"",events:{},actualuiscale_x:2,actualuiscale_y:2,
            actuallayoutwidth:960,actuallayoutheight:540,position:{x:20,y:40},
            IsValid(){return true;}, AddClass(){}, GetParent(){return this.parent;}, Children(){return this.children;},
            GetPositionWithinWindow(){return this.position;},
            FindChildTraverse(key){if(this.id===key)return this;for(const child of this.children){const match=child.FindChildTraverse(key);if(match)return match;}return null;},
            SetPanelEvent(name,fn){this.events[name]=fn;}
        };
        if(parent)parent.children.push(result);if(id)nodes[id]=result;return result;
    }
    const top = panel("Panel",null,"Top"), context = panel("Panel",top,"Context");
    const root = panel("Panel",context,"SurvivalOnboardingRoot");
    for(const id of ["OnboardingTargets","OnboardingMaskTop","OnboardingMaskBottom","OnboardingMaskLeft","OnboardingMaskRight",
        "OnboardingFocus","OnboardingCard","OnboardingSkip","OnboardingProgress","OnboardingTitle","OnboardingDescription","OnboardingStatus","OnboardingSkipText"]) panel("Panel",root,id);
    Object.assign(nodes.OnboardingSkip,{position:{x:1700,y:80},actuallayoutwidth:100,actuallayoutheight:30});
    const native = panel("Panel",top,"NativeHud"), proxies = panel("Panel",native,"SurvivalManagedAbilityProxyLayer");
    const proxy = panel("Button",proxies,"SurvivalManagedAbilityProxy0");
    Object.assign(proxy,{hittest:true,__survivalAbilityName:"ability_build_wall",__survivalAbilityIndex:30,
        __survivalWindowWidth:80,__survivalWindowHeight:80,position:{x:1200,y:850}});
    for(let i=0;i<4;i++) {const button=panel("Button",native,"ProductionTrainingSlot"+i);button.position={x:400+i*160,y:650};button.actuallayoutwidth=70;button.actuallayoutheight=54;}
    const cfg = {SurvivalInputDispatcher:{
        RegisterMouseHandler(id,fn,priority){assert(priority>=1200);handlers.mouse=fn;},
        RegisterKeyHandler(id,fn,priority){assert(priority>=1200);handlers.key=fn;}
    },SurvivalProductionHUD:{Inspect:()=>production},SurvivalUILayers:{
        Top:()=>modalStack.length?modalStack.at(-1).id:null,
        CloseTop(){
            modalCloses++;
            if(modalStack.at(-1)?.closable===false)return;
            modalStack.pop();
            native.style.zIndex=modalStack.length?"100000":"0";
            top.style.zIndex=modalStack.length?"100000":"0";
        }
    }};
    const $ = {};
    $.GetContextPanel=()=>context;$.CreatePanel=panel;
    $.Schedule=(delay,fn)=>{const id=++serial;scheduled.set(id,{delay,fn});return id;};
    $.CancelScheduled=id=>scheduled.delete(id);
    const callbacks = {};
    const env = {$, Date:{now:()=>stamp},GameUI:{CustomUIConfig:()=>cfg,
        SelectUnit:(id,add)=>selected.push({id,add}),SetCameraTargetPosition:(p,t)=>camera.push({p:Array.from(p),t}),
        GetCursorPosition:()=>cursor,GetScreenWorldPosition:()=>world},
        Game:{WorldToScreenX:x=>x+800,WorldToScreenY:(_,y)=>800-y},
        Entities:{IsValidEntity:id=>id===10||id===20,GetAbsOrigin:()=>[0,0,48]},
        CustomNetTables:{GetTableValue:()=>({admission_complete:admitted?1:0}),
            SubscribeNetTableListener:(_,fn)=>{const id=++listenerSerial;subscriptions.set(id,fn);return id;},
            UnsubscribeNetTableListener:id=>subscriptions.delete(id)},
        GameEvents:{Subscribe:(name,fn)=>{const id=++listenerSerial;callbacks[name]={id,fn};return id;},
            Unsubscribe:id=>{for(const key of Object.keys(callbacks))if(callbacks[key].id===id)delete callbacks[key];},
            SendCustomGameEventToServer:(name,data)=>sends.push({name,data})}
    };
    function tick(milliseconds=40) {
        stamp+=milliseconds;
        const entry=[...scheduled.entries()].find(([,item])=>item.fn.name==="loop");
        assert(entry,"controller loop is scheduled");scheduled.delete(entry[0]);entry[1].fn();
    }
    function load(){vm.runInNewContext(source,env,{filename:sourcePath});}
    load();
    return {cfg,nodes,selected,camera,sends,handlers,scheduled,subscriptions,tick,load,
        state(payload){callbacks.survival_onboarding_state.fn(payload);},
        admit(value){admitted=value;for(const fn of subscriptions.values())fn();},
        cursor(x,y){cursor=[x,y];},world(value){world=value;},production(value){production=value;},
        modal(id,closable=true){modalStack.push({id,closable});native.style.zIndex="100000";top.style.zIndex="100000";},
        modalCloses(){return modalCloses;},
        inspect(){return cfg.SurvivalOnboarding.Inspect();}
    };
}
function snapshot(overrides={}) {
    return {generation:7,revision:1,active:1,step:"wall",step_index:1,total_steps:4,
        title:"建造城墙",description:"请在楼梯口绿色区域建造城墙",ability_name:"ability_build_wall",
        builder_entindex:10,main_city_entindex:20,build_grid_size:64,placement_required:1,
        targets:[{x:0,y:0,z:48,width:64,height:64,footprint_x:4,footprint_y:4},
            {x:1000,y:0,z:48,width:64,height:64,footprint_x:4,footprint_y:4}],...overrides};
}
const f=fixture();
assert.equal(f.sends[0].name,"ui_onboarding_request_state");
assert.deepEqual(Object.keys(f.sends[0].data),[],"client sends no trusted player identity");
assert.equal(f.inspect().shown,false,"unknown first-login state does not block loading UI");
f.state(snapshot());
assert.equal(f.inspect().shown,false,"server active cannot cover startup admission");
f.admit(true);
assert.equal(f.inspect().shown,true);
assert.equal(f.inspect().phase,"ability");
assert.equal(f.inspect().actionable,false,"first animation blocks controls");
assert.equal(f.nodes.OnboardingFocus.hittest,true,"the moving hole itself blocks native UI clicks");
assert.deepEqual(f.selected,[{id:10,add:false}],"own builder is selected once");
f.cursor(1220,870);
assert.equal(f.handlers.mouse("pressed",0),true,"animation cannot activate the skill");
f.tick(310);
assert.equal(f.inspect().actionable,true);
assert.equal(f.nodes.OnboardingFocus.hittest,false,"finished hole passes native UI clicks through");
const buttonHole=f.inspect().hole;
assert.equal(buttonHole.x,587,"window pixel x is converted with layer origin and UI scale");
assert.equal(buttonHole.y,402);
assert.equal(buttonHole.width,46,"cached actual native button pixels determine the opening");
assert.equal(f.handlers.mouse("pressed",0),false,"highlighted button is usable");
f.cursor(50,50);assert.equal(f.handlers.mouse("pressed",0),true,"outside mouse is blocked");
assert.equal(f.handlers.key("Q",true),true,"hotkeys cannot activate an unrelated skill");
assert.equal(f.inspect().step,"wall","clicking does not locally advance server-owned progress");
f.cfg.SurvivalPointTargetState={active:true,name:"ability_build_wall",unit:10};
f.tick();assert.equal(f.inspect().phase,"placement");
f.tick(310);
assert.equal(f.inspect().actionable,true);
assert.equal(f.inspect().chosen_target,0,"nearest green target is the single placement opening");
assert.equal(f.inspect().hole.width,38,"click opening is the 64-world-unit centre window at 2x UI scale plus focus padding");
assert.equal(f.nodes.OnboardingTargets.children[0].children[12].style.width,"128.00px",
    "green edge spans the full four-cell building footprint, independently of the 64-unit centre window");
let h=f.inspect().hole;f.cursor(20+(h.x+h.width/2)*2,40+(h.y+h.height/2)*2);
f.world([0,0,48]);assert.equal(f.handlers.mouse("pressed",0),false,"real world target passes to existing grid validation");
f.world([10000,0,48]);assert.equal(f.handlers.mouse("pressed",0),true,"screen hole cannot authorize a different world location");
f.world(null);assert.equal(f.handlers.mouse("pressed",0),true,"failed world projection cannot allow an order");
assert.equal(f.handlers.mouse("pressed",1),false,"right click may cancel the selected placement");
assert.equal(f.handlers.key("ESCAPE",true),false,"Escape reaches the existing placement cancel handler");
f.state(snapshot({revision:2,waiting:1}));
assert.equal(f.inspect().actionable,false);assert.equal(f.inspect().hole,null,"server waiting closes gameplay hole");
f.state(snapshot({revision:1}));assert.equal(f.inspect().revision,2,"out-of-order snapshot is ignored");
f.state(snapshot({generation:6,revision:999}));assert.equal(f.inspect().revision,2,"old session cannot revive its guide");
f.state(snapshot({revision:3,step:"worker",step_index:3,ability_name:"",targets:[]}));
assert.equal(f.inspect().phase,"worker");
assert.deepEqual(f.selected.at(-1),{id:20,add:false},"worker stage selects own main city");
f.tick(310);h=f.inspect().hole;
assert.equal(h.x,267,"training button is resolved by training ID, not fixed slot zero");
assert.equal(f.inspect().actionable,true);
f.production({unit:21,visible:true,slots:["train_lumberjack_01"]});f.tick();
assert.equal(f.inspect().hole,null,"another player's production UI is never exposed");
assert.equal(f.nodes.OnboardingSkip.hittest,true,"skip remains enabled when the required control is missing");
f.state(snapshot({revision:4,error:"已有城墙不在引导位置，请跳过本次引导继续游戏。"}));
assert.equal(f.inspect().hole,null,"sync failure cannot expose a stale target");
assert.equal(f.nodes.OnboardingStatus.text,"已有城墙不在引导位置，请跳过本次引导继续游戏。",
    "the server's actionable Chinese reason is preserved instead of a generic sync error");
f.nodes.OnboardingSkip.events.onactivate();
assert.equal(f.sends.at(-1).name,"ui_onboarding_skip");
assert.equal(f.inspect().shown,true,"client awaits authoritative skip acknowledgement");
assert.equal(f.inspect().skip_pending,true);
assert.equal(f.inspect().hole,null);
f.state(snapshot({revision:5,active:0,step:"skipped"}));
assert.equal(f.inspect().shown,false);assert.equal(f.handlers.key("Q",true),false);
assert.equal(f.handlers.mouse("pressed",0),false,"skip acknowledgement releases all input");
f.state(snapshot({revision:5,active:1}));
assert.equal(f.inspect().shown,false,"a duplicated pre-skip revision cannot restore a blocking mask");
f.state(snapshot({revision:6,active:0,step:"skipped",persisting:2,error:"save pending"}));
assert.equal(f.inspect().shown,false,"background persistence retry after skip never restores the mask");
assert.equal(f.inspect().skip_pending,false,"inactive authoritative state retires local skip waiting");

const retry=fixture();retry.admit(true);retry.state(snapshot());
retry.nodes.OnboardingSkip.events.onactivate();
const skipCount=()=>retry.sends.filter(entry=>entry.name==="ui_onboarding_skip").length;
assert.equal(skipCount(),1);
retry.nodes.OnboardingSkip.events.onactivate();assert.equal(skipCount(),1,"repeat skip retains one-second throttle");
retry.tick(900);retry.nodes.OnboardingSkip.events.onactivate();assert.equal(skipCount(),1);
// Simulate the first skip datagram disappearing, followed by a state reply
// from the still-active server (also valid after a service generation reload).
retry.state(snapshot({generation:8,revision:1,active:1}));
assert.equal(retry.inspect().skip_pending,true);assert.equal(retry.inspect().hole,null);
retry.tick(200);assert.equal(retry.nodes.OnboardingSkipText.text,"重试跳过");
assert.equal(retry.nodes.OnboardingSkip.hittest,true);
retry.nodes.OnboardingSkip.events.onactivate();assert.equal(skipCount(),2,"an active reply does not disable skip retransmission");
assert.deepEqual(Object.keys(retry.sends.at(-1).data),[],"retry still sends no client-trusted identity");
retry.state(snapshot({generation:8,revision:2,active:0,step:"skipped"}));
assert.equal(retry.inspect().shown,false);assert.equal(retry.inspect().skip_pending,false);

const late=fixture();late.admit(true);late.state(snapshot({targets:[{x:9000,y:0,z:48,width:128,height:128}]}));
late.cfg.SurvivalPointTargetState={active:true,name:"ability_build_wall",unit:10};
late.tick();late.tick();late.tick();
assert.equal(late.camera.length,1,"offscreen target recenters once rather than fighting the player's camera");
assert.equal(late.inspect().hole,null);assert.equal(late.nodes.OnboardingSkip.hittest,true);
const oldMouse=late.handlers.mouse,oldKey=late.handlers.key;
late.load();assert.equal(oldMouse("pressed",0),false);assert.equal(oldKey("Q",true),false);
assert.equal(late.inspect().shown,false,"reload requests a new private snapshot");
assert.equal(late.scheduled.size,1,"old render loop is cancelled");
assert.equal(late.subscriptions.size,1,"old nettable listener is removed");

const done=fixture();done.admit(true);done.state(snapshot());done.tick(310);
done.state(snapshot({revision:2,active:0,step:"complete"}));
assert.equal(done.inspect().shown,true);assert.equal(done.inspect().phase,"complete");
assert.equal(done.handlers.key("Q",true),false,"completion toast does not block play");
assert.equal(done.nodes.OnboardingSkipText.text,"完成");
done.tick(3600);assert.equal(done.inspect().shown,false,"completion toast expires");
done.cfg.SurvivalOnboarding.Dispose();assert.equal(done.scheduled.size,0);
assert.equal(done.nodes.SurvivalOnboardingRoot.hittestchildren,false);

const layers=fixture();
layers.modal("ordinary_shop");layers.state(snapshot());
assert.equal(layers.modalCloses(),0,"guide cannot close UI while admission/loading remains incomplete");
assert.equal(layers.nodes.Context.style.zIndex,undefined);
layers.admit(true);
assert.equal(layers.cfg.SurvivalUILayers.Top(),null,"existing ordinary modal closes through its real owner");
assert.equal(layers.nodes.Context.style.zIndex,"150000","the independent native onboarding branch is raised");
assert.equal(layers.nodes.SurvivalOnboardingRoot.style.zIndex,"150000");
assert.equal(layers.nodes.Top.style.zIndex,"0","shared native root is not unnecessarily raised");
assert(Number(layers.nodes.Context.style.zIndex)>Number(layers.nodes.NativeHud.style.zIndex),"guide/skip branch is actually above the sibling HUD");
layers.state(snapshot({revision:2,step:"worker",step_index:3,ability_name:"",targets:[]}));layers.tick(310);
assert.equal(layers.inspect().actionable,true);
assert.equal(layers.cfg.SurvivalUILayers.Top(),null,"training's ordinary modal guard remains clear");
layers.modal("auto_reward");layers.tick();
assert.equal(layers.cfg.SurvivalUILayers.Top(),null,"a later ordinary auto-popup cannot strand the guide behind itself");
layers.nodes.Context.style.zIndex="2000000000";layers.tick();
assert.equal(layers.nodes.Context.style.zIndex,"2000000000","active guide never lowers the native error owner");
layers.nodes.SurvivalOnboardingRoot.style.zIndex="200000";layers.tick();
assert.equal(layers.nodes.SurvivalOnboardingRoot.style.zIndex,"200000","loading-sized layer is not lowered either");
layers.state(snapshot({revision:3,active:0,step:"skipped"}));
assert.equal(layers.nodes.Context.style.zIndex,"2000000000","release preserves a newer external error assignment");
assert.equal(layers.nodes.SurvivalOnboardingRoot.style.zIndex,"200000");

const restore=fixture();restore.admit(true);restore.state(snapshot());
restore.nodes.Context.style.zIndex="120000";restore.tick();
assert.equal(restore.nodes.Context.style.zIndex,"150000","active guide reacquires its foreground after a lower external assignment");
restore.state(snapshot({revision:2,active:0,step:"skipped"}));
assert.equal(restore.nodes.Context.style.zIndex,"120000","release restores that newer baseline, not the original stale value");
assert.equal(restore.nodes.SurvivalOnboardingRoot.style.zIndex,"0");
const trapped=fixture();trapped.admit(true);trapped.modal("refuses_close",false);trapped.state(snapshot());
assert.equal(trapped.modalCloses(),1,"a refusing owner is not repeatedly forced within one render");
assert.equal(trapped.inspect().actionable,false);assert.equal(trapped.inspect().hole,null);
assert.equal(trapped.nodes.OnboardingSkip.hittest,true,"skip remains available during an unclosable modal wait");
trapped.cfg.SurvivalOnboarding.Dispose();
assert.equal(trapped.nodes.Context.style.zIndex,"0","dispose releases the independent foreground lease");
console.log("PASS onboarding: admission, native branches/modal ownership, safe foreground lease, shrinking hole, input confinement, private replay, training ID, world validation, skip, completion, reload");
