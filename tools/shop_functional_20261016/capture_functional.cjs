"use strict";
// Actual production assembly and formal catalog input; every account/eligibility
// state is an explicit local fixture. No account, order or payment endpoint runs.
const fs=require("node:fs"),path=require("node:path"),crypto=require("node:crypto"),{spawnSync}=require("node:child_process");
const {browser}=require("../shop_ui_12h/cdp.cjs"),repo=path.resolve(__dirname,"../..");
const base=path.join(repo,"design_refs/shop_functional_20261016"),out=path.join(base,"ui/functional"),preview=path.join(base,"ui/preview_formal");
process.chdir(repo);fs.mkdirSync(out,{recursive:true});
const catalogs={wallet:"design_refs/shop_functional_20261016/release/commerce_catalog.json",paid:"design_refs/shop_functional_20261016/release/payment_catalog.json"};
const build=spawnSync(process.execPath,["tools/shop_functional_20261016/preview_functional.cjs","--wallet",catalogs.wallet,"--catalog",catalogs.paid],{encoding:"utf8",windowsHide:true});
if(build.status!==0)throw Error(build.stdout+build.stderr);
const hash=file=>crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
const formal={wallet:JSON.parse(fs.readFileSync(catalogs.wallet,"utf8")),paid:JSON.parse(fs.readFileSync(catalogs.paid,"utf8"))};
const targets=["video_bundle_b003","video_p016","video_p028","video_p079","video_p147"],records=[];
const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));
function save(){fs.writeFileSync(path.join(out,"visual_checks.json"),JSON.stringify({status:records.some(r=>r.failures&&r.failures.length)?"FAIL":"RUNNING",scope:"Production XML / JS / CSS and formal release catalogs in browser; isolated offline profile/eligibility. New functional products and starter inspector have not been captured in native Dota. No real account, save, order or payment calls.",catalogs:Object.entries(catalogs).map(([kind,file])=>({kind,path:file,sha256:hash(file)})),checks:records},null,2));}
(async()=>{const b=await browser();try{
 async function load(width,height,category="all",state="vip0"){
  await b.call("Emulation.setDeviceMetricsOverride",{width,height,deviceScaleFactor:1,mobile:false});
  await b.go(path.join(preview,"index.html"),"?page=commerce&state="+state+"&category="+category);
  if(!await b.run("marketReady"))throw Error("Formal production assembly failed");
  await b.run("window.functionalPointer=[0,0];GameUI.GetCursorPosition=()=>functionalPointer;document.addEventListener('mousemove',event=>{functionalPointer=[event.clientX,event.clientY]});window.functionalFormalBefore=JSON.stringify(MARKET_CATALOG_SOURCE);true");
 }
 async function position(sku){
  return b.run(`(()=>{const sku=${JSON.stringify(sku)},view=cfg.SurvivalCommerceView,market=cfg.SurvivalBlackLionMarket.GetWindow(),index=view.Inspect().visibleSkus.indexOf(sku);if(index<0)throw Error('Formal SKU is not listed: '+sku);for(let page=0;page<Math.floor(index/40);page++){const button=market.actions.FindChildrenWithClassTraverse('CJPageAction')[1];if(!button||!button.enabled)throw Error('Formal row page inaccessible');button.events.onactivate();}syncLayout();const row=market.content.FindChildrenWithClassTraverse('BLMarketRow')[index%40];market.content.el.scrollTop=row.el.offsetTop;syncLayout();window.functionalRow=row;const rect=row.__menuCell.iconPanel.el.getBoundingClientRect();return {index,page:Math.floor(index/40),pointer:{x:rect.x+rect.width/2,y:rect.y+rect.height/2}};})()`);
 }
 async function hover(sku){const at=await position(sku);await b.call("Input.dispatchMouseEvent",{type:"mouseMoved",...at.pointer});await b.run("functionalRow.events.onmouseover();syncLayout();true");await wait(140);await b.run("syncLayout();true");return at;}
 async function inspect(sku,memberIndex){
  return b.run(`(()=>{const row=functionalRow,tip=row.__purpleDetail,market=cfg.SurvivalBlackLionMarket.GetWindow(),body=tip.FindChildrenWithClassTraverse('MenuV10CommerceDetailBody')[0],effect=tip.FindChildrenWithClassTraverse('RCProductEffect')[0],member=tip.FindChildrenWithClassTraverse('RCBundleMemberEffect')[0],members=tip.FindChildrenWithClassTraverse('BLMarketBundleMember'),buy=row.FindChildrenWithClassTraverse('BLMarketBuy')[0],price=row.FindChildrenWithClassTraverse('BLMarketPriceMain')[0],source=MARKET_CATALOG_SOURCE.wallet.find(p=>p.sku===${JSON.stringify(sku)}),paid=MARKET_CATALOG_SOURCE.paid.products.find(p=>p.sku===${JSON.stringify(sku)});
   function measure(node){if(!node)return null;const range=document.createRange();range.selectNodeContents(node.el);return {text:node.text,bounds:node.el.getBoundingClientRect().toJSON(),clientHeight:node.el.clientHeight,scrollHeight:node.el.scrollHeight,textBounds:[...range.getClientRects()].filter(r=>r.width>.1&&r.height>.1).map(r=>r.toJSON())};}
   const grade=tip.FindChildrenWithClassTraverse('RCPurpleDetailQuality')[0],tr=tip.el.getBoundingClientRect(),wr=market.panel.el.getBoundingClientRect();return {sku:${JSON.stringify(sku)},memberIndex:${memberIndex===undefined?"null":memberIndex},name:row.__menuCell.namePanel.text,visible:tip.BHasClass('Visible'),quality:{visible:grade.visible,text:grade.text},effect:measure(effect),member:measure(member),members:members.map(node=>({name:node.Children()[0].text,selected:node.BHasClass('UISelected'),bounds:node.el.getBoundingClientRect().toJSON()})),body:{bounds:body.el.getBoundingClientRect().toJSON(),clientHeight:body.el.clientHeight,scrollHeight:body.el.scrollHeight},tooltipBounds:tr.toJSON(),windowBounds:wr.toJSON(),buyEnabled:buy.enabled,buyCaption:buy.Children()[0].text,priceText:price.text,formalPrice:paid?{u_coin_price:paid.u_coin_price,amount_fen:paid.amount,original_u_coin_price:(paid.grants.pricing||{}).original_u_coin_price}:source.price,errors:previewErrors,formalUnchanged:functionalFormalBefore===JSON.stringify(MARKET_CATALOG_SOURCE),checkoutCalls:previewCalls.filter(c=>c.method==='paid'||c.method==='wallet'),missingImages:[...document.querySelectorAll('.BLMarketWindow img')].filter(i=>!i.complete||!i.naturalWidth).map(i=>i.src)};
  })()`);
 }
 function validate(result,width,height){
  const failures=[];if(result.errors.length)failures.push("script errors");if(result.missingImages.length)failures.push("missing icons");
  if(!result.visible)failures.push("tooltip hidden");if(result.checkoutCalls.length)failures.push("checkout request");if(!result.formalUnchanged)failures.push("formal catalog mutated");
  if(result.quality.text.includes("未配置")||!result.quality.visible&&result.quality.text)failures.push("internal missing-grade placeholder exposed");
  if(!result.buyEnabled)failures.push("unowned eligible product disabled");
  const t=result.tooltipBounds,w=result.windowBounds;
  if(t.left<w.left-.5||t.top<w.top-.5||t.right>w.right+.5||t.bottom>w.bottom+.5||t.left<-.5||t.top<-.5||t.right>width+.5||t.bottom>height+.5)failures.push("tooltip outside window/viewport");
  if(result.body.scrollHeight>result.body.clientHeight+1)failures.push("body clipped");
  for(const[name,node]of Object.entries({effect:result.effect,member:result.member}))if(node){
   if(node.scrollHeight>node.clientHeight+1)failures.push(name+" clipped");
   if(node.textBounds.some(rect=>rect.top<node.bounds.top-.5||rect.bottom>node.bounds.bottom+.5||rect.top<result.body.bounds.top-.5||rect.bottom>result.body.bounds.bottom+.5))failures.push(name+" painted text outside body");
  }
  const source=formal.wallet.products.find(p=>p.sku===result.sku),paid=formal.paid.products.find(p=>p.sku===result.sku);
  if(paid){if(result.priceText!==paid.u_coin_price+" U币"||paid.amount*10!==paid.u_coin_price||paid.u_coin_price<=0)failures.push("cash price / unit mismatch");}
  else if(result.priceText!==source.price+" "+source.currency_name||source.price<=0)failures.push("wallet price / unit mismatch");
  if(result.sku==="video_bundle_b003"){
   const rewards=source.grants.lines;
   if(result.members.length!==4||result.members.some((m,i)=>m.name!==rewards[i].label)||result.members.filter(m=>m.selected).length!==1)failures.push("member names/selection");
   if(result.member.text!==rewards[result.memberIndex].description.replace(/[；;][ \t]*/g,"\n"))failures.push("member formal description differs");
   if(result.members.some(m=>m.bounds.top<result.body.bounds.top-.5||m.bounds.bottom>result.body.bounds.bottom+.5))failures.push("member selector clipped");
  }else if(result.effect.text!==source.description.replace(/[；;][ \t]*/g,"\n"))failures.push("single formal description incomplete");
  return failures;
 }
 for(const[width,height]of [[1600,900],[960,720]]){
  await load(width,height,"bundles");const positionRecord=await hover("video_bundle_b003");let memberAnchors=null;
  for(const memberIndex of [3,0,1,2]){
   const rect=await b.run(`functionalRow.__purpleDetail.FindChildrenWithClassTraverse('BLMarketBundleMember')[${memberIndex}].el.getBoundingClientRect().toJSON()`);
   await b.call("Input.dispatchMouseEvent",{type:"mouseMoved",x:rect.x+rect.width/2,y:rect.y+rect.height/2});
   await b.run(`functionalRow.__purpleDetail.FindChildrenWithClassTraverse('BLMarketBundleMember')[${memberIndex}].events.onactivate();syncLayout();true`);await wait(120);await b.run("syncLayout();true");
   const result=await inspect("video_bundle_b003",memberIndex),failures=validate(result,width,height),file="b003_member_"+formal.wallet.products.find(p=>p.sku==="video_bundle_b003").grants.lines[memberIndex].id+"_"+width+"x"+height+".png";
   if(memberAnchors&&result.members.some((member,index)=>Math.abs(member.bounds.x-memberAnchors[index].x)>.1||Math.abs(member.bounds.y-memberAnchors[index].y)>.1))failures.push("member selectors moved under the pointer");
   if(!memberAnchors)memberAnchors=result.members.map(member=>member.bounds);
   await b.shot(path.join(out,file),{x:0,y:0,width,height});records.push({viewport:[width,height],screenshot:file,failures,position:positionRecord,...result});save();
   if(failures.length)throw Error(file+": "+failures.join(", "));
  }
  await b.call("Input.dispatchMouseEvent",{type:"mouseMoved",x:width-5,y:height-5});await wait(150);
  if(await b.run("functionalRow.__purpleDetail.BHasClass('Visible')"))throw Error("Interactive starter tooltip did not close after physical exit");
  for(const sku of targets.slice(1)){
   await load(width,height,"all");const at=await hover(sku),result=await inspect(sku),failures=validate(result,width,height),file=sku+"_tooltip_"+width+"x"+height+".png";
   await b.shot(path.join(out,file),{x:0,y:0,width,height});records.push({viewport:[width,height],screenshot:file,failures,position:at,...result});save();if(failures.length)throw Error(file+": "+failures.join(", "));
  }
 }
 // All five original category orders, authoritative prices and hidden stock.
 await load(1600,900,"all");
 const catalogChecks=await b.run(`(()=>{const view=cfg.SurvivalCommerceView,groups={},formalSkus=new Set(MARKET_CATALOG_SOURCE.wallet.concat(MARKET_CATALOG_SOURCE.paid.products).map(p=>p.sku));for(const id of ['home','bundles','promotions','vip','all']){view.SelectCategory(id);syncLayout();const actual=view.Inspect().visibleSkus,order=cfg.SurvivalShopPresentation.groups[id]||[];groups[id]={actual,videoSubsetActual:actual.filter(sku=>order.includes(sku)),videoSubsetExpected:order.filter(sku=>actual.includes(sku))};}view.SelectCategory('all');syncLayout();const initial=view.Inspect().visibleSkus.slice(),wallet=JSON.parse(JSON.stringify(cfg.SurvivalCommerceWallet.GetCatalog())),paid=JSON.parse(JSON.stringify(cfg.SurvivalPayments.GetCatalog())),invalid=initial.filter(sku=>{if(!formalSkus.has(sku))return true;const w=wallet.products.find(p=>p.sku===sku),p=paid.products.find(p=>p.sku===sku),item=w&&w.currency==='shop_points'?w:p;return !item||item.preview_only||item.currency==='shop_gold'||(item.purchase_method==='wallet'?!(item.price>0):!(item.amount_fen>0));});for(const catalog of [wallet,paid])for(const p of catalog.products)if(${JSON.stringify(targets)}.includes(p.sku)){p.owned=1;p.enabled=false;p.disabled_reason='already_owned';}view.UpdateWalletCatalog(wallet);view.UpdateCatalog(paid);view.SelectCategory('all');syncLayout();const after=view.Inspect().visibleSkus.slice();return {groups,initial,afterOwned:after,targets:${JSON.stringify(targets)},zeroOrGhostListed:invalid,checkoutCalls:previewCalls.filter(c=>c.method==='paid'||c.method==='wallet'),errors:previewErrors};})()`);
 const failures=[];for(const[group,data]of Object.entries(catalogChecks.groups))if(JSON.stringify(data.videoSubsetActual)!==JSON.stringify(data.videoSubsetExpected))failures.push("category ordering "+group);
 if(targets.some(sku=>!catalogChecks.initial.includes(sku)||catalogChecks.afterOwned.includes(sku)))failures.push("owned visibility");if(catalogChecks.zeroOrGhostListed.length)failures.push("zero price or metadata-only product listed");if(catalogChecks.checkoutCalls.length||catalogChecks.errors.length)failures.push("unexpected checkout/script failure");
 const releasePlan=JSON.parse(fs.readFileSync(path.join(base,"release/release_plan.json"),"utf8"));if(releasePlan.old_prices_unchanged!==true)failures.push("existing prices changed");
 await b.shot(path.join(out,"owned_unique_products_hidden_1600x900.png"),{x:0,y:0,width:1600,height:900});records.push({kind:"formal_catalog_order_ownership_price",screenshot:"owned_unique_products_hidden_1600x900.png",failures,oldPricesUnchanged:releasePlan.old_prices_unchanged,...catalogChecks});save();if(failures.length)throw Error(failures.join(", "));
 const assembly=JSON.parse(fs.readFileSync(path.join(preview,"assembly.json"),"utf8"));
 const final=JSON.parse(fs.readFileSync(path.join(out,"visual_checks.json"),"utf8"));final.status="PASS";final.notGameCapture=true;final.assemblySha256=hash(path.join(preview,"assembly.json"));final.sourceGraph=assembly.sourceGraph;final.screenshots=records.map(r=>({path:r.screenshot,sha256:hash(path.join(out,r.screenshot))}));fs.writeFileSync(path.join(out,"visual_checks.json"),JSON.stringify(final,null,2));
 console.log("FUNCTIONAL_MARKET_VISUAL_PASS "+records.length+" captures/checks; full formal descriptions, four visible starter member selectors, no cropped lines, old prices retained, owned unique stock hidden, no checkout");
}finally{b.close();}})().catch(error=>{console.error(error);process.exitCode=1;});
