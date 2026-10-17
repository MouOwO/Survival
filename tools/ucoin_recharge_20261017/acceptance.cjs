'use strict';
const fs=require('node:fs'),assert=require('node:assert/strict'),{browser,sleep}=require('./browser.cjs');
const out='design_refs/ucoin_recharge_20261017/preview',page=out+'/index.html';
(async()=>{const b=await browser(),checks=[];try{
 const input=async text=>{await b.run('nodes.PaymentQuantityInput.el.focus();nodes.PaymentQuantityInput.el.select();true');await b.call('Input.insertText',{text});await sleep(25);await b.run('syncLayout()');};
 const state=()=>b.run(`(()=>{syncLayout();const box=id=>nodes[id].el.getBoundingClientRect().toJSON();return {inspect:cfg.SurvivalPayments.Inspect(),box:box('PaymentDialog'),noticeBox:box('PaymentConsumptionNotice'),priceBox:box('PaymentPrice'),unitBox:box('PaymentUnitPrice'),inputBox:box('PaymentQuantityInput'),buyBox:box('PaymentBuy'),buyLabelBox:box('PaymentBuyLabel'),price:nodes.PaymentPrice.text,unit:nodes.PaymentUnitPrice.text,buy:nodes.PaymentBuyLabel.text,input:nodes.PaymentQuantityInput.el.value,minusEnabled:nodes.PaymentQuantityMinus.enabled,plusEnabled:nodes.PaymentQuantityPlus.enabled,notice:nodes.PaymentConsumptionNotice.text,errors:previewErrors,artLoaded:nodes.PaymentProductArt.el.complete&&nodes.PaymentProductArt.el.naturalWidth>0,create:previewCalls.filter(c=>c.payload.action==='create').map(c=>c.payload),textFit:['PaymentTitle','PaymentPrice','PaymentUnitPrice','PaymentQuantityHint','PaymentBuyLabel','PaymentConsumptionNotice'].map(id=>({id,width:nodes[id].el.clientWidth,scrollWidth:nodes[id].el.scrollWidth,height:nodes[id].el.clientHeight,scrollHeight:nodes[id].el.scrollHeight}))}})()`);
 function verify(s,w,h){
  assert.deepEqual(s.errors,[]);assert(s.inspect.opened);assert.equal(s.inspect.maxQuantity,999999);assert(s.artLoaded);
  assert(s.box.x>=0&&s.box.y>=0&&s.box.right<=w+1&&s.box.bottom<=h+1,JSON.stringify(s.box));
  for(const key of ['noticeBox','priceBox','unitBox','inputBox','buyBox']){const p=s[key];if(s.create.length&&['inputBox','buyBox'].includes(key)){assert.equal(p.width,0);continue;}assert(p.x>=s.box.x-1&&p.y>=s.box.y-1&&p.right<=s.box.right+1&&p.bottom<=s.box.bottom+1,key+' '+JSON.stringify(p));}
  assert.equal(s.notice,'请适度娱乐，理性消费');for(const t of s.textFit)assert(t.scrollWidth<=t.width+1&&t.scrollHeight<=t.height+1,JSON.stringify(t));
 }
 const inputFit=()=>b.run(`(()=>{const i=nodes.PaymentQuantityInput.el,s=getComputedStyle(i),c=document.createElement('canvas').getContext('2d');c.font=[s.fontWeight,s.fontSize,s.fontFamily].join(' ');return {value:i.value,measuredTextWidth:c.measureText(i.value).width,availableWidth:i.clientWidth-parseFloat(s.paddingLeft)-parseFloat(s.paddingRight),horizontalScroll:i.scrollLeft};})()`);
 for(const [width,height] of [[1600,900],[960,720]]){
  await b.call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
  for(const count of [1,999999])for(const [provider,label] of [['wechat','微信'],['alipay','支付宝']]){
   await b.go(page);assert(await b.run('rechargeReady'));await input(String(count));await b.run('PaymentChannel('+JSON.stringify(provider)+');nodes.PaymentQuantityInput.el.blur();syncLayout();true');let s=await state();verify(s,width,height);
   const digits=await inputFit();assert(digits.measuredTextWidth<=digits.availableWidth,JSON.stringify(digits));assert.equal(digits.horizontalScroll,0,'All digits fit without input horizontal scrolling');
   assert.equal(s.inspect.quantity,count);assert.equal(s.input,String(count));assert.equal(s.price,'合计 ¥'+count+'.00');assert.equal(s.buy,label+'充值 ¥'+count+'.00');assert(s.unit.includes('到账 '+count*100+' U币'));assert.equal(s.create.length,0);assert.equal(s.minusEnabled,count>1);assert.equal(s.plusEnabled,count<999999);
   const file='recharge_'+provider+'_'+count+'_'+width+'x'+height+'.png';await b.shot(out+'/'+file,width,height);
   checks.push({width,height,quantity:count,provider,file,production_component_browser_preview:true,real_orders_created:0,inputFit:digits,...s});
  }
  // Local only: production request is captured by the adapter, then answered with fixture QR.
  await b.run('PaymentBuy();rechargeFixtureOrder();syncLayout();true');const pending=await state();verify(pending,width,height);assert.equal(pending.create.length,1);assert.equal(pending.create[0].quantity,999999);await b.shot(out+'/recharge_fixture_qr_'+width+'x'+height+'.png',width,height);
 }
 fs.writeFileSync(out+'/validation.json',JSON.stringify({passed:true,at:new Date().toISOString(),scope:'Production checkout assembled with local browser fixture; HTTP/HTTPS blocked; no game, account, external service or real order. Screenshots are browser component previews.',checks},null,2));
 console.log('UCOIN_RECHARGE_BROWSER_PASS '+checks.length+' confirmation views, 2 fixture QR views');
}finally{b.close();}})().catch(error=>{console.error(error);process.exitCode=1;});
