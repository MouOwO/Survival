"use strict";
const test=require('node:test'),assert=require('node:assert/strict');
const {harness,walletItem}=require('./harness.cjs');
const array=value=>JSON.parse(JSON.stringify(value));
function cash(sku,overrides={}){return {sku,title:sku,category_id:'item',product_type:'single',enabled:true,owned:0,purchase_limit:0,
 amount_fen:1000,currency:'u_coin',u_coin_price:1000,u_coin_per_yuan:100,reward_lines:[],...overrides};}
function setup(products=[],presentation={groups:{home:[]}}){return harness({paid:{catalog_hash:'OFFLINE_ONLY',categories:[],products},presentation});}
function choose(h,id='all'){h.cfg.SurvivalCommerceView.Open();assert(h.cfg.SurvivalCommerceView.SelectCategory(id));}
const rowBuy=(h,row)=>h.descendants(row,'BLMarketBuy')[0];
const rowReason=(h,row)=>h.descendants(row,'BLMarketDisabledReason')[0];
const buyRequests=h=>h.requests.filter(r=>r.payload.action==='purchase');

test('Owned unique products disappear, repeatable stock remains, and unknown ownership is not zero',()=>{
 const h=setup(),K=h.cfg.SurvivalBlackLionMarketModel,unique={...walletItem('unique'),purchase_limit:1,owned:1};
 assert.equal(K.IsListed(unique),false);assert.equal(K.IsListed({...unique,owned:'1',purchase_limit:'1'}),false);
 assert.equal(K.IsListed({...unique,purchase_limit:0,owned:57}),true,'Repeatable inventory does not use the one-off ownership rule');
 for(const owned of [undefined,null,'—']){const item={...unique,owned};const before=JSON.stringify(item);assert.equal(K.IsListed(item),true);assert.equal(JSON.stringify(item),before,'Unknown values are never rewritten to zero');}
 assert.equal(K.IsListed({...unique,owned:0,enabled:false,disabled_reason:'already_owned'}),false,'A free VIP claim may set the server reason without a product inventory counter');
});

test('Unlisted, preview-only, paused currencies and invalid prices never appear as orderable goods',()=>{
 const h=setup(),K=h.cfg.SurvivalBlackLionMarketModel;
 for(const item of [cash('preview',{preview_only:true}),cash('pending',{disabled_reason:'payment_catalog_pending'}),
  cash('unavailable',{disabled_reason:'payment_product_unavailable'}),cash('price-pending',{disabled_reason:'payment_price_unavailable'}),
  cash('mismatch',{u_coin_price:1001}),cash('fractional-fen',{amount_fen:100.1}),cash('over-cap',{amount_fen:1000001,u_coin_price:10000010}),
  {...walletItem('gold'),currency:'shop_gold'},{...walletItem('negative'),price:-1},cash('unknown',{enabled:false,disabled_reason:'future_unknown_reason'})]){
  assert.equal(K.IsListed(item),false,item.sku);assert.equal(K.IsActionable(item),false,item.sku);
 }
 h.cfg.VideoShopBundleCatalog={products:[cash('ghost',{product_type:'bundle'})]};h.updatePaid({catalog_hash:'EMPTY_FORMAL',products:[],categories:[]});choose(h);
 assert.equal(h.cfg.SurvivalCommerceView.Inspect().productCount,0);assert.deepEqual(array(h.cfg.SurvivalCommerceView.Inspect().visibleSkus),[],'Metadata cannot mint an absent formal SKU');
 assert.equal(h.paidCheckouts.length,0);assert.equal(buyRequests(h).length,0);
});

test('All five group counts and explicit video order follow the visible real catalog; new formal SKUs append',()=>{
 const presentation={groups:{home:['bonus','primary'],bundles:['bundle'],promotions:['promo','primary'],vip:['vip'],all:['primary','bundle','promo','vip','bonus']}};
 const products=[cash('extra',{sort_order:0}),cash('bonus'),cash('promo',{original_u_coin_price:2000}),cash('vip',{product_type:'bundle',required_vip_level:5,enabled:false,disabled_reason:'vip_level_required'}),
  cash('bundle',{product_type:'bundle',category_id:'bundles'}),cash('primary'),cash('owned',{purchase_limit:1,owned:1})];
 const before=JSON.stringify(products),h=setup(products,presentation);choose(h);
 assert.deepEqual(array(h.cfg.SurvivalCommerceView.Inspect().groups).map(g=>[g.id,g.count]),[['home',2],['bundles',1],['promotions',2],['vip',1],['all',4]]);
 for(const[group,expected]of Object.entries({home:['bonus','primary'],bundles:['bundle'],promotions:['promo','primary'],vip:['vip'],all:['primary','promo','bonus','extra']})){
  h.cfg.SurvivalCommerceView.SelectCategory(group);assert.deepEqual(array(h.cfg.SurvivalCommerceView.Inspect().visibleSkus),expected,group);
  assert.equal(h.cardList().length,expected.length,group+' rendered row count');
 }
 assert.equal(JSON.stringify(products),before,'Grouping never changes formal price, SKU, type, grant or quantity');
 assert.equal(h.paidCheckouts.length,0);
});

test('VIP restriction states the actual level, disables the row action and never guesses a missing level',()=>{
 const h=setup([cash('vip7',{required_vip_level:7,enabled:false,disabled_reason:'vip_level_insufficient',product_type:'bundle'})]);choose(h,'vip');
 const row=h.cardList()[0],button=rowBuy(h,row);assert.equal(button.enabled,false);assert.equal(rowReason(h,row).text,'需要 VIP 7 才可购买');
 button.events.onactivate();row.events.onactivate();assert.equal(h.paidCheckouts.length,0);assert.equal(buyRequests(h).length,0,'Tooltip/disabled callback cannot create an order');
 const K=h.cfg.SurvivalBlackLionMarketModel;
 assert.equal(K.DisabledMessage(cash('unknown-vip',{product_type:'bundle',enabled:false,disabled_reason:'vip_level_required'})),'VIP 等级不足');
 assert.equal(K.DisabledMessage(cash('message',{disabled_message:'服务端资格说明'})),'服务端资格说明','Server-supplied explanations remain authoritative');
 h.updatePaid({catalog_hash:'ELIGIBLE',products:[cash('vip7',{required_vip_level:7,product_type:'bundle'})],categories:[]});
 assert.equal(rowBuy(h,h.cardList()[0]).enabled,true,'A later authenticated VIP change enables the same item');
});

test('Insufficient points keep exchange centered and show only a native error on click',()=>{
 for(const disabled_reason of ['commerce_balance_insufficient','insufficient_balance']){
  const h=setup();choose(h);h.walletSnapshot([{...walletItem('short'),enabled:false,disabled_reason}],{u_coin:0,shop_points:0,shop_gold:0});
  const row=h.cardList()[0],button=rowBuy(h,row);assert.equal(button.enabled,true);
  assert.equal(rowReason(h,row).visible,false);assert.equal(rowReason(h,row).text,'');
  assert.equal(row.style.height,'64px');assert.equal(button.style.position,'932px 14px 0px','Exchange aligns with the ordinary purchase button');
  button.events.onactivate();
  assert(!h.menus().some(m=>m.panel.BHasClass('MenuV10Exchange')&&m.IsOpen()),'No disabled confirmation opens');
  assert.deepEqual(array(h.clientEvents),[{name:'dota_hud_error_message',payload:{reason:80,message:'您的积分不足'}}]);
  assert(h.cfg.SurvivalCommerceView.IsOpen(),'The store remains open after the native error');
  assert.equal(buyRequests(h).length,0);assert.equal(h.paidCheckouts.length,0);
 }
});

test('Changing only purchase_limit invalidates the list while numeric previews preserve a hovered card',()=>{
 const item=cash('limit',{owned:1,purchase_limit:0}),h=setup([item]);choose(h);const stable=h.cardList()[0];stable.events.onmouseover();
 h.updatePaid({catalog_hash:'OFFLINE_ONLY',products:[{...item,stat_preview:[{value:999}]}],categories:[]});
 assert.equal(h.cardList()[0],stable,'Numeric preview changes do not destroy hovered rows');
 h.updatePaid({catalog_hash:'OFFLINE_ONLY',products:[{...item,purchase_limit:1}],categories:[]});
 assert.equal(h.cfg.SurvivalCommerceView.Inspect().productCount,0);assert.equal(h.cardList().some(row=>row.BHasClass('BLMarketRow')),false,'A one-field limit change removes the now-owned item');
 h.updatePaid({catalog_hash:'OFFLINE_ONLY',products:[item],categories:[]});assert.equal(h.cfg.SurvivalCommerceView.Inspect().productCount,1,'Removing the limit restores a repeatable product');
});

test('Successful wallet purchase plus fresh catalog removes the unique product and updates all counts',()=>{
 const unique={...walletItem('one-off'),purchase_limit:1},h=setup();choose(h);h.walletSnapshot([unique]);const before=JSON.stringify(unique);
 const stale=rowBuy(h,h.cardList()[0]).events.onactivate;stale();assert.equal(buyRequests(h).length,0,'List action only opens confirmation');
 const confirm=h.menus().find(m=>m.panel.BHasClass('MenuV10Exchange'));h.descendants(confirm.actions,'CommerceConfirmBuy')[0].events.onactivate();
 const purchase=buyRequests(h).at(-1);assert(purchase);assert.equal(purchase.payload.sku,unique.sku);
 h.emit('survival_commerce_result',{ok:true,terminal:true,action:'purchase',request_id:purchase.payload.request_id,currency:'shop_points',balance:490});
 h.walletSnapshot([{...unique,enabled:false,owned:1,disabled_reason:'already_owned'}]);
 assert.equal(h.cfg.SurvivalCommerceView.Inspect().productCount,0);assert(h.cfg.SurvivalCommerceView.Inspect().groups.every(g=>g.count===0));
 stale();assert.equal(buyRequests(h).length,1,'Deleted row callbacks cannot repurchase an owned item');assert.equal(JSON.stringify(unique),before,'Receipt refresh never rewrites the original catalog object');
});

test('Changing only VIP reason/message/required level redraws the visible explanation',()=>{
 const item=cash('vip',{product_type:'bundle',enabled:false,required_vip_level:4,disabled_reason:'vip_level_insufficient'}),h=setup([item]);choose(h,'vip');const first=h.cardList()[0];
 h.updatePaid({catalog_hash:'OFFLINE_ONLY',products:[{...item,required_vip_level:8}],categories:[]});assert.notEqual(h.cardList()[0],first);assert.equal(rowReason(h,h.cardList()[0]).text,'需要 VIP 8 才可购买');
 h.updatePaid({catalog_hash:'OFFLINE_ONLY',products:[{...item,required_vip_level:8,disabled_message:'VIP资格正在同步'}],categories:[]});assert.equal(rowReason(h,h.cardList()[0]).text,'VIP资格正在同步');
});

test('U-coin cash price and eligibility come from payment rows, never a wallet balance or a metadata ghost',()=>{
 const real=cash('cash-authority',{amount_fen:6800,u_coin_price:6800}),h=setup([real]);choose(h);
 h.walletSnapshot([{...walletItem('unused'),sku:real.sku,currency:'u_coin',price:1,enabled:false,disabled_reason:'commerce_balance_insufficient'}],{u_coin:0,shop_points:0,shop_gold:0});
 let row=h.cardList()[0];assert.equal(rowBuy(h,row).enabled,true);assert.equal(h.descendants(row,'BLMarketPriceMain')[0].text,'6800 U币');
 rowBuy(h,row).events.onactivate();assert.deepEqual(h.paidCheckouts,[real.sku]);assert.equal(buyRequests(h).length,0,'The U-coin marker is a cash price, not wallet deduction');
 h.updatePaid({catalog_hash:'PRICE_CHANGED',products:[{...real,u_coin_price:6801}],categories:[]});assert.equal(h.cfg.SurvivalCommerceView.Inspect().productCount,0,'A mismatched fen / U-coin pair cannot expose a purchase button');
});


test('A purchase-owned wallet update hides the unique cash SKU while an older payment snapshot lags',()=>{
 const real=cash('owned-race',{purchase_limit:1,amount_fen:6800,u_coin_price:6800}),h=setup([real]);choose(h);
 const wallet={...walletItem('unused'),sku:real.sku,currency:'u_coin',price:1,purchase_limit:1,owned:0,enabled:false,disabled_reason:'commerce_balance_insufficient'};
 h.walletSnapshot([wallet],{u_coin:0,shop_points:0,shop_gold:0});
 assert.equal(rowBuy(h,h.cardList()[0]).enabled,true,'Wallet affordability cannot disable an authorized cash purchase');
 assert.equal(h.descendants(h.cardList()[0],'BLMarketPriceMain')[0].text,'6800 U币','The cash price remains authoritative');
 h.walletSnapshot([{...wallet,owned:1,disabled_reason:'already_owned'}]);
 assert.equal(h.cfg.SurvivalCommerceView.Inspect().productCount,0,'The older cash owned=0 snapshot must not resurrect a just-owned unique item');
 assert.equal(h.paid.products[0].owned,0,'The merge must not overwrite the raw payment catalog');
 h.updatePaid({catalog_hash:'RESET_PAID',products:[{...real,owned:0}],categories:[]});
 assert.equal(h.cfg.SurvivalCommerceView.Inspect().productCount,0,'Resetting only one side cannot override a confirmed owned item');
 h.walletSnapshot([{...wallet,owned:0}]);
 assert.equal(h.cfg.SurvivalCommerceView.Inspect().productCount,1,'After both formal snapshots explicitly reset ownership the product can reappear');
 assert.equal(rowBuy(h,h.cardList()[0]).enabled,true);assert.equal(h.paidCheckouts.length,0);assert.equal(buyRequests(h).length,0);
});
