'use strict';
// Independent enumeration of every resource row and public factory behavior.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const repo=path.resolve(__dirname,'../..');process.chdir(repo);const out='design_refs/item_fill_20261017';fs.mkdirSync(out,{recursive:true});
const hash=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex'),table=JSON.parse(fs.readFileSync('data/ui/item_resources.json','utf8').replace(/^\uFEFF/,''));
class Panel{constructor(type,parent){this.paneltype=type;this.children=[];this.style={};this.classes=new Set();this.scaleCalls=0;if(parent)parent.children.push(this);}IsValid(){return true;}AddClass(c){this.classes.add(c);}BHasClass(c){return this.classes.has(c);}SetScaling(v){this.scaling=v;this.scaleCalls++;}SetImage(v){this.image=v;}Children(){return this.children;}}
const cfg={SurvivalItemResources:{sourceHash:hash('data/ui/item_resources.json'),apiVersion:1}},context=vm.createContext({GameUI:{CustomUIConfig:()=>cfg},$:{CreatePanel:(type,parent)=>new Panel(type,parent)}});
const sources=['common/item_resources.js','common/vip_badges.js','reward_presentation.js','native_ui_icons.js','item_art_remaining_5d5c1152eb.js','archive_v10_icons.js'];
const loaded=[];for(const relative of sources){const file='panorama/src/scripts/custom_game/'+relative;vm.runInContext(fs.readFileSync(file,'utf8'),context,{filename:file});loaded.push({path:file,sha256:hash(file)});}
const registry=cfg.SurvivalItemResources,factory=cfg.SurvivalRewardPresentation;assert.equal(registry.apiVersion,2,'Old registry instance upgrades even when table hash is unchanged');
let images=0,special=0,aliases=0;const sample=[];
for(const row of table.items){
 assert.equal(registry.Lookup(row.id).uri,row.uri,'Canonical art unchanged: '+row.id);
 for(const alias of row.aliases||[]){assert.equal(registry.Lookup(alias).id,row.id);aliases++;}
 const parent=new Panel('Panel'),icon=factory.CreateRegisteredIcon(parent,{id:row.id},'IndependentFill',{width:80,height:80});
 if(row.kind==='layered_title'){assert.equal(icon,null,'Layered titles retain their own renderer');special++;continue;}
 assert(icon,'Registered factory creates '+row.id);
 if(row.kind==='image'||row.kind==='hero'){
  images++;assert.equal(icon.scaling,'stretch-to-cover-preserve-aspect','Ordinary icon covers '+row.id);assert.equal(icon.style.padding,'0px');assert.equal(icon.style.margin,'0px');assert.equal(icon.style.overflow,'clip');
  if(row.uri)assert.equal(icon.image,row.uri);
  const calls=icon.scaleCalls;factory.FillIcon(icon,{id:row.id});registry.FillIcon(icon,row.id);assert.equal(icon.scaleCalls,calls,'Repeated refresh does not mutate scaling '+row.id);
  const legacy=cfg.SurvivalItemArt.Create(parent,{id:row.id},'Legacy');assert.equal(legacy.scaling,'stretch-to-cover-preserve-aspect');
 }else{
  special++;assert.equal(icon.scaling,undefined,'Composed icon host must not be stretched '+row.id);
  if(row.kind==='vip'){assert.equal(icon.__survivalVIPBadge.number.text,String(row.vip_level));assert.equal(icon.__survivalVIPBadge.image.scaling,'stretch-to-fit-preserve-aspect');assert(icon.__survivalVIPBadge.number.style.position,'VIP number retains independent placement');}
  if(row.kind==='endless_emblem'){assert.equal(icon.Children().length,2);assert(icon.Children().every(p=>p.style.borderRadius==='50%'),'Both endless rings retain geometry');}
 }
 if(['commerce_p027','lottery_muramasa','vip_privilege_11'].includes(row.id))sample.push({id:row.id,kind:row.kind,uri:row.uri,scaling:icon.scaling||null,vipNumber:icon.__survivalVIPBadge?.number.text||null});
}
for(const row of[{id:'unknown_image',icon_type:'image',icon:'file://{images}/items/assault.png'},{id:'unknown_item',icon_type:'item',icon:'item_blink'},{id:'unknown_ability',icon_type:'ability',icon:'test_ability'}]){const icon=factory.CreateIcon(new Panel('Panel'),row,'Fallback');assert.equal(icon.scaling,'stretch-to-cover-preserve-aspect','Unregistered original fallback also fills');}
const version2=registry;vm.runInContext(fs.readFileSync('panorama/src/scripts/custom_game/common/item_resources.js','utf8'),context);assert.equal(cfg.SurvivalItemResources,version2,'Matching API2 reload reuses registry');
assert.equal(registry.Resolve('video_p042'),registry.Resolve('lottery_muramasa'));assert.equal(registry.Resolve('video_p042'),registry.Resolve('commerce_p042'));assert.notEqual(registry.Resolve('video_p042'),registry.Resolve('video_p151'),'Separate katana identity remains separate');
const dll=path.resolve(repo,'../../dota/bin/win64/client.dll'),bytes=fs.readFileSync(dll),enumOffset=bytes.indexOf(Buffer.from('stretch-to-cover-preserve-aspect\0'));assert(enumOffset>=0,'Installed native client includes exact aspect-cover enum');
const report={status:'PASS',notGameCapture:true,noGameOrAccountWrites:true,table:{path:'data/ui/item_resources.json',sha256:hash('data/ui/item_resources.json'),rows:table.items.length,ordinaryCover:images,composedPreserved:special,aliases},nativeEnum:{dll,enum:'stretch-to-cover-preserve-aspect',byteOffset:enumOffset},checks:['API1 same-hash migration','Every canonical image and alias unchanged','Every ordinary factory icon uses native aspect-cover','Repeated refresh scaling cached','VIP independent numbers and artwork proportion retained','Layered titles and endless rings preserved','Fallback item/ability/image cover','Muramasa shares one icon across archive/commerce/lottery','Distinct spirit katana artwork retained'],samples:sample,sources:loaded};
fs.writeFileSync(out+'/validation.json',JSON.stringify(report,null,2)+'\n');console.log('ITEM_FILL_INDEPENDENT_PASS '+images+' ordinary cover + '+special+' composed preserved / '+table.items.length+' rows');
