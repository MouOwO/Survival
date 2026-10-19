(function () {
    "use strict";
    // Presentation only. The existing controller owns requests, balances and layers.
    var cfg = GameUI.CustomUIConfig(), root = $.GetContextPanel(), U = cfg.SurvivalUI, R = cfg.RemainingHandoff;
    if (cfg.SurvivalPurpleLottery && cfg.SurvivalPurpleLottery.Dispose) cfg.SurvivalPurpleLottery.Dispose();
    var disposed = false, life = $.CreatePanel("Panel", root, ""), view = null, nodes = {}, moved = [], owned = [], tipDismiss = null;
    var mode = "", pools = [], selected = "map", snapshot = null, opened = false, scale = 1, tabKey = "", previewKey = "", prizeFolded = {}, prizeGroups = [];
    var tipAnchor = null, tipHideJob = null, tipEpoch = 0;
    // Coordinates are local to the accepted 1672 x 941 canvas, never screen pixels.
    var layout={canvas:[1672,941],header:[35,45,1608,74],sidebar:[35,123,299,746],footer:[334,804,1309,65],content:[334,123,1309,681],info:[334,123,1309,746]};
    life.visible = false;
    function valid(n) { return n && (!n.IsValid || n.IsValid()); }
    function alive() { return !disposed && valid(root) && valid(life); }
    function remember(n) { if (!valid(n)) return; if (n.id) nodes[n.id] = n; n.Children().forEach(remember); }
    // Compiled-layout traversal can stop finding controls after SetParent.
    remember(root);
    function p(id) { if (!alive()) return null; if (valid(nodes[id])) return nodes[id]; var n = root.FindChildTraverse(id); if (!valid(n)) return null; nodes[id] = n; return n; }
    function style(n, values) { if (valid(n)) Object.keys(values).forEach(function (k) { n.style[k] = values[k]; }); }
    function place(n, x, y, w, h) { style(n, {position:x + "px " + y + "px 0px", width:w + "px", height:h + "px", margin:"0px", padding:"0px", horizontalAlign:"left", verticalAlign:"top", ignoreParentFlow:"true"}); }
    function fillItemIcon(icon,item){var presentation=cfg.SurvivalRewardPresentation;if(presentation&&presentation.FillIcon)return presentation.FillIcon(icon,item);if(valid(icon)&&icon.SetScaling)icon.SetScaling("stretch-to-cover-preserve-aspect");return icon;}
    function bindTooltipIcon(card,source,item){
        for(var owner=source.GetParent();valid(owner);owner=owner.GetParent()){owner.hittestchildren=true;if(owner===card)break;}
        card.SetPanelEvent("onmouseover",function(){});card.SetPanelEvent("onmouseout",function(){});
        source.hittest=true;source.hittestchildren=false;
        source.SetPanelEvent("onmouseover",function(){if(!card.BHasClass("LotteryCardCovered"))tooltip(item,source);});
        source.SetPanelEvent("onmouseout",function(){if(!requestTooltipHide(source))hideTooltip();});
    }
    function walk(n, fn) { if (!valid(n)) return; fn(n); n.Children().forEach(function (c) { walk(c, fn); }); }
    function make(type, parent, id, cls) { var n = $.CreatePanel(type, parent, id || ""); if (id) nodes[id] = n; if (cls) n.AddClass(cls); owned.push(n); return n; }
    function label(parent, id, text, x, y, w, h, size, color) { var n = make("Label", parent, id, "LotteryGW2Label"); n.text = text; n.hittest = false; place(n,x,y,w,h); style(n,{fontSize:size + "px",color:color || "#eaddc4"}); return n; }
    function asset(key) { var data=cfg.LotteryGW2Data,row=data&&data.assets&&data.assets[key];return row&&row.file||""; }
    function skin(n,key) { style(n,{backgroundImage:'url("' + asset(key) + '")',backgroundSize:"100% 100%",backgroundRepeat:"no-repeat",backgroundColor:"transparent",border:"0px"}); }
    function art(parent,id,key,x,y,w,h) { var n=make("Panel",parent,id,"LotteryGW2Art"); n.hittest=false; n.hittestchildren=false; place(n,x,y,w,h); skin(n,key); return n; }
    function surface(parent,id,box,color){var n=make("Panel",parent,id,"LotteryGW2Surface");place(n,box[0],box[1],box[2],box[3]);style(n,{backgroundImage:"none",backgroundColor:color});n.hittest=false;n.hittestchildren=false;return n;}
    function wellStyle(n){n.AddClass("LotteryGW2ItemWell");style(n,{backgroundImage:'url("s2r://panorama/images/hud/reborn/inventory_item_well_psd.vtex")',backgroundSize:"100% 100%",backgroundRepeat:"no-repeat",backgroundColor:"#171b18",border:"1px solid #9b8c62",overflow:"clip"});return n;}
    function itemWell(parent,x,y,w,h,id){var n=make("Panel",parent,id||"","");place(n,x,y,w,h);n.hittest=false;n.hittestchildren=false;return wellStyle(n);}
    function moveNode(n,parent) {
        if (!valid(n) || !valid(parent) || n.GetParent() === parent) return n;
        if (!moved.some(function (e) { return e.node === n; })) { var old=n.GetParent(),siblings=valid(old)?old.Children():[]; moved.push({node:n,parent:old,next:siblings[siblings.indexOf(n)+1]}); }
        n.SetParent(parent); return n;
    }
    function move(id,parent) { return moveNode(p(id),parent); }
    function hidden(id) { style(p(id),{visibility:"collapse"}); }
    function canAct() { var layers=cfg.SurvivalUILayers,top=layers&&layers.Top?layers.Top():null;return alive()&&opened&&(!layers||!layers.Top||top==="lottery"||top==="lottery_info"); }
    function invoke(method,arg) { if(!canAct())return;var ui=cfg.SurvivalLottery; if(ui && typeof ui[method]==="function") ui[method](arg); }
    function prune() { owned=owned.filter(valid);moved=moved.filter(function(e){return valid(e.node)&&valid(e.parent);}); }
    function button(parent,id,text,fn) { var b=make("Button",parent,id,"LotteryGW2Action"); b.hittestchildren=false;var caption=label(b,"",text,0,0,150,44,19);style(caption,{width:"100%",height:"fit-children",horizontalAlign:"center",verticalAlign:"center",textAlign:"center"}); b.SetPanelEvent("onactivate",function(){if(alive())fn();}); return b; }
    function existingRewardArt(icon,item) {
        // Registered artwork already came from the shared icon factory. Never
        // restore the old per-window catalogue on top of that resource.
        if(cfg.SurvivalItemResources&&cfg.SurvivalItemResources.Lookup(item))return icon;
        var catalog=cfg.SurvivalItemArt,row=catalog&&catalog.Lookup&&catalog.Lookup(item);
        if(!valid(icon)||typeof icon.SetImage!=="function"||!row||!/^lottery_/.test(String(row.item_id||""))||String(row.icon_path||"").indexOf("custom_game/reward_art_v5/")!==0)return icon;
        var uri=row.runtime_uri||"file://{images}/"+row.icon_path;
        if(icon.__lotteryGW2Art!==uri){icon.SetImage(uri);icon.__lotteryGW2Art=uri;}return icon;
    }
    function lotteryParent(parent) {
        // The factory remains unchanged for every non-lottery consumer.
        var window=p("LotteryWindow");for(var n=parent;valid(n);n=n.GetParent())if(n===window)return true;
        return false;
    }
    function fit() {
        if (!ensure()) return false;prune();
        var viewport=cfg.LotteryHandoff && cfg.LotteryHandoff.Viewport && cfg.LotteryHandoff.Viewport();
        if (!viewport) { style(p("LotteryMainCanvas"),{opacity:"0"}); return false; }
        scale=Number(U.Fit(p("LotteryMainCanvas"),root,layout.canvas[0],layout.canvas[1],{reference:layout.canvas.slice()})) || 1;
        style(p("LotteryMainCanvas"),{opacity:"1",transformOrigin:"50% 50%"}); return true;
    }
    function ensure() {
        // A cached view belongs to its original HUD lifetime. Controller reload
        // can call this API before the next presentation script is installed.
        if (!alive()) return null;
        var canvas=p("LotteryMainCanvas"),window=p("LotteryWindow"); if(!valid(canvas)||!valid(window)||!U) return null;
        if (view) return valid(view.root)?view:null;
        canvas.RemoveClass("LotteryPurple"); canvas.RemoveClass("MenuV10Page"); canvas.AddClass("LotteryV10"); canvas.AddClass("LotteryGW2");
        window.RemoveClass("LotteryV10Root"); window.AddClass("LotteryGW2Root");window.AddClass("LotteryCurrentVersion");
        style(canvas,{width:"1672px",height:"941px",position:"0px 0px 0px",horizontalAlign:"center",verticalAlign:"center",transformOrigin:"50% 50%",margin:"0px",padding:"0px",backgroundImage:"none",backgroundColor:"transparent",border:"0px",boxShadow:"none",flowChildren:"none",overflow:"noclip"});
        var shell=make("Panel",canvas,"LotteryGW2Root","LotteryGW2Shell"); place(shell,0,0,1672,941);
        surface(shell,"LotteryGW2Background",[35,45,1608,824],"#0e181c");
        // The original carousel paints under both the sidebar and footer. No
        // composite reference screenshot or patched RGB surface is used here.
        move("LotterySceneBackground",shell);move("LotterySceneShade",shell);
        // Keep the original scene's subject anchored to the right content area.
        // Its own left edge blends into an extension of that same original
        // resource under the sidebar. Shared textures are not copied/repainted.
        ["map","cultivation","dragon_knight","summer"].forEach(function(id){var page=p("LotteryScenePage_"+id);if(!valid(page))return;var subject=make("Panel",page,"","LotteryGW2SceneSubject");place(subject,299,0,1309,746);style(subject,{backgroundImage:'url("file://{images}/custom_game/lottery_cinematic_v1/'+id+'.png")',backgroundSize:"cover",backgroundPosition:"center",backgroundRepeat:"no-repeat",opacityMask:'url("file://{images}/custom_game/lottery_final_v1/scene_blend.svg")'});subject.hittest=false;subject.hittestchildren=false;});
        surface(shell,"LotteryGW2SidebarSkin",layout.sidebar,"#0000004d");
        surface(shell,"LotteryGW2FooterSkin",layout.footer,"#10191d");
        surface(shell,"LotteryGW2HeaderSkin",layout.header,"#0e181c");
        art(shell,"","final_header_rule",35,118,1608,6);
        art(shell,"","final_sidebar_rule",332,123,5,746);
        art(shell,"LotteryGW2FooterRule","final_footer_rule",334,802,1309,5);
        // Valve's sliced border keeps the corners crisp at the full window size.
        var officialFrame=make("Panel",shell,"LotteryGW2OfficialFrame","LotteryGW2OfficialFrame");place(officialFrame,35,45,1608,824);
        style(officialFrame,{backgroundImage:"none",backgroundColor:"transparent",borderImageSource:'url("s2r://panorama/images/events/dark_carnival/overworld/inner_panel_border_png.vtex")',borderWidth:"10px",borderImageSlice:"20px",zIndex:"20"});
        officialFrame.hittest=false;officialFrame.hittestchildren=false;
        var header=make("Panel",shell,"LotteryGW2Header"); place(header,35,45,1608,74);style(header,{zIndex:"4"});
        var sidebarPanel=make("Panel",shell,"LotteryGW2Sidebar"); place(sidebarPanel,35,123,299,746);style(sidebarPanel,{zIndex:"4"});
        var content=make("Panel",shell,"LotteryGW2Content"); place(content,334,123,1309,681); style(content,{overflow:"clip",flowChildren:"none",zIndex:"2"});
        var detail=make("Panel",shell,"LotteryGW2DetailLayer"); place(detail,0,0,1672,941); detail.hittest=false;style(detail,{zIndex:"8"});
        // UILayers raises the details ancestry. Keep its tooltip in that same
        // layer so the authoritative details panel cannot cover the tooltip.
        var tooltip=make("Panel",detail,"LotteryGW2Tooltip","LotteryGW2Tooltip"); tooltip.hittest=false; tooltip.hittestchildren=false; tooltip.visible=false;
        style(tooltip,{zIndex:"100",flowChildren:"none"});
        var tipSkin=cfg.SurvivalBlackLionMarket.SkinTooltip(tooltip);tipSkin.Resize(368,340);
        var tipIconStage=itemWell(tooltip,20,22,48,48,"LotteryGW2TooltipIconStage");
        var tipTitleRow=make("Panel",tooltip,"LotteryGW2TooltipTitleRow");place(tipTitleRow,80,22,264,48);tipTitleRow.hittest=false;tipTitleRow.hittestchildren=false;
        var tipName=label(tipTitleRow,"LotteryGW2TooltipName","",0,0,264,48,21,"#f0dfb8");
        style(tipName,{width:"fit-children",height:"fit-children",maxWidth:"264px",horizontalAlign:"left",verticalAlign:"center",whiteSpace:"nowrap",textOverflow:"shrink"});
        var tipState=label(tooltip,"LotteryGW2TooltipState","",80,67,264,24,16,"#b5bfbb");
        var tipScroll=make("Panel",tooltip,"LotteryGW2TooltipScroll"); place(tipScroll,22,116,322,178); style(tipScroll,{flowChildren:"down",overflow:"squish scroll"});
        var tipDescription=label(tipScroll,"LotteryGW2TooltipDescription","",0,0,316,178,18,"#e0d6c5"); style(tipDescription,{height:"fit-children",ignoreParentFlow:"false",whiteSpace:"normal"});
        var tipCount=label(tooltip,"LotteryGW2TooltipQuantity","",22,294,322,24,17,"#b5bfbb");
        [tipName,tipState,tipDescription,tipCount].forEach(function(node){style(node,{textShadow:"none"});});
        style(tipDescription,{fontSize:"17px",lineHeight:"24px",color:"#d7d9cb",textOverflow:"clip"});
        view={root:shell,header:header,sidebar:sidebarPanel,content:content,detailLayer:detail,tooltip:tooltip,tipSkin:tipSkin,tipName:tipName,tipState:tipState,tipDescription:tipDescription,tipCount:tipCount,tipScroll:tipScroll,tipIconStage:tipIconStage,tabs:[]};
        tooltipGuard();
        tooltip.SetPanelEvent("onmouseover",function(){if(tooltipOverflows())cancelTooltipHide();else if(tipDismiss)tipDismiss.Dismiss();});
        tooltip.SetPanelEvent("onmouseout",function(){if(!requestTooltipHide(false))hideTooltip();});
        art(header,"","final_header_back_divider",110,16,5,46);
        view.title=label(header,"LotteryGW2Title","抽奖",129,10,560,51,40,"#efdfbc");
        view.back=button(header,"LotteryGW2Back","返回",function(){if(mode)invoke("CloseInfo");else invoke("Close");}); place(view.back,22,16,82,46);
        place(view.back.Children()[0],24,0,54,46);style(view.back.Children()[0],{horizontalAlign:"left",verticalAlign:"top",fontSize:"26px"});art(view.back,"","final_back_arrow",4,6,17,31);
        view.ticket=label(header,"LotteryGW2TicketBalance","抽奖券 —",708,21,340,34,25,"#e6dfd0");
        style(view.ticket,{whiteSpace:"nowrap",textOverflow:"shrink"});
        var ticketAt=String(view.ticket.style.position).split(" "),ticketWidth=parseFloat(view.ticket.style.width),ticketHeight=parseFloat(view.ticket.style.height);
        view.ticketHost=make("Panel",header,"LotteryGW2TicketCurrency");place(view.ticketHost,parseFloat(ticketAt[0]),parseFloat(ticketAt[1]),ticketWidth,ticketHeight);style(view.ticketHost,{width:"fit-children",height:"40px",flowChildren:"right"});view.ticketHost.hittest=false;view.ticketHost.hittestchildren=true;
        view.ticket.SetParent(view.ticketHost);place(view.ticket,0,0,ticketWidth-88,ticketHeight);style(view.ticket,{width:"fit-children",maxWidth:(ticketWidth-88)+"px",height:"fit-children",verticalAlign:"center",ignoreParentFlow:"false"});view.ticket.text="—";
        view.ticketIcon=make("Panel",view.ticketHost,"LotteryGW2TicketIcon");place(view.ticketIcon,0,0,36,29);style(view.ticketIcon,{verticalAlign:"center",ignoreParentFlow:"false",marginRight:"8px"});view.ticketIcon.hittest=false;view.ticketIcon.hittestchildren=false;
        if(view.ticketHost.MoveChildBefore)view.ticketHost.MoveChildBefore(view.ticketIcon,view.ticket);
        // Keep the controller's original purchase callback and current-pool
        // routing; only replace its presentation with the shop's recharge affordance.
        var purchase=move("LotteryTicketPurchase",view.ticketHost);place(purchase,0,0,32,32);purchase.AddClass("LotteryGW2Recharge");purchase.hittestchildren=false;
        style(purchase,{verticalAlign:"center",ignoreParentFlow:"false",marginLeft:"8px"});purchase.Children().forEach(function(c){c.visible=false;});
        var plus=make("Image",purchase,"LotteryGW2PurchasePlus","LotteryGW2RechargeIcon");plus.SetImage("file://{images}/control_icons/24px/plus.svg");plus.hittest=false;
        move("LotteryCloseButton",header); place(p("LotteryCloseButton"),1538,11,51,53);style(p("LotteryCloseButton"),{backgroundImage:"none",backgroundColor:"#51483a",border:"0px"});p("LotteryCloseButton").Children().forEach(function(c){c.visible=false;});
        art(p("LotteryCloseButton"),"","final_close_frame",0,0,51,53);art(p("LotteryCloseButton"),"","final_close_cross",8,8,37,37);
        ["LotteryHeroCopy","LotteryUnlockNotice","LotteryResultStage","LotteryRevealStage","LotterySkipReveal","LotteryStatus"].forEach(function(id){move(id,content);});
        move("LotteryCelestialFooter",shell);style(p("LotteryCelestialFooter"),{zIndex:"4"});
        move("LotteryInfoOverlay",detail); move("LotteryAnnouncement",p("LotteryCelestialFooter"));
        ["LotteryCelestialHeader","LotteryPoolTabs","LotteryReadingMask"].forEach(hidden);
        view.preview=make("Panel",content,"LotteryGW2Preview"); place(view.preview,52,502,558,150); style(view.preview,{zIndex:"3"});
        view.previewCaption=label(view.preview,"LotteryGW2PreviewCaption","奖池珍藏",0,0,530,28,20,"#d7c69f");
        view.previewItems=make("Panel",view.preview,"LotteryGW2PreviewItems"); place(view.previewItems,0,34,558,116);
        art(p("LotteryCelestialFooter"),"","final_footer_divider_1",204,698,10,27);
        art(p("LotteryCelestialFooter"),"","final_footer_divider_2",366,698,11,27);
        var skip=p("LotterySkipAnimation");skip.Children().forEach(function(c){if(c.paneltype==="Label"){c.AddClass("LotteryGW2SkipLabel");place(c,48,0,130,38);}else c.visible=false;});
        surface(skip,"",[0,0,38,38],"#151c20c0");art(skip,"","final_skip_checkbox_frame",0,0,38,38);
        label(skip,"LotteryGW2SkipCheck","✓",1,0,36,38,30,"#f0db9e").AddClass("LotteryGW2SkipCheck");
        sidebar(); return view;
    }
    function sidebar() {
        if(!alive()||!view||!valid(view.sidebar))return;
        var signature=pools.map(function(pool){return String(pool.id)+":"+String(pool.display_name||pool.id);}).join("|");
        if(signature!==tabKey){view.sidebar.RemoveAndDeleteChildren();prune();view.tabs=[];tabKey=signature;
            pools.forEach(function(pool,index){
                var boxes=[[19,25,270,120],[23,164,266,126],[23,308,266,127],[23,453,266,128]],box=boxes[index]||[23,25+index*144,266,126];
                var id=String(pool.id),b=make("Button",view.sidebar,"LotteryGW2Pool_"+id,"LotteryGW2Pool"); place(b,box[0],box[1],box[2],box[3]); b.hittestchildren=false;
                var frame=make("Panel",b,"","LotteryGW2PoolSkin");place(frame,0,0,parseFloat(b.style.width),parseFloat(b.style.height));frame.hittest=false;frame.hittestchildren=false;
                style(frame,{padding:"0px",minWidth:"0px",minHeight:"0px",backgroundImage:'url("s2r://panorama/images/events/crownfall/buttons/tabs_background_png.vtex")',backgroundSize:"100% 100%",backgroundRepeat:"no-repeat",backgroundColor:"transparent",border:"0px",overflow:"clip"});
                var name=label(b,"",String(pool.display_name||id),index?18:22,[27,26,27,30][index]||26,232,44,31,"#e4d6bc");
                var state=label(b,"","",index?20:25,[68,75,76,78][index]||75,228,40,22,"#d0d0c5");
                b.SetPanelEvent("onactivate",function(){if(!canAct())return;hideTooltip();if(mode==="history")invoke("SelectHistoryPool",id);else invoke("SelectPool",id);});
                view.tabs.push({id:id,button:b,frame:frame,name:name,state:state});
            });
        }
        view.tabs.forEach(function(tab,index){var pool=pools[index]||{},on=tab.id===selected;tab.button.SetHasClass("Selected",on);style(tab.button,{backgroundImage:"none",backgroundColor:"transparent"});
            tab.state.text=pool.unlocked===false?"未解锁  "+number(pool.unlock_progress)+" / "+number(pool.unlock_required):String(pool.ticket_name||((pool.ticket_content_id==="special_lottery_ticket")?"金色抽奖券":""));
            style(tab.name,{color:on?"#ffdf94":"#e7ddc8",textShadow:"#000000aa 0px 1px 2px 1.0"});style(tab.state,{color:on?"#e6c990":"#b9ae96",textShadow:"#00000088 0px 1px 2px 1.0"});
        });
    }
    function number(raw) { if(raw===undefined||raw===null||raw==="")return "—";var n=Number(raw);return isFinite(n)&&n>=0?String(n):"—"; }
    function ticketIcon(node,pool) {
        var id=String(pool&&pool.ticket_content_id||""),poolId=String(pool&&pool.id||selected);
        if(!id)id=poolId==="dragon_knight"||poolId==="summer"?"special_lottery_ticket":"lottery_ticket";
        var resources=cfg.SurvivalItemResources,uri=resources&&resources.Resolve(id);
        style(node,{backgroundImage:uri?'url("'+uri+'")':"none",backgroundSize:"contain",backgroundPosition:"center",backgroundRepeat:"no-repeat",backgroundColor:"transparent",opacityMask:"none",washColor:"none",saturation:"1",brightness:"1",opacity:"1"});
    }
    function quantity(item) {var current=number(item&&item.owned_count),max=Number(item&&item.max_owned);return current+(current!=="—"&&isFinite(max)&&max>0?"/"+max:"");}
    function previews() {
        if(!alive()||!view||!valid(view.previewItems))return;
        var rows=snapshot&&snapshot.items,items=Array.isArray(rows)?rows:rows&&typeof rows==="object"?Object.keys(rows).map(function(k){return rows[k];}):[];
        var ranks={ur:5,ssr:4,sr:3,r:2,n:1};items=items.slice().sort(function(a,b){return (ranks[String(b.quality).toLowerCase()]||0)-(ranks[String(a.quality).toLowerCase()]||0);}).slice(0,4);
        var signature=String(snapshot&&snapshot.selected_pool_id)+":"+JSON.stringify(items);
        if(signature===previewKey)return;previewKey=signature;view.previewItems.RemoveAndDeleteChildren();prune();view.preview.visible=items.length>0;
        items.forEach(function(item,index){
            var tileWidth=88,b=make("Button",view.previewItems,"LotteryGW2Preview_"+index,"LotteryGW2PreviewCard");place(b,[0,136,273,410][index],0,133,116);b.hittestchildren=false;
            itemWell(b,22.5,0,tileWidth,88);var icon=cfg.SurvivalRewardPresentation&&cfg.SurvivalRewardPresentation.CreateIcon(b,item,"LotteryGW2PreviewIcon");if(icon){place(icon,23.5,1,tileWidth-2,86);fillItemIcon(icon,item);}
            var itemName=label(b,"",String(item.name||item.id||""),0,88,133,28,20,"#e4dcc9");style(itemName,{whiteSpace:"nowrap",textOverflow:"shrink",textShadow:"#000000 0px 1px 2px 1.0"});
            var cardWidth=parseFloat(b.style.width),cardHeight=parseFloat(b.style.height),rowWidth=parseFloat(view.previewItems.style.width),gap=4;
            place(b,(rowWidth-(cardWidth*items.length+gap*(items.length-1)))/2+index*(cardWidth+gap),0,cardWidth,cardHeight);
            var nameAt=String(itemName.style.position).split(" "),nameHeight=parseFloat(itemName.style.height),nameHost=make("Panel",b,"","LotteryGW2PreviewNameHost");
            place(nameHost,0,parseFloat(nameAt[1]),cardWidth,nameHeight);nameHost.hittest=false;nameHost.hittestchildren=false;
            itemName.SetParent(nameHost);place(itemName,0,0,cardWidth,nameHeight);
            style(itemName,{width:"fit-children",height:"fit-children",maxWidth:cardWidth+"px",horizontalAlign:"center",verticalAlign:"center",textAlign:"center"});
            if(icon){var hover=make("Panel",b,"","LotteryGW2PreviewHover"),at=String(icon.style.position).split(" ");place(hover,parseFloat(at[0]),parseFloat(at[1]),parseFloat(icon.style.width),parseFloat(icon.style.height));bindTooltipIcon(b,hover,item);}
            b.SetPanelEvent("onactivate",function(){hideTooltip();invoke("Feature","details");});
        });
    }
    function action(id,primary) {
        var b=p(id);if(!valid(b))return;b.AddClass("LotteryGW2Action");b.AddClass("LotteryGW2NativeButton");b.SetHasClass("LotteryGW2Primary",!!primary);style(b,{backgroundImage:"none",backgroundColor:"transparent",boxShadow:"none",flowChildren:"none",borderRadius:"0px",border:"0px",overflow:"clip"});
        var skins=view.actionSkins||(view.actionSkins={}),surface=skins[id];
        if(!valid(surface)){surface=skins[id]=make("Panel",b,"","LotteryGW2ButtonSurface");surface.hittest=false;surface.hittestchildren=false;var first=b.Children()[0];if(first!==surface&&b.MoveChildBefore)b.MoveChildBefore(surface,first);}
        place(surface,0,0,0,0);style(surface,{width:"100%",height:"100%",zIndex:"0",backgroundImage:"none",backgroundColor:primary?"gradient(linear, 0% 0%, 0% 100%, from(#ffe8ae), to(#c59c50))":"gradient(linear, 0% 0%, 0% 100%, from(#eee5cc), to(#b6aa8d))",border:"2px solid #d7bd83",borderTopColor:"#fff0c8",borderLeftColor:"#f4dfab",borderRightColor:"#9c804a",borderBottomColor:"#866b3d",boxShadow:"inset #fff7d740 0px 0px 2px 1px"});
        walk(b,function(n){if(n.paneltype==="Label")style(n,{color:b.enabled===false?"#77766c":"#30291b",textShadow:"none"});if(n.BHasClass("ZXActionSkin")||n.BHasClass("LHDrawVisual"))n.visible=false;});
        if(id==="LotterySingleButton"||id==="LotteryTenButton"){
            walk(b,function(n){if(n.BHasClass("LHDrawTicket"))ticketIcon(n,snapshot&&(snapshot.selected_pool||snapshot));});
            var width=parseFloat(b.style.width)||274,height=parseFloat(b.style.height)||80;
            walk(b,function(n){if(n.BHasClass("ZXDrawContent")){place(n,(width-206)/2,(height-42)/2,206,42);style(n,{flowChildren:"none"});}if(n.BHasClass("ZXDrawCost")){place(n,108,0,98,42);style(n,{flowChildren:"none"});}if(n.BHasClass("LHDrawTicket"))place(n,0,3,32,36);if(n.BHasClass("LHCost")){place(n,40,0,58,42);style(n,{fontSize:"30px",textAlign:"left"});}});
            var text=p(id==="LotterySingleButton"?"LotterySingleText":"LotteryTenText");place(text,0,0,96,42);style(text,{fontSize:"32px",textAlign:"center",whiteSpace:"nowrap",textOverflow:"shrink"});
        }
    }
    function compactCards(host,single) {
        if(!valid(host)||!ensure())return;
        (single?[single]:host.Children()).forEach(function(card,index){
            if(!card.BHasClass("LotteryDetailRow")&&!card.BHasClass("LotteryRewardCard"))return;
            if(single)index=host.Children().indexOf(card);
            var result=card.BHasClass("LotteryRewardCard"),item=card.__lotteryItem||{},cell=card.__lotteryGW2Cell,icon=null,name=null,cover=null;
            walk(card,function(c){if(c.BHasClass("LotteryRewardIcon"))icon=c;if(c.BHasClass("RHRewardName")||c.BHasClass("LotteryRewardName"))name=c;if(c.BHasClass("LotteryCardBack"))cover=c;});
            existingRewardArt(icon,item);
            if(!cell||!valid(cell.host)){
                var hostVisual=make("Panel",card,"","LotteryGW2CellVisual");place(hostVisual,0,0,134,168);hostVisual.hittest=false;hostVisual.hittestchildren=false;
                var well=itemWell(hostVisual,9,3,116,116),stage=make("Panel",well,"","LotteryGW2CellStage");place(stage,0,0,114,114);style(stage,{overflow:"clip"});
                var selectedFrame=make("Panel",hostVisual,"","LotteryGW2SelectedFrame");place(selectedFrame,9,3,116,116);style(selectedFrame,{border:"1px solid #e3cf95",backgroundColor:"transparent"});selectedFrame.hittest=false;
                if(icon){moveNode(icon,stage);place(icon,0,0,114,114);icon.visible=true;fillItemIcon(icon,item);}
                if(name)moveNode(name,hostVisual);else name=label(hostVisual,"","",0,123,134,39,17);
                place(name,0,123,134,39);style(name,{fontSize:"17px",fontWeight:"normal",fontFamily:'"Source Han Sans SC"',color:"#e0d6c3",textAlign:"center",whiteSpace:"normal",textOverflow:"ellipsis",textShadow:"none"});name.visible=true;
                var count=label(hostVisual,"","",13,88,106,24,16,"#f1e9d8");style(count,{textAlign:"right",textShadow:"#000000 0px 1px 3px 2.0"});
                cell=card.__lotteryGW2Cell={host:hostVisual,name:name,count:count,stage:stage};
            }
            card.Children().forEach(function(c){if(c!==cell.host&&c!==cover)c.visible=false;});card.AddClass("LotteryGW2Cell");
            place(card,result?(host.Children().length===1?488:52+(index%5)*212):5+(index%8)*137,result?10+Math.floor(index/5)*190:8+Math.floor(index/8)*178,134,168);
            style(card,{flowChildren:"none",backgroundImage:"none",backgroundColor:"transparent",border:"0px",boxShadow:"none",overflow:"noclip",transform:"none"});
            cell.name.text=String(item.name||item.id||cell.name.text||"道具");cell.count.text=result?"×"+number(item.count===undefined?(item.quantity===undefined?1:item.quantity):item.count):quantity(item);
            if(result)bindTooltipIcon(card,cell.stage,item);
            if(cover){place(cover,0,0,134,168);wellStyle(cover);style(cover,{zIndex:"20"});}
        });
    }
    function updateFooterSkin() {
        ["LotteryGW2FooterSkin","LotteryGW2FooterRule"].forEach(function(id){style(p(id),{visibility:mode==="details"?"collapse":"visible"});});
    }
    function apply() {
        if(!ensure())return;
        var window=p("LotteryWindow");if(!valid(window))return;
        var results=window.BHasClass("LotteryResultsShown"),drawVisible=!mode&&!results;
        style(window,{width:"100%",height:"100%",position:"0px 0px 0px",horizontalAlign:"left",verticalAlign:"top",margin:"0px",padding:"0px",backgroundImage:"none",backgroundColor:"#080908b8",border:"0px",borderRadius:"0px",boxShadow:"none",flowChildren:"none",transform:"none"});
        ["LotteryCelestialHeader","LotteryPoolTabs","LotteryReadingMask"].forEach(hidden);
        style(view.content,{visibility:mode?"collapse":"visible"});
        updateFooterSkin();
        place(p("LotterySceneBackground"),35,123,1608,746);style(p("LotterySceneBackground"),{opacity:"1",zIndex:"0",overflow:"clip"});
        if(cfg.LotterySceneTransition)cfg.LotterySceneTransition.Resize(1608,746);
        place(p("LotterySceneShade"),35,123,1608,746);style(p("LotterySceneShade"),{zIndex:"1",backgroundColor:"transparent"});
        place(p("LotteryHeroCopy"),693,70,580,290);style(p("LotteryHeroCopy"),{flowChildren:"none",zIndex:"3",visibility:drawVisible?"visible":"collapse"});
        place(p("LotteryTitle"),0,0,570,66);style(p("LotteryTitle"),{visibility:"visible",fontSize:"54px",fontWeight:"normal",color:"#f3e4c0",whiteSpace:"normal",textShadow:"#00000080 0px 1px 2px 1.0"});
        place(p("LotteryTaglineBounds"),10,70,560,120);place(p("LotteryTagline"),0,0,560,120);style(p("LotteryTagline"),{fontSize:"28px",minHeight:"0px",color:"#e0e2dd",transform:"none",whiteSpace:"normal",textShadow:"#00000080 0px 1px 2px 1.0"});
        var pool=snapshot&&(snapshot.selected_pool||snapshot);if(pool&&pool.description)p("LotteryTagline").text=String(pool.description);
        place(p("LotteryGuaranteeRow"),2,230,458,62);style(p("LotteryGuaranteeRow"),{flowChildren:"none",backgroundColor:"transparent",visibility:"collapse"});
        place(p("LotteryUnlockNotice"),703,260,560,70);style(p("LotteryUnlockNotice"),{fontSize:"22px",color:"#cfbfa0",whiteSpace:"normal",textShadow:"none",zIndex:"3",visibility:drawVisible?"visible":"collapse"});
        place(p("LotteryCelestialFooter"),334,123,1309,746);style(p("LotteryCelestialFooter"),{backgroundImage:"none",backgroundColor:"transparent",border:"0px",flowChildren:"none",zIndex:"4",visibility:drawVisible?"visible":"collapse",overflow:"noclip"});p("LotteryCelestialFooter").hittest=false;
        place(p("LotterySingleButton"),671,591,274,80);place(p("LotteryTenButton"),960,591,275,80);
        place(p("LotteryDrawPity"),670,542,555,39);place(p("LotteryDrawPityCaptionBounds"),0,0,555,39);place(p("LotteryDrawPityCaption"),0,0,555,39);style(p("LotteryDrawPityCaption"),{fontSize:"30px",minHeight:"0px",textAlign:"left",transform:"none",color:"#e1d6bc",textShadow:"none"});
        place(p("LHDetails"),82,692,100,38);place(p("LHHistory"),247,692,100,38);place(p("LotteryAnnouncement"),407,692,100,38);style(p("LotteryAnnouncement"),{visibility:"visible"});place(p("LotterySkipAnimation"),546,692,190,38);
        place(p("LotteryStatus"),671,480,564,58);style(p("LotteryStatus"),{fontSize:"20px",color:"#e4d8bb",whiteSpace:"normal",textShadow:"none",zIndex:"8"});
        ["LotteryTitle","LotteryTagline","LotteryUnlockNotice","LotteryDrawPityCaption"].forEach(function(id){style(p(id),{textShadow:"0px 0px 2px 3.0 #000000, 0px 1px 4px 2.0 #000000"});});
        ["LotteryTaglineBounds","LotteryDrawPityCaptionBounds"].forEach(function(id){style(p(id),{overflow:"noclip"});});
        ["LotterySingleButton","LotteryTenButton","LotteryAgain","LotteryConfirm"].forEach(function(id){action(id,id==="LotteryTenButton"||id==="LotteryAgain");});
        ["LotterySingleCost","LotteryTenCost"].forEach(function(id){style(p(id),{visibility:"visible"});});
        ["LHDetails","LHHistory","LotteryAnnouncement","LotteryGW2Back"].forEach(function(id){var b=p(id);if(valid(b))b.AddClass("LotteryGW2Action");});
        place(p("LotteryResultStage"),98,6,1113,669);style(p("LotteryResultStage"),{backgroundImage:"none",backgroundColor:"#161711f8",zIndex:"6",flowChildren:"none",border:"0px"});
        place(p("LotteryResultHeading"),18,13,1076,48);style(p("LotteryResultHeading"),{fontSize:"28px",color:"#efdbb2",textShadow:"none"});
        place(p("LotteryItemList"),8,75,1097,449);style(p("LotteryItemList"),{flowChildren:"none",overflow:"squish scroll"});
        place(p("LotteryResultActions"),0,573,1113,70);style(p("LotteryResultActions"),{flowChildren:"none"});place(p("LotteryConfirm"),292,0,240,55);place(p("LotteryAgain"),568,0,240,55);
        place(p("LotteryRevealStage"),98,6,1113,669);place(p("LotterySkipReveal"),1037,21,155,42);compactCards(p("LotteryItemList"));
        var film=p("LotteryCinematicSurface");if(valid(film)){moveNode(film,view.content);place(film,98,6,1113,669);}
        view.preview.style.visibility=drawVisible?"visible":"collapse";
        if(!mode)view.title.text="抽奖";
        view.ticket.text=number(pool&&pool.tickets);ticketIcon(view.ticketIcon,pool);
        fit();
    }
    // Preview is presentation only: cards retain the controller's click/hover bindings.
    function prizePreview(host,data) {
        var model=cfg.LotteryGW2Data&&cfg.LotteryGW2Data.preview;if(!valid(host)||!model)return;
        var cards=host.Children().filter(function(card){return card.BHasClass("LotteryDetailRow");});
        if(!cards.length)return;
        var pool=data&&(data.selected_pool||data)||{},poolId=String(data&&data.selected_pool_id||pool.id||selected);
        host.AddClass("LotteryGW2PrizeGroup");
        var groups=model.Groups(cards.map(function(card){return card.__lotteryItem||{};}),pool),lookup=[];
        cards.forEach(function(card){lookup.push({item:card.__lotteryItem,card:card});});
        // info() is called once before business cards exist and once after assembly.
        host.Children().forEach(function(node){if(node.BHasClass("LotteryGW2PrizeBar")||node.BHasClass("LotteryGW2PrizeGrid"))node.DeleteAsync(0);});
        prizeGroups=[];
        groups.forEach(function(group){
            var bar=make("Button",host,"","LotteryGW2PrizeBar"),grid=make("Panel",host,"","LotteryGW2PrizeGrid");bar.hittestchildren=false;grid.hittest=false;grid.hittestchildren=false;
            var name=label(bar,"",({n:"普通 N",r:"稀有 R",sr:"史诗 SR",ssr:"传说 SSR",ur:"至臻 UR"}[group.id]||group.label),14,5,134,26,20),odds=label(bar,"",group.percent===undefined?"单抽概率未公布":String(group.percent)+"%",148,6,300,25,18,"#d6ba79");
            var groupWidth=layout.info[2]-29;
            var total=label(bar,"",String(group.count)+" 种奖励",groupWidth-281,6,210,25,16,"#bdb5a2"),arrow=label(bar,"","▾",groupWidth-51,3,36,28,22,"#e0d5b6");style(total,{textAlign:"right"});style(arrow,{textAlign:"center"});
            var entries=[];group.items.forEach(function(item){var match=lookup.filter(function(row){return row.item===item;})[0];if(!match)return;lookup.splice(lookup.indexOf(match),1);var card=match.card,face=card.__lotteryPrizeFace;
                if(!face||!valid(face.host)){
                    var icon=null;walk(card,function(node){if(node.BHasClass("LotteryRewardIcon"))icon=node;});
                    var visual=make("Panel",card,"","LotteryGW2PrizeFace");place(visual,0,0,72,72);visual.hittest=false;visual.hittestchildren=false;
                    itemWell(visual,0,0,72,72);
                    if(icon){moveNode(icon,visual);place(icon,1,1,70,70);icon.visible=true;fillItemIcon(icon,item);}
                    var glow=make("Panel",visual,"","LotteryGW2PrizeSelected");place(glow,0,0,72,72);
                    var count=label(visual,"",model.Quantity(item),19,1,51,24,15,"#f3e9d3");count.AddClass("LotteryGW2PrizeOwned");style(count,{textAlign:"right"});
                    face=card.__lotteryPrizeFace={host:visual,count:count};
                }
                card.Children().forEach(function(child){child.visible=child===face.host;});face.count.text=model.Quantity(item);card.AddClass("LotteryGW2PrizeSlot");card.AddClass("LotteryQuality_"+String(item.quality||"n").toUpperCase());card.SetHasClass("LotteryGW2PrizeUnowned",model.Quantity(item).split("/")[0]==="0");
                style(card,{flowChildren:"none",backgroundImage:"none",backgroundColor:"transparent",border:"0px",boxShadow:"none",overflow:"noclip",transform:"none"});entries.push(card);
            });
            var entry={id:group.id,bar:bar,grid:grid,arrow:arrow,cards:entries,percent:group.percent,key:poolId+":"+group.id};prizeGroups.push(entry);
            bar.SetPanelEvent("onactivate",function(){if(!canAct())return;hideTooltip();prizeFolded[entry.key]=!prizeFolded[entry.key];layoutPrizeGroups();});
        });
        var rule=model.RuleText(pool);if(rule)p("LotteryInfoRules").text=rule;
        layoutPrizeGroups();prune();
    }
    function layoutPrizeGroups() {
        var y=8,width=layout.info[2]-29,columns=Math.max(1,Math.floor((layout.info[2]-48+8)/80));
        prizeGroups.forEach(function(group){if(!valid(group.bar))return;var closed=!!prizeFolded[group.key],rows=Math.ceil(group.cards.length/columns),height=closed?0:rows*80+10;
            place(group.bar,12,y,width,34);group.bar.SetHasClass("Collapsed",closed);group.arrow.text=closed?"▸":"▾";
            place(group.grid,12,y+34,width,height);group.grid.visible=!closed;
            group.cards.forEach(function(card,index){card.visible=!closed;place(card,24+(index%columns)*80,y+42+Math.floor(index/columns)*80,72,72);});
            y+=34+height+8;
        });
    }
    function info(name,options,data) {
        if(!ensure())return;hideTooltip();mode=name;updateFooterSkin();
        p("LotteryInfoList").SetHasClass("LotteryGW2PrizeGroup",name==="details");var win=options.panel;win.RemoveClass("LotteryInfoPurple");win.AddClass("LotteryInfoGW2");
        var bounds=layout.info,width=bounds[2],height=bounds[3],footerHeight=name==="details"?0:88,footerTop=height-footerHeight;
        place(p("LotteryInfoOverlay"),bounds[0],bounds[1],width,height);style(p("LotteryInfoOverlay"),{backgroundImage:"none",backgroundColor:name==="details"?"#211d17d9":"#161711f8",border:"0px",zIndex:"12",flowChildren:"none"});
        style(view.content,{visibility:"collapse"});place(win,0,0,width,height);style(win,{backgroundImage:"none",backgroundColor:"transparent",border:"0px",boxShadow:"none",transform:"none",flowChildren:"none",overflow:"clip"});
        ["LotteryInfoHeader","LotteryInfoTabs","LotteryPoolSelection","LotteryPoolGuarantee"].forEach(hidden);
        var hasNote=!!String(p("LotteryInfoNote")&&p("LotteryInfoNote").text||""),bodyTop=hasNote?64:18,bodyHeight=footerTop-bodyTop;
        place(p("LotteryInfoNote"),18,12,width-36,44);style(p("LotteryInfoNote"),{visibility:hasNote?"visible":"collapse",backgroundImage:"none",backgroundColor:"transparent",border:"0px",fontSize:"18px",color:"#b7c8c1",whiteSpace:"normal",textShadow:"none"});
        place(p("LotteryInfoBody"),0,bodyTop,width,bodyHeight);style(p("LotteryInfoBody"),{backgroundImage:"none",backgroundColor:"transparent",border:"0px",flowChildren:"none"});
        place(p("LotteryInfoList"),0,0,width,bodyHeight);style(p("LotteryInfoList"),{backgroundImage:"none",backgroundColor:"transparent",border:"0px",flowChildren:name==="details"||name==="update"?"none":"down",overflow:"squish scroll"});
        place(p("LotteryInfoFooter"),0,footerTop,width,footerHeight);style(p("LotteryInfoFooter"),{visibility:name==="details"?"collapse":"visible",backgroundImage:"none",backgroundColor:"transparent",border:"0px",flowChildren:"none"});
        p("LotteryInfoFooter").Children().forEach(function(c){if(c.paneltype==="Image")c.visible=false;});
        place(p("LotteryInfoRules"),18,0,width-237,84);style(p("LotteryInfoRules"),{fontSize:"17px",whiteSpace:"normal",color:"#b8b29f"});
        hidden("LotteryInfoConfirm");hidden("RHHistoryColumns");hidden("LotteryCelestialFooter");compactCards(p("LotteryInfoList"));
        if(name==="details")prizePreview(p("LotteryInfoList"),data);
        if(name==="history")p("LotteryInfoList").Children().forEach(function(row){if(row.BHasClass("RHHistoryRow")){
            style(row,{width:(width-23)+"px",backgroundImage:"none",border:"0px",borderBottom:"1px solid #504d3e"});
            row.Children().forEach(function(child){if(child.BHasClass("RHHistoryName"))style(child,{width:(width-653)+"px"});else if(child.BHasClass("RHHistoryQuality"))style(child,{position:(width-331)+"px 0px 0px"});else if(child.BHasClass("RHHistoryQuantity"))style(child,{position:(width-175)+"px 0px 0px"});});
        }});
        if(name==="reward")p("LotteryInfoList").Children().forEach(function(child){if(child.BHasClass("LotteryDetailIcon")){place(child,20,0,120,120);wellStyle(child);walk(child,function(n){if(n.BHasClass("LotteryRewardIcon")){place(n,0,0,118,118);fillItemIcon(n,n.__lotteryItem);}});}else if(child.BHasClass("LotteryDetailDescription"))place(child,20,136,width-40,bodyHeight-136);});
        var names={details:"奖池详情",history:"抽奖记录",announcement:"开奖公告",update:"奖励更新公告",reward:p("LotteryInfoTitle")&&p("LotteryInfoTitle").text||"奖励详情",firstgift:"首充礼包",privilege:"礼包特权"};view.title.text=names[name]||"功能提示";sidebar();
    }
    function tooltipRect(node) {var at=node.GetPositionWithinWindow();return {x:at.x,y:at.y,width:node.actuallayoutwidth*scale,height:node.actuallayoutheight*scale};}
    function raiseTooltip(){
        var canvas=p("LotteryMainCanvas");if(!valid(canvas))return;
        for(var branch=view.tooltip;valid(branch)&&branch!==canvas;branch=branch.GetParent()){
            var parent=branch.GetParent();if(!valid(parent))break;
            var above=0;parent.Children().forEach(function(sibling){if(sibling!==branch)above=Math.max(above,Number(sibling.style.zIndex)||0);});
            // Modal layers can re-raise a sibling after this view was built.
            style(branch,{zIndex:String(Math.max(Number(branch.style.zIndex)||0,above+1))});
        }
    }
    function cancelTooltipHide(){tipEpoch++;if(tipHideJob!==null&&$.CancelScheduled)$.CancelScheduled(tipHideJob);tipHideJob=null;}
    function tooltipOverflows(){return alive()&&view&&valid(view.tipDescription)&&valid(view.tipScroll)&&view.tipDescription.actuallayoutheight>view.tipScroll.actuallayoutheight+1;}
    function cursorInsideTooltipRegion(node){if(!valid(node)||!GameUI.GetCursorPosition)return false;var at=GameUI.GetCursorPosition(),box=tooltipRect(node);return at&&at[0]>=box.x&&at[0]<box.x+box.width&&at[1]>=box.y&&at[1]<box.y+box.height;}
    function hideTooltip() {cancelTooltipHide();if(view&&valid(view.tooltip))view.tooltip.visible=false;if(tipDismiss)tipDismiss.Hidden();}
    function tooltipGuard(){
        if(!tipDismiss)tipDismiss=cfg.SurvivalTooltipDismiss.Create({panel:view.tooltip,surface:view.tipSkin.surface,getRect:tooltipRect,hide:hideTooltip,allowTooltipHover:tooltipOverflows,isAlive:alive,isVisible:function(){return canAct()&&valid(view.tooltip)&&view.tooltip.visible;}});
        return tipDismiss;
    }
    function requestTooltipHide(sourceExit){
        if(!canAct()||!view||!valid(view.tooltip))return false;
        if(sourceExit&&sourceExit!==true&&tipAnchor&&sourceExit!==tipAnchor)return true;
        if(!view.tooltip.visible||!tooltipOverflows()){
            // Match the market: a genuine source exit rearms immediately,
            // including an exit/return before the geometry watcher's next tick.
            if(sourceExit!==false&&tipDismiss){tipDismiss.Dispose();tipDismiss=null;}
            return false;
        }
        cancelTooltipHide();var epoch=tipEpoch;
        tipHideJob=$.Schedule(.15,function(){if(!alive()||epoch!==tipEpoch)return;tipHideJob=null;if(cursorInsideTooltipRegion(tipAnchor)||cursorInsideTooltipRegion(view.tooltip))return;hideTooltip();});
        return true;
    }
    function effectLines(value) {
        var source=String(value||"").replace(/\r\n?/g,"\n"),out="",depth=0;
        var attribute=/^(?:英雄|箭塔|城墙|墙|伐木工?|金矿|地图等级|星悦积分|攻击|生命|护甲|金币|木材)[\u3400-\u9fffA-Za-z]{0,18}[+＋-]\s*\d/;
        for(var i=0;i<source.length;i++){
            var c=source.charAt(i),tail=source.slice(i),line=out.split("\n").pop();
            if(!depth){
                if(c===";"||c==="；"||c==="|"||c==="\n"){out+="\n";continue;}
                if((c===","||c==="，")&&!(c===","&&/\d/.test(source.charAt(i-1))&&/\d/.test(source.charAt(i+1)))
                    &&/[+＋-]|提高|增加|减少|获得/.test(line)){out+="\n";continue;}
                if(/[ \t]/.test(c)){
                    var next=i;while(next<source.length&&/[ \t]/.test(source.charAt(next)))next++;
                    var rest=source.slice(next);
                    if(/[0-9%％wW）)]$/.test(out)||attribute.test(rest)||/^(?:开局自带|获得英雄|购买后自动|获得后自动)/.test(rest)){
                        out+="\n";i=next-1;continue;
                    }
                }
                // Some recorded descriptions concatenate complete attributes.
                // Require the next attribute's own signed value, keeping prose
                // such as "额外增加4%英雄最终伤害" together.
                if(/[0-9%％wW]$/.test(out)&&(attribute.test(tail)||/^(?:获得英雄|在城墙处)/.test(tail)))out+="\n";
            }
            if(c==="("||c==="（"||c==="["||c==="【")depth++;
            if(c===")"||c==="）"||c==="]"||c==="】")depth=Math.max(0,depth-1);
            out+=c;
        }
        return out.split("\n").map(function(line){return line.trim();}).filter(function(line){return !!line;}).join("\n");
    }
    function tooltip(item,anchor) {
        if(!ensure()||!valid(anchor))return false;if(!canAct()){hideTooltip();return true;}
        if(tipAnchor&&tipAnchor!==anchor&&tipDismiss){tipDismiss.Dispose();tipDismiss=null;}
        if(!tooltipGuard().CanShow(anchor))return true;item=item||{};
        anchor.SetPanelEvent("onmouseout",function(){if(!requestTooltipHide(anchor))hideTooltip();});
        cancelTooltipHide();tipAnchor=anchor;if(view.tipScroll.ScrollToTop)view.tipScroll.ScrollToTop();
        var lines=[effectLines(item.description||"暂无效果说明")];if(item.duration_text)lines.push("期限："+item.duration_text);if(item.duplicate_points!==undefined&&item.duplicate_points!==null)lines.push("重复转化："+item.duplicate_points+" "+((item.converted_currency||item.duplicate_currency)==="shop_points"?"商城积分":"星悦积分"));
        if(item.count!==undefined||item.quantity!==undefined)lines.push("本次获得："+number(item.count===undefined?item.quantity:item.count));
        if(item.duplicate===true||Number(item.duplicate)===1)lines.push("本次已转化 "+number(item.converted_points)+" "+((item.converted_currency||item.duplicate_currency)==="shop_points"?"商城积分":"星悦积分"));
        view.tipIconStage.RemoveAndDeleteChildren();var tipIcon=cfg.SurvivalRewardPresentation.CreateIcon(view.tipIconStage,item,"LotteryGW2TooltipIcon");if(tipIcon){place(tipIcon,0,0,46,46);fillItemIcon(tipIcon,item);}prune();
        view.tipName.text=String(item.name||item.id||"道具");view.tipState.text=String(item.quality||"").toUpperCase()+(item.duration_text?" · "+item.duration_text:"");
        style(view.tipName,{color:cfg.SurvivalRewardPresentation.NameColor(item.quality)});view.tipDescription.text=lines.join("\n");view.tipCount.text="拥有 "+quantity(item);
        var lineCount=0;lines.join("\n").split("\n").forEach(function(line){lineCount+=Math.max(1,Math.ceil(line.length/17));});
        var h=Math.max(176,Math.min(704,145+lineCount*24));
        var cp=p("LotteryMainCanvas").GetPositionWithinWindow(),at=anchor.GetPositionWithinWindow(),sx=(p("LotteryMainCanvas").actualuiscale_x||1)*scale,sy=(p("LotteryMainCanvas").actualuiscale_y||1)*scale;
        var headerAt=String(view.header.style.position).split(" "),sidebarAt=String(view.sidebar.style.position).split(" "),left=parseFloat(headerAt[0]),right=left+parseFloat(view.header.style.width),top=parseFloat(headerAt[1]),bottom=parseFloat(sidebarAt[1])+parseFloat(view.sidebar.style.height);
        var x=(at.x-cp.x)/sx+(anchor.actuallayoutwidth||72)+12,y=(at.y-cp.y)/sy;if(x+368>right)x=(at.x-cp.x)/sx-380;x=Math.max(left,Math.min(right-368,x));y=Math.max(top,Math.min(bottom-h,y));
        var cursor=GameUI.GetCursorPosition&&GameUI.GetCursorPosition();
        if(cursor&&cursorInsideTooltipRegion(anchor)){
            var px=(cursor[0]-cp.x)/sx,py=(cursor[1]-cp.y)/sy;
            if(px>=x&&px<x+368&&py>=y&&py<y+h){
                if(px+12+368<=right)x=px+12;
                else if(px-368-12>=left)x=px-368-12;
                else y=py+12+h<=bottom?py+12:Math.max(top,py-h-12);
            }
        }
        place(view.tooltip,x,y,368,h);view.tipSkin.Resize(368,h);place(view.tipScroll,20,98,328,h-144);place(view.tipDescription,0,0,320,0);style(view.tipDescription,{height:"fit-children",ignoreParentFlow:"false"});place(view.tipCount,20,h-38,328,24);view.tooltip.visible=true;
        function syncTooltipInput(){if(!alive()||!view.tooltip.visible||tipAnchor!==anchor)return;raiseTooltip();var interactive=tooltipOverflows();[view.tooltip,view.tipSkin.surface,view.tipScroll].forEach(function(node){node.hittest=interactive;node.hittestchildren=interactive;});}
        syncTooltipInput();[0,.05,.2].forEach(function(delay){$.Schedule(delay,syncTooltipInput);});
        tipDismiss.Shown(anchor);return true;
    }
    var originalDialog=R&&R.LotteryDialog,originalReward=R&&R.RewardCard,presentation=cfg.SurvivalRewardPresentation,originalIcon=presentation&&presentation.CreateIcon;
    function iconWrapper(parent,item,className){var icon=originalIcon.call(presentation,parent,item,className);return alive()&&lotteryParent(parent)?existingRewardArt(icon,item):icon;}
    function dialogWrapper(name,options){info(name,options);}
    function rewardWrapper(card,item){card.__lotteryItem=item;if(originalReward)originalReward(card,item);compactCards(card.GetParent(),card);}
    if(R){R.LotteryDialog=dialogWrapper;R.RewardCard=rewardWrapper;}
    if(presentation&&originalIcon)presentation.CreateIcon=iconWrapper;
    cfg.SurvivalPurpleLottery={
        Version:"lottery_current_20261018",
        Owns:function(owner){return alive()&&owner===root;},
        IsReady:function(){return alive()&&!!view&&valid(view.root)&&valid(view.content)&&valid(view.header)&&cfg.LotteryGW2Data&&cfg.LotteryGW2Data.version===2;},
        Apply:apply,Info:info,Compact:compactCards,StyleTabs:function(){sidebar();},IsAlive:alive,
        Pools:function(rows,id){if(!alive())return;pools=rows||[];selected=String(id||"map");sidebar();},
        Snapshot:function(data){if(!alive())return;snapshot=data;previews();apply();},
        Open:function(){if(!alive())return;opened=true;mode="";apply();if(view&&valid(view.root))view.root.visible=true;},
        Close:function(){if(!alive())return;opened=false;mode="";hideTooltip();if(view&&valid(view.root))view.root.visible=false;},
        CloseInfo:function(){if(!alive())return;mode="";hideTooltip();apply();},
        Content:function(){return ensure()?view.content:null;},Fit:fit,Tooltip:tooltip,HideTooltip:hideTooltip,RequestTooltipHide:requestTooltipHide,
        Dispose:function(){
            if(disposed)return;hideTooltip();if(tipDismiss)tipDismiss.Dispose();
            // A replacement skin must finish assembling before this window can
            // open again. Never expose the original XML skin between lifetimes.
            var window=p("LotteryWindow");if(valid(window)){window.RemoveClass("LotteryOpen");window.RemoveClass("LotteryCurrentVersion");window.AddClass("LotteryClosed");}
            var legacyTooltip=p("LotteryItemTooltip");if(valid(legacyTooltip))legacyTooltip.AddClass("Hidden");
            if(R&&R.LotteryDialog===dialogWrapper)R.LotteryDialog=originalDialog;if(R&&R.RewardCard===rewardWrapper)R.RewardCard=originalReward;
            if(presentation&&presentation.CreateIcon===iconWrapper)presentation.CreateIcon=originalIcon;
            // Restore original business nodes before deleting any presentation hosts.
            moved.forEach(function(e){if(valid(e.node)&&valid(e.parent)){e.node.SetParent(e.parent);if(valid(e.next)&&e.next.GetParent()===e.parent&&e.parent.MoveChildBefore)e.parent.MoveChildBefore(e.node,e.next);}});moved=[];
            owned.slice().reverse().forEach(function(n){if(valid(n))n.DeleteAsync(0);});owned=[];
            if(valid(p("LotteryMainCanvas")))p("LotteryMainCanvas").RemoveClass("LotteryGW2");if(valid(p("LotteryWindow")))p("LotteryWindow").RemoveClass("LotteryGW2Root");view=null;disposed=true;if(valid(life))life.DeleteAsync(0);
        },
        Inspect:function(){return {alive:alive(),view:!!view,open:opened,mode:mode,pools:pools.length,poolIds:pools.map(function(pool){return String(pool.id);}),selected:selected,hasSnapshot:!!snapshot,canvas:layout.canvas.slice(),content:layout.content.slice(),movedCount:moved.filter(function(e){return valid(e.node);}).length,trackedOwned:owned.length,trackedMoved:moved.length,prizeGroups:prizeGroups.filter(function(g){return valid(g.bar);}).map(function(g){return {id:g.id,count:g.cards.length,percent:g.percent,collapsed:!!prizeFolded[g.key]};}),scale:scale};}
    };
    apply();
    if(cfg.SurvivalLottery&&cfg.SurvivalLottery.PresentationReady)cfg.SurvivalLottery.PresentationReady(cfg.SurvivalPurpleLottery);
})();
