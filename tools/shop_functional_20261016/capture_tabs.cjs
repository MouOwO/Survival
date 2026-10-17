"use strict";
// Render the production component chain; profiles remain synthetic and offline.
const fs=require("node:fs"),path=require("node:path"),{browser}=require("../shop_ui_12h/cdp.cjs");
const repo=path.resolve(__dirname,"../.."),phase=process.argv.includes("--before")?"before":"after",out=path.join(repo,"design_refs/shop_functional_20261016/ui");
process.chdir(repo);fs.mkdirSync(out,{recursive:true});
const scenarios=phase==="before"?[[1600,900,"home"],[960,720,"home"]]:[[960,720,"home"],[1280,720,"home"],[1600,900,"home"],[1920,1080,"home"],[2560,1440,"home"],...["bundles","promotions","vip","all"].map(group=>[1600,900,group])];
(async()=>{const b=await browser(),checks=[];try{
 for(const[width,height,category]of scenarios){
  await b.call("Emulation.setDeviceMetricsOverride",{width,height,deviceScaleFactor:1,mobile:false});
  await b.go(path.join(out,"preview_"+phase+"/index.html"),"?page=commerce&state=vip0&category="+category);
  if(!await b.run("marketReady"))throw Error("Production assembly failed");
  const result=await b.run(String.raw`(()=>{
   syncLayout();const market=cfg.SurvivalBlackLionMarket.GetWindow(),r=market.panel.el.getBoundingClientRect(),scale=r.width/1120;
   const tabs=market.sidebar.Children().map(tab=>{const text=tab.Children().find(p=>p.paneltype==='Label'||p.el.classList.contains('label')),tr=tab.el.getBoundingClientRect(),lr=text.el.getBoundingClientRect(),style=getComputedStyle(tab.el);return {label:text.text,children:tab.Children().map(p=>({tag:p.el.tagName,text:p.text||'',classes:p.el.className})),height:tr.height/scale,width:tr.width/scale,centerDelta:[(lr.left+lr.right-tr.left-tr.right)/2/scale,(lr.top+lr.bottom-tr.top-tr.bottom)/2/scale],contentCenterDelta:[(lr.left+lr.right-tr.left-tr.right)/2/scale+(parseFloat(style.borderRightWidth)-parseFloat(style.borderLeftWidth))/2,(lr.top+lr.bottom-tr.top-tr.bottom)/2/scale+(parseFloat(style.borderBottomWidth)-parseFloat(style.borderTopWidth))/2],padding:getComputedStyle(text.el).padding,margin:getComputedStyle(text.el).margin,bounds:tr.toJSON(),labelBounds:lr.toJSON()};});
   const list=market.content.el.getBoundingClientRect(),rows=market.content.FindChildrenWithClassTraverse('BLMarketRow');
   const buttons=rows.map(row=>{const button=row.FindChildrenWithClassTraverse('BLMarketBuy')[0],label=button.FindChildrenWithClassTraverse('BLMarketBuyText')[0],br=button.el.getBoundingClientRect(),lr=label.el.getBoundingClientRect();return {text:label.text,centerDelta:[(lr.left+lr.right-br.left-br.right)/2/scale,(lr.top+lr.bottom-br.top-br.bottom)/2/scale]};});
   return {bounds:r.toJSON(),scale,tabs,list:{x:(list.x-r.x)/scale,y:(list.y-r.y)/scale,width:list.width/scale,height:list.height/scale,bottom:(list.bottom-r.y)/scale},rowCount:rows.length,buttons,errors:previewErrors,missingImages:[...document.querySelectorAll('.BLMarketWindow img')].filter(i=>!i.complete||!i.naturalWidth).map(i=>i.src),checkoutCalls:previewCalls.filter(c=>c.method==='paid'||c.method==='wallet')};
  })()`);
  const failures=[];if(result.errors.length)failures.push("script errors");if(result.missingImages.length)failures.push("missing images");
  if(result.bounds.x<-.1||result.bounds.y<-.1||result.bounds.right>width+.1||result.bounds.bottom>height+.1)failures.push("window clipping");
  if(result.tabs.length!==5)failures.push("not five tabs");if(result.checkoutCalls.length)failures.push("checkout requests");
  if(result.buttons.some(button=>button.centerDelta.some(value=>Math.abs(value)>.11)))failures.push("purchase caption moved");
  if(phase==="after"){
   if(result.tabs.some(tab=>tab.children.length!==1||tab.children[0].tag!=="LABEL"||!tab.children[0].classes.includes("RCTabText")))failures.push("tab contains icon/count");
   if(result.tabs.some(tab=>Math.abs(tab.height-46)>.11||tab.contentCenterDelta.some(value=>Math.abs(value)>.11)||tab.padding!=="0px"||tab.margin!=="0px"))failures.push("tab height/centering");
   if(Math.abs(result.list.y-164)>.11||Math.abs(result.list.height-564)>.11||Math.abs(result.list.bottom-728)>.11)failures.push("list geometry");
   const transitions=await b.run(`(()=>{const menu=cfg.SurvivalBlackLionMarket.GetWindow(),seen=[];for(const tab of menu.sidebar.Children().slice()){tab.events.onactivate();syncLayout();seen.push(cfg.SurvivalCommerceView.Inspect().category);}return {seen,requests:previewCalls.filter(c=>c.method==='paid'||c.method==='wallet')};})()`);
   result.transitions=transitions;if(JSON.stringify(transitions.seen)!==JSON.stringify(["home","bundles","promotions","vip","all"])||transitions.requests.length)failures.push("tab click behavior");
   await b.run("cfg.SurvivalCommerceView.SelectCategory("+JSON.stringify(category)+");syncLayout()");
  }
  const name=phase+"_"+category+"_"+width+"x"+height;await b.shot(path.join(out,name+".png"),{x:0,y:0,width,height});
  if(width===1600&&category==="home"){const first=result.tabs[0].bounds,last=result.tabs.at(-1).bounds;await b.shot(path.join(out,phase+"_tabs_1600x900.png"),{x:first.x,y:first.y,width:last.right-first.x,height:first.height});}
  checks.push({viewport:[width,height],category,phase,screenshot:name+".png",failures,...result});
  fs.writeFileSync(path.join(out,"tabs_checks_"+phase+".json"),JSON.stringify({scope:"Production XML / JS / CSS assembled in local browser. Native game rendering not captured. Catalog data formal; account and eligibility synthetic. No account/order/payment calls.",checks},null,2));
  if(failures.length)throw Error(name+": "+failures.join(", "));
 }
 console.log("MARKET_TABS_"+phase.toUpperCase()+"_PASS "+checks.length+" states");
}finally{b.close();}})().catch(error=>{console.error(error);process.exitCode=1;});
