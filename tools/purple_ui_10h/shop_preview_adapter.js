// Preview-only platform adapter. Production shop and commerce code stays unchanged.
const subscribers={};
window.previewScale=innerHeight/1080;
Panel.prototype.FindChildTraverse=function(id){return nodes[id]||null;};
Panel.prototype.SetFocus=function(){};
Panel.prototype.MoveChildBefore=function(child,before){this.children=this.children.filter(x=>x!==child);const at=this.children.indexOf(before);this.children.splice(Math.max(0,at),0,child);this.el.insertBefore(child.el,before.el);};
Panel.prototype.GetPositionWithinWindow=function(){const b=this.el.getBoundingClientRect();return {x:b.x,y:b.y};};
Panel.prototype.SetAttributeString=function(k,v){this.el.dataset[k]=v;};
Panel.prototype.GetAttributeString=function(k,f){return this.el.dataset[k]||f;};
Object.defineProperty(Panel.prototype,"actuallayoutwidth",{get(){return this.parent?this.el.getBoundingClientRect().width:innerWidth;}});
Object.defineProperty(Panel.prototype,"actuallayoutheight",{get(){return this.parent?this.el.getBoundingClientRect().height:innerHeight;}});
Object.defineProperty(Panel.prototype,"actualuiscale_x",{get(){return previewScale;}});
Object.defineProperty(Panel.prototype,"actualuiscale_y",{get(){return previewScale;}});
function imageURI(uri){const alias=IMAGE_ALIASES[uri];if(alias&&alias.startsWith("file:"))return alias;return IMAGE_ROOT+(alias||String(uri).replace("file://{images}/","").replace("s2r://panorama/images/","").replace(/_png\.vtex$|\.vtex$/,".png"));}
Panel.prototype.SetImage=function(uri){this.el.src=imageURI(uri);};
Object.defineProperty(Panel.prototype,"itemname",{set(v){this._item=v;this.el.style.backgroundImage='url("'+imageURI("file://{images}/items/"+v.replace(/^item_/,"")+".png")+'")';this.el.style.backgroundSize="contain";this.el.style.backgroundPosition="center";this.el.style.backgroundRepeat="no-repeat";}});
Object.defineProperty(Panel.prototype,"abilityname",{set(v){this._ability=v;this.el.style.backgroundImage='url("'+imageURI("file://{images}/spellicons/"+v+".png")+'")';this.el.style.backgroundSize="contain";this.el.style.backgroundPosition="center";this.el.style.backgroundRepeat="no-repeat";}});
const createPanel=$.CreatePanel;
function adapt(p){
 const original=p.style;
 p.style=new Proxy(original,{set(target,key,value){
  if(key==="backgroundColor"){target[key]=value;p.el.style.background=String(value).replace(/gradient\(linear,.*?from\((#[0-9a-f]+)\),(?:color-stop\([^)]*\),)*to\((#[0-9a-f]+)\)\)/gi,"linear-gradient(180deg,$1,$2)");return true;}
  if(key==="flowChildren"&&value==="none"){target[key]=value;p.el.style.display="block";return true;}
  if(key==="visibility"){target[key]=value;p.el.style.display=value==="collapse"?"none":"";return true;}
  return Reflect.set(target,key,value);
 }});
 return p;
}
$.CreatePanel=(type,parent,id)=>adapt(createPanel(type,parent,id));
root.style.width=(innerWidth/previewScale)+"px";root.style.height="1080px";root.style.transformOrigin="0% 0%";root.style.transform="scale3d("+previewScale+","+previewScale+",1)";
$.RegisterEventHandler=()=>{};$.RegisterForUnhandledEvent=()=>{};
GameEvents.Subscribe=(name,fn)=>{(subscribers[name]||=[]).push(fn);return 1;};
GameEvents.SendCustomGameEventToServer=(name,payload)=>previewCalls.push({name,payload});
Game.GetLocalPlayerID=()=>0;Game.GetGameTime=()=>100;Game.IsInToolsMode=()=>false;
const CustomNetTables={GetTableValue:(name,key)=>name==="survival_tooltips"?{desc:(SHOP_FIXTURE.find(e=>"shop_item:"+e.entry_id===key)||{}).description||""}:{},SubscribeNetTableListener:()=>1};
const Players={GetLocalPlayer:()=>0,GetPlayerName:()=>"生存档案"};
function emit(name,data){for(const fn of subscribers[name]||[])fn(data);}
let fixtureSequence=0;
window.previewShopTab=function(category){
 const mode=category==="challenge"?"challenge":"shop";
 if(category==="other")cfg.SurvivalShop.SelectOther();else if(category==="challenge")cfg.SurvivalShop.OpenChallenge();else cfg.SurvivalShop.SelectShop();
 emit("ui_shop_snapshot",{sequence:++fixtureSequence,full:1,ui_mode:mode,entries:SHOP_FIXTURE.filter(e=>mode==="challenge"?e.shop_id==="challenge"||e.shop_id==="rebirth":e.shop_id==="weapon"||e.shop_id==="item"),categories:[],resources:{gold:0,wood:0}});
 syncFlows();
};
if(PREVIEW_MODE==="shop"){
 const doc=new DOMParser().parseFromString(SHOP_XML,"application/xml");
 function make(el,parent){if(!["Panel","Button","Label","Image","DOTAItemImage"].includes(el.tagName))return;const p=adapt(new Panel(el.tagName,parent,el.getAttribute("id")));for(const c of(el.getAttribute("class")||"").split(" ").filter(Boolean))p.AddClass(c);if(el.getAttribute("text"))p.text=el.getAttribute("text");if(el.getAttribute("src"))p.SetImage(el.getAttribute("src"));if(el.getAttribute("visible")==="false")p.visible=false;for(const c of el.children)make(c,p);return p;}
 for(const el of doc.documentElement.children)make(el,root);
 for(const[id,fn]of [["ShopModeShop",()=>previewShopTab("equipment")],["ShopModeChallenge",()=>previewShopTab("challenge")]])nodes[id].SetPanelEvent("onactivate",fn);
}
window.syncFlows=()=>{document.querySelectorAll(".panel").forEach(parent=>{if(getComputedStyle(parent).display==="flex")for(const child of parent.children){if(!child.classList.contains("panel"))continue;if(child.classList.contains("UIModalInputShield")||getComputedStyle(child).getPropertyValue("--pano-ignore-flow").trim()==="true")continue;child.style.position="relative";child.style.left="auto";child.style.top="auto";child.style.transform="none";}});};
new MutationObserver(()=>requestAnimationFrame(syncFlows)).observe(root.el,{childList:true,subtree:true,attributes:true,attributeFilter:["class"]});
