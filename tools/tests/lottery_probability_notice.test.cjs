const fs=require('fs'),vm=require('vm'),path=require('path');
const loader=fs.readFileSync('tools/test_lottery_updates.cjs','utf8').split('suite+=')[0];
const checks=`
root.actuallayoutwidth=1920;root.actuallayoutheight=1080;root.actualuiscale_x=1;root.actualuiscale_y=1;
const probability='SSR：1.5%　 SR：4%　 R：25%　 N：69.5%';
function notice(pool,odds){const x=snapshot(pool);x.selected_pool.update_notice={single_draw_probabilities:odds};return x;}
function textInNotice(){return nodes.LotteryInfoList.children.map(p=>p.text||'').join(' ');}
ui.Open();ui.SelectPool('map');events.ui_lottery_snapshot(notice('map',probability));ui.Feature('announcement');
assert(textInNotice().includes(probability));assert(textInNotice().includes('玩家须知'));
assert(textInNotice().includes('连续十次单抽不触发'));assert(!textInNotice().includes('活动公告内容暂未接入'));
for(const pool of ['cultivation','dragon_knight','summer']){
 ui.CloseInfo();ui.SelectPool(pool);events.ui_lottery_snapshot(notice(pool,''));ui.Feature('announcement');
 assert(!textInNotice().includes('69.5%'),'map odds must not leak into another pool');
 assert(textInNotice().includes('暂未公布'));
}
ui.CloseInfo();ui.SelectPool('map');events.ui_lottery_snapshot(notice('map',''));ui.Feature('announcement');
assert(!textInNotice().includes('69.5%'),'old server snapshot must not be presented as the new probability');
events.ui_lottery_snapshot(notice('map',probability));assert(textInNotice().includes(probability),'open notice refreshes with matching server snapshot');
assert(!requests.some(r=>r.n==='ui_lottery_draw_request'||r.n==='ui_lottery_exchange_request'));
console.log('LOTTERY_PROBABILITY_NOTICE_PASS: map text, pool isolation, old snapshot guard, refresh and no draw/exchange');
`;
vm.runInNewContext(loader+'suite+='+JSON.stringify(checks)+';vm.runInNewContext(suite,{require:require("node:module").createRequire(require("path").resolve("tools/test_lottery_ui.js")),console});',{require:require('node:module').createRequire(path.resolve('tools/tests/lottery_probability_notice.test.cjs')),console});
