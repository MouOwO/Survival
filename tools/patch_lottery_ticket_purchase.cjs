module.exports=function(source){
 const anchor='    function feature(name) {\n        if (pending || animating) return;';
 if(source.includes('OpenTicketPurchase'))return source;
 if(!source.includes(anchor))throw Error('Ticket purchase entry anchor missing');
 return source.replace(anchor,anchor+`\n        if (name === "purchase") {\n            var selectedTicketPool = state && (state.selected_pool || state);\n            var commerce = GameUI.CustomUIConfig().SurvivalCommerceView;\n            hideTooltip();\n            if (commerce && commerce.OpenTicketPurchase && selectedTicketPool) {\n                commerce.OpenTicketPurchase({id:selectedTicketPool.id || selectedPoolId,display_name:selectedTicketPool.display_name || selectedPoolId,ticket_name:selectedTicketPool.ticket_name || "抽奖券"});\n            } else { setText("LotteryStatus", "抽奖券演示界面尚未就绪，请稍后重试"); }\n            return;\n        }`);
};
