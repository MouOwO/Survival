(function(){
    'use strict';
    var catalog=/*PREVIEW_CATALOG*/,serial=0;
    // Local-only provider. No HTTP, game events, wallet or entitlement operations.
    GameUI.CustomUIConfig().SurvivalCommercePreviewData={
        catalog:catalog,
        methods:[{id:'preview_scan_a',name:'微信（模拟）'},{id:'preview_scan_b',name:'支付宝（模拟）'}],
        qr:'file://{images}/custom_game/shop_preview_v1/preview_qr.png',
        createOrder:function(product,quantity,method){
            return {id:'UI-DEMO-'+(++serial),product_id:product.id,name:product.name,quantity:quantity,
                amount:product.prices[0].amount*quantity,currency:product.prices[0].currencyName,
                payment_name:method.name,state:'waiting',expires:180};
        }
    };
})();
