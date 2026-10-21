const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('panorama/src/scripts/custom_game/payment_test.js','utf8');
function fixture(){
 let now=100000,serial=0,shopVisible=false,walletAttempts=0,walletAccepted=0,walletBusy=0;const nodes={},requests=[],jobs=new Map(),handlers={};
 function panel(){return {style:{},events:{},children:[],enabled:true,text:'',SetHasClass(k,v){this[k]=v},AddClass(k){this[k]=true},RemoveClass(k){delete this[k]},BHasClass(k){return !!this[k]},SetPanelEvent(k,v){this.events[k]=v},RemoveAndDeleteChildren(){this.children=[]},Children(){return this.children},IsValid(){return !this.deleted}}}
 function $(id){return nodes[id]||(nodes[id]=panel())} $.CreatePanel=(type,p)=>{const n=panel();p.children.push(n);return n};$.Schedule=(delay,fn)=>{const id=++serial;jobs.set(id,{at:now+delay*1000,fn});return id};$.CancelScheduled=id=>jobs.delete(id);$.DispatchEvent=()=>{};
 const cfg={SurvivalDevelopmentPayments:true,SurvivalCommerceWallet:{Refresh(){walletAttempts++;if(walletBusy>0){walletBusy--;return false}walletAccepted++;return true},GetCatalog(){return {products:[],balances:{shop_gold:50}}}},SurvivalCommerceView:{IsOpen:()=>shopVisible,Open(){shopVisible=true;cfg.SurvivalPayments.RefreshCatalog()},UpdateCatalog(){},SetNotice(){}}};
 const env={$,Date:{now:()=>now},GameUI:{CustomUIConfig:()=>cfg},GameEvents:{Subscribe:(k,fn)=>handlers[k]=fn,Unsubscribe(){},SendCustomGameEventToServer:(name,data)=>requests.push({...data,at:now})}};vm.runInNewContext(source,env);
 const products=['ticket_a','ticket_b'].map(sku=>({sku,title:sku,amount_fen:120,u_coin_price:1200,u_coin_per_yuan:1000,max_quantity:100,enabled:true,owned:8,reward_lines:[{kind:'archive_item',id:'lottery_ticket',quantity:1,label:'抽奖券'}]}));
 const catalog=()=>({ok:true,products:products.map(p=>({...p})),wechat:1,alipay:1});
 function reply(data,request=requests.at(-1)){handlers.survival_payment_result({action:request.action,request_id:request.request_id,...data})}
 function advance(ms){const until=now+ms;let count=0;while(true){const [id,j]=[...jobs.entries()].sort((a,b)=>a[1].at-b[1].at)[0]||[];if(!j||j.at>until)break;jobs.delete(id);now=j.at;j.fn();assert(++count<1000,'scheduler must remain bounded')}now=until}
 function order(sku,state='pending'){return {ok:true,sku,title:sku,quantity:1,unit_amount_fen:120,unit_u_coin_price:1200,amount_fen:120,u_coin_price:1200,u_coin_per_yuan:1000,provider:'wechat',state,order_id:'WX'+(sku==='ticket_a'?'a':'b').repeat(30),effects:{},effect_changes:{},reward_lines:[{kind:'archive_item',id:'lottery_ticket',quantity:1,label:'抽奖券'}]}}
 function pending(sku){cfg.SurvivalPayments.Checkout(sku);env.PaymentBuy();assert.equal(requests.at(-1).action,'create');reply(order(sku))}
 cfg.SurvivalPayments.RefreshCatalog();reply(catalog());
 return {env,cfg,nodes,requests,products,catalog,reply,advance,order,pending,emit(data){handlers.survival_payment_result(data)},wallet(){return {attempts:walletAttempts,accepted:walletAccepted}},setWalletBusy(n){walletBusy=n},close(){if(cfg.SurvivalPayments.Inspect().opened)env.PaymentToggle();shopVisible=false},showShop(){shopVisible=true},dispose(){cfg.SurvivalPayments.Dispose()}};
}
{
 const f=fixture();f.pending('ticket_a');f.close();const before=f.requests.length;f.advance(5000);
 assert.equal(f.requests.length,before+1,'closing payment must not stop reconciliation of a known pending order');assert.equal(f.requests.at(-1).action,'status');assert.equal(f.requests.at(-1).sku,'ticket_a');
 f.reply(f.order('ticket_a','delivered'));assert.equal(f.nodes['#PaymentBuy'].enabled,false,'delivery waits for authoritative catalogue before another purchase');assert.equal(f.cfg.SurvivalPayments.Inspect().opened,false,'background delivery must never reopen payment');f.advance(0);assert.equal(f.wallet().accepted,1);f.env.PaymentRefresh();f.reply(f.order('ticket_a','delivered'));f.advance(0);assert.equal(f.wallet().accepted,1,'duplicate delivered status only refreshes wallet once per order');
 const owned=f.nodes['#PaymentProducts'].children[0].children[2].text;assert(owned.includes('已购 8'),'delivery cannot fabricate owned=1');assert.equal(f.cfg.SurvivalPayments.GetCatalog().products[0].owned,8);
 f.advance(1100);assert.equal(f.requests.at(-1).action,'catalog');f.products[0].owned=9;f.reply(f.catalog());assert.equal(f.cfg.SurvivalPayments.GetCatalog().products[0].owned,9);assert(f.nodes['#PaymentProducts'].children[0].children[2].text.includes('已购 9'));
 assert.equal(f.requests.filter(r=>r.action==='create').length,1,'background reads never create another order');f.emit({ok:true,action:'reset'});f.advance(0);assert.equal(f.wallet().accepted,2,'reset completion refreshes wallet too');f.dispose();
}
{
 const f=fixture();f.pending('ticket_a');f.pending('ticket_b');f.close();f.showShop();let old=null;
 for(let i=0;i<10;i++){const before=f.requests.length;f.advance(5000);assert.equal(f.requests.length,before+1,'one bounded read per scheduler turn');const r=f.requests.at(-1);assert(['status','catalog'].includes(r.action));if(r.action==='catalog')f.reply(f.catalog());else{if(!old)old=r;f.reply(f.order(r.sku));}}
 const reads=f.requests.filter(r=>r.action==='status');assert(reads.filter(r=>r.sku==='ticket_a').length>=3);assert(reads.filter(r=>r.sku==='ticket_b').length>=3);assert(f.requests.filter(r=>r.action==='catalog').length>=3,'pending reads cannot starve visible catalogue TTL');assert.equal(f.requests.filter(r=>r.action==='create').length,2);
 f.advance(5000);const active=f.requests.at(-1),before=f.requests.length;f.reply(f.order(old.sku,'delivered'),old);f.advance(5000);assert.equal(f.requests.length,before,'stale response cannot unlock a newer in-flight read');f.reply(active.action==='catalog'?f.catalog():f.order(active.sku));f.dispose();const count=f.requests.length;f.advance(120000);assert.equal(f.requests.length,count,'Dispose stops all pending/catalogue polling');
}
{
 const f=fixture();f.pending('ticket_a');f.close();f.advance(5000);const timedOut=f.requests.at(-1);assert.equal(timedOut.action,'status');const before=f.requests.length;f.advance(31000);assert.equal(f.requests.length,before,'busy read is not duplicated before timeout');f.advance(9000);assert(f.requests.length>before,'pending reconciliation resumes after read timeout');const active=f.requests.at(-1);assert.equal(active.action,'status');f.reply(f.order('ticket_a','delivered'),timedOut);assert.equal(f.cfg.SurvivalPayments.Inspect().pending,'status','late timeout response cannot release the current request');f.reply(f.order('ticket_a','closed'),active);f.advance(1100);const count=f.requests.length;f.advance(60000);assert.equal(f.requests.length,count,'closed orders stop background polling');f.dispose();
}
{
 const f=fixture();f.pending('ticket_a');f.close();f.cfg.SurvivalPayments.RefreshCatalog(true);f.reply({ok:false,error:'match_session_missing'});const before=f.requests.filter(r=>r.action==='status').length;f.advance(20000);assert.equal(f.requests.filter(r=>r.action==='status').length,before,'session loss discards pending account-scoped orders');f.dispose();
}
{
 const f=fixture();f.setWalletBusy(2);f.pending('ticket_a');f.close();f.advance(5000);f.reply(f.order('ticket_a','delivered'));f.advance(0);assert.deepEqual(f.wallet(),{attempts:1,accepted:0});f.advance(4100);assert.deepEqual(f.wallet(),{attempts:3,accepted:1},'busy wallet gets one accepted refresh when its in-flight read clears');f.dispose();const count=f.wallet().attempts;f.advance(120000);assert.equal(f.wallet().attempts,count);
}
{
 const f=fixture();f.setWalletBusy(10);f.pending('ticket_a');f.close();f.advance(5000);f.reply(f.order('ticket_a','delivered'));f.advance(0);assert.equal(f.wallet().attempts,1);f.cfg.SurvivalPayments.RefreshCatalog(true);f.reply({ok:false,error:'match_session_missing'});f.advance(20000);assert.equal(f.wallet().attempts,1,'session loss cancels queued wallet work');f.dispose();
}
for(const error of ['unauthorized','match_session_missing','test_account_required']){
 for(const action of ['status','catalog','cancel','create']){
  const f=fixture();f.pending('ticket_a');f.close();
  if(action==='status')f.env.PaymentRefresh();else if(action==='catalog')f.cfg.SurvivalPayments.RefreshCatalog(true);else if(action==='cancel')f.env.PaymentCancel();else{f.cfg.SurvivalPayments.Checkout('ticket_b');f.env.PaymentBuy();f.close();}
  assert.equal(f.requests.at(-1).action,action);f.reply({ok:false,error});assert.equal(f.cfg.SurvivalPayments.GetCatalog().products.length,0,error+' must clear account data on '+action);const reads=f.requests.filter(r=>r.action==='status').length;f.advance(20000);assert.equal(f.requests.filter(r=>r.action==='status').length,reads,error+' must stop old status polling on '+action);f.dispose();
 }
 const f=fixture();f.setWalletBusy(10);f.pending('ticket_a');f.pending('ticket_b');f.close();f.advance(5000);f.reply(f.order('ticket_a','delivered'));f.advance(0);assert.equal(f.wallet().attempts,1);f.env.PaymentRefresh();f.reply({ok:false,error});f.advance(120000);assert.equal(f.wallet().attempts,1,error+' status must cancel queued wallet work');f.dispose();
}
{
 const f=fixture();f.pending('ticket_a');f.close();f.advance(5000);f.reply({ok:false,error:'profile_not_ready'});const count=f.requests.length;f.advance(5000);assert.equal(f.requests.length,count+1);assert.equal(f.requests.at(-1).action,'status');assert.equal(f.requests.at(-1).sku,'ticket_a','temporary profile loading must retain a known payment');f.dispose();
}
console.log('PAYMENT_CLOSED_REFRESH_PASS: closed known orders, fair multiple SKUs/catalogue, authoritative ownership, stale responses, timeout, terminal stop, all-action identity scope, temporary-profile retry, wallet refresh/dedupe/busy/reset, Dispose, no background create');
