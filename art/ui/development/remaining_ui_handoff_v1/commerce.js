(function(){
    "use strict";
    var cfg=GameUI.CustomUIConfig(),U=cfg.SurvivalUI,R=cfg.RemainingHandoff,root=$.GetContextPanel();
    // Display-only adapter. No catalogue, prices, QR or payment outcomes are synthesized.
    // No adapter is registered by this project yet; the existing gold/wood shop stays intact.
    if(cfg.SurvivalCommerceView&&cfg.SurvivalCommerceView.Dispose){try{cfg.SurvivalCommerceView.Dispose();}catch(e){if(String(e).indexOf("Underlying panel is deleted")<0)throw e;}}
    var adapter=null,catalog=null,mode="shop",product=null,quantity=1,channel=null,pending=false,order=null,disposed=false,requestSerial=0;
    function panel(t,parent,cls){var p=$.CreatePanel(t,parent,"");if(cls)p.AddClass(cls);return p;}
    function text(parent,value,cls){var p=panel("Label",parent,cls);p.text=String(value||"");p.hittest=false;return p;}
    function button(parent,title,action,primary){var b=U.ActionButton(parent,{label:title,action:action});R.Action(b,primary);return b;}
    function close(){purchase.shell.Close();store.shell.Close();}
    function modal(id,title,w,h){var scrim=panel("Button",root,"RCBackdrop"),p=panel("Panel",root,"RCWindow"),header=panel("Panel",p,"RCHeader"),heading=text(header,title,"RCTitle"),x=panel("Button",header,"RCClose");
        var shell=U.ModalShell.Adopt({id:id,root:root,panel:p,header:header,titlePanel:heading,scrim:scrim,closeButton:x,width:w,height:h,fit:{reference:[1672,941]},onClose:function(){shell.Close();}});
        R.Window(p,header,x);R.SizeWindow(p,w,h);R.Box(header,0,0,w,84);R.Box(x,w-66,22,38,38);shell.Close();return {panel:p,scrim:scrim,shell:shell,title:heading};
    }
    var store=modal("commerce", "商城",1210,810),purchase=modal("commerce_purchase","订单确认",960,640);
    var tabs=U.TabBar(store.panel,{items:[{id:"shop",label:"全部商品"},{id:"bundles",label:"礼包"}],selectedId:"shop",onChange:function(id){mode=id;renderCatalog();}});tabs.panel.AddClass("RCTabs");
    tabs.panel.Children().forEach(function(b,i){R.Tab(b,i===0?0:3);R.Image(b,"tab_glow","RCNavGlow");});
    var notice=text(store.panel,"","RCNotice"),grid=panel("Panel",store.panel,"RCGrid"),footer=text(store.panel,"","RCFooter");
    function rows(value){return Array.isArray(value)?value:[];}
    function validPrices(item){return rows(item&&item.prices).length>0&&item.prices.every(function(p){return typeof p.amount==="number"&&isFinite(p.amount)&&p.amount>=0&&!!p.currencyName;});}
    function canBuy(item){return !!(adapter&&typeof adapter.createOrder==="function"&&item&&item.id&&item.purchasable===true&&validPrices(item)&&!pending);}
    function art(parent,item,cls){var mapped=cfg.SurvivalItemArt&&cfg.SurvivalItemArt.Create(parent,item,cls);if(mapped)return mapped;if(item.artId&&U.ResourceInfo(item.artId).runtime)return U.Image(parent,item.artId,cls);if(item.image){var img=panel("Image",parent,cls);img.SetImage(item.image);img.SetScaling("stretch-to-fit-preserve-aspect");img.hittest=false;return img;}return text(parent,"物品图片待接入",cls+"Missing");}
    function renderCatalog(){
        tabs.Select(mode);grid.SetHasClass("RCBundles",mode==="bundles");grid.RemoveAndDeleteChildren();
        var items=rows(catalog&&(mode==="bundles"?catalog.bundles:catalog.products));
        notice.text=catalog?String(catalog.notice||""):"商品与支付接口尚未接入 · 当前仅验证交接组件";
        footer.text=catalog?String(catalog.balance_text||""):"";
        if(!items.length){for(var i=0;i<(mode==="bundles"?4:8);i++){var slot=U.CardShell(grid,{bodyVariant:"product"});slot.AddClass("RCProduct");slot.SetHasClass("RCFourth",i%4===3);slot.SetHasClass("RCSecond",i%2===1);R.Image(slot,mode==="bundles"?"shop_bundle_compact":"shop_card_normal_native","RCCardBase");text(slot,mode==="bundles"?"礼包配置待接入":"暂无商品配置","RCEmpty");}return;}
        items.forEach(function(item,index){
            var props={name:item.name||"名称待接入",prices:validPrices(item)?item.prices:[],bodyVariant:"product"};
            var c=mode==="bundles"?U.BundleCard(grid,props):U.ProductCard(grid,props);c.AddClass("RCProduct");c.SetHasClass("RCFourth",index%4===3);c.SetHasClass("RCSecond",index%2===1);
            R.Image(c,mode==="bundles"?"shop_bundle_compact":"shop_card_normal_native","RCCardBase");
            if(mode==="bundles"){
                var contents=panel("Panel",c,"RCBundleContents");rows(item.items).forEach(function(entry){var slot=panel("Panel",contents,"RCBundleItem");art(slot,entry,"RCBundleArt");text(slot,entry.name||"名称待接入","RCBundleName");if(entry.quantity!==undefined)text(slot,"×"+entry.quantity,"RCBundleQuantity");U.Tooltip.Bind(slot,{title:entry.name,body:entry.effect||"效果待接入"});});
                var buy=button(c,"立即购买",function(){openPurchase(item);},true);buy.AddClass("RCBundleBuy");U.State.Set(buy,{enabled:canBuy(item)});
            }else{
                art(c,item,"RCProductArt");R.Image(c,"shop_card_hover_native","RCCardHover");
                var hover=panel("Panel",c,"RCProductHover");R.Image(hover,"shop_product_hover_scrim","RCHoverScrim");text(hover,item.effect||"效果说明待接入","RCProductEffect");
                var buy=button(hover,"立即购买",function(){openPurchase(item);},true);buy.AddClass("RCProductBuy");U.State.Set(buy,{enabled:canBuy(item)});
            }
        });
    }
    var body=panel("Panel",purchase.panel,"RCOrderBody"),status=text(purchase.panel,"","RCOrderStatus");
    function openPurchase(item){if(pending){purchase.shell.Open();return;}product=item||null;quantity=item&&Number(item.min_quantity)>0?Number(item.min_quantity):1;channel=null;order=null;renderPurchase();purchase.shell.Open();}
    function createOrder(){if(!canBuy(product)||!channel)return;pending=true;renderPurchase();var serial=++requestSerial,settled=false,request={product_id:product.id,quantity:quantity,payment_method_id:channel.id};
        try{adapter.createOrder(request,function(response){if(disposed||settled||serial!==requestSerial)return;settled=true;if(!response||!response.order_id){pending=false;renderPurchase();status.text=response&&response.error||"订单未建立，请重试";return;}order=response;pending=["complete","expired","failed"].indexOf(order.status)<0;renderPurchase();});}catch(e){if(settled)return;settled=true;pending=false;renderPurchase();status.text="订单请求未完成";}
    }
    function renderPurchase(){
        body.RemoveAndDeleteChildren();purchase.title.text=order&&order.qr_image?"扫码支付":"订单确认";
        if(!product){text(body,"商品与订单接口待接入","RCOrderName");text(body,"金额、支付方式及二维码由现有服务端返回后显示。","RCOrderHint");var unavailable=button(body,"暂不可购买",function(){},true);unavailable.AddClass("RCOrderConfirm");U.State.Set(unavailable,{enabled:false});status.text="尚未创建订单，不会扣款或发放奖励";return;}
        text(body,product.name||"名称待接入","RCOrderName");
        U.PriceLabel(body,{prices:validPrices(product)?product.prices:[]}).AddClass("RCOrderPrice");
        if(!order){
            text(body,product.effect||"","RCOrderHint");var quantityRow=panel("Panel",body,"RCQuantity");
            var minus=button(quantityRow,"−",function(){quantity--;renderPurchase();});text(quantityRow,String(quantity),"RCQuantityText");var plus=button(quantityRow,"+",function(){quantity++;renderPurchase();});
            U.State.Set(minus,{enabled:!pending&&typeof product.min_quantity==="number"&&quantity>product.min_quantity});U.State.Set(plus,{enabled:!pending&&typeof product.max_quantity==="number"&&quantity<product.max_quantity});
            var methods=panel("Panel",body,"RCMethods");rows(product.payment_methods).forEach(function(method){var b=panel("Button",methods,"RCMethod");R.Image(b,"shop_payment_normal","RCMethodBase");var selected=R.Image(b,"shop_payment_selected","RCMethodSelected");selected.visible=!!channel&&channel.id===method.id;text(b,method.name||method.id,"RCMethodText");U.State.Bind(b,function(){channel=method;renderPurchase();});U.State.Set(b,{enabled:!pending&&method.enabled===true});});
            var buy=button(body,pending?"订单处理中…":"确认购买",createOrder,true);buy.AddClass("RCOrderConfirm");U.State.Set(buy,{enabled:canBuy(product)&&!!channel,busy:pending});status.text=pending?"正在等待服务器订单，请勿重复提交":"金额与支付方式以服务器最终订单为准";
        }else{
            text(body,order.amount_text||"金额待服务器确认","RCActualAmount");text(body,order.payment_name||"支付方式待确认","RCOrderHint");
            var qr=panel("Panel",body,"RCQR");R.Image(qr,"shop_qr_outer","RCQRFrame");
            if(["expired","failed","complete"].indexOf(order.status)>=0){text(qr,{expired:"二维码已失效",failed:"支付未完成",complete:"支付已完成"}[order.status],"RCQRState");}else if(order.qr_image){var image=panel("Image",qr,"RCQRCode");image.SetImage(order.qr_image);image.SetScaling("stretch-to-fit-preserve-aspect");image.hittest=false;}else R.Image(qr,"shop_qr_loading","RCQRCode");
            var states={pending:"等待支付",processing:"支付处理中",expired:"订单已过期",failed:"支付失败",complete:"支付完成"};status.text=(states[order.status]||"正在查询订单状态")+" · "+order.order_id+(order.error?" · "+order.error:"");
            text(body,order.expires_text||"","RCExpiry");
        }
    }
    cfg.SurvivalCommerceView={
        SetAdapter:function(value){adapter=value||null;},
        SetCatalog:function(value){catalog=value||null;renderCatalog();},
        UpdateOrder:function(value){if(!order||!value||value.order_id!==order.order_id)return;if(["complete","expired"].indexOf(order.status)>=0)return;if(Number(order.sequence)>0&&!(Number(value.sequence)>Number(order.sequence)))return;order=value;pending=["complete","expired","failed"].indexOf(order.status)<0;renderPurchase();},
        Open:function(page){mode=page==="bundles"?"bundles":"shop";renderCatalog();store.shell.Open();if(page==="purchase")openPurchase(null);},
        Close:close,
        Dispose:function(){if(disposed)return;disposed=true;purchase.shell.Dispose();store.shell.Dispose();[purchase.panel,store.panel,purchase.scrim,store.scrim].forEach(function(p){if(p&&p.IsValid())p.DeleteAsync(0);});}
    };
})();
