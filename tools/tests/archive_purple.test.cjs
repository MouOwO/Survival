const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const path=require('node:path'),project=path.resolve(__dirname,'../..');
class Panel{
 constructor(parent,id='',classes=[]){this.id=id;this.children=[];this.classes=new Set(classes);this.style={};this.visible=true;this.parent=parent;if(parent)parent.children.push(this);}
 Children(){return this.children;} AddClass(c){this.classes.add(c);} BHasClass(c){return this.classes.has(c);} IsValid(){return true;}
 FindChildTraverse(id){if(this.id===id)return this;for(const child of this.children){const hit=child.FindChildTraverse(id);if(hit)return hit;}return null;}
}
const root=new Panel(null,'Root'),win=new Panel(root,'ArchiveWindow');
for(const id of ['ArchiveBody','ArchiveContent','ArchiveTabs','ArchiveGrid','ArchiveTooltip','ArchiveTooltipBody','ArchiveTooltipName','ArchiveTooltipStateText','ArchiveTooltipProgress'])new Panel(root,id);
const filters=new Panel(root,'ArchiveFilters'),nativeFilter=new Panel(filters,'ArchiveFilter_unlocked'),nativeLabel=new Panel(nativeFilter),radioBox=new Panel(nativeFilter,'',['RadioBox']);nativeLabel.paneltype='Label';nativeLabel.style.width='14px';nativeLabel.style.height='9px';nativeLabel.style.textOverflow='shrink';
const cfg={ArchiveHandoff:{
 Progress(item){return (item.count_known===0?'—':item.count)+' / '+item.target;},
 Icon(card,item){const art=new Panel(card,'',['ArchiveArt']),icon=new Panel(art,'',['ArchiveRewardIcon']);art.style.width='72px';art.style.height='56px';const count=new Panel(card,'',['ArchiveCount']);count.text='old count';},
 Card(card){for(const child of card.Children().slice())if(child.BHasClass('ArchiveCount')){const host=new Panel(card,'',['ArchiveCountHost']);card.children=card.children.filter(c=>c!==child);host.children.push(child);child.parent=host;}},
 Init(){},ApplyPalette(){},Hide(){}
}};
vm.runInNewContext(fs.readFileSync(path.join(project,'panorama/src/scripts/custom_game/archive_purple.js'),'utf8'),{GameUI:{CustomUIConfig:()=>cfg},$:{GetContextPanel:()=>root}});
const A=cfg.ArchiveHandoff,P=cfg.SurvivalArchivePurple;
assert.equal(P.Badge({count:3,target:5},'clear'),'3/5');
assert.equal(P.Badge({count:99,level:2,target:5},'building'),'2/5');
assert.equal(P.Badge({count:4,count_known:0},'fishing'),'×—');
assert.equal(P.Badge({count:7},'friend'),'×7');
assert.equal(P.Badge({},'titles'),'');
const grid=root.FindChildTraverse('ArchiveGrid'),card=new Panel(grid,'',['ArchiveCard']);
A.Icon(card,{count:3,target:5},'clear',{});A.Card(card);A.ApplyPalette();
const art=card.children.find(c=>c.BHasClass('ArchiveArt')),counter=card.children.find(c=>c.BHasClass('ArchiveCountHost')).children[0];
assert.equal(card.style.width,'128px');assert.equal(card.style.height,'128px');assert.equal(art.style.width,'92px');assert.equal(art.style.height,'92px');assert.equal(counter.text,'3/5');
assert(counter.BHasClass('ArchiveCompactBadge'));assert.equal(counter.style.fontSize,'16px');
card.AddClass('ArchiveHovered');A.ApplyPalette();assert(art.style.border.includes('#efd079'));
card.classes.delete('ArchiveHovered');A.Hide();assert(art.style.border.includes('#63518b'));
const promotion=new Panel(card,'',['ArchivePromote']),promotionText=new Panel(promotion);promotion.enabled=false;P.Decorate(card);assert.equal(promotion.style.backgroundColor,'#251a35');assert.equal(promotionText.style.color,'#9688a7');
promotion.enabled=true;P.Decorate(card);assert.equal(promotion.style.backgroundColor,'#3f285d');assert.equal(promotionText.style.color,'#ecdbfa');
const title=new Panel(grid,'',['ArchiveCard','ArchiveTitleCard']);A.Card(title);assert.equal(title.style.width,'268px');
const portrait=new Panel(grid,'',['ArchiveCard']);const viewport=new Panel(portrait,'',['ArchiveArt','ArchivePortraitViewport']);viewport.style.width='96px';const face=new Panel(viewport,'',['ArchiveRewardIcon']);face.style.width='192px';face.style.height='192px';face.style.position='-12px -24px 0px';
P.Decorate(portrait);P.Decorate(portrait);assert.equal(face.style.width,'184px');assert.equal(face.style.position,'-11.5px -23px 0px');
assert.equal(root.FindChildTraverse('ArchiveBody').style.position,'0px 132px 0px');assert.equal(root.FindChildTraverse('ArchiveTooltip').style.width,'380px');
assert.equal(root.FindChildTraverse('ArchiveTooltip').style.flowChildren,'down','the tooltip body must participate in its fit-content height');
assert.equal(nativeLabel.style.width,'100%');assert.equal(nativeLabel.style.height,'35px');assert.equal(nativeLabel.style.textOverflow,'clip','native RadioButton defaults cannot shrink anonymous filter labels into a tiny text box');assert.equal(radioBox.style.visibility,'collapse');
const controller=fs.readFileSync(path.join(project,'panorama/src/scripts/custom_game/archive_180de7e38b_titles_compact_v6.js'),'utf8');
assert(controller.includes('archiveFit={reference:[1920,1080]}') && controller.includes('fit:archiveFit'));
let opens=0,requests=0;
const apiEnv={active:()=>true,needsSync:()=>false,opened:false,fitGeneration:0,pageCache:{},current:'clear',panel:()=>({enabled:true,RemoveClass(){},AddClass(){}}),archiveShell:{Open(){opens++;}},dispose(){},request(){requests++;},render(){},renderVoid(){},hideTooltip(){},registerToolsProbe(){},GameUI:{CustomUIConfig:()=>cfg}};
apiEnv.close=()=>{apiEnv.opened=false;};vm.createContext(apiEnv);
vm.runInContext(controller.slice(controller.indexOf('    GameUI.CustomUIConfig().SurvivalArchive = api = {'),controller.indexOf('    $.RegisterEventHandler("Cancelled"')),apiEnv);
cfg.SurvivalArchive.Open();cfg.SurvivalArchive.Open();assert.equal(opens,1);assert.equal(requests,1);cfg.SurvivalArchive.Close();cfg.SurvivalArchive.Open();assert.equal(opens,2);
const titleStatus={},titleCalls=[],titleCard={SetPanelEvent(name,fn){this.activate=fn;}};
const titleEnv={active:()=>true,valid:p=>!!p,later(){},unlocked:true,titleSubmitting:false,data:{},panel:()=>titleStatus,actionLabel:{},rowCards:{title:{}},key:'title',equipped:false,item:{id:'peak_perfection'},card:titleCard,GameEvents:{SendCustomGameEventToServer(name,payload){titleCalls.push({name,payload});}},$:{Schedule(){}},request(){}};
const titleStart=controller.indexOf('                card.SetPanelEvent("onactivate",function() {'),titleEnd='\n                });';
vm.runInNewContext(controller.slice(titleStart,controller.indexOf(titleEnd,titleStart)+titleEnd.length),titleEnv);titleCard.activate();titleCard.activate();
assert.equal(titleCalls.length,1,'title requests remain guarded against repeated activation');assert.equal(titleStatus.text,'正在切换称号…','the compact card hides the action label, so pending feedback belongs in the visible footer');
const source=fs.readFileSync(path.join(project,'panorama/src/scripts/custom_game/archive_handoff_180de7e38b.js'),'utf8');
for(const scale of [.75,1,1.5]){
 const panels={ArchiveTooltip:{style:{width:'380px'},actuallayoutheight:300*scale,SetAttributeString(){}},ArchiveTooltipBody:{style:{}},ArchiveWindow:{style:{}}};
 const env={root:{actualuiscale_x:scale,actualuiscale_y:scale,actuallayoutwidth:1920,actuallayoutheight:1080},cfg:{SurvivalArchiveColors:{}},generation:1,anchor:{IsValid:()=>true,GetPositionWithinWindow:()=>({x:1800,y:980}),actuallayoutwidth:128*scale,actuallayoutheight:128*scale,actualuiscale_x:scale*1.25,actualuiscale_y:scale*1.25},p:id=>panels[id],$:{Schedule(){}},effectOnly:false};
 vm.createContext(env);vm.runInContext(source.slice(source.indexOf('    function place('),source.indexOf('function formatArchiveEffects')),env);env.position(1);
 const [x,y]=panels.ArchiveTooltip.style.position.split(' ').map(parseFloat);
 assert(x*scale>=11&&x*scale+380*scale<=1921);assert(y*scale>=11&&y*scale+300*scale<=1081);assert.equal(panels.ArchiveTooltip.style.transform,'none');
 env.anchor.GetPositionWithinWindow=()=>({x:100,y:100});env.position(1);
 assert.equal(parseFloat(panels.ArchiveTooltip.style.position),Math.round(100/scale+160+12),'native dimensions already contain UI scale; CSS fit multiplies only once');
}
console.log('ARCHIVE_PURPLE_PASS: real counts, unknown inventory, compact cells, title width, portrait resize once, hover reset and measured tooltip bounds at 3 UI scales');
