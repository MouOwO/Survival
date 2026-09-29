var PaymentToggle, PaymentBuy, PaymentOpen, PaymentRefresh;
(function () {
    "use strict";
    var cfg = GameUI.CustomUIConfig(), disposed = false, subscriptions = [];
    if (cfg.SurvivalPayments && cfg.SurvivalPayments.Dispose) cfg.SurvivalPayments.Dispose();
    var products = [], selected = "", orders = {}, busy = false, opened = false, generation = 0, lastMatrix = "", ticks = 0;
    var entry = $("#PaymentEntry"), dialog = $("#PaymentDialog"), status = $("#PaymentStatus"), buy = $("#PaymentBuy");
    function rows(value) {
        if (Array.isArray(value)) return value;
        return Object.keys(value || {}).sort(function(a,b){return Number(a)-Number(b);}).map(function(key){return value[key];});
    }
    function current() { return products.filter(function(p){return p.sku === selected;})[0]; }
    function money(fen) { return "¥" + (Number(fen) / 100).toFixed(2); }
    function validURL(url) { return typeof url === "string" && /^https:\/\/pay\.xiaofengnet\.com\/checkout\?order=WX[0-9a-f]{30}&token=[0-9a-f]{64}$/.test(url); }
    function terminal(state) { return ["delivered", "paid_review", "closed"].indexOf(state) >= 0; }
    function drawQR(matrix) {
        var parent = $("#PaymentQR");
        if (typeof matrix !== "string" || !/^[01|]+$/.test(matrix)) { parent.style.visibility = "collapse"; return; }
        var qr = matrix.split("|"), size = qr.length;
        if (size < 29 || size > 65 || qr.some(function(row){return row.length !== size;})) { parent.style.visibility = "collapse"; return; }
        parent.style.visibility = "visible";
        if (lastMatrix === matrix) return;
        lastMatrix = matrix; parent.RemoveAndDeleteChildren();
        var cell = Math.max(4, Math.floor(260 / size));
        parent.style.width = (size * cell) + "px"; parent.style.height = (size * cell) + "px";
        qr.forEach(function(bits) {
            var row = $.CreatePanel("Panel", parent, ""); row.AddClass("PaymentQRRow"); row.style.height = cell + "px";
            for (var start=0; start<size;) {
                var end=start+1; while (end<size && bits[end]===bits[start]) end++;
                var run=$.CreatePanel("Panel",row,""); run.style.width=((end-start)*cell)+"px"; run.style.height=cell+"px";
                run.style.backgroundColor=bits[start]==="1"?"#000000":"#ffffff"; start=end;
            }
        });
    }
    function render() {
        if (disposed) return;
        var p = current(), order = orders[selected];
        $("#PaymentTitle").text = p ? p.title : "正在加载商品";
        $("#PaymentDescription").text = p ? p.description : "请先完成对局登录";
        $("#PaymentPrice").text = p ? money(p.amount_fen) : "";
        buy.enabled = !busy && !!p && !!p.enabled && (!order || order.state === "closed");
        $("#PaymentBuyLabel").text = p ? "微信购买 " + money(p.amount_fen) : "加载中";
        var canOpen = order && order.state === "pending" && !order.expired && validURL(order.checkout_url);
        $("#PaymentOpen").style.visibility = canOpen ? "visible" : "collapse";
        $("#PaymentLink").style.visibility = canOpen ? "visible" : "collapse";
        if (canOpen) $("#PaymentLink").text = order.checkout_url;
        drawQR(canOpen ? order.qr_matrix : null);
        if (order) {
            var labels = {created:"订单正在确认，请查询结果后重试。", pending:"用手机微信扫描上方二维码。付款后自动发放并刷新存档。",
                delivered:"支付成功：" + order.title + " ×1 已写入存档。",
                paid_review:"已收到付款，该订单需要人工核对。请保留订单号联系开发者。",
                closed:"订单已关闭，可以重新购买。"};
            status.text = order.expired && !terminal(order.state) ? "付款码已过期，正在核对最终状态。" : labels[order.state] || "正在查询…";
            if (order.state === "created") buy.enabled = !busy && !!p && !!p.enabled;
        } else status.text = p && p.owned > 0 ? "已拥有此商品。" : "永久存档道具 ×1，到账后由服务器自动发放。";
        products.forEach(function(item) {
            if (item.panel) {
                item.panel.SetHasClass("Selected", item.sku === selected);
                item.ownedLabel.text = item.owned > 0 ? "已拥有" : item.enabled ? money(item.amount_fen) : "暂不可购买";
            }
        });
    }
    function request(action, sku) {
        if (disposed || busy) return false;
        busy = true; render();
        var ticket = ++generation, body = {action:action};
        if (sku) body.sku = sku;
        GameEvents.SendCustomGameEventToServer("survival_payment_request", body);
        $.Schedule(32, function() {
            if (!disposed && ticket === generation && busy) { busy=false; render(); status.text="请求超时，请查询结果后重试。"; }
        });
        return true;
    }
    function refreshCatalog() { if (!disposed && !busy) request("catalog"); }
    function buildList(data) {
        products = rows(data.products).filter(function(p) {
            return p && typeof p.sku === "string" && p.amount_fen === 5000;
        });
        var list = $("#PaymentProducts"); list.RemoveAndDeleteChildren();
        products.forEach(function(p, index) {
            var card=$.CreatePanel("Button",list,""); card.AddClass("PaymentProduct"); p.panel=card;
            var number=$.CreatePanel("Label",card,""); number.AddClass("PaymentProductNumber"); number.text="0"+(index+1);
            var title=$.CreatePanel("Label",card,""); title.AddClass("PaymentProductTitle"); title.text=p.title;
            var price=$.CreatePanel("Label",card,""); price.AddClass("PaymentProductOwned"); p.ownedLabel=price;
            card.SetPanelEvent("onactivate",function(){selected=p.sku; render();});
        });
        if (!current()) selected = products.length ? products[0].sku : "";
        render();
    }
    function setOpen(value) {
        opened=value;
        if (dialog && (!dialog.IsValid || dialog.IsValid())) dialog.SetHasClass("Open",value);
        var scrim=$("#PaymentScrim"); if (scrim) scrim.SetHasClass("Open",value);
        if (cfg.SurvivalUILayers) {
            if (value) cfg.SurvivalUILayers.Open("payment_shop",dialog,closeShop,{scrim:$("#PaymentScrim"),click:$("#PaymentScrim")});
            else cfg.SurvivalUILayers.Close("payment_shop");
        }
    }
    function closeShop() { setOpen(false); }
    PaymentToggle=function(){setOpen(!opened);if(opened)refreshCatalog();};
    function openShop() { setOpen(true);refreshCatalog(); }
    cfg.SurvivalPayments={Open:openShop,Dispose:function(){closeShop();disposed=true;subscriptions.forEach(function(id){GameEvents.Unsubscribe(id);});}};
    PaymentBuy=function(){
        var p=current(), order=orders[selected];
        if (!p || !p.enabled || busy || (order && order.state!=="closed" && order.state!=="created")) return;
        if (request("create",selected)) status.text="正在创建 " + money(p.amount_fen) + " 微信订单…";
    };
    PaymentOpen=function(){var order=orders[selected];if(order && order.state==="pending" && validURL(order.checkout_url))$.DispatchEvent("ExternalBrowserGoToURL",order.checkout_url);};
    PaymentRefresh=function(){request(orders[selected]?"status":"catalog",orders[selected]?selected:null);};
    var messages={test_account_required:"商城当前仅对指定测试账号开放。",already_owned:"你已经拥有此商品。",
        purchase_limit_reached:"此商品已达到账号购买次数限制。",profile_not_ready:"请先进入对局，等待存档加载。",
        match_session_missing:"请先完成本局登录。",reward_refresh_pending:"远端已更新，存档刷新中；请稍后查询。",
        payment_busy:"上个请求正在处理，请稍后重试。",reset_in_progress:"正在清理测试数据，请先完成清理。",
        product_unavailable:"此商品暂不可购买，请刷新列表。",order_not_in_session:"请重新点击购买，服务器会恢复已有订单。",
        test_reset_disabled:"测试清理功能未开启。",pending_payment_unresolved:"尚有订单需要核对，请再次输入清理命令重试。"};
    subscriptions.push(GameEvents.Subscribe("survival_payment_result",function(data) {
        busy=false; generation++;
        if (!data.ok) {
            render(); if(data.error==="test_account_required")entry.style.visibility="collapse";
            status.text=messages[data.error]||"暂时无法完成请求，请稍后重试。"; return;
        }
        entry.style.visibility="visible";
        if (data.action==="reset") {
            orders={}; lastMatrix=""; render(); status.text="远端测试数据已清理，正在更新商品列表。";
            $.Schedule(1.1,refreshCatalog); return;
        }
        if (data.action==="catalog") { buildList(data); return; }
        var previous=orders[data.sku];
        if (!previous || previous.order_id!==data.order_id || !terminal(previous.state) || terminal(data.state)) orders[data.sku]=data;
        if (data.state==="delivered") {
            products.forEach(function(p){if(p.sku===data.sku){p.owned=1;p.enabled=false;}});
            $.Schedule(1.1,refreshCatalog);
        }
        if (data.action==="create") {selected=data.sku;setOpen(true);}
        render();
    }));
    subscriptions.push(GameEvents.Subscribe("survival_payment_open",openShop));
    function tick() {
        if (disposed) return;
        ticks++;
        if (!busy) {
            var order=orders[selected];
            if (opened && order && !terminal(order.state)) request("status",selected);
            else if (ticks===1 || ticks%4===0) refreshCatalog();
        }
        $.Schedule(5,tick);
    }
    $.Schedule(5,tick);
}());
