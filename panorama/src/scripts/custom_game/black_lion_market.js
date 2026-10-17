(function () {
    "use strict";
    var cfg=GameUI.CustomUIConfig(),U=cfg.SurvivalUI,M={},lastWindow=null;
    function valid(p){return p&&(!p.IsValid||p.IsValid());}
    function make(type,parent,id,cls){var p=$.CreatePanel(type,parent,id||"");(cls||"").split(/\s+/).filter(Boolean).forEach(function(c){p.AddClass(c);});return p;}
    function box(p,x,y,w,h){p.style.position=x+"px "+y+"px 0px";p.style.width=w+"px";p.style.height=h+"px";return p;}
    function label(parent,value,cls){var p=make("Label",parent,"",cls);p.text=String(value===undefined?"":value);p.hittest=false;return p;}
    function image(parent,path,cls){var p=make("Image",parent,"",cls);var resolver=cfg.SurvivalCommerceComponents,uri=resolver&&resolver.NormalizeIconURI?resolver.NormalizeIconURI(path):"";if(uri)p.SetImage(uri);if(p.SetScaling)p.SetScaling("stretch-to-fit-preserve-aspect");p.hittest=false;return p;}
    function currencyIcon(currency){return currency==="shop_points"?"custom_game/commerce_jade_v1/crystal.png":currency==="shop_gold"?"custom_game/hud_resources_v2/gold.svg":"custom_game/commerce_jade_v1/coin.png";}
    // Nine independent clips retain the original border corners. Only the plain
    // texture center stretches; no reference screenshot or baked text is used.
    function texture(parent,w,h){
        var layer=box(make("Panel",parent,"","BLMarketTexture"),0,0,w,h);layer.style.backgroundImage="none";layer.hittest=false;layer.hittestchildren=false;
        var sw=1536,sh=864,e=28,sx=[0,e,sw-e],sy=[0,e,sh-e],sourceW=[e,sw-e*2,e],sourceH=[e,sh-e*2,e];
        var dx=[0,e,w-e],dy=[0,e,h-e],targetW=[e,w-e*2,e],targetH=[e,h-e*2,e];
        for(var r=0;r<3;r++)for(var c=0;c<3;c++){
            var tile=box(make("Panel",layer,"","BLMarketTextureTile"),dx[c],dy[r],targetW[c],targetH[r]);tile.style.overflow="clip";tile.hittest=false;
            var art=image(tile,"custom_game/lottery_gw2_v1/window_background.png","");var xs=targetW[c]/sourceW[c],ys=targetH[r]/sourceH[r];
            box(art,-sx[c]*xs,-sy[r]*ys,sw*xs,sh*ys);art.SetScaling("stretch-to-fit");
        }
        return layer;
    }
    M.Window=function(root,onClose){
        var scrim=make("Button",root,"","BLMarketBackdrop"),p=make("Panel",root,"BlackLionMarketWindow","BLMarketWindow");
        var canvas=box(make("Panel",p,"","BLMarketCanvas"),0,0,1120,790);canvas.hittestchildren=true;
        texture(canvas,1120,790);
        var header=box(make("Panel",canvas,"","BLMarketHeader"),0,0,1120,68);
        label(header,"商城","BLMarketTitle");
        var balance=make("Panel",header,"","BLMarketBalance"),balanceLabels=[];
        ["U币","积分","商城金币"].forEach(function(name,i){var group=make("Panel",balance,"","BLMarketBalanceItem");if(i===2)group.style.marginRight="0px";image(group,currencyIcon(["u_coin","shop_points","shop_gold"][i]),"BLMarketCurrencyIcon");balanceLabels.push(label(group,name+" —",""));});
        var close=box(make("Button",canvas,"","BLMarketClose"),1066,15,34,34);close.hittestchildren=false;
        var shell=U.ModalShell.Adopt({id:"commerce",panel:p,root:root,scrim:scrim,closeButton:close,width:1120,height:790,fit:{widthFraction:.93,heightFraction:.88},onFit:function(scale){var w=(root.actuallayoutwidth||1672)/(root.actualuiscale_x||1),h=(root.actuallayoutheight||941)/(root.actualuiscale_y||1);p.style.horizontalAlign="left";p.style.verticalAlign="top";p.style.transformOrigin="0% 0%";var pos=Number(((w-1120*scale)/2).toFixed(3))+"px "+Number(((h-790*scale)/2).toFixed(3))+"px 0px";if(String(p.style.position)!==pos)p.style.position=pos;},onClose:onClose});
        p.style.backgroundColor="#18201adf";p.style.border="0px";p.style.backgroundImage="none";
        scrim.style.backgroundColor="#00000070";
        // Use the same project close glyph, independently of the old archive shell.
        close.Children().forEach(function(child){child.visible=false;});box(image(close,"custom_game/daily_gw2_v1/close.png",""),0,0,34,34);
        var tabs=box(make("Panel",canvas,"BlackLionMarketTabs","BLMarketTabs"),24,74,1072,46);
        var headings=box(make("Panel",canvas,"","BLMarketColumnHead"),24,129,1072,34);
        [["物品",82,156],["价格",744,178],["",932,124]].forEach(function(v){box(label(headings,v[0],""),v[1],0,v[2],28);});
        box(label(headings,"显示类型","BLMarketFilterCaption"),250,0,84,28);
        var typeButton=box(make("Button",headings,"BLMarketPurchaseType","BLMarketPurchaseType"),338,0,180,30);
        var typeLabel=label(typeButton,"全部","BLMarketPurchaseTypeText");label(typeButton,"▾","BLMarketPurchaseTypeArrow");
        var typeLayer=box(make("Panel",canvas,"","BLMarketPurchaseTypeLayer"),0,0,1120,790);typeLayer.hittest=false;typeLayer.hittestchildren=true;typeLayer.visible=false;
        var typeDismiss=box(make("Button",typeLayer,"BLMarketPurchaseTypeDismiss","BLMarketPurchaseTypeDismiss"),0,0,1120,790);typeDismiss.hittestchildren=false;
        var typeMenu=box(make("Panel",typeLayer,"BLMarketPurchaseTypeMenu","BLMarketPurchaseTypeMenu"),362,159,180,128),typeButtons={},typeCallback=null;
        var typeOptions=cfg.SurvivalBlackLionMarketModel.PurchaseTypes();
        function hideTypeMenu(){typeLayer.visible=false;}
        typeOptions.forEach(function(option){
            var button=make("Button",typeMenu,"BLMarketPurchaseType_"+option.id,"BLMarketPurchaseTypeOption");button.hittestchildren=false;
            label(button,option.label,"");typeButtons[option.id]=button;
            button.SetPanelEvent("onactivate",function(){hideTypeMenu();if(typeCallback)typeCallback(option.id);});
        });
        typeButton.hittestchildren=false;typeButton.SetPanelEvent("onactivate",function(){typeLayer.visible=!typeLayer.visible;});
        typeDismiss.SetPanelEvent("onactivate",hideTypeMenu);
        var content=box(make("Panel",canvas,"BlackLionMarketList","BLMarketList"),24,164,1072,564);content.hittestchildren=true;
        var actions=box(make("Panel",canvas,"","BLMarketFooter"),24,752,1072,30);
        var details=box(make("Panel",canvas,"","BLMarketDetailLayer"),0,0,1120,790);details.style.overflow="noclip";details.style.zIndex="50";details.hittest=false;details.hittestchildren=true;
        var menu={panel:p,shell:shell,canvas:canvas,content:content,actions:actions,detailLayer:details,sidebar:tabs,
            Open:function(){shell.Open();},Close:function(){hideTypeMenu();shell.Close();},Dispose:function(){hideTypeMenu();shell.Dispose();},
            SetPurchaseType:function(value,select){typeCallback=select;typeOptions.forEach(function(option){var chosen=option.id===value;typeButtons[option.id].SetHasClass("UISelected",chosen);if(chosen)typeLabel.text=option.label;});},
            IsOpen:function(){return shell.IsOpen();},Scale:function(){var w=(root.actuallayoutwidth||1672)/(root.actualuiscale_x||1),h=(root.actuallayoutheight||941)/(root.actualuiscale_y||1);return Math.min(w*.93/1120,h*.88/790);},
            SetSidebar:function(groups,selected,select){tabs.RemoveAndDeleteChildren();groups.forEach(function(group){
                var b=make("Button",tabs,"BLMarketSection_"+group.id,"RCTab BLMarketTab");b.hittestchildren=false;b.SetHasClass("UISelected",selected===group.id);
                var caption=label(b,group.label,"RCTabText");
                // Keep the five tabs independent of the legacy sidebar label rules.
                caption.style.width="fit-children";caption.style.maxWidth="100%";caption.style.height="fit-children";caption.style.margin="0px";caption.style.padding="0px";
                caption.style.horizontalAlign="center";caption.style.verticalAlign="center";caption.style.textAlign="center";
                b.SetPanelEvent("onactivate",function(){select(group.id);});
            });},
            SetResources:function(resources){resources.forEach(function(r,i){if(!balanceLabels[i])return;var value=r.value===undefined||r.value===null?"—":String(r.value);var next=r.name+" "+value;if(balanceLabels[i].text!==next)balanceLabels[i].text=next;});},
            DecorateCell:function(){},layout:"black_lion_list",width:1120,height:790};
        shell.Close();lastWindow=menu;return {panel:p,scrim:scrim,shell:shell,menu:menu,canvas:canvas,content:content,actions:actions,detailLayer:details};
    };
    M.SkinTooltip=function(tip){tip.AddClass("BLMarketDetail");var surface=make("Panel",tip,"","BLMarketDetailSurface");surface.hittest=false;return {surface:surface,Resize:function(w,h){box(surface,0,0,w,h);}};};
    // Local video placeholders are presentation only, with no product identity.
    function homeUnavailableRow(parent,item){
        var row=make("Panel",parent,"","BLMarketRow BLMarketHomeUnavailable");
        row.style.width="1072px";row.style.minWidth="1072px";row.style.height="64px";row.style.minHeight="64px";
        row.style.margin="0px";row.style.padding="0px";row.hittest=true;row.hittestchildren=false;
        var well=box(make("Panel",row,"","BLMarketArt"),8,8,48,48);well.hittest=false;
        var glyph=box(label(well,"?","BLMarketUnavailableIcon"),0,0,48,48);
        glyph.style.textAlign="center";glyph.style.fontSize="30px";glyph.style.color="#9d9b8c";
        var name=box(label(row,item.title,"BLMarketName"),82,17,628,30);
        var state=box(label(row,"未开放","BLMarketUnavailableState"),744,17,178,30);state.style.color="#aaa89a";
        row.__menuCell={iconPanel:well,namePanel:name,countPanel:null};
        row.SetPanelEvent("onmouseover",function(){if(valid(row))$.DispatchEvent("DOTAShowTextTooltip",row,item.description);});
        row.SetPanelEvent("onmouseout",function(){$.DispatchEvent("DOTAHideTextTooltip",row);});
        return row;
    }
    M.Row=function(parent,item,props){
        if(item&&item.home_unavailable===true)return homeUnavailableRow(parent,item);
        var J=cfg.SurvivalCommerceComponents,K=cfg.SurvivalBlackLionMarketModel,row=make("Panel",parent,"","RCProduct BLMarketRow");
        row.AddClass(item.product_type==="bundle"?"CJBundle":"CJProduct");row.SetHasClass("BLMarketOdd",!!(props.index%2));row.hittest=true;row.hittestchildren=true;row.style.width="1072px";row.style.minWidth="1072px";row.style.margin="0px";row.style.padding="0px";row.style.height="64px";row.style.minHeight="64px";
        var well=box(make("Panel",row,"","BLMarketArt"),8,8,48,48),icon=J.ItemIcon(well,item,"",{width:48,height:48});icon.style.width="100%";icon.style.height="100%";icon.style.margin="0px";icon.style.padding="0px";well.style.overflow="clip";
        var name=box(label(row,String(item.title||item.sku||"").replace(/\s*[·•]\s*永久\s*$/,""),"BLMarketName"),82,Number(item.owned)>0?8:17,628,30);
        var owned=box(label(row,Number(item.owned)>0?"已拥有 "+item.owned:"","BLMarketOwned"),82,40,628,18);owned.visible=Number(item.owned)>0;
        var price=box(make("Panel",row,"","BLMarketRowPrice"),744,7,178,52),primary="价格待同步",secondary="";
        var cost=item.price,isU=item.currency==="u_coin"||item.u_coin_price!==undefined||item.u_coin_per_yuan!==undefined;
        if(item.purchase_method==="wallet"&&typeof cost==="number"&&isFinite(cost)&&cost>=0)primary=cost+" "+(item.currency_name||"");
        else if(isU){var coin=item.u_coin_price,fen=item.amount_fen,validPrice=typeof coin==="number"&&coin>0&&coin%1===0&&item.u_coin_per_yuan===1000&&typeof fen==="number"&&fen>0&&fen<=1000000&&fen%1===0&&coin===fen*10;
            if(validPrice){primary=coin+" U币";secondary="¥"+(fen/100).toFixed(2);}else secondary="直购价格待同步";
        }else if(typeof item.amount_fen==="number"&&isFinite(item.amount_fen)&&item.amount_fen>0)primary="¥"+(item.amount_fen/100).toFixed(2);
        var currencyArt=image(price,currencyIcon(item.currency),"");box(currencyArt,0,3,22,22);
        box(label(price,primary,"BLMarketPriceMain"),27,0,151,28);var secondaryLabel=box(label(price,secondary,"BLMarketPriceSecondary"),27,31,151,20);secondaryLabel.visible=!!secondary;
        var available=K.IsActionable?K.IsActionable(item):item.enabled===true||item.enabled===1;
        var reason=K.DisabledMessage?K.DisabledMessage(item):String(item.disabled_message||"");
        if(item.purchase_method==="wallet"&&item.currency==="shop_points"
            &&(item.disabled_reason==="commerce_balance_insufficient"||item.disabled_reason==="insufficient_balance"))reason="";
        if(!available&&!reason)reason="未满足购买条件";
        var hasReason=!!reason,rowHeight=hasReason?82:64;
        row.style.height=rowHeight+"px";row.style.minHeight=rowHeight+"px";row.SetHasClass("BLMarketHasReason",hasReason);
        var buy=box(make("Button",row,"","BLMarketBuy"),932,hasReason?6:14,124,36);buy.hittestchildren=false;
        var buyText=label(buy,available?(item.purchase_method==="wallet"?"兑换":"购买"):"暂不可购","BLMarketBuyText");
        // RCProduct/Label rules from other menus must not move this button caption.
        buyText.style.width="fit-children";buyText.style.maxWidth="100%";buyText.style.height="fit-children";buyText.style.margin="0px";buyText.style.padding="0px";
        buyText.style.horizontalAlign="center";buyText.style.verticalAlign="center";buyText.style.textAlign="center";buyText.style.color=available?"#282518":"#c4c7ba";buyText.style.fontSize="18px";
        var reasonText=box(label(row,reason,"BLMarketDisabledReason"),928,45,132,32);reasonText.visible=hasReason;
        buy.enabled=available;buy.SetHasClass("UIDisabled",!available);buy.SetPanelEvent("onactivate",function(){if(valid(row)&&buy.enabled&&props.action){props.action();return true;}});
        row.__menuCell={iconPanel:well,namePanel:name,countPanel:owned};
        props.market=true;props.sourcePanel=well;props.sourceWidth=48;props.windowWidth=1120;props.windowHeight=790;
        J.BindDetail(row,item,props,item.product_type==="bundle");return row;
    };
    M.GetWindow=function(){return lastWindow;};cfg.SurvivalBlackLionMarket=M;
})();
