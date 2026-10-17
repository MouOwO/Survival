'use strict';
// Final readably sized marketplace replacements. Never enlarge legacy inventory sprites.
const fs=require('fs'),path=require('path'),assert=require('assert/strict'),crypto=require('crypto');
const root=path.resolve(__dirname,'../..'),file=path.join(root,'data/ui/item_resources.json'),out=path.join(root,'output/shop_icon_quality_20261017');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex'),beforeBytes=fs.readFileSync(file),table=JSON.parse(beforeBytes);
const assets=[...JSON.parse(fs.readFileSync(path.join(out,'native/manifest.json'))).records,...JSON.parse(fs.readFileSync(path.join(out,'axe_candidates/manifest.json'))).records];
const changes=[];
function set(id,uri,size,concept){const row=table.items.find(r=>r.id===id);assert(row,id);assert(Math.min(...size)>=128,id+' true source size');const before=JSON.parse(JSON.stringify(row));row.kind='image';row.uri=uri;row.source_size=size;delete row.native_type;delete row.native_name;changes.push({id,concept,before,after:JSON.parse(JSON.stringify(row))});}
function native(id,relative,concept){const uri='file://{images}/'+relative+'.png',a=assets.find(r=>r.uri===uri);assert(a,'Reviewed exact native '+uri);set(id,uri,[a.width,a.height],concept);}
function hd(id,name,concept){set(id,'s2r://panorama/images/custom_game/reward_art_v5/'+name+'.vtex',[313,313],concept);}
function shop(id,name,concept){set(id,'s2r://panorama/images/custom_game/shop_icons_hd_v1/'+name+'.vtex',[1254,1254],concept);}
native('commerce_p004','econ/crafting/crafting_recipe_scroll_evergreen','清暑符：绿叶法符');
native('commerce_p005','econ/crafting/crafting_recipe_scroll_common','双倍通关卡：卷轴卡券');
native('commerce_p011','econ/tools/seasonal_ti10_soccerball','炫彩足球：原生足球');
hd('commerce_p014','lottery_protection_crystal','硬质涂层：金属包边防护晶盾');
native('commerce_p015','econ/items/beastmaster/chimeras_rage_weapon/chimeras_rage_weapon','金斧头：金橙兽形斧刃');
native('commerce_p017','econ/items/axe/axe_executioner','铜斧头：棕铜斧刃木柄');
native('commerce_p019','econ/items/alchemist/alchemeyerflask/alchemeyerflask','淬火剂：蓝色药剂烧瓶');
shop('commerce_p021','equipment_iron_armor_01','优质装备：金边银色胸甲');
hd('commerce_p023','lottery_kings_treasure','古董收藏家：古典珠宝箱');
shop('commerce_p024','item_knowledge_book','建筑手册：青绿金边手册');
hd('commerce_p025','daily_wealth_talisman','文玩收藏家：玉石金钱挂坠');
native('commerce_p026','spellicons/tinker_keen_teleport','侏儒传送器：原生科技传送阵');
hd('commerce_p027','lottery_crystalline_armor','精英装备：晶体重铠');
native('commerce_p030','econ/items/axe/greek_weapon','银斧头：亮银宽弧斧刃');
hd('commerce_p031','lottery_tower_retrofit','强化箭塔：木制攻城弩塔');
hd('commerce_p032','lottery_universal_tool','快速建造：铁木施工工具');
native('commerce_p033','econ/items/beastmaster/korosh_peaks_weapon/korosh_peaks_weapon','伐木斧：林地木柄双刃斧');
assert.equal(changes.length,17);assert.equal(sha(fs.readFileSync(file)),sha(beforeBytes),'Concurrent registry edit');
fs.writeFileSync(file,JSON.stringify(table,null,2)+'\n');fs.writeFileSync(path.join(out,'market_resource_changes.json'),JSON.stringify({scope:'Only artwork; every product identity/alias/quantity/eligibility preserved',previousHash:sha(beforeBytes),newHash:sha(fs.readFileSync(file)),changes,rejectedCandidates:'Native econ/artifacts wrappers contain embedded enlarged low-resolution item sprites; none selected.'},null,2)+'\n');
console.log(JSON.stringify({changed:changes.length,extraTextureCompiles:0,hash:sha(fs.readFileSync(file))}));
