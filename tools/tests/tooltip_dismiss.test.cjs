'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync('panorama/src/scripts/custom_game/common/tooltip_dismiss.js','utf8');
let cursor=[0,0],clock=0,serial=0;const cfg={},jobs=new Map();
const context={GameUI:{CustomUIConfig:()=>cfg,GetCursorPosition:()=>cursor},$:{Schedule(delay,fn){const id=++serial;jobs.set(id,{time:clock+delay,fn});return id;},CancelScheduled(id){jobs.delete(id);}}};
vm.createContext(context);vm.runInContext(source,context);
function step(){clock+=.031;for(const [id,job] of [...jobs])if(job.time<=clock){jobs.delete(id);job.fn();}}
function panel(id,x,y,w,h){return {id,visible:true,hittest:false,hittestchildren:false,actuallayoutwidth:w,actuallayoutheight:h,events:{},IsValid(){return !this.deleted;},GetPositionWithinWindow(){return {x,y};},SetPanelEvent(name,fn){this.events[name]=fn;}};}
function tooltip(id,x,y,w=100,h=100){const p=panel(id,x,y,w,h);p.visible=false;let guard,hidden=0,alive=true;
 guard=cfg.SurvivalTooltipDismiss.Create({panel:p,isAlive:()=>alive,isVisible:()=>p.visible,hide(){hidden++;p.visible=false;guard.Hidden();}});
 return {p,guard,hidden:()=>hidden,retire(){alive=false;},show(anchor){if(!guard.CanShow(anchor))return false;p.visible=true;guard.Shown(anchor);return true;}};
}
const anchor=panel('source',10,10,40,40),other=panel('covered-source',100,100,40,40),first=tooltip('passive',80,80),second=tooltip('another-window',260,80);
cursor=[20,20];assert(first.show(anchor));step();assert(first.p.visible,'Hovering the source keeps its tooltip visible');
cursor=[110,110];step();assert(!first.p.visible,'Entering a passive false/false tooltip hides it');assert.equal(first.hidden(),1);
assert(!first.show(anchor),'The source cannot immediately redisplay after dismiss');
assert(!second.show(other),'A covered source in another window cannot flash a replacement under the cursor');
anchor.deleted=true;assert(!second.show(other),'Refreshing or replacing the original card preserves the dismissed area');anchor.deleted=false;
step();step();assert.equal(first.hidden(),1,'Remaining inside dismissed area does not repeatedly hide');
cursor=[20,20];assert(!first.show(anchor),'Returning directly to the original source remains blocked');
cursor=[220,220];step();assert.equal(jobs.size,0,'No polling remains when the cursor leaves the tooltip and source');
cursor=[20,20];assert(first.show(anchor),'A fresh hover works after leaving both areas');
first.p.events.onmouseover();assert(!first.p.visible,'Hit tested tooltip entry follows the same immediate rule');
assert.equal(first.hidden(),2);first.guard.Dispose();assert.equal(jobs.size,0,'Disposal clears the dismissed region and timer');
cursor=[110,110];assert(second.show(other));second.retire();step();assert.equal(jobs.size,0,'Retired owner stops scheduling');
const shared=panel('shared-owner-surface',300,300,80,80);let owning='new',oldHidden=0,newHidden=0;
const old=cfg.SurvivalTooltipDismiss.Create({panel:shared,isVisible:()=>owning==='old',hide(){oldHidden++;old.Hidden();}});
const current=cfg.SurvivalTooltipDismiss.Create({panel:shared,isVisible:()=>owning==='new',hide(){newHidden++;current.Hidden();}});
old.Shown(anchor);current.Shown(other);shared.events.onmouseover();assert.equal(oldHidden,0);assert.equal(newHidden,1,'Shared surface only dismisses the active renderer');
old.Dispose();current.Dispose();second.guard.Dispose();assert.equal(jobs.size,0);
const api=cfg.SurvivalTooltipDismiss;vm.runInContext(source,context);assert.equal(cfg.SurvivalTooltipDismiss,api,'Loading another layout reuses one policy');
console.log('TOOLTIP_DISMISS_PASS: entry hides immediately; passive geometry; cross-window overlap guard; leave/reenter; owner isolation; no idle timers');
