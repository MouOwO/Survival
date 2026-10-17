"use strict";
const fs=require("node:fs"),path=require("node:path"),{spawnSync}=require("node:child_process");
const {browser}=require("../shop_ui_12h/cdp.cjs"),repo=path.resolve(__dirname,"../.."),out=path.join(repo,"design_refs/shop_catalog_20261016/ui");
process.chdir(repo);
const build=spawnSync(process.execPath,["tools/shop_catalog_20261016/preview.cjs",...process.argv.slice(2)],{encoding:"utf8",windowsHide:true});
if(build.status!==0)throw Error(build.stdout+build.stderr);
const scenarios=[[960,720,"vip0","home"],[1280,720,"vip0","home"],[1600,900,"vip0","home"],[1920,1080,"vip0","home"],[2560,1440,"vip0","home"],...['bundles','promotions','vip','all'].map(group=>[1600,900,'vip0',group]),[1600,900,'vip5','vip'],[1600,900,'vip12','vip'],[960,720,'vip0','vip'],[1600,900,'owned','all'],[1600,900,'insufficient','all']];
(async()=>{const b=await browser(),records=[];try{
 for(const[w,h,state,category]of scenarios){
  await b.call('Emulation.setDeviceMetricsOverride',{width:w,height:h,deviceScaleFactor:1,mobile:false});
  await b.go(path.join(out,'preview/index.html'),'?page=commerce&state='+state+'&category='+category);
  if(!await b.run('marketReady'))throw Error('Production component assembly failed');
  const result=await b.run(String.raw`(()=>{
   syncLayout();const market=cfg.SurvivalBlackLionMarket.GetWindow(),rect=market.panel.el.getBoundingClientRect(),scale=rect.width/1120;
   const tabs=[...document.querySelectorAll('.BLMarketTab')].map(p=>({name:p.querySelector('.RCTabText').textContent,bounds:p.getBoundingClientRect().toJSON()}));
   const rows=market.content.FindChildrenWithClassTraverse('BLMarketRow').map(row=>{
    const button=row.FindChildrenWithClassTraverse('BLMarketBuy')[0],label=button.FindChildrenWithClassTraverse('BLMarketBuyText')[0],reason=row.FindChildrenWithClassTraverse('BLMarketDisabledReason')[0];
    const rb=row.el.getBoundingClientRect(),bb=button.el.getBoundingClientRect(),lb=label.el.getBoundingClientRect(),reasonRect=reason.el.getBoundingClientRect();
    return {name:row.__menuCell.namePanel.text,buyText:label.text,enabled:button.enabled,reason:reason.visible?reason.text:'',
     centerDelta:[((lb.left+lb.right)-(bb.left+bb.right))/2/scale,((lb.top+lb.bottom)-(bb.top+bb.bottom))/2/scale],
     labelPadding:getComputedStyle(label.el).padding,rowWidth:rb.width/scale,rowMargin:getComputedStyle(row.el).margin,rowBounds:rb.toJSON(),buttonBounds:bb.toJSON(),reasonBounds:reasonRect.toJSON(),reasonOverflow:reason.visible&&(reasonRect.bottom>rb.bottom+.1||reasonRect.top<bb.bottom-.1)};
   });
   return {category:cfg.SurvivalCommerceView.Inspect().category,bounds:rect.toJSON(),tabs,rows,errors:previewErrors,
    missingImages:[...document.querySelectorAll('.BLMarketWindow img')].filter(i=>!i.complete||!i.naturalWidth).map(i=>i.src),
    checkoutCalls:previewCalls.filter(c=>c.method==='paid'||c.method==='wallet'),fixture:{scenario:marketFixture.scenario,vipLevel:marketFixture.vipLevel,ownedSku:marketFixture.ownedSku,note:marketFixture.note}};
  })()`);
  const failures=[];
  if(result.errors.length)failures.push('script errors');if(result.missingImages.length)failures.push('missing icons');if(result.tabs.length!==5)failures.push('expected five tabs');
  if(result.bounds.x<-.1||result.bounds.y<-.1||result.bounds.right>w+.1||result.bounds.bottom>h+.1)failures.push('window clipped');
  if(result.tabs.some(t=>t.bounds.right>result.bounds.right+.1))failures.push('tab clipped');if(result.checkoutCalls.length)failures.push('checkout called');
  if(result.rows.some(r=>Math.abs(r.centerDelta[0])>.11||Math.abs(r.centerDelta[1])>.11||r.labelPadding!=='0px'))failures.push('button caption off center');
  if(result.rows.some(r=>r.reasonOverflow))failures.push('disabled reason overlaps or clips');
  if(result.rows.some(r=>Math.abs(r.rowWidth-1072)>.11||r.rowMargin!=='0px'))failures.push('legacy bundle layout leaked into row');
  if(category==='vip'&&state==='vip0'&&(!result.rows.length||result.rows.some(r=>r.enabled||!r.reason)))failures.push('VIP restriction missing');
  if(category==='vip'&&state==='vip12'&&result.rows.some(r=>!r.enabled))failures.push('eligible VIP not actionable');
  const name=category+'_'+state+'_'+w+'x'+h;
  await b.shot(path.join(out,name+'.png'),{x:0,y:0,width:w,height:h});
  records.push({viewport:[w,h],state,category,screenshot:name+'.png',failures,...result});
  fs.writeFileSync(path.join(out,'visual_checks.json'),JSON.stringify({scope:'Actual production XML/JS/CSS assembled in browser; eligibility/ownership are labeled offline samples; not native game validation. No account/order/payment calls.',checks:records},null,2));
  if(failures.length)throw Error(name+': '+failures.join(', '));
  if(w===1600&&category==='home'&&state==='vip0'){
   const hover=await b.run(`(()=>{const row=cfg.SurvivalBlackLionMarket.GetWindow().content.FindChildrenWithClassTraverse('BLMarketRow')[0];if(!row)return false;row.events.onmouseover();syncLayout();return true;})()`);
   if(hover){await b.run('new Promise(resolve=>setTimeout(()=>{syncLayout();resolve(true);},80))');await b.shot(path.join(out,'home_hover_vip0_1600x900.png'),{x:0,y:0,width:w,height:h});}
  }
  if(w===1600&&category==='vip'&&state==='vip0'){
   const clip=await b.run(`(()=>{const r=document.querySelector('.BLMarketList').getBoundingClientRect(),first=document.querySelector('.BLMarketBuy').getBoundingClientRect();return {x:Math.floor(first.x-12),y:Math.floor(r.y),width:Math.ceil(first.width+24),height:Math.ceil(r.height)};})()`);
   await b.shot(path.join(out,'button_center_vip0_1600x900.png'),clip);
  }
 }
 console.log('SHOP_CATALOG_VISUAL_PASS '+records.length+' states; five tabs, centered captions, visible VIP reasons, no missing icons or checkout calls.');
}finally{b.close();}})().catch(error=>{console.error(error);process.exitCode=1;});
