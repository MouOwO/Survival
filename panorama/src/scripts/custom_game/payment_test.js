var PaymentToggle, PaymentBuy, PaymentOpen, PaymentRefresh;
(function(){
    "use strict";
    var order=null,busy=false,opened=false,timer=null,lastMatrix="";
    var entry=$("#PaymentEntry"),dialog=$("#PaymentDialog"),status=$("#PaymentStatus"),buy=$("#PaymentBuy");
    function request(action){GameEvents.SendCustomGameEventToServer("survival_payment_request",{action:action});}
    function validURL(url){return typeof url==="string" && /^https:\/\/pay\.xiaofengnet\.com\/checkout\?order=WX[0-9a-f]{30}&token=[0-9a-f]{64}$/.test(url);}
    function setBusy(value){busy=value;buy.enabled=!value;}
    function open(){if(order&&validURL(order.checkout_url))$.DispatchEvent("ExternalBrowserGoToURL",order.checkout_url);}
    function drawQR(matrix){
        var parent=$("#PaymentQR");
        if(typeof matrix!=="string"||!/^[01|]+$/.test(matrix)){parent.style.visibility="collapse";return;}
        var rows=matrix.split("|"),size=rows.length;
        if(size<29||size>65||rows.some(function(row){return row.length!==size;})){parent.style.visibility="collapse";return;}
        parent.style.visibility="visible";
        if(lastMatrix===matrix)return;
        lastMatrix=matrix;parent.RemoveAndDeleteChildren();
        var cell=Math.max(4,Math.floor(260/size));parent.style.width=(size*cell)+"px";parent.style.height=(size*cell)+"px";
        rows.forEach(function(bits){
            var row=$.CreatePanel("Panel",parent,"");row.AddClass("PaymentQRRow");row.style.height=cell+"px";
            for(var start=0;start<size;){var end=start+1;while(end<size&&bits[end]===bits[start])end++;
                var run=$.CreatePanel("Panel",row,"");run.style.width=((end-start)*cell)+"px";run.style.height=cell+"px";run.style.backgroundColor=bits[start]==="1"?"#000000":"#ffffff";start=end;}
        });
    }
    function poll(){timer=null;if(order&&["created","pending"].indexOf(order.state)>=0){request("status");timer=$.Schedule(5,poll);}}
    function catalog(){request("catalog");$.Schedule(20,catalog);}
    PaymentToggle=function(){opened=!opened;dialog.SetHasClass("Open",opened);if(opened)request("catalog");};
    PaymentBuy=function(){if(busy)return;setBusy(true);status.text="正在创建微信订单…";request("create");$.Schedule(32,function(){if(busy){setBusy(false);status.text="查询超时，请重试。重复点击会查询同一笔未完成订单。";}});};
    PaymentOpen=open;
    PaymentRefresh=function(){request(order?"status":"catalog");};
    var messages={test_account_required:"此商品仅对指定测试账号开放。",already_owned:"你已经拥有齐天大圣，无需再次购买。",profile_not_ready:"请先进入对局，等待存档加载完成。",match_session_missing:"请先完成本局登录，再打开支付。",reward_refresh_pending:"付款已成功，存档刷新中；请稍后查询或重新进入游戏。",payment_not_configured:"游戏服务端尚未配置支付连接。",APPID_MCHID_NOT_MATCH:"微信 APPID 与商户号尚未完成绑定。",NO_AUTH:"微信商户尚未取得此支付接口权限。"};
    GameEvents.Subscribe("survival_payment_result",function(data){
        if($.Msg && data.action==="create")$.Msg("[PaymentUI] create_result ok="+data.ok+" state="+(data.state||"")+" error="+(data.error||""));
        if(!data.ok){if(data.action==="create")setBusy(false);if(data.error==="test_account_required")entry.style.visibility="collapse";if(opened)status.text=messages[data.error]||"暂时无法完成请求，请稍后重试。";return;}
        entry.style.visibility="visible";
        if(data.action==="catalog"){if(!order){buy.enabled=!!data.enabled;if(data.owned>0)status.text="你已经拥有齐天大圣，无需再次购买。";}return;}
        setBusy(false);order=data;
        var labels={created:"订单正在确认，请稍后重试。",pending:"使用手机微信扫一扫上方二维码，到账后自动发奖。",delivered:"支付成功：齐天大圣 ×1 已写入存档并完成刷新。",paid_review:"已收到付款，但你已经拥有奖励。请保留订单号联系开发者处理退款。",closed:"订单已关闭，可以重新下单。"};
        status.text=labels[data.state]||"正在确认支付结果…";
        buy.enabled=data.state==="created"||data.state==="closed";
        $("#PaymentRefresh").style.visibility="visible";
        var canOpen=data.state==="pending"&&!data.expired&&validURL(data.checkout_url);
        $("#PaymentOpen").style.visibility=canOpen?"visible":"collapse";
        $("#PaymentLink").style.visibility=canOpen?"visible":"collapse";
        if(canOpen)$("#PaymentLink").text=data.checkout_url;
        drawQR(canOpen?data.qr_matrix:null);
        if(timer!==null){$.CancelScheduled(timer);timer=null;}
        if(["created","pending"].indexOf(data.state)>=0)timer=$.Schedule(5,poll);
        if(data.action==="create"){opened=true;dialog.SetHasClass("Open",true);}
    });
    GameEvents.Subscribe("survival_payment_open",function(){opened=true;dialog.SetHasClass("Open",true);request(order?"status":"catalog");});
    $.Schedule(5,catalog);
}());
