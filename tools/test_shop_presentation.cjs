const fs=require('fs'),vm=require('vm');
let suite=fs.readFileSync(__dirname+'/test_shop_shared_ui.cjs','utf8');
suite=suite.replace('const root=new Panel','Panel.prototype.SetScaling=function(v){this.scaling=v;};Panel.prototype.Children=function(){return this.children;};const root=new Panel');
suite=suite.replace("vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/shop_ui.js','utf8'),env);", "vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/remaining_5d5c1152eb.js','utf8'),env);vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/shop_remaining_5d5c1152eb.js','utf8'),env);");
suite=suite.replace('assert.equal(jobs.size,0);', 'for(const [id,fn] of [...jobs]){jobs.delete(id);fn();}assert.equal(jobs.size,0);assert.equal(nodes.CustomShopWindow.visible,false);');
suite+=`\nconst parent=new Panel('Panel');U.PriceLabel(parent,{prices:[{amount:12,currencyName:'U币'},{amount:20,currencyName:'积分'}]});function find(p,c){let out=p.classes.has(c)?[p]:[];for(const x of p.children)out=out.concat(find(x,c));return out;}assert.equal(find(parent,'UIPriceCurrencyIcon').length,1);assert.deepEqual(find(parent,'UIPrice').map(p=>p.text),['12','20 积分']);assert(nodes.CustomShopWindow.BHasClass('RHSurvivalShop'));console.log('SHOP_PRESENTATION_PASS: accepted helper + actual shop controller, currency icon/text distinction');`;
suite+=`
assert.equal(nodes.CustomShopWindow.style.width,'604px');
assert(!nodes.ShopModeLottery && !nodes.ShopRefreshButton);
shop.SetUnlocks({shop:false});assert.equal(cfg.SurvivalShopUnlocks.shop,false);
shop.SetUnlocks({shop:true});assert.equal(cfg.SurvivalShopUnlocks.shop,true);shop.Open();
const compact={...good,stock:0,stock_max:0,purchase_limit:5,owned_count:2,gold_cost:200,wood_cost:0};
events.ui_shop_snapshot({sequence:2,full:1,ui_mode:'shop',entries:[compact],categories:[],resources:{wood:1000,gold:1000}});
const tile=cards()[0];assert.equal(tile.__survivalStockLabel.text,'3/5');
assert.equal(find(tile,'RHShopPrices').length,0);assert.equal(tile.__rhPrices,undefined);
assert.equal(find(tile,'RHShopHover').length,0);assert.equal(find(tile,'RHShopName').length,0);
tile.events.oncontextmenu();assert.equal(requests.at(-1).n,'ui_shop_purchase_request');
assert.equal(nodes.CustomShopWindow.style.horizontalAlign,'left');
assert.equal(nodes.CustomShopWindow.style.position,'0px 0px 0px');
shop.Close();assert.equal(nodes.CustomShopWindow.hittestchildren,false);assert(nodes.CustomShopWindow.style.position.startsWith('-'));
assert.equal(nodes.CustomShopWindow.visible,true,'remain visible while sliding out');
const oldClose=[...jobs.values()];shop.Open();for(const fn of oldClose)fn();assert.equal(nodes.CustomShopWindow.visible,true,'old close callback cannot hide reopened drawer');
nodes.CustomShopWindow.actuallayoutwidth=1600;shop.Close();assert(parseFloat(nodes.CustomShopWindow.style.position)<=-1680,'account for measured scaled width');
for(const [id,fn] of [...jobs]){jobs.delete(id);fn();}assert.equal(nodes.CustomShopWindow.visible,false,'hide full panel after exit animation');
assert.equal(jobs.size,0);shop.Close();assert.equal(nodes.CustomShopWindow.visible,false);assert.equal(jobs.size,0);
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/item_art_remaining_5d5c1152eb.js','utf8'),env);
const sword=cfg.SurvivalItemArt.Create(parent,{content_id:'weapon_growth_sword_01',icon:'item_broadsword'},'icon');assert(sword.image.includes('items/survival_shop_v2/swords_00.png'));
const red=cfg.SurvivalItemArt.Create(parent,{content_id:'item_knowledge_book'},'icon'),blue=cfg.SurvivalItemArt.Create(parent,{content_id:'item_super_knowledge_book'},'icon');
assert(red.image.includes('items/survival_shop_v2/shop_07.png'));assert.notEqual(red.image,blue.image);
for(const family of ['growth_sword','frost_blade','ice_blade','epic_icefire','legend_abyss'])for(let level=0;level<=10;level++){
 const icon=cfg.SurvivalItemArt.Create(parent,{content_id:'weapon_'+family+'_'+String(level).padStart(2,'0')},'icon');assert(icon.image.includes('/swords_'));
}
for(let level=1;level<=11;level++){const icon=cfg.SurvivalItemArt.Create(parent,{content_id:'challenge_'+String(level).padStart(2,'0')},'icon');assert(icon.image.includes('/challenges_'));}
for(let level=1;level<=10;level++){const icon=cfg.SurvivalItemArt.Create(parent,{content_id:'rebirth_challenge_'+String(level).padStart(2,'0')},'icon');assert(icon.image.includes('/challenges_'));}
console.log('SHOP_V2_PASS: original art families, challenge art, drawer positioning, repeat stock, icon-only tiles, right-click preserved');
`;
suite+=`
shop.Open();let now=100;env.Game.GetGameTime=()=>now;
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
let stockSequence=3;
function showStock(row){events.ui_shop_snapshot({sequence:++stockSequence,full:1,ui_mode:'shop',entries:[row],categories:[],resources:{}});return cards()[0];}
let stockTile=showStock({...good,stock:0,stock_max:5,purchasable:0});
assert(stockTile.BHasClass('StockEmpty'));assert.equal(stockTile.__survivalStockLabel.text,'0/5');
stockTile=showStock({...good,stock:1,stock_max:5,purchasable:0,disabled_reason_code:'insufficient_gold'});
assert(!stockTile.BHasClass('StockEmpty'),'resource shortage does not gray stocked items');
stockTile=showStock({...good,stock:0,stock_max:0,purchase_limit:5,owned_count:5,purchasable:0});
assert(stockTile.BHasClass('StockEmpty'),'exhausted repeat purchase stock is gray');
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
