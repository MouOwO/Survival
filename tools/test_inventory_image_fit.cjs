const fs=require('fs'),vm=require('vm'),assert=require('assert');
class Panel{constructor(){this.style={};this.children={};this.visible=true;}FindChildTraverse(id){return this.children[id]||null;}SetScaling(v){this.scaling=v;}SetImage(v){this.image=v;}}
const inv=new Panel(),items=['item_survival_growth_sword_01','item_survival_attack_gloves_shell','item_survival_iron_armor_shell'];
const slots=Array.from({length:9},(_,i)=>{const p=new Panel();p.children.ItemImage=new Panel();p.children.ItemCharges=new Panel();p.children.ItemAltCharges=new Panel();inv.children['inventory_slot_'+i]=p;return p;});
const cfg={},identity={};const env={cfg,GameUI:{CustomUIConfig:()=>cfg},valid:p=>!!p,native:()=>inv,selectedUnit:()=>7,
 child:(p,id,s)=>{const c=p.FindChildTraverse(id);if(c)Object.assign(c.style,s);},
 Entities:{GetItemInSlot:(_,i)=>items[i]?i:-1},Abilities:{GetAbilityName:i=>items[i]},CustomNetTables:{GetTableValue:(_,id)=>identity[id]},style:(p,s)=>Object.assign(p.style,s),
 $:{CreatePanel:(type,parent,id)=>{assert(['Image','Label'].includes(type));assert(!parent.children[id]);return parent.children[id]=new Panel();}}};
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/item_art_remaining_5d5c1152eb.js','utf8'),env);
const source=fs.readFileSync('panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js','utf8');
vm.runInNewContext(source.slice(source.indexOf('    function refreshInventoryPresentation()'),source.indexOf('    function nativeLayout(')),env);
env.refreshInventoryPresentation();env.refreshInventoryPresentation();
const fitted=i=>slots[i].children.ItemImage.children.SurvivalInventoryFittedIcon;
assert(fitted(0).image.endsWith('swords_00.png'));assert(fitted(1).image.endsWith('shop_01.png'));
for(let i=0;i<3;i++){assert.equal(fitted(i).scaling,'stretch-to-fit-preserve-aspect');assert.equal(fitted(i).style.width,'100%');assert.equal(fitted(i).style.height,'100%');assert.equal(fitted(i).hittest,false);assert.equal(fitted(i).hittestchildren,false);}
for(const p of slots)for(const id of ['ItemCharges','ItemAltCharges'])assert.equal(p.children[id].style.fontSize,'26px');
assert.equal(slots[0].children.ItemCharges.style.opacity,'1');
assert.equal(slots[1].children.ItemCharges.style.opacity,'0');
assert.equal(slots[2].children.ItemCharges.style.opacity,'0');
identity[2]={content_id:'equipment_iron_armor_max'};env.refreshInventoryPresentation();
const armorMax=slots[2].children.SurvivalInventoryArmorMax;
assert(armorMax.visible);assert.equal(armorMax.text,'MAX');assert.equal(armorMax.style.fontSize,'26px');assert.equal(armorMax.hittest,false);
env.refreshInventoryPresentation();assert.strictEqual(slots[2].children.SurvivalInventoryArmorMax,armorMax);
identity[2]={content_id:'equipment_iron_armor_04'};env.refreshInventoryPresentation();assert.equal(armorMax.visible,false);
identity[2]={content_id:'equipment_iron_armor_max',removed:1};env.refreshInventoryPresentation();assert.equal(armorMax.visible,false);
identity[2]={content_id:'equipment_iron_armor_max'};items[2]=null;env.refreshInventoryPresentation();assert.equal(armorMax.visible,false);
items[2]='item_survival_iron_armor_shell';delete identity[2];
for(const family of ['attack_gloves','burning_blade','iron_armor']){
 items[2]='item_survival_'+family+'_shell';
 identity[2]={content_id:'equipment_'+family+'_max'};env.refreshInventoryPresentation();
 assert(armorMax.visible);assert.equal(armorMax.text,'MAX');
 for(const level of ['01','02','03','04']){
  identity[2]={content_id:'equipment_'+family+'_'+level};env.refreshInventoryPresentation();assert.equal(armorMax.visible,false);
 }
 delete identity[2];items[2]='item_survival_'+family+'_max';env.refreshInventoryPresentation();assert(armorMax.visible);
 items[2]=null;env.refreshInventoryPresentation();assert.equal(armorMax.visible,false);
}
items[2]='item_survival_iron_armor_shell';
items[0]='item_survival_growth_sword_max';env.refreshInventoryPresentation();assert(fitted(0).image.endsWith('swords_04.png'));
items[6]=items[0];items[0]=null;env.refreshInventoryPresentation();assert(!fitted(0).visible);assert(fitted(6).visible&&fitted(6).image.endsWith('swords_04.png'));
items[1]='item_blink';env.refreshInventoryPresentation();assert(!fitted(1).visible,'native fallback must not retain the previous custom icon');
assert.equal(slots[1].children.ItemCharges.style.opacity,'1','moving a different item into the slot restores its counter');
items[1]='item_survival_burning_blade_shell';env.refreshInventoryPresentation();assert.equal(slots[1].children.ItemAltCharges.style.opacity,'0');
const tooltipCode=fs.readFileSync('panorama/src/scripts/custom_game/inventory_tooltip.js','utf8');
vm.runInNewContext(tooltipCode.slice(tooltipCode.indexOf('    function updateItemIcon('),tooltipCode.indexOf('    function render(')),env);
const tipIcon=new Panel();env.updateItemIcon(tipIcon,'equipment_iron_armor_04','item_survival_iron_armor_shell');
const tipImage=tipIcon.children.InventoryTooltipFittedIcon;assert(tipImage.image.endsWith('shop_03.png'));assert.equal(tipImage.scaling,'stretch-to-fit-preserve-aspect');assert.equal(tipImage.style.width,'100%');assert.equal(tipImage.style.height,'100%');
env.updateItemIcon(tipIcon,'weapon_growth_sword_max','item_survival_growth_sword_max');assert.strictEqual(tipIcon.children.InventoryTooltipFittedIcon,tipImage);assert(tipImage.image.endsWith('swords_04.png'));
env.updateItemIcon(tipIcon,'item_blink','item_blink');assert.equal(tipImage.visible,false);
for(const n of [1,2,3,4])assert.equal(env.equipmentLevelText('equipment_iron_armor_0'+n),'Lv.'+n);
assert.equal(env.equipmentLevelText('equipment_iron_armor_max'),'MAX');
console.log('INVENTORY_IMAGE_FIT_PASS: fitted Image layer, all counters 26px, upgrade, backpack move, empty/native fallback, repeated refresh');
