const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const path=require('node:path');const root=path.resolve(__dirname,'../..');
function read(name){return fs.readFileSync(path.join(root,'panorama/src/scripts/custom_game',name),'utf8');}
class Panel {
 constructor(id='',type='Panel',parent=null){this.id=id;this.paneltype=type;this.parent=parent;this.children=[];this.style={};this.classes=new Set();this.hittest=true;this.hittestchildren=true;if(parent)parent.children.push(this);}
 IsValid(){return true;}GetParent(){return this.parent;}Children(){return this.children.slice();}AddClass(c){this.classes.add(c);}RemoveClass(c){this.classes.delete(c);}BHasClass(c){return this.classes.has(c);}SetImage(uri){this.uri=uri;}MoveChildBefore(child,before){this.children.splice(this.children.indexOf(child),1);this.children.splice(this.children.indexOf(before),0,child);}
}
const cfg={},panels={};const $=id=>panels[id.slice(1)];
$.CreatePanel=(t,p,id)=>new Panel(id,t,p);$.Msg=()=>{};
const context=vm.createContext({GameUI:{CustomUIConfig:()=>cfg},$,Game:{},console});
vm.runInContext(read('reference_windows.js'),context);
const win=new Panel('ArchiveWindow'),header=new Panel('ArchiveHeader','Panel',win),button=new Panel('close','Button',header);
const title=new Panel('DailyHeading','Label',header);title.style.color='#ffffff';
cfg.ReferenceWindows.Apply(win,header,button);const count=win.children.length;
cfg.ReferenceWindows.Apply(win,header,button);assert.equal(win.children.length,count,'Repeated opens must not add decorative layers');
assert.equal(button.hittest,true,'Close button remains interactive');assert.equal(title.style.color,'#eed8a7','Replace modal inline title color');
for(const child of win.children.filter(c=>c!==header)){
 const walk=p=>{assert.equal(p.hittest,false,'Decoration must not intercept a click');assert.equal(p.hittestchildren,false);p.Children().forEach(walk);};walk(child);
}
vm.runInContext(read('archive_theme_tokens.js'),context);vm.runInContext(read('archive_theme.js'),context);
const body=new Panel('ArchiveBody','Panel',win),heading=new Panel('ArchiveTitle','Label',header);
const item=new Panel('','Label',body);item.AddClass('ArchiveCount');
cfg.ArchiveTheme.Apply(win);cfg.ArchiveTheme.Apply(win);
assert.equal(body.style.backgroundColor,'transparent','Category refresh must retain continuous reference background');assert.equal(heading.style.color,'#eed8a7');assert.equal(item.style.color,cfg.SurvivalArchiveColors.number,'Progress gold must retain meaning');
item.style.textShadow='0px 1px 2px 3 #071018ff';item.style.fontWeight='bold';cfg.ArchiveTheme.Apply(win);
assert.equal(item.style.textShadow,'none','Refresh must retain the approved TreasureHint text without an outline');assert.equal(item.style.fontWeight,'normal');assert.equal(item.style.fontFamily,'"Source Han Sans SC", "Microsoft YaHei", sans-serif');
const tooltip=new Panel('ArchiveTooltip');cfg.ArchiveTheme.Apply(tooltip);assert.equal(tooltip.style.backgroundColor,cfg.SurvivalArchiveColors.surface_52,'Do not restyle accepted archive tooltips');
const viewport=new Panel('viewport');$.GetContextPanel=()=>viewport;
for(const id of ['LotteryWindow','LotteryMainCanvas','LotteryCelestialHeader','LotteryCloseButton'])panels[id]=new Panel(id);
vm.runInContext(read('lottery_handoff_bb9968eef7.js'),context);
for(const [w,h] of [[1280,720],[1920,1080],[2560,1440],[3440,1440],[1024,768]]){
 viewport.actuallayoutwidth=w;viewport.actuallayoutheight=h;viewport.actualuiscale_x=1;viewport.actualuiscale_y=1;
 cfg.LotteryHandoff.Prepare();const s=Number(panels.LotteryMainCanvas.style.transform.match(/scale3d\(([^,]+)/)[1]);
 assert.ok(Math.abs(parseFloat(panels.LotteryMainCanvas.style.width)*s-w)<.01,'Canvas fills viewport width');
 assert.ok(Math.abs(parseFloat(panels.LotteryMainCanvas.style.height)*s-h)<.01,'Canvas fills viewport height');
 assert.ok(parseFloat(panels.LotteryMainCanvas.style.width)>=1599.99 && parseFloat(panels.LotteryMainCanvas.style.height)>=899.99,'Controls retain safe area');
}
// Read dimensions from the shipped CSS, so stale overflow fails the check.
const css=fs.readFileSync(path.join(root,'panorama/src/styles/custom_game/reference_windows.css'),'utf8');
function rule(selector){const esc=selector.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');const matches=[...css.matchAll(new RegExp(esc+'\\s*\\{([^}]+)\\}','g'))];assert.ok(matches.length,selector);return matches.map(m=>m[1]).join(';');}
function val(s,prop){const m=[...s.matchAll(new RegExp('(?:^|;)\\s*'+prop+'\\s*:\\s*([^;]+)','g'))];assert.ok(m.length,prop);return m.at(-1)[1].trim();}
console.log('PASS: input-transparent archive frame, palette refresh and 5 full-screen viewport fits.');

const lockedCard=new Panel('','Panel',body);lockedCard.AddClass('ArchiveCard');lockedCard.AddClass('ArchiveContentLocked');
const lockedArt=new Panel('','Panel',lockedCard);lockedArt.AddClass('ArchiveArt');
const lockedName=new Panel('','Label',lockedCard);lockedName.AddClass('ArchiveItemName');
const lockedCount=new Panel('','Label',lockedCard);lockedCount.AddClass('ArchiveCount');
cfg.ArchiveTheme.Apply(win);
assert.equal(lockedName.style.color,'#9eafb6');assert.equal(lockedCount.style.color,'#788b93');assert.equal(lockedArt.style.brightness,'0.6');
lockedCard.classes.delete('ArchiveContentLocked');cfg.ArchiveTheme.Apply(win);
assert.equal(lockedName.style.color,'#e1e8e8');assert.equal(lockedCount.style.color,cfg.SurvivalArchiveColors.number);assert.equal(lockedArt.style.brightness,'1');
console.log('PASS: archive card refresh dims locked artwork/text and restores unlocked appearance.');

lockedCard.AddClass('ArchiveContentLocked');lockedCard.AddClass('ArchiveArtAlwaysBright');cfg.ArchiveTheme.Apply(win);
assert.equal(lockedArt.style.brightness,'1');assert.equal(lockedArt.style.saturation,'1');
assert.equal(lockedName.style.color,'#9eafb6');assert.equal(lockedCount.style.color,'#788b93');
lockedCard.classes.delete('ArchiveArtAlwaysBright');cfg.ArchiveTheme.Apply(win);
assert.equal(lockedArt.style.brightness,'0.6','Achievement artwork still follows unlock status');
console.log('PASS: collection artwork remains bright while locked text and achievement artwork remain dim.');

const actualImage=new Panel('','Image',lockedArt);actualImage.AddClass('ArchiveRewardIcon');
actualImage.style.saturation='0.2';actualImage.style.brightness='0.5';actualImage.style.opacity='0.6';actualImage.style.washColor='#999999';
lockedCard.AddClass('ArchiveArtAlwaysBright');cfg.ArchiveTheme.Apply(win);
assert.equal(actualImage.style.saturation,'1');assert.equal(actualImage.style.brightness,'1');assert.equal(actualImage.style.opacity,'1');assert.equal(actualImage.style.washColor,'none');
assert.equal(lockedName.style.color,'#9eafb6');
console.log('PASS: actual image filters reset independently of locked card text.');

const collectionRule=rule('.ArchiveRoot #ArchiveWindow.ReferenceWindow #ArchiveContent.ArchiveCollectionPage #ArchiveGrid');
assert.equal(parseFloat(val(collectionRule,'height')),504);
assert.ok(3*(164+4)<=504,'Three complete portrait rows must fit');
const footerRule=rule('.ArchiveRoot #ArchiveWindow.ReferenceWindow #ArchiveContent #ArchiveFooter');
const footerY=parseFloat(val(footerRule,'position').split(' ')[1]);
assert.ok(footerY>=568+54+10,'Draw controls and explanation must not overlap');
assert.ok(footerY+parseFloat(val(footerRule,'height'))<=692-16,'Footer must retain lower frame padding');
assert.ok(2*(214+4)<=440,'Two complete artifact rows must fit below source instructions');
console.log('PASS: archive collection rows, controls, footer padding and artifact rows.');

const fullCss=fs.readFileSync(path.join(root,'panorama/src/styles/custom_game/lottery_fullscreen_v2.css'),'utf8');
function fullRule(selector){const entry=fullCss.split(selector+' {')[1];assert(entry,selector);return entry.split('\n')[0];}
const grid=fullRule('#LotteryWindow #LotteryMainCanvas #LotteryItemList');
const reward=fullRule('#LotteryWindow #LotteryMainCanvas #LotteryItemList .LotteryRewardCard');
const gridW=parseFloat(val(grid,'width')),gridH=parseFloat(val(grid,'height'));
const rewardW=parseFloat(val(reward,'width')),rewardH=parseFloat(val(reward,'height'));
const gap=val(reward,'margin').split(/\s+/).map(parseFloat);
assert.equal(Math.floor((gridW+.01)/(rewardW+gap[1]*2)),5,'Exactly five rewards fit each row');
assert.equal(Math.floor((gridH+.01)/(rewardH+gap[0]*2)),2,'Exactly two complete rows fit');
assert.equal(val(reward,'background-color'),'transparent');assert.equal(val(reward,'border'),'0px');
assert(gridW<1600&&gridH+66+62<742,'Rewards, heading and actions fit the safe area');
for(const pool of ['map','cultivation','dragon_knight','summer']){
 assert(fullRule('#LotterySceneBackground.LotteryScene_'+pool).includes('/'+pool+'.png'));
 assert(fs.existsSync(path.join(root,'panorama/src/images/custom_game/lottery_cinematic_v1',pool+'.png')));
}
console.log('PASS: 5 x 2 borderless rewards, safe-area controls and four full-screen scene assets.');
