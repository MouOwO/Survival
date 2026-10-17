"use strict";
window.resourcePreview={scope:'Actual survival shop, formal catalog read-only fixture; no game, account or purchases',ready:false};
window.previewReady=(async()=>{await previewLoad();
 cfg.SurvivalShop.SetUnlocks({shop:true,research:true});cfg.SurvivalShop.Open();
 let seq=100;
 window.resourceEntries=structuredClone(PREVIEW_FIXTURE.shop);
 window.resourceShopTab=function(category){const challenge=category==='challenge';if(challenge)cfg.SurvivalShop.OpenChallenge();else if(category==='other')cfg.SurvivalShop.SelectOther();else cfg.SurvivalShop.SelectShop();emit('ui_shop_snapshot',{success:1,sequence:++seq,full:1,ui_mode:challenge?'challenge':'shop',resources:{wood:60000,gold:2881},categories:[{shopid:'weapon',shopname:'装备',order:1},{shopid:'item',shopname:'其他',order:2}],entries:resourceEntries.filter(x=>challenge?['challenge','rebirth'].includes(x.shop_id):['weapon','item'].includes(x.shop_id))});syncLayout();};
 resourceShopTab('equipment');emitNet('survival_ui_state','player_0',{sequence:100,shop_unlocked:1,research_unlocked:1,resources:{wood:60000,gold:2881}});syncLayout();await new Promise(r=>setTimeout(r,250));syncLayout();resourcePreview.ready=true;return true;
})().catch(e=>{previewErrors.push({scope:'resource state',message:String(e),stack:e.stack});return false;});
