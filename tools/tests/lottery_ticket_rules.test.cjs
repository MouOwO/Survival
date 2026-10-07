const fs=require('fs'),vm=require('vm'),path=require('path');
const loader=fs.readFileSync('tools/tests/lottery_cinematic_flow.test.cjs','utf8').split('suite+=')[0];
const checks=`
root.actuallayoutwidth=1920;root.actuallayoutheight=1080;root.actualuiscale_x=1;root.actualuiscale_y=1;
ui.Open();
function rules(pool,progress,tickets){const s=snapshot(pool,tickets);Object.assign(s.selected_pool,{ticket_content_id:['map','cultivation'].includes(pool)?'lottery_ticket':'special_lottery_ticket',unlocked:pool!=='cultivation'||progress>=100,unlock_progress:progress,unlock_required:pool==='cultivation'?100:0});s.pools=[s.selected_pool];return s;}
ui.SelectPool('cultivation');events.ui_lottery_snapshot(rules('cultivation',99,200));
assert(!nodes.LotterySingleButton.enabled&&!nodes.LotteryTenButton.enabled,'locked despite enough tickets');
assert(nodes.LotteryUnlockNotice.visible&&nodes.LotteryUnlockNotice.text.includes('99 / 100'));
let count=requests.length;ui.DrawSingle();ui.DrawTen();assert.equal(requests.length,count,'locked UI never sends a draw');
assert(!nodes.LotteryWindow.BHasClass('LotteryGoldenTicket'));
events.ui_lottery_snapshot(rules('cultivation',100,200));assert(nodes.LotterySingleButton.enabled&&nodes.LotteryTenButton.enabled);assert(!nodes.LotteryUnlockNotice.visible);
for(const pool of ['dragon_knight','summer']){ui.SelectPool(pool);events.ui_lottery_snapshot(rules(pool,0,1));assert(nodes.LotterySingleButton.enabled);assert(!nodes.LotteryTenButton.enabled,'ten still costs ten');assert(nodes.LotteryWindow.BHasClass('LotteryGoldenTicket'));}
ui.SelectPool('map');events.ui_lottery_snapshot(rules('map',0,10));assert(!nodes.LotteryWindow.BHasClass('LotteryGoldenTicket'));assert(nodes.LotteryTenButton.enabled);
console.log('LOTTERY_TICKET_RULES_UI_PASS: 99/100 lock boundary, no locked requests, normal/gold icons, gold single with zero progress and balance-aware ten.');
`;
vm.runInNewContext(loader+'suite+='+JSON.stringify(checks)+';vm.runInNewContext(suite,{require:require("node:module").createRequire(require("path").resolve("tools/test_lottery_ui.js")),console,__dirname:require("path").resolve("tools")});',{require:require('node:module').createRequire(path.resolve('tools/tests/lottery_cinematic_flow.test.cjs')),console});
