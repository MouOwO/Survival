const fs=require('fs'),vm=require('vm'),path=require('path');
const loader=fs.readFileSync('tools/tests/lottery_cinematic_flow.test.cjs','utf8').split('suite+=')[0];
const checks=`
root.actuallayoutwidth=1920;root.actuallayoutheight=1080;root.actualuiscale_x=1;root.actualuiscale_y=1;
config.SurvivalPurpleLottery={Version:'lottery_current_20261018',Owns(owner){return owner===root;},IsAlive(){return true;},IsReady(){return true;},Open(){},Close(){},Apply(){},Fit(){return true;}};
ui.Open();
function rules(pool,progress,tickets){const s=snapshot(pool,tickets);Object.assign(s.selected_pool,{ticket_content_id:pool==='map'?'lottery_ticket':'special_lottery_ticket',unlocked:true,unlock_progress:progress,unlock_required:0});s.pools=[s.selected_pool];return s;}
// A genuinely locked authoritative response must still be respected; the
// approved configuration no longer produces this response for cultivation.
ui.SelectPool('cultivation');const locked=rules('cultivation',99,200);Object.assign(locked.selected_pool,{unlocked:false,unlock_required:100});events.ui_lottery_snapshot(locked);
assert(!nodes.LotterySingleButton.enabled&&!nodes.LotteryTenButton.enabled,'locked despite enough tickets');
assert(nodes.LotteryUnlockNotice.visible&&nodes.LotteryUnlockNotice.text.includes('99 / 100'));
let count=requests.length;ui.DrawSingle();ui.DrawTen();assert.equal(requests.length,count,'locked UI never sends a draw');
assert(nodes.LotteryWindow.BHasClass('LotteryGoldenTicket'));
for(const progress of [0,99,100]){events.ui_lottery_snapshot(rules('cultivation',progress,1362));assert(nodes.LotterySingleButton.enabled&&nodes.LotteryTenButton.enabled);assert(!nodes.LotteryUnlockNotice.visible);}
for(const pool of ['cultivation','dragon_knight','summer']){ui.SelectPool(pool);events.ui_lottery_snapshot(rules(pool,0,1));assert(nodes.LotterySingleButton.enabled);assert(!nodes.LotteryTenButton.enabled,'ten still costs ten');assert(nodes.LotteryWindow.BHasClass('LotteryGoldenTicket'));}
ui.SelectPool('map');events.ui_lottery_snapshot(rules('map',0,10));assert(!nodes.LotteryWindow.BHasClass('LotteryGoldenTicket'));assert(nodes.LotteryTenButton.enabled);
console.log('LOTTERY_TICKET_RULES_UI_PASS: authoritative locks respected, cultivation 0/99/100 enabled with 1362 gold, correct ticket types and balance-aware ten.');
`;
vm.runInNewContext(loader+'suite+='+JSON.stringify(checks)+';vm.runInNewContext(suite,{require:require("node:module").createRequire(require("path").resolve("tools/test_lottery_ui.js")),console,__dirname:require("path").resolve("tools")});',{require:require('node:module').createRequire(path.resolve('tools/tests/lottery_cinematic_flow.test.cjs')),console});
