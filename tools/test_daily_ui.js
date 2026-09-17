// Runs production components and controller against a minimal native-panel mock.
const fs=require('fs'),vm=require('vm'),assert=require('assert');
const panels={},events={},requests=[],jobs=new Map();let serial=0;
class Panel{
 constructor(type,parent,id){this.children=[];this.classes=new Set();this.events={};this.style={};this.parent=parent;this.id=id;this.enabled=true;if(parent)parent.children.push(this);if(id)panels[id]=this;}
 AddClass(c){this.classes.add(c)}RemoveClass(c){this.classes.delete(c)}BHasClass(c){return this.classes.has(c)}ToggleClass(c){this.SetHasClass(c,!this.BHasClass(c))}SetHasClass(c,v){v?this.AddClass(c):this.RemoveClass(c)}SetPanelEvent(n,f){this.events[n]=f}RemoveAndDeleteChildren(){this.children=[]}SetImage(s){this.image=s}SetScaling(s){this.scaling=s}IsValid(){return true}GetParent(){return this.parent}GetChildCount(){return this.children.length}GetChild(i){return this.children[i]}FindChildTraverse(id){return panels[id]||null}get actuallayoutwidth(){return 1672}get actuallayoutheight(){return 941}get actualuiscale_x(){return 1}get actualuiscale_y(){return 1}
}
const root=new Panel('Panel',null,'Root');for(const m of fs.readFileSync('panorama/src/layout/custom_game/archive.xml','utf8').matchAll(/id="([^"]+)"/g))new Panel('Panel',root,m[1]);
const $=id=>panels[id.slice(1)];$.CreatePanel=(t,p,id)=>new Panel(t,p,id);$.GetContextPanel=()=>root;$.Schedule=(d,f)=>{jobs.set(++serial,f);return serial};$.CancelScheduled=id=>jobs.delete(id);$.DispatchEvent=()=>{};
const config={},context=vm.createContext({$,GameUI:{CustomUIConfig:()=>config},GameEvents:{Subscribe:(n,f)=>{events[n]=f;return n},Unsubscribe:n=>delete events[n],SendCustomGameEventToServer:(n,p)=>requests.push({n,p})}});
for(const file of ['common/ui_registry','daily_resources','ui_layers','common/ui_components','daily_rewards'])vm.runInContext(fs.readFileSync('panorama/src/scripts/custom_game/'+file+'.js','utf8'),context);
const fixture=JSON.parse(fs.readFileSync('art/ui/development/daily_rewards_import/preview/fixture.js','utf8').match(/^const fixture=(.*?);config/)[1]);let sequence=0;
function send(overrides={}){events.survival_daily_snapshot({...fixture,sequence:++sequence,...overrides})}
config.SurvivalDaily.Open(false);send();assert.equal(panels.DailyCards.children.length,7);assert(panels.DailyClaim.enabled);
panels.DailyClaim.events.onactivate();panels.DailyClaim.events.onactivate();assert.equal(requests.filter(r=>r.n==='survival_daily_claim').length,1);assert(!panels.DailyClaim.enabled);
send({claim_result:{target_day:fixture.today,ok:false,error:'保存失败'}});assert(panels.DailyClaim.enabled);assert.equal(panels.DailyClaimText.text,'重试领取');
panels.DailyClaim.events.onactivate();send({count:7,claimed:1,ordinary_status:'claimed'});assert(!panels.DailyClaim.enabled);
events.survival_daily_snapshot({...fixture,sequence:1});assert(!panels.DailyClaim.enabled);
send({today:25001,period_id:'1',ordinary_status:'claimed',premium:{status:'claimable',name:'测试专属'}});assert(panels.DailyClaim.enabled);assert.equal(panels.DailyClaimText.text,'领取通行证奖励');
send({today:25001,ordinary_status:'claimed',premium:{status:'claimed'}});assert(!panels.DailyClaim.enabled);
send({today:25002,has_pass:0,premium:{status:'requires_pass'}});assert(panels.DailyClaim.enabled);assert(!panels.DailyMakeup.enabled);
config.SurvivalDaily.Open(true);assert(panels.DailyClaimPage.BHasClass('ArchiveHidden'));assert(!panels.PassPurchase.enabled);send({today:25002,purchase_enabled:1});panels.PassPurchase.events.onactivate();assert.equal(requests.at(-1).n,'survival_pass_purchase');assert.equal(Object.keys(requests.at(-1).p).length,0);
config.SurvivalDaily.Close();assert.equal(config.SurvivalUILayers.Top(),null);config.SurvivalDaily.Open(false);panels.DailyScrim.events.onactivate();assert.equal(config.SurvivalUILayers.Top(),null);config.SurvivalDaily.Open(false);panels.DailyClose.events.onactivate();assert.equal(config.SurvivalUILayers.Top(),null);
config.SurvivalDaily.Dispose();assert(!events.survival_daily_snapshot);
console.log('DAILY_UI_PASS: production shared components, seven cards, independent slots, busy/failed/retry, sequence, day reset, purchase, close and cleanup');
