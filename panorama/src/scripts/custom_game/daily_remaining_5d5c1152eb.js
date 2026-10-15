(function(){
"use strict";
// Independent login calendar. All rewards and eligibility come from the existing
// authoritative daily snapshot; the shell never grants or unlocks an entitlement.
var cfg=GameUI.CustomUIConfig(),U=cfg.SurvivalUI,RH=cfg.RemainingHandoff,P=cfg.DailyGW2Data||{},size=P.canvas||[1200,900];
var data=null,waiting=null,errorText="",buying=false,sequence=0,active=true,life=U.Lifecycle(),viewLife=U.Lifecycle(),fetching=false,fetchSerial=0;
var dailyRoot=$.GetContextPanel(),view=null,shell=null,canvas=null,tipPanel=null,tipFrame=null,tipBody=null,tipTitle=null,tipViewport=null,tipAnchor=null,tipEpoch=0,tipHideJob=null,tipDismiss=null,moved=[];
var cardSignature="",specialSignature="",statusText="",scale=1;
var rewardFX=null;
function valid(node){return node&&(!node.IsValid||node.IsValid());}
function p(id){return valid(dailyRoot)?dailyRoot.FindChildTraverse(id):null;}
function viewValid(){return valid(p("DailyWindow"));}
if(!viewValid()){active=false;return;}
if(cfg.SurvivalDaily&&cfg.SurvivalDaily.Dispose)cfg.SurvivalDaily.Dispose();
function stopIfInvalid(){if(!active)return true;if(viewValid())return false;active=false;if(rewardFX)rewardFX.Dispose();life.Dispose();viewLife.Dispose();if(view)view.Dispose();return true;}
function array(v){return Array.isArray(v)?v:Object.keys(v||{}).sort(function(a,b){return Number(a)-Number(b);}).map(function(k){return v[k];});}
function style(node,values){Object.keys(values).forEach(function(key){if(node.style[key]!==values[key])node.style[key]=values[key];});}
function rect(node,x,y,w,h){style(node,{position:x+"px "+y+"px 0px",width:w+"px",height:h+"px",margin:"0px",padding:"0px",horizontalAlign:"left",verticalAlign:"top"});}
function make(type,parent,id,cls){var node=$.CreatePanel(type,parent,id||"");if(cls)node.AddClass(cls);return node;}
function skin(node,key){var asset=P.assets&&P.assets[key];if(asset)style(node,{backgroundImage:'url("'+asset.file+'")',backgroundColor:"transparent",backgroundSize:"100% 100%",backgroundRepeat:"no-repeat",border:"0px"});}
function component(parent,key,x,y,w,h,id){var node=make("Panel",parent,id,"DailyGW2Art");rect(node,x,y,w,h);node.hittest=false;node.hittestchildren=false;skin(node,key);return node;}
function label(parent,text,x,y,w,h,font,color,id){var node=make("Label",parent,id,"DailyGW2Text");node.text=String(text===undefined?"":text);node.hittest=false;rect(node,x,y,w,h);style(node,{fontSize:font+"px",color:color||"#f0efeb",fontFamily:'"Source Han Sans SC"',whiteSpace:"nowrap",textOverflow:"ellipsis"});return node;}
function move(id,parent){var node=p(id);if(!valid(node))return null;moved.push({node:node,parent:node.GetParent()});node.SetParent(parent);node.style.visibility="visible";return node;}
function escapedLines(value){return String(value||"").replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/\r?\n/g,"<br>");}
function cancelTooltipHide(){tipEpoch++;if(tipHideJob!==null&&$.CancelScheduled)$.CancelScheduled(tipHideJob);tipHideJob=null;}
function tooltipRect(node){var at=node.GetPositionWithinWindow();return {x:at.x,y:at.y,width:node.actuallayoutwidth*scale,height:node.actuallayoutheight*scale};}
function hideTooltip(){cancelTooltipHide();tipAnchor=null;if(valid(tipPanel))tipPanel.visible=false;if(tipDismiss)tipDismiss.Hidden();if(valid(p("DailyTooltip")))p("DailyTooltip").AddClass("ArchiveHidden");}
function leaveTooltip(){cancelTooltipHide();var epoch=tipEpoch;tipHideJob=$.Schedule(.18,function(){tipHideJob=null;if(epoch===tipEpoch)hideTooltip();});}
function fitTooltip(epoch){
 if(!active||epoch!==tipEpoch||!valid(tipAnchor)||!valid(tipPanel)||!shell.IsOpen())return;
 var origin=canvas.GetPositionWithinWindow(),at=tipAnchor.GetPositionWithinWindow(),sx=(canvas.actualuiscale_x||1)*scale,sy=(canvas.actualuiscale_y||1)*scale;
 var measured=(tipTitle.actuallayoutheight||32)+(tipBody.actuallayoutheight||100),height=Math.max(150,Math.min(570,measured+42));
 var x=(at.x-origin.x)/sx+110,y=(at.y-origin.y)/sy;
 if(x+350>1180)x=(at.x-origin.x)/sx-362;x=Math.max(20,Math.min(830,x));y=Math.max(210,Math.min(855-height,y));
 rect(tipPanel,x,y,350,height);rect(tipFrame,0,0,350,height);rect(tipViewport,17,16,316,height-32);
}
function tip(anchor,title,body){
 anchor.hittest=true;anchor.SetPanelEvent("onmouseover",function(){
  if(!active||!viewValid()||!shell.IsOpen()||!p("DailyRulesText").BHasClass("ArchiveHidden")){hideTooltip();return;}
  if(!tipDismiss.CanShow(anchor))return;
  hideTooltip();tipAnchor=anchor;tipTitle.text=String(title||"奖励说明");tipBody.text=String(body||"奖励说明待同步");
  p("DailyTooltipName").text=tipTitle.text;p("DailyTooltipEffect").text=tipBody.text;tipPanel.visible=true;
  var epoch=tipEpoch;fitTooltip(epoch);tipDismiss.Shown(anchor);[0,.05,.15,.35].forEach(function(delay){viewLife.Later(delay,function(){fitTooltip(epoch);});});
 });anchor.SetPanelEvent("onmouseout",leaveTooltip);
}
function close(){
 if(rewardFX)rewardFX.Clear();if(waiting)waiting.present=false;
 if(!active)return;hideTooltip();viewLife.Cancel();fetching=false;fetchSerial++;if(view)view.Close();
 if(valid(p("DailyWindow")))p("DailyWindow").AddClass("ArchiveHidden");if(valid(p("DailyScrim")))p("DailyScrim").AddClass("ArchiveHidden");
 if(valid(p("DailyRulesText")))p("DailyRulesText").AddClass("ArchiveHidden");$.DispatchEvent("DOTAHideTextTooltip");
}
function build(){
 var win=p("DailyWindow");win.AddClass("DailyGW2Page");win.RemoveClass("DailyV10Page");win.RemoveClass("DailyPurple");
 shell=U.ModalShell.Adopt({id:"daily_rewards",panel:win,root:dailyRoot,scrim:p("DailyScrim"),width:size[0],height:size[1],fit:{reference:size.slice()},onClose:close});
 style(win,{width:size[0]+"px",height:size[1]+"px",flowChildren:"none",padding:"0px",margin:"0px",backgroundImage:"none",backgroundColor:"transparent",border:"0px",boxShadow:"none",overflow:"noclip"});
 canvas=make("Panel",win,"DailyGW2Canvas","DailyGW2Canvas");rect(canvas,0,0,size[0],size[1]);canvas.hittest=false;canvas.hittestchildren=true;
 component(canvas,"window_background",18,168,1164,703,"DailyGW2Background");component(canvas,"crown",70,0,1060,182,"DailyGW2Crown");
 component(canvas,"title_brush",18,173,1164,61,"DailyGW2TitleBrush");label(canvas,"每日登录奖励",67,181,850,46,34,"#fff7df","DailyGW2Title");
 var closeButton=make("Button",canvas,"DailyGW2Close","DailyGW2Button");rect(closeButton,1121,186,31,31);skin(closeButton,"close");if(!(P.assets&&P.assets.close))label(closeButton,"×",0,-5,31,36,31,"#eee9dc");
 closeButton.SetPanelEvent("onactivate",function(){if(active&&valid(closeButton)){if(shell.RequestClose)shell.RequestClose("button");else close();}});
 component(canvas,"divider",879,252,3,485,"DailyGW2Divider");
 ["DailyFrame","DailyHeader","DailyClaimPage","DailyPassPage","DailyRuleLine","DailyBack","DailyTooltip"].forEach(function(id){p(id).visible=false;});
 ["DailyCards","DailySubtitle","DailyCount","DailyPassStatus","DailySpecials","PassValidity","PassPrice","PassPurchase","DailyRules","DailyMakeup","DailyClaim","DailyNotice","DailyRulesText"].forEach(function(id){move(id,canvas);});
 rect(p("DailySubtitle"),66,246,760,32);style(p("DailySubtitle"),{fontSize:"23px",color:"#f2eee0",fontWeight:"normal"});
 rect(p("DailyCount"),66,740,764,24);style(p("DailyCount"),{fontSize:"18px",color:"#c5beb0",textAlign:"left"});
 rect(p("DailyCards"),64,292,784,436);style(p("DailyCards"),{flowChildren:"none",overflow:"clip"});
 rect(p("DailyPassStatus"),919,246,233,32);style(p("DailyPassStatus"),{backgroundImage:"none",backgroundColor:"transparent",border:"0px"});p("DailyPassStatus").hittestchildren=false;
 rect(p("DailyPassStatusText"),0,0,233,32);style(p("DailyPassStatusText"),{fontSize:"22px",color:"#a9d7ed",textAlign:"center",margin:"0px",marginLeft:"0px"});
 rect(p("DailySpecials"),918,292,235,330);style(p("DailySpecials"),{flowChildren:"none",overflow:"squish scroll"});
 var passInfo=component(canvas,"premium_frame_locked",924,628,223,100,"DailyGW2PassInfo");passInfo.AddClass("DailyGW2PassInfo");
 rect(p("PassValidity"),932,640,207,27);style(p("PassValidity"),{fontSize:"17px",color:"#d0e5ef",textAlign:"center",margin:"0px",marginBottom:"0px"});
 rect(p("PassPrice"),932,671,207,40);style(p("PassPrice"),{fontSize:"14px",color:"#9eabb5",textAlign:"center",whiteSpace:"normal",margin:"0px",marginBottom:"0px"});
 rect(p("PassPurchase"),922,746,228,43);rect(p("DailyRules"),66,770,150,40);rect(p("DailyMakeup"),236,770,240,40);rect(p("DailyClaim"),594,765,248,46);
 rect(p("DailyNotice"),69,818,1080,22);style(p("DailyNotice"),{fontSize:"16px",color:"#d4c5a7",textAlign:"center",marginTop:"0px",whiteSpace:"nowrap",textOverflow:"ellipsis"});
 var rules=p("DailyRulesText");rect(rules,175,255,850,490);style(rules,{flowChildren:"down",overflow:"squish scroll",backgroundColor:"#121518fa",backgroundImage:"none",border:"1px solid #777466",padding:"24px",zIndex:"120"});rules.hittest=true;rules.hittestchildren=true;rules.AddClass("ArchiveHidden");
 style(p("DailyRulesBody"),{width:"790px",height:"fit-children",fontSize:"20px",color:"#eee6d2",whiteSpace:"normal",textOverflow:"clip",lineHeight:"28px"});p("DailyRulesBody").html=true;
 var rulesClose=make("Button",rules,"DailyGW2RulesClose","DailyGW2Button");rect(rulesClose,0,0,750,34);label(rulesClose,"关闭奖励说明",0,0,750,34,18,"#e3c68a");rulesClose.SetPanelEvent("onactivate",function(){if(active)p("DailyRulesText").AddClass("ArchiveHidden");});
 tipPanel=make("Panel",canvas,"DailyGW2Tooltip","DailyGW2Tooltip");tipPanel.visible=false;tipPanel.hittest=true;tipPanel.hittestchildren=true;skin(tipPanel,"tooltip_background");
 tipDismiss=cfg.SurvivalTooltipDismiss.Create({panel:tipPanel,getRect:tooltipRect,hide:hideTooltip,isAlive:function(){return active&&viewValid();},isVisible:function(){return valid(tipPanel)&&tipPanel.visible&&shell.IsOpen();}});tipPanel.SetPanelEvent("onmouseout",leaveTooltip);
 tipFrame=component(tipPanel,"tooltip_frame",0,0,350,180,"DailyGW2TooltipFrame");
 tipViewport=make("Panel",tipPanel,"DailyGW2TooltipViewport","DailyGW2TooltipViewport");rect(tipViewport,17,16,316,230);
 tipTitle=label(tipViewport,"",0,0,316,32,23,"#f0d899","DailyGW2TooltipTitle");style(tipTitle,{height:"fit-children",whiteSpace:"normal",marginBottom:"10px"});
 tipBody=label(tipViewport,"",0,0,316,180,18,"#e1dfd7","DailyGW2TooltipBody");style(tipBody,{height:"fit-children",whiteSpace:"normal",textOverflow:"clip"});
 view=cfg.SurvivalDailyGW2={canvas:canvas,shell:shell,Open:function(){shell.Open();canvas.visible=true;scale=Number(U.Fit(win,dailyRoot,size[0],size[1],{reference:size.slice()}))||1;},Close:function(){shell.Close();if(valid(canvas))canvas.visible=false;},IsOpen:function(){return shell.IsOpen();},Dispose:function(){if(tipDismiss)tipDismiss.Dispose();shell.Dispose();moved.forEach(function(e){if(valid(e.node)&&valid(e.parent))e.node.SetParent(e.parent);});moved=[];if(valid(canvas))canvas.DeleteAsync(0);if(valid(win))win.RemoveClass("DailyGW2Page");}};
}
build();
if(U.RewardFX)rewardFX=U.RewardFX.Create(canvas,{channel:"daily",getScale:function(){return scale;}});
p("DailyClose").SetPanelEvent("onactivate",function(){if(active)close();});
U.State.Bind(p("DailyRules"),function(){if(!active||!viewValid())return;hideTooltip();p("DailyRulesText").ToggleClass("ArchiveHidden");});
U.State.Bind(p("DailyPassStatus"),function(){if(!active||!viewValid())return;buying=true;p("DailyGW2PassInfo").AddClass("DailyGW2PassFocus");});
U.ActionButton.Adopt(p("DailyClaim"),{action:function(){if(!active)return;if(!data){request();return;}claim(data.today);}});
U.ActionButton.Adopt(p("DailyMakeup"),{action:function(){if(active)claim(array(data&&data.missed)[0]);}});
U.ActionButton.Adopt(p("PassPurchase"),{action:function(){if(!active||!data||Number(data.purchase_enabled)!==1||waiting||Number(data.pending)===1)return;U.State.Set(p("PassPurchase"),{enabled:false});GameEvents.SendCustomGameEventToServer("survival_pass_purchase",{});}});
function setStatus(text){statusText=String(text||"");if(valid(p("DailyNotice")))p("DailyNotice").text=statusText;}
function paintActions(){
 ["DailyClaim","DailyMakeup","PassPurchase","DailyRules"].forEach(function(id){
  var button=p(id),disabled=button.enabled===false;button.AddClass("DailyGW2Button");skin(button,"button");style(button,{opacity:disabled?".48":"1",backgroundColor:P.assets&&P.assets.button?"transparent":"#24292c",border:"0px",flowChildren:"none"});
  if(!button.__dailyGW2Hover||!valid(button.__dailyGW2Hover)){var before=button.Children()[0],overlay=component(button,"button_hover",0,0,parseFloat(button.style.width),parseFloat(button.style.height));overlay.AddClass("DailyGW2HoverArt");if(before)button.MoveChildBefore(overlay,before);button.__dailyGW2Hover=overlay;}
  button.hittestchildren=false;button.Children().forEach(function(node){if(node.paneltype==="Label"){rect(node,0,0,parseFloat(button.style.width),parseFloat(button.style.height));style(node,{fontSize:id==="DailyClaim"?"22px":"18px",color:P.assets&&P.assets.button?(disabled?"#5f5c52":"#302d26"):(disabled?"#999b98":"#efe7d3"),textAlign:"center",verticalAlign:"center",marginTop:"0px",marginLeft:"0px",paddingTop:"7px",whiteSpace:"nowrap",textOverflow:"shrink"});}});
 });
}
function request(){
 if(stopIfInvalid()||fetching)return;fetching=true;var serial=++fetchSerial;if(!data){errorText="";render();}
 GameEvents.SendCustomGameEventToServer("survival_daily_request",{});
 if(shell.IsOpen())viewLife.Later(8,function(){if(!active||serial!==fetchSerial||!fetching)return;fetching=false;if(!data){errorText="读取奖励超时，请重试";render();}});else fetching=false;
}
function artId(item){return item.art_id&&RH.DailyResourceInfo(item.art_id).runtime?item.art_id:"daily.item.crystals";}
function reward(parent,item,x,y,w,h,cls){
 var slot=make("Panel",parent,"",cls||"DailyGW2Reward");rect(slot,x,y,w,h);slot.hittest=true;slot.hittestchildren=false;
 var premium=cls==="DailyGW2PassReward",artSize=premium?68:54;
 var art=(cfg.SurvivalItemArt&&cfg.SurvivalItemArt.Create(slot,item,"DailyGW2ItemArt"))||RH.DailyImage(slot,artId(item),"DailyGW2ItemArt");rect(art,Math.max(0,(w-artSize)/2),0,Math.min(w,artSize),premium?64:49);art.hittest=false;if(art.SetScaling)art.SetScaling("stretch-to-fit-preserve-aspect");
 var known=item.count!==undefined&&item.count!==null&&String(item.count).trim()!==""&&isFinite(Number(item.count))&&Number(item.count)>=0;
 if(!premium){var name=label(slot,item.name||"奖励",0,50,w,18,w<55?11:13,"#dddcd4");style(name,{textAlign:"center",textOverflow:"shrink"});}
 if(known){var count=label(slot,String(item.count),Math.max(0,w-31),premium?48:32,29,18,14,"#fff3c8");style(count,{textAlign:"right",textShadow:"#000000 0px 1px 2px 2.0"});}
 tip(slot,item.name,(item.description||"奖励说明待同步")+(known?"\n数量："+item.count:""));return slot;
}
function stateText(status){return {claimed:"已领取",claimable:"今日可领",not_open:"尚未开放",requires_pass:"购买战令后解锁",unconfigured:"暂无奖励配置"}[status]||"等待同步";}
function calendar(){return data?array(data.calendar28||data.calendar||data.cycle):[];}
function renderCards(){
 var days=calendar(),signature=JSON.stringify([days,data&&data.calendar_start_count]);if(signature===cardSignature&&p("DailyCards").GetChildCount()===(days.length||28))return;
 cardSignature=signature;hideTooltip();p("DailyCards").RemoveAndDeleteChildren();
 var shown=days.length?days:Array.apply(null,new Array(28)).map(function(_,i){return {day:i+1,rewards:[],status:"loading"};});
 shown.slice(0,28).forEach(function(day,i){
  var card=make("Panel",p("DailyCards"),"DailyGW2Day_"+(i+1),"DailyGW2Day");rect(card,(i%7)*112,Math.floor(i/7)*112,100,100);card.hittest=true;card.hittestchildren=true;
  var status=day.status||"not_open",today=Number(day.is_today)===1;card.SetHasClass("DailyGW2Today",today);card.SetHasClass("DailyGW2Claimed",status==="claimed");card.SetHasClass("DailyGW2Future",status==="not_open");
  skin(card,status==="claimed"?"reward_frame_claimed":today?"reward_frame_today":"reward_frame");
  var hoverArt=component(card,"reward_frame_hover",0,0,100,100);hoverArt.AddClass("DailyGW2HoverArt");
  label(card,String(day.day||i+1),7,3,61,19,16,today?"#ffdc84":"#eeece4");
  var items=array(day.rewards),width=items.length>1?43:80,start=items.length>1?7:10;
  if(items.length>2){width=80;start=10;}
  items.slice(0,2).forEach(function(item,j){reward(card,item,start+j*(width+1),23,width,69);});
  if(items.length>2)label(card,"+"+(items.length-2)+"项",58,3,36,18,11,"#eedbab");
  if(status==="claimed")component(card,"check",71,5,22,22);
  else if(today)label(card,"今日",63,4,31,18,12,"#f6d084");
  var summary=items.map(function(item){return item.name+(item.count!==undefined?" ×"+item.count:"")+"\n"+(item.description||"");}).join("\n\n");
  tip(card,"第"+(day.day||i+1)+"天 · "+stateText(status),summary||"正在读取该日奖励");
 });
}
function renderSpecials(){
 var rows=array(data&&data.specials),signature=JSON.stringify([rows,data&&data.has_pass,data&&data.count]);if(signature===specialSignature&&p("DailySpecials").GetChildCount()===rows.length)return;specialSignature=signature;p("DailySpecials").RemoveAndDeleteChildren();
 rows.forEach(function(item,i){
  var owned=Number(item.owned)>0,pass=Number(data.has_pass)===1,card=make("Panel",p("DailySpecials"),"DailyGW2Special_"+item.id,"DailyGW2Special");rect(card,7,i*112,223,100);
  var frame=component(card,!pass&&!owned?"premium_frame_locked":"premium_frame",0,0,100,100);frame.AddClass("DailyGW2SpecialFrame");
  card.SetHasClass("DailyGW2Locked",!pass&&!owned);label(card,"累计 "+item.day+" 次",111,4,112,23,16,"#c3e7f6");
  var itemWithCount={id:item.id,name:item.name,description:item.description,art_id:item.art_id,count:1},slot=reward(frame,itemWithCount,10,22,80,69,"DailyGW2PassReward");
  var name=label(card,item.name,111,30,112,38,16,"#e5f4f8");style(name,{whiteSpace:"normal"});
  var status=owned?"已获得":!pass?"购买战令后解锁":Number(data.count)>=Number(item.day)?"下次签到时发放":"累计签到 "+item.day+" 次";
  var state=label(card,status,111,70,112,30,13,owned?"#c4ddb4":"#a7c6d6");style(state,{whiteSpace:"normal"});
  if(owned)component(frame,"check",73,5,20,20);else if(!pass)component(frame,"lock",73,5,20,20);
  var details=(item.description||"奖励说明待同步")+"\n领取条件：累计签到"+item.day+"次\n领取状态："+status+"\n战令奖励随符合条件的签到自动发放。";
  tip(card,item.name,details);tip(slot,item.name,details);
 });
}
function availability(){var base=data&&data.ordinary_status==="claimable",bonus=data&&data.premium&&data.premium.status==="claimable";return {enabled:!!(base||bonus),text:base?"领取今日奖励":bonus?"领取战令奖励":data&&data.ordinary_status==="claimed"?"今日已领取":"尚未开放"};}
function render(){
 if(stopIfInvalid())return;RH=cfg.RemainingHandoff;var ready=availability(),busy=!!waiting||!!data&&Number(data.pending)===1;
 p("DailyEntry").SetHasClass("DailyCanClaim",ready.enabled);p("DailyEntry").SetHasClass("DailyClaimed",!!data&&!ready.enabled&&data.ordinary_status==="claimed");if(!shell.IsOpen())return;
 p("DailyGW2PassInfo").SetHasClass("DailyGW2PassFocus",buying);p("DailyCards").visible=true;p("DailySpecials").visible=true;p("PassPurchase").visible=true;p("DailyRules").visible=true;p("DailyClaim").visible=true;
 if(!data){
  p("DailySubtitle").text="每日登录，累积成长";p("DailyCount").text="";p("DailyPassStatusText").text="战令奖励";p("PassValidity").text="资格待同步";p("PassPrice").text="";p("PassPurchaseText").text="正在读取…";p("DailyClaimText").text=fetching?"加载中…":"重试加载";
  U.State.Set(p("DailyClaim"),{enabled:!fetching,busy:fetching});U.State.Set(p("DailyMakeup"),{enabled:false});U.State.Set(p("PassPurchase"),{enabled:false});p("DailyMakeup").visible=false;
  renderCards();p("DailySpecials").RemoveAndDeleteChildren();specialSignature="";setStatus(errorText||"正在读取每日奖励…");paintActions();return;
 }
 var pass=Number(data.has_pass)===1;U.State.Set(p("DailyPassStatus"),{enabled:true});p("DailyPassStatusText").text=pass?"战令奖励 · 已解锁":"战令奖励";
 p("DailySubtitle").text="免费登录奖励";p("DailyCount").text="累计签到 "+data.count+" 次"+(data.calendar_current_day?" · 本轮第 "+data.calendar_current_day+" / 28 天":"");
 p("DailyClaimText").text=busy?"领取中…":errorText&&ready.enabled?"重试领取":ready.text;U.State.Set(p("DailyClaim"),{enabled:ready.enabled&&!busy,busy:busy});
 U.State.Set(p("DailyMakeup"),{enabled:pass&&array(data.missed).length>0&&!busy});p("DailyMakeup").visible=pass&&array(data.missed).length>0;
 p("PassValidity").text=pass?"战令已解锁":"购买战令后解锁";
 var expiry=Number(data.expires_at),until=expiry>0?new Date((expiry+8*3600)*1000):null;p("PassPrice").text=(data.duration_days?data.duration_days+"天 · ":"")+(data.price||"价格待配置")+(pass?(until?" · 有效至 "+until.getUTCFullYear()+"/"+(until.getUTCMonth()+1)+"/"+until.getUTCDate():" · 权益已生效"):"");
 p("PassPurchaseText").text=(pass?"续费":"开通")+(data.price||"月卡");U.State.Set(p("PassPurchase"),{enabled:Number(data.purchase_enabled)===1&&!busy});
 p("DailyRulesBody").text=escapedLines((data.rule_text||"奖励以服务端配置为准")+"\n补签范围：最近"+(data.makeup_days||30)+"天，需有效战令。\n"+array(data.specials).map(function(s){return "累计"+s.day+"次："+s.name+"；"+s.description;}).join("\n"));
 renderCards();renderSpecials();paintActions();setStatus(errorText||(busy?"正在等待服务端保存，请勿重复提交。":data.calendar28?"每日零点刷新，断签不重置累计进度。":"28日奖励视图待同步，当前展示已配置奖励。"));
}
function claim(target){
 if(!active||!data||waiting||Number(data.pending)===1||target===undefined)return;
 var slot=Number(data.calendar_current_day)||1,day=calendar()[slot-1],bonus=Number(target)===Number(data.today)&&data.ordinary_status==="claimed";
 waiting={target:Number(target),day:Number(data.today),period:String(data.period_id),count:Number(data.count),
  ordinary:data.ordinary_status,premium:data.premium&&data.premium.status,slot:slot,calendarStart:Number(data.calendar_start_count)||0,
  text:bonus?"月卡奖励":array(day&&day.rewards).map(function(item){return item.name;}).join("、"),present:shell.IsOpen(),bonus:bonus};
 errorText="";render();GameEvents.SendCustomGameEventToServer("survival_daily_claim",{target_day:Number(target)});
}
function confirmedClaim(next,intent){
 var result=next.claim_result,matching=result&&Number(result.target_day)===intent.target;
 if(Number(next.pending)===1||(matching&&(result.pending===true||Number(result.pending)===1)))return false;
 if(matching)return result.ok===true||Number(result.ok)===1;
 return Number(next.count)>intent.count||(intent.target===Number(next.today)&&(
  (intent.ordinary==="claimable"&&next.ordinary_status==="claimed")||
  (intent.premium==="claimable"&&next.premium&&next.premium.status==="claimed")));
}
function showClaim(intent){
 if(!rewardFX||!intent.present||!shell.IsOpen())return;
 var samePage=(Number(data.calendar_start_count)||0)===intent.calendarStart;
 rewardFX.Play({key:intent.period+":"+intent.target+":"+intent.count+":"+intent.ordinary+":"+intent.premium,
  anchor:!intent.bonus&&samePage?p("DailyGW2Day_"+intent.slot):p("DailyClaim"),title:"领取成功",text:intent.text||"奖励已领取",tone:"gold"});
}
life.Subscribe("survival_daily_snapshot",function(next){
 if(!active)return;fetching=false;fetchSerial++;if(!(next.ok===true||Number(next.ok)===1)){errorText=next.error||"正在读取档案";render();return;}
 if(Number(next.sequence)>0&&Number(next.sequence)<=sequence)return;if(data&&Number(next.today)<Number(data.today))return;sequence=Number(next.sequence)||sequence;
 var result=next.claim_result,claimed=null;if(waiting){if(Number(next.today)!==waiting.day||String(next.period_id)!==waiting.period){waiting=null;errorText="";}else if(confirmedClaim(next,waiting)){claimed=waiting;waiting=null;errorText="";}else if(result&&Number(result.target_day)===waiting.target&&Number(next.pending)!==1&&!(result.pending===true||Number(result.pending)===1)){waiting=null;errorText=result.error||"领取失败，请重试";}}
 data=next;if(!waiting&&!(result&&!(result.ok===true||Number(result.ok)===1)))errorText="";render();if(claimed)showClaim(claimed);
});
function poll(){if(stopIfInvalid()||!shell.IsOpen())return;request();viewLife.Later(3,poll);}
cfg.SurvivalDaily={Open:function(pass){
 if(!active||!viewValid())return;hideTooltip();buying=pass===true;p("DailyWindow").RemoveClass("ArchiveHidden");p("DailyScrim").RemoveClass("ArchiveHidden");view.Open();viewLife.Cancel();fetching=false;render();request();viewLife.Later(3,poll);
},Close:close,Inspect:function(){var cards=p("DailyCards");return {open:active&&viewValid()&&shell.IsOpen(),layout:"daily_gw2",pass:buying,waiting:!!waiting,fetching:fetching,today:data&&data.today,count:data&&data.count,hasPass:!!data&&Number(data.has_pass)===1,calendarDay:data&&data.calendar_current_day,days:valid(cards)?cards.GetChildCount():0,status:statusText};},
Dispose:function(){if(!active)return;close();active=false;if(rewardFX)rewardFX.Dispose();viewLife.Dispose();life.Dispose();view.Dispose();}};
life.Later(1,request);
})();
