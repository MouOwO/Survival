"use strict";
const fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
let suite=fs.readFileSync('tools/test_commerce_wallet.cjs','utf8').split('catalog();assert.equal')[0];
if(process.argv[2]){
 const marker="const script=fs.readFileSync('panorama/src/scripts/custom_game/commerce_wallet.js','utf8');";
 if(!suite.includes(marker))throw Error('wallet_fixture_shape_changed');
 suite=suite.replace(marker,'const script=fs.readFileSync('+JSON.stringify(process.argv[2])+',"utf8");');
}
suite+=String.raw`
let now=0;timers.length=0;$.Schedule=(delay,fn)=>{const task={at:now+delay,fn};timers.push(task);return task;};
function advance(seconds){const stop=now+seconds;let count=0;for(;;){timers.sort((a,b)=>a.at-b.at);if(!timers.length||timers[0].at>stop)break;const task=timers.shift();now=task.at;task.fn();assert(++count<1000);}now=stop;}
function buy(){return panels.filter(p=>p.classes.has('CommerceConfirmBuy')&&!p.deleted).at(-1);}
catalog();assert(cfg.SurvivalCommerceWallet.Checkout(product.sku));buy().events.onactivate();
const purchase=requests.at(-1);assert.equal(purchase.action,'purchase');
advance(100);
assert.equal(cfg.SurvivalCommerceWallet.Refresh(),false,'UI waits for all three 32s attempts plus gaps and delivery transit');
respond({ok:1,terminal:1,sku:product.sku,currency:'shop_points',balance:3200});
assert.equal(cfg.SurvivalCommercePending,null);assert.equal(snapshot.balances.shop_points,3200,'late authoritative result still refreshes the wallet');
// A separate authoritative reward funds another purchase before its reply race.
advance(1.2);respond({ok:1,part:'begin',count:1,balances:{shop_points:10000},categories:[]});respond({ok:1,part:'product',index:1,product});respond({ok:1,part:'end'});
assert(cfg.SurvivalCommerceWallet.Checkout(product.sku));buy().events.onactivate();const uncertain=requests.at(-1);
advance(106);assert.equal(cfg.SurvivalCommercePending.id,uncertain.request_id,'timeout preserves the original operation identity');
assert(cfg.SurvivalCommerceWallet.Refresh());const fresh=requests.at(-1);
respond({ok:1,terminal:1,action:'purchase',request_id:uncertain.request_id,currency:'shop_points',balance:1});
assert.equal(cfg.SurvivalCommerceWallet.Refresh(),false,'old purchase cannot release a current catalogue');
assert.equal(snapshot.balances.shop_points,10000,'old purchase cannot publish a stale balance');
respond({ok:1,part:'begin',count:1,balances:{shop_points:9000},categories:[]});respond({ok:1,part:'product',index:1,product});respond({ok:1,part:'end'});
assert(cfg.SurvivalCommerceWallet.Checkout(product.sku));buy().events.onactivate();
assert.equal(requests.at(-1).request_id,uncertain.request_id,'manual recovery queries the same durable operation instead of a second debit');
cfg.SurvivalCommerceWallet.Dispose();
console.log('COMMERCE_TRANSPORT_UI_PASS: 100s accepted completion, 105s finite UI limit, same-ID recovery, late/new catalogue isolation and Dispose; real_gateway_calls=0');
`;
vm.runInNewContext(suite,{require:require('node:module').createRequire(path.resolve('tools/test_commerce_wallet.cjs')),console});
