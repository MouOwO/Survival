const assert=require('node:assert/strict');
const {createHarness}=require('./fixtures/menus_v10_harness.cjs');
const h=createHarness(),{cfg,nodes,root}=h;
cfg.ArchiveHandoff={};
h.load('archive_parchment_data.js');h.load('archive_v10_semantics.js');h.load('common/archive_tooltip.js');
const Panel=root.constructor,firstParent=new Panel('Panel',root,'FirstOwner'),secondParent=new Panel('Panel',root,'SecondOwner');
secondParent.style.position='400px 0px 0px';h.setCursor(0,0);
const firstCard=new Panel('Button',firstParent,'FirstCard'),secondCard=new Panel('Button',secondParent,'SecondCard');
firstCard.style.position='100px 100px 0px';secondCard.style.position='200px 100px 0px';
const options=(parent,idPrefix)=>({parent,root,idPrefix,getBounds:()=>[760,410],getScale:()=>1,maxHeight:338,watchAnchor:true,position:()=>({x:24,y:48}),categoryName:()=> '收藏'});
const a=cfg.SurvivalArchiveTooltip.Create(options(firstParent,'FirstTip')),b=cfg.SurvivalArchiveTooltip.Create(options(secondParent,'SecondTip'));
const item={id:'ex_01',name:'真实字段',description:'攻击力+5',count:2,count_known:1,target:60};
assert(a.Show(item,'ex',firstCard));assert(b.Show({...item,count_known:0},'ex',secondCard));
assert.equal(a.elements.Quantity.text,'2/60');assert.equal(b.elements.Quantity.text,'—/60');assert(b.elements.State.text.includes('状态待同步'));assert.equal(a.elements.Effect.text,item.description);
assert(a.Show({...item,id:'wife_01'},'wife',firstCard));assert(a.elements.State.text.includes('已拥有'),'Owned wife collections share the existing owned-item tooltip semantics');
assert(a.Show({...item,id:'wife_31',description:'初始魔法卡+1',draw_enabled:0,availability_note:'待适配，暂不参与抽取，不消耗玫瑰'},'wife',firstCard));assert.equal(a.elements.Effect.text,'初始魔法卡+1');assert.equal(a.elements.Condition.text,'待适配，暂不参与抽取，不消耗玫瑰');assert(a.elements.Condition.visible);assert.equal(a.elements.State.text,'收藏 · 已拥有','Availability no longer replaces the real ownership state');
assert(a.Show(item,'ex',firstCard));assert.equal(a.elements.Condition.text,'');assert.equal(a.elements.Condition.visible,false,'Switching to ordinary rows clears the adaptation-only note');
const uniquePoints=Object.freeze({id:'lottery_attribute_crystal',name:'属性结晶',description:'英雄全属性+50',count:1,count_known:1,max_owned:1,target:1,duplicate_points:100,duplicate_currency:'shop_points'});
const uniquePointsBefore=JSON.stringify(uniquePoints);
assert(a.Show(uniquePoints,'points',firstCard));
assert(a.elements.State.text.endsWith(' · 已解锁'),'Unique points items use unlock wording at the top');
assert.equal(a.elements.MetricCaption.text,'解锁状态');assert.equal(a.elements.Quantity.text,'已解锁');
assert(a.elements.Condition.text.includes('唯一持有 · 重复获得转化为 100 商城积分'),'Duplicate conversion uses the configured amount and currency');
assert.equal(a.elements.Effect.text,uniquePoints.description);assert.equal(JSON.stringify(uniquePoints),uniquePointsBefore);
for(const [changes,stateText]of[[{count:0},'未解锁'],[{count:7},'已解锁'],[{count:7,count_known:0,unlocked:1},'状态待同步']]){
 const row=Object.freeze({...uniquePoints,...changes}),before=JSON.stringify(row);assert(a.Show(row,'points',firstCard));
 assert(a.elements.State.text.endsWith(' · '+stateText));assert.equal(a.elements.Quantity.text,stateText);assert.equal(a.elements.MetricCaption.text,'解锁状态');
 assert.equal(JSON.stringify(row),before,'Repeated hover leaves historical excess and unknown counts untouched');
}
assert(a.Show({id:'daily_health_gem',name:'生命宝石',description:'墙生命+50',count:3,target:999999},'points',firstCard));
assert(a.elements.State.text.endsWith(' · 已拥有'));assert.equal(a.elements.MetricCaption.text,'拥有数量');assert.equal(a.elements.Quantity.text,'3/999999');
assert(!a.elements.Condition.text.includes('重复获得转化'),'Daily stacks never inherit a previous unique-item conversion note');
assert(a.Show({id:'daily_wealth_talisman',name:'聚财古符',description:'开局木材+50',count:1,target:1},'points',firstCard));
assert(a.elements.State.text.endsWith(' · 已解锁'));assert.equal(a.elements.Quantity.text,'已解锁');
assert(!a.elements.Condition.text.includes('重复获得转化'),'A one-time monthly reward has no invented duplicate payout');
assert(a.Show({...uniquePoints,id:'no_currency',duplicate_currency:undefined},'points',firstCard));
assert(!a.elements.Condition.text.includes('重复获得转化'),'An amount without a declared currency is not a payout promise');
assert(a.Show({...uniquePoints,id:'not_points'},'ex',firstCard));
assert(a.elements.State.text.endsWith(' · 已拥有'));assert.equal(a.elements.MetricCaption.text,'拥有数量');assert.equal(a.elements.Quantity.text,'1/1');
assert(!a.elements.Condition.text.includes('重复获得转化'),'Other archive categories keep their existing quantity semantics');
const mapEffects='每升一级：城墙初始生命+100；城墙每秒回血+5\n本级奖励：伐木效率+1\n人口+1';
const mapLevel=Object.freeze({id:'map_10',name:'地图等级10',description:'累计有效在线时长：90小时\n'+mapEffects,count:4657,target:5400,completed:0,__v10CurrentLevel:9,__v10TargetLevel:10});
const mapSnapshot=JSON.stringify(mapLevel),formatted=[];
cfg.ArchiveHandoff.FormatEffects=description=>{formatted.push(description);return description;};
assert(a.Show(mapLevel,'map_level',firstCard));
assert.equal(formatted.at(-1),mapEffects,'Effect formatting receives rewards without the online requirement');
assert.equal(a.elements.Effect.text,mapEffects,'All map level bonuses remain intact');
assert.equal(a.elements.Condition.text,'解锁条件：\n累计有效在线时长：90小时\n累计有效在线 4657 分钟','The required time appears below the effects separately from current progress');
assert(a.elements.Condition.visible);assert.equal(a.elements.Quantity.text,'LV9/10');
assert(a.Show(mapLevel,'map_level',firstCard));assert.equal(JSON.stringify(mapLevel),mapSnapshot,'Repeated hovers never mutate the shared server snapshot');
assert(a.Show({...mapLevel,description:'累计有效在线时长:120小时\r\n'+mapEffects,target:7200},'map_level',firstCard));
assert.equal(a.elements.Effect.text,mapEffects);assert.equal(a.elements.Condition.text,'解锁条件：\n累计有效在线时长:120小时\n累计有效在线 4657 分钟','Other requirements and CRLF snapshots retain the actual threshold');
assert(a.Show({...mapLevel,description:mapEffects,unlock_condition:'累计有效在线时长：150小时'},'map_level',firstCard));
assert.equal(a.elements.Effect.text,mapEffects);assert(a.elements.Condition.text.startsWith('解锁条件：\n累计有效在线时长：150小时'),'Structured conditions use the same lower section');
delete cfg.ArchiveHandoff.FormatEffects;
assert(a.Show({...item,description:'累计有效在线时长：90小时\n攻击力+5'},'ex',firstCard));assert.equal(a.elements.Effect.text,'累计有效在线时长：90小时\n攻击力+5','Only map level tooltips move the online requirement');assert.equal(a.elements.Condition.text,'');assert.equal(a.elements.Condition.visible,false,'Changing categories clears the map unlock section');
assert(a.Show(item,'ex',firstCard));
assert.notEqual(a.panel,b.panel);assert.notEqual(a.elements.Backing,b.elements.Backing);assert.equal(a.elements.Surface.hittest,true);assert.equal(a.panel.hittest,false,'Shadow bounds do not steal card input');
assert.equal(a.elements.Frame.style.visibility,undefined,'Unskinned callers keep the default CSS frame visibility');assert.equal(a.elements.Backing.Children()[0].Children()[0].style.backgroundImage,'url("file://{images}/custom_game/gw2_tooltip_v1/background.png")','Unskinned callers keep their existing background artwork');
function corners(tip){return ['Backing','Frame'].map(role=>tip.elements[role].Children().filter((_,index)=>[0,2,6,8].includes(index)).map(clip=>({width:clip.style.width,height:clip.style.height,artWidth:clip.Children()[0].style.width,artHeight:clip.Children()[0].style.height})));}
const shortCorners=corners(a),shortHeight=a.Inspect().surfaceHeight;a.Show({...item,description:'长说明\n'.repeat(150)},'ex',firstCard);h.flushFinite();assert.deepEqual(corners(a),shortCorners,'Changing content height never stretches material corners');assert(a.Inspect().surfaceHeight>shortHeight,'Long content actually changes the material height');assert.equal(a.Inspect().nineSlices.Backing.count,9);assert.equal(a.Inspect().nineSlices.Frame.count,9);
a.QueueHide();const surfaceAt=a.elements.Surface.GetPositionWithinWindow();h.setCursor(surfaceAt.x+10,surfaceAt.y+10);a.elements.Surface.events.onmouseover();h.flushFinite();assert(!a.IsVisible(),'Entering the surface hides immediately instead of cancelling card leave');assert(b.IsVisible());
assert.equal(a.Show(item,'ex',firstCard),false,'The source cannot reopen while the cursor remains in the dismissed area');assert.equal(b.Show(item,'ex',secondCard),false,'The same shared policy blocks another tooltip under the dismissed area');h.setCursor(1000,900);h.flushFinite();assert(a.Show(item,'ex',firstCard),'Leaving both source and dismissed area permits a later hover');
a.QueueHide();h.flushFinite();assert(!a.IsVisible());assert(b.IsVisible(),'One owner hiding never affects another owner');
a.Show(item,'ex',firstCard);firstCard.style.position='101px 100px 0px';h.flushFinite();assert(!a.IsVisible(),'Moving the anchor invalidates the floating description');assert(b.IsVisible());
const retiredSurface=a.elements.Surface,queued=h.scheduled.slice();a.Dispose();a.Dispose();assert(!a.panel.IsValid());assert.doesNotThrow(()=>{retiredSurface.events.onmouseover();retiredSurface.events.onmouseout();queued.filter(job=>!job.cancelled).forEach(job=>job.fn());});assert(!a.IsVisible());assert(b.IsVisible(),'Disposing one instance preserves its sibling');
b.Hide();h.flushFinite();assert(!b.IsVisible());b.Dispose();assert.equal(h.sent.length,0,'Tooltip rendering never emits a game event');
const scroll=cfg.SurvivalArchiveTooltip.Create(options(firstParent,'ScrollableTip'));
// Model native fit-children measurement of the actual populated content body.
Object.defineProperty(scroll.elements.Body,'actuallayoutheight',{get(){return this.Children().filter(c=>c.visible!==false).reduce((sum,c)=>sum+c.actuallayoutheight+(parseFloat(c.style.marginBottom)||0),0);}});
h.setCursor(1000,900);assert(scroll.Show({...item,description:'完整长说明\n'.repeat(100)},'ex',firstCard));h.flushFinite();
assert(scroll.elements.Body.actuallayoutheight>scroll.elements.Viewport.actuallayoutheight,'The real content exceeds the bounded scroll viewport');
const scrollCreated=h.counts.created,scrollAt=scroll.elements.Surface.GetPositionWithinWindow();
scroll.QueueHide();h.setCursor(scrollAt.x+10,scrollAt.y+10);scroll.elements.Surface.events.onmouseover();h.flushFinite();
assert(scroll.IsVisible(),'A long tooltip remains open when crossing the card gap into its existing scroll viewport');
assert.equal(h.counts.created,scrollCreated,'Hovering and scrolling never rebuilds content or material panels');
scroll.elements.Surface.events.onmouseout();h.flushFinite();assert(scroll.IsVisible(),'A delayed child leave cannot hide while still inside the surface');
h.setCursor(1000,900);scroll.elements.Surface.events.onmouseout();h.flushFinite();assert(!scroll.IsVisible(),'Leaving both card and scroll surface hides after the grace period');
assert(scroll.Show(item,'ex',firstCard));h.flushFinite();assert(scroll.elements.Body.actuallayoutheight<=scroll.elements.Viewport.actuallayoutheight+1);
const passiveAt=scroll.elements.Surface.GetPositionWithinWindow();h.setCursor(passiveAt.x+10,passiveAt.y+10);scroll.elements.Surface.events.onmouseover();assert(!scroll.IsVisible(),'Short tooltips retain passive immediate dismissal');
scroll.Dispose();assert.equal(cfg.SurvivalTooltipDismiss.Inspect().owners,0);assert.equal(h.sent.length,0);
const nativeSkin=Object.freeze({
 backing:Object.freeze({file:'s2r://panorama/images/hud/reborn/bg_tooltip_psd.vtex',size:Object.freeze([500,452]),nine_slice_ltrb:Object.freeze([12,12,12,12]),edge_ltrb:Object.freeze([6,6,6,6]),fill:true}),
 frame:Object.freeze({file:'s2r://panorama/images/events/dark_carnival/overworld/inner_panel_border_png.vtex',size:Object.freeze([400,400]),nine_slice_ltrb:Object.freeze([20,20,20,20]),edge_ltrb:Object.freeze([8,8,8,8]),fill:false})
});
const nativeSkinBefore=JSON.stringify(nativeSkin),native=cfg.SurvivalArchiveTooltip.Create({...options(firstParent,'NativeSkinTip'),compact:true,skin:nativeSkin});
h.setCursor(1000,900);assert(native.Show(item,'ex',firstCard));
assert.equal(native.elements.Frame.style.visibility,'visible','An explicit frame skin overrides the default collapsed frame');
for(const [role,asset] of [['Backing',nativeSkin.backing],['Frame',nativeSkin.frame]]){
 const clips=native.elements[role].Children();assert.equal(clips.length,9);assert.equal(native.Inspect().nineSlices[role].count,9);
 for(const corner of [0,2,6,8]){assert.equal(clips[corner].style.width,asset.edge_ltrb[0]+'px');assert.equal(clips[corner].style.height,asset.edge_ltrb[1]+'px');}
 assert.equal(clips[0].Children()[0].style.backgroundImage,'url("'+asset.file+'")','The caller supplies the native material without changing source assets');
 assert.equal(parseFloat(clips[0].Children()[0].style.width),asset.size[0]*asset.edge_ltrb[0]/asset.nine_slice_ltrb[0],'Source cuts and fixed display corner sizes remain independent');
 const center=clips[4].Children()[0];
 if(asset.fill===false){assert.equal(center.visible,false);assert.equal(center.style.backgroundImage,'none','A border-only frame cannot cover the underlying tooltip background');}
 else assert.notEqual(center.style.backgroundImage,'none','A solid backing retains its center artwork');
}
const nativeCorners=corners(native),nativeHeight=native.Inspect().surfaceHeight;
assert(native.Show({...item,description:'原生材质长说明\n'.repeat(150)},'ex',firstCard));h.flushFinite();
assert(native.Inspect().surfaceHeight>nativeHeight);assert.deepEqual(corners(native),nativeCorners,'Fixed native corners survive tooltip height changes');assert.equal(JSON.stringify(nativeSkin),nativeSkinBefore,'Tooltip rendering leaves caller-owned skin definitions untouched');
native.Dispose();assert.equal(cfg.SurvivalTooltipDismiss.Inspect().owners,0);assert.equal(h.sent.length,0);
console.log('ARCHIVE_SHARED_TOOLTIP_PASS: isolated owners, real quantity semantics, enter-dismiss, cross-tooltip reentry guard, anchored movement, stable material corners, optional native nine-slice skins with transparent frame centers, disposal guards');
