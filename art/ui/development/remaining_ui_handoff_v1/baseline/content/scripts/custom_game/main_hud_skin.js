(function () {
    "use strict";
    // UI_REUSE_V1
    var U=GameUI.CustomUIConfig().SurvivalUI;
    var cfg=GameUI.CustomUIConfig(),ctx=$.GetContextPanel(),root=ctx;
    while(root.GetParent&&root.GetParent())root=root.GetParent();
    var assets=cfg.SurvivalMainHudAssets,skin=$("#MainHudSkin"),generation=(cfg.MainHudSkinGeneration||0)+1;
    cfg.MainHudSkinGeneration=generation;
    var scale=1,dw=1672,dh=941,lastSize="",snapshot={},sequence=-1,noticeSerial=0,ready=false;
    var statBindings=[["attack","攻击","CombatAttackValue"],["armor","护甲","CombatArmorValue"],["strength","力量","CombatStrengthValue"],["agility","敏捷","CombatAgilityValue"],["intelligence","智力","CombatIntellectValue"]];
    var nativeNodes={},frameNodes={},topButtons={};
    var nativeScopes={center_with_stats:"lower_hud",center_block:"center_with_stats",PortraitGroup:"center_block",PortraitContainer:"PortraitGroup",portraitHUD:"PortraitGroup",portraitHUDOverlay:"PortraitGroup",stats_container:"center_block",unitname:"center_block",health_mana:"center_block",center_bg:"center_block",left_flare:"center_block",right_flare:"center_block",AbilitiesAndStatBranch:"center_block",abilities:"AbilitiesAndStatBranch",inventory:"center_block",inventory_composition_layer_container:"center_block",minimap_block:"minimap_container",minimap:"minimap_block"};
    function valid(p){return p&&(!p.IsValid||p.IsValid());}
    function p(id){return ctx.FindChildTraverse(id);}
    function native(id){var n=nativeNodes[id];if(!valid(n)){var owner=nativeScopes[id]?native(nativeScopes[id]):root;n=valid(owner)?owner.FindChildTraverse(id):null;nativeNodes[id]=n;}return n;}
    function set(panel,styles){if(!valid(panel))return;Object.keys(styles).forEach(function(k){if(String(panel.style[k])!==String(styles[k]))panel.style[k]=styles[k];});}
    function place(panel,x,y,w,h){set(panel,{horizontalAlign:"left",verticalAlign:"top",margin:"0px",padding:"0px",position:x+"px "+y+"px 0px",width:w+"px",height:h+"px"});}
    function label(parent,id,text){var l=$.CreatePanel("Label",parent,id);l.text=text||"";l.hittest=false;return l;}
    function image(parent,file){var i=$.CreatePanel("Image",parent,"");i.SetImage(U.ProjectAsset("custom_game/main_hud_v1/"+file));i.hittest=false;return i;}
    function tip(target,text){target.SetPanelEvent("onmouseover",function(){$.DispatchEvent("DOTAShowTextTooltip",target,typeof text==="function"?text():text);});target.SetPanelEvent("onmouseout",function(){$.DispatchEvent("DOTAHideTextTooltip");});}
    function notice(text){var serial=++noticeSerial;p("MainHudNotice").text=text;p("MainHudNotice").RemoveClass("MainHudHidden");$.Schedule(4,function(){if(valid(ctx)&&serial===noticeSerial)p("MainHudNotice").AddClass("MainHudHidden");});}
    function blocked(){return cfg.SurvivalUILayers&&cfg.SurvivalUILayers.Top();}
    function forward(id){var target=native(id);if(!valid(target))return false;$.DispatchEvent("Activated",target,"mouse");return true;}
    var bindings={treasure:["SurvivalTreasure","Toggle"],archive:["SurvivalArchive","Toggle"],equipment:["SurvivalEquipment","Toggle"],lottery:["SurvivalLottery","Open"],benefit:["SurvivalDaily","Open"],appearance:["SurvivalAppearance","Toggle"]};
    function available(id){if(id==="return")return valid(native("DashboardButton"));if(id==="settings")return valid(native("SettingsRebornButton"))||valid(native("SettingsButton"));if(id==="social")return true;var b=bindings[id];return b&&cfg[b[0]]&&typeof cfg[b[0]][b[1]]==="function";}
    function activate(id){if(blocked())return;if(id==="return"){if(!forward("DashboardButton"))notice("官方返回入口尚未就绪");return;}if(id==="settings"){if(!forward("SettingsRebornButton")&&!forward("SettingsButton"))notice("官方设置入口尚未就绪");return;}if(id==="social"){p("MainHudSocial").ToggleClass("MainHudHidden");return;}var b=bindings[id];if(available(id)){p("MainHudSocial").AddClass("MainHudHidden");cfg[b[0]][b[1]]();}else notice("该入口暂无已接入功能");}
    U.HUDShell.Adopt(skin);
    assets.icons.forEach(function(a){var b=U.IconButton(p("MainHudTop"),{id:"MainHudEntry_"+a.id,iconId:"icon.nav."+a.id,label:a.label,action:function(){activate(a.id);}});b.AddClass("MainHudIconButton");tip(b,function(){return available(a.id)?a.label:a.label+"：功能待接入";});topButtons[a.id]=b;});
    [["SharedUnitsButton","共享单位"],["SharedContentButton","共享内容"],["CombatLogButton","战斗日志"]].forEach(function(entry){var b=$.CreatePanel("Button",p("MainHudSocial"),"");label(b,"",entry[1]);b.SetPanelEvent("onactivate",function(){if(blocked())return;if(!forward(entry[0]))notice(entry[1]+"入口当前不可用");p("MainHudSocial").AddClass("MainHudHidden");});});
    tip(p("MainHudHideEffects"),"屏蔽特效：项目尚无对应的全局特效开关，暂不可用");
    statBindings.forEach(function(b){var cell=$.CreatePanel("Panel",p("MainHudStats"),"");cell.AddClass("MainHudStat");image(cell,"stat_"+b[0]+"_icon_64.png");label(cell,"",b[1]);var value=label(cell,"MainHudStat_"+b[0],"—");value.AddClass("MainHudStatValue");});
    var toolBindings=[["utility_target_icon_64.png","定位当前单位",function(){var resolver=cfg.SurvivalSelectionResolver,unit=resolver&&resolver.Resolve?resolver.Resolve():Players.GetLocalPlayerPortraitUnit();if(unit>=0)GameUI.SetCameraTargetPosition(Entities.GetAbsOrigin(unit),.15);}],["utility_flag_icon_64.png","防御符文",function(){if(!forward("glyph"))notice("符文入口当前不可用");}],["utility_bag_icon_64.png","商店",function(){if(cfg.SurvivalShop)cfg.SurvivalShop.ToggleShop();}],["utility_zoom_icon_64.png","地图扫描",function(){if(!forward("RadarButton"))notice("扫描入口当前不可用");}]];
    toolBindings.forEach(function(b,index){var button=$.CreatePanel("Button",p("MainHudTools"),"");button.AddClass("MainHudUtility");button.hittestchildren=false;frame(button,"utility_"+index,"utility_button",0,0,51,49);image(button,b[0]);tip(button,b[1]);button.SetPanelEvent("onactivate",function(){if(!blocked())b[2]();});});
    function frame(parent,key,type,x,y,w,h,background){var host=frameNodes[key];if(!valid(host)){host=$.CreatePanel("Panel",parent,"MainHudFrame_"+key);host.hittest=false;host.hittestchildren=false;host._pieces={};["tl","top","tr","left","right","bl","bottom","br"].forEach(function(part){host._pieces[part]=image(host,type+"_"+part+".png");});frameNodes[key]=host;}place(host,x,y,w,h);set(host,{zIndex:"-1",backgroundColor:background||"transparent"});var n=assets.frames[type].inset;
        var bounds={tl:[0,0,n,n],top:[n,0,w-2*n,n],tr:[w-n,0,n,n],left:[0,n,n,h-2*n],right:[w-n,n,n,h-2*n],bl:[0,h-n,n,n],bottom:[n,h-n,w-2*n,n],br:[w-n,h-n,n,n]};
        Object.keys(bounds).forEach(function(k){var b=bounds[k];place(host._pieces[k],b[0],b[1],b[2],b[3]);});return host;}
    function nativeLayout(){
        var lower=native("lower_hud"),center=native("center_with_stats"),block=native("center_block"),map=native("minimap_container"),mini=native("minimap_block"),abilities=native("AbilitiesAndStatBranch"),list=native("abilities"),inventory=native("inventory"),portrait=native("PortraitGroup");
        if(![lower,center,block,map,mini,abilities,list,inventory,portrait].every(valid))return false;
        // Never SetParent/Delete/replace an engine-owned panel or alter its events.
        // Full-screen positioning hosts must never intercept world clicks.
        [lower,center,block,map].forEach(function(n){n.hittest=false;n.hittestchildren=true;});
        [lower,map].forEach(function(n){set(n,{width:dw+"px",height:dh+"px",maxWidth:"10000px",horizontalAlign:"center",verticalAlign:"bottom",margin:"0px",padding:"0px",transformOrigin:"50% 100%",transform:"scale3d("+scale+","+scale+",1)",overflow:"noclip"});});
        [center,block].forEach(function(n){place(n,0,0,dw,dh);set(n,{flowChildren:"none",overflow:"noclip",transform:"none"});});
        var dx=(dw-1672)/2,dy=dh-941,right=dw-1672;
        // Frames are siblings of native controls, never inserted into AbilityN trees.
        [["hero",dx,dy],["inventory",right,dy],["commands",right,dy]].forEach(function(v){var r=assets.frames[v[0]].rect;frame(block,v[0],v[0],r[0]+v[1],r[1]+v[2],r[2],r[3],"#102f39ed");});
        place(portrait,470+dx,767+dy,124,113);set(portrait,{overflow:"clip"});
        place(native("PortraitContainer"),0,0,124,113);
        // The model and existing project portrait overlays continue to follow the selected unit.
        ["portraitHUD","portraitHUDOverlay"].forEach(function(id){set(native(id),{width:"124px",height:"113px",transform:"none"});});
        ["stats_container","unitname","health_mana","center_bg","left_flare","right_flare"].forEach(function(id){var n=native(id);set(n,{opacity:"0"});if(valid(n)){n.hittest=false;n.hittestchildren=false;}});
        place(abilities,1319+right,691+dy,319,216);set(abilities,{minWidth:"0px",flowChildren:"none",overflow:"noclip"});
        place(list,0,0,319,216);set(list,{minHeight:"0px",flowChildren:"right-wrap",overflow:"squish scroll",transform:"none"});
        // Native hidden slots remain hidden. No artificial 12-slot binding or key reassignment.
        if(list.GetChildCount)for(var i=0;i<list.GetChildCount();i++){var slot=list.GetChild(i);if(!/^Ability\d+$/.test(slot.id))continue;set(slot,{width:"79px",height:"72px",margin:"0px",padding:"0px"});}
        place(inventory,1041+right,772+dy,201,138);set(inventory,{overflow:"noclip"});
        ["InventoryBG","InventoryBackpackContainer","BackPackShadow"].forEach(function(id){set(inventory.FindChildTraverse(id),{backgroundImage:"none",backgroundColor:"transparent"});});
        set(inventory.FindChildTraverse("inventory_items"),{backgroundImage:"none",backgroundColor:"transparent",overflow:"noclip"});
        set(inventory.FindChildTraverse("inventory_list_container"),{padding:"0px"});
        ["inventory_list","inventory_list2"].forEach(function(id){set(inventory.FindChildTraverse(id),{width:"201px",height:"64px",margin:"0px",padding:"0px"});});
        for(var j=0;j<6;j++)set(inventory.FindChildTraverse("inventory_slot_"+j),{width:"61px",height:"61px",margin:"0px 3px",padding:"0px"});
        set(inventory.FindChildTraverse("inventory_backpack_list"),{marginTop:"130px",marginLeft:"0px"});
        // Additional native slots and buffs stay reachable, above the main plates.
        place(native("inventory_composition_layer_container"),1150+right,635+dy,100,96);
        place(native("buffs"),620+dx,704+dy,350,40);place(native("debuffs"),620+dx,658+dy,350,40);
        place(mini,40,690+dy,232,213);set(mini,{backgroundImage:"none",backgroundColor:"#102e39",overflow:"clip"});
        var mapControl=native("minimap");place(mapControl,0,0,232,213);set(mapControl,{transform:"none"});
        var mf=frame(map,"minimap","minimap",28,678+dy,256,237);set(mf,{zIndex:"3"});
        set(native("GlyphScanContainer"),{opacity:"0"});
        // The original shop/archive/treasure APIs are invoked by the new toolbar.
        ["ArchiveEntry","TreasureEntry","CustomShopButton"].forEach(function(id){var n=root.FindChildTraverse(id);if(valid(n)){set(n,{visibility:"collapse"});}});
        return true;
    }
    function layout(){var w=(ctx.actuallayoutwidth||1672)/(ctx.actualuiscale_x||1),h=(ctx.actuallayoutheight||941)/(ctx.actualuiscale_y||1);scale=Math.min(w/1672,h/941);dw=w/scale;dh=h/scale;
        var size=[Math.round(w),Math.round(h)].join(":");set(skin,{width:dw+"px",height:dh+"px",transform:"scale3d("+scale+","+scale+",1)"});
        var dx=(dw-1672)/2,dy=dh-941,right=dw-1672;
        place(p("MainHudHeroText"),459+dx,750+dy,532,165);place(p("MainHudCurrency"),1091+right,735+dy,150,30);place(p("MainHudTools"),291,702+dy,51,201);place(p("MainHudScore"),1203+right,16,454,104);
        // Score frame deliberately expands below the original row to preserve population/city information.
        frame(p("MainHudScore"),"scoreboard","scoreboard",0,0,454,104);
        if(size!==lastSize||!ready){ready=nativeLayout();if(ready){lastSize=size;ctx.AddClass("MainHudSkinReady");["TopBar","WaveBar"].forEach(function(id){var n=p(id);if(n){n.hittest=false;n.hittestchildren=false;}});}}
        p("MainHudHeroText").visible=ready;p("MainHudCurrency").visible=ready;p("MainHudTools").visible=ready;
    }
    function text(id,value){var n=p(id);if(n&&n.text!==String(value))n.text=String(value);}
    function compact(v){var f=cfg.SurvivalNumberFormatter;return f&&f.Compact?f.Compact(v):String(v===undefined?"—":v);}
    function data(next){if(!next||Number(next.sequence)<=sequence)return;sequence=Number(next.sequence||sequence+1);snapshot=next;var r=next.resources||{},wave=next.wave||{},t=Math.max(0,Math.ceil(Number(wave.timer)||0));
        text("MainHudWaveText","第"+Number(wave.current_wave||0)+"波 · "+Math.floor(t/60)+":"+(t%60<10?"0":"")+t%60);
        // No invented timer duration: only show a fraction when the server supplies one.
        var duration=Number(wave.duration||wave.total_time||0);p("MainHudWaveTrack").visible=duration>0;set(p("MainHudWaveFill"),{width:(duration>0?Math.max(0,Math.min(100,t/duration*100)):0)+"%"});
        text("MainHudDifficulty",wave.difficulty_id||"待选");text("MainHudCurrencyText",compact(r.gold));text("MainHudResourcesExtra","人口 "+compact(r.population)+"/"+compact(r.max_population)+" · 主城 Lv."+Number(next.city_level||0)+" · 存活 "+Number(wave.alive||0)+" · 待生成 "+Number(wave.pending||0));
        var rows=p("MainHudScoreRows");rows.RemoveAndDeleteChildren();var row=$.CreatePanel("Panel",rows,"");row.AddClass("MainHudScoreRow");var info=Game.GetPlayerInfo(Game.GetLocalPlayerID())||{};label(row,"",info.player_name||"玩家").AddClass("MainHudPlayerName");[r.gold,r.wood,info.player_kills].forEach(function(v){label(row,"",compact(v));});
    }
    function mirror(){[["MainHudHeroName","SurvivalHeroName"],["MainHudHeroLevel","SurvivalHeroLevel"],["MainHudHealthText","SurvivalHeroHealthText"],["MainHudManaText","SurvivalHeroManaText"]].forEach(function(pair){var source=p(pair[1]);if(source)text(pair[0],(pair[0]==="MainHudHeroLevel"?"Lv.":"")+source.text);});
        ["Health","Mana"].forEach(function(type){var source=p("SurvivalHero"+type+"Fill");if(source&&source.style.width)set(p("MainHud"+type+"Fill"),{width:source.style.width});});
        statBindings.forEach(function(b){var source=p(b[2]);if(source)text("MainHudStat_"+b[0],source.text);});
        Object.keys(topButtons).forEach(function(id){topButtons[id].SetHasClass("Unavailable",!available(id)); U.State.Set(topButtons[id],{enabled:!!available(id)});});
    }
    function tick(){if(!valid(ctx)||cfg.MainHudSkinGeneration!==generation)return;layout();mirror();$.Schedule(.25,tick);}
    // A new selected entity may rebuild native slots; apply geometry after that rebuild, not on Alt.
    ["dota_player_update_selected_unit","dota_player_update_query_unit"].forEach(function(event){GameEvents.Subscribe(event,function(){lastSize="";});});
    GameEvents.Subscribe("survival_ui_private_snapshot",data);
    cfg.SurvivalMainHUD={Inspect:function(){return {nativeReady:ready,designWidth:dw,designHeight:dh,scale:scale,missing:Object.keys(nativeNodes).filter(function(k){return !valid(nativeNodes[k]);})};}};
    data(CustomNetTables.GetTableValue("survival_ui_state","player_"+Game.GetLocalPlayerID()));tick();
})();
