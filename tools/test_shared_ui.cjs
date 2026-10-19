const fs=require('fs'),vm=require('vm'),assert=require('assert');
const jobs=new Map(),nodes={};let serial=0,time=0,closed=[],draws=0;
class Panel{constructor(t,p,id){this.type=t;this.parent=p;this.id=id;this.children=[];this.classes=new Set();this.style={};this.events={};this.enabled=true;if(p)p.children.push(this);if(id)nodes[id]=this;}AddClass(c){this.classes.add(c)}RemoveClass(c){this.classes.delete(c)}SetHasClass(c,v){v?this.AddClass(c):this.RemoveClass(c)}SetPanelEvent(n,f){this.events[n]=f}}
const root=new Panel('Panel',null,'root');root.actuallayoutwidth=1920;root.actuallayoutheight=1080;
function $(){}$.GetContextPanel=()=>root;$.CreatePanel=(t,p,id)=>new Panel(t,p,id);$.Schedule=(dt,fn)=>{jobs.set(++serial,{at:time+dt,fn});return serial};$.CancelScheduled=id=>jobs.delete(id);
const previousUI={version:'1.0.3',IsAlive:()=>true},cfg={SurvivalUI:previousUI},env={$,GameUI:{CustomUIConfig:()=>cfg},GameEvents:{SendCustomGameEventToServer:()=>draws++}};
require('./load_shared_ui_test.cjs')(env,Panel,root);vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/ui_layers.js','utf8'),env);const U=cfg.SurvivalUI;
assert.notStrictEqual(U,previousUI,'A live older component version cannot retain the pre-cap Fit implementation');assert.equal(U.version,'1.0.4');vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/common/ui_components.js','utf8'),env);assert.strictEqual(cfg.SurvivalUI,U,'Reloading the current live version preserves its component owners');
function modal(id,explicit,fit){const scrim=new Panel('Panel',root,id+'scrim'),panel=new Panel('Panel',scrim,id),header=new Panel('Panel',panel,''),close=new Panel('Button',header,'');let shell;shell=U.ModalShell.Adopt({id,panel,scrim,root,header,closeButton:close,width:720,height:480,fit,closePolicy:explicit?'explicit':undefined,onClose(){closed.push(id);shell.Close()}});return{shell,panel,scrim,close,hit:scrim.children.at(-1)}}
const a=modal('a'),b=modal('b');a.shell.Open();a.shell.Open();assert.equal(jobs.size,1,'repeated open has one fit timer');b.shell.Open();assert.equal(U.ModalManager.Top(),'b');a.hit.events.onactivate();assert.equal(closed.length,0,'covered modal cannot close');assert(!b.scrim.events.onactivate,'window ancestor does not bind outside click');assert.equal(b.panel.events.onactivate(),true,'inside explicitly consumes input');assert.equal(closed.length,0,'inside does not close');b.hit.events.onactivate();assert.deepEqual(closed,['b']);assert.equal(jobs.size,1);U.ModalManager.CloseTop();assert.deepEqual(closed,['b','a']);assert.equal(jobs.size,0);assert.equal(U.ModalManager.Top(),null);
const c=modal('c',true);c.shell.Open();c.hit.events.onactivate();assert(c.shell.IsOpen());c.close.events.onactivate();assert(!c.shell.IsOpen());assert.equal(jobs.size,0);
// Open writes native visible=true: CSS UIClosed alone cannot undo that override.
assert.strictEqual(c.panel.visible,false,'Close must hide the native window, not only the scrim/class');
assert.strictEqual(c.scrim.visible,false);
c.shell.Open();assert.strictEqual(c.panel.visible,true);assert.strictEqual(c.scrim.visible,true);
c.close.events.onactivate();assert.strictEqual(c.panel.visible,false);assert.equal(U.ModalManager.Top(),null);
// Archive/daily use a sibling scrim, unlike the nested scrim above.
const siblingPanel=new Panel('Panel',root,'archive'),siblingScrim=new Panel('Button',root,'archive_scrim');
const sibling=U.ModalShell.Adopt({id:'archive',panel:siblingPanel,scrim:siblingScrim,root,width:1002,height:758});
sibling.Open();siblingScrim.events.onactivate();assert.strictEqual(siblingPanel.visible,false);assert.strictEqual(siblingScrim.visible,false);assert.equal(U.ModalManager.Top(),null);
sibling.Open();assert.strictEqual(siblingPanel.visible,true);sibling.Close();assert.strictEqual(siblingPanel.visible,false);assert.equal(jobs.size,0);
let actions=0;const button=U.ActionButton(root,{label:'测试',action:()=>actions++});button.events.onactivate();U.State.Set(button,{busy:true});button.events.onactivate();U.State.Set(button,{busy:false,enabled:false});button.events.onactivate();assert.equal(actions,1);U.State.Set(button,{enabled:true,selected:true});button.events.onactivate();assert.equal(actions,2);assert(button.BHasClass('UISelected'));
const check=U.Checkbox(root,{checked:true,label:'跳过'});assert.equal(check.children.filter(n=>n.BHasClass('UICheckOff')||n.BHasClass('UICheckOn')).length,2);assert.equal(check.children[0].style.width,check.children[1].style.width,'glyph hit boxes stable despite canvas padding');
assert(!U.ProgressBadge(root,{current:3}).visible);assert.equal(U.ProgressBadge(root,{current:8,required:3}).text,'8/3');
const vip=U.VipBundleCard(root,{name:'仅测试变体',eligible:false,requiredVipLevel:2,prices:[{amount:3,currency:'A'},{amount:9,currency:'B'}],action:()=>actions++});assert.equal(vip.enabled,true,'card remains readable');assert.equal(vip.purchase.enabled,false);vip.purchase.events.onactivate();assert.equal(actions,2);
const tabs1=U.TabBar(root,{items:[{id:'a',label:'A'},{id:'b',label:'B'}],selectedId:'a'}),tabs2=U.TabBar(root,{items:[{id:'a',label:'A'},{id:'b',label:'B'}],selectedId:'a'});tabs2.Select('b');assert(tabs1.panel.children[0].BHasClass('UISelected'));assert(tabs2.panel.children[1].BHasClass('UISelected'));
for(const [w,h,u] of [[1920,1080,1],[1280,720,2/3],[2560,1440,4/3],[3440,1440,4/3]]){root.actuallayoutwidth=w;root.actuallayoutheight=h;root.actualuiscale_x=u;root.actualuiscale_y=u;const scale=U.Fit(a.panel,root,1002,758);assert(scale*1002*u<=w);assert(scale*758*u<=h);const axis=a.panel.style.transform.match(/scale3d\(([^,]+),([^,]+)/);assert.equal(axis[1],axis[2]);}
const fitOptions=Object.freeze({widthFraction:.95,heightFraction:.9,maxScale:1}),reference=Object.freeze({reference:Object.freeze([1200,778])});
const portrait=new Panel('Image',a.panel,'fitPortrait');portrait.style.width='76px';portrait.style.height='76px';const caption=new Panel('Label',a.panel,'fitCaption');caption.style.fontSize='17px';
for(const [w,h,u] of [[1920,1080,1],[1366,768,1],[2560,1440,4/3],[3840,2160,2],[800,600,1],[640,360,1],[1280,720,2]]){
 root.actuallayoutwidth=w;root.actuallayoutheight=h;root.actualuiscale_x=u;root.actualuiscale_y=u;
 const oldReference=Math.min(w/u/1200,h/u/778),oldSize=Math.min(w/u*.95/960,h/u*.9/548);
 assert.equal(U.Fit(a.panel,root,960,548,reference),oldReference,'Omitting maxScale preserves reference-based sizing exactly');
 assert.equal(U.Fit(a.panel,root,960,548),oldSize,'Omitting maxScale preserves size-based sizing exactly');
 const fitted=U.Fit(a.panel,root,960,548,fitOptions);assert.equal(fitted,Math.min(1,oldSize));assert(fitted<=1,'Large screens never magnify a pixel-sized window');
 if(oldSize<1)assert(fitted<1,'Small screens still reduce the complete window to fit');else assert.equal(fitted,1,'A window that fits keeps its authored dimensions');
 assert.equal(portrait.style.width,'76px');assert.equal(portrait.style.height,'76px');assert.equal(caption.style.fontSize,'17px','Native UI scaling never changes authored text or image dimensions');assert.equal(root.actualuiscale_x,u);
}
root.actuallayoutwidth=1920;root.actuallayoutheight=1080;root.actualuiscale_x=root.actualuiscale_y=1;
for(const maxScale of [undefined,null,0,-1,Infinity,NaN,'invalid'])assert.equal(U.Fit(a.panel,root,960,548,{reference:[1200,778],maxScale}),1080/778,'Invalid or omitted limits preserve the previous reference behavior');
assert.equal(U.Fit(a.panel,root,960,548,{reference:[1200,778],maxScale:.75}),.75,'A valid caller-selected maximum also applies to reference fitting');
const capped=modal('cappedFit',false,fitOptions);capped.shell.Open();assert.equal(capped.panel.style.transform,'scale3d(1,1,1)');assert.equal(jobs.size,1);
root.actuallayoutwidth=640;root.actuallayoutheight=360;
let fitJob=jobs.values().next().value;jobs.clear();time=fitJob.at;fitJob.fn();assert.equal(capped.panel.style.transform,'scale3d(0.675,0.675,1)','The real modal resize timer retains the opt-in limit and small-screen fit');assert.equal(jobs.size,1);
root.actuallayoutwidth=1920;root.actuallayoutheight=1080;fitJob=jobs.values().next().value;jobs.clear();time=fitJob.at;fitJob.fn();assert.equal(capped.panel.style.transform,'scale3d(1,1,1)','A later resize cannot restore automatic upscaling');capped.shell.Close();assert.equal(jobs.size,0);
const sequence=U.DrawResultSequence(),seen=[];sequence.Play([{id:'real_a'},{id:'real_b'}],{timing:{enter:10,flip:20,ready:30},flipHalf:2,onCharged(){},onEnter(i,x){seen.push(x.id)},onFlip(){},onReveal(){},onReady(){}});sequence.Cancel();assert.equal(jobs.size,0);assert.equal(draws,0,'presentation components cannot grant or request draws');
const css=fs.readFileSync('panorama/src/styles/custom_game/common/ui_components.css','utf8');assert(css.includes('.UINavToggle:selected:hover'));assert(css.includes('.UIActionButton.UIGold.UIBusy'));assert(!/\.UIIconButton[^{}]*\{[^{}]*scale3d/.test(css));
console.log('SHARED_UI_PASS: top-only close, isolated scrim, no timer duplication, busy/disabled guard, checkbox bounds, data variants, independent tabs, unchanged default fit and opt-in maximum with native scale and modal resize coverage');
