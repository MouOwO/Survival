const assert=require('node:assert/strict');
const test=require('node:test');
const wallet=require('../../panorama/src/scripts/custom_game/common/shop_wallet_model.js');
function row(id,wood,gold,extra={}) {
    return {entry_id:id,wood_cost:wood,gold_cost:gold,purchasable:1,disabled_reason:'',disabled_reason_code:'',
        wallet_purchasable:1,wallet_disabled_reason:'',wallet_disabled_reason_code:'',...extra};
}
test('both resource boundaries, shortage precedence and research charge timing remain exact',()=>{
    const model=wallet.Create();model.Update({wood:49,gold:99});
    const rows=[row('both',50,100),row('queued',5000,5000,{resource_check_on_cast:1})];
    model.Rebuild(rows);assert.equal(rows[0].disabled_reason_code,'insufficient_wood');
    assert.equal(rows[1].purchasable,1);
    model.Update({wood:50,gold:99});assert.equal(rows[0].disabled_reason_code,'insufficient_gold');
    assert.deepEqual(model.Update({wood:50,gold:100}).entries.map(r=>r.entry_id),['both']);
    assert.equal(rows[0].purchasable,1);
    model.Update({wood:49,gold:100});assert.equal(rows[0].purchasable,0);
    assert.equal(rows[0].disabled_reason_code,'insufficient_wood');
    assert.equal(model.Update({wood:undefined,gold:0}).known,false);
    assert.equal(rows[1].purchasable,1);
});
test('stock, limits and permission rejections remain locked; real price/eligibility changes rebuild indexes',()=>{
    const model=wallet.Create();model.Update({wood:0,gold:0});
    const blocked=row('stock',2,3,{wallet_purchasable:0,wallet_disabled_reason:'库存补充中',wallet_disabled_reason_code:'shop_stock_empty'});
    const permitted=row('price',10,10);model.Rebuild([blocked,permitted]);
    model.Update({wood:100,gold:100});assert.equal(blocked.purchasable,0);assert.equal(blocked.disabled_reason_code,'shop_stock_empty');
    assert.equal(permitted.purchasable,1);
    const changed=row('price',200,200);model.Rebuild([blocked,changed]);assert.equal(changed.purchasable,0);
    assert.equal(changed.disabled_reason_code,'insufficient_wood');
    model.Update({wood:200,gold:200});assert.equal(changed.purchasable,1);
    model.Rebuild([row('price',0,0,{wallet_purchasable:0,wallet_disabled_reason:'需要前置科技',wallet_disabled_reason_code:'prerequisite_not_met'})]);
    assert.equal(model.Update({wood:9007199254740991,gold:9007199254740991}).entries.length,0);
});
test('10000 entries and 1000 changing wallets visit no rows without a crossed threshold',()=>{
    const model=wallet.Create();model.Update({wood:0,gold:0});
    model.Rebuild(Array.from({length:10000},(_,i)=>row('e'+i,100000+i,100000+i)));
    const initial=model.Inspect();
    for(let i=1;i<=1000;i++)model.Update({wood:i,gold:i});
    const changing=model.Inspect();
    assert.equal(changing.entry_checks,initial.entry_checks);assert.equal(changing.candidates,initial.candidates);
    assert(changing.binary_steps-initial.binary_steps<=56000);
    for(let i=0;i<1000;i++)model.Update({wood:1000,gold:1000});
    const stable=model.Inspect();assert.equal(stable.binary_steps,changing.binary_steps);assert.equal(stable.entry_checks,changing.entry_checks);
    const changes=model.Update({wood:100002,gold:100002});assert.equal(changes.entries.length,3);
    assert.equal(model.Inspect().entry_checks-initial.entry_checks,3,'two currency indexes deduplicate the same three rows');
});
test('threshold updates match an independent full result for mixed funds and bounded prices',()=>{
    const model=wallet.Create(),rows=Array.from({length:71},(_,i)=>row('e'+i,i*7,(70-i)*11));
    model.Rebuild(rows);
    for(let tick=0;tick<400;tick++){
        const wood=(tick*37)%700,gold=(tick*59)%900;model.Update({wood,gold});
        for(const r of rows){assert.equal(r.purchasable,wood>=r.wood_cost&&gold>=r.gold_cost?1:0);
            assert.equal(r.disabled_reason_code,wood<r.wood_cost?'insufficient_wood':gold<r.gold_cost?'insufficient_gold':'');}
    }
});
function source(runtime){
    let serial=0,alive=true;const callbacks=new Map(),retired=[];
    return {Runtime:runtime,IsAlive:()=>alive,Subscribe(owner,sections,callback){assert.deepEqual(sections,['resources']);callbacks.set(++serial,callback);return serial;},
        Unsubscribe(id){retired.push(callbacks.get(id));callbacks.delete(id);},emit(resources){for(const cb of callbacks.values())cb({resources});},
        emitRetired(resources){for(const cb of retired)cb({resources});},kill(){alive=false;},size:()=>callbacks.size};
}
test('same-price eligibility deltas update K references without sorting or editing either index',()=>{
    const model=wallet.Create();model.Update({wood:1000,gold:1000});
    const rows=Array.from({length:10000},(_,i)=>row('e'+i,500,500));model.Rebuild(rows);const before=model.Inspect();
    const changed=row('e42',500,500,{wallet_purchasable:0,wallet_disabled_reason:'stock',wallet_disabled_reason_code:'shop_stock_empty'});
    model.Patch([changed],[]);const after=model.Inspect();
    assert.equal(after.builds,before.builds);assert.equal(after.index_edits,before.index_edits);
    assert.equal(after.entry_checks-before.entry_checks,1);assert.equal(changed.purchasable,0);
    changed.wallet_purchasable=1;changed.wallet_disabled_reason='';changed.wallet_disabled_reason_code='';
    model.Patch([changed],[]);assert.equal(model.Inspect().index_edits,before.index_edits);assert.equal(changed.purchasable,1);
    // In-place mutations cannot erase the cached old price key.
    changed.wood_cost=2000;model.Patch([changed],[]);assert.equal(changed.purchasable,0);
    model.Update({wood:2000,gold:1000});assert.equal(changed.purchasable,1);
    model.Patch([],['e42']);const checks=model.Inspect().entry_checks;model.Update({wood:1500,gold:1000});
    assert.equal(model.Inspect().entry_checks,checks,'removed price key is absent from the sorted index');
    assert.equal(model.Inspect().builds,before.builds);
});
test('normal request negotiation, close, replaced roots and stale callbacks do not publish old wallets',()=>{
    const runtime={ScopeIdentity:()=>({active:true,ready:true})},first=source(runtime),cfg={SurvivalCompactRuntime:runtime,SurvivalCompactHUDSource:first};
    let updates=0;const lane=wallet.Connect({config:cfg,owner:{},onChange(){updates++;}});
    assert.equal(lane.RequestFlag(),1);assert.equal(lane.RequestFlag(),1);assert.equal(first.size(),1);
    first.emit({wood:0,gold:0});const snapshot={hud_wallet:1,resources:{wood:10,gold:10},entries:[row('a',5,5)]};lane.Apply(snapshot,snapshot.entries);
    assert.equal(snapshot.entries[0].purchasable,0);first.emit({wood:5,gold:5});assert.equal(updates,1);assert.equal(snapshot.entries[0].purchasable,1);
    lane.Close();assert.equal(first.size(),0);first.emitRetired({wood:100,gold:100});assert.equal(updates,1);
    const second=source(runtime);cfg.SurvivalCompactHUDSource=second;assert.equal(lane.RequestFlag(),1);
    first.emitRetired({wood:0,gold:0});assert.equal(updates,1);second.emit({wood:0,gold:0});
    const next={hud_wallet:1,resources:{wood:0,gold:0},entries:[row('a',5,5)]};lane.Apply(next,next.entries);assert.equal(next.entries[0].purchasable,0);
    second.kill();second.emit({wood:100,gold:100});assert.equal(updates,1);
    assert.equal(lane.RequestFlag(),0);assert.equal(second.size(),0);
});
