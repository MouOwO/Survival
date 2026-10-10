const fs=require('fs'),vm=require('vm'),assert=require('assert');
const panels={},requests=[],scheduled=[];
class Panel {
 constructor(type,parent,id=''){this.paneltype=type;this.id=id;this.style={};this.classes=new Set();this.children=[];this.events={};this.visible=true;this.hittest=true;if(parent)parent.children.push(this);}
 AddClass(c){this.classes.add(c)} RemoveClass(c){this.classes.delete(c)} SetHasClass(c,b){b?this.AddClass(c):this.RemoveClass(c)} BHasClass(c){return this.classes.has(c)}
 RemoveAndDeleteChildren(){this.children=[]} SetPanelEvent(k,v){this.events[k]=v} SetImage(){} Children(){return this.children}
 click(){assert.equal(this.paneltype,'Button','actionable archive cards must use an engine Button');assert(this.hittest);this.events.onactivate();}
}
function panel(id){return panels[id]||(panels[id]=new Panel('Panel',null,id));}
const cfg={ArchiveHandoffAssets:{},SurvivalArchiveColors:{number:'#fff'}};
const env={cfg,current:'work',opened:true,rowCards:{},filterMode:'all',lastData:null,lastPaletteKey:'',renderVoid:()=>false,array:x=>x||[],panel,GameUI:{CustomUIConfig:()=>cfg},
 A:{Observe(){},Unlocked:r=>!!r.completed,ApplyPalette(){}},active:()=>true,valid:p=>!!p,later:(delay,fn)=>scheduled.push(fn),hideTooltip(){},tabs(){},showDrawBar(){},isDrawPage:()=>false,icon(){},cardFrame(){},tooltip(){},request(){},
 label(parent,text,cls){const p=new Panel('Label',parent);p.text=text;p.AddClass(cls);return p},
 $:{CreatePanel:(t,p,id)=>new Panel(t,p,id),Schedule:(delay,fn)=>scheduled.push(fn)},GameEvents:{SendCustomGameEventToServer:(name,payload)=>requests.push({name,payload})}};
const source=fs.readFileSync('panorama/src/scripts/custom_game/archive_180de7e38b_titles_compact_v6.js','utf8');
vm.runInNewContext(source.slice(source.indexOf('    function render(data)'),source.indexOf('    subscribe("survival_archive_snapshot"')),env);
const row={id:'work_01',name:'Boss',count:0,level:0,cost:600,can_upgrade:1,completed:0};
const data={category_id:'work',categories:[],pending:0,online:{coins:2294},rows:[row,{...row,id:'work_02',cost:3000,can_upgrade:0}]};
function card(index=0){return env.rowCards['work:'+index].panel}
function cost(){return card().children.find(p=>p.BHasClass('ArchiveWorkCost')).text}
env.render(data);card().click();card().click();assert.equal(requests.length,1);assert.equal(requests[0].name,'survival_archive_work_upgrade');assert.equal(requests[0].payload.expected_level,0);assert.equal(cost(),'正在解锁…');
// Rejected/lost request returns unchanged authoritative data. Cached card must recover.
env.render(data);assert(card().BHasClass('ArchiveWorkAvailable'));card().click();assert.equal(requests.length,2);
env.render({...data,pending:1,upgrade_pending:1});card().click();assert.equal(requests.length,2);assert(panels.ArchiveStatus.text.includes('保存'));
env.render(data);card(1).click();assert.equal(requests.length,2);assert.equal(panels.ArchiveStatus.text,'软妹币不足');
// The live regression: an unrelated boss reward remains pending, coins suffice.
env.render({...data,pending:1,upgrade_pending:0});card().click();assert.equal(requests.length,3,'background rewards must not block welfare');
// The successful server response alone updates ownership and currency.
env.render({...data,online:{coins:1694},rows:[{...row,count:1,level:1,completed:1,can_upgrade:0}]});
assert.equal(panels.ArchiveContext.text,'软妹币 1694');assert.equal(cost(),'已激活');assert.equal(panels.ArchiveFilterAllLabel.text,'全部（1/1）');card().click();assert.equal(requests.length,3);
// Shared artifact cards retain their own currency and event route.
env.current='building';env.render({category_id:'building',categories:[],pending:0,rows:[{...row,id:'building_01'}]});env.rowCards['building:0'].panel.click();assert.equal(requests.at(-1).name,'survival_archive_building_upgrade');
console.log('WORK_UNLOCK_CLICK_PASS: real Button, duplicate suppression, unchanged-response retry, pending and insufficient feedback, authoritative balance/unlock refresh, artifact route');
