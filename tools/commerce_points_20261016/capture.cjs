"use strict";
const fs=require("node:fs"),path=require("node:path"),crypto=require("node:crypto"),assert=require("node:assert/strict");
const {browser,sleep}=require("./cdp.cjs");
const {info,validate,validateTooltip}=require("../lottery_gw2/acceptance.cjs");
const out="design_refs/commerce_points_20261016/preview",page=out+"/index.html";
const assembly=JSON.parse(fs.readFileSync(out+"/assembly.json","utf8")),assetCount=Object.keys(JSON.parse(fs.readFileSync("tools/lottery_gw2/asset_manifest.json","utf8")).assets).length;
async function header(b){
 return b.run(`(()=>{syncLayout();function row(id){const p=nodes[id],s=getComputedStyle(p.el);return {id,text:p.text,bounds:p.el.getBoundingClientRect().toJSON(),font:s.fontFamily,fontSize:s.fontSize};}return {points:row("LotteryGW2Points"),starjoy:row("LotteryGW2StarjoyPoints"),ticket:row("LotteryGW2TicketBalance"),purchase:row("LotteryTicketPurchase"),close:row("LotteryCloseButton"),errors:previewErrors,calls:previewCalls};})()`);
}
function overlap(a,b){return Math.min(a.right,b.right)-Math.max(a.x,b.x)>0.5&&Math.min(a.bottom,b.bottom)-Math.max(a.y,b.y)>0.5;}
function verify(h,width,height){assert.deepEqual(h.errors,[]);assert.equal(h.points.text,"商城积分  425");assert.equal(h.starjoy.text,"星悦积分  320");
 for(const row of [h.points,h.starjoy]){const r=row.bounds;assert(r.x>=0&&r.y>=0&&r.right<=width+1&&r.bottom<=height+1);for(const other of [h.ticket,h.purchase,h.close])assert(!overlap(r,other.bounds),"Balance must not overlap "+other.id);}
 assert(!overlap(h.points.bounds,h.starjoy.bounds),"The two independent balances must not overlap");
 assert(!h.calls.some(call=>/ui_lottery_(draw|exchange)_request|survival_payment|survival_commerce/.test(call.name||"")),"No real or stub draw/payment/commerce request may be sent");}
async function ready(b,mode="normal"){await b.go(page,"?pool=map&state="+mode);assert.equal(await b.run("previewReady"),true);await b.run("syncLayout();Promise.all([...document.images].map(i=>i.decode().catch(()=>false))).then(()=>true)");await sleep(100);}
(async()=>{const b=await browser(),report={notGameCapture:true,fixtureOnly:true,externalNetworkBlocked:true,sourceHashes:assembly.pointsSourceHashes,screens:[],checks:[]};try{
 await b.call("Network.enable");await b.call("Network.setBlockedURLs",{urls:["http://*","https://*","ws://*","wss://*"]});
 for(const [width,height]of [[1600,900],[960,720]]){await b.call("Emulation.setDeviceMetricsOverride",{width,height,deviceScaleFactor:1,mobile:false});await ready(b);
  const state=await info(b);validate(state,width,height,assetCount);const h=await header(b);verify(h,width,height);
  const file="header_"+width+"x"+height+".png";await b.shot(out+"/"+file,{x:0,y:0,width,height});fs.writeFileSync(out+"/header_"+width+"x"+height+".json",JSON.stringify(h,null,2));report.screens.push({file,width,height,header:h});}
 await b.call("Emulation.setDeviceMetricsOverride",{width:1600,height:900,deviceScaleFactor:1,mobile:false});await ready(b,"details");
 const point=await b.run(`(()=>{const card=nodes.LotteryInfoList.Children().find(p=>p.BHasClass("LotteryDetailRow"));card.el.scrollIntoView({block:"center",inline:"nearest"});syncLayout();const r=card.el.getBoundingClientRect(),x=r.x+r.width/2,y=r.y+r.height/2,front=document.elementFromPoint(x,y);return{x,y,hit:!!front&&card.el.contains(front),item:card.__lotteryItem};})()`);
 assert(point.hit,"Actual pointer reaches the original production card");assert.equal(point.item.converted_currency,"shop_points");
 await b.call("Input.dispatchMouseEvent",{type:"mouseMoved",x:2,y:2});await b.call("Input.dispatchMouseEvent",{type:"mouseMoved",x:point.x,y:point.y});await sleep(180);
 const tip=await info(b);validateTooltip(tip,1600,900);assert(tip.tooltipDescription.text.includes("商城积分"),tip.tooltipDescription.text);verify(await header(b),1600,900);
 await b.shot(out+"/tooltip_shop_points_1600x900.png",{x:0,y:0,width:1600,height:900});fs.writeFileSync(out+"/tooltip_shop_points_1600x900.json",JSON.stringify(tip,null,2));report.screens.push({file:"tooltip_shop_points_1600x900.png",width:1600,height:900,realPointer:true,item:point.item.id,tooltip:tip.tooltipDescription.text});
 for(const src of report.sourceHashes)assert.equal(crypto.createHash("sha256").update(fs.readFileSync(src.path)).digest("hex"),src.sha256,"Production source remained frozen");
 report.status="PASS_OFFLINE_ASSEMBLED_POINTS_HEADER";fs.writeFileSync(out+"/validation.json",JSON.stringify(report,null,2));console.log(report.status+" "+out+"/validation.json");
 }catch(error){report.status="FAIL_OFFLINE_ASSEMBLED_POINTS_HEADER";report.error=error.stack||String(error);try{await b.shot(out+"/failure.png");report.failure=await info(b);}catch{}fs.writeFileSync(out+"/validation.json",JSON.stringify(report,null,2));throw error;}finally{b.close();}})().catch(error=>{console.error(error);process.exitCode=1;});
