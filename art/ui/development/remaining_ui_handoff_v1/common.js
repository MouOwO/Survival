(function(){
    "use strict";
    var cfg=GameUI.CustomUIConfig(),U=cfg.SurvivalUI,A=/*ASSETS*/,R={};
    function valid(p){return p&&(!p.IsValid||p.IsValid());}
    function panel(parent,cls){var p=$.CreatePanel("Panel",parent,"");p.AddClass(cls);p.hittest=false;p.hittestchildren=false;return p;}
    function image(parent,key,cls){var p=$.CreatePanel("Image",parent,"");p.SetImage(A[key]);cls.split(/\s+/).forEach(function(c){p.AddClass(c);});p.hittest=false;p.hittestchildren=false;return p;}
    function label(parent,text,cls){var p=$.CreatePanel("Label",parent,"");p.text=String(text);cls.split(/\s+/).forEach(function(c){p.AddClass(c);});p.hittest=false;return p;}
    function box(p,x,y,w,h){p.style.position=x+"px "+y+"px 0px";p.style.width=w+"px";p.style.height=h+"px";}
    R.Window=function(p,header,close){
        p.AddClass("RHWindow");p.style.backgroundColor="transparent";p.style.backgroundImage="none";p.style.border="0px solid transparent";p.style.boxShadow="none";
        var frame=panel(p,"RHFrame");p._rhFrame=frame;
        ["top_left","top","top_right","left","center","right","bottom_left","bottom","bottom_right"].forEach(function(key){
            if(key==="center"){var fill=panel(frame,"RHFrame_center");fill.style.backgroundImage='url("'+A.window_center+'")';fill.style.backgroundSize="616px 134px";fill.style.backgroundRepeat="repeat";}
            else image(frame,"window_"+key,"RHFrame_"+key);
        });
        image(frame,"window_header_texture","RHHeaderPatch");
        if(header){header.style.backgroundColor="transparent";image(header,"window_title_ornament_left","RHTitleOrnamentLeft");image(header,"window_title_ornament_right","RHTitleOrnamentRight");}
        if(close){close.AddClass("RHClose");close.RemoveAndDeleteChildren();["normal","hover","pressed"].forEach(function(state){image(close,"window_close_"+state,"RHCloseImage RHClose_"+state);});close.hittestchildren=false;}
    };
    R.SizeWindow=function(p,w,h){
        p.style.width=w+"px";p.style.height=h+"px";
        if(!valid(p._rhFrame))return;
        var f=p._rhFrame,children=f.Children(),t=84,c=32*t/58;
        [[0,0,c,t],[c,0,w-c*2,t],[w-c,0,c,t],[0,t-1,c,h-t-c+2],[c,t-1,w-c*2,h-t-c+2],[w-c,t-1,c,h-t-c+2],[0,h-c,c,c],[c,h-c,w-c*2,c],[w-c,h-c,c,c],[w-120,13,101,58]].forEach(function(b,i){box(children[i],b[0],b[1],b[2],b[3]);});
    };
    R.Tab=function(b,i){b.AddClass("RHTab");b.AddClass(i===0?"RHTabFirst":i===3?"RHTabLast":"RHTabMiddle");b.style.backgroundImage="none";cfg.SurvivalNineSlice.Create(b,A[i===0?"tab_left":i===3?"tab_right":"tab_middle"],199,59,[12,12,12,12],"RHTabBase");if(i>0)panel(b,"RHTabSeparator");b.hittestchildren=false;};
    R.TabSelection=function(host,isHistory){var index=0;host.Children().forEach(function(b,i){if(b.BHasClass("Selected"))index=i;});var glow=image(host,"tab_glow","RHStandaloneTabGlow");box(glow,index*(isHistory?268:199),24,isHistory?268:199,59);host.style.zIndex="10";};
    R.RewardCard=function(b,item){
        var q=String(item.quality||"n").toLowerCase(),colors={n:"#398754",r:"#3283c5",sr:"#a052c8",ssr:"#bd8b25",ur:"#66338f"},tints={n:"#cdebd4",r:"#cce4fa",sr:"#e4cef5",ssr:"#ffebaf",ur:"#bda1d3"};
        b.AddClass("RHRewardCard");var skin=cfg.SurvivalNineSlice.Create(b,A.reward_card,170,155,[14,14,14,14],"RHRewardCardBase");skin.style.washColor=tints[q]||tints.n;
        var name="";b.Children().forEach(function(c){if(c.BHasClass("LotteryDetailIcon"))box(c,25,12,120,114);if(c.BHasClass("LotteryDetailCopy")){c.visible=false;c.Children().forEach(function(n){if(n.BHasClass("LotteryDetailName"))name=n.text;});}});
        // The old detail-copy class carries inherited text offsets from the retired side panel.
        // A clean label keeps the same authoritative name/quality and has one centered baseline.
        var caption=label(b,name,"RHRewardName");caption.style.position="0px 126px 0px";caption.style.width="fit-children";caption.style.maxWidth="159px";caption.style.height="30px";caption.style.horizontalAlign="center";caption.style.textAlign="center";
        caption.html=true;caption.text='<font color="'+(colors[q]||colors.n)+'">'+q.toUpperCase()+'</font> · '+String(item.name||item.id||"").replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
    };
    R.LotteryDialog=function(name,options){
        var p=options.panel,history=name==="history";
        p.SetHasClass("RHHistory",history);p.SetHasClass("RHPool",name==="details");
        if(!valid(p._rhContent))p._rhContent=image(p,"pool_content","RHPoolMaterial");
        p._rhContent.visible=name==="details";box(p._rhContent,22,139,796,451);
        options.width=history?1120:840;options.height=history?660:610;R.SizeWindow(p,options.width,options.height);
        // Explicit design coordinates also replace stale inline offsets retained by live editing.
        p.style.flowChildren="none";p.style.padding="0px";
        var header=$("#LotteryInfoHeader");box(header,0,0,options.width,84);header.style.padding="0px";
        var title=$("#LotteryInfoTitle");title.style.position="0px 0px 0px";
        $("#LotteryInfoClose").style.position="0px 0px 0px";
        box($("#LotteryInfoBody"),history?40:22,history?208:139,history?1055:796,history?370:382);
        box($("#LotteryInfoList"),history?0:22,history?0:22,history?1055:756,history?360:352);
        box($("#LotteryInfoFooter"),40,history?583:534,history?1040:760,54);
        box($("#LotteryInfoRules"),history?850:0,history?10:8,history?190:760,history?35:47);
        box($("#LotteryInfoNote"),49,597,730,35);
        var h=$("#RHHistoryColumns");if(!h){h=$.CreatePanel("Panel",p,"RHHistoryColumns");h.AddClass("RHHistoryColumns");["时间","奖励","品质","数量"].forEach(function(t,i){label(h,t,"RHHistoryColumn RHCol"+i);});}h.visible=history;
        $("#LotteryInfoBody").style.backgroundColor="transparent";
    };
    R.QualityText=function(value){return String(value||"").replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/\b(SSR|SR|UR|N|R)\b/g,function(q){return '<font color="'+cfg.SurvivalRewardPresentation.NameColor(q)+'">'+q+'</font>';});};
    R.History=function(host,entries,createIcon,showTooltip,hideTooltip){
        var index=0;
        entries.forEach(function(entry){entry.items.forEach(function(item){
            var row=$.CreatePanel("Panel",host,"");row.AddClass("RHHistoryRow");row.SetHasClass("RHAlternate",index++%2===0);row.hittestchildren=false;
            label(row,entry.time,"RHHistoryTime");var icon=createIcon(row,item,"RHHistoryRewardIcon");
            if(icon&&icon.SetScaling)icon.SetScaling("stretch-to-fit-preserve-aspect");
            label(row,(item.name||item.id)+(item.duplicate===true||Number(item.duplicate)===1?" · 已转化 "+Number(item.converted_points||0)+" 积分":""),"RHHistoryName");
            var q=String(item.quality||"n").toUpperCase(),quality=label(row,q,"RHHistoryQuality");quality.AddClass("RHQuality"+q);
            label(row,"×"+Number(item.count||item.quantity||1),"RHHistoryQuantity");
            row.SetPanelEvent("onmouseover",function(){showTooltip(item,row,true);});row.SetPanelEvent("onmouseout",hideTooltip);
        });});
        if(!index){var empty=panel(host,"RHHistoryEmpty");image(empty,"history_empty","RHHistoryEmptyIcon");label(empty,"暂无抽奖记录","RHHistoryEmptyText");}
    };
    R.Action=function(button,primary,profile){profile=profile||[304,64];button.AddClass("RHAction");button.style.backgroundImage="none";button.style.backgroundColor="transparent";button.hittestchildren=false;if(button.Children().some(function(c){return c.BHasClass("RHActionArt");}))return;["normal","hover","pressed","disabled"].forEach(function(s){cfg.SurvivalNineSlice.AtHeight(button,A[(primary?"button_primary_":"button_secondary_")+s],156,64,[24,22,24,22],profile[1],"RHActionArt RHAction_"+s);});};
    R.Image=function(parent,key,cls){
        var profiles={shop_card_normal_native:[225,273,14,14],shop_card_hover_native:[225,273,14,14],shop_bundle_compact:[540,276,18,18],shop_payment_normal:[210,60,14,14],shop_payment_selected:[210,60,14,14],shop_qr_outer:[220,220,18,18]};
        var s=profiles[key];return s?cfg.SurvivalNineSlice.Create(parent,A[key],s[0],s[1],[s[2],s[3],s[2],s[3]],cls):image(parent,key,cls);
    };R.Box=box;
    R.LotteryActions=function(){
        [['LHSingleBase','single_button.png'],['LHTenBase','ten_button.png'],['LHTenHover','ten_button_hover.png']].forEach(function(entry){
            var old=$('#'+entry[0]);if(!old)return;old.visible=false;
            var skin=cfg.SurvivalNineSlice.Create(old.GetParent(),'file://{images}/custom_game/lottery_handoff_v1/'+entry[1],312,72,[36,24,36,24],entry[0]==='LHTenHover'?'PolishTenHover':'PolishDrawBase');
            if(entry[0]==='LHSingleBase')cfg.SurvivalNineSlice.Create(old.GetParent(),'file://{images}/custom_game/lottery_handoff_v1/'+entry[1],312,72,[36,24,36,24],'PolishSingleHover');
        });
        ["LotteryConfirm","LotteryAgain"].forEach(function(id){var b=$("#"+id);b.Children().forEach(function(c){if(c.BHasClass("LotteryFunctionIcon"))c.visible=false;});R.Action(b,id==="LotteryAgain");});
        var skip=$("#LotterySkipReveal");skip.Children().forEach(function(c){if(c.BHasClass("LotteryFunctionIcon")){c.SetImage(A.action_chevron);c.style.transform="rotateZ(-90deg)";}});
    };
    var dailyResources=/*DAILY_RESOURCES*/;
    R.DailyResourceInfo=function(id){return dailyResources[id]||U.ResourceInfo(id);};
    R.DailyImage=function(parent,id,cls){var map={"daily.icon.calendar.normal":"daily_calendar","daily.icon.claimed":"daily_claimed","daily.item.crystals":"daily_crystals","daily.badge.premium":"daily_premium"};if(map[id])return image(parent,map[id],cls);var resource=dailyResources[id];if(!resource)return U.Image(parent,id,cls);var art=$.CreatePanel('Image',parent,'');art.SetImage('file://{images}/'+resource.runtime);art.AddClass(cls);art.hittest=false;art.hittestchildren=false;return art;};
    R.DailyCard=function(card,last,today){cfg.SurvivalNineSlice.Create(card,A[last?"daily_week":"daily_day"],last?310:152,394,[18,18,18,18],"RHDailyCardBase");card.SetHasClass("RHDailyCurrent",today);};
    R.DailyPass=function(button,on){button.style.backgroundImage="none";if(!button._rhPassSkins||!valid(button._rhPassSkins.ready)||!valid(button._rhPassSkins.locked)){button._rhPassSkins={};["ready","locked"].forEach(function(state){button._rhPassSkins[state]=cfg.SurvivalNineSlice.AtHeight(button,A["daily_"+state],112,32,[12,10,12,10],42,"RHDailyPassSkin");});}button._rhPassSkins.ready.visible=!!on;button._rhPassSkins.locked.visible=!on;};
    R.DailyTooltip=function(anchor,title,body){
        var tip=$("#DailyTooltip");U.Tooltip.Adopt(tip);anchor.hittest=true;
        anchor.SetPanelEvent("onmouseover",function(){
            $("#DailyTooltipName").text=title;$("#DailyTooltipEffect").text=body;
            tip.RemoveClass("ArchiveHidden");
        });
        anchor.SetPanelEvent("onmouseout",function(){tip.AddClass("ArchiveHidden");});
    };
    cfg.RemainingHandoff=R;
    // Local to the three-choice page; lottery result animations keep their own timeline.
    R.RogueSequence=function(){var life=U.Lifecycle();return {Later:life.Later,Cancel:life.Cancel,Dispose:life.Dispose,Animate:function(card,index){
        var at=.30+index*.11;
        life.Later(at,function(){card.slot.style.opacity="1";card.slot.style.transform="translate3d(0px,0px,0px) scale3d(1,1,1)";});
        life.Later(at+.65+.10,function(){card.flip.style.transform="rotateY(90deg)";});
        life.Later(at+.65+.10+.27,function(){card.front.visible=true;card.back.visible=false;card.flip.AddClass("RogueInstant");card.flip.style.transform="rotateY(-90deg)";life.Later(.01,function(){card.flip.RemoveClass("RogueInstant");card.flip.style.transform="rotateY(0deg)";});});
    }};};
    R.Dump=function(){function scan(p,depth){if(depth>2)return;$.Msg("[RH_TREE] "+depth+" "+p.id+" "+p.paneltype+" "+p.actuallayoutwidth+"x"+p.actuallayoutheight+" @"+p.actualxoffset+","+p.actualyoffset+" visible="+p.visible+" position="+p.style.position+" flow="+p.style.flowChildren+" z="+p.style.zIndex);p.Children().forEach(function(c){scan(c,depth+1);});}scan($("#LotteryInfoDialog"),0);};
    if(typeof Game!=="undefined"&&Game.AddCommand&&$("#LotteryInfoDialog")){
        var stamp=Date.now();
        ["details","history"].forEach(function(name){Game.AddCommand("remaining_"+name+"_"+stamp,function(){cfg.SurvivalLottery.Open();$.Schedule(.4,function(){cfg.SurvivalLottery.Feature(name);});},"Open existing UI for visual verification",0);});
        Game.AddCommand("remaining_dump_"+stamp,function(){var values={};["LotteryInfoDialog","LotteryInfoHeader","LotteryInfoTitle","LotteryInfoTabs","LotteryInfoBody","LotteryInfoList","LotteryInfoFooter","LotteryInfoRules"].forEach(function(id){var p=$("#"+id);values[id]=p?{width:p.actuallayoutwidth,height:p.actuallayoutheight,scale:p.actualuiscale_x,position:p.actualxoffset+","+p.actualyoffset,visible:p.visible,text:p.text}:null;});$.Msg("[REMAINING_UI_STATE] "+JSON.stringify(values));},"Read modal layout",0);
        $.Msg("[REMAINING_UI_READY] commands="+stamp);
    }
})();
