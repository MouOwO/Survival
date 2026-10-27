"use strict";
const fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
let suite=fs.readFileSync('tools/test_commerce_wallet.cjs','utf8').split('catalog();assert.equal')[0];
suite+=String.raw`
let now=0;timers.length=0;$.Schedule=(delay,fn)=>{const t={at:now+delay,fn};timers.push(t);return t;};
function advance(seconds){const end=now+seconds;let guard=0;for(;;){timers.sort((a,b)=>a.at-b.at);if(!timers.length||timers[0].at>end)break;const t=timers.shift();now=t.at;t.fn();assert(++guard<1000);}now=end;}
function catalogResult(balance){respond({ok:1,part:'begin',count:1,balances:{u_coin:0,shop_points:balance,shop_gold:0},categories:[]});respond({ok:1,part:'product',index:1,product});respond({ok:1,part:'end'});}
assert.equal(typeof cfg.SurvivalCommerceWallet.Invalidate,'function','wallet needs a queued invalidation API');
assert(cfg.SurvivalCommerceWallet.Refresh());catalogResult(10000);assert.equal(snapshot.balances.shop_points,10000);
assert(cfg.SurvivalCommerceWallet.Refresh());const old=requests.at(-1);assert.equal(cfg.SurvivalCommerceWallet.Refresh(),false,'public busy return contract remains unchanged');
for(let i=0;i<100;i++)assert(cfg.SurvivalCommerceWallet.Invalidate('draw_same'));
assert.equal(requests.at(-1),old,'busy invalidation must not dispatch another concurrent request');
catalogResult(20);assert.equal(snapshot.balances.shop_points,10000,'stale pre-reward catalog must not overwrite the known wallet');
const before=requests.length;advance(1.2);assert.equal(requests.length,before+1,'coalesced invalidation issues one follow-up catalog');
catalogResult(10400);assert.equal(snapshot.balances.shop_points,10400);
advance(5);assert.equal(requests.length,before+1,'settled invalidation has no idle polling');
cfg.SurvivalCommerceWallet.Invalidate('next_draw');advance(1.2);
respond({ok:0,terminal:0,error:'commerce_busy'});const retryBefore=requests.length;advance(1.2);assert.equal(requests.length,retryBefore+1,'transient busy is retried');
respond({ok:0,terminal:0,error:'commerce_busy'});advance(4);respond({ok:0,terminal:0,error:'commerce_busy'});
const bounded=requests.length;advance(30);assert.equal(requests.length,bounded,'failure retries are bounded');
assert(cfg.SurvivalCommerceWallet.Refresh());catalogResult(10800);assert.equal(snapshot.balances.shop_points,10800,'manual refresh recovers after bounded retries');
product.enabled=0;product.disabled_reason='shop_gold_not_open';product.currency='shop_gold';cfg.SurvivalCommerceWallet.Refresh();catalogResult(10800);assert.equal(cfg.SurvivalCommerceWallet.Checkout(product.sku),false);
const status=panels.find(p=>p.classes.has('CommerceResultStatus')&&!p.deleted);assert(status.text.includes('商城金币暂未开放'),'closed currency gets explicit Chinese message');
cfg.SurvivalCommerceWallet.Invalidate('dispose_pending');const stopped=requests.length;cfg.SurvivalCommerceWallet.Dispose();advance(60);assert.equal(requests.length,stopped,'dispose cancels dirty maintenance');
console.log('COMMERCE_WALLET_INVALIDATION_PASS: busy API compatibility, coalescing, stale rejection, retry bounds, manual recovery, gold gate and dispose');
`;
vm.runInNewContext(suite,{require:require('node:module').createRequire(path.resolve('tools/test_commerce_wallet.cjs')),console});
