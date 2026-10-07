// Browser preview adapter only. Executes the same production component/controller JS.
const cfg={},nodes={};
class Panel {
 constructor(type,parent,id,el){this.type=type;this.parent=parent;this.id=id||'';this.children=[];this.events={};this.el=el||document.createElement(type==='Image'?'img':type==='Label'?'label':'div');this.el.classList.add('panel');this.el.dataset.type=type;if(type==='Label')this.el.classList.add('label');if(type==='Button')this.el.classList.add('button');if(parent){parent.children.push(this);parent.el.append(this.el);}if(id){nodes[id]=this;this.el.id=id;}this.enabled=true;
  this.style=new Proxy({}, {set:(o,k,v)=>{o[k]=v;const s=this.el.style;if(k==='position'){const t=String(v).split(' ');s.position='absolute';s.left=t[0];s.top=t[1];this.align();}else if(k==='horizontalAlign'||k==='verticalAlign'||k==='align'||k==='transform'){this.align();}else if(k==='backgroundImage')s.backgroundImage=String(v).replaceAll('file://{images}/',window.IMAGE_ROOT);else if((k==='width'||k==='height')&&v==='fit-children')s[k]='max-content';else if(k==='zIndex')s.zIndex=v;else if(k==='boxShadow'){s.boxShadow='none';}else if(k==='flowChildren'){s.display='flex';s.flexDirection=v==='down'?'column':'row';s.flexWrap=v==='right-wrap'?'wrap':'nowrap';}else if(k==='textOverflow'&&v==='shrink'){s.textOverflow='ellipsis';}else if(!['ignoreParentFlow','brightness'].includes(k)){s[k]=v;}return true;}});
 }
 align(){const a=this.style,centerX=a.horizontalAlign==='center',centerY=a.verticalAlign==='center';if(centerX)this.el.style.left='50%';else if(a.horizontalAlign==='right'){this.el.style.right='0';this.el.style.left='auto';}if(centerY)this.el.style.top='50%';this.el.style.transform=(centerX||centerY?'translate('+(centerX?'-50%':'0')+','+(centerY?'-50%':'0')+') ':'')+(a.transform||'');}
 AddClass(c){this.el.classList.add(c);}RemoveClass(c){this.el.classList.remove(c);}SetHasClass(c,on){this.el.classList.toggle(c,!!on);}BHasClass(c){return this.el.classList.contains(c);}
 SetPanelEvent(n,fn){const event={onactivate:'click',onmouseover:'mouseenter',onmouseout:'mouseleave'}[n]||n.slice(2);if(this.events[n])this.el.removeEventListener(event,this.events[n]);this.events[n]=fn;this.el.addEventListener(event,fn);}
 SetImage(uri){this.el.src=uri.replace('file://{images}/',window.IMAGE_ROOT);}SetScaling(){this.el.style.objectFit='contain';}
 RemoveAndDeleteChildren(){this.children=[];this.el.replaceChildren();}GetParent(){return this.parent;}GetChildCount(){return this.children.length;}GetChild(i){return this.children[i];}Children(){return this.children;}IsValid(){return !this.deleted;}DeleteAsync(){this.deleted=true;this.el.remove();}SetAcceptsFocus(){}
 get actuallayoutwidth(){return this.parent?this.el.offsetWidth:innerWidth;}get actuallayoutheight(){return this.parent?this.el.offsetHeight:innerHeight;}get actualuiscale_x(){return 1;}get actualuiscale_y(){return 1;}
 set text(t){this.el.textContent=t;}get text(){return this.el.textContent;}set visible(v){this.el.hidden=!v;}get visible(){return !this.el.hidden;}set enabled(v){this._enabled=v;this.el.classList.toggle('UIDisabled',v===false);}get enabled(){return this._enabled;}
 set hittest(v){this.el.dataset.hittest=String(v);if(this.type==='Image'||this.type==='Label')this.el.style.pointerEvents=v?'auto':'none';}set hittestchildren(v){this.el.dataset.hitChildren=String(v);}
}
const root=new Panel('Panel',null,'PreviewRoot',document.getElementById('PreviewRoot'));
function $(id){return nodes[String(id).replace(/^#/,'')];}$.GetContextPanel=()=>root;$.CreatePanel=(t,p,id)=>new Panel(t,p,id);$.Schedule=(d,fn)=>setTimeout(fn,d*1000);$.CancelScheduled=id=>clearTimeout(id);$.DispatchEvent=()=>{};$.Msg=()=>{};
const GameUI={CustomUIConfig:()=>cfg},GameEvents={Subscribe:()=>1,Unsubscribe:()=>{}},Game={};
window.previewCalls=[];
cfg.SurvivalPayments={GetCatalog:()=>window.CATALOG_FIXTURE.paid,RefreshCatalog:()=>{},Checkout:sku=>{previewCalls.push({method:'paid',sku});return true;}};
cfg.SurvivalCommerceWallet={GetCatalog:()=>window.CATALOG_FIXTURE.wallet,Refresh:()=>{},Checkout:sku=>{previewCalls.push({method:'wallet',sku});return true;}};
window.panoRoot=root;
window.selectCategory=id=>{const tab=root.children.flatMap(p=>p.children).find(p=>p.BHasClass('RCTabs'))?.children.find(p=>p.children.some(c=>c.text===(CATALOG_FIXTURE.paid.categories.find(c=>c.id===id)||{}).label));if(!tab)throw Error('Unknown category '+id);tab.events.onactivate();};
window.previewReady=true;
window.syncFlows=()=>{document.querySelectorAll('.panel').forEach(p=>{if(getComputedStyle(p).display==='flex')for(const c of p.children){if(c.classList.contains('panel')){c.style.position='relative';c.style.left='auto';c.style.top='auto';c.style.transform='none';}}});};
