// Browser-only adapter. All rendered queue and archive nodes come from production JS/XML.
const subscribers={};
// Panorama lays out at 1080 UI units, then scales to the actual game viewport.
window.previewScale=innerHeight/1080;
const createNativePreview=$.CreatePanel;
function adaptNativePanel(panel){const original=panel.style;panel.style=new Proxy(original,{set:(target,key,value)=>{if(key==='flowChildren'&&value==='none'){Reflect.set(target,key,value);panel.el.style.display='block';return true;}if(value==='fill-parent-flow(1)'){panel.el.style.flex='1';panel.el.style.minHeight='0';panel.el.style.minWidth='0';}if(key==='visibility'){panel.el.style.display=value==='collapse'?'none':target.flowChildren&&target.flowChildren!=='none'?'flex':'block';}if(key==='brightness'||key==='saturation')panel.el.style.filter='brightness('+(key==='brightness'?value:target.brightness||1)+') saturate('+(key==='saturation'?value:target.saturation||1)+')';return Reflect.set(target,key,value);}});return panel;}
$.CreatePanel=function(type,parent,id){return adaptNativePanel(createNativePreview(type,parent,id));};
Object.defineProperty(Panel.prototype,'paneltype',{get(){return this.type;}});
window.syncFlows=()=>{document.querySelectorAll('.panel').forEach(parent=>{if(getComputedStyle(parent).display==='flex')for(const child of parent.children){if(!child.classList.contains('panel'))continue;if(getComputedStyle(child).getPropertyValue('--pano-ignore-flow').trim()==='true'||child.classList.contains('UINineSlice')||child.classList.contains('ArchiveTitleArt')){child.style.position='absolute';continue;}child.style.position='relative';child.style.left='auto';child.style.top='auto';child.style.transform='none';}});};
// Panorama Label HTML supports font/br only; convert its escaped markup for preview.
Object.defineProperty(Panel.prototype,'text',{set(value){if(this.type==='Label'&&this.html)this.el.innerHTML=String(value);else this.el.textContent=value;},get(){return this.el.textContent;}});
window.previewGeometry=()=>cfg.HandoffGeometry(innerWidth/previewScale,1080,3);
Object.defineProperty(Panel.prototype,'actualuiscale_x',{get(){return previewScale;}});
Object.defineProperty(Panel.prototype,'actualuiscale_y',{get(){return previewScale;}});
root.style.width=(innerWidth/previewScale)+'px';root.style.height='1080px';
root.style.transformOrigin='0% 0%';root.style.transform='scale3d('+previewScale+','+previewScale+',1)';
Panel.prototype.FindChildTraverse=function(id){return nodes[id]||null;};
Panel.prototype.SetParent=function(parent){this.parent.children=this.parent.children.filter(x=>x!==this);this.parent=parent;parent.children.push(this);parent.el.append(this.el);};
Panel.prototype.MoveChildBefore=function(child,before){this.children=this.children.filter(x=>x!==child);const at=this.children.indexOf(before);this.children.splice(Math.max(0,at),0,child);this.el.insertBefore(child.el,before.el);};
Panel.prototype.GetPositionWithinWindow=function(){const r=this.el.getBoundingClientRect();return {x:r.x,y:r.y};};
Object.defineProperty(Panel.prototype,'checked',{set(v){this.el.classList.toggle('Selected',!!v);},get(){return this.el.classList.contains('Selected');}});
Object.defineProperty(Panel.prototype,'abilityname',{set(v){this._ability=v;this.el.style.backgroundImage='url("'+IMAGE_ROOT+'spellicons/survival/native/'+v.replace(/^ability_/,'')+'.png")';this.el.style.backgroundSize='cover';}});
$.RegisterEventHandler=()=>{};$.Localize=s=>s;$.DispatchEvent=(name,node,body)=>{window.lastTooltip={name,body};};
GameEvents.Subscribe=(name,f)=>{(subscribers[name]||=[]).push(f);return 1;};GameEvents.SendCustomGameEventToServer=(name,payload)=>previewCalls.push({name,payload});
Game.GetLocalPlayerID=()=>0;Game.GetGameTime=()=>100;Game.AddCommand=()=>{};Game.GetState=()=>10;Game.IsInToolsMode=()=>false;
const Players={GetLocalPlayerPortraitUnit:()=>window.selectedEntity||42};const Entities={GetUnitName:id=>id===42?'building_main_city':id===43?'building_research_lab':'npc_dota_hero_ogre_magi'};
const CustomNetTables={GetTableValue:()=>({}),SubscribeNetTableListener:()=>1};
function emit(name,data){for(const f of subscribers[name]||[])f(data);}
const xml=new DOMParser().parseFromString(ARCHIVE_XML,'application/xml');
function make(el,parent){if(!['Panel','Button','RadioButton','Label','Image'].includes(el.tagName))return;const p=adaptNativePanel(new Panel(el.tagName,parent,el.getAttribute('id')));if(el.tagName==='RadioButton')p.el.classList.add('radio');for(const c of (el.getAttribute('class')||'').split(' ').filter(Boolean))p.AddClass(c);if(el.getAttribute('visible')==='false')p.visible=false;if(el.getAttribute('text'))p.text=el.getAttribute('text');if(el.getAttribute('src'))p.SetImage(el.getAttribute('src'));for(const c of el.children)make(c,p);return p;}
make(xml.querySelector('root>Panel'),root);new Panel('Panel',root,'SurvivalProductionPanel');new Panel('Panel',root,'SurvivalResearchAutoMarkers');
for(const id of ['ArchiveEntry','TreasureEntry','DailyEntry','PassEntry','EndlessStatus'])nodes[id].visible=false;
for(const id of ['VIPWindow','VIPScrim','VIPTooltip'])if(nodes[id])nodes[id].visible=false;
cfg.SurvivalRewardPresentation={BadgeColor:()=> '#cfb679',CreateIcon:(parent,item,cls)=>{const p=new Panel('Image',parent,'');p.AddClass(cls);p.SetImage('file://{images}/items/survival_unified/'+(item.icon||'item_octarine_core').replace(/^item_/,'')+'.png');}};
cfg.SurvivalSelectionResolver={Resolve:()=>window.selectedEntity||42};
