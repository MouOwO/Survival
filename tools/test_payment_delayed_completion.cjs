"use strict";
const assert=require('node:assert/strict'),fs=require('node:fs');
const {fixture}=require('./test_payment_closed_refresh.cjs');
const source=process.argv[2]?fs.readFileSync(process.argv[2],'utf8'):undefined;

// A verified receipt may wait 30s for HTTP and 35s for profile application.
// Closing the UI during this interval must not discard its sole stable ID.
for(const delay of [34000,66000]){
 const f=fixture(source);f.cfg.SurvivalPayments.Checkout('ticket_a');f.env.PaymentBuy();
 const create=f.requests.at(-1);assert.equal(create.action,'create');f.close();f.advance(delay);
 assert.equal(f.cfg.SurvivalPayments.Inspect().pending,'create','order waits for both server phases');
 assert.equal(f.requests.filter(r=>r.action==='create').length,1,'slow response never creates a second order');
 f.reply(f.order('ticket_a','delivered'),create);f.advance(0);
 assert.equal(f.wallet().accepted,1,'final receipt refreshes the authoritative wallet');
 assert.equal(f.cfg.SurvivalPayments.Inspect().opened,false,'slow create completion does not reopen a closed window');
 f.products[0].owned=9;f.advance(1100);assert.equal(f.requests.at(-1).action,'catalog');f.reply(f.catalog());
 assert.equal(f.cfg.SurvivalPayments.GetCatalog().products[0].owned,9,'following read updates ownership');
 f.reply(f.order('ticket_a','delivered'),create);f.advance(0);assert.equal(f.wallet().accepted,1,'duplicate reply does not refresh twice');
 f.dispose();
}

{
 const f=fixture(source);f.cfg.SurvivalPayments.Checkout('ticket_a');f.env.PaymentBuy();
 const old=f.requests.at(-1);f.close();f.advance(70000);
 assert.equal(f.cfg.SurvivalPayments.Inspect().pending,'','lost response still has a finite deadline');
 assert.equal(f.requests.filter(r=>r.action==='create').length,1,'timeout never creates an order in the background');
 f.cfg.SurvivalPayments.RefreshCatalog(true);const fresh=f.requests.at(-1);assert.equal(fresh.action,'catalog');
 f.reply(f.order('ticket_a','delivered'),old);assert.equal(f.cfg.SurvivalPayments.Inspect().pending,'catalog','expired receipt cannot release a newer request');
 assert.equal(f.wallet().accepted,0);f.reply({ok:false,error:'match_session_missing'},fresh);
 f.reply(f.order('ticket_a','delivered'),old);f.advance(0);
 assert.equal(f.cfg.SurvivalPayments.GetCatalog().products.length,0,'identity loss keeps old account data retired');
 assert.equal(f.wallet().accepted,0);f.dispose();
}

{
 const f=fixture(source);f.cfg.SurvivalPayments.Checkout('ticket_a');f.env.PaymentBuy();
 const old=f.requests.at(-1);f.close();f.dispose();const count=f.requests.length;
 f.reply(f.order('ticket_a','delivered'),old);f.advance(120000);
 assert.equal(f.requests.length,count,'retired HUD never starts recovery work');assert.equal(f.wallet().accepted,0);
}
console.log('PAYMENT_DELAYED_COMPLETION_PASS: 34/66s final receipt, stable ID, closed window, current ownership, bounded timeout, stale/new request, identity loss and Dispose; real_gateway_calls=0');
