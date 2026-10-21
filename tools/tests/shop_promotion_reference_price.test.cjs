'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),test=require('node:test');
const {harness,walletItem}=require('../shop_catalog_20261016/harness.cjs');
const root=path.resolve(__dirname,'../..');
function model(){
 const cfg={};vm.runInNewContext(fs.readFileSync(path.join(root,'panorama/src/scripts/custom_game/black_lion_market_model.js'),'utf8'),{GameUI:{CustomUIConfig:()=>cfg}});
 return cfg.SurvivalBlackLionMarketModel;
}
function points(sku,price,extra={}){return {...walletItem(0),sku,title:sku,price,...extra};}
function cash(sku,coins,extra={}){
 return {sku,title:sku,category_id:'item',product_type:'single',purchase_method:'cash',currency:'u_coin',
  u_coin_price:coins,amount_fen:coins,u_coin_per_yuan:100,enabled:1,owned:0,purchase_limit:0,reward_lines:[],...extra};
}
function data(){
 const odd=points('promo_odd',3),plain=points('plain',2),paid=cash('paid_promo',501,{original_u_coin_price:9999});
 const presentation={groups:{home:['promo_odd','plain','paid_promo'],promotions:['promo_odd'],all:['promo_odd','plain','paid_promo']}};
 const h=harness({presentation,paid:{catalog_hash:'price-fixture',products:[paid],categories:[]}});
 h.cfg.SurvivalCommerceView.Open();h.walletSnapshot([odd,plain]);h.cfg.SurvivalCommerceView.SelectCategory('all');
 return {h,odd,plain,paid};
}
function card(h,title){const found=h.cardList().find(row=>row.__menuCell.namePanel.text===title);assert(found,'A real product row exists for '+title);return found;}
const references=(h,row)=>h.descendants(row,'BLMarketPriceReference');
const center=panel=>parseFloat(panel.style.position.split(' ')[0])+parseFloat(panel.style.width)/2;

test('Only existing promotions get a 1.5x comparison; server grouping and price fields remain unchanged',()=>{
 const m=model();m.SetPresentation({groups:{home:[],promotions:['manual','archive_pass_monthly','u_coin_recharge'],all:[]}});
 const products=[points('manual',3),points('plain',3),cash('server_promo',501,{original_u_coin_price:9999}),
  cash('archive_pass_monthly',5800),cash('u_coin_recharge',100,{product_type:'recharge'}),
  cash('old_rate',100,{u_coin_per_yuan:1000,amount_fen:10,original_u_coin_price:1000}),
  points('hidden',10,{enabled:0,original_price:20}),points('free',0,{original_price:10})];
 const frozen=JSON.stringify(products),before=JSON.stringify(m.Groups({products}));
 assert.equal(m.InGroup(products[0],'promotions'),true,'The reviewed manual promotion list still counts');
 assert.equal(m.ReferencePrice(products[0]),4.5);assert.equal(m.ReferencePrice(products[2]),751.5);
 for(const index of[1,3,4,5,6,7])assert.equal(m.ReferencePrice(products[index]),null,products[index].sku);
 assert.equal(m.ReferencePrice(null),null);assert.equal(m.ReferencePrice({}),null);
 assert.equal(JSON.stringify(m.Groups({products})),before,'The display helper cannot promote ordinary goods or move bundles');
 assert.equal(JSON.stringify(products),frozen,'Neither current nor historical price metadata is rewritten');
 assert.equal(m.PurchaseTypes().find(row=>row.id==='u_coin').label,'G币');
 assert.equal(m.ChannelLabel(products[2]),'购买');
});

test('Promotion rows keep current prices and show a smaller crossed-out comparison beside them in every existing view',()=>{
 const {h}=data();
 let promo=card(h,'promo_odd'),plain=card(h,'plain');
 assert.equal(h.descendants(promo,'BLMarketPriceMain')[0].text,'3 积分');
 assert.equal(references(h,promo)[0].text,'4.5 积分');assert.equal(references(h,plain).length,0);
 assert.equal(center(h.descendants(promo,'BLMarketRowPrice')[0]),center(h.descendants(plain,'BLMarketRowPrice')[0]),'Wider comparison preserves the price-heading center');
 const line=h.descendants(promo,'BLMarketPriceLine')[0];
 assert.equal(line.style.flowChildren,'right');assert.equal(references(h,promo)[0].GetParent(),line);
 assert.equal(references(h,promo)[0].style.verticalAlign,'center');
 assert.equal(h.descendants(card(h,'paid_promo'),'BLMarketPriceMain')[0].text,'501 G币');
 assert.equal(references(h,card(h,'paid_promo'))[0].text,'751.5 G币','The visual comparison ignores a different stored historical original price');
 for(const category of['home','promotions','all']){
  h.cfg.SurvivalCommerceView.SelectCategory(category);promo=card(h,'promo_odd');
  assert.equal(references(h,promo)[0].text,'4.5 积分',category);
 }
 const css=fs.readFileSync(path.join(root,'panorama/src/styles/custom_game/black_lion_market.css'),'utf8');
 const reference=css.match(/\.BLMarketWindow \.BLMarketPriceReference\s*\{([^}]+)\}/)[1];
 const current=css.match(/\.BLMarketWindow \.BLMarketPriceMain\s*\{([^}]+)\}/)[1];
 assert.match(reference,/text-decoration:\s*line-through/);
 assert(Number(reference.match(/font-size:\s*(\d+)px/)[1])<Number(current.match(/font-size:\s*(\d+)px/)[1]));
 assert.equal(h.requests.filter(request=>['purchase','create'].includes(request.payload.action)).length,0);
});

test('Reference labels refresh with actual prices and the purchase routes still send only existing identifiers',()=>{
 const {h,odd,plain,paid}=data(),before=JSON.stringify({odd,plain,paid});
 h.walletSnapshot([{...odd,price:5},plain]);h.cfg.SurvivalCommerceView.SelectCategory('all');
 const updated=card(h,'promo_odd');assert.equal(h.descendants(updated,'BLMarketPriceMain')[0].text,'5 积分');
 assert.equal(references(h,updated)[0].text,'7.5 积分');
 h.descendants(updated,'BLMarketBuy')[0].events.onactivate();
 const confirmation=h.menus().find(menu=>menu.panel.BHasClass('MenuV10Exchange'));
 assert(confirmation&&confirmation.IsOpen());h.descendants(confirmation.actions,'CommerceConfirmBuy')[0].events.onactivate();
 const request=h.requests.findLast(value=>value.payload.action==='purchase');assert(request);assert.equal(request.payload.sku,'promo_odd');
 for(const field of['price','original_price','reference_price','u_coin_price','amount_fen'])assert(!Object.hasOwn(request.payload,field),field+' is not a client-authorized charge');
 h.cfg.SurvivalCommerceView.Open();h.cfg.SurvivalCommerceView.SelectCategory('all');
 h.descendants(card(h,'paid_promo'),'BLMarketBuy')[0].events.onactivate();assert.deepEqual(h.paidCheckouts,['paid_promo']);
 assert.equal(JSON.stringify({odd,plain,paid}),before,'Source data and both purchase identities remain untouched');
});

test('Legacy text is normalized to G-coins in market titles, balances and disabled messages without changing protocol fields',()=>{
 const {h}=data();h.store().SetResources([{name:'U币',value:123},{name:'积分',value:456}]);
 const texts=h.descendants(h.store().panel,'BLMarketBalanceText').map(node=>node.text);assert(texts.includes('G币 123'));
 const item=Object.freeze(cash('legacy_text',100,{title:'U币旧商品',required_vip_level:4,enabled:0,disabled_reason:'vip_level_insufficient',disabled_message:'需要U币权益'}));
 const before=JSON.stringify(item);const row=h.cfg.SurvivalBlackLionMarket.Row(h.root,item,{index:0,action(){throw Error('No purchase');},rewards:[]});
 assert.equal(row.__menuCell.namePanel.text,'G币旧商品');
 assert.equal(h.descendants(row,'BLMarketDisabledReason')[0].text,'需要G币权益');
 assert.equal(h.descendants(row,'BLMarketPriceMain')[0].text,'100 G币');
 assert.equal(item.currency,'u_coin');assert.equal(JSON.stringify(item),before);
});
