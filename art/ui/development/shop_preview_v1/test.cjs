const fs=require('fs'),vm=require('vm'),assert=require('assert');
class Panel{constructor(type,parent,id){this.type=type;this.id=id;this.children=[];this.style={};this.classes=new Set;this.events={};if(parent)parent.children.push(this);}AddClass(c){this.classes.add(c);}SetHasClass(c,b){b?this.classes.add(c):this.classes.delete(c);}Children(){return this.children;}RemoveAndDeleteChildren(){this.children=[];}SetPanelEvent(e,f){this.events[e]=f;}SetImage(){}SetScaling(){}IsValid(){return true;}DeleteAsync(){}FindChildTraverse(id){if(this.id===id)return this;for(const c of this.children){const v=c.FindChildTraverse(id);if(v)return v;}return null;}}
const root=new Panel(),timers=new Map;let serial=0;const cfg={};
const U=cfg.SurvivalUI={ActionButton(parent,props){const b=new Panel('Button',parent);b.caption=props.label;b.events.onactivate=props.action;return b;},State:{Set(b,v){b.enabled=v.enabled;}},ModalShell:{Adopt(props){return{Open(){props.panel.open=true;},Close(){props.panel.open=false;},Dispose(){}};}},ProductCard(parent,props){const b=new Panel('Panel',parent);b.productName=props.name;return b;}};
cfg.RemainingHandoff={Action(){},Window(){},SizeWindow(){},Box(){},Tab(){},Image(parent){return new Panel('Image',parent);}};
const $={GetContextPanel:()=>root,CreatePanel:(t,p,id)=>new Panel(t,p,id),Schedule:(s,f)=>{timers.set(++serial,f);return serial;},CancelScheduled:id=>timers.delete(id)};
const context=vm.createContext({GameUI:{CustomUIConfig:()=>cfg},$,console});
vm.runInContext(fs.readFileSync(__dirname+'/data.js','utf8').replace('/*PREVIEW_CATALOG*/',fs.readFileSync(__dirname+'/catalog.json','utf8')),context);
vm.runInContext(fs.readFileSync(__dirname+'/view.js','utf8'),context);
function all(n=root){return[n,...n.children.flatMap(all)];}function click(name){const b=all().find(x=>x.caption===name);assert(b,name);b.events.onactivate();}function flush(){const [id,fn]=timers.entries().next().value;timers.delete(id);fn();}
const view=cfg.SurvivalCommerceView;view.Open();assert.equal(all().filter(x=>x.classes.has('RCProduct')).length,8);
click('立即购买');click('+');click('+');assert.equal(view.Inspect().quantity,3);click('确认模拟订单');click('生成模拟订单…');assert.equal(timers.size,1);flush();assert.equal(view.Inspect().order.quantity,3);assert.equal(view.Inspect().order.amount,360);
for(const state of ['loading','qr_failed','expired','complete','failed','waiting']){view.PreviewState(state);assert.equal(view.Inspect().order.state,state);assert.equal(timers.size,state==='waiting'?1:0);}
click('返回商城');assert.equal(timers.size,0);assert.equal(view.Inspect().order,null);click('立即购买');assert.equal(view.Inspect().quantity,1);click('确认模拟订单');view.Close();assert.equal(timers.size,0);assert.equal(view.Inspect().product,null);
view.Open();view.Dispose();assert.equal(timers.size,0);
for(const file of ['data.js','view.js'])assert(!/SendCustomGameEventToServer|CreateHTTPRequest|https?:\/\//.test(fs.readFileSync(__dirname+'/'+file,'utf8')));
console.log('SHOP_PREVIEW_PASS: local catalog, quantity/amount, duplicate order guard, all six states, close/reopen cancellation, no network/server calls');
