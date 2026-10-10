"use strict";
const fs=require("node:fs"),{browser,sleep}=require("../shop_ui_12h/cdp.cjs");
(async()=>{
 const b=await browser(),results=[];
 try{
  for(const mode of ["shop","commerce"]){
   await b.go("design_refs/purple_ui_10h/work/shop_preview/"+mode+".html");
   const inspect=()=>b.run(`({calls:previewCalls.length,images:[...document.images].filter(i=>i.getAttribute("src")&&i.getClientRects().length&&(!i.complete||!i.naturalWidth)).map(i=>i.src),shop:cfg.SurvivalShop&&cfg.SurvivalShop.Inspect(),windows:[...document.querySelectorAll(".UIModal")].map(p=>({classes:p.className,visible:!p.hidden,bounds:p.getBoundingClientRect().toJSON()}))})`);
   const first=await inspect();results.push({mode,resolution:[1920,1080],...first});
   await b.shot("design_refs/purple_ui_10h/work/shop_preview/"+mode+"_1920.png");
   if(mode==="shop"){
    for(const height of [456,662,760]){
     await b.run(`nodes.CustomShopWindow.style.height="${height}px";nodes.ShopBody.style.height="${Math.min(height-234,490)}px";nodes.ShopFooter.style.position="36px ${height-46}px 0px";syncFlows()`);
     await b.shot("design_refs/purple_ui_10h/work/shop_preview/shop_same_equipment_height_"+height+".png");
    }
    await b.run('previewShopTab("equipment")');
   }
   if(mode==="shop")await b.run('nodes.ShopItemList.Children().filter(p=>p.BHasClass("ShopShelfSlot"))[0].events.onmouseover()');
   else await b.run('root.Children().find(p=>p.BHasClass("CommercePurple")).Children().find(p=>p.BHasClass("RCGrid")).Children()[0].events.onmouseover()');
   await sleep(120);await b.run("syncFlows()");await b.shot("design_refs/purple_ui_10h/work/shop_preview/"+mode+"_1920_tooltip.png");
   if(mode==="shop"){
    await b.run('previewShopTab("other")');await sleep(120);
    results.push({mode,category:"other",resolution:[1920,1080],...await inspect()});
    await b.shot("design_refs/purple_ui_10h/work/shop_preview/shop_1920_other.png");
    await b.run('previewShopTab("challenge")');
   }
   else await b.run('selectCategory("bundles")');
   await sleep(120);await b.shot("design_refs/purple_ui_10h/work/shop_preview/"+mode+"_1920_more.png");
   await b.call("Emulation.setDeviceMetricsOverride",{width:1280,height:720,deviceScaleFactor:1,mobile:false});
   await b.go("design_refs/purple_ui_10h/work/shop_preview/"+mode+".html");
   results.push({mode,resolution:[1280,720],...await inspect()});
   await b.shot("design_refs/purple_ui_10h/work/shop_preview/"+mode+"_1280.png");
   await b.call("Emulation.setDeviceMetricsOverride",{width:1920,height:1080,deviceScaleFactor:1,mobile:false});
  }
  fs.writeFileSync("design_refs/purple_ui_10h/work/shop_preview/inspection.json",JSON.stringify(results,null,2));console.log(JSON.stringify(results,null,2));
 }finally{b.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
