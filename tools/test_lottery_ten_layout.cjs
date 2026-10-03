const fs = require('fs'), vm = require('vm'), path = require('path');
// Reuse the live-script Panorama fixture, including its shared UI dependencies.
const setup = fs.readFileSync('tools/test_lottery_updates.cjs', 'utf8').split('suite+=`')[0];
const checks = String.raw`
ui.Open(); events.ui_lottery_snapshot(snapshot());
nodes.LotterySkipAnimation.checked=true; ui.SetSkipAnimation();
ui.DrawTen();
const ten=results(10);
events.ui_lottery_result({ok:1,request_id:requests.at(-1).p.request_id,pool_id:'map',count:10,results:ten,snapshot:snapshot('map',10)});
const cards=nodes.LotteryItemList.children;
assert.equal(cards.length,10);
const css=fs.readFileSync('panorama/src/styles/custom_game/lottery_fullscreen_v2.css','utf8');
assert(css.includes('#LotteryWindow #LotteryMainCanvas #LotteryItemList.LotteryTenResults { flow-children:none; }'));
const box=css.match(/#LotteryWindow #LotteryMainCanvas #LotteryItemList \.LotteryRewardCard \{ width:(\d+)px; height:(\d+)px;/);
const bounds=css.match(/#LotteryWindow #LotteryMainCanvas #LotteryItemList \{[^\n]*width:(\d+)px; height:(\d+)px;/);
assert(box && bounds);
const positions=cards.map((c,i)=>{
 assert.equal(c.style.margin,'0px');
 assert.equal(c.style.horizontalAlign,'left'); assert.equal(c.style.verticalAlign,'top');
 assert(c.children.some(n=>n.text===ten[i].name),'server result order preserved');
 assert(!c.BHasClass('LotteryCardCovered'));
 const p=c.style.position.match(/^(\d+)px (\d+)px 0px$/); assert(p);return [+p[1],+p[2]];
});
assert.equal(new Set(positions.map(p=>p[0])).size,5);
assert.equal(new Set(positions.map(p=>p[1])).size,2);
// Pixel rounding at windowed and fullscreen scales cannot push any card outside.
for(const [w,h] of [[962,409],[1280,720],[1600,900],[1920,1080],[2560,1440],[3440,1440]]){
 const scale=Math.min(w/1600,h/900);
 for(const [x,y] of positions){
  assert(Math.ceil((x + +box[1])*scale)<=Math.floor(+bounds[1]*scale),w+' horizontal clipping');
  assert(Math.ceil((y + +box[2])*scale)<=Math.floor(+bounds[2]*scale),h+' vertical clipping');
 }
}
ui.CloseResult(); ui.DrawSingle();
events.ui_lottery_result({ok:1,request_id:requests.at(-1).p.request_id,pool_id:'map',count:1,results:results(1),snapshot:snapshot('map',9)});
assert.equal(nodes.LotteryItemList.children.length,1);
assert(nodes.LotteryItemList.BHasClass('LotterySingleResult'));
assert.equal(nodes.LotteryItemList.children[0].style.position,undefined,'single result keeps centered CSS');
console.log('LOTTERY_TEN_LAYOUT_PASS: all 10 ordered cards, 5 x 2, six viewport sizes, single draw preserved');
`;
vm.runInNewContext(setup + '\nsuite+=' + JSON.stringify(checks) + ';\nvm.runInNewContext(suite,{require,console});',
 {require:require('module').createRequire(path.resolve('tools/test_lottery_ui.js')),console});
