'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),test=require('node:test');
const root=path.resolve(__dirname,'../..'),source=fs.readFileSync(path.join(root,'panorama/src/scripts/custom_game/common/item_resources.js'),'utf8');
function runtime(){const cfg={},context=vm.createContext({GameUI:{CustomUIConfig:()=>cfg}});vm.runInContext(source,context);return {cfg,context,resources:cfg.SurvivalItemResources};}
function icon(){return {style:{},images:['foreground unchanged'],IsValid(){return true;},SetScaling(value){this.scaling=value;}};}
test('Only the five explicit grades acquire their requested colors; absent or unrelated metadata stays gray',()=>{
 const {resources:r}=runtime(),used=new Set();
 for(const grade of ['N','R','SR','SSR','UR']){
  const p=icon();r.FillIcon(p,{id:'unregistered',quality:' '+grade.toLowerCase()+' '});
  assert.equal(p.__survivalItemGrade,grade);assert.match(p.style.backgroundColor,/gradient\(linear/);used.add(p.style.backgroundColor);
  assert.match(p.style.backgroundImage,/econ\/tools\/ti10_seasonal_item_background\.png/);assert.equal(p.style.backgroundImgOpacity,'0.28');
  assert.deepEqual(p.images,['foreground unchanged'],'Background color never washes or replaces foreground pixels');
 }
 assert.equal(used.size,5);
 for(const item of [{},'missing',{quality:'white'},{quality:'unknown'},{quality:'Legendary'},{name:'SSR sword',price:100,rarity:2}]){
  const p=icon();r.FillIcon(p,item);assert.equal(r.Grade(item),'');assert.equal(p.__survivalItemGrade,'');assert.equal(p.style.backgroundImgOpacity,'1.0');
 }
});
test('Every registered grade and alias resolves through the same authority, without inventing a default N',()=>{
 const {resources:r}=runtime();let classified=0,gray=0;
 for(const row of r.Rows()){
  const expected=/^(N|R|SR|SSR|UR)$/i.test(row.quality||'')?row.quality.toUpperCase():'';
  const p=icon();r.FillIcon(p,row.id);assert.equal(p.__survivalItemGrade,expected,row.id);
  row.aliases.forEach(alias=>assert.equal(r.Grade(alias),expected,alias));
  expected?classified++:gray++;
 }
 assert(classified>=296);assert(gray>1000);
 const known=r.Rows().find(row=>String(row.quality).toUpperCase()==='N');
 assert.equal(r.Grade({id:known.id,rarity:'UR'}),'UR','Explicit live rarity overrides static N');
});
test('Single-item rewards keep their real grade while bundles and multiple item rewards have no inferred grade',()=>{
 const {resources:r}=runtime(),row=r.Rows().find(row=>String(row.quality).toUpperCase()==='SSR');
 const reward={kind:'item',id:row.id},product={id:'unregistered-product',reward_lines:[reward,{kind:'currency',id:'u_coin'}]};
 const original=JSON.stringify(product);
 assert.equal(r.Grade(product),'SSR');assert.equal(JSON.stringify(product),original);
 assert.equal(r.Grade({...product,product_type:'bundle'}),'');
 assert.equal(r.Grade({...product,reward_lines:[reward,reward]}),'');
 assert.equal(r.Grade({id:'unknown',grants:{lines:[reward]}}),'SSR');
});
test('Reused panels reset old grades and restore backgrounds cleared by consumer layout',()=>{
 const {resources:r}=runtime(),p=icon();
 for(const grade of ['UR','','N','SSR','R','']){
  r.FillIcon(p,{quality:grade});assert.equal(p.__survivalItemGrade,grade);
  const expected=p.style.backgroundColor;p.style.backgroundColor='transparent';p.style.backgroundImage='none';
  r.FillIcon(p,{quality:grade});assert.equal(p.style.backgroundColor,expected);assert.notEqual(p.style.backgroundImage,'none');
 }
 const invalid=icon();invalid.IsValid=()=>false;r.FillIcon(invalid,{quality:'UR'});assert.deepEqual(invalid.style,{});
});
test('The runtime upgrade replaces a cached old API even when resource data hash is unchanged',()=>{
 const {cfg,context,resources:r}=runtime();cfg.SurvivalItemResources={sourceHash:r.sourceHash,apiVersion:4};
 vm.runInContext(source,context);const upgraded=cfg.SurvivalItemResources;
 assert.equal(upgraded.apiVersion,5);assert.equal(typeof upgraded.Grade,'function');
 vm.runInContext(source,context);assert.equal(cfg.SurvivalItemResources,upgraded,'Repeated current includes share one registry');
});

test('All nine parchment artifacts retain native aspect and no square frame after repeated fills or panel reuse',()=>{
 const {resources:r}=runtime(),p=icon();p.BHasClass=cls=>cls==='ArchiveV10Icon';
 for(let i=1;i<=9;i++){
  const id='building_'+String(i).padStart(2,'0'),row=r.Lookup(id);
  assert.equal(row.fit,'contain');assert(row.uri.startsWith('file://{images}/items/'));
  for(let paint=0;paint<3;paint++){
   p.style.border='1px solid #83aa65';p.style.backgroundImage='old square bevel';
   r.FillIcon(p,{id,quality:'N'});
   assert.equal(p.style.border,'0px',id);assert.equal(p.style.backgroundImage,'none');
   assert.equal(p.style.backgroundColor,'transparent');assert.equal(p.scaling,'stretch-to-fit-preserve-aspect');
  }
 }
 r.FillIcon(p,{id:'lottery_gale_bow',quality:'N'});
 assert.equal(p.style.border,'1px solid #83aa65','Other archive items retain their grade frame');
 const popup=icon();r.FillIcon(popup,{id:'building_01',quality:'N'});
 assert.equal(popup.style.border,'1px solid #83aa65','Artifact tooltip/other consumers retain the shared background');
});
