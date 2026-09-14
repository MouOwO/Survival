    R.SurvivalShopWindow=function(){
        var w=$("#CustomShopWindow");if(!valid(w)||w._rhSurvivalShop)return;
        w._rhSurvivalShop=true;w.AddClass("RHSurvivalShop");
        R.Window(w,$("#ShopHeader"),$("#ShopCloseButton"));R.SizeWindow(w,604,806);
        ["ShopModeShop","ShopModeChallenge"].forEach(function(id){var b=$("#"+id);if(!b)return;b.hittestchildren=false;panel(b,"RHShopTabGlow");});
    };
    R.ShopStock=function(entry){
        var max=Number(entry.stock_max||0);
        if(max>0)return {count:Number(entry.stock||0),max:max};
        max=Number(entry.purchase_limit||0);
        return max>1?{count:Math.max(0,max-Number(entry.owned_count||0)),max:max}:null;
    };
    // Resource costs are presented only in the tooltip.
    R.UpdateShopPrices=function(card,entry){};
    R.SurvivalShopCard=function(card,entry,buy){};
