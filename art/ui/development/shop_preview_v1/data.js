(function(){
    'use strict';
    var catalog=/*PREVIEW_CATALOG*/,serial=0;
    // Local-only provider. No HTTP, game events, wallet or entitlement operations.
    GameUI.CustomUIConfig().SurvivalCommercePreviewData={
        catalog:catalog,
        methods:[{id:'preview_scan_a',name:'微信（模拟）'},{id:'preview_scan_b',name:'支付宝（模拟）'}],
        qr:'file://{images}/custom_game/shop_preview_v1/preview_qr.png',
        // Explicit preview-only pricing, independent of gameplay ticket balances.
        ticketPreview:{unit_price:1,currency_name:'U币',max_quantity:99},
        ticketProduct:function(pool){
            if(!pool||!pool.id)return null;
            var price=this.ticketPreview;
            return {id:'preview_ticket_'+String(pool.id),name:String(pool.ticket_name||'抽奖券'),
                pool_id:String(pool.id),image:'file://{images}/custom_game/lottery_handoff_v1/ticket_illustrated.png',
                effect:'所属奖池：'+String(pool.display_name||pool.id)+'。每份演示商品为 1 张抽奖券。价格仅供界面演示，模拟完成不会增加抽奖券。',
                prices:[{amount:price.unit_price,currencyName:price.currency_name}],max_quantity:price.max_quantity,purchasable:true};
        },
        createOrder:function(product,quantity,method){
            return {id:'UI-DEMO-'+(++serial),product_id:product.id,name:product.name,quantity:quantity,
                amount:product.prices[0].amount*quantity,currency:product.prices[0].currencyName,
                payment_name:method.name,state:'waiting',expires:180};
        }
    };
})();
