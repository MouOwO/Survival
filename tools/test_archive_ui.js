"use strict";
const fs = require("fs"), vm = require("vm"), assert = require("assert");
const panels = {}, callbacks = {}, requests = [], scheduled = [], types = [];
class Panel {
    constructor(type, parent, id) {
        this.type = type; this.parent = parent; this.id = id;
        this.children = []; this.classes = new Set(); this.events = {}; this.style = {};
        if (parent) parent.children.push(this);
        if (id) panels[id] = this;
    }
    AddClass(c) { this.classes.add(c); }
    RemoveClass(c) { this.classes.delete(c); }
    SetHasClass(c, on) { on ? this.AddClass(c) : this.RemoveClass(c); }
    RemoveAndDeleteChildren() { this.children = []; }
    SetPanelEvent(name, cb) { this.events[name] = cb; }
}
const root = new Panel("Panel", null, "Root");
root.actuallayoutwidth = 1920; root.actuallayoutheight = 1080;
const xml = fs.readFileSync("panorama/src/layout/custom_game/archive.xml", "utf8");
for (const match of xml.matchAll(/id="([^"]+)"/g)) new Panel("Panel", root, match[1]);
function $(id) { return panels[id.substring(1)]; }
$.CreatePanel = (type, parent, id) => { types.push(type); return new Panel(type, parent, id); };
$.GetContextPanel = () => root;
$.RegisterEventHandler = () => {};
$.Schedule = (delay, fn) => scheduled.push({ delay, fn });
const config = {};
require("./load_shared_ui_test.cjs")({$,GameUI:{CustomUIConfig:()=>config}},Panel,root);
vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/reward_presentation.js", "utf8"), {
    $, GameUI: { CustomUIConfig: () => config }
});
vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/archive.js", "utf8"), {
    $, GameUI: { CustomUIConfig: () => config, GetCursorPosition: () => [1900, 1070] },
    Game: { GetScreenWidth: () => 1920, GetScreenHeight: () => 1080 },
    GameEvents: { Subscribe: (name, cb) => { callbacks[name] = cb; },
        SendCustomGameEventToServer: (name, payload) => requests.push({ name, payload }) }
});
config.SurvivalArchive.Toggle();
assert.equal(requests[0].payload.category_id, "clear");
const receive = callbacks.survival_archive_snapshot;
const categories = [{id:"clear",name:"通关存档"},{id:"shadow",name:"虚空之影"},{id:"points",name:"积分道具"},{id:"fragment",name:"神兵碎片"},{id:"pet",name:"秘法牢笼"}];
categories.push({id:"friend",name:"我的好基友"},{id:"ex",name:"我的前女友"},{id:"beast",name:"瑞兽赐福"});
const first = { id:"a", name:"N1（1次）", description:"木材+50", icon_style:"scroll", count:1,target:1,completed:1 };
const second = { id:"b", name:"N1（3次）", description:"木材+80", icon_style:"scroll", count:1,target:3,completed:0 };
function packet(sequence, category, chunk, chunks, rows) {
    return { sequence, category_id:category, chunk, chunks, rows, ok:1, categories };
}
receive(packet(1,"clear",2,2,[second]));
assert.equal(panels.ArchiveGrid.children.length, 0, "partial packets do not render");
receive(packet(1,"clear",1,2,[first]));
assert.equal(panels.ArchiveGrid.children.length, 2);
assert.equal(panels.ArchiveTabs.children.length, categories.length);
assert.equal(panels.ArchiveTab_clear.checked, true);
assert.equal(panels.ArchiveTab_shadow.checked, false);
const card = panels.ArchiveGrid.children[0];
assert(card.children[0].classes.has("ArchiveCompleted"));
assert(!panels.ArchiveGrid.children[1].children[0].classes.has("ArchiveCompleted"));
assert(!card.events.onactivate, "icons have no click actions");
card.events.onmouseover();
assert.equal(panels.ArchiveTooltipName.text, "N1（1次）");
assert(panels.ArchiveTooltipEffect.text.includes("木材+50"));assert(panels.ArchiveTooltipEffect.text.includes("通关 1 次"));
assert(!types.some(type => /DOTA/.test(type)), "archive navigation uses registered UI images, not native item panels");
panels.ArchiveTab_shadow.events.onactivate();
assert.equal(panels.ArchiveTab_shadow.checked, true);
scheduled.filter(x => x.delay === 0.18).forEach(x => x.fn());
assert.equal(requests[requests.length - 1].payload.category_id, "shadow");
receive(packet(2,"clear",1,1,[first]));
assert.equal(panels.ArchiveGrid.children.length, 0, "stale category ignored");
receive(packet(3,"shadow",1,1,[]));
assert.equal(panels.ArchiveEmpty.text, "尚未获得虚空之影道具");
assert(!panels.ArchiveEmpty.classes.has("ArchiveHidden"));
receive(packet(2,"shadow",1,1,[first]));
assert.equal(panels.ArchiveGrid.children.length, 0, "stale sequence ignored");
panels.ArchiveTab_fragment.events.onactivate();
receive(packet(4,"fragment",1,1,[{id:"fragment_01",name:"破碎大剑",count:201,target:999,level:10,promotion_target:"狂战斧",promotion_cost:10,can_promote:1},
    {id:"fragment_02",name:"始祖之祸",count:0,target:999,level:0,promotion_target:"碎颅锤",promotion_cost:10,can_promote:0}]));
assert.equal(panels.ArchiveSummary.text, "已拥有 1 种");
const fragmentCard = panels.ArchiveGrid.children[0];
assert(!fragmentCard.events.onactivate, "fragment icon still has no click action");
const promotion = fragmentCard.children.find(p => p.type === "Button");
promotion.events.onactivate();
assert.equal(requests[requests.length - 1].name, "survival_archive_promote");
assert.equal(requests[requests.length - 1].payload.fragment_id, "fragment_01");
const requestCount = requests.length;
promotion.events.onactivate();
panels.ArchiveGrid.children[1].children.find(p => p.type === "Button").events.onactivate();
assert.equal(requests.length, requestCount, "disabled promotion and duplicate click are blocked");
config.SurvivalArchive.Close();
panels.ArchiveTab_points.events.onactivate();
receive(packet(5,"points",1,1,[{id:"point",name:"积分测试",icon_type:"item",icon:"item_daedalus",quality:"ur",count:1,target:1}]));
const pointCard = panels.ArchiveGrid.children[0];
assert.equal(pointCard.children[0].children[0].itemname, "item_daedalus");
pointCard.events.onmouseover();
assert.equal(panels.ArchiveTooltipName.style.color, "#8844bb");
assert.equal(config.SurvivalRewardPresentation.NameColor("N"), "#ffffff");
config.SurvivalArchive.Close();
assert(panels.ArchiveWindow.classes.has("ArchiveHidden"));
assert(panels.ArchiveTooltip.classes.has("ArchiveHidden"));
callbacks.survival_endless_state({status:"running",wave:11,remaining:5,seconds:60,score:10});
assert(panels.EndlessStatus.text.includes("剩余5只"));
assert(!panels.EndlessStatus.classes.has("ArchiveHidden"));
callbacks.survival_endless_state({status:"finished",wave:11,cleared:10,score:10,reason:"本波60秒超时"});
assert(panels.EndlessStatus.text.includes("本波60秒超时"));
panels.ArchiveTab_friend.events.onactivate();
receive(Object.assign(packet(6,"friend",1,1,[{id:"friend_01",name:"哆啦A梦",count:1,target:65},{id:"friend_02",name:"孙悟空",count:0,target:65}]),{
    social:{tickets:2,currency_name:"义帖",draw_cost:1,remaining:100,total:1,unlocked:0}
}));
assert(!panels.ArchiveGrid.children[0].children[0].classes.has("ArchiveCompleted"));
assert(panels.ArchiveGrid.children[1].children[0].classes.has("ArchiveCompleted"));
assert.equal(panels.ArchiveTickets.text,"义帖：2");
assert(panels.ArchiveDraw.enabled);
panels.ArchiveDraw.events.onactivate();
assert.equal(requests[requests.length-1].name,"survival_archive_social_draw");
assert.equal(requests[requests.length-1].payload.pool_id,"friend");
assert(!('PlayerID' in requests[requests.length-1].payload));
assert(!panels.ArchiveDraw.enabled);
panels.ArchiveTab_ex.events.onactivate();
receive(Object.assign(packet(7,"ex",1,1,[]),{social:{tickets:0,currency_name:"义帖",draw_cost:1,remaining:100,total:0}}));
assert(!panels.ArchiveDraw.enabled);
panels.ArchiveTab_beast.events.onactivate();
assert(!panels.ArchiveDrawBar.classes.has("ArchiveHidden"), "draw bar is visible while loading");
receive(Object.assign(packet(8,"beast",1,1,[{id:"beast_01",name:"散魂钟",count:1,target:50}]),{social:{tickets:1,currency_name:"福签",draw_cost:1,remaining:100,total:1},last_draw:{pool_id:"beast",name:"散魂钟"}}));
assert.equal(panels.ArchiveTickets.text,"福签：1");
assert.equal(panels.ArchiveDrawResult.text,"获得：散魂钟");
panels.ArchiveDraw.events.onactivate();
assert.equal(requests[requests.length-1].payload.pool_id,"beast");
assert.equal(panels.ArchiveDrawResult.text,"抽奖结算中…");
console.log("ARCHIVE_UI_PASS: three draw pages, ticket names, ownership and result refresh");
categories.push({id:"map_level",name:"地图等级"},{id:"work",name:"上班福利"});
receive(packet(9,"beast",1,1,[]));
panels.ArchiveTab_work.events.onactivate();
const workRows=[{id:"work_01",name:"老板凝视",description:"伐木工攻速+2%",quality:"N",count:0,target:1,level:0,cost:600,can_upgrade:1},
    {id:"work_02",name:"996lv1",count:0,target:1,level:0,cost:800,can_upgrade:0}];
receive(Object.assign(packet(10,"work",1,1,workRows),{online:{coins:600}}));
assert(panels.ArchiveSummary.text.includes("软妹币：600"));
assert(panels.ArchiveDrawBar.classes.has("ArchiveHidden"));
const workCell=panels.ArchiveGrid.children[0];
workCell.events.onmouseover();
assert.equal(panels.ArchiveTooltipEffect.text,"伐木工攻速+2%");
const beforeWork=requests.length;
panels.ArchiveGrid.children[1].events.onactivate();
assert.equal(requests.length,beforeWork,"unaffordable item cannot submit");
workCell.events.onactivate();workCell.events.onactivate();
assert.equal(requests.length,beforeWork+1,"double click submits once");
assert.equal(requests[requests.length-1].name,"survival_archive_work_upgrade");
assert.equal(requests[requests.length-1].payload.item_id,"work_01");
assert.equal(requests[requests.length-1].payload.expected_level,0);
receive(Object.assign(packet(11,"work",1,1,[Object.assign({},workRows[0],{count:1,completed:1,can_upgrade:0})]),{online:{coins:0}}));
assert(panels.ArchiveGrid.children[0].children[0].classes.has("ArchiveCompleted"));
assert(panels.ArchiveSummary.text.includes("软妹币：0"));
panels.ArchiveTab_map_level.events.onactivate();
receive(Object.assign(packet(12,"map_level",1,1,[{id:"map_01",name:"地图等级1",count:60,target:60,completed:1}]),{online:{level:1,max_level:34,map_seconds:3600},has_pass:1}));
assert(panels.ArchiveHint.text.includes("1小时0分钟") && panels.ArchiveHint.text.includes("双倍计时"));
assert(!panels.ArchiveGrid.children[0].events.onactivate,"map levels unlock automatically");
console.log("ARCHIVE_ONLINE_UI_PASS: balance, click intent, duplicate guard, activated state, map-time display");
categories.push({id:"fishing",name:"钓鱼存档"});
receive(packet(13,"map_level",1,1,[]));
panels.ArchiveTab_fishing.events.onactivate();
const fishRows=[{id:"star_blessing_001",name:"青萍",description:"初始木材+10",quality:"N",count:3,target:90,count_known:1},
    {id:"star_blessing_002",name:"浮玉",count:0,target:300,count_known:1}];
receive(Object.assign(packet(14,"fishing",1,1,fishRows),{fishing:{ready:1,total:3,owned:1,types:26}}));
assert(panels.ArchiveSummary.text.includes("共 3 件"));
assert(!panels.ArchiveGrid.children[0].children[0].classes.has("ArchiveCompleted"));
assert(panels.ArchiveGrid.children[1].children[0].classes.has("ArchiveCompleted"));
assert(panels.ArchiveDrawBar.classes.has("ArchiveHidden"));
assert(!panels.ArchiveGrid.children[0].events.onactivate,"fishing items are read-only");
panels.ArchiveGrid.children[0].events.onmouseover();
assert.equal(panels.ArchiveTooltipEffect.text,"初始木材+10");
receive(Object.assign(packet(15,"fishing",1,1,[Object.assign({},fishRows[0],{count:0,count_known:0})]),{fishing:{ready:0}}));
assert.equal(panels.ArchiveSummary.text,"库存待同步");
console.log("ARCHIVE_FISHING_UI_PASS: owned state, count, tooltip, unknown inventory, no grant actions");
categories.push({id:"building",name:"存档建筑"});
receive(packet(16,"fishing",1,1,[]));
panels.ArchiveTab_building.events.onactivate();
const buildingRows=[{id:"building_01",name:"玲珑心",count:2,level:2,target:5,cost:3000,can_upgrade:1,completed:0},
 {id:"building_02",name:"圣剑",count:5,level:5,target:5,cost:3000,can_upgrade:0,completed:1}];
receive(Object.assign(packet(17,"building",1,1,buildingRows),{buildings:{faith:6000,earned_today:4000,daily_cap:4000,per_clear:400}}));
assert(panels.ArchiveSummary.text.includes("信仰值：6000"));
assert(panels.ArchiveHint.text.includes("通行证不加成"));
const beforeBuilding=requests.length;
panels.ArchiveGrid.children[1].events.onactivate();
assert.equal(requests.length,beforeBuilding,"max level cannot submit");
panels.ArchiveGrid.children[0].events.onactivate();
panels.ArchiveGrid.children[0].events.onactivate();
assert.equal(requests.length,beforeBuilding+1);
assert.equal(requests[requests.length-1].name,"survival_archive_building_upgrade");
assert.equal(requests[requests.length-1].payload.expected_level,2);
console.log("ARCHIVE_BUILDING_UI_PASS");

config.SurvivalArchive.Toggle();assert(!panels.ArchiveScrim.classes.has('ArchiveHidden'));
panels.ArchiveTab_clear.events.onactivate();receive(packet(18,'clear',1,1,[first,{...second,count:8,completed:0},{id:'unknown',name:'无进度字段'}]));
const withProgress=panels.ArchiveGrid.children[1];assert(withProgress.children.some(p=>p.classes.has('ArchiveCount')&&p.text==='8/3'));assert(withProgress.children.some(p=>p.classes.has('ArchiveUnlockBadge')&&p.text==='未解锁'),'never infer unlock from count');assert(!panels.ArchiveGrid.children[2].children.some(p=>p.classes.has('ArchiveCount')));
const beforeFilter=requests.length;config.SurvivalArchive.Filter('unlocked');assert.equal(panels.ArchiveGrid.children.length,1);config.SurvivalArchive.Filter('locked');assert.equal(panels.ArchiveGrid.children.length,1);assert.equal(requests.length,beforeFilter);config.SurvivalArchive.Filter('all');assert.equal(panels.ArchiveGrid.children.length,3);
assert(panels.ArchiveWindow.style.transform.includes('scale3d('));config.SurvivalArchive.Close();assert(panels.ArchiveScrim.classes.has('ArchiveHidden'));console.log('ARCHIVE_KIT_PASS: scrim, parent scaling, real progress, explicit unlock and local filters');
