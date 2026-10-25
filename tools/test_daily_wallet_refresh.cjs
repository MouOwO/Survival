"use strict";
// Real daily + wallet + storefront controllers, isolated Panorama contexts and
// synthetic transport only. No native game, network, purchase or real funds.
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const {createHarness}=require('./tests/fixtures/menus_v10_harness.cjs');
const sourceRoot=path.resolve('panorama/src/scripts/custom_game'),results=[];
const walletPrefix=fs.readFileSync('tools/test_commerce_wallet.cjs','utf8').split('catalog();assert.equal')[0];
assert(walletPrefix.includes('function respond(data)'), 'Reviewed existing wallet harness boundary exists');

function walletFixture(){
    const context={require:require('node:module').createRequire(path.resolve('tools/test_commerce_wallet.cjs')),console};
    const additions=String.raw`
        let now=0;timers.length=0;
        $.Schedule=(delay,fn)=>{const task={at:now+delay,fn};timers.push(task);return task;};
        function advance(seconds){const end=now+seconds;let guard=0;for(;;){timers.sort((a,b)=>a.at-b.at);if(!timers.length||timers[0].at>end)break;const task=timers.shift();now=task.at;task.fn();assert(++guard<1000,'No runaway maintenance loop');}now=end;}
        function catalogResult(balance){respond({ok:1,part:'begin',count:1,balances:{u_coin:0,shop_points:balance,shop_gold:0},categories:[]});respond({ok:1,part:'product',index:1,product});respond({ok:1,part:'end'});}
        // Use the actual distributed disabled-cash branch and storefront Open.
        vm.runInContext(fs.readFileSync('panorama/src/scripts/custom_game/payment_test.js','utf8'),env);
        vm.runInContext(fs.readFileSync('panorama/src/scripts/custom_game/common/commerce_components.js','utf8'),env);
        vm.runInContext(fs.readFileSync('panorama/src/scripts/custom_game/commerce_remaining_5d5c1152eb.js','utf8'),env);
        globalThis.fixture={cfg,requests,handlers,panels,advance,catalogResult,respond,
            points:()=>cfg.SurvivalCommerceWallet.GetCatalog().balances.shop_points};
    `;
    vm.runInNewContext(walletPrefix+additions,context,{filename:'daily_wallet_real_controller_fixture'});
    const w=context.fixture;
    w.cfg.SurvivalCommerceView.Open();w.catalogResult(7);w.cfg.SurvivalCommerceView.Close();
    return w;
}

function dailyFixture(w,{count=0,claimed=false,missingWallet=false}={}){
    const h=createHarness();
    // Models the two native HUD contexts sharing the real wallet controller.
    // Its methods and transport are not replaced with a preview stub.
    h.cfg.SurvivalCommerceWallet=missingWallet?undefined:w.cfg.SurvivalCommerceWallet;
    for(const source of ['archive_theme_tokens.js','archive_parchment_data.js','archive_handoff_180de7e38b.js',
        'archive_v10_semantics.js','common/archive_tooltip.js','daily_gw2_data.js','daily_remaining_5d5c1152eb.js'])h.load(source);
    h.cfg.SurvivalDaily.Open(false);
    let sequence=1;
    const snapshot={ok:true,sequence,today:25004,period_id:'0',count,ordinary_status:claimed?'claimed':'claimable',
        pending:0,has_pass:0,purchase_enabled:0,missed:[],specials:[],premium:{status:'unconfigured'},
        calendar_current_day:1,calendar_start_count:0,
        calendar28:Array.from({length:28},(_,i)=>({day:i+1,is_today:i===0?1:0,
            status:i===0?(claimed?'claimed':'claimable'):'not_open',
            rewards:[{id:'daily_growth_gem',name:'成长宝石',count:3,description:'合成测试奖励'}]}))};
    h.emit('survival_daily_snapshot',snapshot);
    return {h,snapshot,claim(){h.click(h.nodes.DailyClaim);},send(changes){
        h.emit('survival_daily_snapshot',{...snapshot,sequence:++sequence,...changes});
    },saved(changes={}){this.send({count:count+1,ordinary_status:'claimed',
        claim_result:{target_day:25004,ok:true,pending:false},...changes});}};
}

function run(name,fn){try{fn();results.push({name,ok:true});}catch(error){results.push({name,ok:false,error:String(error.stack||error)});}}
function lastRequest(w){return w.requests.at(-1);}

run('idle authoritative daily success invalidates real wallet once',()=>{
    const w=walletFixture(),d=dailyFixture(w);d.claim();const before=w.requests.length;
    d.saved();assert.equal(d.h.cfg.SurvivalDaily.Inspect().count,1);
    w.advance(1.2);assert.equal(w.requests.length,before+1,'Saved daily reward must request an authoritative wallet catalog');
    assert.equal(lastRequest(w).action,'catalog');w.catalogResult(57);assert.equal(w.points(),57);
    const settled=w.requests.length;d.saved();d.send({count:1,ordinary_status:'claimed'});w.advance(180);
    assert.equal(w.requests.length,settled,'Duplicate ACK and routine daily polls do not loop catalog refreshes');
    assert(!w.requests.some(r=>r.action==='purchase'));
});

run('daily success during catalog flight rejects old zero and coalesces fresh response',()=>{
    const w=walletFixture(),d=dailyFixture(w);w.cfg.SurvivalCommerceView.Open();
    const old=lastRequest(w),before=w.requests.length;d.claim();d.saved();w.advance(1.2);
    assert.equal(w.requests.length,before,'No concurrent catalog while the prior one is in flight');
    assert.equal(lastRequest(w),old);w.catalogResult(0);
    assert.equal(w.points(),7,'Pre-reward catalog cannot overwrite the last authoritative wallet');
    w.advance(1.2);assert.equal(w.requests.length,before+1);w.catalogResult(57);assert.equal(w.points(),57);
    const settled=w.requests.length;w.advance(180);assert.equal(w.requests.length,settled);
});

run('real storefront reopen during flight keeps false busy contract and queues one follow-up',()=>{
    const w=walletFixture();w.cfg.SurvivalCommerceView.Open();const before=w.requests.length;
    for(let i=0;i<12;i++){w.cfg.SurvivalCommerceView.Close();w.cfg.SurvivalCommerceView.Open();}
    assert.equal(w.requests.length,before);assert.equal(w.cfg.SurvivalCommerceWallet.Refresh(),false);
    w.catalogResult(0);assert.equal(w.points(),7,'Busy open cannot accept its superseded snapshot');
    w.advance(1.2);assert.equal(w.requests.length,before+1);w.catalogResult(57);assert.equal(w.points(),57);
    const settled=w.requests.length;w.advance(180);assert.equal(w.requests.length,settled);
});

run('pending reward and explicit failure do not request or spend',()=>{
    const w=walletFixture(),d=dailyFixture(w);d.claim();const before=w.requests.length;
    d.saved({pending:1,claim_result:{target_day:25004,ok:true,pending:true}});w.advance(4);
    assert.equal(w.requests.length,before);
    d.saved({claim_result:{target_day:25004,ok:0,error:'保存失败'}});w.advance(4);
    assert.equal(w.requests.length,before);assert.equal(w.points(),7);
});

run('final pending-to-saved transition refreshes even if count already projected',()=>{
    const w=walletFixture(),d=dailyFixture(w);d.claim();const before=w.requests.length;
    d.saved({pending:1,claim_result:{target_day:25004,ok:true,pending:true}});
    d.saved();w.advance(1.2);assert.equal(w.requests.length,before+1);w.catalogResult(57);assert.equal(w.points(),57);
});

run('closed daily window still invalidates on confirmed saved reward',()=>{
    const w=walletFixture(),d=dailyFixture(w);d.claim();d.h.cfg.SurvivalDaily.Close();const before=w.requests.length;
    d.saved();w.advance(1.2);assert.equal(w.requests.length,before+1);w.catalogResult(57);assert.equal(w.points(),57);
    assert.equal(d.h.cfg.SurvivalDaily.Inspect().open,false);
});

run('saved progress confirms a lost success ACK without duplicate invalidation',()=>{
    const w=walletFixture(),d=dailyFixture(w);d.claim();const before=w.requests.length;
    d.saved({claim_result:undefined});w.advance(1.2);assert.equal(w.requests.length,before+1);w.catalogResult(57);
    d.saved({claim_result:undefined});w.advance(20);assert.equal(w.requests.length,before+1);
});

run('initial already-claimed data is not a new reward receipt',()=>{
    const w=walletFixture(),d=dailyFixture(w,{count:1,claimed:true});const before=w.requests.length;
    d.send({count:1,ordinary_status:'claimed'});w.advance(20);assert.equal(w.requests.length,before);
});

run('older daily sequence cannot invalidate or overwrite current confirmation',()=>{
    const w=walletFixture(),d=dailyFixture(w);const before=w.requests.length;
    d.claim();d.send({sequence:1,count:1,ordinary_status:'claimed',claim_result:{target_day:25004,ok:true}});
    w.advance(5);assert.equal(w.requests.length,before);assert(d.h.cfg.SurvivalDaily.Inspect().waiting);
});

run('missing wallet controller is safe and does not claim again',()=>{
    const w=walletFixture(),d=dailyFixture(w,{missingWallet:true});d.claim();
    assert.doesNotThrow(()=>d.saved());assert.equal(d.h.cfg.SurvivalDaily.Inspect().count,1);
    assert.equal(d.h.sent.filter(r=>r.name==='survival_daily_claim').length,1);
});

run('disposed wallet ignores deferred daily invalidation safely',()=>{
    const w=walletFixture(),d=dailyFixture(w);d.claim();w.cfg.SurvivalCommerceWallet.Dispose();const before=w.requests.length;
    assert.doesNotThrow(()=>d.saved());w.advance(180);assert.equal(w.requests.length,before);
});

run('transient fresh-catalog failure retries within the existing bound',()=>{
    const w=walletFixture(),d=dailyFixture(w);d.claim();const before=w.requests.length;d.saved();w.advance(1.2);
    assert.equal(w.requests.length,before+1);w.respond({ok:0,terminal:0,error:'commerce_busy'});
    w.advance(1.2);assert.equal(w.requests.length,before+2);w.catalogResult(57);assert.equal(w.points(),57);
    const settled=w.requests.length;w.advance(180);assert.equal(w.requests.length,settled);
});

const report={schema:1,real_controllers:['daily_remaining_5d5c1152eb.js','commerce_wallet.js','commerce_remaining_5d5c1152eb.js','payment_test.js disabled cash branch'],
    sources:Object.fromEntries(['daily_remaining_5d5c1152eb.js','commerce_wallet.js'].map(name=>[name,require('node:crypto').createHash('sha256').update(fs.readFileSync(path.join(sourceRoot,name))).digest('hex')])),
    game_operated:false,network:false,real_wallet_or_funds_changed:false,synthetic_catalog_only:true,
    passed:results.filter(r=>r.ok).length,failed:results.filter(r=>!r.ok).length,results};
console.log(JSON.stringify(report,null,2));
if(report.failed)process.exitCode=1;
