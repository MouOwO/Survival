const fs=require('fs'),vm=require('vm');
let suite=fs.readFileSync(__dirname+'/test_shop_shared_ui.cjs','utf8');
suite=suite.replace('const root=new Panel','Panel.prototype.SetScaling=function(v){this.scaling=v;};Panel.prototype.Children=function(){return this.children;};const root=new Panel');
suite=suite.replace("vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/shop_ui.js','utf8'),env);", "vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/remaining_5d5c1152eb.js','utf8'),env);vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/shop_remaining_5d5c1152eb.js','utf8'),env);");
suite=suite.replace('assert.equal(jobs.size,0);', 'for(const [id,fn] of [...jobs]){jobs.delete(id);fn();}assert.equal(jobs.size,0);assert.equal(nodes.CustomShopWindow.visible,false);');
suite=suite.replace('const U=cfg.SurvivalUI', 'env.CustomNetTables={GetTableValue:()=>({})};env.Game.GetLocalPlayerID=()=>0;const U=cfg.SurvivalUI');
suite+=`\nconst parent=new Panel('Panel');U.PriceLabel(parent,{prices:[{amount:12,currencyName:'U币'},{amount:20,currencyName:'积分'}]});function find(p,c){let out=p.classes.has(c)?[p]:[];for(const x of p.children)out=out.concat(find(x,c));return out;}assert.equal(find(parent,'UIPriceCurrencyIcon').length,1);assert.deepEqual(find(parent,'UIPrice').map(p=>p.text),['12','20 积分']);assert(nodes.CustomShopWindow.BHasClass('RHSurvivalShop'));console.log('SHOP_PRESENTATION_PASS: accepted helper + actual shop controller, currency icon/text distinction');`;
suite+=`
assert.equal(nodes.CustomShopWindow.style.width,'680px');assert.equal(nodes.CustomShopWindow.style.height,'600px');
assert(!nodes.ShopModeLottery && !nodes.ShopRefreshButton);
shop.SetUnlocks({shop:false});assert.equal(cfg.SurvivalShopUnlocks.shop,false);
// The shared fixture finishes in research after remembering challenge mode.
// Explicitly select the shop before testing a shop-mode response.
shop.SetUnlocks({shop:true});assert.equal(cfg.SurvivalShopUnlocks.shop,true);shop.SelectShop();
const compact={...good,stock:0,stock_max:0,purchase_limit:5,owned_count:2,gold_cost:200,wood_cost:0};
events.ui_shop_snapshot({sequence:2,full:1,ui_mode:'shop',entries:[compact],categories:[],resources:{wood:1000,gold:1000}});
const tile=cards()[0];assert.equal(tile.__survivalStockLabel.text,'3/5');assert.equal(tile.__survivalStockLabel.visible,false,'native stock label stays hidden, internal remaining stock remains correct');
assert.equal(find(tile,'RHShopPrices').length,0);assert.equal(tile.__rhPrices,undefined);
assert.equal(find(tile,'RHShopHover').length,0);assert.equal(find(tile,'RHShopName').length,0);
tile.events.oncontextmenu();assert.equal(requests.at(-1).n,'ui_shop_purchase_request');
assert.equal(nodes.CustomShopWindow.style.horizontalAlign,'left');
assert.equal(nodes.CustomShopWindow.style.position,'16px 240px 0px');
shop.Close();assert.equal(nodes.CustomShopWindow.hittestchildren,false);assert(nodes.CustomShopWindow.style.position.startsWith('-'));
assert.equal(nodes.CustomShopWindow.visible,true,'remain visible while sliding out');
const oldClose=[...jobs.values()];shop.Open();for(const fn of oldClose)fn();assert.equal(nodes.CustomShopWindow.visible,true,'old close callback cannot hide reopened drawer');
root.actuallayoutwidth=1280;root.actuallayoutheight=720;nodes.CustomShopWindow.actuallayoutwidth=680*(2/3);shop.Close();assert(parseFloat(nodes.CustomShopWindow.style.position)+680*(2/3)<=-12,'fixed 680px reference window exits fully after actual 720p Fit scale');
for(const [id,fn] of [...jobs]){jobs.delete(id);fn();}assert.equal(nodes.CustomShopWindow.visible,false,'hide full panel after exit animation');
assert.equal(jobs.size,0);shop.Close();assert.equal(nodes.CustomShopWindow.visible,false);assert.equal(jobs.size,0);
root.actuallayoutwidth=1920;root.actuallayoutheight=1080;
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/native_ui_icons.js','utf8'),env);
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/item_art_remaining_5d5c1152eb.js','utf8'),env);
const sword=cfg.SurvivalItemArt.Create(parent,{content_id:'weapon_growth_sword_01',icon:'item_broadsword'},'icon');assert.equal(sword.image,'file://{images}/items/broadsword.png');
const red=cfg.SurvivalItemArt.Create(parent,{content_id:'item_knowledge_book'},'icon'),blue=cfg.SurvivalItemArt.Create(parent,{content_id:'item_super_knowledge_book'},'icon');
assert.equal(red.image,'file://{images}/items/tome_of_knowledge.png');assert.notEqual(red.image,blue.image);
const nativeManifest=JSON.parse(fs.readFileSync('panorama/src/images/custom_game/shop_v2/inventory_manifest.json','utf8'));
for(const[id,value]of Object.entries(nativeManifest.icons))assert.equal(cfg.SurvivalItemArt.Create(parent,{content_id:id},'icon').image,value.uri,id);
console.log('SHOP_V2_PASS: native item families, challenge skill icons, drawer positioning, repeat stock, icon-only tiles, right-click preserved');
`;
suite+=`
shop.OpenChallenge();assert.equal(nodes.ShopTitle.text,'生存商店','challenge request mode does not replace the reference title');assert.equal(requests.at(-1).p.mode,'challenge');shop.SelectOther();assert.equal(nodes.ShopTitle.text,'生存商店','other category preserves reference title');let now=100;env.Game.GetGameTime=()=>now;
const early={...good,entry_id:'early',content_id:'service_early_final_boss',purchasable:1,
 early_final_cooldown_remaining:60,early_final_cooldown_total:60,early_final_cooldown_until:160};
events.ui_shop_snapshot({sequence:3,full:1,ui_mode:'shop',entries:[early],categories:[],resources:{}});
const earlyCard=cards()[0],mask=earlyCard.__survivalCooldownMask;
assert.equal(mask.style.position,'0px 0px 0px');assert.equal(mask.style.zIndex,'5');
assert.equal(mask.style.backgroundColor,'#000000cc');assert.equal(mask.hittestchildren,false);
assert(mask.visible);assert(mask.style.clip.includes('360.00deg'));
let sent=requests.length;earlyCard.events.oncontextmenu();assert.equal(requests.length,sent,'cooldown blocks even stale purchasable flag');
function tick(){for(const [id,fn] of [...jobs]){jobs.delete(id);fn();}}
now=130;tick();assert(mask.style.clip.includes('180.00deg'));
now=160;sent=requests.length;tick();assert.equal(mask.visible,false);
assert.equal(requests.length,sent+1,'expiry requests authoritative availability');
tick();assert.equal(requests.length,sent+1,'expiry refresh is not repeated');
earlyCard.events.oncontextmenu();assert.equal(requests.at(-1).n,'ui_shop_purchase_request');
console.log('SHOP_EARLY_COOLDOWN_PASS: radial full/half/expired, input lock, single refresh');
shop.SelectShop();let stockSequence=3;
function showStock(row){events.ui_shop_snapshot({sequence:++stockSequence,full:1,ui_mode:'shop',entries:[row],categories:[],resources:{}});return cards()[0];}
let stockTile=showStock({...good,stock:0,stock_max:5,purchasable:0});
assert(stockTile.BHasClass('StockEmpty'));assert.equal(stockTile.__survivalStockLabel.text,'0/5');assert.equal(stockTile.__survivalStockLabel.visible,false);
stockTile=showStock({...good,stock:1,stock_max:5,purchasable:0,disabled_reason_code:'insufficient_gold'});
assert(!stockTile.BHasClass('StockEmpty'),'resource shortage does not gray stocked items');assert.equal(stockTile.__survivalStockLabel.text,'1/5');assert.equal(stockTile.__survivalStockLabel.visible,false,'replenishment does not revive the hidden stock label');
stockTile=showStock({...good,stock:0,stock_max:0,purchase_limit:5,owned_count:5,purchasable:0});
assert(stockTile.BHasClass('StockEmpty'),'exhausted repeat purchase stock is gray');assert.equal(stockTile.__survivalStockLabel.text,'0/5');assert.equal(stockTile.__survivalStockLabel.visible,false);
stockTile=showStock({...good,stock:0,stock_max:0,purchase_limit:0});
assert(!stockTile.BHasClass('StockEmpty'),'unlimited stock is not empty');
console.log('SHOP_STOCK_GRAY_PASS: empty, replenished, resource shortage, repeat limit and unlimited stock');
for(const content_id of ['weapon_growth_sword_01','item_death_mask','item_small_polar_crystal']){
 const single={...good,content_id,stock:0,stock_max:0,purchase_limit:1,owned_count:0};
 assert(!showStock(single).BHasClass('StockEmpty'),'single purchase item starts in color');
 const bought=showStock({...single,owned_count:1,purchasable:0,disabled_reason_code:'purchase_limit_reached'});
 assert(bought.BHasClass('StockEmpty'),'purchased single-use stock is gray');
 assert(!bought.__survivalStockLabel,'do not add a stock label for single purchase items');
 assert(!showStock({...single,purchasable:0,disabled_reason_code:'insufficient_gold'}).BHasClass('StockEmpty'));
}
console.log('SHOP_SINGLE_PURCHASE_GRAY_PASS: growth sword and death mask purchased/unpurchased states');
let crystal=showStock({...good,content_id:'item_small_polar_crystal',stock:0,stock_max:0,purchase_limit:1,owned_count:0});
const baseSequence=stockSequence;
events.ui_shop_snapshot({sequence:++stockSequence,base_sequence:baseSequence,full:0,ui_mode:'shop',categories:[],
 changed_entries:[{...good,content_id:'item_small_polar_crystal',stock:0,stock_max:0,purchase_limit:1,owned_count:1,purchasable:0,disabled_reason_code:'purchase_limit_reached'}]});
assert.strictEqual(cards()[0],crystal);assert(crystal.BHasClass('StockEmpty'),'category refresh must update purchased crystal without rebuilding layout');
`;
vm.runInNewContext(suite,{require,console,__dirname},{filename:__filename});
