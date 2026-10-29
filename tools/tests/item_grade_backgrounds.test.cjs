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
 const {cfg,context,resources:r}=runtime();cfg.SurvivalItemResources={sourceHash:r.sourceHash,apiVersion:5};
 vm.runInContext(source,context);const upgraded=cfg.SurvivalItemResources;
 assert.equal(upgraded.apiVersion,6);assert.equal(typeof upgraded.Grade,'function');
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
 assert.equal(p.style.border,'0px','Other parchment row items share the border exception');
 const popup=icon();r.FillIcon(popup,{id:'building_01',quality:'N'});
 assert.equal(popup.style.border,'1px solid #83aa65','Artifact tooltip/other consumers retain the shared background');
});

test('All requested archive categories suppress clipped square frames without changing their resource identity',()=>{
 const {resources:r}=runtime(),counts={};
 const requested=new Set(['fishing','boss','work','map_level','clear']);
 for(const row of r.Rows()){
  const category=requested.has(row.category_id)?row.category_id:/^shadow_\d+$/.test(row.id)?'shadow':/^starjoy_lv\d+$/.test(row.id)?'starjoy_points':null;
  if(!category)continue;counts[category]=(counts[category]||0)+1;
  const p=icon();p.BHasClass=cls=>cls==='ArchiveV10Icon';const before=JSON.stringify(row);
  for(const quality of ['N','SSR','']){
   r.FillIcon(p,{id:row.id,quality});
   assert.equal(p.style.border,'0px',row.id);assert.equal(p.style.backgroundImage,'none');
   assert.equal(p.style.backgroundColor,'transparent');
   if(row.kind==='image')assert.equal(p.scaling,'stretch-to-fit-preserve-aspect');
  }
  assert.equal(JSON.stringify(row),before,'Display cannot alter icons, layers or levels');
  const popup=icon();r.FillIcon(popup,{id:row.id,quality:'N'});assert.equal(popup.style.border,'1px solid #83aa65');
 }
 assert.deepEqual(counts,{boss:34,clear:44,map_level:34,shadow:23,fishing:26,starjoy_points:24,work:34});
});

test('Nested fallback art and reused panels follow the current archive context',()=>{
 const {resources:r}=runtime(),row=icon(),child=icon();row.BHasClass=cls=>cls==='ArchiveV10Icon';
 child.GetParent=()=>row;r.FillIcon(child,{id:'fragment_01',quality:'N'});
 assert.equal(child.style.border,'0px');assert.equal(child.scaling,'stretch-to-fit-preserve-aspect');
 child.GetParent=()=>null;r.FillIcon(child,{id:'fragment_01',quality:'N'});
 assert.equal(child.style.border,'1px solid #83aa65');assert.equal(child.scaling,'stretch-to-cover-preserve-aspect');
 row.BHasClass=()=>false;r.FillIcon(row,{id:'clear_n1_1',quality:'N'});
 assert.equal(row.style.border,'1px solid #83aa65','Leaving the archive restores shared grade decoration');
});

test('All 24 Starjoy badges retain their base, pips and LV label with only the outer square frame removed',()=>{
 const {cfg,context,resources:r}=runtime();
 context.$={CreatePanel(type,parent){
  const classes=new Set(),node={type,style:{},children:[],IsValid:()=>true,
   AddClass:cls=>classes.add(cls),BHasClass:cls=>classes.has(cls),GetParent:()=>parent};
  if(type==='Image'){node.SetImage=value=>node.uri=value;node.SetScaling=value=>node.scaling=value;}
  if(parent)parent.children.push(node);return node;
 }};
 vm.runInContext(fs.readFileSync(path.join(root,'panorama/src/scripts/custom_game/reward_presentation.js'),'utf8'),context);
 for(let i=1;i<=24;i++){
  const id='starjoy_lv'+String(i).padStart(2,'0'),resource=r.Lookup(id);
  const badge=cfg.SurvivalRewardPresentation.CreateRegisteredIcon(null,{id},'ArchiveV10Icon');
  assert.equal(badge.style.border,'0px');assert.equal(badge.style.backgroundImage,'none');
  const stage=badge.children[0];assert.equal(stage.children.length,3);
  const [base,pips,label]=stage.children;
  assert.equal(base.uri,resource.uri);assert.equal(pips.uri,resource.overlay_uri);
  assert.equal(base.scaling,'stretch-to-fit-preserve-aspect');assert.equal(pips.scaling,'stretch-to-fit-preserve-aspect');
  assert.equal(label.text,'LV'+i);assert.equal(label.style.border,'1px solid '+resource.badge_color);
  r.FillIcon(badge,{id,quality:'N'});assert.equal(badge.style.border,'0px');assert.equal(stage.children.length,3);
 }
});
