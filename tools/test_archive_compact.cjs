const fs=require('fs'),vm=require('vm'),assert=require('assert');
const panels={},cfg={};
class Panel {
 constructor(type,id=''){this.paneltype=type;this.id=id;this.style={};this.classes=new Set();this.children=[];this.visible=true;}
 AddClass(c){this.classes.add(c);} RemoveClass(c){this.classes.delete(c);} BHasClass(c){return this.classes.has(c);}
 SetHasClass(c,on){on?this.AddClass(c):this.RemoveClass(c);} Children(){return this.children;}
 RemoveAndDeleteChildren(){this.children=[];} SetPanelEvent(){} SetImage(value){this.image=value;}
}
cfg.ArchiveHandoffAssets={'icon_check_light.png':'test-check','icon_lock_light.png':'test-lock'};
const root=new Panel('Panel','ArchiveWindow');
function panel(id){if(!panels[id]){panels[id]=new Panel(id.includes('Label')||id==='ArchiveContext'?'Label':'Panel',id);root.children.push(panels[id]);}return panels[id];}
function label(parent,text,cls){const p=new Panel('Label');p.text=text;if(cls)p.AddClass(cls);parent.children.push(p);return p;}
const env={GameUI:{CustomUIConfig:()=>cfg},current:'clear',array:v=>v||[],rowCards:{},filterMode:'all',panel,label,
 hideTooltip(){},tabs(){},showDrawBar(){},isDrawPage:()=>false,icon(){},cardFrame(){},request(){},tooltip(){},
 $:{CreatePanel(type,parent){const p=new Panel(type);parent.children.push(p);return p;},Schedule(){}},GameEvents:{SendCustomGameEventToServer(){}},lastData:null};
vm.createContext(env);
for(const f of ['archive_theme_tokens.js','archive_theme.js'])vm.runInContext(fs.readFileSync('panorama/src/scripts/custom_game/'+f,'utf8'),env);
let paletteRuns=0;env.A={Observe(){},Unlocked:(r,c)=>r.completed!==undefined?Number(r.completed)===1:Number(r.count)>0,ApplyPalette(){paletteRuns++;cfg.ArchiveTheme.Apply(root);}};
const source=fs.readFileSync('panorama/src/scripts/custom_game/archive_180de7e38b.js','utf8');
vm.runInContext(source.slice(source.indexOf('    function render(data)'),source.indexOf('    GameEvents.Subscribe("survival_archive_snapshot"')),env);
const data={category_id:'clear',categories:[],rows:[{id:'a',name:'N1',count:1,completed:1},{id:'b',name:'N2',count:0,completed:0}]};
env.render(data);assert.equal(panel('ArchiveFilterAllLabel').text,'全部（1/2）');assert.equal(paletteRuns,1);
const first=env.rowCards['clear:0'].panel.children.find(p=>p.BHasClass('ArchiveItemName'));
assert.equal(first.style.color,cfg.SurvivalArchiveColors.name);assert.equal(first.style.fontFamily,undefined,'palette must preserve CSS font metrics');
env.filterMode='unlocked';env.render(data);assert.equal(panel('ArchiveFilterAllLabel').text,'全部（1/2）');assert.equal(env.rowCards['clear:1'].panel.visible,false);
env.current='fragment';env.filterMode='all';
env.render({category_id:'fragment',categories:[],rows:[{id:'fragment_01',name:'神兵-破碎大剑',count:0,promotion_target:'fragment_05',promotion_cost:10,can_promote:0}]});
const card=env.rowCards['fragment:0'].panel,promote=card.children.find(p=>p.BHasClass('ArchivePromote'));
assert.equal(card.children.find(p=>p.BHasClass('ArchiveItemName')).text,'破碎大剑');
assert.equal(promote.style.backgroundImage,'none');assert.equal(promote.children[0].style.color,cfg.SurvivalArchiveColors.button_disabled_text);
const native=JSON.parse(fs.readFileSync('data/ui/archive_native_icons.json','utf8'));
for(const filename of ['icons_remaining_5d5c1152eb.js','item_art_remaining_5d5c1152eb.js']){
 const s=fs.readFileSync('panorama/src/scripts/custom_game/'+filename,'utf8');
 for(const [id,row] of Object.entries(native)){assert(s.includes(row.runtime_uri));assert(s.includes(row.icon_path));}
}
const css=fs.readFileSync('panorama/src/styles/custom_game/archive_comfort.css','utf8');
assert(css.includes('width:112px; height:108px'));assert(css.includes('#ArchivePageHeader'));assert(css.includes('font-family:'+cfg.SurvivalArchiveColors.tooltip_font));
console.log('ARCHIVE_COMPACT_PASS: current renderer applies palette after cards, counts survive filtering, dark disabled promotion, twelve native icons in both catalogs');

// Exercise the real icon wrapper: its old inline dimensions overrode compact CSS.
Panel.prototype.SetImage=function(value){this.image=value;};
Panel.prototype.SetScaling=function(value){this.scaling=value;};
cfg.ArchiveHandoff={Icon(){},Init(){},Observe(){},Progress(){return '0 / 999';}};
vm.runInContext(fs.readFileSync('panorama/src/scripts/custom_game/icons_remaining_5d5c1152eb.js','utf8'),env);
const iconCard=new Panel('Panel');cfg.ArchiveHandoff.Icon(iconCard,{id:'fragment_01'},'fragment',{});
const actualArt=iconCard.children.find(p=>p.BHasClass('ArchiveArt'));
assert.equal(actualArt.style.width,'128px');assert.equal(actualArt.style.height,'112px');
assert(actualArt.children[0].image.startsWith('s2r://panorama/images/econ/'));
const tip=new Panel('Panel','ArchiveTooltip'),frame=new Panel('Panel','ArchiveTooltipFrame');tip.children.push(frame);
cfg.ArchiveTheme.Apply(tip);
const abilitySurface=fs.readFileSync('panorama/src/styles/custom_game/ability_tooltip.css','utf8').match(/#CustomAbilityTooltip\s*\{([^}]+)\}/)[1];
function abilityProperty(name){return abilitySurface.match(new RegExp('(?:^|;)\\s*'+name+'\\s*:\\s*([^;]+);'))[1].trim();}
const trainingSurface=fs.readFileSync('panorama/src/styles/custom_game/production_progress.css','utf8').match(/#SurvivalProductionPanel\s*\{([^}]+)\}/)[1];
const trainingBackground=trainingSurface.match(/background-color\s*:\s*([^;]+);/)[1].trim().replace(/#([0-9a-f]{6})[0-9a-f]{2}\b/gi,'#$1');
assert.equal(tip.style.backgroundColor,trainingBackground);
assert.equal(tip.style.border,abilityProperty('border'));
assert.equal(tip.style.boxShadow,abilityProperty('box-shadow'));
assert.equal(frame.style.visibility,'collapse');
assert.equal(tip.style.opacity,'1');assert(tip.style.backgroundColor.includes('from(#16353e)'));
const tooltipBody=new Panel('Panel','ArchiveTooltipBody');cfg.ArchiveTheme.Apply(tooltipBody);
assert.equal(tooltipBody.style.backgroundColor,tip.style.backgroundColor);
for(const key of ['archive_text_size','tooltip_title_size','tooltip_body_size','tooltip_field_size','tooltip_meta_size']) assert.equal(cfg.SurvivalArchiveColors[key],'19px');
assert(cfg.SurvivalArchiveColors.tooltip_font.startsWith('"Source Han Sans SC"'));

const bar=new Panel('Panel','ArchiveDrawBar'),draw=new Panel('Button','ArchiveDraw'),drawText=label(draw,'抽奖 ×1');
draw.enabled=false;bar.children.push(draw);cfg.ArchiveTheme.Apply(bar);
assert.equal(bar.style.flowChildren,'none');assert.equal(draw.style.backgroundColor,cfg.SurvivalArchiveColors.button_disabled);
assert.equal(drawText.style.color,cfg.SurvivalArchiveColors.button_disabled_text);
env.current='endless';env.render({category_id:'endless',categories:[],rows:[{id:'tier1',name:'无尽存档1（1000分）',count:0,target:1000,completed:0}]});
assert.equal(env.rowCards['endless:0'].panel.children.find(p=>p.BHasClass('ArchiveItemName')).text,'第 1 阶');
console.log('ARCHIVE_LIVE_AUDIT_REGRESSION_PASS: production icon wrapper, shared training-panel background, dark draw state, short tier name');

// Shared card renderer: use shapes for state, preserve state changes on cached cards.
for(const category of ['clear','endless','fragment','friend','map_level','work','building','boss']) {
 env.current=category;env.filterMode='all';
 const snapshot={category_id:category,categories:[],rows:[{id:'quiet',name:'测试',count:0,completed:0,cost:1}]};
 env.render(snapshot);
 let c=env.rowCards[category+':0'].panel;
 assert(!c.children.some(p=>p.BHasClass('ArchiveUnlockBadge')));
 let state=c.children.find(p=>p.BHasClass('ArchiveStateIcon'));
 assert(state.BHasClass('Locked'));assert.equal(state.image,'test-lock');
 assert.equal(state.style.washColor,cfg.SurvivalArchiveColors.state_locked);
 snapshot.rows[0].count=1;snapshot.rows[0].completed=1;env.render(snapshot);
 c=env.rowCards[category+':0'].panel;state=c.children.find(p=>p.BHasClass('ArchiveStateIcon'));
 assert(state.BHasClass('Unlocked'));assert.equal(state.image,'test-check');
 assert.equal(c.children.filter(p=>p.BHasClass('ArchiveStateIcon')).length,1);
}
// Exercise tinted icons too: the production wrapper must not write rarity backgrounds.
// Unknown IDs use fallback; derive a real tone-colored row from the generated catalog.
const iconSource=fs.readFileSync('panorama/src/scripts/custom_game/icons_remaining_5d5c1152eb.js','utf8');
const catalog=JSON.parse(iconSource.match(/entries=(\[.*\]);/)[1]);
const toneRow=catalog.find(r=>r.tone_color);assert(toneRow);
const toneCard=new Panel('Panel');cfg.ArchiveHandoff.Icon(toneCard,{id:toneRow.item_id},toneRow.category_id,{});
const toneArt=toneCard.children.find(p=>p.BHasClass('ArchiveArt'));
assert.equal(toneArt.style.backgroundColor,undefined);
cfg.ArchiveTheme.Apply(toneCard);
assert.equal(toneArt.style.backgroundColor,cfg.SurvivalArchiveColors.icon_surface);
assert.equal(toneArt.style.border,'1px solid '+cfg.SurvivalArchiveColors.icon_border);
console.log('ARCHIVE_QUIET_CARDS_PASS: shared lock/check states, cached state transitions, neutral toned-icon frames');

// All clear/endless tiers have one tint, independent of the generated tier color.
for(const row of catalog.filter(r=>r.category_id==='clear')) {
 const card=new Panel('Panel');cfg.ArchiveHandoff.Icon(card,{id:row.item_id},row.category_id,{});
 const art=card.children.find(p=>p.BHasClass('ArchiveArt'));
 assert.equal(art.children[0].style.washColor,cfg.SurvivalArchiveColors.achievement_tint);
}
const handoffSource=fs.readFileSync('panorama/src/scripts/custom_game/archive_handoff_180de7e38b.js','utf8');
env.cfg=cfg;
vm.runInContext(handoffSource.slice(handoffSource.indexOf('function formatArchiveEffects'),handoffSource.indexOf('    function show(item')),env);
const markup=env.effectMarkup('攻击+50；攻速+2%；说明 <tag> & Lv0');
assert(markup.includes('<font color="#f0d48a">+50</font>'));
assert(markup.includes('<font color="#f0d48a">+2%</font>'));
assert(markup.includes('&lt;tag&gt; &amp; Lv'));assert(!markup.includes('<tag>'));assert(markup.includes('<br>'));
console.log('ARCHIVE_REFERENCE_STYLE_PASS: all achievement tints, enlarged fragment art, escaped gold effect values');

env.current='endless';env.render({category_id:'endless',categories:[],rows:[{id:'endless_51',name:'无尽层数10',short_name:'超过10层',count:10,target:11,completed:0}]});
assert.equal(env.rowCards['endless:0'].panel.children.find(p=>p.BHasClass('ArchiveItemName')).text,'超过10层');
for(const id of ['endless_51','endless_82']) {
 const parent=new Panel('Panel');cfg.ArchiveHandoff.Icon(parent,{id},'endless',{});
 const art=parent.children.find(p=>p.BHasClass('ArchiveArt'));assert(art);
 assert(art.children[0].BHasClass('ArchiveEndlessEmblem'));
 assert.equal(art.children[0].children.length,2);
}
assert.equal(catalog.filter(r=>r.category_id==='endless').length,82);
console.log('ARCHIVE_ENDLESS_UI_PASS: 82 mapped icons, floor short names, shared readable counter layout');

// Detached popup stays at native scale while its card anchor still follows modal fit.
for(const scale of [0.75,1,1.5]) {
 const tip={style:{},actuallayoutheight:240*scale,SetAttributeString(){}},body={style:{}};
 const mock={ArchiveTooltip:tip,ArchiveTooltipBody:body,ArchiveWindow:{style:{},GetPositionWithinWindow(){return {x:400,y:50};}}};
 const pos={cfg:cfg,root:{actualuiscale_x:scale,actualuiscale_y:scale,actuallayoutwidth:1920,actuallayoutheight:1080},
   generation:7,anchor:{IsValid(){return true;},GetPositionWithinWindow(){return {x:1700,y:940};},BHasClass(){return false;}},
   effectOnly:false,p:id=>mock[id],$:{Schedule(){}}};
 vm.createContext(pos);
 vm.runInContext(handoffSource.slice(handoffSource.indexOf('    function place('),handoffSource.indexOf('function formatArchiveEffects')),pos);
 pos.position(7);
 assert.equal(tip.style.transform,'none');
 const xy=tip.style.position.split(' ').map(parseFloat);
 assert(xy[0]*scale>=0&&xy[0]*scale+460*scale<=1921);
 assert(xy[1]*scale>=0&&xy[1]*scale+tip.actuallayoutheight<=1081);
}
console.log('ARCHIVE_TOOLTIP_NATIVE_SCALE_PASS: identical opaque surfaces/font roles and screen bounds at 3 UI scales');

// Exercise the production reparenting step that gives progress its own center host.
const cardWrapStart=handoffSource.indexOf('Card:function(card)');
const cardWrapSource=handoffSource.slice(cardWrapStart+5,handoffSource.indexOf('        Init:function()',cardWrapStart)).trim().replace(/,$/,'');
const wrapCard=vm.runInContext('('+cardWrapSource+')',env);
const hostedCard=new Panel('Panel'),counter=label(hostedCard,'0 / 1000000','ArchiveCount'),cardName=label(hostedCard,'第50阶','ArchiveItemName');
for(const child of [counter,cardName])child.SetParent=function(parent){hostedCard.children=hostedCard.children.filter(p=>p!==this);parent.children.push(this);};
wrapCard(hostedCard);
assert(!hostedCard.children.includes(counter));assert(!hostedCard.children.includes(cardName));
assert.equal(hostedCard.children.find(p=>p.BHasClass('ArchiveCountHost')).children[0],counter);
assert.equal(hostedCard.children.find(p=>p.BHasClass('ArchiveNameHost')).children[0],cardName);
console.log('ARCHIVE_COUNT_HOST_PASS: actual card wrapper reparents count and name without skipping children');

for(const key of ['surface_16','surface_17','surface_32','surface_33','surface_35','surface_37','icon_surface'])
 assert.equal(cfg.SurvivalArchiveColors[key],cfg.SurvivalArchiveColors.surface_52,key+' must share the training-panel background');
assert.equal(cfg.SurvivalArchiveColors.tooltip_width,'460px');
console.log('ARCHIVE_REFERENCE_SURFACES_PASS: text/card/icon/popup backgrounds share the training-panel gradient');

// Native text overlays convert screen coordinates once; glyphs have no modal transform.
const nativeRectSource=handoffSource.slice(handoffSource.indexOf('    function cardTextRect('),handoffSource.indexOf('    function updateNativeCardText('));
const nativeRectEnv={};vm.createContext(nativeRectEnv);vm.runInContext(nativeRectSource,nativeRectEnv);
for(const fit of [0.8,1,1080/941,1.4]) {
 const r=nativeRectEnv.cardTextRect({x:300,y:250},{x:200,y:200},100,25,0.75,0.75,fit);
 assert.equal(r.x,100/0.75);assert.equal(r.y,50/0.75);
 assert.equal(r.w,100*fit/0.75);assert.equal(r.h,25*fit/0.75);
}
assert(css.includes('.ArchiveNativeText'));assert(css.includes('transform:none;'));
console.log('ARCHIVE_CARD_NATIVE_TEXT_PASS: untransformed text layer preserves scaled card positions at four fits');
